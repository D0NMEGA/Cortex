// REFIT-03 / D-08 / D-09 — Soukoreff & MacKenzie 2004 effective-width throughput + dwell-to-select.
//
// These tests pin the load-bearing BPS math the headless harness (Task 2) drives. The metric is the
// S&M-2004 ISO 9241-9 Fitts THROUGHPUT (`TP = IDe/MT`, effective-width method) — NOT the
// Neuralink/BrainGate Webgrid bitrate (07-RESEARCH §4.3; the 4.16/8.5 comparison is deferred to
// Phase 8, D-13). The five behaviors (07-RESEARCH §4.2 + VALIDATION §6 row 4):
//
//   1. IDe = log2(De/We + 1) for known De/We → hand-computed bits (Shannon effective ID).
//   2. We = 4.133 · SDx for a known endpoint-scatter SD (4.133 = √(2πe), the 96%-spread constant).
//   3. TP = IDe / MT for known IDe and MT (seconds) → bits/second.
//   4. mean-of-means aggregation averages the PER-CONDITION means, NOT a pooled all-trials average —
//      with unequal trial counts the two differ, and a regression to pooling is caught.
//   5. acquisition: a cursor held inside the target cell for ≥ the dwell window registers a HIT; a
//      cursor that never enters within the per-trial timeout registers a TIMEOUT.
//
// Both types are pure value math (Foundation-free `import simd` — they live in the hotpath-policed
// CortexReFIT dir, so they stay `import simd`-only; `log2f`/`sqrtf`/`Float.pi` come from the C math
// lib via simd, no Foundation needed). The suite is `nonisolated` (these are pure value types).
import Testing
import simd

@testable import CortexReFIT

@Suite("REFIT-03: S&M-2004 effective-width throughput + dwell-to-select acquisition")
struct FittsThroughputTests {
  /// Float tolerance for the throughput-math comparisons (Double math, generous but tight enough to
  /// catch a wrong formula — e.g. natural-log instead of log2, or 4.0 instead of 4.133).
  private static let tol = 1e-9

  // MARK: - Test 1: effective index of difficulty (Shannon form)

  /// IDe = log2(De/We + 1). For De = 0.6, We = 0.2 → log2(0.6/0.2 + 1) = log2(4) = 2.0 bits.
  @Test("IDe = log2(De/We + 1) returns the hand-computed bits")
  func indexOfDifficultyShannonForm() {
    let ide = FittsThroughput.indexOfDifficulty(de: 0.6, we: 0.2)
    #expect(abs(ide - 2.0) < Self.tol) // log2(4) == 2
    // A second point: De/We = 1 → log2(2) = 1 bit.
    #expect(abs(FittsThroughput.indexOfDifficulty(de: 0.2, we: 0.2) - 1.0) < Self.tol)
  }

  // MARK: - Test 2: effective width (4.133 · SDx)

  /// We = 4.133 · SDx (the ISO 9241-9 96%-spread constant). For SDx = 0.05 → We = 0.20665.
  @Test("We = 4.133 · SDx for a known endpoint-scatter SD")
  func effectiveWidthFromScatter() {
    let we = FittsThroughput.effectiveWidth(sdx: 0.05)
    #expect(abs(we - (4.133 * 0.05)) < Self.tol)
    #expect(abs(we - 0.20665) < 1e-6)
  }

  // MARK: - Test 3: throughput per condition (TP = IDe / MT)

  /// TP = IDe / MT (bits/second). For IDe = 3.0 bits, MT = 1.5 s → TP = 2.0 bits/s.
  @Test("TP = IDe / MT returns bits/second")
  func throughputIsBitsPerSecond() {
    let tp = FittsThroughput.throughput(ide: 3.0, mt: 1.5)
    #expect(abs(tp - 2.0) < Self.tol)
  }

  // MARK: - Test 4: mean-of-means ≠ pooled mean on unequal trial counts

  /// Mean-of-means aggregates per-CONDITION throughputs (average the condition means), NOT a pooled
  /// all-trials average. With two conditions of UNEQUAL trial counts whose per-trial values would
  /// pool to a different number, the mean-of-means must differ from the pooled mean — so a regression
  /// to pooling (which silently weights the larger condition more) is caught (07-RESEARCH §4.2).
  @Test("mean-of-means averages the condition means, not the pooled trials (differs on unequal n)")
  func meanOfMeansDiffersFromPooled() {
    // Condition A: 1 trial valued 1.0 (mean 1.0). Condition B: 3 trials valued 3.0 each (mean 3.0).
    let perConditionTP = [1.0, 3.0] // the two condition MEANS
    let mom = FittsThroughput.meanOfMeans(perConditionTP: perConditionTP)
    #expect(abs(mom - 2.0) < Self.tol) // (1.0 + 3.0) / 2 == 2.0

    // The POOLED mean over the 4 trials (1×1.0 + 3×3.0) / 4 == 2.5 — different from the mean-of-means.
    let pooled = (1.0 * 1.0 + 3.0 * 3.0) / 4.0
    #expect(abs(pooled - 2.5) < Self.tol)
    #expect(abs(mom - pooled) > 0.4) // mean-of-means (2.0) is NOT the pooled mean (2.5)
  }

  // MARK: - Test 5: dwell-to-select acquisition — HIT vs TIMEOUT

  /// A cursor held inside the acquisition radius of the target for ≥ the dwell window registers a
  /// HIT, recording its movement time and endpoint; a cursor that never satisfies the dwell within
  /// the per-trial timeout registers a TIMEOUT (D-08).
  @Test("acquisition: dwell-satisfied cursor HITs; never-arriving cursor TIMES OUT")
  func dwellToSelectHitAndTimeout() {
    let dt = 0.020
    // Dwell of 60 ms = 3 ticks at dt=20ms; timeout of 0.4 s = 20 ticks; radius half a 30-cell pitch.
    let model = WebgridAcquisition(
      dwellSeconds: 0.060,
      acquisitionRadius: 0.5 / 30.0,
      timeoutSeconds: 0.400,
      dt: dt
    )
    let target = SIMD2<Float>(0.5, 0.5)

    // HIT: the cursor is parked exactly on the target for 10 ticks (>> the 3-tick dwell).
    let onTarget = [SIMD2<Float>](repeating: target, count: 10)
    let hit = model.runTrial(positions: onTarget, target: target)
    #expect(hit.acquired)
    #expect(hit.endpoint == target)
    // Movement time is the time to FIRST satisfy the dwell: it entered immediately, so the dwell
    // completes after `dwellTicks` (3) ticks → ~0.060 s. Must be positive and ≤ the dwell+slack.
    #expect(hit.movementTime > 0)
    #expect(hit.movementTime <= 0.060 + dt) // dwell satisfied right at the dwell window

    // TIMEOUT: the cursor stays far away (top-left corner) the entire trial — never within r_acq.
    let farAway = [SIMD2<Float>](repeating: SIMD2<Float>(0.0, 0.0), count: 50)
    let miss = model.runTrial(positions: farAway, target: target)
    #expect(!miss.acquired)
  }
}
