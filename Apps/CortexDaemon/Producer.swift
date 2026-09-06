// Producer.swift — the Phase-2 daemon producer (Plan 02-04 Task 2, IPC-02/03/05). Wires the
// Foundation-free transport (ShmRing + Doorbell + FDChannel, Plan 02-02) and the session crypto
// (SampleCodec + SessionCrypto + SessionKeychain, Plan 02-03) into the producer half of the D-07
// two-process proof harness.
//
// LIFECYCLE:
//   • init: generate a fresh 256-bit session secret (D-14), STORE it single-process in the
//     data-protection Keychain (SC#3, SessionKeychain.store), derive the per-direction subkeys, open
//     the shm ring (create), and create the doorbell.
//   • handoff(to:): deliver the secret to the consumer OVER THE CHANNEL (CF#1 fallback — a second
//     mach_msg sent BEFORE the fd message), then pass the shm fd via FDChannel (mach_msg + fileport,
//     SC#2 — the no-rights-transfer invariant, no BSD socket control-message FD path). The consumer
//     maps the same region from this fd.
//   • produce(frameCount:): for each frame, build one 20 ms bin of Float16 channel values, encode a
//     FlatBuffers Sample, AES-GCM-seal it with the seq-derived nonce (D-16), write ciphertext||tag
//     into the next ring slot (release-store), ring the doorbell, then busy-poll the ack-bounce
//     (D-02) until the consumer acks that seq (bounded — T-02-04-05).
//
// PHASE 10 (RD-08, D-05): the payload's ORIGIN is now injectable. When `CORTEX_REPLAY_EXPORT` names a
// D-06 replay export, `binF16` hands `produce` a REAL 20 ms bin from the recorded session instead of
// the Phase-2 test pattern. That is the ONLY change: the FlatBuffers frame, the AES-GCM sealing, the
// ring write, the doorbell and the ack-bounce are untouched, so Seam B measures the same transport
// carrying different bytes. There is deliberately NO option to bypass AES-GCM for the replay — a
// second crypto code path is how a fail-open appears (10-RESEARCH Security V6), and the real path
// stays sealed exactly like the synthetic one.
//
// SECURITY: the secret bytes are NEVER logged (T-02-04-06); only seq/counts are. This is Apps-target
// orchestration (Foundation allowed) — the policed hot-path code it calls stays Foundation-free.
import Foundation
import Darwin
import CryptoKit
import CortexCore
import CortexIPCTransport
import CortexIPCSession

/// Errors surfaced by the producer setup / round trip (Swift 6 typed throws upstream where possible;
/// this aggregates the few cross-layer failures that are not already typed).
public enum ProducerError: Error {
  /// The ack-bounce did not arrive within the per-frame budget (a dead/stuck consumer, T-02-04-05).
  case ackTimeout(seq: UInt64)
}

/// The Phase-2 producer. Holds the session keys, the shm ring (created), and the doorbell for the
/// lifetime of a harness run. NOT on the audio-callback hot path itself — it is the orchestration
/// that drives the Foundation-free ring/doorbell primitives.
public final class Producer {
  /// The per-direction AES-GCM subkeys derived from the session secret (D-15).
  private let keys: SessionKeys
  /// The session secret — delivered to the consumer over the channel (CF#1 fallback). Held privately;
  /// never logged.
  private let secret: SymmetricKey
  /// The created shm ring (producer owns the fd; `ring.fd` feeds FDChannel.send).
  private let ring: ShmRing
  /// The socketpair+kqueue doorbell (idle/arming wake; the frame path is the ring busy-poll).
  private let doorbell: Doorbell
  /// Deterministic per-frame Float16 pattern length (one value per channel).
  private let channelCount = cortexChannelCount
  /// The Phase-10 D-05 replay source: real 20 ms bins read from the gitignored export
  /// (`CORTEX_REPLAY_EXPORT`). Non-nil => `produce` emits REAL spike bins; nil => the existing
  /// deterministic `patternF16` runs, so a clean clone with no export behaves exactly as it did in
  /// Phase 2. IPC, crypto, ring and doorbell are UNCHANGED: only the payload's origin moves.
  private let replay: ReplayExport?

  /// Generate the secret (D-14), store it single-process in the Keychain (SC#3), derive subkeys, open
  /// the ring (create), and build the doorbell. `keychainBackend` defaults to production
  /// (.dataProtection); the harness test injects `.legacyFile` so it runs on the unentitled host
  /// (mirrors 02-03's KeychainTests seam — the data-protection round-trip needs Phase-8 enrollment).
  ///
  /// D-05, and the one behaviour worth stating loudly: if `CORTEX_REPLAY_EXPORT` is SET but the export
  /// cannot be loaded, this THROWS. It does NOT fall back to `patternF16`. A daemon that was asked for
  /// a real replay and silently emitted a synthetic pattern is the D-05 version of the Pattern-2 trap
  /// Plan 10-04 removed from the closed loop, and it would put a synthetic number under a real-data
  /// label. An UNSET variable is the clean-clone path and changes nothing.
  public init(ringName: String = CORTEX_SHM_NAME,
              keychainBackend: SessionKeychain.Backend = .dataProtection) throws {
    // Resolve the replay source FIRST, so a misconfigured export fails before any Keychain write or
    // shm region exists to clean up.
    if let sidecarURL = ReplayExport.sidecarURLFromEnvironment() {
      replay = try ReplayExport(sidecarURL: sidecarURL)
    } else {
      replay = nil
    }
    let secret = SessionKeys.generateSecret()
    self.secret = secret
    self.keys = SessionKeys(secret: secret)
    // SC#3: store the secret single-process. The CROSS-PROCESS delivery is over the channel (CF#1
    // fallback) — see handoff(to:). The store proves the IPC-06 Keychain round-trip half of SC#3.
    try SessionKeychain.store(secret: secret, backend: keychainBackend)
    self.ring = try ShmRing(name: ringName, create: true)
    self.doorbell = try Doorbell()
  }

  /// Whether this producer emits REAL exported bins (D-05) rather than the Phase-2 test pattern.
  /// Recorded by the Seam B smoke so a run's data source is a fact in the artifact, not an assumption.
  public var isReplayBacked: Bool { replay != nil }

  /// The session the replay is replaying, or nil when running the Phase-2 pattern.
  public var replaySessionId: String? { replay?.sidecar.sessionId }

  /// The same fact `isReplayBacked` / `replaySessionId` report, resolved WITHOUT constructing a
  /// producer: no Keychain write, no shm region, no doorbell. That matters because the daemon banner
  /// runs before `Harness.runParent`, which creates the real producer, and a second live `Producer`
  /// would contend for the same named shm ring and the same single-process Keychain entry.
  ///
  /// Throws on a set-but-unloadable `CORTEX_REPLAY_EXPORT` exactly as `init` does, so the banner can
  /// never announce a source the producer would then refuse.
  public static func configuredPayloadSourceDescription() throws -> String {
    guard let sidecarURL = ReplayExport.sidecarURLFromEnvironment() else {
      return "Phase-2 synthetic pattern (CORTEX_REPLAY_EXPORT unset)"
    }
    let export = try ReplayExport(sidecarURL: sidecarURL)
    return "replay export, real bins (D-05): session=\(export.sidecar.sessionId), "
      + "bins=\(export.binCount), channels=\(export.channelCount)"
  }

  /// The shm region fd (for the harness/consumer to know what is being shared). Read-only.
  public var shmFD: Int32 { ring.fd }

  /// The producer end of the doorbell (the consumer arms its kqueue on the consumer end). Exposed so
  /// a single-process harness can wire the consumer's doorbell wake; the two-process harness uses the
  /// ring busy-poll as the data path and the doorbell only as the idle wake.
  public var doorbellProducerFD: Int32 { doorbell.producerFD }

  /// Hand the consumer everything it needs to map + decrypt: FIRST the session secret over the
  /// channel (CF#1 fallback — a second mach_msg sent BEFORE the fd message, so the consumer has the
  /// key before any frame), THEN the shm fd + geometry via FDChannel (mach_msg + fileport, SC#2).
  /// `dest` is the rendezvous send right (from Rendezvous.parentAwaitReply).
  public func handoff(to dest: mach_port_t) throws {
    // CF#1 fallback: deliver the 256-bit secret over the secure channel (NOT a shared Keychain group).
    try SessionKeyChannel.send(secret: secret, to: dest)
    // SC#2: pass the shm region fd as a fileport in a mach_msg port descriptor — the no-rights-transfer
    // invariant (no BSD socket control-message FD path).
    try FDChannel.send(shmFD: ring.fd, geometry: ring.layout, to: dest)
  }

  /// Monotonic nanosecond timestamp for the frame ts_ns (D-12). Computed inline from Darwin's
  /// `mach_absolute_time()` (nonisolated) rather than CortexCore's `Time.machAbsoluteNanoseconds()`,
  /// which is MainActor-isolated and would force a hop — the producer runs off the main actor, mirroring
  /// the hot-path regime. Same mach_absolute_time → ns conversion as Time.swift.
  private func nowNanos() -> UInt64 {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    let raw = mach_absolute_time()
    return raw &* UInt64(info.numer) / UInt64(info.denom)
  }

  /// Build the deterministic test pattern for `seq`: each channel = Float16(seq & 0xFF) so the
  /// consumer can verify the decoded Sample matches what was sent (T-02-04 correctness, no RNG).
  public func patternF16(forSeq seq: UInt64) -> [Float16] {
    let v = Float16(UInt8(truncatingIfNeeded: seq))
    return [Float16](repeating: v, count: channelCount)
  }

  /// One 20 ms bin across 96 channels for `seq`, from the replay export when present, else the
  /// deterministic Phase-2 pattern. Exactly `channelCount` values either way, because
  /// `SampleCodec.encode` requires it (one IPC frame == one bin; the 32-bin decode window is assembled
  /// consumer-side by `RollingSpikeWindow` — 10-RESEARCH Pitfall 9).
  ///
  /// The seq→bin mapping is `seq % binCount`, so CONSECUTIVE sequence numbers carry CONSECUTIVE
  /// export bins and a consumer accumulating 32 of them holds 32 contiguous bins of the recorded
  /// session. Note the producer's first frame is seq 1 (`ring.loadProducerSeq() &+ 1`), so the replay
  /// starts at bin 1, not bin 0; the modulo is taken in `UInt64` so the `Int` conversion of a value
  /// already less than `binCount` can never trap.
  ///
  /// A read failure here is NOT survivable by falling back to `patternF16`: that is exactly how a
  /// synthetic number acquires a real-data label. The index is bounds-checked by construction, so an
  /// error means the mapped export changed underfoot, and the daemon stops rather than substituting.
  public func binF16(forSeq seq: UInt64) -> [Float16] {
    guard let replay else { return patternF16(forSeq: seq) }
    let bin = Int(seq % UInt64(replay.binCount))
    do {
      return try replay.window(endingAt: bin, length: 1)
    } catch {
      preconditionFailure(
        "replay bin \(bin) of \(replay.binCount) could not be read (\(error)); refusing to substitute "
          + "the synthetic pattern under a real-data label (D-05)"
      )
    }
  }

  /// Produce `frameCount` frames end-to-end with the D-02 ack-bounce round trip. For each frame:
  /// encode → seal (daemon→app, seq) → write slot (release-store) → ring doorbell → busy-poll the ack
  /// for that seq (bounded by `ackSpinBudget`). Returns the number of frames the consumer acked.
  /// Throws `ProducerError.ackTimeout` if the consumer stalls (T-02-04-05: never spin forever).
  @discardableResult
  public func produce(frameCount: Int, ackSpinBudget: Int = 50_000_000) throws -> Int {
    var lastAck: UInt64 = 0
    var acked = 0
    for _ in 0..<frameCount {
      let seq = ring.loadProducerSeq() &+ 1
      let tsNs = nowNanos()
      let pattern = binF16(forSeq: seq)
      let plain = try SampleCodec.encode(tsNs: tsNs, seq: seq, channels: pattern)
      let (ct, tag) = try SessionCrypto.seal(plain, keys: keys, direction: .daemonToApp, seq: seq)

      // Pack [len LE][ct][tag] into the slot (FlatBuffers frames are variable-length, so the
      // ciphertext length is carried explicitly; HarnessConsumer.consumeOne parses this layout).
      let slot = HarnessConsumer.packSlot(ciphertext: ct, tag: tag)
      let written = slot.withUnsafeBytes { ring.write(slotBytes: $0) }
      // Notify the consumer it can wake from idle (the data path is the ring; this is the doorbell, D-01).
      doorbell.ring(seq: written)

      // D-02 ack-bounce: busy-poll until the consumer acks `written` (bounded — never spin forever).
      var spun = 0
      while true {
        if let a = ring.pollAck(lastSeen: lastAck), a >= written {
          lastAck = a
          acked += 1
          break
        }
        spun += 1
        if spun >= ackSpinBudget {
          throw ProducerError.ackTimeout(seq: written)
        }
      }
    }
    return acked
  }

  deinit {
    // Clean up the single-process test key; ignore not-found. ShmRing/Doorbell close in their deinits.
    try? SessionKeychain.delete()
  }
}
