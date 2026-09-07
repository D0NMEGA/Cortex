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

@Suite("Render-rate integration: a slow producer must not shrink the trajectory")
struct ZeroOrderHoldTests {
  /// The display loop's exact shape: render at `renderHz`, publish at `produceHz`, integrate the
  /// popped value with the frame delta. Returns the distance travelled in one second.
  private func travelInOneSecond(
    renderHz: Double,
    produceHz: Double,
    speed: Float,
    holdVelocity: Bool
  ) -> Float {
    let integrator = CursorIntegrator(start: .init(x: 0.0, y: 0.5))
    let frameDt = 1.0 / renderHz
    var held: CursorVelocity?
    var produced = 0.0
    for frame in 0 ..< Int(renderHz) {
      // A rate accumulator, not a frame-index modulo: 120 Hz over 50 Hz is 2.4 frames per sample, so
      // an integer stride would model a cadence this system never has. Exactly `produceHz` samples
      // land across `renderHz` frames -- the steady state of the real producer, and an empty ring on
      // every other frame.
      produced += produceHz / renderHz
      let fresh: CursorVelocity? = produced >= 1.0
        ? CursorVelocity(tsNs: 0, seq: UInt64(frame), vx: Float16(speed), vy: 0)
        : nil
      if fresh != nil {
        produced -= 1.0
        held = fresh
      }
      integrator.integrate(latest: holdVelocity ? held : fresh, dt: frameDt)
    }
    return integrator.position.x
  }

  @Test("dropping to zero velocity between samples loses most of the travel")
  func droppingVelocityBetweenSamplesUndershoots() {
    // 0.4 grid-units/second for one second should travel 0.4. Passing nil between samples makes the
    // integrator hold POSITION, so only the frames carrying a sample advance at all: 50 of 120.
    let dropped = travelInOneSecond(renderHz: 120, produceHz: 50, speed: 0.4, holdVelocity: false)
    let expected: Float = 0.4
    #expect(dropped < expected * 0.5, "measured \(dropped) of \(expected)")
    // The shortfall is the cadence ratio, not a rounding error.
    #expect(abs(dropped / expected - Float(50.0 / 120.0)) < 0.05)
  }

  @Test("holding the last velocity between samples preserves the travel")
  func holdingVelocityPreservesTravel() {
    let held = travelInOneSecond(renderHz: 120, produceHz: 50, speed: 0.4, holdVelocity: true)
    #expect(abs(held - 0.4) < 0.02, "measured \(held), expected 0.4")
  }

  @Test("the shortfall scales with the cadence gap, which is why it hid at equal rates")
  func shortfallScalesWithCadenceGap() {
    // At matched rates every frame carries a sample and the defect is invisible; it only appears
    // once the renderer outruns the producer, which is this system's whole design.
    let matched = travelInOneSecond(renderHz: 50, produceHz: 50, speed: 0.4, holdVelocity: false)
    #expect(abs(matched - 0.4) < 0.02, "at equal rates the bug does not show: \(matched)")
  }
}

@Suite("integrateHoldingVelocity: the shipped zero-order hold")
struct IntegrateHoldingVelocityTests {
  @Test("a 50 Hz producer feeding a 120 Hz consumer travels the full distance")
  func holdsAcrossTheCadenceGap() {
    let integrator = CursorIntegrator(start: .init(x: 0.0, y: 0.5))
    let frameDt = 1.0 / 120.0
    var produced = 0.0
    for frame in 0 ..< 120 {
      produced += 50.0 / 120.0
      var fresh: CursorVelocity?
      if produced >= 1.0 {
        produced -= 1.0
        fresh = CursorVelocity(tsNs: 0, seq: UInt64(frame), vx: 0.4, vy: 0)
      }
      integrator.integrateHoldingVelocity(latest: fresh, dt: frameDt)
    }
    #expect(abs(integrator.position.x - 0.4) < 0.02, "travelled \(integrator.position.x) of 0.4")
  }

  @Test("a producer that stops parks the cursor instead of flying it into the clamp")
  func expiresAStaleVelocity() {
    let integrator = CursorIntegrator(start: .init(x: 0.0, y: 0.5))
    integrator.integrateHoldingVelocity(latest: CursorVelocity(tsNs: 0, seq: 0, vx: 1.0, vy: 0), dt: 1.0 / 120.0)
    // The producer dies here. Two seconds of held 1.0 would slam the cursor to the clamp at x = 1.
    for _ in 0 ..< 240 {
      integrator.integrateHoldingVelocity(latest: nil, dt: 1.0 / 120.0)
    }
    // Held for at most `staleAfter` (0.1 s) past the last sample, so travel stays near 0.1 units.
    #expect(integrator.position.x < 0.2, "held too long: \(integrator.position.x)")
    #expect(integrator.position.x > 0.05, "expired too early: \(integrator.position.x)")
  }

  @Test("a re-anchor drops the held velocity rather than carrying it across the teleport")
  func resetClearsTheHold() {
    let integrator = CursorIntegrator(start: .init(x: 0.0, y: 0.5))
    integrator.integrateHoldingVelocity(latest: CursorVelocity(tsNs: 0, seq: 0, vx: 1.0, vy: 0), dt: 1.0 / 120.0)
    integrator.reset(to: .init(x: 0.5, y: 0.5))
    for _ in 0 ..< 12 {
      integrator.integrateHoldingVelocity(latest: nil, dt: 1.0 / 120.0)
    }
    #expect(integrator.position.x == 0.5, "the abandoned trajectory's velocity leaked: \(integrator.position.x)")
  }
}
