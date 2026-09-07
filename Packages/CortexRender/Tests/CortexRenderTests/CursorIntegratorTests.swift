// CursorIntegratorTests — the renderer-owned velocity→position integrator (D-04) and the
// CursorVelocity fp16 seam (D-03). These are pure-math / defined-I/O behaviors, so they are the
// TDD core of Plan 06-02: written RED first, then implemented GREEN.
//
// Velocity-scale contract (documented, load-bearing for the exact magnitude assertions below):
// `CursorVelocity.vx`/`vy` are velocities in GRID-UNITS PER SECOND. The integrator advances
// `position += velocity * dt` with NO additional scale factor (scale == 1.0), so a velocity of
// `1.0` grid-units/s over `dt = 0.1 s` moves the cursor by exactly `0.1` in grid-normalised space.
// This is the seam Phase 7's Kalman feeds unchanged (it also emits a velocity).

import CortexRender
import Testing

@Suite("CursorIntegrator")
struct CursorIntegratorTests {
  /// Tolerance for Float16→Float round-trip + Float accumulation. fp16 has ~3 decimal digits of
  /// precision; 1e-3 comfortably covers a single store + one multiply-add.
  private let eps: Float = 1e-3

  @Test("integrate moves position by exactly velocity * dt from the start point")
  func integrateMovesByVelocityTimesDt() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    // vx = 1.0 grid-units/s, dt = 0.1 s  ->  Δx = +0.1, y unchanged.
    let v = CursorVelocity(tsNs: 1, seq: 1, vx: 1.0, vy: 0.0)
    let pos = integrator.integrate(latest: v, dt: 0.1)
    #expect(abs(pos.x - 0.6) < eps) // moved right by velocity*dt
    #expect(abs(pos.y - 0.5) < eps) // y held (vy == 0)
    #expect(pos.x > 0.5) // direction is positive
  }

  @Test("integrate clamps to the upper grid bound — cursor cannot leave [0,1] on the right/top")
  func integrateClampsUpper() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let fast = CursorVelocity(tsNs: 1, seq: 1, vx: 1000.0, vy: 1000.0)
    // Many ticks of a large positive velocity must saturate, never exceed 1.0 (threat T-06-02-01).
    var pos = CursorPosition(x: 0, y: 0)
    for _ in 0 ..< 100 {
      pos = integrator.integrate(latest: fast, dt: 0.1)
    }
    #expect(pos.x <= 1.0)
    #expect(pos.y <= 1.0)
    #expect(abs(pos.x - 1.0) < eps) // saturated AT the bound
    #expect(abs(pos.y - 1.0) < eps)
  }

  @Test("integrate clamps to the lower grid bound — cursor cannot leave [0,1] on the left/bottom")
  func integrateClampsLower() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let fast = CursorVelocity(tsNs: 1, seq: 1, vx: -1000.0, vy: -1000.0)
    var pos = CursorPosition(x: 1, y: 1)
    for _ in 0 ..< 100 {
      pos = integrator.integrate(latest: fast, dt: 0.1)
    }
    #expect(pos.x >= 0.0)
    #expect(pos.y >= 0.0)
    #expect(abs(pos.x - 0.0) < eps) // saturated AT the bound
    #expect(abs(pos.y - 0.0) < eps)
  }

  @Test("integrate rejects NaN velocity (holds position, no NaN position) — T-06-02-01")
  func integrateRejectsNaN() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let bad = CursorVelocity(tsNs: 1, seq: 1, vx: Float16.nan, vy: 0.0)
    let pos = integrator.integrate(latest: bad, dt: 0.1)
    #expect(!pos.x.isNaN) // never produces a NaN coordinate
    #expect(!pos.y.isNaN)
    #expect(abs(pos.x - 0.5) < eps) // held exactly
    #expect(abs(pos.y - 0.5) < eps)
  }

  @Test("integrate rejects infinite velocity (holds position) — T-06-02-01")
  func integrateRejectsInfinity() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    let bad = CursorVelocity(tsNs: 1, seq: 1, vx: Float16.infinity, vy: -Float16.infinity)
    let pos = integrator.integrate(latest: bad, dt: 0.1)
    #expect(pos.x.isFinite)
    #expect(pos.y.isFinite)
    #expect(abs(pos.x - 0.5) < eps) // held — infinite velocity rejected
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

  @Test("CursorVelocity field order is tsNs, seq, vx, vy and round-trips its values")
  func cursorVelocityFieldOrder() {
    let v = CursorVelocity(tsNs: 0xDEAD_BEEF, seq: 7, vx: 0.5, vy: -0.25)
    #expect(v.tsNs == 0xDEAD_BEEF)
    #expect(v.seq == 7)
    #expect(v.vx == Float16(0.5))
    #expect(v.vy == Float16(-0.25))
  }
}

@Suite("AnchorChannel: re-anchor events reach the renderer exactly once")
struct AnchorChannelTests {
  @Test("nothing published means nothing to apply")
  func emptyChannelYieldsNil() {
    #expect(AnchorChannel().take(after: 0) == nil)
  }

  @Test("an anchor is delivered once, then not again")
  func anchorAppliesExactlyOnce() {
    let channel = AnchorChannel()
    channel.store(x: 0.25, y: 0.75)

    guard let first = channel.take(after: 0) else {
      Issue.record("a published anchor must be delivered")
      return
    }
    #expect(abs(first.x - 0.25) < 1e-4)
    #expect(abs(first.y - 0.75) < 1e-4)
    // Polling again with the generation just seen must yield nothing: an anchor is an event, and
    // re-applying it every frame would pin the cursor on it instead of letting it integrate away.
    #expect(channel.take(after: first.generation) == nil)

    channel.store(x: 0.1, y: 0.9)
    guard let second = channel.take(after: first.generation) else {
      Issue.record("a second anchor must be delivered")
      return
    }
    #expect(second.generation != first.generation)
    #expect(abs(second.x - 0.1) < 1e-4)
  }

  @Test("out-of-range clamps and non-finite is refused")
  func anchorClampsAndRefuses() {
    let channel = AnchorChannel()
    channel.store(x: 2.0, y: -1.0)
    let clamped = channel.take(after: 0)
    #expect(clamped?.x == 1.0)
    #expect(clamped?.y == 0.0)

    // A NaN must not publish AT ALL. Clamping it to a bound would teleport the cursor to a corner
    // and present that as a re-anchor.
    let seen = clamped?.generation ?? 0
    channel.store(x: .nan, y: 0.5)
    #expect(channel.take(after: seen) == nil)
  }

  @Test("integrator reset moves the cursor under the same clamp as integrate")
  func integratorResetClamps() {
    let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
    integrator.reset(to: .init(x: 0.2, y: 0.8))
    #expect(integrator.position.x == 0.2)
    #expect(integrator.position.y == 0.8)

    integrator.reset(to: .init(x: 3.0, y: -2.0))
    #expect(integrator.position.x == 1.0)
    #expect(integrator.position.y == 0.0)
  }
}
