@testable import CortexReFIT
import simd

// REFIT-02 / D-04..D-06 — the Gilja-2012 intent-rotation, four gating branches + magnitude.
//
// These tests pin the ReFIT intent-rotation semantics (07-RESEARCH §1, CONTEXT D-05/D-06): the
// decoded velocity `z` is rotated so its DIRECTION aligns fully onto the cursor→target vector while
// its MAGNITUDE (decoded speed) is PRESERVED — and ONLY when a target is active AND the cursor is
// outside the acquisition radius (so the cursor does not "snap" on-target, 07-RESEARCH §7 pitfall
// 4). All four gating branches (outside r_acq, inside r_acq, no target, zero-velocity guard) plus a
// finiteness property are covered (VALIDATION §6 row 3). The rotation acts on the MEASUREMENT, not
// the output (D-05) — Task 2 wires it before the Kalman update.
//
// `IntentRotation` is a `nonisolated` value type (it runs on the decoder pthread, SC#3, NOT the
// MainActor the package defaults to), so this suite needs no actor isolation.
import Testing

@Suite("REFIT-02: intent-rotation — gating branches + magnitude preservation")
struct IntentRotationTests {
  /// A small absolute tolerance for float comparisons of magnitude/direction.
  private static let tol: Float = 1e-4

  /// Test 1 (OUTSIDE r_acq, target active): the rotation aligns direction FULLY onto cursor→target
  /// and PRESERVES the decoded speed. The output's magnitude == ‖z‖ and its unit direction ==
  /// unit(target − cursor) — the canonical Gilja behavior (D-06).
  @Test("outside acquisition radius: direction aligns to cursor→target, magnitude preserved")
  func rotatesOutsideAcquisitionRadius() {
    let rotation = IntentRotation()
    // Decoded velocity pointing the WRONG way (down-left); target is up-right of the cursor.
    let z = SIMD2<Float>(-1.0, -2.0)
    let cursor = SIMD2<Float>(0.2, 0.2)
    let target = SIMD2<Float>(0.8, 0.6)
    let rAcq: Float = 0.05 // cursor is ~0.72 away — well outside

    let out = rotation.rotate(measurement: z, cursor: cursor, target: target, acquisitionRadius: rAcq)

    // Magnitude preserved: ‖out‖ == ‖z‖.
    #expect(abs(simd_length(out) - simd_length(z)) < Self.tol)

    // Direction == unit(target − cursor).
    let wantDir = simd_normalize(target - cursor)
    let gotDir = simd_normalize(out)
    #expect(abs(gotDir.x - wantDir.x) < Self.tol)
    #expect(abs(gotDir.y - wantDir.y) < Self.tol)
  }

  /// Test 2 (INSIDE r_acq): when the cursor is within the acquisition radius of the target, the
  /// rotation is OFF — output == z unchanged. This prevents the on-target "snap" (07-RESEARCH §7
  /// pitfall 4); it is the online analogue of Gilja's "magnitude→0 on hold".
  @Test("inside acquisition radius: passthrough (no rotation, prevents on-target snap)")
  func passthroughInsideAcquisitionRadius() {
    let rotation = IntentRotation()
    let z = SIMD2<Float>(0.3, -0.4)
    let cursor = SIMD2<Float>(0.50, 0.50)
    let target = SIMD2<Float>(0.51, 0.50) // 0.01 away
    let rAcq: Float = 0.05 // cursor is INSIDE r_acq

    let out = rotation.rotate(measurement: z, cursor: cursor, target: target, acquisitionRadius: rAcq)

    #expect(out == z)
  }

  /// Test 3 (NO active target): no target ⇒ nothing to rotate toward ⇒ output == z unchanged.
  @Test("no active target: passthrough (output == z)")
  func passthroughNoTarget() {
    let rotation = IntentRotation()
    let z = SIMD2<Float>(0.7, 0.1)
    let cursor = SIMD2<Float>(0.3, 0.3)
    let rAcq: Float = 0.05

    let out = rotation.rotate(measurement: z, cursor: cursor, target: nil, acquisitionRadius: rAcq)

    #expect(out == z)
  }

  /// Test 4 (ZERO-velocity guard): ‖z‖ ≈ 0 with an active target outside r_acq ⇒ output == z (no
  /// divide-by-zero, no NaN). The `eps` gate (speed > eps) is the T-07-02-02 mitigation.
  @Test("zero-velocity guard: ‖z‖≈0 → passthrough, no divide-by-zero / NaN")
  func zeroVelocityGuard() {
    let rotation = IntentRotation()
    let z = SIMD2<Float>(0.0, 0.0)
    let cursor = SIMD2<Float>(0.2, 0.2)
    let target = SIMD2<Float>(0.9, 0.9) // far outside r_acq
    let rAcq: Float = 0.05

    let out = rotation.rotate(measurement: z, cursor: cursor, target: target, acquisitionRadius: rAcq)

    #expect(out == z)
    #expect(out.x.isFinite)
    #expect(out.y.isFinite)
  }

  /// Test 5 (FINITENESS): the output is always finite for finite inputs (never NaN/Inf). Covers the
  /// rotating branch and the degenerate target == cursor case (‖d‖ → 0; the dist > r_acq gate with a
  /// positive r_acq guards the divide and forces passthrough).
  @Test("finiteness: finite inputs → finite output across branches")
  func finiteForFiniteInputs() {
    let rotation = IntentRotation()
    let cursor = SIMD2<Float>(0.5, 0.5)

    // Rotating branch.
    let out1 = rotation.rotate(
      measurement: SIMD2<Float>(0.4, -0.3),
      cursor: cursor,
      target: SIMD2<Float>(0.9, 0.1),
      acquisitionRadius: 0.05
    )
    #expect(out1.x.isFinite && out1.y.isFinite)

    // Degenerate: target == cursor (dist == 0). With a positive r_acq the gate (dist > r_acq) is
    // false, so it must passthrough — NOT divide by zero.
    let out2 = rotation.rotate(
      measurement: SIMD2<Float>(0.4, -0.3),
      cursor: cursor,
      target: cursor,
      acquisitionRadius: 0.05
    )
    #expect(out2.x.isFinite && out2.y.isFinite)
    #expect(out2 == SIMD2<Float>(0.4, -0.3))
  }
}
