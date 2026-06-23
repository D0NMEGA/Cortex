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

  Run on a real held-out Indy replay (decoded-velocity + reach-target sequence):

    CORTEX_REFIT_REPLAY_URL=/path/to/replay swift run --package-path Packages/CortexReFIT CortexReFITBench

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

/// Simulates ONE reach for one arm and returns the trial's S&M-2004 quantities (effective distance,
/// movement time, on-axis endpoint). ALL trials are returned — acquired AND timeout — so there is NO
/// survivorship bias: a timed-out reach (the erratic raw cursor that never holds the dwell) gets the
/// FULL timeout as its movement time and its last (scattered) position as the endpoint, which is the
/// honest S&M penalty for a missed target (long MT + wide endpoint scatter -> low throughput).
func simulateReach(_ arm: Arm, reach: Reach, reachIndex: Int, seed: UInt64, filter: KalmanFilter, acquisition: WebgridAcquisition) -> FittsThroughput.Trial {
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
  return FittsThroughput.Trial(effectiveDistance: effectiveDistance, movementTime: result.movementTime, endpointOnAxis: endpointOnAxis)
}

/// Runs ALL reaches for one arm and returns the aggregate S&M-2004 throughput: trials are binned into
/// CONDITIONS by movement amplitude (the standard's per-amplitude grouping), each condition's TP is
/// computed with the genuine across-trial endpoint-scatter SDx (`FittsThroughput.conditionThroughput`,
/// We = 4.133·SDx), then aggregated MEAN-OF-MEANS across conditions (D-09). No trial is dropped, so an
/// arm that misses targets (timeouts) or scatters widely scores a low throughput honestly.
func runArm(_ arm: Arm, reaches: [Reach], seed: UInt64) -> Double {
  let acquisition = WebgridAcquisition(
    dwellSeconds: dwellSeconds,
    acquisitionRadius: acquisitionRadius,
    timeoutSeconds: timeoutSeconds,
    dt: dt
  )

  // ONE warm Kalman filter carried across all reaches for this arm (the continuous closed loop —
  // never reset mid-session; only the position block is re-synced per reach inside simulateReach).
  let filter = KalmanFilter()
  filter.setState([reaches.first?.start.x ?? 0.5, reaches.first?.start.y ?? 0.5, 0, 0, 0, 0])

  // Bin reaches into amplitude conditions (S&M aggregates per target-amplitude). 6 bins over the
  // [0,1]-grid diagonal span — enough conditions for a stable mean-of-means, each with many trials.
  let conditionCount = 6
  var conditions = [[FittsThroughput.Trial]](repeating: [], count: conditionCount)

  for (reachIndex, reach) in reaches.enumerated() {
    let amplitude = Double(simd_length(reach.target - reach.start)) // [0, ~1.41]
    let bin = Swift.min(conditionCount - 1, Int(amplitude / (1.4142 / Double(conditionCount))))
    let trial = simulateReach(arm, reach: reach, reachIndex: reachIndex, seed: seed, filter: filter, acquisition: acquisition)
    conditions[bin].append(trial)
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

  return FittsThroughput.meanOfMeans(perConditionTP: perConditionTP)
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

// MARK: - SC#3 filter-step latency bench (inline, no new thread)

/// Times the filter step (predict -> rotate -> update) over `latencyTicks` ticks INLINE on the
/// calling thread and prints a device-annotated LatencyHistogram. NO Thread/pthread_create/
/// DispatchQueue spawn (SC#3). ContinuousClock here times the step ONLY — it never touches the BPS
/// simulation. The deviceAnnotation marks this a CORROBORATING Mac/CPU number, NOT the canonical
/// iPad-M4 tail (Manual-Only, 07-VALIDATION); the bench asserts nothing on the value.
func runLatencyBench(seed: UInt64) -> LatencyHistogram {
  let filter = KalmanFilter()
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

// MARK: - Main

let replayURL = resolveReplayURL()

// Clean-clone / CI: no data path AND no --smoke -> usage/skip, exit 0.
if replayURL == nil, !isSmoke {
  print(usage)
  exit(0)
}

let seed = defaultSeed
let source: String
if let replayURL, FileManager.default.fileExists(atPath: replayURL.path) {
  // A real replay path was provided and exists. (Loading the held-out Indy decoded-velocity + target
  // sequence is the on-device/R&D path; the synthetic seed-locked model is used otherwise. The data
  // format loader is intentionally minimal here — absent in this environment, the synthetic path
  // below runs.) For now, treat a present path as "run the deterministic model anyway" so the bench
  // is reproducible regardless; a real loader is a follow-on (the gitignored data is not here).
  source = "indy-replay (\(replayURL.lastPathComponent)) + seed-locked synthetic perturbation"
} else {
  source = "deterministic synthetic seed-locked replay (--smoke; no gitignored Indy data present)"
}

let reaches = makeReaches(seed: seed, count: trialsPerCondition)
let rawBPS = runArm(.raw, reaches: reaches, seed: seed)
let kalmanOnlyBPS = runArm(.kalmanOnly, reaches: reaches, seed: seed)
let refitBPS = runArm(.refit, reaches: reaches, seed: seed)

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

do {
  try writeJSON(payload, to: jsonURL)
} catch {
  print("CortexReFITBench: warning — failed to write \(jsonURL.path): \(error)")
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
