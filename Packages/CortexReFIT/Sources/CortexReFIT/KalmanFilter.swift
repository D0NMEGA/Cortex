// KalmanFilter — the 6-DOF steady-state constant-gain ReFIT-Kalman step (REFIT-01, D-01..D-03).
//
// Wraps the NDT1 decoder's 2-vector `(vx, vy)` measurement in a 6-DOF constant-acceleration kinematic
// filter `[px, py, vx, vy, ax, ay]` and emits a refined `(vx, vy)` velocity every 20 ms tick. The
// gain `K` is the STEADY-STATE constant solved offline in `Decoder/` (D-15) and loaded from
// ``KalmanConstants`` — there is NO runtime Riccati and NO per-tick covariance propagation (D-02). The
// per-tick op is a handful of fixed-dim `simd` mat-vecs with ZERO allocation, so it is trivially
// inside the 20 ms budget on the existing decoder pthread (SC#3).
//
// ## Per-tick ordering (07-RESEARCH §2.2 — load-bearing)
// ```
// x⁻      = A · x                              // predict (kinematic propagation)
// x⁻[p]   = synced cursor position             // SYNC position externally (§2.3) — BEFORE rotation
// z_rot   = rotate(z, toward = target − x⁻[p]) // §1 intent-rotation on the MEASUREMENT (D-05)
// x       = x⁻ + K · (z_rot − H · x⁻)          // update (constant gain)
// emit (x[vx], x[vy])                          // 2-vector output to the VelocityRing seam
// ```
// The position sync happens BEFORE the rotation so the cursor→target vector uses the integrator's
// authoritative clamped position, not the unobservable predicted-position block (07-RESEARCH §7
// pitfall 5; threat T-07-02-03). Position is unobservable from a velocity measurement, so K's position
// rows are exactly zero (Plan 01) — the update never corrects position; only `setCursorPosition` moves
// it.
//
// ## Hot-path discipline (SC#3)
// `import simd` only — Foundation-free (never the Obj-C runtime), no allocation, no locks, no
// cooperative-dispatch hops. `nonisolated` (NOT the package-default `MainActor`) so it is callable from
// the decoder pthread — mirrors `IntentRotation` / `VelocityRing` / `CursorVelocity`, which opt out of
// `.defaultIsolation(MainActor.self)` the same way. (Comments avoid the literal forbidden tokens so the
// hotpath-policy `grep -F` gate — which now scans this dir — does not false-positive on the prose.)
//
// ## No clamp here (07-RESEARCH §7 pitfall 5)
// `CursorIntegrator` (CortexRender) is the single `[0,1]`-clamp + non-finite-reject validation point.
// `KalmanFilter` only emits finite values: the rotation's `dist > r_acq` / `speed > eps` gates and the
// finite constant gain guarantee a finite output for finite inputs (threat T-07-02-02).
import simd

/// The 6-DOF steady-state constant-gain ReFIT-Kalman filter (REFIT-01).
///
/// `nonisolated final class`: it holds the mutable 6-state and crosses onto the decoder pthread (SC#3,
/// NOT the MainActor the package defaults to). Reference semantics so the live producer holds one
/// filter and steps it in place each tick (no per-tick allocation).
public final nonisolated class KalmanFilter {
  /// The 6-DOF state `[px, py, vx, vy, ax, ay]` packed into a `SIMD8<Float>` (lanes 6,7 unused, kept
  /// zero) so the predict `A · x` is six inlined `simd` dot products against the SIMD8 constant rows —
  /// the exact layout ``KalmanConstants/A`` emits (Plan 01). No heap; the whole state is one register
  /// file of floats.
  private var state: SIMD8<Float>

  /// The intent-rotation applied to the measurement before the update (D-05). Stateless value type.
  private let rotation = IntentRotation()

  // The committed steady-state matrices, captured once into stored `let`s so the hot-path `step`
  // touches only instance storage (no static-property access, no isolation hop) per tick. A/H rows are
  // SIMD8 (cols 0..5 meaningful, 6,7 zero-pad — Swift has no SIMD6); K rows are SIMD2 (kx,ky), with
  // exactly-zero position rows 0,1 (Plan 01 observability resolution).
  private let a0: SIMD8<Float>, a1: SIMD8<Float>, a2: SIMD8<Float>
  private let a3: SIMD8<Float>, a4: SIMD8<Float>, a5: SIMD8<Float>
  private let h0: SIMD8<Float>, h1: SIMD8<Float>
  private let k0: SIMD2<Float>, k1: SIMD2<Float>, k2: SIMD2<Float>
  private let k3: SIMD2<Float>, k4: SIMD2<Float>, k5: SIMD2<Float>

  /// Create a filter with a zero initial state on the SHIPPED gain ``KalmanConstants/K``. The
  /// committed constants are snapshotted into stored rows here (a one-time setup cost — not on the
  /// hot path); `step` then reads only instance storage.
  public convenience init() {
    self.init(gain: KalmanConstants.K)
  }

  /// Build the filter on an EXPLICIT gain rather than the shipped `KalmanConstants.K`. The only
  /// caller is the synthetic regression fixture, which passes `KalmanConstants.phase7BaselineK` so
  /// its bytes are immune to a real-data re-fit (Phase-10 D-09). `A` and `H` are structural and are
  /// always taken from `KalmanConstants`.
  ///
  /// This is the ONE unpacking implementation; `init()` forwards to it, so a second gain source can
  /// never drift from the first (`KalmanFilterTests` Test 6 pins that equivalence).
  ///
  /// - Parameter k: 6 rows of `(kx, ky)` in the `KalmanConstants.K` layout. Rows 0 and 1 are the
  ///   position block and are expected to be zero (position is unobservable from a velocity
  ///   measurement); a shorter array traps here rather than mis-indexing on the hot path.
  public init(gain k: [SIMD2<Float>]) {
    precondition(k.count == 6, "KalmanFilter requires a 6-row gain; got \(k.count)")
    state = SIMD8<Float>(repeating: 0)

    let a = KalmanConstants.A
    let h = KalmanConstants.H
    a0 = a[0]
    a1 = a[1]
    a2 = a[2]
    a3 = a[3]
    a4 = a[4]
    a5 = a[5]
    h0 = h[0]
    h1 = h[1]
    k0 = k[0]
    k1 = k[1]
    k2 = k[2]
    k3 = k[3]
    k4 = k[4]
    k5 = k[5]
  }

  /// Sync the filter's position block to the integrator's authoritative clamped cursor position
  /// (07-RESEARCH §2.3). Called each tick BEFORE `step` (the live path feeds back `CursorIntegrator`'s
  /// position; the headless harness knows it directly). Position is unobservable from a velocity
  /// measurement, so this external sync — not a measurement correction — is what moves `px,py`.
  public func setCursorPosition(_ p: SIMD2<Float>) {
    state[0] = p.x
    state[1] = p.y
  }

  /// Overwrite the full 6-DOF state `[px, py, vx, vy, ax, ay]` (test/harness seam). Ignores any extra
  /// elements; missing elements are treated as zero. Not on the hot path.
  public func setState(_ x: [Float]) {
    var s = SIMD8<Float>(repeating: 0)
    for i in 0 ..< min(6, x.count) {
      s[i] = x[i]
    }
    state = s
  }

  /// The current 6-DOF state as a `[px, py, vx, vy, ax, ay]` array (test/inspection seam). Not on the
  /// hot path.
  public var stateVector: [Float] {
    [state[0], state[1], state[2], state[3], state[4], state[5]]
  }

  /// Run one steady-state constant-gain step and return the refined `(vx, vy)` velocity.
  ///
  /// Ordering is EXACTLY 07-RESEARCH §2.2: predict → sync position (already done via
  /// `setCursorPosition`, re-asserted here so the predicted position block is overwritten BEFORE the
  /// rotation) → rotate the measurement toward the target → constant-gain update → emit. Allocation-
  /// free: a few inlined `simd` dot products on stored rows.
  ///
  /// - Parameters:
  ///   - z: the decoded `(vx, vy)` measurement (fp16 widened to `Float`), BEFORE the update (D-05).
  ///   - target: the active target center, or `nil` if no target is active (⇒ no rotation).
  ///   - rAcq: the on-target hold radius. Inside it the rotation is OFF (no snap — D-06).
  /// - Returns: the refined `(vx, vy)` velocity. Finite for finite inputs (no clamp — the integrator
  ///   owns that).
  @inline(__always)
  public func step(
    measurement z: SIMD2<Float>,
    target: SIMD2<Float>?,
    acquisitionRadius rAcq: Float
  ) -> SIMD2<Float> {
    // The synced cursor position (lanes 0,1) must survive the predict so the rotation sees it. Capture
    // it, predict the rest, then write it back into the predicted position block (§2.3, §7 pitfall 5).
    let syncedPosition = SIMD2<Float>(state[0], state[1])

    // predict: x⁻ = A · x  (six inlined 6-wide dot products; pad lanes 6,7 are zero in both operands).
    var xMinus = SIMD8<Float>(repeating: 0)
    xMinus[0] = simd_dot(a0, state)
    xMinus[1] = simd_dot(a1, state)
    xMinus[2] = simd_dot(a2, state)
    xMinus[3] = simd_dot(a3, state)
    xMinus[4] = simd_dot(a4, state)
    xMinus[5] = simd_dot(a5, state)

    // SYNC position externally into the predicted position block BEFORE the rotation (§2.3).
    xMinus[0] = syncedPosition.x
    xMinus[1] = syncedPosition.y

    // rotate the MEASUREMENT toward (target − synced cursor) (D-05; §1). Gated inside IntentRotation.
    let zRot = rotation.rotate(
      measurement: z,
      cursor: syncedPosition,
      target: target,
      acquisitionRadius: rAcq
    )

    // innovation: z_rot − H · x⁻. H = [0 I 0] selects (vx,vy) = predicted lanes 2,3.
    let hx = SIMD2<Float>(simd_dot(h0, xMinus), simd_dot(h1, xMinus))
    let innovation = zRot - hx

    // update: x = x⁻ + K · innovation  (K is 6×2; rows are (kx,ky)). Position rows k0,k1 are zero, so
    // the update applies no correction to px,py — only the external sync moves position.
    var xNew = xMinus
    xNew[0] = xMinus[0] + simd_dot(k0, innovation)
    xNew[1] = xMinus[1] + simd_dot(k1, innovation)
    xNew[2] = xMinus[2] + simd_dot(k2, innovation)
    xNew[3] = xMinus[3] + simd_dot(k3, innovation)
    xNew[4] = xMinus[4] + simd_dot(k4, innovation)
    xNew[5] = xMinus[5] + simd_dot(k5, innovation)

    state = xNew

    // emit the refined (vx, vy) = lanes 2,3.
    return SIMD2<Float>(xNew[2], xNew[3])
  }
}
