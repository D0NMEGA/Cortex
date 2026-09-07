// HarnessConsumer.swift — the consumer half of the D-07 two-process proof (Plan 02-04 Task 3,
// IPC-02/03/07 correctness; SC#2/SC#3 at runtime). It receives the shm fd over the CF#3 rendezvous +
// FDChannel, maps the ring, busy-polls the producer seq (the CF#2 measured path), opens each AES-GCM
// box with the seq-derived nonce, decodes the FlatBuffers Sample, verifies it equals what the
// producer sent, enforces a forward-only anti-replay check, and ack-bounces (D-02).
//
// KEY DELIVERY (CF#1 fallback, 02-SPIKES.md / 02-03-SUMMARY): the consumer does NOT load the secret
// from a shared Keychain access group (un-backable under the free team). It receives the 256-bit
// secret over the secure mach_msg channel via SessionKeyChannel.receive — the SECOND message on the
// rendezvous port is the key (sent BEFORE the fd by the producer), then the fd message.
//
// ANTI-REPLAY (T-02-04-04, ASVS V6.2): AES-GCM authenticates every frame (open() throws on tamper),
// and the consumer tracks `lastSeen` and only ACCEPTS strictly-increasing seq — a replayed/stale
// older seq (which would reproduce the same (key,nonce)) is IGNORED, never decoded/acked. Forward
// progress only.
//
// Foundation-allowed (CortexIPCSession, D-04/D-06). `nonisolated` so it runs off the main actor in
// the Foundation-free transport regime (the child consumer needs no MainActor/CFRunLoop).
import CortexCore
import CortexIPCTransport
import CryptoKit
import Foundation

/// The outcome of a consumer run — used by the in-process correctness test and reported by the child.
public nonisolated struct HarnessResult: Sendable, Equatable {
  /// How many frames the producer was expected to send (the loop's target).
  public let framesSent: Int
  /// How many frames decoded AND matched the expected (seq, pattern) — the decoded==sent count.
  public let framesVerified: Int
  /// Whether every verified frame was acked (the D-02 round trip closed for all).
  public let allAcked: Bool

  public init(framesSent: Int, framesVerified: Int, allAcked: Bool) {
    self.framesSent = framesSent
    self.framesVerified = framesVerified
    self.allAcked = allAcked
  }
}

/// Errors specific to consumer verification (decode/crypto errors propagate from their own layers).
public nonisolated enum HarnessConsumerError: Error, Equatable, Sendable {
  /// A decoded Sample's seq did not match the seq the slot was published under (frame/seq mismatch).
  case seqMismatch(expected: UInt64, decoded: UInt64)
  /// A decoded channel value did not match the deterministic producer pattern (corruption).
  case patternMismatch(seq: UInt64)
  /// The producer never advanced the ring within the spin budget (a dead/stuck producer).
  case producerStalled(lastSeen: UInt64)
  /// The slot's length prefix was zero or implied a ciphertext+tag larger than the slot (corruption).
  case malformedSlot(seq: UInt64, ciphertextLength: Int)
}

public nonisolated enum HarnessConsumer {
  /// The deterministic per-channel value the producer wrote for `seq` (mirror of Producer.patternF16):
  /// every channel == Float16(seq & 0xFF). The consumer recomputes it to verify decoded == sent.
  public static func expectedValue(forSeq seq: UInt64) -> Float16 {
    Float16(UInt8(truncatingIfNeeded: seq))
  }

  /// The AES-GCM tag length appended after the ciphertext in each slot.
  public static let tagLength = 16

  /// The slot PAYLOAD wire layout (producer ↔ consumer agreement, both in CortexIPCSession scope):
  ///   [4-byte little-endian ciphertext length] [ciphertext (variable)] [16-byte GCM tag]
  /// A FlatBuffers `Sample` is VARIABLE-length (FlatBuffers omits default/zero scalar fields, so a
  /// frame with zero ts_ns/seq encodes shorter than one with non-zero values), so the ciphertext
  /// length MUST be carried explicitly — a fixed-length split is incorrect. AES-GCM preserves length
  /// (ciphertext length == plaintext length). The whole `4 + ct + 16` fits the slot stride (which now
  /// reserves the FlatBuffers framing headroom — Plan 02-04 Rule-1 fix in ShmRing.swift).
  public static let lengthPrefixBytes = 4

  /// Pack a sealed frame into a slot payload: `[len LE][ct][tag]`. Used by the producer and the
  /// in-process test so both sides agree on the layout `consumeOne` parses.
  public static func packSlot(ciphertext: [UInt8], tag: [UInt8]) -> [UInt8] {
    var out = [UInt8]()
    out.reserveCapacity(lengthPrefixBytes + ciphertext.count + tag.count)
    let len = UInt32(ciphertext.count).littleEndian
    withUnsafeBytes(of: len) { out.append(contentsOf: $0) }
    out.append(contentsOf: ciphertext)
    out.append(contentsOf: tag)
    return out
  }

  /// Consume EXACTLY ONE frame from `ring` past `lastSeen`: busy-poll the producer seq (the CF#2
  /// measured path), enforce the forward-only anti-replay check (T-02-04-04), parse the slot payload
  /// (`[len][ct][tag]`), open the AES-GCM box (daemon→app, seq), decode the Sample, verify decoded ==
  /// sent (seq + deterministic channel pattern), and ack-bounce (D-02). Returns the accepted seq, or
  /// throws on stall/tamper/mismatch. Shared by both the in-process test (lock-step) and the spawned
  /// child loop. `scratch` is a caller-provided slotStride-sized buffer reused across calls (no
  /// per-frame allocation on the polling path).
  @discardableResult
  public static func consumeOne(ring: ShmRing,
                                keys: SessionKeys,
                                lastSeen: UInt64,
                                scratch: inout [UInt8],
                                spinBudget: Int = 50_000_000) throws -> UInt64
  {
    // Busy-poll until a STRICTLY increasing seq appears (forward-only anti-replay, T-02-04-04: an
    // older-or-equal seq would reproduce a used (key,nonce) and is never decoded/acked).
    var seq: UInt64 = 0
    var spun = 0
    while true {
      if let s = (scratch.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: lastSeen) }),
         s > lastSeen
      {
        seq = s
        break
      }
      spun += 1
      if spun >= spinBudget {
        throw HarnessConsumerError.producerStalled(lastSeen: lastSeen)
      }
    }

    // Parse the slot payload: [4-byte LE ciphertext length][ciphertext][16-byte tag].
    let ctLen = scratch.withUnsafeBytes { raw -> Int in
      Int(raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self).littleEndian)
    }
    let ctStart = Self.lengthPrefixBytes
    let ctEnd = ctStart + ctLen
    let tagEnd = ctEnd + Self.tagLength
    guard ctLen > 0, tagEnd <= scratch.count else {
      throw HarnessConsumerError.malformedSlot(seq: seq, ciphertextLength: ctLen)
    }
    let ct = Array(scratch[ctStart ..< ctEnd])
    let tag = Array(scratch[ctEnd ..< tagEnd])

    // SC#3: fail-closed AES-GCM open with the seq-derived nonce, then decode + verify decoded == sent.
    let plain = try SessionCrypto.open(ciphertext: ct, tag: tag, keys: keys,
                                       direction: .daemonToApp, seq: seq)
    let sample = try SampleCodec.decode(plain)
    guard sample.seq == seq else {
      throw HarnessConsumerError.seqMismatch(expected: seq, decoded: sample.seq)
    }
    let expected = Self.expectedValue(forSeq: seq)
    let ok = sample.withChannelF16 { f16 -> Bool in
      for v in f16 where v != expected {
        return false
      }
      return true
    }
    guard ok else { throw HarnessConsumerError.patternMismatch(seq: seq) }

    // D-02 ack-bounce: signal the producer this seq was consumed + verified.
    ring.ack(seq: seq)
    return seq
  }

  /// The reusable consumer loop (the spawned child path): verify `frameCount` frames in order via
  /// repeated `consumeOne`. The cross-process lock-step comes from the producer's own per-frame
  /// ack-wait (Producer.produce), so successive `pollLatest` calls observe each distinct seq.
  public static func consumeLoop(ring: ShmRing,
                                 keys: SessionKeys,
                                 frameCount: Int,
                                 spinBudgetPerFrame: Int = 50_000_000) throws -> HarnessResult
  {
    var scratch = [UInt8](repeating: 0, count: ring.layout.slotStride)
    var lastSeen: UInt64 = 0
    var verified = 0
    while verified < frameCount {
      let seq = try consumeOne(ring: ring, keys: keys, lastSeen: lastSeen,
                               scratch: &scratch, spinBudget: spinBudgetPerFrame)
      lastSeen = seq
      verified += 1
    }
    return HarnessResult(framesSent: frameCount, framesVerified: verified, allAcked: true)
  }

  /// The child entry point (posix_spawn'd with "consume"): acquire the rendezvous reply right, receive
  /// the key over the channel (CF#1 fallback), receive the shm fd, map the ring, run the consumer
  /// loop. Returns a HarnessResult the daemon turns into an exit status.
  public static func runChild(frameCount: Int) throws -> HarnessResult {
    let rcv = try Rendezvous.childAcquire()
    // CF#1 fallback: the FIRST message on the rendezvous port is the 256-bit secret (sent before fd).
    let secret = try SessionKeyChannel.receive(on: rcv)
    let keys = SessionKeys(secret: secret)
    // SC#2: the SECOND message carries the shm fd as a fileport in a mach_msg port descriptor — the
    // no-rights-transfer invariant (no BSD socket control-message FD path); geometry is validated.
    let (fd, geometry) = try FDChannel.receive(on: rcv)
    let ring = try ShmRing(adoptingFD: fd, layout: geometry)
    return try consumeLoop(ring: ring, keys: keys, frameCount: frameCount)
  }
}
