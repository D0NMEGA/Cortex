// CortexReFITBench — the headless deterministic 3-way ablation BPS harness + the SC#3 filter-step
// tail-latency bench (Plan 07-03, D-07/D-11/D-12, SC#3). Mirrors CortexDecoderBench's pattern.
//
// ## Pipeline per condition (07-RESEARCH §4.1)
//   seed-locked replay -> decoded (vx,vy) -> [ raw | Kalman-only | Kalman+rotation ]
//     -> CursorIntegrator -> 30×30 WebgridParams acquisition -> S&M-2004 throughput
// The THREE arms differ ONLY in the filter stage (D-12 — isolates rotation vs Kalman smoothing):
//   • raw            : feed the decoded velocity straight to the integrator (no filter).
//   • Kalman-only    : KalmanFilter.step with rotation DISABLED (target: nil).
//   • Kalman+rotation: KalmanFilter.step with the active target + acquisition radius (rotation on).
// All three run the IDENTICAL seed-locked replay + target sequence, so the delta is the filter's
// pure contribution (CONTEXT D-12 / specifics).
//
// ## Determinism (07-RESEARCH §7 pitfall 8 — load-bearing)
// NO wall-clock, NO RNG in the SIMULATION path. The decoded velocity is a closed-form function of
// (seed, tick index) modelled on LissajousProducer: it points toward the active target with a
// deterministic, index-driven directional+magnitude perturbation (a "noisy decoder"). Two runs on
// the same seed produce byte-identical results; refit_bps.json is written with .sortedKeys so the
// bytes are identical too. (ContinuousClock is used ONLY in --latency mode to time the step; it never
// drives the simulation or the BPS numbers.)
//
// ## Clean-clone / CI safety
// The held-out Indy R&D data is gitignored / absent here. With no data env/argv path and no --smoke
// flag, the bench prints a usage/skip message and exits 0 (mirrors CortexDecoderBench). The --smoke
// variant runs the deterministic synthetic seed-locked sequence, which still produces a valid
// raw/kalman_only/refit triple preserving refit >= raw for the committed JSON + the CI guard.
//
// ## SC#3 latency
// --latency times the filter step (predict -> rotate -> update) over n >= 10 000 ticks INLINE on the
// calling thread (NO Thread/pthread_create/DispatchQueue spawn — SC#3 "existing pthread, not a new
// thread"), builds a device-annotated LatencyHistogram, prints p50/p99/max. The Mac/M5-Pro number is
// CORROBORATING; the canonical iPad-M4 tail number is Manual-Only (07-VALIDATION). The bench asserts
// nothing on the latency VALUE — it records and prints (the constant-gain op is ~tens of simd FLOPs).
import CortexDecoder // LatencyHistogram (SC#3 tail-latency value type)
import CortexReFIT // KalmanFilter, IntentRotation, FittsThroughput, WebgridAcquisition
import CortexRender // CursorIntegrator, CursorVelocity, WebgridParams
import Foundation // JSONEncoder/.sortedKeys, FileManager, URL — bench is OFF the hot path (allowed here)
import simd

// MARK: - Configuration

/// The fixed seed for the committed deterministic run (recorded in refit_bps.json + the evidence).
let defaultSeed: UInt64 = 0xC0_FF_EE
/// Filter tick in seconds (20 ms — KalmanConstants.dt / the decode cadence).
let dt: Double = 0.020
/// Acquisition radius = ½ cell of the 30×30 grid in [0,1] space (07-RESEARCH §4.4 default).
let acquisitionRadius: Float = 0.5 / 30.0
/// Dwell to commit a selection (300 ms — 07-RESEARCH §4.4 default).
let dwellSeconds: Double = 0.30
/// Per-trial timeout (5 s — 07-RESEARCH §4.4 default).
let timeoutSeconds: Double = 5.0
/// Max ticks the cursor is allowed to reach a target (the per-trial sim budget = timeout / dt).
let maxTicksPerTrial = Int((timeoutSeconds / dt).rounded(.up))
/// SC#3 latency sample count (>= 10 000 — same bar as the decoder bench, 07-RESEARCH §5).
let latencyTicks = 10_000

// MARK: - CLI flags

let args = CommandLine.arguments
let isSmoke = args.contains("--smoke")
let isLatency = args.contains("--latency")
/// Trials per condition: a short-budget count in --smoke (still >= the SDx-stability floor while
/// staying CI-fast), the full count otherwise (07-RESEARCH §6 row 4: >= ~100 trials per condition).
let trialsPerCondition = isSmoke ? 120 : 256

/// Resolves the held-out Indy replay path from CORTEX_REFIT_REPLAY_URL (env) or the first non-flag
/// argv. Absent => nil (the --smoke synthetic path or the usage/skip exit handles it).
func resolveReplayURL() -> URL? {
  if let envPath = ProcessInfo.processInfo.environment["CORTEX_REFIT_REPLAY_URL"], !envPath.isEmpty {
    return URL(fileURLWithPath: envPath)
  }
  for arg in args.dropFirst() where !arg.hasPrefix("-") {
    return URL(fileURLWithPath: arg)
  }
  return nil
}

let usage = """
CortexReFITBench — headless deterministic 3-way ablation BPS harness (REFIT-03, D-07/D-12) + the
SC#3 filter-step tail-latency bench.

  No held-out Indy replay path was provided and --smoke was not passed, so there is no data to
  measure — exiting 0 (this is the expected path on a clean clone / CI, where the Indy R&D data is
  gitignored).

  Run the DETERMINISTIC synthetic ablation (no data needed — what produces the committed JSON):

    swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke

  There is NO real-data mode here. This bench is the SYNTHETIC regression fixture and its output is
  a byte-identity build gate (D-09). Setting CORTEX_REFIT_REPLAY_URL to an existing path exits 1
  rather than labelling synthetic numbers with a real session id (RD-09). The real-data four-arm
  ablation over the D-06 export lives in a separate executable:

    swift run --package-path Packages/CortexDemo CortexReplayBench --export <sidecar.json> --model <model.mlpackage>

  Measure the SC#3 filter-step tail latency over \(latencyTicks) ticks (add --latency):

    swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke --latency

  The 3-way ablation reports S&M-2004 Fitts throughput (TP = IDe/MT, effective-width) for raw /
  Kalman-only / Kalman+rotation on the IDENTICAL seed-locked replay, and writes refit_bps.json. That
  is S&M-2004 Fitts throughput, NOT the Neuralink/BrainGate Webgrid bitrate — do NOT compare it to
  the 4.16 / 8.5 reference numbers (that comparison is Phase 8, deferred per D-13).
"""

// MARK: - Deterministic synthetic replay (seed/index-driven — NO clock, NO RNG)

/// A reach: a start position and a target cell center, both in grid-normalised [0,1] space.
struct Reach {
  let start: SIMD2<Float>
  let target: SIMD2<Float>
}

/// A small deterministic hash of (seed, index) -> [0,1) — a closed-form value source for the reach
/// layout and the decoder perturbation (the LissajousProducer determinism contract: no RNG/clock).
/// SplitMix64 finalizer over (seed ^ index): a pure function, identical output for identical inputs.
func unitHash(_ seed: UInt64, _ index: UInt64) -> Double {
  var z = (seed &+ 0x9E37_79B9_7F4A_7C15) ^ (index &* 0x9E37_79B9_7F4A_7C15)
  z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
  z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
  z = z ^ (z >> 31)
  // Top 53 bits -> [0,1) double (standard uint64 -> unit-double construction).
  return Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0) // 2^-53
}

/// Generates `count` reaches deterministically from the seed — Indy-style center-out reaches mapped
/// onto the 30×30 grid (the targets are the dataset's own reach targets analog, D-11; here a
/// seed-locked synthetic stand-in for the absent gitignored data). Each target sits on a grid cell
/// center; the start is the previous target (a continuous reaching session).
func makeReaches(seed: UInt64, count: Int) -> [Reach] {
  let cells = 30
  func cellCenter(_ col: Int, _ row: Int) -> SIMD2<Float> {
    SIMD2<Float>((Float(col) + 0.5) / Float(cells), (Float(row) + 0.5) / Float(cells))
  }
  var reaches = [Reach]()
  reaches.reserveCapacity(count)
  var current = cellCenter(15, 15) // start at the grid center
  for i in 0 ..< count {
    // Deterministic target cell from the hash; keep it a few cells away so De is non-trivial.
    let col = Int(unitHash(seed, UInt64(i) &* 2 &+ 1) * Double(cells)) % cells
    let row = Int(unitHash(seed, UInt64(i) &* 2 &+ 2) * Double(cells)) % cells
    let target = cellCenter(col, row)
    reaches.append(Reach(start: current, target: target))
    current = target
  }
  return reaches
}

/// The synthetic "decoded" velocity for one tick of one reach (grid-units/second). Closed-form,
/// seed/index-driven: it points from `cursor` toward `target` at a base speed, with a DETERMINISTIC
/// directional perturbation (a sinusoid in the tick index, amplitude from the hash) + a magnitude
/// wobble — the analog of a noisy NDT1 readout. This is what makes the raw arm scatter and the
/// Kalman/rotation arms recover it. NO RNG, NO clock — pure function of its arguments.
func decodedVelocity(
  seed: UInt64,
  reachIndex: Int,
  tick: Int,
  cursor: SIMD2<Float>,
  target: SIMD2<Float>
) -> SIMD2<Float> {
  let toTarget = target - cursor
  let dist = simd_length(toTarget)
  guard dist > 1e-6 else { return SIMD2<Float>(0, 0) }
  let dir = toTarget / dist

  // Base speed eases DOWN as the cursor approaches the target (a smooth approach so a clean decoder
  // can settle into the dwell rather than overshoot forever). Far away: full speed; within a few
  // cells: proportional. This easing is what lets the aligned (rotation) arm HOLD the dwell.
  let approach = Swift.min(1.0, dist / 0.15) // ramp over ~4-5 cells
  let baseSpeed: Float = 0.85 * approach

  // Deterministic directional perturbation: rotate `dir` by an angle that oscillates with the tick
  // index (a Lissajous-style closed form) with a per-reach amplitude from the hash. This is the
  // "decoder noise" the raw arm suffers and the rotation arm corrects — it does NOT decay with
  // distance, so near the target the raw cursor keeps jittering out of the acquisition radius (the
  // dwell never completes) while the rotation arm re-aligns every tick toward the target.
  let ampSeed = Float(unitHash(seed, UInt64(reachIndex) &* 7 &+ 3)) // [0,1)
  let angleAmplitude: Float = 1.6 + 0.8 * ampSeed // radians of swing (large — raw genuinely scatters/misses)
  let phase = Float(reachIndex) * 0.7
  let theta = angleAmplitude * sinf(Float(tick) * 0.35 + phase)
  let cosT = cosf(theta)
  let sinT = sinf(theta)
  let perturbedDir = SIMD2<Float>(dir.x * cosT - dir.y * sinT, dir.x * sinT + dir.y * cosT)

  // Magnitude wobble (deterministic): ±30% around the base speed.
  let magWobble = 1.0 + 0.30 * sinf(Float(tick) * 0.5 + phase * 1.3)
  return perturbedDir * (baseSpeed * magWobble)
}

// MARK: - Ablation arms

/// Which filter stage an arm uses.
enum Arm: String, CaseIterable {
  case raw // no filter — decoded velocity straight to the integrator
  case kalmanOnly = "kalman_only" // KalmanFilter.step with rotation disabled (target: nil)
  case refit // KalmanFilter.step with the active target + acquisition radius (rotation on)
}

/// What one simulated reach yields for BOTH metrics. The S&M-2004 Fitts `Trial` (effective distance /
/// movement time / on-axis endpoint — the Phase-7 metric, unchanged) PLUS the Webgrid accounting bits
/// for this reach: whether it was a HIT (a correct Webgrid selection, Sc) and its elapsed seconds
/// (the trial's movement time — HIT or TIMEOUT — which sums into the arm's `t`). There is NO wrong-cell
/// outcome (the single-target dwell-to-select model returns only HIT/TIMEOUT), so Si is STRUCTURALLY 0
/// — disclosed downstream, never silently emitted (D-12, T-08-05-07).
struct ReachOutcome {
  let fittsTrial: FittsThroughput.Trial
  let acquired: Bool // HIT == a correct Webgrid selection (Sc); a TIMEOUT is neither Sc nor Si here.
  let elapsedSeconds: Double // the trial's movement time (HIT) or full timeout (TIMEOUT) — sums into t.
}

/// The aggregate result for one arm: the S&M-2004 Fitts throughput (mean-of-means, the Phase-7 number,
/// unchanged) PLUS the Webgrid BPS quantities accumulated over the SAME seed-locked reaches —
/// `correct` (Sc, HIT count), `incorrect` (Si, structurally 0 — disclosed), and `seconds` (t, summed
/// elapsed). The Webgrid BPS itself is computed from these by ``WebgridBPS/bitsPerSecond(n:correct:incorrect:seconds:)``.
struct ArmResult {
  let fittsTP: Double // S&M-2004 Fitts throughput (TP=IDe/MT, effective-width) — the Phase-7 metric.
  let correct: Int // Sc — Webgrid HIT count.
  let incorrect: Int // Si — structurally 0 (single-target dwell-to-select has no mis-selection path).
  let seconds: Double // t — total elapsed across the arm's reaches (sum of per-trial movement times).

  /// The Webgrid information-rate bitrate for this arm: `B = max(0, log2(N)·(Sc−Si)/t)` over the
  /// 30×30 grid (N = 900 incl. the delete key). The mandatory clamp lives in `WebgridBPS`.
  var webgridBPS: Double {
    WebgridBPS.bitsPerSecond(
      n: WebgridBPS.gridTargetCount(rows: 30, cols: 30),
      correct: correct,
      incorrect: incorrect,
      seconds: seconds
    )
  }
}

/// Simulates ONE reach for one arm and returns BOTH metrics' per-trial quantities (a ``ReachOutcome``):
/// the S&M-2004 Fitts `Trial` (effective distance, movement time, on-axis endpoint) AND the Webgrid
/// HIT/elapsed accounting. ALL trials are returned — acquired AND timeout — so there is NO survivorship
/// bias: a timed-out reach (the erratic raw cursor that never holds the dwell) gets the FULL timeout as
/// its movement time and its last (scattered) position as the endpoint, which is the honest S&M penalty
/// for a missed target (long MT + wide endpoint scatter -> low throughput) AND is NOT counted as a
/// Webgrid HIT (Sc). The SAME `acquisition.runTrial` result drives both metrics on the identical replay.
func simulateReach(_ arm: Arm, reach: Reach, reachIndex: Int, seed: UInt64, filter: KalmanFilter, acquisition: WebgridAcquisition) -> ReachOutcome {
  // The integrator is per-reach (each reach starts at its own start position). The Kalman `filter` is
  // CARRIED ACROSS reaches by the caller (warm — the continuous closed loop is never reset mid-session,
  // 07-RESEARCH §2; a per-reach cold velocity reset would inject a startup-ramp artifact that unfairly
  // penalizes the Kalman arms). Sync the filter's position block to this reach's start before the run.
  let integrator = CursorIntegrator(start: .init(x: reach.start.x, y: reach.start.y))
  filter.setCursorPosition(reach.start)

  var sampled = [SIMD2<Float>]()
  sampled.reserveCapacity(maxTicksPerTrial)

  for tick in 0 ..< maxTicksPerTrial {
    let cursor = SIMD2<Float>(integrator.position.x, integrator.position.y)
    // Sync the integrator's authoritative clamped position into the filter BEFORE the step (§2.3).
    filter.setCursorPosition(cursor)

    let decoded = decodedVelocity(seed: seed, reachIndex: reachIndex, tick: tick, cursor: cursor, target: reach.target)

    let filtered: SIMD2<Float>
    switch arm {
    case .raw:
      filtered = decoded // no filter
    case .kalmanOnly:
      filtered = filter.step(measurement: decoded, target: nil, acquisitionRadius: acquisitionRadius)
    case .refit:
      filtered = filter.step(measurement: decoded, target: reach.target, acquisitionRadius: acquisitionRadius)
    }

    // Integrate via the renderer-owned integrator (the single [0,1] clamp + non-finite reject).
    let velocity = CursorVelocity(ts_ns: 0, seq: UInt64(tick), vx: Float16(filtered.x), vy: Float16(filtered.y))
    let pos = integrator.integrate(latest: velocity, dt: dt)
    sampled.append(SIMD2<Float>(pos.x, pos.y))
  }

  let result = acquisition.runTrial(positions: sampled, target: reach.target)

  // S&M-2004 per-trial quantities. Effective distance = realized reach length; endpoint projected
  // onto the start->target movement axis is the scalar whose ACROSS-TRIAL SD (within a condition) is
  // SDx (07-RESEARCH §4.2 — the effective width comes from the real endpoint scatter, not nominal).
  let axis = reach.target - reach.start
  let axisLen = simd_length(axis)
  let axisUnit = axisLen > 1e-6 ? axis / axisLen : SIMD2<Float>(1, 0)
  let endpointOnAxis = Double(simd_dot(result.endpoint - reach.start, axisUnit))
  let effectiveDistance = Double(simd_length(result.endpoint - reach.start))
  let trial = FittsThroughput.Trial(effectiveDistance: effectiveDistance, movementTime: result.movementTime, endpointOnAxis: endpointOnAxis)
  // The SAME trial result feeds the Webgrid metric: a HIT is a correct selection (Sc); the trial's
  // movement time (HIT) or full timeout (TIMEOUT) is the elapsed time `t` summed over the arm. There
  // is NO wrong-cell outcome to count as Si (structurally 0 — disclosed downstream, D-12/T-08-05-07).
  return ReachOutcome(fittsTrial: trial, acquired: result.acquired, elapsedSeconds: result.movementTime)
}

/// Runs ALL reaches for one arm and returns the aggregate result for BOTH metrics (an ``ArmResult``):
/// the S&M-2004 Fitts throughput (mean-of-means — the Phase-7 number, computed EXACTLY as before) AND
/// the Webgrid BPS quantities (Sc = HIT count, Si = 0 structurally, t = summed elapsed) over the SAME
/// seed-locked reaches. For the Fitts-TP: trials are binned into CONDITIONS by movement amplitude (the
/// standard's per-amplitude grouping), each condition's TP is computed with the genuine across-trial
/// endpoint-scatter SDx (`FittsThroughput.conditionThroughput`, We = 4.133·SDx), then aggregated
/// MEAN-OF-MEANS across conditions (D-09). No trial is dropped, so an arm that misses targets (timeouts)
/// or scatters widely scores a low throughput honestly — and a missed target is likewise NOT a Webgrid Sc.
func runArm(_ arm: Arm, reaches: [Reach], seed: UInt64) -> ArmResult {
  let acquisition = WebgridAcquisition(
    dwellSeconds: dwellSeconds,
    acquisitionRadius: acquisitionRadius,
    timeoutSeconds: timeoutSeconds,
    dt: dt
  )

  // ONE warm Kalman filter carried across all reaches for this arm (the continuous closed loop —
  // never reset mid-session; only the position block is re-synced per reach inside simulateReach).
  //
  // D-09: the SYNTHETIC regression fixture holds the gain FIXED at the frozen Phase-7 baseline ON
  // PURPOSE. This bench's output is a build gate (`refit_bps.json` byte-identity at ci.yml:378-388,
  // `webgrid_bps.json` in bps-policy.sh), and a gate that moved with a real-data re-fit of
  // `KalmanConstants.K` would turn a real-data finding into a red build — which is pressure to tune.
  // Frozen, the fixture keeps guarding what it was always for: the FILTER CODE. The re-fit gain is
  // exercised by `CortexReplayBench` over the real export instead.
  let filter = KalmanFilter(gain: KalmanConstants.phase7BaselineK)
  filter.setState([reaches.first?.start.x ?? 0.5, reaches.first?.start.y ?? 0.5, 0, 0, 0, 0])

  // Bin reaches into amplitude conditions (S&M aggregates per target-amplitude). 6 bins over the
  // [0,1]-grid diagonal span — enough conditions for a stable mean-of-means, each with many trials.
  let conditionCount = 6
  var conditions = [[FittsThroughput.Trial]](repeating: [], count: conditionCount)

  // Webgrid accumulators over the SAME reaches (D-13): Sc = HIT count, t = summed elapsed seconds.
  var webgridCorrect = 0
  var webgridSeconds = 0.0

  for (reachIndex, reach) in reaches.enumerated() {
    let amplitude = Double(simd_length(reach.target - reach.start)) // [0, ~1.41]
    let bin = Swift.min(conditionCount - 1, Int(amplitude / (1.4142 / Double(conditionCount))))
    let outcome = simulateReach(arm, reach: reach, reachIndex: reachIndex, seed: seed, filter: filter, acquisition: acquisition)
    conditions[bin].append(outcome.fittsTrial)
    if outcome.acquired { webgridCorrect += 1 } // a HIT is a correct Webgrid selection (Sc).
    webgridSeconds += outcome.elapsedSeconds // sum the per-trial elapsed time into the arm's t.
  }

  // Per-condition S&M throughput (effective-width from each condition's own endpoint scatter), then
  // mean-of-means across the non-empty conditions.
  let perConditionTP = conditions
    .filter { !$0.isEmpty }
    .map { FittsThroughput.conditionThroughput(trials: $0) }

  if ProcessInfo.processInfo.environment["CORTEX_REFIT_DEBUG"] != nil {
    let all = conditions.flatMap { $0 }
    let meanMT = all.reduce(0.0) { $0 + $1.movementTime } / Double(Swift.max(1, all.count))
    let acquiredCount = all.filter { $0.movementTime < timeoutSeconds - 1e-9 }.count
    let meanDe = all.reduce(0.0) { $0 + $1.effectiveDistance } / Double(Swift.max(1, all.count))
    print("  [debug \(arm.rawValue)] acq=\(acquiredCount)/\(all.count) meanMT=\(String(format: "%.3f", meanMT))s meanDe=\(String(format: "%.3f", meanDe)) perCondTP=\(perConditionTP.map { String(format: "%.2f", $0) })")
  }

  // Si (incorrect) is STRUCTURALLY 0: WebgridAcquisition.runTrial returns only HIT or TIMEOUT — there
  // is no wrong-cell selection outcome — so the harness CANNOT drive Si>0 (T-08-05-07). This is
  // DISCLOSED (incorrect_model) in the JSON + evidence; the BPS is therefore an honest UPPER-BOUND, not
  // a silent "measured zero errors" (D-12). No RNG/clock miss model (that would break D-13 determinism).
  return ArmResult(
    fittsTP: FittsThroughput.meanOfMeans(perConditionTP: perConditionTP),
    correct: webgridCorrect,
    incorrect: 0,
    seconds: webgridSeconds
  )
}

// MARK: - JSON output

/// The committed machine-readable evidence shape (D-10). Snake-case keys; encoded with .sortedKeys
/// so two same-seed runs are byte-identical.
struct RefitBPS: Codable {
  let raw_bps: Double
  let kalman_only_bps: Double
  let refit_bps: Double
  let delta: Double // refit_bps − raw_bps (the filter's pure contribution)
  let n_trials: Int
  let seed: String // hex string (UInt64 seed)
  let dt: Double
  let metric: String
  let methodology: String
}

func writeJSON(_ payload: RefitBPS, to url: URL) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // deterministic byte order
  try encoder.encode(payload).write(to: url)
}

/// The committed machine-readable Webgrid-BPS evidence shape (PERF-01/02/03, D-11/D-12/D-13). A
/// SEPARATE artifact from `RefitBPS` (which stays byte-identical for the Phase-7 CI guard — the
/// Webgrid BPS is ADDITIVE). Snake-case keys; encoded with `.sortedKeys` so two same-seed runs are
/// byte-identical (D-13). Carries BOTH metrics per arm (Webgrid BPS — the leaderboard-comparable
/// metric — AND the S&M-2004 Fitts-TP cross-check, PERF-03), the formula DISCLOSURE string, the
/// mandatory `incorrect_model` Si disclosure (D-12/T-08-05-07), and the honest synthetic-vs-live caveat.
struct WebgridBPSReport: Codable {
  let raw_webgrid_bps: Double
  let kalman_only_webgrid_bps: Double
  let refit_webgrid_bps: Double
  let raw_fitts_tp: Double // the S&M-2004 Fitts-TP cross-check, raw arm (PERF-03 — retained alongside).
  let refit_fitts_tp: Double // the S&M-2004 Fitts-TP cross-check, ReFIT arm (PERF-03).
  let n_targets: Int // N = 900 (the 30×30 grid incl. the delete/cancel key — 08-RESEARCH §6).
  let formula: String // DISCLOSURE pin (asserted by bps-policy.sh) — NOT the executed source of truth.
  let incorrect_model: String // the mandatory Si disclosure (single-target dwell-to-select ⇒ Si=0).
  let correct: Int // Sc on the ReFIT arm (HIT count) — the arm whose BPS is the headline.
  let incorrect: Int // Si — structurally 0 (disclosed by `incorrect_model`).
  let seconds: Double // t on the ReFIT arm (summed elapsed across reaches).
  let seed: String // hex string (UInt64 seed) — matches refit_bps.json.
  let reference_peak_bps: Double // Neuralink P1 figure (8.5, as cited by this repo since Phase 7; not independently sourceable) — the honest gap target (D-12).
  let brain_gate_dense_9x9_bps: Double // BrainGate T5 dense 9x9 (4.16) — Pandarinath 2017 (NOT a pass bar — D-12).
  let brain_gate_6x6_t5_bps: Double   // Same paper's 6x6 figure for T5 (3.7) — exposed for like-for-like comparison.
  let caveat: String // synthetic-replay (not live-human), honest gap to 8.5, NOT tuned toward 4.16 — D-12.
}

func writeWebgridJSON(_ payload: WebgridBPSReport, to url: URL) throws {
  let encoder = JSONEncoder()
  // `.withoutEscapingSlashes` so the `formula` field reads as the documented literal
  // `B = max(0, log2(N)*(Sc-Si)/t)` (not the JSON-default `\/`-escaped form) — it must match the
  // 08-bps-evidence.md / 08-05-PLAN literal AND the bps-policy.sh assertion verbatim. `.sortedKeys`
  // keeps the byte order deterministic across runs (D-13). (This is a SEPARATE writer from the
  // Phase-7 `writeJSON`, which is left untouched so refit_bps.json stays byte-identical.)
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(payload).write(to: url)
}

// MARK: - SC#3 filter-step latency bench (inline, no new thread)

/// Times the filter step (predict -> rotate -> update) over `latencyTicks` ticks INLINE on the
/// calling thread and prints a device-annotated LatencyHistogram. NO Thread/pthread_create/
/// DispatchQueue spawn (SC#3). ContinuousClock here times the step ONLY — it never touches the BPS
/// simulation. The deviceAnnotation marks this a CORROBORATING Mac/CPU number, NOT the canonical
/// iPad-M4 tail (Manual-Only, 07-VALIDATION); the bench asserts nothing on the value.
func runLatencyBench(seed: UInt64) -> LatencyHistogram {
  // D-09: the same frozen Phase-7 baseline gain the ablation runs on, so the two paths of this bench
  // measure the same filter and neither moves with a real-data re-fit of `KalmanConstants.K`. The
  // step cost is a fixed count of simd dot products either way, so the gain's VALUE does not change
  // what is being timed; using the same constant keeps the bench internally consistent.
  let filter = KalmanFilter(gain: KalmanConstants.phase7BaselineK)
  filter.setState([0.5, 0.5, 0, 0, 0, 0])
  let target = SIMD2<Float>(0.9, 0.8)
  let clock = ContinuousClock()
  var samples = [UInt64]()
  samples.reserveCapacity(latencyTicks)

  for tick in 0 ..< latencyTicks {
    // Deterministic synced position + measurement (seed/index-driven, no RNG).
    let p = SIMD2<Float>(0.2 + 0.0001 * Float(tick % 5000), 0.2 + 0.00008 * Float(tick % 5000))
    let z = SIMD2<Float>(0.3 * cosf(Float(tick) * 0.1), 0.3 * sinf(Float(tick) * 0.1))
    filter.setCursorPosition(p)
    let t0 = clock.now
    _ = filter.step(measurement: z, target: target, acquisitionRadius: acquisitionRadius)
    let elapsed = clock.now - t0
    let c = elapsed.components
    let ns = UInt64(Swift.max(0, c.seconds)) &* 1_000_000_000 &+ UInt64(Swift.max(0, c.attoseconds) / 1_000_000_000)
    samples.append(ns)
  }
  return LatencyHistogram(samplesNs: samples, deviceAnnotation: "M5-Pro-CPU-corroborating")
}

// MARK: - Output dir (gitignored .bench/, mirrors CortexDecoderBench)

let outputDir = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent() // CortexReFITBench
  .deletingLastPathComponent() // Sources
  .deletingLastPathComponent() // CortexReFIT (package root)
  .appendingPathComponent(".bench", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let jsonURL = outputDir.appendingPathComponent("refit_bps.json")
// The NEW Webgrid-BPS artifact (PERF-01, D-13) — separate file so refit_bps.json stays byte-identical.
let webgridJSONURL = outputDir.appendingPathComponent("webgrid_bps.json")

// MARK: - Main

let replayURL = resolveReplayURL()

// Clean-clone / CI: no data path AND no --smoke -> usage/skip, exit 0.
if replayURL == nil, !isSmoke {
  print(usage)
  exit(0)
}

// RD-09 (Phase 10): a PRESENT replay path is now REFUSED rather than half-honoured. It used to set
// `source = "indy-replay (...) + seed-locked synthetic perturbation"` and then run the synthetic
// reaches anyway, so the transcript named a real session while every number in it was synthetic —
// the exact mislabelling defect RD-09 exists to remove, sitting inside the harness RD-07 uses. There
// has never been a loader behind this hook. The hook is KEPT (it is discoverable, and an operator who
// sets it clearly wants real data) but it now exits non-zero and names the real-data entry point.
// The `--smoke` path is untouched: with no env var and no non-flag argv, `replayURL` is nil.
if let replayURL, FileManager.default.fileExists(atPath: replayURL.path) {
  print("CortexReFITBench: refusing to run against \(replayURL.lastPathComponent).")
  print("  This bench has NO real-data loader and never had one. It runs a deterministic seed-locked")
  print("  SYNTHETIC replay, and honouring this path would label synthetic numbers with a real")
  print("  session id. Its output is also a byte-identity build gate that must not move (D-09).")
  print("")
  print("  The real-data four-arm ablation over the D-06 export is a SEPARATE executable:")
  print("")
  print("    swift run --package-path Packages/CortexDemo CortexReplayBench \\")
  print("      --export Decoder/exports/<session>.replay.json \\")
  print("      --model  Decoder/checkpoints/<model>.mlpackage")
  print("")
  print("  For the synthetic regression fixture, unset CORTEX_REFIT_REPLAY_URL and pass --smoke.")
  exit(1)
}

let seed = defaultSeed
let source = "deterministic synthetic seed-locked replay (--smoke; no gitignored Indy data present)"

let reaches = makeReaches(seed: seed, count: trialsPerCondition)
// Each arm now returns BOTH metrics (ArmResult): the S&M-2004 Fitts-TP (.fittsTP — the Phase-7 number,
// unchanged) AND the Webgrid BPS quantities, computed over the IDENTICAL seed-locked replay.
let rawResult = runArm(.raw, reaches: reaches, seed: seed)
let kalmanOnlyResult = runArm(.kalmanOnly, reaches: reaches, seed: seed)
let refitResult = runArm(.refit, reaches: reaches, seed: seed)

// The Fitts-TP values feed the EXISTING refit_bps.json payload — UNCHANGED (byte-identical to the
// Phase-7 committed artifact so the CI guard at ci.yml ~316-340 still passes; the Webgrid BPS is
// additive in a separate file). These are the same three Double values runArm previously returned.
let rawBPS = rawResult.fittsTP
let kalmanOnlyBPS = kalmanOnlyResult.fittsTP
let refitBPS = refitResult.fittsTP

let payload = RefitBPS(
  raw_bps: rawBPS,
  kalman_only_bps: kalmanOnlyBPS,
  refit_bps: refitBPS,
  delta: refitBPS - rawBPS,
  n_trials: reaches.count,
  seed: String(format: "0x%llX", seed),
  dt: dt,
  metric: "Soukoreff-MacKenzie-2004 ISO 9241-9 Fitts throughput (TP=IDe/MT, effective-width); NOT the Webgrid bitrate — do not compare to 4.16/8.5 (Phase 8, D-13)",
  methodology: "headless deterministic 3-way ablation (raw/kalman_only/refit) on the identical seed-locked replay; We=4.133*SDx from endpoint scatter, mean-of-means across reaches; dwell=\(dwellSeconds)s, r_acq=0.5/30 cell, timeout=\(timeoutSeconds)s"
)

// The NEW Webgrid-BPS report (additive — PERF-01/02/03, D-11/D-12/D-13). The Webgrid BPS per arm comes
// from ArmResult.webgridBPS (= max(0, log2(900)·(Sc−Si)/t)); the S&M-2004 Fitts-TP cross-check is
// carried alongside (PERF-03). Si is the DISCLOSED structural 0 (single-target dwell-to-select has no
// mis-selection path ⇒ the BPS is an honest upper-bound, NOT "measured zero errors" — D-12/T-08-05-07).
let incorrectModelDisclosure = "none — single-target dwell-to-select; Si structurally 0; BPS is upper-bound"
// D-4 disclosure: comparison against BrainGate is not like-for-like on three independent grounds (formula,
// grid, Si-structural-zero) plus a fourth against Neuralink (click-types term). See WebgridBPS.nonComparabilityDisclosure.
let webgridCaveat = "synthetic Indy replay, NOT a live-human two-stage ReFIT retrain; reference figure 8.5 BPS (Neuralink P1, as cited since Phase 7; not independently sourceable); honest measured number, NOT tuned toward 4.16 (T5 dense 9x9) — D-12. " + WebgridBPS.nonComparabilityDisclosure
let webgridPayload = WebgridBPSReport(
  raw_webgrid_bps: rawResult.webgridBPS,
  kalman_only_webgrid_bps: kalmanOnlyResult.webgridBPS,
  refit_webgrid_bps: refitResult.webgridBPS,
  raw_fitts_tp: rawResult.fittsTP,
  refit_fitts_tp: refitResult.fittsTP,
  n_targets: WebgridBPS.gridTargetCount(rows: 30, cols: 30), // 900 incl. the delete key.
  formula: "B = max(0, log2(N)*(Sc-Si)/t)", // DISCLOSURE pin (bps-policy.sh) — executed math is WebgridBPS.
  incorrect_model: incorrectModelDisclosure,
  correct: refitResult.correct, // Sc on the ReFIT arm (the headline arm).
  incorrect: refitResult.incorrect, // 0 — structurally (disclosed above).
  seconds: refitResult.seconds, // t on the ReFIT arm.
  seed: String(format: "0x%llX", seed),
  reference_peak_bps: WebgridBPS.referencePeakBPS, // 8.5 — the honest gap target.
  brain_gate_dense_9x9_bps: WebgridBPS.brainGateDenseGridBPS, // 4.16 T5 dense 9x9 — reference, NOT a pass bar.
  brain_gate_6x6_t5_bps: WebgridBPS.brainGate6x6T5BPS, // 3.7 T5 6x6 — for like-for-like comparison.
  caveat: webgridCaveat
)

do {
  try writeJSON(payload, to: jsonURL)
} catch {
  print("CortexReFITBench: warning — failed to write \(jsonURL.path): \(error)")
}

// Write the NEW Webgrid-BPS artifact (additive; refit_bps.json above is unchanged — Phase-7 guard safe).
do {
  try writeWebgridJSON(webgridPayload, to: webgridJSONURL)
} catch {
  print("CortexReFITBench: warning — failed to write \(webgridJSONURL.path): \(error)")
}

print("CortexReFITBench — 3-way ablation S&M-2004 Fitts throughput (n=\(reaches.count) reaches/arm, seed=\(payload.seed))")
print("  source: \(source)")
print("  raw_bps         = \(rawBPS)")
print("  kalman_only_bps = \(kalmanOnlyBPS)")
print("  refit_bps       = \(refitBPS)")
print("  delta (refit-raw) = \(payload.delta)")
print("  metric: S&M-2004 Fitts throughput (TP=IDe/MT, effective-width) — NOT the Webgrid bitrate;")
print("          do NOT compare to the 4.16/8.5 reference numbers (Phase 8 SC#5, deferred per D-13).")
print("  wrote: \(jsonURL.path)")
if refitBPS >= rawBPS {
  print("  OK: refit_bps >= raw_bps (the ReFIT uplift holds on the fixed seed — the CI guard invariant).")
} else {
  print("  WARN: refit_bps < raw_bps on this seed — the CI guard would FAIL (filter regression).")
}

// ── Webgrid information-rate BPS (PERF-01/02/03, D-11/D-12/D-13) — the leaderboard-comparable metric ──
// B = max(0, log2(N)·(Sc−Si)/t), N=900 (30×30 incl. delete key). Reported HONESTLY on synthetic replay
// with the explicit gap toward the 8.5 peak + the Si=0 disclosure — NOT tuned toward 4.16 (D-12).
let refitGapTo85 = WebgridBPS.referencePeakBPS - refitResult.webgridBPS
print("")
print("CortexReFITBench — Webgrid information-rate BPS  (B = max(0, log2(N)*(Sc-Si)/t), N=\(webgridPayload.n_targets) incl. delete key)")
print("  raw_webgrid_bps         = \(rawResult.webgridBPS)")
print("  kalman_only_webgrid_bps = \(kalmanOnlyResult.webgridBPS)")
print("  refit_webgrid_bps       = \(refitResult.webgridBPS)  (Sc=\(refitResult.correct), Si=\(refitResult.incorrect), t=\(String(format: "%.3f", refitResult.seconds))s)")
print("  Fitts-TP cross-check (PERF-03): raw=\(rawResult.fittsTP)  refit=\(refitResult.fittsTP)")
print("  incorrect_model: \(incorrectModelDisclosure)")
print("  gap to Neuralink P1 peak (\(WebgridBPS.referencePeakBPS) BPS): ReFIT is \(String(format: "%.3f", refitGapTo85)) BPS short (BrainGate T5 dense 9x9 ref = \(WebgridBPS.brainGateDenseGridBPS)).")
print("  caveat: \(webgridCaveat)")
print("  wrote: \(webgridJSONURL.path)")

if isLatency {
  let histogram = runLatencyBench(seed: seed)
  print("")
  print("CortexReFITBench — SC#3 filter-step tail latency (n=\(latencyTicks) ticks, INLINE on the calling thread, no new thread)")
  print("  p50=\(histogram.p50) ns  p99=\(histogram.p99) ns  max=\(histogram.max) ns")
  print("  device=\(histogram.deviceAnnotation)")
  print("  NOTE: this is a CORROBORATING Mac/CPU number. The canonical iPad-M4 tail-latency claim is")
  print("        Manual-Only (deferred per 07-VALIDATION) — NOT an automated-coverage gap. The constant-")
  print("        gain step is ~tens of simd FLOPs; the bench records + prints, it asserts no value (SC#3).")
}

exit(0)
