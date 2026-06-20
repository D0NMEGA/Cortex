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
//   • produce(frameCount:): for each frame, build a deterministic Float16 pattern, encode a
//     FlatBuffers Sample, AES-GCM-seal it with the seq-derived nonce (D-16), write ciphertext||tag
//     into the next ring slot (release-store), ring the doorbell, then busy-poll the ack-bounce
//     (D-02) until the consumer acks that seq (bounded — T-02-04-05).
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

  /// Generate the secret (D-14), store it single-process in the Keychain (SC#3), derive subkeys, open
  /// the ring (create), and build the doorbell. `keychainBackend` defaults to production
  /// (.dataProtection); the harness test injects `.legacyFile` so it runs on the unentitled host
  /// (mirrors 02-03's KeychainTests seam — the data-protection round-trip needs Phase-8 enrollment).
  public init(ringName: String = CORTEX_SHM_NAME,
              keychainBackend: SessionKeychain.Backend = .dataProtection) throws {
    let secret = SessionKeys.generateSecret()
    self.secret = secret
    self.keys = SessionKeys(secret: secret)
    // SC#3: store the secret single-process. The CROSS-PROCESS delivery is over the channel (CF#1
    // fallback) — see handoff(to:). The store proves the IPC-06 Keychain round-trip half of SC#3.
    try SessionKeychain.store(secret: secret, backend: keychainBackend)
    self.ring = try ShmRing(name: ringName, create: true)
    self.doorbell = try Doorbell()
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
      let pattern = patternF16(forSeq: seq)
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
