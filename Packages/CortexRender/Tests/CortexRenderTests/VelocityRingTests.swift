// VelocityRingTests — the in-process SPSC velocity ring (D-03) + the deterministic Lissajous
// synthetic drive (D-05). Written RED first (TDD), then implemented GREEN.
//
// The ring's FIFO ordering + bounded capacity + no-torn-read are unit-testable on a single thread
// (the memory-ordering discipline is what makes the cross-thread case safe; the single-thread tests
// pin the FIFO/bounded contract). The Lissajous determinism (same `t` ⇒ bit-identical velocity,
// no clock/RNG) is the property the 60s soak (SC#4) reproducibility rests on.

import Testing
import CortexRender

@Suite("VelocityRing")
struct VelocityRingTests {

  @Test("a fresh ring pops nil (empty)")
  func freshRingIsEmpty() {
    let ring = VelocityRing(capacity: 8)
    #expect(ring.pop() == nil)
  }

  @Test("push then pop returns the same frame (ts_ns/seq/vx/vy preserved)")
  func pushPopRoundTrip() {
    let ring = VelocityRing(capacity: 8)
    let v = CursorVelocity(ts_ns: 123, seq: 1, vx: 0.5, vy: -0.25)
    #expect(ring.push(v) == true)
    let out = ring.pop()
    #expect(out == v)                          // full value round-trip
    #expect(ring.pop() == nil)                 // drained
  }

  @Test("FIFO order — push v1,v2,v3 pops v1,v2,v3 in order")
  func fifoOrder() {
    let ring = VelocityRing(capacity: 8)
    let v1 = CursorVelocity(ts_ns: 1, seq: 1, vx: 0.1, vy: 0.0)
    let v2 = CursorVelocity(ts_ns: 2, seq: 2, vx: 0.2, vy: 0.0)
    let v3 = CursorVelocity(ts_ns: 3, seq: 3, vx: 0.3, vy: 0.0)
    #expect(ring.push(v1) == true)
    #expect(ring.push(v2) == true)
    #expect(ring.push(v3) == true)
    #expect(ring.pop() == v1)
    #expect(ring.pop() == v2)
    #expect(ring.pop() == v3)
    #expect(ring.pop() == nil)
  }

  @Test("push beyond capacity returns false and does not corrupt earlier frames (T-06-02-02)")
  func boundedNoCorruption() {
    // capacity 4 — a single-slot-reserved ring holds 3 live frames (mirror CortexRing's full rule);
    // the exact usable count is an impl detail, so assert via the observable contract: once push
    // starts returning false, every previously-accepted frame still pops back intact and in order.
    let ring = VelocityRing(capacity: 4)
    var accepted: [CursorVelocity] = []
    for i in 0..<16 {
      let v = CursorVelocity(ts_ns: UInt64(i), seq: UInt64(i), vx: Float16(Float(i)), vy: 0.0)
      if ring.push(v) { accepted.append(v) } else { break }
    }
    #expect(accepted.count >= 1)               // some frames fit
    #expect(accepted.count < 16)               // …but it is bounded (push eventually returns false)
    // Every accepted frame pops back, in FIFO order, uncorrupted (no torn write clobbered them).
    for expected in accepted {
      #expect(ring.pop() == expected)
    }
    #expect(ring.pop() == nil)
  }

  @Test("non-power-of-two / zero capacity is rejected by init (mirror CortexRing)")
  func rejectsBadCapacity() {
    #expect(VelocityRing(capacity: 0) == nil)
    #expect(VelocityRing(capacity: 3) == nil)   // not a power of two
    #expect(VelocityRing(capacity: 6) == nil)
    #expect(VelocityRing(capacity: 8) != nil)   // power of two OK
  }
}

@Suite("LissajousProducer")
struct LissajousProducerTests {

  @Test("velocity(at:) is deterministic — identical params give bit-identical output for the same t")
  func deterministicAcrossInstances() {
    let a = LissajousProducer(ampX: 0.8, ampY: 0.6, freqX: 0.7, freqY: 1.1, phase: 0.3)
    let b = LissajousProducer(ampX: 0.8, ampY: 0.6, freqX: 0.7, freqY: 1.1, phase: 0.3)
    for t in stride(from: 0.0, through: 5.0, by: 0.37) {
      let va = a.velocity(at: t)
      let vb = b.velocity(at: t)
      #expect(va.vx == vb.vx)                   // bit-identical (no clock, no RNG, no global state)
      #expect(va.vy == vb.vy)
    }
  }

  @Test("velocity(at:) varies smoothly — different t yields different velocity (non-constant drive)")
  func variesOverTime() {
    let p = LissajousProducer(ampX: 0.8, ampY: 0.6, freqX: 0.7, freqY: 1.1, phase: 0.0)
    let v0 = p.velocity(at: 0.0)
    let v1 = p.velocity(at: 1.3)
    // The drive must actually move the cursor — at least one component differs between two times.
    #expect(v0.vx != v1.vx || v0.vy != v1.vy)
  }

  @Test("a sampled-then-integrated Lissajous path stays within the [0,1] grid bounds")
  func integratedPathStaysOnGrid() {
    // D-05 intent: amplitudes chosen so the integrated path stays on-surface. Drive the real
    // integrator with the producer over a few seconds and confirm the position never leaves [0,1]
    // (the integrator clamps regardless, but a sane default producer should not be perpetually
    // saturated — assert it visits the interior, not just the bounds).
    let producer = LissajousProducer()                 // sensible defaults
    let integrator = CursorIntegrator()
    let dt = 1.0 / 120.0
    var sawInterior = false
    var t = 0.0
    for i in 0..<600 {                                  // 5 s at 120 Hz
      let v = producer.velocity(at: t)
      let pos = integrator.integrate(
        latest: CursorVelocity(ts_ns: UInt64(i), seq: UInt64(i), vx: v.vx, vy: v.vy),
        dt: dt
      )
      #expect(pos.x >= 0.0 && pos.x <= 1.0)
      #expect(pos.y >= 0.0 && pos.y <= 1.0)
      if pos.x > 0.05 && pos.x < 0.95 && pos.y > 0.05 && pos.y < 0.95 { sawInterior = true }
      t += dt
    }
    #expect(sawInterior)                                // not pinned to a corner — a real figure
  }
}
