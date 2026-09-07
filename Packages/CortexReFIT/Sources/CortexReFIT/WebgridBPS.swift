// WebgridBPS — the Neuralink / BrainGate Webgrid information-rate BITRATE math (PERF-01, D-11/D-13).
// Pure value functions, no I/O, unit-testable. Mirrors FittsThroughput's stateless-namespace style.
//
// ## The metric (08-RESEARCH §0.4 / §6 — handed verbatim)
// ```
// B = max(0, log2(N) × (Sc − Si) / t)        (bits/second — the Webgrid "BPS")
// ```
// - `N`  = number of selectable targets INCLUDING the delete/cancel key. For a 30×30 webgrid,
//          N = 900 ⇒ `log2(900) ≈ 9.81` bits/correct-selection. This `log2(N)` normalization is
//          what makes a 30×30 result comparable to BrainGate's 4.16 reference (T5 dense 9x9 grid).
// - `Sc` = correct selections, `Si` = incorrect selections, `t` = elapsed seconds.
// - **The `max(0, …)` clamp is MANDATORY** (08-RESEARCH §0.4) — never report a negative bitrate.
//   CONTEXT D-11 OMITTED this clamp; RESEARCH §0.4 corrects it. This is load-bearing: a net-negative
//   selection count (more incorrect than correct) must read as 0 bits/s, not a nonsensical negative.
//   `WebgridBPSTests` Test 2 asserts the clamp bites; `bps-policy.sh` requires the `Swift.max(0,` token.
//
// ## ⚠ This is the Webgrid BITRATE, NOT the S&M-2004 Fitts throughput (the metric-naming honesty)
// `B = log2(N)·(Sc−Si)/t` is a DIFFERENT metric from `FittsThroughput.throughput` (`TP = IDe/MT`,
// effective-width). The well-known leaderboard numbers — BrainGate 4.16, Neuralink P1 8.5 — are
// **Webgrid bitrate**, which is what THIS type computes (the leaderboard-comparable metric, PERF-01).
// The S&M-2004 Fitts-TP (Phase 7, `FittsThroughput`) is the **secondary cross-check** (PERF-03). The
// two are emitted side-by-side by `CortexReFITBench`; do not conflate them (mirrors the Phase-7
// `FittsThroughput` "this is NOT the Webgrid bitrate" framing — now reciprocated here).
//
// ## Hot-path note (off the policed path, but kept Foundation-free anyway)
// This file lives under `Packages/CortexReFIT/Sources/CortexReFIT` (which `hotpath-policy.sh` scans),
// so it stays `simd`-only — `log2` is a C-math free function exposed via the simd module, so no
// Obj-C-runtime framework import is required. It is MEASUREMENT/harness math (NOT on the audio hot
// path), computed in `Double` for accuracy, but framework-free so the policed dir stays clean.
import simd

/// Pure Neuralink/BrainGate Webgrid information-rate BITRATE math (D-11). A stateless value namespace —
/// every function is a closed-form transform of its inputs, deterministic, no I/O. DISTINCT from
/// ``FittsThroughput`` (TP = IDe/MT): this is the `log2(N)`-normalized bitrate, the leaderboard metric.
public nonisolated enum WebgridBPS {
  /// Neuralink P1 (Noland Arbaugh) Webgrid bitrate this repo has cited since Phase 7 - **8.5 BPS**.
  /// This figure is NOT independently sourceable to a Neuralink primary: Neuralink's own May-2024
  /// post reports 8 BPS. Treat as an unsourced historical repo reference, not a confirmed measurement.
  /// Current public statement, neuralink.com/webgrid, retrieved 2026-09-05: "Our clinical trial
  /// participants have achieved over 10 BPS controlling a computer with their brain."
  /// Exposed so the evidence artifact and tests reference the SAME literal. The honest
  /// synthetic-replay number is reported WITH the gap toward this figure - NOT tuned toward it (D-12).
  public static let referencePeakBPS = 8.5

  /// BrainGate (Pandarinath et al. 2017, eLife 18554) Webgrid bitrate - **4.16 +/- 0.39 bps**,
  /// participant **T5 on the DENSE 9x9 grid**, 8 evaluation blocks. Verified against the paper's
  /// full text 2026-09-05. This is NOT a 6x6 number: the same paper's 6x6 figures are T6
  /// 2.2 +/- 0.4, T5 3.7 +/- 0.4 and T7 1.4 +/- 0.1 bps, and the 9x9 result "was significantly
  /// greater than the 6 x 6 performance". Reported honestly, NOT engineered toward as a pass bar
  /// (D-12). The repo previously labeled this constant `brainGate6x6BPS`; RD-09 corrected it.
  public static let brainGateDenseGridBPS = 4.16

  /// The same paper's 6x6 figure for the SAME participant (T5): **3.7 +/- 0.4 bps**. Exposed so a
  /// comparison against a 6x6 condition uses the 6x6 number rather than the 9x9 one.
  public static let brainGate6x6T5BPS = 3.7

  /// Why this repo's Webgrid BPS is NOT like-for-like with the reference figures it is reported
  /// beside. Verified against primary sources 2026-09-05 and against this repo's own harness.
  /// Three independent grounds, plus a fourth against Neuralink specifically:
  ///
  ///  1. FORMULA. Pandarinath et al. 2017 (eLife 18554) computes achieved bitrate with
  ///     `log2(N - 1)`. This repo pins `log2(N)`. Matching the `(correct - incorrect)` numerator
  ///     does not make them the same metric.
  ///  2. GRID. 4.16 is the participant-T5 DENSE 9x9 figure, not a 6x6 figure. The paper's 6x6
  ///     numbers are T6 2.2, T5 3.7, T7 1.4.
  ///  3. TASK. `CortexReFITBench/main.swift:283-285` makes incorrect selections STRUCTURALLY ZERO,
  ///     so `Si` is always 0 and this metric cannot express the speed-accuracy tradeoff that a
  ///     human point-and-click bitrate measures. `CortexReplayBench` inherits the same property.
  ///  4. NEURALINK. neuralink.com/webgrid describes its score as derived from net correct targets
  ///     per minute, grid size, AND the number of click types. This harness is single-click-type
  ///     and its disclosed formula omits that term.
  ///
  /// This is a DISCLOSURE, not a formula change: `Tools/scripts/bps-policy.sh` pins the formula and
  /// byte-diffs the Phase-7 `refit_bps.json` fixture, which D-09 exists to protect. Editing the
  /// formula to chase parity would break that fixture and destroy the regression signal.
  public static let nonComparabilityDisclosure = """
  this repo's Webgrid BPS is not like-for-like with either reference: the formula differs \
  (log2(N) here versus log2(N-1) in eLife 18554), the grid differs (T5 dense 9x9, not 6x6), \
  the harness makes incorrect selections structurally zero so Si is always 0, and Neuralink's \
  current published score adds a click-types term this single-click-type harness omits
  """

  /// `log2(N)` — the bits-per-correct-selection normalization (the information content of choosing
  /// one of `N` equiprobable targets). For N = 900 (a 30×30 grid incl. the delete key) ≈ 9.81 bits.
  ///
  /// - Parameter n: the number of selectable targets (≥ 2 to be meaningful).
  /// - Returns: `log2(N)` bits, or 0 for `n < 2` (a grid with < 2 targets has no choice information,
  ///   and the guard avoids `log2` of a value ≤ 1, which would be ≤ 0 / undefined).
  public static func targetBits(n: Int) -> Double {
    guard n >= 2 else { return 0 }
    return log2(Double(n))
  }

  /// The number of selectable targets on a `rows × cols` webgrid INCLUDING the delete/cancel cell —
  /// i.e. `rows · cols` (08-RESEARCH §6: the 30×30 grid's delete key is one of the 900 cells, so the
  /// full grid count IS the selectable-target count `N`). For the canonical 30×30 grid this is 900.
  ///
  /// - Parameters:
  ///   - rows: grid row count.
  ///   - cols: grid column count.
  /// - Returns: `rows * cols` (the 900-cell incl-delete-key convention for 30×30).
  public static func gridTargetCount(rows: Int, cols: Int) -> Int {
    rows * cols
  }

  /// The Webgrid information-rate bitrate `B = max(0, log2(N) × (Sc − Si) / t)` (bits/second).
  ///
  /// The `Swift.max(0, …)` clamp is **MANDATORY** (08-RESEARCH §0.4 — CONTEXT D-11 omitted it): a
  /// net-negative selection count (`Sc < Si`) must clamp to 0, never report a negative bitrate.
  ///
  /// - Parameters:
  ///   - n: selectable-target count `N` (≥ 2; see ``targetBits(n:)``).
  ///   - correct: `Sc`, the number of correct selections.
  ///   - incorrect: `Si`, the number of incorrect selections.
  ///   - seconds: `t`, elapsed seconds (strictly positive).
  /// - Returns: bits/second, clamped to be non-negative. Guards a non-positive `seconds` (→ 0) so a
  ///   degenerate/empty window is well-defined rather than a divide-by-zero / non-finite value.
  public static func bitsPerSecond(n: Int, correct: Int, incorrect: Int, seconds: Double) -> Double {
    guard seconds > 0 else { return 0 }
    let net = Double(correct - incorrect)
    // MANDATORY clamp (08-RESEARCH §0.4): never a negative bitrate. Load-bearing — do NOT remove
    // (WebgridBPSTests Test 2 + bps-policy.sh both assert this `Swift.max(0,` is present and bites).
    return Swift.max(0, targetBits(n: n) * net / seconds)
  }
}
