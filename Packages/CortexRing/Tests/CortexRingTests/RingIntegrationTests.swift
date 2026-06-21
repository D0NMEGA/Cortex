// SC#4 (THREAD-06): a `cbindgen`-generated header lets Swift consume the loom-verified Rust SPSC
// ring over a stable C ABI. These tests create the ring through the C ABI via the safe `CortexRing`
// RAII wrapper, produce N frames from the producer side, and pop + verify them by VALUE and strict
// FIFO ORDER on the consumer side — the round-trip-fidelity proof that Swift reads frames produced
// on the C/Rust side (the consumer half of the producer→ring→consumer topology, RESEARCH §4).
//
// Correctness ONLY — no timing/latency assertion here (D-18 split: the M4 SC#1 glass-to-glass
// number is hardware Instruments evidence, not a unit-test claim).
//
// NEGATIVE CONTROL (SC#4 structural): the cbindgen header drift gate (Plan-01 CI step
// `cargo build` + `git diff --exit-code Packages/CortexRing/rust/include/cortex_ring.h`) is this
// test's negative control. If the Rust `extern "C"` ABI / `#[repr(C)] CortexFrame` layout changes
// without regenerating the committed header, the drift gate FAILS — so this value+order round-trip
// can never silently pass against a stale/divergent ABI (D-R6 / D-13). The test below asserts the
// behavior; the drift gate guarantees the behavior is measured against the real, current ABI.
import CortexRing
import Testing

// MARK: - SC#4 round-trip (value + strict FIFO order)

@Test
func `ring round-trips 1000 frames produced C/Rust-side in strict FIFO order with full fidelity`() {
  // capacity 256 (power of two) — smaller than N=1000 on purpose, so the bounded ring forces
  // interleaved push/pop (drain-when-full) and every frame genuinely traverses the C/Rust ring.
  guard let ring = CortexRing(capacity: 256) else {
    Issue.record("cortex_spsc_create(256) returned null for a valid power-of-two capacity")
    return
  }

  let frameCount = 1000
  var nextToPush = 0
  var collected: [CortexFrame] = []
  collected.reserveCapacity(frameCount)

  // Produce N frames with a known (seq, ts_ns, channel_data) pattern; push until full, then drain
  // via pop into `collected`, until all N have been pushed AND drained. This is the producer→ring→
  // consumer round-trip with a bounded ring (single producer + single consumer, SPSC contract).
  while collected.count < frameCount {
    while nextToPush < frameCount {
      let frame = CortexFrame.cortexTestFrame(seq: UInt64(nextToPush))
      if ring.push(frame) {
        nextToPush += 1
      } else {
        break // ring full — drain below
      }
    }
    // Drain everything currently buffered.
    while let popped = ring.pop() {
      collected.append(popped)
    }
  }

  // VALUE + ORDER (SC#4): exactly N frames, strict FIFO seq 0..<N, and each frame's ts_ns +
  // channel_data match the produced pattern bit-for-bit.
  #expect(collected.count == frameCount)
  #expect(collected.map(\.seq) == Array(0 ..< UInt64(frameCount))) // strict FIFO order

  for (index, frame) in collected.enumerated() {
    let expected = CortexFrame.cortexTestFrame(seq: UInt64(index))
    #expect(frame.seq == expected.seq)
    #expect(frame.ts_ns == expected.ts_ns) // ts_ns round-trips
    #expect(channelDataEqual(frame, expected)) // channel_data bitwise (value)
  }
}

// MARK: - Capacity / null edges (T-03-04-01 / T-03-04-03 mitigations)

@Test
func `pop on a fresh empty ring returns nil`() {
  guard let ring = CortexRing(capacity: 8) else {
    Issue.record("cortex_spsc_create(8) returned null for a valid power-of-two capacity")
    return
  }
  #expect(ring.pop() == nil) // pop() zero-inits out and returns nil on empty — never reads uninit
}

@Test
func `push on a full ring returns false`() {
  guard let ring = CortexRing(capacity: 4) else {
    Issue.record("cortex_spsc_create(4) returned null for a valid power-of-two capacity")
    return
  }
  // The pow2 ring holds capacity-1 usable slots (one slot distinguishes full from empty); fill it.
  var pushed = 0
  while ring.push(CortexFrame.cortexTestFrame(seq: UInt64(pushed))) {
    pushed += 1
    if pushed > 64 { break } // safety: never spin forever if the contract regressed
  }
  #expect(pushed >= 1) // at least one slot was usable
  #expect(ring.push(CortexFrame.cortexTestFrame(seq: 999)) == false) // now full → false
}

@Test
func `non-power-of-two capacity makes init return nil`() {
  // create rejects a non-power-of-two capacity by returning null (T-03-02-04); the wrapper's
  // init? surfaces that as nil (T-03-04-01: no destroy-of-null, no handle constructed).
  #expect(CortexRing(capacity: 3) == nil)
  #expect(CortexRing(capacity: 0) == nil) // zero capacity likewise rejected → nil
}

@Test
func `repeated create-and-deinit cycles do not crash (RAII destroy exactly once)`() {
  // Exercises the deinit → cortex_spsc_destroy RAII path many times. A double-free or
  // destroy-of-null would crash the test process here (T-03-04-01).
  for seed in 0 ..< 200 {
    let ring = CortexRing(capacity: 8)
    #expect(ring != nil)
    _ = ring?.push(CortexFrame.cortexTestFrame(seq: UInt64(seed)))
    _ = ring?.pop()
    // `ring` drops at the end of each iteration → deinit → destroy exactly once.
  }
}

// MARK: - test-only CortexFrame helpers (no layout redefinition — operate on the C type directly)

extension CortexFrame {
  /// Builds a `CortexFrame` with a deterministic, verifiable pattern keyed off `seq`:
  /// `ts_ns = seq * 2 + 1` (monotonically increasing, distinct from seq) and every channel lane
  /// set to `seq & 0xFFFF`. Uses the C `CortexFrame` type directly — NO hand-written Swift mirror
  /// of the repr(C) layout (D-R6); channel_data is treated as opaque u16 bits (D-10), never
  /// converted to/from Float16.
  static func cortexTestFrame(seq: UInt64) -> CortexFrame {
    var frame = CortexFrame() // memberwise zero-init from the imported C struct
    frame.ts_ns = seq &* 2 &+ 1
    frame.seq = seq
    let lane = UInt16(truncatingIfNeeded: seq)
    // channel_data is imported as a 96-element homogeneous tuple; fill it via raw bytes so we do
    // not depend on tuple indexing (and so the layout stays the single C-defined one).
    withUnsafeMutableBytes(of: &frame.channel_data) { raw in
      raw.bindMemory(to: UInt16.self).update(repeating: lane)
    }
    return frame
  }
}

/// Bitwise equality of the `channel_data` payloads of two frames (the C arrays import as tuples,
/// which are not `Equatable`/subscriptable by a runtime index — compare the raw bytes).
private func channelDataEqual(_ lhs: CortexFrame, _ rhs: CortexFrame) -> Bool {
  var lhsFrame = lhs
  var rhsFrame = rhs
  return withUnsafeBytes(of: &lhsFrame.channel_data) { lhsBytes in
    withUnsafeBytes(of: &rhsFrame.channel_data) { rhsBytes in
      lhsBytes.elementsEqual(rhsBytes)
    }
  }
}
