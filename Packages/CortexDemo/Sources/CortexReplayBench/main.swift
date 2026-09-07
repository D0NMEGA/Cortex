// 617 code lines. A top-level `main.swift` bench driver: Swift only allows top-level statements in a
// file with this name, so the run sequence cannot move to a sibling file, and the ten Codable report
// shapes below carry the snake_case wire keys of `10-refit-real.json`, which is committed and read
// back by Decoder/tests/test_real_replay_schema.py. Splitting the file for a length rule would put a
// byte-identical artifact at risk for no behavioural gain (Phase 10 / D-18).
// swiftlint:disable file_length
// CortexReplayBench - the RD-07 four-arm ablation over REAL Indy spikes (Phase 10, Plan 10-05).
//
// ## What it is
// One decoded replay of the D-06 export through the shipped NDT1 CoreML model, scored four ways:
//
//   raw                   : the decoded velocity straight to the integrator, no filter
//   kalman_only           : KalmanFilter.step with the rotation disabled (target: nil)
//   refit                 : KalmanFilter.step rotating toward the session's TRUE target
//   refit_reversed_target : identical to refit EXCEPT the rotation's target comes from the
//                           TIME-REVERSED target track; scoring still uses the TRUE target
//
// The four arms differ ONLY in the filter stage, over an IDENTICAL decoded sequence. The decode runs
// ONCE, before the arm loop, into a shared array (T-10-05-04): decoding per arm would inject a
// difference the ablation would then attribute to the filter.
//
// ## Why this is a separate executable
// RESEARCH Pitfall 6 / D-09. `CortexReFITBench --smoke`'s output is a byte-identity build gate in two
// places, and a fourth `Arm` case there would put a real-data path inside a frozen fixture. That
// fixture now runs on `KalmanConstants.phase7BaselineK`; THIS bench is where the shipped re-fit gain
// `KalmanConstants.K` is exercised.
//
// ## No verdict, ever
// This bench prints its numbers and exits 0 whatever their sign or magnitude. It compares nothing
// against any bar and emits no pass/fail field (D-09, 10-PREREGISTRATION section 13). A real-data
// result that could redden the build would be pressure to tune, and this phase exists to remove that
// pressure, not to add it.
//
// ## Decode cadence
// ONE decode per 20 ms bin, on the trailing 32-bin window ENDING at that bin, paired with that bin's
// target and true velocity. That is `RecordedSpikeSource`'s documented alignment ("row i pairs the
// spike window ENDING at bin i") applied at every bin rather than every 32nd, and it is the cadence
// `KalmanConstants.dt = 0.02`, `WebgridAcquisition(dt: 0.020)` and the Phase-7 harness all assume.
// Non-overlapping windows would advance the session clock 640 ms per tick, which would collapse the
// pre-registered 0.30 s dwell to a single sample and destroy the acquisition semantics.
import CortexCore // ReplayExport - the ONE Swift reader of the D-06 export (Plan 10-04).
import CortexDecoder // NeuralDecoder (NDT1 CoreML) + SpikeInputBuffer.
import CortexDemo // ArmStatistics + RecordedSpikeSource.modelSeqLen.
import CortexReFIT // KalmanFilter, WebgridAcquisition, WebgridBPS, FittsThroughput.
import CortexRender // CursorIntegrator + CursorVelocity - the single [0,1] clamp seam.
import CryptoKit // SHA256 over the sidecar bytes actually read.
import Foundation // JSONEncoder, FileManager, URL - a bench, off the hot path.
import Metal // MTLCreateSystemDefaultDevice, for the shared-surface spike buffer.
import simd

// MARK: - Pre-registered constants

/// Filter/decode tick in seconds: one 20 ms bin (10-PREREGISTRATION section 2).
let dt = 0.020
/// Half a cell of the 30x30 grid in `[0,1]` space. Cross-check on the real export: the sidecar's
/// `acquisition_radius_mm / side_mm` is 2.8613660406415042 / 171.68196243849025 = 0.5/30 exactly.
let acquisitionRadius: Float = 0.5 / 30.0
/// Continuous on-target hold that commits a selection (10-PREREGISTRATION section 15). Not relaxed.
let dwellSeconds = 0.30
/// Per-trial timeout (10-PREREGISTRATION section 15). Not relaxed.
let timeoutSeconds = 5.0
/// `N` for the counterfactual 30x30 grid score, and `N` for the task the session actually presented.
let gridTargetCount = WebgridBPS.gridTargetCount(rows: 30, cols: 30)
let taskTargetCount = 64

/// The pre-registered label discipline of 10-PREREGISTRATION section 6, verbatim. Both BPS keys carry
/// a sibling `*_label` so the label cannot be dropped by a prose edit downstream.
let bpsN900Label =
  "counterfactual 30x30 grid score; the recorded task presented 64 targets (6.0 bits), whose rate is N=64"
let bpsN64Label = "the recorded task's information rate"

/// The open-loop disclosure, byte-identical everywhere it appears (10-PREREGISTRATION section 12).
let openLoopDisclosure = "open-loop replay of a recorded session; the subject was not in the loop"

// MARK: - CLI

let arguments = CommandLine.arguments

func flagValue(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
  let value = arguments[index + 1]
  return value.isEmpty ? nil : value
}

let exportURL = flagValue("--export").map { URL(fileURLWithPath: $0) }
  ?? ReplayExport.sidecarURLFromEnvironment()
let modelURL = flagValue("--model").map { URL(fileURLWithPath: $0) }
  ?? ClosedLoopPipeline.modelURLFromEnvironment()

/// The gitignored `.bench/` output dir beside the package root (the CortexDemoBench idiom).
let benchDir = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent() // CortexReplayBench
  .deletingLastPathComponent() // Sources
  .deletingLastPathComponent() // CortexDemo (package root)
  .appendingPathComponent(".bench", isDirectory: true)
let outputURL = flagValue("--out").map { URL(fileURLWithPath: $0) }
  ?? benchDir.appendingPathComponent("refit_real.json")

// Clean-clone / CI: name which input is missing and exit 0. Both the export and the model are
// gitignored and materialized by script (D-07), so CI structurally cannot run this bench.
guard let exportURL, let modelURL else {
  var missing = [String]()
  if exportURL == nil {
    missing.append("the D-06 replay export - pass --export <sidecar.json> or set CORTEX_REPLAY_EXPORT")
  }
  if modelURL == nil {
    missing.append("the real CoreML model - pass --model <path.mlpackage> or set CORTEX_MODEL_URL")
  }
  print("CortexReplayBench: skipping, \(missing.count) of 2 required inputs are missing:")
  for item in missing {
    print("  - \(item)")
  }
  print("")
  print("  CortexReplayBench runs the RD-07 four-arm ablation (raw, kalman_only, refit,")
  print("  refit_reversed_target) over one decoded replay of a recorded Indy session.")
  print("")
  print("    swift run --package-path Packages/CortexDemo CortexReplayBench \\")
  print("      --export Decoder/exports/<session>.replay.json \\")
  print("      --model  Decoder/checkpoints/<model>.mlpackage \\")
  print("      [--out <path.json>]")
  print("")
  print("  Both inputs are gitignored (D-07), so this skip is the expected clean-clone and CI path.")
  print("  Exiting 0 - nothing was measured, so nothing is reported.")
  exit(0)
}

// MARK: - Load the export

let export: ReplayExport
do {
  export = try ReplayExport(sidecarURL: exportURL)
} catch {
  print("CortexReplayBench: refusing the export at \(exportURL.path) - \(error)")
  print("  A refused export means NO measurement was taken, which is a setup failure, not a result.")
  exit(1)
}

let workspace = export.sidecar.workspace
let seqLen = RecordedSpikeSource.modelSeqLen
let channels = export.channelCount
let binCount = export.binCount

/// The first bin with a full trailing window. Below this there are not enough bins behind the index to
/// fill the model's 32-bin input, and a short window would be zero-padded spikes the session never had.
let firstDecodableBin = seqLen - 1
guard binCount > firstDecodableBin else {
  print("CortexReplayBench: the export holds \(binCount) bins, fewer than one \(seqLen)-bin window.")
  print("  Refusing to report statistics over zero decoded ticks.")
  exit(1)
}

/// Millimetres to the `cursor_bbox_square` grid, per axis (10-PREREGISTRATION section 3 as amended by
/// 3a): `grid = (mm - min_mm) / side_mm`. The box is a SQUARE, so one grid unit is the same physical
/// distance on both axes and the scalar `acquisitionRadius` means the same thing in x and y.
func toGrid(_ mm: SIMD2<Double>) -> SIMD2<Float> {
  SIMD2<Float>(
    Float((mm.x - workspace.xMinMm) / workspace.sideMm),
    Float((mm.y - workspace.yMinMm) / workspace.sideMm)
  )
}

/// Grid units back to millimetres, for the D-11 cursor-to-target distance proxy.
func gridDistanceToMm(_ gridDistance: Float) -> Double {
  Double(gridDistance) * workspace.sideMm
}

// MARK: - The decode, ONCE

let device = MTLCreateSystemDefaultDevice()
guard let device else {
  print("CortexReplayBench: no Metal device, so the shared-surface spike buffer cannot be created.")
  exit(1)
}

let decoder: NeuralDecoder
let spikeBuffer: SpikeInputBuffer
do {
  decoder = try NeuralDecoder(modelURL: modelURL)
  spikeBuffer = try SpikeInputBuffer(device: device, seqLen: seqLen, channels: channels)
} catch {
  print("CortexReplayBench: could not wire the model-backed decode path - \(error)")
  print("  Requested SpikeInputBuffer seqLen \(seqLen) x channels \(channels); the shipped model's")
  print("  spikes input is (1, 96, 1, 32). No fallback exists here on purpose: a synthetic decode")
  print("  under a real-data label is exactly the defect RD-09 removes.")
  exit(1)
}

let tickCount = binCount - firstDecodableBin
print("CortexReplayBench - decoding \(tickCount) ticks (one per 20 ms bin, \(seqLen)-bin trailing window)")

/// The decoded velocity per tick, in GRID-UNITS/s. Shared by all four arms (T-10-05-04).
var decoded = [SIMD2<Float>]()
decoded.reserveCapacity(tickCount)
/// The session's TRUE target per tick, in grid units, and the same track REVERSED IN TIME.
var trueTargets = [SIMD2<Float>]()
var reversedTargets = [SIMD2<Float>]()
trueTargets.reserveCapacity(tickCount)
reversedTargets.reserveCapacity(tickCount)
/// The raw target in mm per tick, used only to segment trials on a change of target.
var targetsMm = [SIMD2<Double>]()
targetsMm.reserveCapacity(tickCount)

var decodeFailures = 0
var firstDecodeFailure: String?
let gridUnitsPerCm = Float(workspace.gridUnitsPerCm)

for tick in 0 ..< tickCount {
  let bin = firstDecodableBin + tick

  var velocityGridPerSecond = SIMD2<Float>(0, 0)
  do {
    let window = try export.window(endingAt: bin, length: seqLen)
    for binOffset in 0 ..< seqLen {
      for channel in 0 ..< channels {
        try spikeBuffer.write(window[binOffset * channels + channel], channel: channel, bin: binOffset)
      }
    }
    // NDT1 emits cm/s; the filter, the integrator and the webgrid all run in grid-units/s.
    let cmPerSecond = try decoder.decode(spikeBuffer)
    velocityGridPerSecond = cmPerSecond * gridUnitsPerCm
  } catch {
    decodeFailures += 1
    if firstDecodeFailure == nil {
      firstDecodeFailure = "bin \(bin): \(error)"
    }
  }
  decoded.append(velocityGridPerSecond)

  // Kinematics under RecordedSpikeSource's alignment: the window ENDING at `bin` pairs with `bin`.
  let targetMm = (try? export.target(at: bin)) ?? SIMD2<Double>(0, 0)
  targetsMm.append(targetMm)
  trueTargets.append(toGrid(targetMm))
  // 10-PREREGISTRATION section 7: the rotation's track is `track[::-1]`, the whole recorded target
  // track reversed in time. Time reversal preserves the track's autocorrelation and its spatial
  // distribution while destroying its temporal relationship to the spikes.
  let reversedMm = (try? export.target(at: binCount - 1 - bin)) ?? SIMD2<Double>(0, 0)
  reversedTargets.append(toGrid(reversedMm))

  if tick > 0, tick.isMultiple(of: 10000) {
    print("  .. \(tick) / \(tickCount) ticks decoded")
  }
}

// 10-PREREGISTRATION section 10: no real-data number is published from a run where any tick fell back.
// A precondition, not a warning: numbers from a partially-synthetic run under a real-data label are
// exactly the defect this phase exists to remove.
precondition(
  decodeFailures == 0,
  "RD-07: \(decodeFailures) of \(tickCount) decode ticks failed, so this run's numbers are NOT "
    + "real-data numbers. First failure: \(firstDecodeFailure ?? "none recorded"). "
    + "SpikeInputBuffer was built at seqLen \(seqLen) x channels \(channels) against a model whose "
    + "spikes input is (1, 96, 1, 32); RecordedSpikeSource.modelSeqLen is \(RecordedSpikeSource.modelSeqLen)."
)

// MARK: - Trial segmentation

/// One trial: a half-open tick range over which the session's target was constant.
struct TrialRange {
  let start: Int
  let end: Int // exclusive
}

var trials = [TrialRange]()
var trialStart = 0
for tick in 1 ..< tickCount where targetsMm[tick] != targetsMm[tick - 1] {
  trials.append(TrialRange(start: trialStart, end: tick))
  trialStart = tick
}

trials.append(TrialRange(start: trialStart, end: tickCount))

print("  segmented \(trials.count) trials on target changes "
  + "(the sidecar records \(export.sidecar.trials) over the whole session)")

// MARK: - The four arms

enum RotationTargetSource: String {
  case none
  case trueTrack = "true_track"
  case reversedTrack = "reversed_track"
}

enum ReplayArm: String, CaseIterable {
  case raw
  case kalmanOnly = "kalman_only"
  case refit
  case refitReversedTarget = "refit_reversed_target"

  var rotationTargetSource: RotationTargetSource {
    switch self {
    case .raw, .kalmanOnly: .none
    case .refit: .trueTrack
    case .refitReversedTarget: .reversedTrack
    }
  }
}

/// Everything one arm produced, before it is turned into rates.
struct ArmRun {
  let outputs: [SIMD2<Float>] // the arm's filtered velocities, tick-aligned with `decoded`
  let correct: Int
  let seconds: Double
  let fittsTrials: [(amplitude: Double, trial: FittsThroughput.Trial)]
  let distancesMm: [Double] // cursor to TRUE target, every tick
}

let acquisition = WebgridAcquisition(
  dwellSeconds: dwellSeconds,
  acquisitionRadius: acquisitionRadius,
  timeoutSeconds: timeoutSeconds,
  dt: dt
)

@MainActor
// One arm of the four-arm ablation, start to finish: warm filter, warm integrator, the per-trial
// replay loop, then the per-arm reduction. It is deliberately ONE function so all four arms
// provably run identical code, and this file's JSON output is byte-diffed against a committed
// artifact, so splitting it for a length rule trades a real risk for a style number.
// swiftlint:disable:next function_body_length
func runArm(_ arm: ReplayArm) -> ArmRun {
  // ONE warm filter carried across all trials, on the SHIPPED re-fit gain. This bench is where the
  // Plan 10-03 re-fit is exercised; the synthetic fixture runs on the frozen Phase-7 baseline (D-09).
  let filter = KalmanFilter()
  // ONE integrator carried across the whole replay. The D-06 export stores spikes, velocity, target
  // and bin start - it has NO recorded cursor track - so there is no per-trial "true cursor position"
  // to seed from. A continuous cursor is also what the recorded task had: the targets change, the
  // cursor does not teleport. Resetting it per trial would fabricate cursor behavior.
  let integrator = CursorIntegrator(start: .init(x: 0.5, y: 0.5))
  filter.setState([0.5, 0.5, 0, 0, 0, 0])
  filter.setCursorPosition(SIMD2<Float>(0.5, 0.5))

  var outputs = [SIMD2<Float>]()
  var distancesMm = [Double]()
  outputs.reserveCapacity(tickCount)
  distancesMm.reserveCapacity(tickCount)

  var correct = 0
  var seconds = 0.0
  var fittsTrials = [(amplitude: Double, trial: FittsThroughput.Trial)]()

  for range in trials {
    let start = SIMD2<Float>(integrator.position.x, integrator.position.y)
    var sampled = [SIMD2<Float>]()
    sampled.reserveCapacity(range.end - range.start)

    for tick in range.start ..< range.end {
      let cursor = SIMD2<Float>(integrator.position.x, integrator.position.y)
      filter.setCursorPosition(cursor)

      let filtered: SIMD2<Float> = switch arm {
      case .raw:
        decoded[tick] // no filter
      case .kalmanOnly:
        filter.step(measurement: decoded[tick], target: nil, acquisitionRadius: acquisitionRadius)
      case .refit:
        filter.step(
          measurement: decoded[tick],
          target: trueTargets[tick],
          acquisitionRadius: acquisitionRadius
        )
      case .refitReversedTarget:
        // THE TRAP, stated verbatim (10-PREREGISTRATION section 7): if both the rotation target and
        // the scoring target were reversed the control would be vacuous, because the cursor would be
        // rotated toward the same target it is scored against. Only the ROTATION's target is
        // reversed here; `acquisition.runTrial` and the Fitts endpoint projection below both take the
        // TRUE target, so all four arms are scored against the same thing and stay comparable.
        //
        // WHAT THIS CONTROL CANNOT ESTABLISH (review D-9, section 7). `IntentRotation.rotate` returns
        // `(speed / dist) * d`: it replaces the decoded DIRECTION with the direction to the known
        // target and keeps only the decoded speed. So a reversed-target arm that FAILS does NOT make
        // the `refit` arm an independent neural-decoding result - both arms are target-determined by
        // construction and only the target differs. The correct reading of a failing reversed arm is
        // narrow: the rotation needs the correct target to help. `raw` and `kalman_only`, which never
        // see a target, are the only arms whose rate is attributable to the decode.
        filter.step(
          measurement: decoded[tick],
          target: reversedTargets[tick],
          acquisitionRadius: acquisitionRadius
        )
      }
      outputs.append(filtered)

      // The renderer-owned integrator is the SINGLE [0,1] clamp and non-finite reject point. No
      // second clamp is added here (07-RESEARCH pitfall 5).
      let velocity = CursorVelocity(
        tsNs: 0,
        seq: UInt64(tick),
        vx: Float16(filtered.x),
        vy: Float16(filtered.y)
      )
      let position = integrator.integrate(latest: velocity, dt: dt)
      let point = SIMD2<Float>(position.x, position.y)
      sampled.append(point)
      // The D-11 hit-independent proxy: cursor to TRUE target, in millimetres, every tick.
      distancesMm.append(gridDistanceToMm(simd_distance(point, trueTargets[tick])))
    }

    // Scored against the TRUE target for every arm, including the reversed-target one.
    let target = trueTargets[range.start]
    let result = acquisition.runTrial(positions: sampled, target: target)
    if result.acquired {
      correct += 1
    }
    seconds += result.movementTime

    let axis = target - start
    let axisLength = simd_length(axis)
    let axisUnit = axisLength > 1e-6 ? axis / axisLength : SIMD2<Float>(1, 0)
    let trial = FittsThroughput.Trial(
      effectiveDistance: Double(simd_length(result.endpoint - start)),
      movementTime: result.movementTime,
      endpointOnAxis: Double(simd_dot(result.endpoint - start, axisUnit))
    )
    fittsTrials.append((amplitude: Double(axisLength), trial: trial))
  }

  return ArmRun(
    outputs: outputs,
    correct: correct,
    seconds: seconds,
    fittsTrials: fittsTrials,
    distancesMm: distancesMm
  )
}

/// S&M-2004 mean-of-means over amplitude-binned conditions - the same aggregation CortexReFITBench
/// uses, so the Fitts numbers here and there are computed the same way.
func fittsThroughput(_ run: ArmRun) -> Double {
  let conditionCount = 6
  var conditions = [[FittsThroughput.Trial]](repeating: [], count: conditionCount)
  for entry in run.fittsTrials {
    let bin = Swift.min(conditionCount - 1, Int(entry.amplitude / (1.4142 / Double(conditionCount))))
    conditions[Swift.max(0, bin)].append(entry.trial)
  }
  let perCondition = conditions.filter { !$0.isEmpty }.map { FittsThroughput.conditionThroughput(trials: $0) }
  return FittsThroughput.meanOfMeans(perConditionTP: perCondition)
}

/// Nearest-rank percentile over a sorted array: index `ceil(p/100 * n) - 1`, clamped. Stated because
/// a percentile convention chosen after seeing a distribution is not a convention.
func percentile(_ sorted: [Double], _ p: Double) -> Double {
  guard !sorted.isEmpty else { return 0 }
  let rank = Int((p / 100.0 * Double(sorted.count)).rounded(.up))
  return sorted[Swift.min(Swift.max(rank - 1, 0), sorted.count - 1)]
}

// MARK: - JSON payload

struct DistancePercentiles: Codable {
  let p1: Double
  let p5: Double
  let p25: Double
  let p50: Double
  let p90: Double
}

struct ArmReport: Codable {
  let name: String
  let rotationTargetSource: String
  let correct: Int
  let incorrect: Int
  let incorrectModel: String
  let seconds: Double
  let bpsN900: Double
  let bpsN900Label: String
  let bpsN64: Double
  let bpsN64Label: String
  let fittsTp: Double
  let realizedGain: Double
  let realizedSmoothing: Double
  let distanceToTargetMm: DistancePercentiles

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case name
    case rotationTargetSource = "rotation_target_source"
    case correct
    case incorrect
    case incorrectModel = "incorrect_model"
    case seconds
    case bpsN900 = "bps_n900"
    case bpsN900Label = "bps_n900_label"
    case bpsN64 = "bps_n64"
    case bpsN64Label = "bps_n64_label"
    case fittsTp = "fitts_tp"
    case realizedGain = "realized_gain"
    case realizedSmoothing = "realized_smoothing"
    case distanceToTargetMm = "distance_to_target_mm"
  }
}

struct DeltaTriple: Codable {
  let bpsN900: Double
  let bpsN64: Double
  let fittsTp: Double

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case bpsN900 = "bps_n900"
    case bpsN64 = "bps_n64"
    case fittsTp = "fitts_tp"
  }
}

struct Deltas: Codable {
  let refitMinusKalmanOnly: DeltaTriple
  let refitMinusRaw: DeltaTriple
  let refitMinusReversed: DeltaTriple
  let note: String

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case refitMinusKalmanOnly = "refit_minus_kalman_only"
    case refitMinusRaw = "refit_minus_raw"
    case refitMinusReversed = "refit_minus_reversed"
    case note
  }
}

struct References: Codable {
  let braingateDense9x9Bps: Double
  let braingate6x6T5Bps: Double
  let neuralinkP1CitedPeakBps: Double
  let phase8SyntheticRefitBpsN900: Double
  let note: String

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case braingateDense9x9Bps = "braingate_dense_9x9_bps"
    case braingate6x6T5Bps = "braingate_6x6_t5_bps"
    case neuralinkP1CitedPeakBps = "neuralink_p1_cited_peak_bps"
    case phase8SyntheticRefitBpsN900 = "phase8_synthetic_refit_bps_n900"
    case note
  }
}

struct SupersededSynthetic: Codable {
  let rawWebgridBps: Double
  let kalmanOnlyWebgridBps: Double
  let refitWebgridBps: Double
  let rawFittsTp: Double
  let kalmanOnlyFittsTp: Double
  let refitFittsTp: Double
  let note: String

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case rawWebgridBps = "raw_webgrid_bps"
    case kalmanOnlyWebgridBps = "kalman_only_webgrid_bps"
    case refitWebgridBps = "refit_webgrid_bps"
    case rawFittsTp = "raw_fitts_tp"
    case kalmanOnlyFittsTp = "kalman_only_fitts_tp"
    case refitFittsTp = "refit_fitts_tp"
    case note
  }
}

struct DeviceLabel: Codable {
  let label: String
  let status: String
}

struct RefitRealReport: Codable {
  let schemaVersion: Int
  let dataSource: String
  let sessionId: String
  let sourceSha256: String
  let manifestPath: String
  let exportSidecarSha256: String
  let encoderCheckpointSha256: String
  let velocityCheckpointSha256: String
  let arms: [ArmReport]
  let deltas: Deltas
  let references: References
  let device: DeviceLabel
  let env: [String: String]
  let disclosure: String
  let supersededSynthetic: SupersededSynthetic

  /// The JSON keys are snake_case and LOAD-BEARING: `10-replay.json` and `10-refit-real.json` are read
  /// back by `Decoder/tests/test_real_replay_schema.py` and by `Tools/scripts/refit-real-policy.sh`,
  /// which match the key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase
  /// (SwiftLint identifier_name) and the wire format snake_case (byte identity) at the same time.
  /// Do not remove.
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case dataSource = "data_source"
    case sessionId = "session_id"
    case sourceSha256 = "source_sha256"
    case manifestPath = "manifest_path"
    case exportSidecarSha256 = "export_sidecar_sha256"
    case encoderCheckpointSha256 = "encoder_checkpoint_sha256"
    case velocityCheckpointSha256 = "velocity_checkpoint_sha256"
    case arms
    case deltas
    case references
    case device
    case env
    case disclosure
    case supersededSynthetic = "superseded_synthetic"
  }
}

// MARK: - Run the arms and assemble

var runs = [ReplayArm: ArmRun]()
for arm in ReplayArm.allCases {
  print("  running arm \(arm.rawValue)")
  runs[arm] = runArm(arm)
}

@MainActor
func report(for arm: ReplayArm) -> ArmReport {
  guard let run = runs[arm] else {
    preconditionFailure("arm \(arm.rawValue) was not run")
  }
  // Si is STRUCTURALLY 0: WebgridAcquisition.runTrial returns only HIT or TIMEOUT, so the harness
  // cannot drive an incorrect selection. Disclosed here rather than emitted as a measured zero.
  let incorrect = 0
  // Both normalisations, computed for every arm (10-PREREGISTRATION section 6).
  let n900 = WebgridBPS.bitsPerSecond(
    n: gridTargetCount,
    correct: run.correct,
    incorrect: incorrect,
    seconds: run.seconds
  )
  let n64 = WebgridBPS.bitsPerSecond(
    n: taskTargetCount,
    correct: run.correct,
    incorrect: incorrect,
    seconds: run.seconds
  )
  let sortedDistances = run.distancesMm.sorted()
  return ArmReport(
    name: arm.rawValue,
    rotationTargetSource: arm.rotationTargetSource.rawValue,
    correct: run.correct,
    incorrect: incorrect,
    incorrectModel: "none - single-target dwell-to-select; Si structurally 0; BPS is upper-bound",
    seconds: run.seconds,
    bpsN900: n900,
    bpsN900Label: bpsN900Label,
    bpsN64: n64,
    bpsN64Label: bpsN64Label,
    fittsTp: fittsThroughput(run),
    realizedGain: ArmStatistics.realizedGain(inputs: decoded, outputs: run.outputs),
    realizedSmoothing: ArmStatistics.realizedSmoothing(outputs: run.outputs),
    distanceToTargetMm: DistancePercentiles(
      p1: percentile(sortedDistances, 1),
      p5: percentile(sortedDistances, 5),
      p25: percentile(sortedDistances, 25),
      p50: percentile(sortedDistances, 50),
      p90: percentile(sortedDistances, 90)
    )
  )
}

let armReports = ReplayArm.allCases.map(report(for:))

@MainActor
func armReport(_ arm: ReplayArm) -> ArmReport {
  guard let found = armReports.first(where: { $0.name == arm.rawValue }) else {
    preconditionFailure("arm \(arm.rawValue) is missing from the report set")
  }
  return found
}

let rawReport = armReport(.raw)
let kalmanOnlyReport = armReport(.kalmanOnly)
let refitReport = armReport(.refit)
let reversedReport = armReport(.refitReversedTarget)

func delta(_ lhs: ArmReport, _ rhs: ArmReport) -> DeltaTriple {
  DeltaTriple(
    bpsN900: lhs.bpsN900 - rhs.bpsN900,
    bpsN64: lhs.bpsN64 - rhs.bpsN64,
    fittsTp: lhs.fittsTp - rhs.fittsTp
  )
}

let deltas = Deltas(
  refitMinusKalmanOnly: delta(refitReport, kalmanOnlyReport),
  refitMinusRaw: delta(refitReport, rawReport),
  refitMinusReversed: delta(refitReport, reversedReport),
  note: "refit_minus_kalman_only is the ATTRIBUTABLE number: the rotation with the Kalman's gain and "
    + "smoothing held fixed. refit_minus_raw is the headline comparison and CONFLATES the rotation "
    + "with the Kalman's gain and smoothing, which is why realized_gain and realized_smoothing are "
    + "reported per arm (10-PREREGISTRATION section 8)."
)

let references = References(
  braingateDense9x9Bps: 4.16, // Pandarinath 2017 eLife 18554: T5 on a DENSE 9x9 grid, not the 6x6.
  braingate6x6T5Bps: 3.7,
  neuralinkP1CitedPeakBps: 8.5,
  // The label lives in this comment, not in the property name: before Plan 10-16 camelCased the
  // field, `phase8_synthetic_refit_bps_n900` carried the lowercase token `synthetic` that
  // honesty-sweep.sh's line-scoped label check reads, and `Synthetic` does not match it. Saying
  // what the number is beats relying on an identifier's spelling to say it.
  phase8SyntheticRefitBpsN900: 1.953047883714651, // synthetic Phase-8 seed-locked replay, superseded
  note: "4.16 is Pandarinath et al. 2017 (eLife 18554) measured with T5 on a DENSE 9x9 grid over 8 "
    + "evaluation blocks, NOT the 6x6 grid; the 6x6 figures in the same paper are T6 2.2, T5 3.7, "
    + "T7 1.4, so braingate_6x6_t5_bps is the like-for-like 6x6 number. 8.5 is the figure this repo "
    + "has cited for Neuralink P1 and is kept per D-17, dated: as of 2026-09-05 neuralink.com/webgrid "
    + "states 'over 10 BPS'. phase8_synthetic_refit_bps_n900 is this repo's own Phase-8 SYNTHETIC "
    + "seed-locked replay figure. None of these is like-for-like with the numbers in this file: the "
    + "formula differs (log2(N) here versus log2(N-1) in eLife 18554), the grid differs, and this "
    + "harness makes incorrect selections structurally zero so Si is always 0."
)

let supersededSynthetic = SupersededSynthetic(
  rawWebgridBps: 1.292123144105848,
  kalmanOnlyWebgridBps: 1.183000907045892,
  refitWebgridBps: 1.953047883714651, // superseded synthetic (Phase 8)
  rawFittsTp: 0.16089860247386525,
  kalmanOnlyFittsTp: 0.15545586433053596,
  refitFittsTp: 0.37439506338290895, // superseded synthetic (Phase 7)
  note: "The Phase-8 SYNTHETIC seed-locked replay triple, carried here so the before-and-after is in "
    + "the artifact itself (D-12). Copied verbatim from the committed webgrid_bps.json (Phase 8) and "
    + "refit_bps.json (Phase 7). On that synthetic data kalman_only is BELOW raw on both metrics, so "
    + "none of the synthetic uplift was attributable to the Kalman's gain and smoothing; that is "
    + "precisely what the per-arm gain and smoothing statistics exist to establish on real data too."
)

let sidecarDigest: String
do {
  sidecarDigest = try SHA256.hash(data: Data(contentsOf: exportURL))
    .map { String(format: "%02x", $0) }
    .joined()
} catch {
  print("CortexReplayBench: could not re-read the sidecar to digest it - \(error)")
  exit(1)
}

#if compiler(>=6.2)
  let compilerLabel = ">=6.2"
#else
  let compilerLabel = "<6.2"
#endif

let payload = RefitRealReport(
  schemaVersion: 1,
  dataSource: "real",
  sessionId: export.sidecar.sessionId,
  sourceSha256: export.sidecar.sourceSha256,
  manifestPath: export.sidecar.manifestPath,
  exportSidecarSha256: sidecarDigest,
  encoderCheckpointSha256: export.sidecar.encoderCheckpointSha256,
  velocityCheckpointSha256: export.sidecar.velocityCheckpointSha256,
  arms: armReports,
  deltas: deltas,
  references: references,
  device: DeviceLabel(label: "Apple M5 Pro (arm64)", status: "corroborating"),
  env: [
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "swift_compiler": compilerLabel,
    "bin_ms": String(export.sidecar.binMs),
    "seq_len": String(seqLen),
    "lag_bins": String(export.sidecar.lagBins),
    "dwell_s": String(dwellSeconds),
    "timeout_s": String(timeoutSeconds),
    "acquisition_radius_mm": String(workspace.acquisitionRadiusMm),
    "normalisation": workspace.normalisation,
    "ticks": String(tickCount),
    "trials": String(trials.count)
  ],
  disclosure: openLoopDisclosure,
  supersededSynthetic: supersededSynthetic
)

try? FileManager.default.createDirectory(
  at: outputURL.deletingLastPathComponent(),
  withIntermediateDirectories: true
)
do {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(payload).write(to: outputURL)
} catch {
  print("CortexReplayBench: warning - failed to write \(outputURL.path): \(error)")
}

// MARK: - Print (numbers only, no verdict)

print("")
print("CortexReplayBench - RD-07 four-arm ablation on REAL spikes")
print("  session = \(export.sidecar.sessionId)   sidecar sha256 = \(sidecarDigest)")
print("  \(binCount) bins, \(tickCount) decoded ticks, \(trials.count) trials, "
  + "\(export.sidecar.nChannels) channels, \(seqLen)-bin window")
print("  workspace = \(workspace.normalisation), side_mm = \(workspace.sideMm), "
  + "acq_radius_mm = \(workspace.acquisitionRadiusMm)")
print("  dwell = \(dwellSeconds) s, timeout = \(timeoutSeconds) s, r_acq = 0.5/30 grid units "
  + "(pre-registered; not relaxed)")
print("  decode failures = \(decodeFailures) of \(tickCount) (the run aborts above if this is not 0)")
print("")
for arm in armReports {
  print("  \(arm.name)  [rotation target: \(arm.rotationTargetSource)]")
  print("    hits = \(arm.correct)  (Si = \(arm.incorrect), \(arm.incorrectModel))")
  print("    seconds = \(arm.seconds)")
  print("    bps_n900 = \(arm.bpsN900)   [\(arm.bpsN900Label)]")
  print("    bps_n64  = \(arm.bpsN64)   [\(arm.bpsN64Label)]")
  print("    fitts_tp = \(arm.fittsTp)")
  print("    realized_gain = \(arm.realizedGain)   realized_smoothing = \(arm.realizedSmoothing)")
  print("    distance_to_target_mm p1/p5/p25/p50/p90 = "
    + "\(arm.distanceToTargetMm.p1) / \(arm.distanceToTargetMm.p5) / "
    + "\(arm.distanceToTargetMm.p25) / \(arm.distanceToTargetMm.p50) / "
    + "\(arm.distanceToTargetMm.p90)")
}

print("")
print("  deltas (refit - kalman_only), the ATTRIBUTABLE number:")
print("    bps_n900 = \(deltas.refitMinusKalmanOnly.bpsN900)  "
  + "bps_n64 = \(deltas.refitMinusKalmanOnly.bpsN64)  "
  + "fitts_tp = \(deltas.refitMinusKalmanOnly.fittsTp)")
print("  deltas (refit - raw), which conflates the rotation with the Kalman's gain and smoothing:")
print("    bps_n900 = \(deltas.refitMinusRaw.bpsN900)  "
  + "bps_n64 = \(deltas.refitMinusRaw.bpsN64)  "
  + "fitts_tp = \(deltas.refitMinusRaw.fittsTp)")
print("  deltas (refit - refit_reversed_target), the attribution control:")
print("    bps_n900 = \(deltas.refitMinusReversed.bpsN900)  "
  + "bps_n64 = \(deltas.refitMinusReversed.bpsN64)  "
  + "fitts_tp = \(deltas.refitMinusReversed.fittsTp)")
print("")
print("  \(deltas.note)")
print("  disclosure: \(openLoopDisclosure)")
print("  The recorded-cursor replay reference this hit count is read against is the committed")
print("  10-ceiling.json, at the same radius and dwell. It is a property of ONE recorded trajectory")
print("  under ONE acceptance rule, not a bound on what a decoder can achieve.")
print("  D-09: this bench compares nothing against any bar and exits 0 whatever the numbers are.")
print("  wrote: \(outputURL.path)")

exit(0)

// swiftlint:enable file_length
