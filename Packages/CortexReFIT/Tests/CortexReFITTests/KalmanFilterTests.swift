// REFIT-01 / D-01..D-03 — the 6-DOF steady-state constant-gain Kalman step (predict → external
// position sync → rotate measurement → constant-gain update → emit 2-vector velocity).
//
// These tests pin the per-tick filter math (07-RESEARCH §2.2 ordering, §2.3 external position sync,
// §6 row 1 reference-match bar). The filter loads `KalmanConstants` (A/H/K) and does a handful of
// fixed-dim simd mat-vecs with zero allocation (no runtime Riccati — D-02). The five behaviors:
//
//   1. Single step (no target): one `step` equals a hand-computed `x⁻ = A·x; x = x⁻ + K·(z − H·x⁻)`.
//   2. ≥50-tick trajectory: the inlined-simd step matches an independent textbook nested-loop
//      reference (`‖x_swift − x_ref‖ < tol`) — exercises propagation error, not one step (§6 row 1).
//   3. External position sync: the position used for the rotation's cursor→target vector is the
//      externally-synced `p` (07-RESEARCH §2.3), NOT a velocity-double-integrated position.
//   4. Finite 2-vector output for finite inputs (never NaN/Inf — the integrator is the clamp, but the
//      filter must not itself poison the stream — threat T-07-02-02).
//   5. Rotation wired: with an active target outside r_acq the measurement fed to the update is the
//      ROTATED z — the emitted velocity differs from the no-rotation (no-target) path on the same z.
//
// `KalmanFilter` is `nonisolated` (it runs on the decoder pthread, SC#3, NOT the MainActor the package
// defaults to), so this suite needs no actor isolation.
import Testing
import simd

@testable import CortexReFIT

@Suite("REFIT-01: KalmanFilter — constant-gain step, ordering, reference-match, rotation wiring")
struct KalmanFilterTests {
  /// Per-element absolute tolerance for the single-step and trajectory float comparisons. Float math
  /// over a constant-acceleration model accumulates a little over ≥50 ticks; 2e-3 is comfortably
  /// above the float-rounding floor yet tight enough that a wrong mat-vec (drift) fails.
  private static let tol: Float = 2e-3

  // MARK: - Independent textbook reference (plain nested-loop, no simd inlining)

  /// A deliberately naive, allocation-heavy, textbook constant-gain Kalman step over plain `[Float]`
  /// arrays — the INDEPENDENT reference the inlined-simd `KalmanFilter` is checked against (§6 row 1).
  /// It reads the SAME committed `KalmanConstants` (A/H/K) but via lane accessors into flat matrices,
  /// so a coding error in the production simd dot-products drifts away from this and fails Test 2.
  ///
  /// Mirrors the production ordering EXACTLY (07-RESEARCH §2.2): predict → overwrite predicted
  /// position with the synced cursor → rotate the measurement toward (target − synced cursor) →
  /// constant-gain update → return the full 6-state. Position rows of K are zero (Plan 01), so the
  /// update never corrects position — only the external sync moves it.
  ///
  /// `nonisolated`: reads the now-`nonisolated` ``KalmanConstants``, so it is callable directly from
  /// the (nonisolated) `@Test` methods with no isolation hop — mirroring the production `KalmanFilter`.
  private static func referenceStep(
    state x: [Float],
    measurement z: SIMD2<Float>,
    syncedPosition p: SIMD2<Float>,
    target: SIMD2<Float>?,
    acquisitionRadius rAcq: Float
  ) -> [Float] {
    // Flatten the committed constants into plain Float matrices (cols 0..5 of the SIMD8 rows).
    let a: [[Float]] = KalmanConstants.A.map { row in [row[0], row[1], row[2], row[3], row[4], row[5]] }
    let h: [[Float]] = KalmanConstants.H.map { row in [row[0], row[1], row[2], row[3], row[4], row[5]] }
    let k: [[Float]] = KalmanConstants.K.map { row in [row.x, row.y] }

    // predict: xMinus = A · x  (textbook nested loop)
    var xMinus = [Float](repeating: 0, count: 6)
    for i in 0 ..< 6 {
      var acc: Float = 0
      for j in 0 ..< 6 { acc += a[i][j] * x[j] }
      xMinus[i] = acc
    }

    // SYNC position externally into the predicted position block BEFORE the rotation (§2.3).
    xMinus[0] = p.x
    xMinus[1] = p.y

    // rotate the measurement toward (target − synced cursor). Same gating as IntentRotation.
    var zRot = z
    if let target {
      let d = target - SIMD2<Float>(xMinus[0], xMinus[1])
      let dist = simd_length(d)
      let speed = simd_length(z)
      if dist > rAcq, speed > IntentRotation.epsilon {
        zRot = (speed / dist) * d
      }
    }

    // innovation: zRot − H · xMinus  (H selects (vx,vy) = indices 2,3)
    var hx = [Float](repeating: 0, count: 2)
    for i in 0 ..< 2 {
      var acc: Float = 0
      for j in 0 ..< 6 { acc += h[i][j] * xMinus[j] }
      hx[i] = acc
    }
    let innovation = SIMD2<Float>(zRot.x - hx[0], zRot.y - hx[1])

    // update: x = xMinus + K · innovation  (K is 6×2)
    var xNew = [Float](repeating: 0, count: 6)
    for i in 0 ..< 6 {
      xNew[i] = xMinus[i] + k[i][0] * innovation.x + k[i][1] * innovation.y
    }
    return xNew
  }

  // MARK: - Test 1: single step matches a hand-computed constant-gain update

  /// Test 1 (single step, NO active target → no rotation): one `step` equals the textbook
  /// `x⁻ = A·x; x = x⁻ + K·(z − H·x⁻)` (with the external position sync) to float tolerance.
  @Test("single step (no target) equals the hand-computed constant-gain update")
  func singleStepMatchesReference() {
    let filter = KalmanFilter()
    let x0: [Float] = [0.2, 0.3, 0.5, -0.4, 0.1, 0.05] // px,py,vx,vy,ax,ay
    filter.setState(x0)
    let p = SIMD2<Float>(0.25, 0.35)
    filter.setCursorPosition(p)

    let z = SIMD2<Float>(0.6, -0.5)
    let out = filter.step(measurement: z, target: nil, acquisitionRadius: 0.05)

    let ref = Self.referenceStep(state: x0, measurement: z, syncedPosition: p, target: nil, acquisitionRadius: 0.05)
    // Emitted velocity is (vx,vy) = ref[2], ref[3].
    #expect(abs(out.x - ref[2]) < Self.tol)
    #expect(abs(out.y - ref[3]) < Self.tol)
  }

  // MARK: - Test 2: ≥50-tick trajectory matches the independent reference

  /// Test 2 (≥50-tick trajectory): feeding a fixed deterministic z-sequence for 64 ticks, the inlined
  /// `KalmanFilter` full state stays within `tol` of the independent nested-loop reference at EVERY
  /// tick — exercises propagation, not a single step (§6 row 1, threat T-07-02-04). Position is synced
  /// each tick to a deterministic closed-form sweep (no clock/RNG — determinism contract).
  @Test("≥50-tick trajectory matches the independent reference (‖x_swift − x_ref‖ < tol)")
  func trajectoryMatchesReference() {
    let filter = KalmanFilter()
    let x0: [Float] = [0.5, 0.5, 0.0, 0.0, 0.0, 0.0]
    filter.setState(x0)
    var ref = x0
    let target = SIMD2<Float>(0.9, 0.8)
    let rAcq: Float = 0.02

    let ticks = 64
    for t in 0 ..< ticks {
      // Deterministic closed-form measurement + synced position sweep (no RNG).
      let phase = Float(t) * 0.1
      let z = SIMD2<Float>(0.3 * cosf(phase), 0.3 * sinf(phase))
      // Synced cursor sweeps along a fixed line — the authoritative position each tick.
      let p = SIMD2<Float>(0.2 + 0.005 * Float(t), 0.2 + 0.004 * Float(t))

      filter.setCursorPosition(p)
      let out = filter.step(measurement: z, target: target, acquisitionRadius: rAcq)

      ref = Self.referenceStep(state: ref, measurement: z, syncedPosition: p, target: target, acquisitionRadius: rAcq)

      // The emitted velocity must track the reference velocity (indices 2,3) at every tick.
      #expect(abs(out.x - ref[2]) < Self.tol, "vx drift at tick \(t): \(out.x) vs \(ref[2])")
      #expect(abs(out.y - ref[3]) < Self.tol, "vy drift at tick \(t): \(out.y) vs \(ref[3])")
      // And the full internal state must track (catches a position/accel mat-vec error too).
      let xs = filter.stateVector
      for i in 0 ..< 6 {
        #expect(abs(xs[i] - ref[i]) < Self.tol, "state[\(i)] drift at tick \(t): \(xs[i]) vs \(ref[i])")
      }
    }
  }

  // MARK: - Test 3: position is synced EXTERNALLY, not double-integrated

  /// Test 3 (external position sync, 07-RESEARCH §2.3 / §7 pitfall 5): the position that feeds the
  /// rotation's cursor→target vector is the externally-synced `p`, NOT a velocity-integrated one.
  /// Proof: with the SAME state, measurement, and target, two DIFFERENT synced cursor positions
  /// produce two DIFFERENT rotated measurements ⇒ two different emitted velocities. If the filter
  /// double-integrated position internally (ignoring the sync), both calls would be identical.
  @Test("position is synced externally (rotation uses synced p, not a double-integrated position)")
  func positionIsSyncedExternally() {
    let target = SIMD2<Float>(0.5, 0.9)
    let z = SIMD2<Float>(0.4, 0.0) // points +x; rotation will steer it toward the target
    let rAcq: Float = 0.02
    let x0: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

    // Cursor synced to the LEFT of the target.
    let fa = KalmanFilter()
    fa.setState(x0)
    fa.setCursorPosition(SIMD2<Float>(0.1, 0.1))
    let outA = fa.step(measurement: z, target: target, acquisitionRadius: rAcq)

    // Cursor synced to the RIGHT of the target — the cursor→target direction differs, so the rotated
    // measurement (and the fused velocity) must differ.
    let fb = KalmanFilter()
    fb.setState(x0)
    fb.setCursorPosition(SIMD2<Float>(0.9, 0.1))
    let outB = fb.step(measurement: z, target: target, acquisitionRadius: rAcq)

    #expect(outA != outB)

    // Direct sync read: the filter's position block equals the synced p after a step (not integrated).
    let fc = KalmanFilter()
    fc.setState(x0)
    let synced = SIMD2<Float>(0.33, 0.66)
    fc.setCursorPosition(synced)
    _ = fc.step(measurement: z, target: nil, acquisitionRadius: rAcq)
    let st = fc.stateVector
    #expect(abs(st[0] - synced.x) < Self.tol)
    #expect(abs(st[1] - synced.y) < Self.tol)
  }

  // MARK: - Test 4: finite 2-vector output for finite inputs

  /// Test 4 (finiteness): `step` returns a finite `SIMD2<Float>` for finite inputs across the
  /// rotating and passthrough paths. The filter does not clamp (the integrator owns that) but it must
  /// not emit NaN/Inf (threat T-07-02-02).
  @Test("step returns a finite 2-vector for finite inputs")
  func outputIsFinite() {
    let filter = KalmanFilter()
    filter.setCursorPosition(SIMD2<Float>(0.5, 0.5))

    // Rotating branch (target outside r_acq).
    let o1 = filter.step(measurement: SIMD2<Float>(0.4, -0.3), target: SIMD2<Float>(0.9, 0.1), acquisitionRadius: 0.02)
    #expect(o1.x.isFinite && o1.y.isFinite)

    // Passthrough branch (no target).
    let o2 = filter.step(measurement: SIMD2<Float>(-0.2, 0.7), target: nil, acquisitionRadius: 0.02)
    #expect(o2.x.isFinite && o2.y.isFinite)

    // Zero-velocity guard branch.
    let o3 = filter.step(measurement: SIMD2<Float>(0, 0), target: SIMD2<Float>(0.9, 0.9), acquisitionRadius: 0.02)
    #expect(o3.x.isFinite && o3.y.isFinite)
  }

  // MARK: - Test 5: rotation is wired on the MEASUREMENT before the update

  /// Test 5 (rotation wired, D-05): with an active target OUTSIDE r_acq, the measurement fed to the
  /// update is the ROTATED z — so the emitted velocity differs from the no-rotation (no-target) path
  /// on the SAME state + measurement. Confirms the rotation acts on the measurement before the update,
  /// not as a cosmetic post-hoc nudge.
  @Test("rotation wired: active-target output differs from the no-rotation path")
  func rotationIsWiredOnTheMeasurement() {
    let x0: [Float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    // Measurement points the WRONG way relative to the target so the rotation visibly changes it.
    let z = SIMD2<Float>(-0.5, -0.5)
    let cursor = SIMD2<Float>(0.2, 0.2)
    let target = SIMD2<Float>(0.9, 0.8) // up-right; z points down-left
    let rAcq: Float = 0.02

    let rotated = KalmanFilter()
    rotated.setState(x0)
    rotated.setCursorPosition(cursor)
    let outRot = rotated.step(measurement: z, target: target, acquisitionRadius: rAcq)

    let noRot = KalmanFilter()
    noRot.setState(x0)
    noRot.setCursorPosition(cursor)
    let outNoRot = noRot.step(measurement: z, target: nil, acquisitionRadius: rAcq)

    #expect(outRot != outNoRot)

    // Sanity: the rotated path should fuse a measurement pointing toward the target, so its emitted
    // velocity has a larger component along cursor→target than the no-rotation path (which points away).
    let towardTarget = simd_normalize(target - cursor)
    let projRot = simd_dot(outRot, towardTarget)
    let projNoRot = simd_dot(outNoRot, towardTarget)
    #expect(projRot > projNoRot)
  }

  // MARK: - Test 6: the injected-gain init is the same filter when handed the shipped gain

  /// Test 6 (Phase 10, D-09): `KalmanFilter(gain:)` exists so the SYNTHETIC regression fixture can
  /// hold the gain fixed at ``KalmanConstants/phase7BaselineK`` while the shipped ``KalmanConstants/K``
  /// moves with a real-data re-fit. That seam is only safe if the two inits are the SAME filter when
  /// handed the same gain: `init()` must be `init(gain: KalmanConstants.K)` and nothing else. Drive
  /// both over an identical 64-tick measurement sequence and require bit-equal emitted velocities.
  ///
  /// This is the test that would catch a second unpacking implementation drifting from the first.
  @Test("KalmanFilter(gain: KalmanConstants.K) reproduces KalmanFilter() exactly")
  func injectedShippedGainMatchesDefaultInit() {
    let x0: [Float] = [0.5, 0.5, 0.0, 0.0, 0.0, 0.0]
    let target = SIMD2<Float>(0.9, 0.8)
    let rAcq: Float = 0.02

    let byDefault = KalmanFilter()
    byDefault.setState(x0)
    let byInjection = KalmanFilter(gain: KalmanConstants.K)
    byInjection.setState(x0)

    for t in 0 ..< 64 {
      let phase = Float(t) * 0.1
      let z = SIMD2<Float>(0.3 * cosf(phase), 0.3 * sinf(phase))
      let p = SIMD2<Float>(0.2 + 0.005 * Float(t), 0.2 + 0.004 * Float(t))

      byDefault.setCursorPosition(p)
      byInjection.setCursorPosition(p)
      let a = byDefault.step(measurement: z, target: target, acquisitionRadius: rAcq)
      let b = byInjection.step(measurement: z, target: target, acquisitionRadius: rAcq)

      #expect(a == b, "injected-gain output diverged at tick \(t): \(a) vs \(b)")
      #expect(byDefault.stateVector == byInjection.stateVector, "state diverged at tick \(t)")
    }
  }

  /// Test 7 (Phase 10, D-09): the frozen baseline gain produces a DIFFERENT filter from the shipped
  /// re-fit gain. If these two ever agreed, `CortexReFITBench --smoke` would be immune to a re-fit by
  /// coincidence rather than by construction, and the freeze would be silently load-free.
  ///
  /// It asserts a DIFFERENCE, never a direction or a magnitude, so it stays inside D-09.
  @Test("KalmanFilter(gain: phase7BaselineK) differs from the shipped-gain filter")
  func frozenBaselineGainProducesADifferentFilter() {
    let x0: [Float] = [0.5, 0.5, 0.0, 0.0, 0.0, 0.0]
    let target = SIMD2<Float>(0.9, 0.8)
    let rAcq: Float = 0.02

    let shipped = KalmanFilter()
    shipped.setState(x0)
    let frozen = KalmanFilter(gain: KalmanConstants.phase7BaselineK)
    frozen.setState(x0)

    var diverged = false
    for t in 0 ..< 64 {
      let phase = Float(t) * 0.1
      let z = SIMD2<Float>(0.3 * cosf(phase), 0.3 * sinf(phase))
      let p = SIMD2<Float>(0.2 + 0.005 * Float(t), 0.2 + 0.004 * Float(t))

      shipped.setCursorPosition(p)
      frozen.setCursorPosition(p)
      let a = shipped.step(measurement: z, target: target, acquisitionRadius: rAcq)
      let b = frozen.step(measurement: z, target: target, acquisitionRadius: rAcq)
      if a != b { diverged = true }
    }
    #expect(diverged, "the frozen Phase-7 baseline gain and the shipped re-fit gain drive the filter identically")
  }
}
