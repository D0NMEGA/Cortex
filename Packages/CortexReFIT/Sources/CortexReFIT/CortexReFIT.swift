// CortexReFIT — the Swift, post-CoreML ReFIT-Kalman stage (Phase 7, REFIT-01/02).
//
// Wraps the NDT1 decoder's 2-vector `(vx, vy)` cursor-velocity output in a 6-DOF
// constant-acceleration steady-state Kalman filter and applies a Gilja-2012 intent-rotation step
// every 20 ms cursor update, emitting a refined `CursorVelocity` into the renderer's seam. The
// filter is constant-gain: the converged gain `K` is fit OFFLINE in the `Decoder/` uv subsystem
// (`scripts/fit_kalman_gain.py`, D-15) and loaded here as committed `simd` constants
// (``KalmanConstants``) — no Riccati at runtime; the per-tick op is a few fixed simd mat-vecs on
// the existing decoder pthread (SC#3: zero new threads, inside the 20 ms budget).
//
// This plan (07-01) stands up the package scaffold + the committed constants; the predict/rotate/
// update filter and the headless BPS harness land in Waves 2–3.

/// Namespace + build metadata for the CortexReFIT Swift filter stage.
public enum CortexReFIT {
  /// The phase that owns this package (7 — ReFIT-Kalman closed-loop recalibration).
  public static let phase: Int = 7

  /// Full kinematic state width `[px, py, vx, vy, ax, ay]` (CONTEXT D-01). The output to the seam
  /// stays a 2-vector velocity; the position state is internal to the filter dynamics.
  public static let stateDimension: Int = 6

  /// Measurement width — the decoded `(vx, vy)` the filter fuses (matches
  /// ``CortexDecoder/velocityDimension`` == 2).
  public static let measurementDimension: Int = 2
}
