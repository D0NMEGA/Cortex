// CursorIntegrator — the RENDERER-OWNED velocity→position integrator (Phase 6 D-04).
//
// Per D-04 the seam stays velocity-typed; the renderer integrates velocity→position each tick and
// clamps to grid bounds. Position is a presentation concern, and Phase 7's Kalman also emits
// velocity, so the seam is unchanged when the real decoder lands. Plan 03's display-link callback
// pops the latest `CursorVelocity` from the ring, calls `integrate(latest:dt:)` with
// `dt = targetPresentationTimestamp` delta, and feeds the resulting position into
// `WebgridParams.cursorX/cursorY` for the compute kernel.
//
// ## Validation point at the trust boundary (threat T-06-02-01)
// In Phase 7 the velocity comes from a learned decoder + Kalman — it MAY emit NaN/Inf or
// out-of-range values. The integrator is the single validation point: it rejects non-finite
// velocity (holds the last position) and clamps the result to the `[0, 1]` grid-normalised bounds.
// The post-clamp position is therefore PROVABLY finite and in-range, so the kernel's cursor disc +
// cell mapping never receive an off-grid or NaN coordinate (the cursor cannot be driven
// off-surface, and a NaN can never index out of the grid).
//
// ## Velocity-scale contract
// `CursorVelocity.vx/vy` are in GRID-UNITS PER SECOND. `integrate` advances
// `position += velocity * Float(dt)` with NO additional scale factor (scale == 1.0): a velocity of
// 1.0 over `dt = 0.1 s` moves the cursor by exactly 0.1 in grid-normalised space.
//
// ## Callback-safety
// `integrate` performs no allocation, no locking, and no logging — it is a few scalar ops on stored
// `Float`s. It is safe to call from the display-link callback (the Plan 03 consumer thread), in the
// same audio-callback discipline as the Phase 3 hot path.

/// A cursor position in grid-normalised `[0, 1]` space (the coordinate space `WebgridParams`
/// consumes). `Sendable` + `nonisolated` so it can be produced/read from the callback thread.
public nonisolated struct CursorPosition: Sendable, Equatable {
  public var x: Float
  public var y: Float
  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }
}

/// Integrates a velocity stream into a clamped, always-finite cursor position (D-04).
public nonisolated final class CursorIntegrator {
  /// The current cursor position. Updated in-place by `integrate`; always finite and in `[0, 1]`.
  public private(set) var position: CursorPosition

  /// Grid-normalised lower/upper bounds. The grid is `[0, 1]²` (square-cell letterbox mapping is
  /// applied in the kernel), so the cursor saturates here and can never leave the surface.
  private static let lowerBound: Float = 0.0
  private static let upperBound: Float = 1.0

  /// - Parameter start: the initial position (default centre of the grid). Clamped on store so an
  ///   out-of-range start can never seed an off-grid position.
  public init(start: CursorPosition = .init(x: 0.5, y: 0.5)) {
    position = CursorPosition(
      x: Self.clampFinite(start.x),
      y: Self.clampFinite(start.y)
    )
  }

  /// Advance the cursor by `latest * dt`, then clamp to `[0, 1]`. Returns (and stores) the new
  /// position.
  ///
  /// - Parameters:
  ///   - latest: the most recent velocity popped from the ring, or `nil` if the ring was empty.
  ///     `nil` ⇒ velocity `(0, 0)` ⇒ the cursor HOLDS its last position (empty-ring behavior, D-04).
  ///   - dt: the frame delta in SECONDS (e.g. the `targetPresentationTimestamp` delta).
  /// - Returns: the new, guaranteed-finite, in-`[0,1]` position.
  @discardableResult
  public func integrate(latest: CursorVelocity?, dt: Double) -> CursorPosition {
    // Empty ring → velocity 0 → hold (D-04).
    guard let v = latest else { return position }

    // Float16 → Float. A non-finite velocity (NaN/±Inf) from the future decoder must NOT drive the
    // cursor (T-06-02-01): reject the whole update and hold the current position.
    let vx = Float(v.vx)
    let vy = Float(v.vy)
    guard vx.isFinite, vy.isFinite else { return position }

    // Per-axis displacement. If the multiply produces a non-finite result (e.g. a pathological dt),
    // reject that axis's update (hold) rather than poison the position; the surviving axis still
    // integrates. The subsequent clamp guarantees the stored value is finite + in-range regardless.
    let dtF = Float(dt)
    let dx = vx * dtF
    let dy = vy * dtF

    let newX = dx.isFinite ? position.x + dx : position.x
    let newY = dy.isFinite ? position.y + dy : position.y

    position = CursorPosition(
      x: Self.clampFinite(newX),
      y: Self.clampFinite(newY)
    )
    return position
  }

  /// Clamp to `[lowerBound, upperBound]`. `min(max(...))` with finite bounds yields a finite,
  /// in-range result for any finite input (and, defensively, maps a non-finite input to a bound
  /// rather than propagating it — `max(NaN, 0)`/`min(_, 1)` collapses to a bound on Apple Silicon).
  private static func clampFinite(_ v: Float) -> Float {
    // Guard NaN explicitly: `min`/`max` with NaN are implementation-leaning; force a defined value.
    guard v.isFinite else { return lowerBound }
    return min(max(v, lowerBound), upperBound)
  }
}
