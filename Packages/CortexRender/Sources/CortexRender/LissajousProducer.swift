// LissajousProducer — a deterministic, closed-form synthetic VELOCITY drive for the cursor
// (Phase 6 D-05).
//
// Per D-05 a smooth parametric (Lissajous) drive powers the cursor for the 60s sustained 120Hz soak
// (SC#4) and the demo. It MUST be deterministic and reproducible so frame-pacing measurements are
// stable and the no-dropped-frames soak is repeatable — therefore `t` (absolute time in seconds) is
// the ONLY input: no randomness, no wall-clock read, no global mutable state. Two producers with
// identical parameters return bit-identical velocity for the same `t`.
//
// ## Velocity, not position (matches the D-03 seam)
// The renderer's seam is velocity-typed (D-03/D-04) and the integrator advances
// `position += velocity * dt`. So this produces the VELOCITY of a Lissajous figure:
//   vx(t) = ampX · cos(freqX · t + phase)
//   vy(t) = ampY · sin(freqY · t)
// Integrating these traces a classic Lissajous curve. With `freqX ≠ freqY` the figure is an open
// curve that fills a region of the grid (keeping all 900 cells "alive" near the cursor, D-09).
//
// ## Staying on-grid (default amplitudes)
// The integral of `ampX·cos(freqX·t+φ)` has amplitude `ampX/freqX`. To keep the integrated path
// inside the grid's `[0,1]` span about the centre `0.5`, the defaults pick `ampX/freqX ≈ 0.4` and
// `ampY/freqY ≈ 0.4` so the cursor sweeps most of the surface without perpetually saturating at a
// bound (the integrator clamps regardless — this is about producing a *useful* figure, not safety).

import Foundation // cos/sin (Darwin math) only — purely the trig free functions, no clock, no RNG.

/// A deterministic parametric velocity source (D-05). `Sendable` value type (no stored state beyond
/// the immutable parameters) — safe to hand to the producer thread.
public nonisolated struct LissajousProducer: Sendable {
  /// Velocity amplitude on x (grid-units/second).
  public let ampX: Float
  /// Velocity amplitude on y (grid-units/second).
  public let ampY: Float
  /// Angular frequency on x (radians/second).
  public let freqX: Double
  /// Angular frequency on y (radians/second).
  public let freqY: Double
  /// Phase offset on x (radians) — shifts the figure; part of the determinism contract.
  public let phase: Double

  /// - Defaults trace a classic open Lissajous figure (freqX ≠ freqY) whose integrated path sweeps
  ///   most of the `[0,1]` grid without sitting on a bound: `ampX/freqX ≈ ampY/freqY ≈ 0.4`.
  public init(
    ampX: Float = 0.40,
    ampY: Float = 0.44,
    freqX: Double = 1.0,
    freqY: Double = 1.1,
    phase: Double = 0.0
  ) {
    self.ampX = ampX
    self.ampY = ampY
    self.freqX = freqX
    self.freqY = freqY
    self.phase = phase
  }

  /// The deterministic velocity at absolute time `t` (seconds). Closed-form: identical `(params, t)`
  /// always yields bit-identical `(vx, vy)` — no clock, no RNG, no state (D-05).
  public func velocity(at t: Double) -> (vx: Float16, vy: Float16) {
    // Compute in Double for precision, then narrow to the fp16 seam type (DEC-10).
    let vx = Double(ampX) * cos(freqX * t + phase)
    let vy = Double(ampY) * sin(freqY * t)
    return (Float16(vx), Float16(vy))
  }
}
