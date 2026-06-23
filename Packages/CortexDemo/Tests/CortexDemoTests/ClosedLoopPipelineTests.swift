@testable import CortexDemo

// ClosedLoopPipelineTests — Phase 8 (SYS-06, D-10): the deterministic end-to-end harness proving the
// synthetic-spike → NDT1 → ReFIT-Kalman → CursorIntegrator → 30×30 webgrid loop is wired end-to-end
// with the DECODER + KALMAN genuinely in the loop (NOT the oscillator-velocity shortcut).
//
// The 5 behaviors (08-03-PLAN Task 1):
//   1. Synthetic mode (no CORTEX_MODEL_URL): the loop reaches a target cell (a webgrid HIT) — the
//      IPC→decode→Kalman→integrate→webgrid assembly is wired without the gitignored model.
//   2. Model-backed path: skips cleanly when the model is absent, but the NeuralDecoder.decode code
//      path is present + compiled (asserted structurally) so the NDT1-in-loop path is real (D-10).
//   3. Determinism: same seed → byte-identical cursor trajectory + same hit/miss across two runs.
//   4. ReFIT-Kalman genuinely applied: the Kalman+rotation arm reaches the target where the raw-
//      passthrough arm does NOT (the filter is in the loop, not bypassed — mirrors the Phase-7 ablation).
//   5. SyntheticSpikeSource: emits (numBins, 96)-shaped fp16 windows, deterministic per seed.
//
// Swift Testing; skip-clean when the model is absent (mirrors VelocityOutputTests). The library is
// MainActor-isolated, so the suite is @MainActor. `@Test("description")` + camelCase function names
// mirror the committed CortexReFITTests / CortexDecoderTests convention.
import Foundation
import simd
import Testing

@Suite("SYS-06 / D-10: synthetic-spike -> NDT1 -> ReFIT -> webgrid closed loop")
@MainActor
struct ClosedLoopPipelineTests {
  /// A reachable target on a 30×30 cell center used across the HIT tests. Chosen so the ReFIT
  /// (Kalman+rotation) arm reaches it comfortably within the dwell-to-select budget while the raw-
  /// passthrough arm misses (the Test-4 ablation) — a deterministic, well-margined separation.
  static let reachableTarget = SIMD2<Float>((Float(13) + 0.5) / 30.0, (Float(13) + 0.5) / 30.0)
  static let testSeed: UInt64 = 0xC0FFEE

  // MARK: Test 1 — the loop reaches a target cell (a webgrid HIT) in synthetic mode.

  @Test("Test 1: synthetic-mode closed loop reaches the target cell (a webgrid HIT)")
  func syntheticLoopReachesTarget() {
    let pipeline = ClosedLoopPipeline(seed: Self.testSeed, target: Self.reachableTarget)
    // No CORTEX_MODEL_URL ⇒ the synthetic decode fallback runs (the clean-clone / CI path).
    #expect(!pipeline.isModelBacked, "with no model the pipeline must run the synthetic decode fallback")

    let result = pipeline.runToHit(seed: Self.testSeed, target: Self.reachableTarget)
    #expect(result.hit, "the synthetic-spike -> decode -> Kalman -> integrate -> webgrid loop must reach a HIT")
    #expect(!result.positions.isEmpty, "the loop must produce a cursor trajectory")
    // Every sampled position is the integrator's clamped, in-[0,1] output (the seam guarantee).
    for point in result.positions {
      #expect(point.x >= 0 && point.x <= 1 && point.y >= 0 && point.y <= 1, "positions stay in the [0,1] grid")
      #expect(point.x.isFinite && point.y.isFinite, "positions are always finite")
    }
  }

  // MARK: Test 2 — the model-backed NDT1 path is present + compiled; skips cleanly when absent.

  @Test("Test 2: NDT1 model-backed decode path is present + compiled (skips cleanly when no model)")
  func modelBackedDecodePathPresent() {
    // The .mlpackage is gitignored; resolve from CORTEX_MODEL_URL and SKIP cleanly when absent so the
    // suite stays green on a clean clone / CI (mirrors VelocityOutputTests). The NeuralDecoder.decode
    // call site is COMPILED regardless (in ClosedLoopPipeline.decodeWithModel) — the structural grep in
    // the acceptance criteria proves it is present; here we exercise it ONLY when a real model exists.
    guard let modelURL = ClosedLoopPipeline.modelURLFromEnvironment() else {
      return // model artifact not built — export CORTEX_MODEL_URL to exercise the NDT1-in-loop path.
    }
    let pipeline = ClosedLoopPipeline(seed: Self.testSeed, target: Self.reachableTarget, modelURL: modelURL)
    #expect(pipeline.isModelBacked, "with a real CORTEX_MODEL_URL the pipeline routes spikes through NDT1 (D-10)")
    // Drive a few ticks through the model-backed loop; the decode must report it ran NDT1.
    var anyModelTick = false
    for _ in 0 ..< 4 {
      let state = pipeline.tick()
      anyModelTick = anyModelTick || state.decodedByModel
      #expect(state.position.x.isFinite && state.position.y.isFinite)
    }
    #expect(anyModelTick, "the model-backed pipeline must report NDT1 decode ran (NDT1 genuinely in loop)")
  }

  // MARK: Test 3 — determinism: same seed → byte-identical trajectory + same hit/miss.

  @Test("Test 3: deterministic — same seed reproduces the byte-identical trajectory + hit/miss")
  func deterministicAcrossRuns() {
    let first = ClosedLoopPipeline(seed: Self.testSeed, target: Self.reachableTarget)
      .runToHit(seed: Self.testSeed, target: Self.reachableTarget)
    let second = ClosedLoopPipeline(seed: Self.testSeed, target: Self.reachableTarget)
      .runToHit(seed: Self.testSeed, target: Self.reachableTarget)

    #expect(first.hit == second.hit, "the hit/miss outcome is deterministic for a fixed seed")
    #expect(first.ticks == second.ticks, "the tick count is deterministic for a fixed seed")
    #expect(first.positions.count == second.positions.count, "the trajectory length is deterministic")
    // Bit-exact: the SIMULATION path has no RNG/clock, so the float trajectory is byte-identical.
    #expect(
      first.positions == second.positions,
      "the cursor trajectory is byte-identical across two runs (no RNG/clock)"
    )
  }

  // MARK: Test 4 — the ReFIT-Kalman stage is genuinely applied (vs raw passthrough).

  @Test("Test 4: ReFIT-Kalman is genuinely in the loop — the rotation arm HITs where raw does not")
  func kalmanGenuinelyApplied() {
    // Same synthetic decode + target; the ONLY difference is the filter stage (the Phase-7 ablation).
    let refit = ClosedLoopPipeline.simulate(seed: Self.testSeed, target: Self.reachableTarget, arm: .refit)
    let raw = ClosedLoopPipeline.simulate(seed: Self.testSeed, target: Self.reachableTarget, arm: .raw)

    // The Kalman+rotation arm reaches the target; the raw-passthrough arm (no filter) does not —
    // proving the filter is genuinely applied in the loop, not bypassed.
    #expect(refit.hit, "the ReFIT (Kalman+rotation) arm must reach the target")
    #expect(!raw.hit, "the raw-passthrough arm (no filter) must NOT reach the target on the same decode")
    // The trajectories must differ (the filter changes the cursor path — it is not a no-op).
    #expect(
      refit.positions != raw.positions,
      "the Kalman arm produces a different trajectory than raw (filter applied)"
    )
  }

  // MARK: Test 5 — SyntheticSpikeSource emits (numBins, 96) fp16 windows, deterministic per seed.

  @Test("Test 5: SyntheticSpikeSource emits (numBins, 96) fp16 windows, deterministic per seed")
  func syntheticSpikeSourceShapeAndDeterminism() {
    let source = SyntheticSpikeSource(seed: Self.testSeed)
    #expect(source.channels == 96, "the spike source models the 96-channel Indy/Loco contract (DEC-02)")

    let window0 = source.window(0)
    #expect(window0.count == source.numBins * source.channels, "the window is (numBins, 96)-shaped")
    // fp16 spike counts are non-negative + finite (rectified rates).
    for value in window0 {
      #expect(value.isFinite, "spike counts are finite")
      #expect(value >= 0, "spike counts are non-negative")
    }
    // Deterministic per (seed, windowIndex): the same window index reproduces byte-identical bytes.
    #expect(source.window(0) == window0, "window(0) is reproducible (deterministic, no RNG/clock)")
    #expect(source.window(3) == source.window(3), "window(3) is reproducible")
    // Distinct windows differ (the stream drifts over time — not a constant).
    #expect(source.window(0) != source.window(50), "the stream varies across windows (a time-varying pattern)")
    // A different seed gives a different stream (each individually reproducible).
    let other = SyntheticSpikeSource(seed: Self.testSeed ^ 0xFF)
    #expect(other.window(0) != window0, "a different seed yields a different (but reproducible) stream")
  }
}
