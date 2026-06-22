// CursorIntegratorTests — the renderer-owned velocity→position integrator (D-04) and the
// CursorVelocity fp16 seam (D-03). These are pure-math / defined-I/O behaviors, so they are the
// TDD core of Plan 06-02: written RED first, then implemented GREEN.
//
// Velocity-scale contract (documented, load-bearing for the exact magnitude assertions below):
// `CursorVelocity.vx`/`vy` are velocities in GRID-UNITS PER SECOND. The integrator advances
// `position += velocity * dt` with NO additional scale factor (scale == 1.0), so a velocity of
// `1.0` grid-units/s over `dt = 0.1 s` moves the cursor by exactly `0.1` in grid-normalised space.
// This is the seam Phase 7's Kalman feeds unchanged (it also emits a velocity).

import Testing
import CortexRender

@Suite("CursorIntegrator")
struct CursorIntegratorTests {

  // Tolerance for Float16→Float round-trip + Float accumulation. fp16 has ~3 decimal digits of
  // precision; 1e-3 comfortably covers a single store + one multiply-add.
  private let eps: Float = 1e-3

  @Test("integrate moves position by exactly velocity * dt from the start point")
  func integrateMovesByVelocityTimesDt() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    // vx = 1.0 grid-units/s, dt = 0.1 s  ->  Δx = +0.1, y unchanged.
    let v = CursorVelocity(ts_ns: 1, seq: 1, vx: 1.0, vy: 0.0)
    let pos = integrator.integrate(latest: v, dt: 0.1)
    #expect(abs(pos.x - 0.6) < eps)          // moved right by velocity*dt
    #expect(abs(pos.y - 0.5) < eps)          // y held (vy == 0)
    #expect(pos.x > 0.5)                      // direction is positive
  }

  @Test("integrate clamps to the upper grid bound — cursor cannot leave [0,1] on the right/top")
  func integrateClampsUpper() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let fast = CursorVelocity(ts_ns: 1, seq: 1, vx: 1000.0, vy: 1000.0)
    // Many ticks of a large positive velocity must saturate, never exceed 1.0 (threat T-06-02-01).
    var pos = CursorPosition(x: 0, y: 0)
    for _ in 0..<100 { pos = integrator.integrate(latest: fast, dt: 0.1) }
    #expect(pos.x <= 1.0)
    #expect(pos.y <= 1.0)
    #expect(abs(pos.x - 1.0) < eps)           // saturated AT the bound
    #expect(abs(pos.y - 1.0) < eps)
  }

  @Test("integrate clamps to the lower grid bound — cursor cannot leave [0,1] on the left/bottom")
  func integrateClampsLower() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let fast = CursorVelocity(ts_ns: 1, seq: 1, vx: -1000.0, vy: -1000.0)
    var pos = CursorPosition(x: 1, y: 1)
    for _ in 0..<100 { pos = integrator.integrate(latest: fast, dt: 0.1) }
    #expect(pos.x >= 0.0)
    #expect(pos.y >= 0.0)
    #expect(abs(pos.x - 0.0) < eps)           // saturated AT the bound
    #expect(abs(pos.y - 0.0) < eps)
  }

  @Test("integrate rejects NaN velocity (holds position, no NaN position) — T-06-02-01")
  func integrateRejectsNaN() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let bad = CursorVelocity(ts_ns: 1, seq: 1, vx: Float16.nan, vy: 0.0)
    let pos = integrator.integrate(latest: bad, dt: 0.1)
    #expect(!pos.x.isNaN)                      // never produces a NaN coordinate
    #expect(!pos.y.isNaN)
    #expect(abs(pos.x - 0.5) < eps)            // held exactly
    #expect(abs(pos.y - 0.5) < eps)
  }

  @Test("integrate rejects infinite velocity (holds position) — T-06-02-01")
  func integrateRejectsInfinity() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let bad = CursorVelocity(ts_ns: 1, seq: 1, vx: Float16.infinity, vy: -Float16.infinity)
    let pos = integrator.integrate(latest: bad, dt: 0.1)
    #expect(pos.x.isFinite)
    #expect(pos.y.isFinite)
    #expect(abs(pos.x - 0.5) < eps)            // held — infinite velocity rejected
    #expect(abs(pos.y - 0.5) < eps)
  }

  @Test("integrate(latest: nil) holds position exactly — empty ring -> velocity 0 (D-04)")
  func integrateEmptyRingHolds() {
    let integrator = CursorIntegrator(start: .init(x: 0.42, y: 0.73))
    let pos = integrator.integrate(latest: nil, dt: 0.1)
    #expect(abs(pos.x - 0.42) < eps)
    #expect(abs(pos.y - 0.73) < eps)
    // And the stored position equals the returned one (no drift on an empty ring).
    #expect(integrator.position.x == pos.x)
    #expect(integrator.position.y == pos.y)
  }

  @Test("CursorVelocity field order is ts_ns, seq, vx, vy and round-trips its values")
  func cursorVelocityFieldOrder() {
    let v = CursorVelocity(ts_ns: 0xDEAD_BEEF, seq: 7, vx: 0.5, vy: -0.25)
    #expect(v.ts_ns == 0xDEAD_BEEF)
    #expect(v.seq == 7)
    #expect(v.vx == Float16(0.5))
    #expect(v.vy == Float16(-0.25))
  }
}
