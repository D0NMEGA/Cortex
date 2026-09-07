// IntentRotation — the Gilja-2012 ReFIT intent-rotation on the MEASUREMENT (REFIT-02, D-04..D-06).
//
// Rotates the decoded velocity `z`'s DIRECTION fully onto the cursor→target vector while PRESERVING
// its decoded speed (magnitude), and ONLY when a target is active AND the cursor is OUTSIDE the
// acquisition radius. This is the online per-tick analogue of Gilja's intention estimation
// ("cursor velocities are rotated to point towards the direction of the target … magnitudes set to
// zero during the periods the cursor is held at the target"): full direction-align + speed-preserve
// while reaching, no rotation once on-target (the "hold" gate prevents the cursor "snap" that would
// make the BPS meaningless — 07-RESEARCH §1, §7 pitfall 4; CONTEXT D-06).
//
// The rotation acts on the decoded velocity BEFORE the Kalman measurement update (D-05) so the
// filter fuses a target-consistent observation — not a cosmetic post-hoc nudge of the output.
// `KalmanFilter.step` (this package) calls `rotate` after syncing the cursor position and before
// the constant-gain update (07-RESEARCH §2.2 ordering).
//
// ## Hot-path discipline (SC#3)
// `import simd` only — Foundation-free (never the Obj-C runtime), no allocation, no locks, no
// cooperative-dispatch hops. The op is a handful of `SIMD2<Float>` float ops (length, normalize,
// scalar·vector), so it runs inside the 20 ms tick on the existing decoder pthread. `nonisolated`
// (NOT the package-default `MainActor`) so it is callable from that pthread — mirrors `VelocityRing`
// / `CursorVelocity` in CortexRender, which opt out of `.defaultIsolation(MainActor.self)` the same
// way. (Comments here avoid the literal forbidden tokens so the hotpath-policy `grep -F` gate — which
// now scans this dir — does not false-positive on the prose, per the Plan-01 KalmanConstants note.)
//
// ## No clamp here (07-RESEARCH §7 pitfall 5)
// This type does NOT clamp or modify position — the renderer's `CursorIntegrator` is the single
// `[0,1]`-clamp + non-finite-reject validation point (Phase-6 D-04). `rotate` only returns a finite
// rotated measurement; the `dist > r_acq` (positive `r_acq`) and `speed > eps` gates guarantee the
// rotating branch never divides by zero, so finite inputs always yield a finite output.
import simd

/// The Gilja-2012 intent-rotation applied to the decoded velocity measurement (REFIT-02).
///
/// `nonisolated` value type: it crosses onto the decoder pthread (SC#3, NOT the MainActor the
/// package defaults to). Stateless — a fixed `eps` zero-velocity guard is the only stored datum.
public nonisolated struct IntentRotation: Sendable {
  /// Zero-velocity / numerical guard. The rotation is applied only when the decoded speed exceeds
  /// this floor, so a near-zero `z` never produces a `z/‖z‖`-style divide and the output is finite
  /// (T-07-02-02 mitigation). `1e-6` is far below any meaningful grid-units/second decoded speed.
  public static let epsilon: Float = 1e-6

  /// Memberwise initializer (explicit so the public API is stable).
  public init() {}

  /// Rotate the decoded velocity `z` toward the active target, preserving its magnitude — gated.
  ///
  /// Per 07-RESEARCH §1 (handed to the executor verbatim):
  /// ```
  /// d = t - p                       // cursor→target vector
  /// if (target_active && |d| > r_acq && |z| > eps) {
  ///     speed = |z|                 // preserve decoded speed (magnitude)
  ///     z_rot = speed * (d / |d|)   // full direction-align onto cursor→target
  /// } else {
  ///     z_rot = z                   // no rotation: on-target hold or no target
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - z: the decoded `(vx, vy)` velocity (the Kalman measurement, BEFORE the update — D-05).
  ///   - cursor: the cursor position synced from the integrator's authoritative clamped position
  ///     (07-RESEARCH §2.3) — synced BEFORE this call (§7 pitfall 5).
  ///   - target: the active target center, or `nil` if no target is active (⇒ passthrough).
  ///   - acquisitionRadius: the on-target hold radius. Inside it the rotation is OFF (no snap).
  /// - Returns: the rotated measurement when reaching outside `r_acq`; otherwise `z` unchanged.
  ///   Always finite for finite inputs.
  public func rotate(
    measurement z: SIMD2<Float>,
    cursor p: SIMD2<Float>,
    target: SIMD2<Float>?,
    acquisitionRadius rAcq: Float
  ) -> SIMD2<Float> {
    // No active target → nothing to rotate toward (Test 3).
    guard let target else { return z }

    let d = target - p // cursor→target vector
    let dist = simd_length(d)
    let speed = simd_length(z)

    // Gate (CONTEXT D-06): rotate ONLY when the cursor is OUTSIDE the acquisition radius AND the
    // decoded speed exceeds the zero-velocity guard. `dist > r_acq` (with a positive `r_acq`) also
    // guarantees `dist > 0`, so `speed / dist` below never divides by zero (Tests 2, 4, 5).
    guard dist > rAcq, speed > Self.epsilon else { return z }

    // Full direction-align with magnitude preserved: speed * (d / dist) (Test 1).
    return (speed / dist) * d
  }
}
