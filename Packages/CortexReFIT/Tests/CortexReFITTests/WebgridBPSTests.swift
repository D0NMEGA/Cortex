// PERF-01 / D-11 / D-13 — the Neuralink/BrainGate Webgrid information-rate BITRATE math.
//
// These tests are the REAL correctness guard for the Webgrid BPS formula (08-05-PLAN Task 1,
// 08-RESEARCH §0.4/§6). The `formula` string literal written into webgrid_bps.json is merely a
// human-readable DISCLOSURE pin asserted by bps-policy.sh — it is NOT the executed code path; THIS
// suite pins the executed math:
//
//   B = max(0, log2(N) × (Sc − Si) / t)
//
// with N = 900 for the 30×30 grid (incl. the delete/cancel key). The five behaviors:
//
//   1. clean-run value: bitsPerSecond(n:900, correct:100, incorrect:0, seconds:60) ≈ log2(900)·100/60.
//   2. the MANDATORY max(0,…) clamp BITES — a net-negative (Sc−Si)<0 returns 0.0, never a negative
//      bitrate (08-RESEARCH §0.4 corrects CONTEXT D-11's omission of the clamp — the load-bearing test).
//   3. targetBits(n:900) ≈ 9.8138 (the log2(N) normalization); n<2 → 0 (no log2 of ≤1).
//   4. seconds ≤ 0 guard → 0 (no divide-by-zero / non-finite).
//   5. gridTargetCount(rows:30, cols:30) == 900 (the 30×30 incl-delete-key convention, §6).
//
// ## ⚠ This is the Webgrid BITRATE — DISTINCT from FittsThroughput's TP = IDe/MT (the metric-naming
// honesty mirrored from Phase 7). The Webgrid BPS is the leaderboard-comparable metric (vs BrainGate
// 6×6 4.16 / Neuralink P1 8.5); the S&M-2004 Fitts-TP is the secondary cross-check (PERF-03). The
// `log2(N)` normalization is exactly what makes a 30×30 result comparable to a 6×6 one.
//
// WebgridBPS is pure value math (Foundation-free `import simd` — it lives in the hotpath-policed
// CortexReFIT dir, so it stays `import simd`-only; `log2` comes from the C math lib via simd). The
// suite is `nonisolated` (pure value type).
import Testing
import simd

@testable import CortexReFIT

@Suite("PERF-01: Webgrid information-rate BPS = max(0, log2(N)·(Sc−Si)/t)")
struct WebgridBPSTests {
  /// Double-math tolerance — tight enough to catch a wrong formula (natural-log vs log2, a missing
  /// normalization), generous enough for floating-point.
  private static let tol = 1e-9

  // MARK: - Test 1: clean-run value

  /// bitsPerSecond(n:900, correct:100, incorrect:0, seconds:60) = log2(900)·(100−0)/60.
  /// log2(900) ≈ 9.8138 → ≈ 16.3563 bits/s. The formula computes correctly for a clean run.
  @Test("clean run: B = log2(N)·Sc/t for N=900, Sc=100, Si=0, t=60")
  func cleanRunValue() {
    let b = WebgridBPS.bitsPerSecond(n: 900, correct: 100, incorrect: 0, seconds: 60)
    let expected = log2(900.0) * 100.0 / 60.0
    #expect(abs(b - expected) < Self.tol)
    // Sanity anchor: ≈ 16.3563 bits/s (catches a gross normalization error). Exact: log2(900)·100/60.
    #expect(abs(b - 16.356_301_985_361_73) < 1e-9)
  }

  // MARK: - Test 2: the MANDATORY max(0,…) clamp bites (the load-bearing honesty test)

  /// A net-negative selection count (Sc − Si < 0) must clamp to 0.0 — NEVER a negative bitrate
  /// (08-RESEARCH §0.4; CONTEXT D-11 omitted this clamp). For Sc=5, Si=20 → (5−20)=−15 < 0 → 0.0.
  @Test("clamp BITES: net-negative (Sc−Si)<0 returns 0.0, not a negative bitrate")
  func clampBitesOnNetNegative() {
    let b = WebgridBPS.bitsPerSecond(n: 900, correct: 5, incorrect: 20, seconds: 30)
    #expect(b == 0.0)
    // And it is NOT merely small-negative-rounded — the raw unclamped value would be clearly < 0.
    let unclamped = log2(900.0) * Double(5 - 20) / 30.0
    #expect(unclamped < 0.0) // proves the input genuinely drives the unclamped formula negative
  }

  // MARK: - Test 3: targetBits = log2(N), guarded for N<2

  /// targetBits(n:900) = log2(900) ≈ 9.8138 bits/correct-selection (the log2(N) normalization).
  /// n<2 returns 0 (no log2 of a value ≤ 1, which would be ≤ 0 / non-finite).
  @Test("targetBits(n) = log2(N); n<2 → 0")
  func targetBitsLog2WithGuard() {
    #expect(abs(WebgridBPS.targetBits(n: 900) - log2(900.0)) < Self.tol)
    #expect(abs(WebgridBPS.targetBits(n: 900) - 9.813_781_191_217_037) < 1e-9)
    // Degenerate guards: n = 1 → log2(1) = 0 would be fine, but n ≤ 1 is meaningless for a grid →
    // the guard returns 0 for n<2 (and never attempts log2 of 0 / a negative).
    #expect(WebgridBPS.targetBits(n: 1) == 0)
    #expect(WebgridBPS.targetBits(n: 0) == 0)
    #expect(WebgridBPS.targetBits(n: -5) == 0)
  }

  // MARK: - Test 4: seconds ≤ 0 guard (no divide-by-zero / non-finite)

  /// seconds ≤ 0 → 0 (the divide-by-zero / non-finite guard).
  @Test("seconds ≤ 0 → 0 (divide-by-zero guard)")
  func secondsGuard() {
    #expect(WebgridBPS.bitsPerSecond(n: 900, correct: 100, incorrect: 0, seconds: 0) == 0)
    #expect(WebgridBPS.bitsPerSecond(n: 900, correct: 100, incorrect: 0, seconds: -1) == 0)
    // Result is always finite (never NaN/Inf) even at the guard boundary.
    #expect(WebgridBPS.bitsPerSecond(n: 900, correct: 100, incorrect: 0, seconds: 0).isFinite)
  }

  // MARK: - Test 5: gridTargetCount(30, 30) == 900 (incl. delete/cancel key)

  /// The 30×30 grid INCLUDING the delete/cancel cell is N = 900 selectable targets (08-RESEARCH §6).
  @Test("gridTargetCount(rows:30, cols:30) == 900 (incl. delete key)")
  func gridTargetCountIs900() {
    #expect(WebgridBPS.gridTargetCount(rows: 30, cols: 30) == 900)
    // And the leaderboard anchors are the documented Webgrid-bitrate reference literals (D-12).
    #expect(WebgridBPS.referencePeakBPS == 8.5)
    #expect(WebgridBPS.brainGate6x6BPS == 4.16)
  }
}
