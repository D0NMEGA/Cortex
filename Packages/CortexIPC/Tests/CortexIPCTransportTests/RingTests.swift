import CortexCoreC
@testable import CortexIPCTransport
import Darwin
import Synchronization

// RingTests — proves the Foundation-free fixed-stride shm ring (Plan 02-02 Task 1, IPC-01).
//
// Isolation: the production ring opens the GLOBAL shm name CORTEX_SHM_NAME. To keep tests
// independent (the kernel shm namespace is process-global, not per-test) every test here uses
// a UNIQUE per-run shm name via the test-only `ShmRing(name:create:)` overload and shm_unlink's
// it in teardown. Never run two tests against the same name concurrently.
//
// Coverage (the five behaviors mandated by the plan):
//   1. write/read round-trip via the busy-poll path (bytes identical, seq advanced)
//   2. slot arithmetic wraps (depth+2 frames overwrite slots 0 and 1; reader sees latest seq)
//   3. stride is the constant computed from CORTEX_CHANNEL_COUNT (== the value the ring reports)
//   4. a second mapping of the SAME name observes a write through the first (MAP_SHARED proof)
//   5. acquire/release ordering contract: write payload THEN release-store seq; read seq THEN payload
import Testing

/// A unique shm name per test (≤31 bytes incl. NUL, Darwin PSHMNAMLEN). Uses pid + a counter so
/// parallel test execution never collides, and stays well under the limit.
private let nameCounter = Atomic<UInt64>(0)
private func uniqueRingName() -> String {
  let n = nameCounter.wrappingAdd(1, ordering: .relaxed).newValue
  // "/cx" + up to ~10 digits of pid + "." + counter — comfortably ≤31 bytes.
  return "/cx\(getpid()).\(n)"
}

/// RAII-ish helper: open a fresh uniquely-named ring, guarantee it is unlinked when the test ends.
private func withFreshRing(_ body: (ShmRing, String) throws -> Void) throws {
  let name = uniqueRingName()
  // Defensive: clear any stale region from a crashed prior run before creating.
  _ = shm_unlink(name)
  let ring = try ShmRing(name: name, create: true)
  defer {
    // Drop the kernel object after the test (the mapping/fd are released by ring's deinit).
    _ = shm_unlink(name)
  }
  try body(ring, name)
}

@Suite("ShmRing")
struct RingTests {
  /// 1. Round-trip: write a known payload + bump seq, read it back via the busy-poll path.
  @Test("write/read round-trip via busy-poll: bytes identical, seq advanced")
  func roundTrip() throws {
    try withFreshRing { ring, _ in
      let payloadLen = ring.layout.slotStride
      var src = [UInt8](repeating: 0, count: payloadLen)
      for i in 0 ..< payloadLen {
        src[i] = UInt8(truncatingIfNeeded: i &* 7 &+ 13)
      }

      let seq = src.withUnsafeBytes { ring.write(slotBytes: $0) }
      #expect(seq == 1, "first write yields seq 1")

      var dst = [UInt8](repeating: 0, count: payloadLen)
      let seen = dst.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: 0) }
      #expect(seen == 1, "consumer observes seq 1")
      #expect(dst == src, "payload round-trips byte-for-byte")

      // No new frame -> pollLatest returns nil for the already-seen seq.
      let none = dst.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: 1) }
      #expect(none == nil, "no new frame after lastSeen == producerSeq")
    }
  }

  /// 2. Wrap-around: writing depth+2 frames overwrites slots 0 and 1; reader sees latest seq.
  @Test("slot arithmetic wraps: depth+2 frames reuse slots 0 and 1, latest seq visible")
  func wrapAround() throws {
    try withFreshRing { ring, _ in
      let depth = ring.layout.depth
      let stride = ring.layout.slotStride
      var frame = [UInt8](repeating: 0, count: stride)

      // Write depth+2 frames; tag each frame's first byte with its seq (mod 256).
      var lastSeq: UInt64 = 0
      for s in 1 ... (depth + 2) {
        for i in 0 ..< stride {
          frame[i] = UInt8(truncatingIfNeeded: s &+ i)
        }
        lastSeq = frame.withUnsafeBytes { ring.write(slotBytes: $0) }
      }
      #expect(lastSeq == UInt64(depth + 2), "producer seq advanced to depth+2")

      // The latest frame (seq depth+2) lives in slot (depth+2) % depth == 2.
      #expect(ring.slotIndex(forSeq: lastSeq) == 2, "seq depth+2 maps to slot index 2")
      // seq 1 and seq depth+1 share slot index 1 (both ≡ 1 mod depth) -> seq 1 was overwritten.
      #expect(ring.slotIndex(forSeq: 1) == ring.slotIndex(forSeq: UInt64(depth + 1)),
              "seq 1 and seq depth+1 collide on the same slot (overwrite proof)")

      var dst = [UInt8](repeating: 0, count: stride)
      let seen = dst.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: 0) }
      #expect(seen == lastSeq, "consumer sees the latest seq after wrap")
      #expect(dst[0] == UInt8(truncatingIfNeeded: Int(lastSeq)),
              "latest slot holds the latest frame's tag, not a stale one")
    }
  }

  /// 3. Stride is the constant derived from CORTEX_CHANNEL_COUNT — assert == the computed value.
  @Test("stride is the constant computed from CORTEX_CHANNEL_COUNT")
  func constantStride() throws {
    try withFreshRing { ring, _ in
      // Recompute independently: roundUp16(perSlotSeq(8) + CHANNEL_COUNT*2 + FlatBuffers framing
      // headroom + GCM_TAG(16)). Plan 02-04 Rule-1 fix: the slot reserves the ENCRYPTED FlatBuffers
      // frame, not the bare f16 payload, so the framing headroom is part of the stride.
      let raw = 8 + Int(CORTEX_CHANNEL_COUNT) * 2 + ShmRingLayout.flatBuffersFramingHeadroom + 16
      let expected = (raw + 15) & ~15
      #expect(ring.layout.slotStride == expected,
              "stride == roundUp16(8 + CHANNEL_COUNT*2 + framing + 16)")
      #expect(ring.layout.slotStride % 16 == 0, "stride is 16-byte aligned")
      #expect(ring.layout.depth > 0 && (ring.layout.depth & (ring.layout.depth - 1)) == 0,
              "depth is a power of two")
      #expect(ring.layout.headerBytes % 64 == 0, "header is cache-line aligned")
      #expect(ring.layout.ringBytes == ring.layout.headerBytes + ring.layout.slotStride * ring.layout.depth)
    }
  }

  /// 4. Two mappings of the SAME name: a write through mapping A is visible through mapping B
  ///    (intra-process MAP_SHARED proof; full cross-process is the Plan 02-04 harness).
  @Test("MAP_SHARED visibility across two mappings of the same name")
  func twoMappingsShare() throws {
    let name = uniqueRingName()
    _ = shm_unlink(name)
    let producer = try ShmRing(name: name, create: true)
    // Consumer maps the SAME existing region (create: false) — like the FD-adopting consumer.
    let consumer = try ShmRing(name: name, create: false)
    defer { _ = shm_unlink(name) }

    let stride = producer.layout.slotStride
    var src = [UInt8](repeating: 0xAB, count: stride)
    src[0] = 0x5A
    src[stride - 1] = 0xC3
    let seq = src.withUnsafeBytes { producer.write(slotBytes: $0) }

    var dst = [UInt8](repeating: 0, count: stride)
    let seen = dst.withUnsafeMutableBytes { consumer.pollLatest(into: $0, lastSeen: 0) }
    #expect(seen == seq, "second mapping observes the producer's seq")
    #expect(dst == src, "second mapping reads the producer's payload (MAP_SHARED)")
  }

  /// 5. Ordering contract: producer writes the slot THEN release-stores seq; consumer
  ///    acquire-loads seq THEN reads the slot. A consumer that has seen seq S must therefore
  ///    observe the full slot for S (no torn read). We assert the contract structurally: after
  ///    pollLatest returns S, the payload for S is fully present, then exercise the ack-bounce.
  @Test("acquire/release ordering: observed seq implies a fully-written slot + ack-bounce")
  func orderingContract() throws {
    try withFreshRing { ring, _ in
      let stride = ring.layout.slotStride
      // Sentinel payload: every byte distinct-ish so a partial copy would be detectable.
      var src = [UInt8](repeating: 0, count: stride)
      for i in 0 ..< stride {
        src[i] = UInt8(truncatingIfNeeded: 0xF0 &- i)
      }

      // Producer path order is enforced inside ShmRing.write (payload memcpy, THEN
      // producerSeq.store(.releasing)). Consumer path order is enforced inside pollLatest
      // (producerSeq.load(.acquiring), THEN slot read). Here we prove the end-to-end invariant
      // the ordering guarantees: a returned seq comes with its complete payload.
      let seq = src.withUnsafeBytes { ring.write(slotBytes: $0) }
      var dst = [UInt8](repeating: 0, count: stride)
      let seen = dst.withUnsafeMutableBytes { ring.pollLatest(into: $0, lastSeen: 0) }
      #expect(seen == seq)
      #expect(dst == src, "the whole slot is visible once its seq is observed (no torn read)")

      // ack-bounce (D-02): consumer acks the seq it consumed; producer polls the ack.
      try ring.ack(seq: #require(seen, "pollLatest must have returned a seq to ack"))
      let ackSeen = ring.pollAck(lastSeen: 0)
      #expect(ackSeen == seq, "ack-bounce: producer observes the consumer's ack seq")
      #expect(ring.pollAck(lastSeen: seq) == nil, "no new ack after lastSeen == ackSeq")
    }
  }
}
