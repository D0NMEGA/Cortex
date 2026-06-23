// FittsThroughput — the Soukoreff & MacKenzie 2004 ISO 9241-9 effective-width Fitts THROUGHPUT
// math (REFIT-03, D-09). Pure value functions, no I/O, unit-testable.
//
// ## The metric (07-RESEARCH §4.2 — handed verbatim)
// ```
// TP  = IDe / MT                       (bits/second; the "BPS" this phase reports)
// IDe = log2( De / We + 1 )            (effective index of difficulty, Shannon form)
// We  = 4.133 · SDx                    (effective width; 4.133 = √(2πe), the 96%-spread constant)
// ```
// - `De`  = mean EFFECTIVE movement distance (actual start→endpoint per trial).
// - `MT`  = mean movement time per trial (seconds).
// - `SDx` = standard deviation of the endpoint coordinates PROJECTED ONTO THE TASK (movement) AXIS —
//   the scatter of where the cursor actually LANDED, NOT the nominal target width. Using effective
//   width (adjusting for the speed-accuracy tradeoff the subject actually struck) is precisely what
//   makes the number defensible to a Neuralink-grade reviewer (07-RESEARCH §4.2, §7 pitfall 3).
// - Aggregate by MEAN-OF-MEANS across conditions/target-amplitudes (per-condition `TP`, then average
//   those) — NOT a pooled all-trials average (the ISO standard's recommended aggregation).
//
// ## ⚠ This is S&M-2004 Fitts throughput, NOT the Webgrid bitrate (07-RESEARCH §4.3 — load-bearing)
// `TP = IDe/MT` is a DIFFERENT metric from the Neuralink/BrainGate Webgrid bitrate
// (`log2(N)·(correct−incorrect)/time`). The 4.16 / 8.5 reference numbers are Webgrid-bitrate; the
// Phase-7 TP number MUST NOT be compared to them (that apples-to-oranges leaderboard comparison is
// Phase 8 SC#5 / PERF-01/02, deferred per D-13). See `07-bps-evidence.md` for the framing.
//
// ## Hot-path note (off the policed path, but kept Foundation-free anyway)
// This file lives under `Packages/CortexReFIT/Sources/CortexReFIT` (which `hotpath-policy.sh` scans),
// so it stays `simd`-only — `log2`/`sqrt`/`Float.pi` are C-math free functions exposed via the simd
// module, so no Obj-C-runtime framework import is required. It is MEASUREMENT/harness math (NOT on
// the audio hot path), computed in `Double` for accuracy, but framework-free so the policed dir stays
// clean. (Comments deliberately avoid the literal forbidden tokens so the `grep -F` gate that now
// scans this dir does not false-positive on the prose — mirrors the Plan-02 KalmanFilter note.)
import simd

/// Pure Soukoreff & MacKenzie 2004 effective-width Fitts throughput math (D-09). A stateless value
/// namespace — every function is a closed-form transform of its inputs, deterministic, no I/O.
public nonisolated enum FittsThroughput {
  /// The ISO 9241-9 effective-width constant `4.133 = √(2πe)` — the multiplier that converts an
  /// endpoint-scatter standard deviation into the width spanning ~96% of the hits (the basis of the
  /// effective-width adjustment, S&M-2004). Exposed so the evidence artifact and tests reference the
  /// same literal.
  public static let effectiveWidthConstant: Double = 4.133

  /// Effective target width `We = 4.133 · SDx` from the endpoint-scatter SD on the movement axis.
  ///
  /// - Parameter sdx: standard deviation of the endpoint coordinates projected onto the task
  ///   (movement) axis — the *actual* landing scatter, not the nominal cell width.
  /// - Returns: the effective width `We` in the same units as `sdx`.
  public static func effectiveWidth(sdx: Double) -> Double {
    effectiveWidthConstant * sdx
  }

  /// Effective index of difficulty `IDe = log2(De/We + 1)` (Shannon form).
  ///
  /// - Parameters:
  ///   - de: mean effective movement distance (start→endpoint), same units as `we`.
  ///   - we: effective width (``effectiveWidth(sdx:)``), strictly positive.
  /// - Returns: the effective ID in bits. Guards a non-positive `we` (→ 0 bits) so a degenerate
  ///   zero-scatter condition cannot divide-by-zero or return a non-finite ID.
  public static func indexOfDifficulty(de: Double, we: Double) -> Double {
    guard we > 0 else { return 0 }
    return log2(de / we + 1.0)
  }

  /// Throughput `TP = IDe / MT` (bits per second) — the per-condition "BPS".
  ///
  /// - Parameters:
  ///   - ide: the effective index of difficulty (bits).
  ///   - mt: the mean movement time for the condition (seconds), strictly positive.
  /// - Returns: bits/second. Guards a non-positive `mt` (→ 0) so an empty/degenerate condition is
  ///   well-defined rather than non-finite.
  public static func throughput(ide: Double, mt: Double) -> Double {
    guard mt > 0 else { return 0 }
    return ide / mt
  }

  /// Mean-of-means aggregation across conditions: the arithmetic mean of the PER-CONDITION
  /// throughputs — NOT a pooled all-trials average (S&M-2004's recommended aggregation, 07-RESEARCH
  /// §4.2). Pooling would silently weight a condition with more trials more heavily; averaging the
  /// condition means gives every condition equal weight.
  ///
  /// - Parameter perConditionTP: one throughput per condition (already per-condition aggregated).
  /// - Returns: the mean of those condition throughputs, or 0 if there are no conditions.
  public static func meanOfMeans(perConditionTP: [Double]) -> Double {
    guard !perConditionTP.isEmpty else { return 0 }
    return perConditionTP.reduce(0, +) / Double(perConditionTP.count)
  }

  // MARK: - Per-condition aggregation from raw trials

  /// One acquired trial's measured quantities (the inputs the per-condition throughput is built from).
  public struct Trial: Sendable, Equatable {
    /// Effective movement distance: ‖endpoint − start‖ (the actual reach length).
    public let effectiveDistance: Double
    /// Movement time in seconds (ticks·dt until the dwell was satisfied).
    public let movementTime: Double
    /// Endpoint coordinate projected onto the movement axis (start→target unit vector) — the scalar
    /// whose across-trial SD is `SDx`. Projecting onto the task axis is the S&M-2004 convention.
    public let endpointOnAxis: Double

    public init(effectiveDistance: Double, movementTime: Double, endpointOnAxis: Double) {
      self.effectiveDistance = effectiveDistance
      self.movementTime = movementTime
      self.endpointOnAxis = endpointOnAxis
    }
  }

  /// Population (N-divisor) standard deviation of a sample — the endpoint-scatter SD feeding `We`.
  /// (Population, not sample/`N−1`: the endpoints ARE the full set of observations for the condition,
  /// and S&M's effective-width uses the spread of the realized endpoints.) Returns 0 for < 2 values.
  public static func standardDeviation(_ values: [Double]) -> Double {
    let n = values.count
    guard n >= 2 else { return 0 }
    let mean = values.reduce(0, +) / Double(n)
    let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)
    return variance.squareRoot()
  }

  /// The per-condition throughput from a condition's acquired trials, the full S&M-2004 effective-
  /// width chain: `We = 4.133·SD(endpointOnAxis)`, `IDe = log2(meanDe/We + 1)`, `TP = IDe/meanMT`.
  ///
  /// Uses the EFFECTIVE width from the endpoint scatter (not nominal target width — §7 pitfall 3).
  /// Returns 0 for a condition with no acquired trials.
  public static func conditionThroughput(trials: [Trial]) -> Double {
    guard !trials.isEmpty else { return 0 }
    let n = Double(trials.count)
    let meanDe = trials.reduce(0.0) { $0 + $1.effectiveDistance } / n
    let meanMT = trials.reduce(0.0) { $0 + $1.movementTime } / n
    let sdx = standardDeviation(trials.map(\.endpointOnAxis))
    let we = effectiveWidth(sdx: sdx)
    let ide = indexOfDifficulty(de: meanDe, we: we)
    return throughput(ide: ide, mt: meanMT)
  }
}
