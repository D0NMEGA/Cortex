// CortexDemoBench — Phase 8 (PERF-04, D-07/D-08): the headless SOFTWARE-TIMED glass-to-glass latency
// bench. Mirrors CortexReFITBench / CortexDecoderBench (a dedicated bench executable, NOT a swift-test
// timing gate — D-18 precedent keeps a flaky latency assertion out of CI).
//
// ## What it measures (08-RESEARCH §0.3/§5, D-07)
// It drives the `ReplayPipeline` for n ≥ 10,000 ticks. For each tick it records the intent-emission
// `mach_absolute_time()` → ns (CortexCore.Time, the SAME clock as the BCI HID report timestamp, §1.3),
// times the decode+filter+integrate pipeline cost INLINE, and models the on-glass present time as a
// SIMULATED `targetPresentationTimestamp`:
//
//   presentNs = intentEmissionNs + measuredPipelineCostNs, then advanced UP to the next 120Hz
//   (8.333 ms) present boundary  — the beam-raced present a real CAMetalDisplayLink would deliver.
//
// A headless runner has NO display link, so the present boundary is modeled deterministically here; the
// `GlassToGlassTimer.sample(intentEmissionNs:presentTimestampSeconds:)` conversion (present−intent,
// clamped ≥0) is the SAME code the live GUI path uses with the real `update.targetPresentationTimestamp`.
//
// ## The claim discipline (D-07/D-08 — load-bearing, do not fudge)
// The number is SOFTWARE-TIMED and carries the verbatim `GlassToGlassTimer.methodologyLabel` in the
// printed output AND the JSON — it excludes the compositor's 1-3 frames of scanout (the delta the v1
// photodiode rig quantifies). It is reported on M5 Pro as CORROBORATING-canonical; the canonical iPad-M4
// capture (the same bench against a real CAMetalDisplayLink present timestamp) is the Plan 07 never-auto-
// approve HUMAN-UAT gate (D-08). The bench ASSERTS p99 < 25 ms (PERF-04) on the M5-Pro corroborating run
// and prints a PASS/FAIL line — that is the software-pipeline budget, NOT the iPad photodiode claim.
//
// ## Clean-clone / CI safety
// With NO flag it prints usage and exits 0 (mirrors the sibling benches). `--smoke` runs a short
// CI-fast budget; the full run (no `--smoke`, or `--full`) runs n = 10,000. Deterministic except the
// mach clock (which only sets the intent-emission base — the pipeline cost it measures is real work).
import CortexCore // Time.machAbsoluteNanoseconds + ReplayExport (the D-06 reader, Phase 10 RD-08).
import CortexDecoder // LatencyHistogram (reused percentile value type).
import CortexDemo // ReplayPipeline + GlassToGlassTimer (the software-timed measurement under test).
import CryptoKit // SHA256 — binds the Seam A report to the exact sidecar bytes replayed (Phase 10).
import Foundation
import simd

// MARK: - CLI flags

let arguments = CommandLine.arguments
let isSmoke = arguments.contains("--smoke")
let isFull = arguments.contains("--full")
/// Phase 10 (RD-08): the Seam A real-data mode. Additive — it never runs the synthetic block below.
let isReal = arguments.contains("--real")

/// The value following `name` on the command line, or nil when the flag is absent or has no value.
func flagValue(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
  let value = arguments[index + 1]
  return value.isEmpty ? nil : value
}

let usage = """
CortexDemoBench — headless SOFTWARE-TIMED glass-to-glass latency bench (PERF-04, D-07/D-08).

  No flag was passed, so there is nothing to measure — exiting 0 (the expected clean-clone / CI path
  when this bench is invoked without a mode).

  Run the CI-fast smoke budget (still proves the bench + the determinism + the PERF-04 assertion):

    swift run --package-path Packages/CortexDemo CortexDemoBench --smoke

  Run the full n = 10,000-tick corroborating bench (M5 Pro):

    swift run --package-path Packages/CortexDemo CortexDemoBench --full

  It drives ReplayPipeline, records intent-emission mach_absolute_time -> ns, models the on-glass
  present time as a SIMULATED targetPresentationTimestamp (intent + measured pipeline cost, advanced to
  the next 120Hz present boundary), builds a device-annotated LatencyHistogram, prints p50/p99/max + the
  verbatim methodology label, writes .bench/glass_to_glass.json, and ASSERTS p99 < 25 ms (PERF-04).

  This is the SOFTWARE-TIMED number (excludes the compositor scanout — the v1 photodiode delta). The
  canonical iPad-M4 capture is the Plan 07 never-auto-approve HUMAN-UAT gate (D-08); this M5-Pro number
  is CORROBORATING.

  Run Seam A, the REAL-DATA replay (Phase 10, RD-08). It takes over from the modes above:

    swift run --package-path Packages/CortexDemo CortexDemoBench --real \\
      --export Decoder/exports/indy_20160630_01.replay.json \\
      --model  Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage

  Either input may instead come from CORTEX_REPLAY_EXPORT / CORTEX_MODEL_URL. With either input
  missing it names which one and exits 0 (the clean-clone / CI path — CI never has the dataset).
  Seam A is the geometry above with exactly two things changed: the spike source and the decode. It
  applies NO pass/fail bar and writes .bench/glass_to_glass_real.json, a separate file.
"""

// Clean-clone / CI: no flag -> usage/skip, exit 0.
if !isSmoke, !isFull, !isReal {
  print(usage)
  exit(0)
}

// MARK: - Configuration

/// PERF-04 software-pipeline budget: p99 < 25 ms.
let budgetNs: UInt64 = 25_000_000
/// 120Hz present period in ns (8.333… ms) — the beam-raced present boundary the present time snaps to.
let framePeriodNs: UInt64 = 8_333_333
/// Tick count: a short CI-fast budget in --smoke, the full n = 10,000 otherwise (≥ the 10k bar the
/// decoder/ReFIT benches use).
let tickCount = isSmoke ? 2000 : 10000
/// The determinism seed for the driven pipeline (matches the replay-loop tests).
let seed: UInt64 = 0xC0FFEE
/// The device annotation — WHY this is an M5-Pro CORROBORATING number, NOT the iPad-M4 canonical claim.
let deviceAnnotation = "M5-Pro-software-timed-corroborating"

// MARK: - Seam A: the real-data replay (Phase 10, RD-08 / 10-PREREGISTRATION section 9)

//
// `--real` changes EXACTLY TWO things versus the `--full` path below: the spike source becomes a
// RecordedSpikeSource over the D-06 export, and the pipeline is constructed with the real model URL.
// Everything else — the 8-tick warmup, `Time.machAbsoluteNanoseconds()`, the MODELLED 120 Hz present
// arithmetic, `GlassToGlassTimer.sample`, the histogram — is byte-identical to the block below, and the
// `framePeriodNs` constant is READ from the configuration above rather than re-typed. THIS IS SEAM A,
// and its comparability to the Phase-8 8.3 ms rests entirely on nothing else changing. The arithmetic
// is repeated verbatim rather than factored out precisely so the Phase-8 code path is not edited.
//
// ONE deliberate exception, and it is not optional (D-09; review D-3, 2026-09-05). The real path does
// NOT inherit the PERF-04 verdict. It computes no verdict value, compares against no `budgetNs`, exits
// 0 whatever the p99 is, and `RealSeamReport` carries no `budget_ns` key at all — an ABSENT key cannot
// be misread as a verdict. Routing a real-data measurement through a 25 ms pass/fail bar is exactly the
// "a red build is pressure to tune the number" failure D-09 forbids. The `--smoke` / `--full` verdict
// below is unchanged: that synthetic gate is correct, and it is what protects the deterministic
// pipeline from regression. It simply must not be inherited by a measurement whose value is a finding
// rather than a target.

/// The Seam A evidence shape. Deliberately NOT `GlassToGlassReport`: it must carry no verdict and no
/// budget, and reusing that struct would also change the Phase-8 artifact's shape.
struct RealSeamReport: Codable {
  let seam: String
  let boundary: String
  let p50Ns: UInt64
  let p99Ns: UInt64
  let maxNs: UInt64
  let count: Int
  let deviceAnnotation: String
  let methodology: String
  let note: String
  let ticksModelBacked: Int
  let ticksTotal: Int
  let sessionId: String
  let exportSidecarSha256: String
  let dataSource: String
  let framePeriodNs: UInt64
  let framesModelled: Int
  let cadenceProvenance: String

  /// The JSON keys are snake_case and LOAD-BEARING: the emitted artifacts are read back by
  /// `Decoder/tests/test_real_replay_schema.py` and by the Tools/scripts policy gates, which match the
  /// key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase (SwiftLint
  /// identifier_name) and the wire format snake_case (byte identity) at the same time. Do not remove.
  enum CodingKeys: String, CodingKey {
    case seam
    case boundary
    case p50Ns = "p50_ns"
    case p99Ns = "p99_ns"
    case maxNs = "max_ns"
    case count
    case deviceAnnotation = "device_annotation"
    case methodology
    case note
    case ticksModelBacked = "ticks_model_backed"
    case ticksTotal = "ticks_total"
    case sessionId = "session_id"
    case exportSidecarSha256 = "export_sidecar_sha256"
    case dataSource = "data_source"
    case framePeriodNs = "frame_period_ns"
    case framesModelled = "frames_modelled"
    case cadenceProvenance = "cadence_provenance"
  }
}

if isReal {
  let exportURL = flagValue("--export").map { URL(fileURLWithPath: $0) }
    ?? ReplayExport.sidecarURLFromEnvironment()
  let realModelURL = flagValue("--model").map { URL(fileURLWithPath: $0) }
    ?? ReplayPipeline.modelURLFromEnvironment()

  // Clean-clone / CI: name which input is missing and exit 0. D-07 gitignores the export and the
  // model, so CI structurally cannot run this mode, and the tier split already accepts that.
  guard let exportURL, let realModelURL else {
    var missing = [String]()
    if exportURL == nil {
      missing.append("the D-06 replay export — pass --export <sidecar.json> or set CORTEX_REPLAY_EXPORT")
    }
    if realModelURL == nil {
      missing.append("the real CoreML model — pass --model <path.mlpackage> or set CORTEX_MODEL_URL")
    }
    print("CortexDemoBench --real: skipping, \(missing.count) of 2 required inputs are missing:")
    for item in missing {
      print("  - \(item)")
    }
    print("  Both are gitignored and materialized by script (D-07), so this is the expected clean-clone")
    print("  and CI path. Exiting 0 — nothing was measured, so nothing is reported.")
    exit(0)
  }

  let export: ReplayExport
  do {
    export = try ReplayExport(sidecarURL: exportURL)
  } catch {
    print("CortexDemoBench --real: refusing the export at \(exportURL.path) — \(error)")
    print("  A refused export means NO measurement was taken, which is a setup failure, not a result.")
    exit(1)
  }

  let realSource = RecordedSpikeSource(export: export)
  // The real replay's length is bounded by the export, not by the 10,000-tick bar.
  let realTickCount = min(10000, realSource.windowCount)
  guard realTickCount > 0 else {
    print("CortexDemoBench --real: the export holds \(export.binCount) bins, fewer than one "
      + "\(RecordedSpikeSource.modelSeqLen)-bin window. Refusing to report percentiles over zero samples.")
    exit(1)
  }

  // NDT1 emits cm/s; the filter, integrator and webgrid run in grid-units/s. This bench times the
  // pipeline rather than scoring its trajectory, so the conversion does not move the published
  // latency (one scalar multiply per tick, far under the run-to-run spread) - it is applied because
  // leaving a known unit error in a second call site is how the first one survived.
  let realPipeline = ReplayPipeline(
    source: realSource,
    seed: seed,
    modelURL: realModelURL,
    modelVelocityGridUnitsPerCm: Float(export.sidecar.workspace.gridUnitsPerCm)
  )
  var realSamplesNs = [UInt64]()
  realSamplesNs.reserveCapacity(realTickCount)

  // Warm up a few ticks so the first sample is not a cold-start outlier (mirrors the decoder bench warmup).
  for _ in 0 ..< 8 {
    _ = realPipeline.tick()
  }

  // The modelled 120 Hz present boundaries this run crossed, recorded so SC#2's "at 120Hz" claim has a
  // number behind it instead of an assumption (review D-7).
  var firstFrameIndex: UInt64?
  var lastFrameIndex: UInt64 = 0

  for _ in 0 ..< realTickCount {
    // Intent emission: the decoder's clock at the start of the pipeline tick (§1.3).
    let intentEmissionNs = Time.machAbsoluteNanoseconds()

    // Run one decode -> filter -> integrate tick (the REAL pipeline work — this is the measured cost).
    _ = realPipeline.tick()

    // Measured pipeline cost = elapsed since intent emission on the same clock.
    let afterTickNs = Time.machAbsoluteNanoseconds()
    let pipelineCostNs = afterTickNs >= intentEmissionNs ? afterTickNs - intentEmissionNs : 0

    // Model the on-glass present time as a SIMULATED targetPresentationTimestamp: the pipeline finishes at
    // intent + cost, then the beam-raced present lands at the NEXT 120Hz frame boundary after that.
    let pipelineDoneNs = intentEmissionNs + pipelineCostNs
    let framesElapsed = pipelineDoneNs / framePeriodNs
    let presentNs = (framesElapsed + 1) * framePeriodNs
    let presentTimestampSeconds = Double(presentNs) / 1_000_000_000

    // Sample via the SAME GlassToGlassTimer the live GUI uses (present - intent, clamped ≥0).
    let latencyNs = GlassToGlassTimer.sample(
      intentEmissionNs: intentEmissionNs,
      presentTimestampSeconds: presentTimestampSeconds
    )
    realSamplesNs.append(latencyNs)

    let frameIndex = presentNs / framePeriodNs
    if firstFrameIndex == nil {
      firstFrameIndex = frameIndex
    }
    lastFrameIndex = frameIndex
  }

  // 10-PREREGISTRATION section 10: no real-data number is published from a run where any tick fell back
  // to the synthetic decode. A precondition, not a warning: a run that silently produced synthetic
  // numbers under a real-data label is exactly the defect RD-09 exists to remove.
  precondition(
    realPipeline.allTicksModelBacked,
    "RD-08 Seam A: \(realPipeline.totalTicks - realPipeline.modelBackedTicks) of \(realPipeline.totalTicks) "
      + "ticks fell back to the synthetic decode, so this run's numbers are NOT real-data numbers. "
      + "First failure: \(realPipeline.lastDecodeFailure ?? "none recorded"). "
      + "Check SpikeInputBuffer seqLen == 32 against the model's (1, 96, 1, 32) input."
  )

  let realHistogram = GlassToGlassTimer.histogram(samplesNs: realSamplesNs, deviceAnnotation: deviceAnnotation)

  // The sidecar's own sha256, computed from the bytes actually read, so the number is bound to the exact
  // export replayed (T-10-04-07). Only the digest, the session id and repo-relative labels reach the
  // JSON — never the absolute export or model path (T-10-04-06).
  let sidecarDigest: String
  do {
    sidecarDigest = try SHA256.hash(data: Data(contentsOf: exportURL))
      .map { String(format: "%02x", $0) }
      .joined()
  } catch {
    print("CortexDemoBench --real: could not re-read the sidecar to digest it — \(error)")
    exit(1)
  }

  let realReport = RealSeamReport(
    seam: "A",
    boundary: "intent emission (mach_absolute_time at the start of one decode -> filter -> integrate "
      + "tick) to the MODELLED next 120 Hz present boundary. INCLUDES the real NDT1 CoreML decode, the "
      + "ReFIT-Kalman step and the integrator. EXCLUDES IPC, the GPU encode, and the compositor's 1-3 "
      + "frames of scanout. Seam B (Plan 10-06) measures a strictly WIDER boundary and is not "
      + "comparable to this number.",
    p50Ns: realHistogram.p50,
    p99Ns: realHistogram.p99,
    maxNs: realHistogram.max,
    count: realHistogram.count,
    deviceAnnotation: deviceAnnotation,
    methodology: GlassToGlassTimer.methodologyLabel,
    note: "Seam A: the Phase-8 measurement geometry with exactly two things changed, the spike source "
      + "and the decode. NO pass/fail bar is applied and no budget is compared against (D-09). "
      + "ticks_total includes the 8 warmup ticks that precede the \(realTickCount) measured ticks; the "
      + "source clamps at its last whole window, so any tick beyond window \(realSource.windowCount - 1) "
      + "re-replays that window.",
    ticksModelBacked: realPipeline.modelBackedTicks,
    ticksTotal: realPipeline.totalTicks,
    sessionId: export.sidecar.sessionId,
    exportSidecarSha256: sidecarDigest,
    dataSource: "real",
    framePeriodNs: framePeriodNs,
    framesModelled: Int(lastFrameIndex - (firstFrameIndex ?? lastFrameIndex)),
    cadenceProvenance: "MODELLED 120 Hz present boundary arithmetic, not a CAMetalDisplayLink reading; "
      + "the measured display cadence is the Plan 10-10 GUI capture and the deferred iPad-M4 gate"
  )

  // A NEW file. `.bench/glass_to_glass.json` and the whole `--smoke` / `--full` code path are untouched,
  // so the Phase-8 artifact, its verdict and its CI step are unaffected (Pitfall 6). The directory chain
  // is repeated rather than shared for the same reason.
  let realOutputDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // CortexDemoBench
    .deletingLastPathComponent() // Sources
    .deletingLastPathComponent() // CortexDemo (package root)
    .appendingPathComponent(".bench", isDirectory: true)
  try? FileManager.default.createDirectory(at: realOutputDir, withIntermediateDirectories: true)
  let realJSONURL = realOutputDir.appendingPathComponent("glass_to_glass_real.json")
  do {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(realReport).write(to: realJSONURL)
  } catch {
    print("CortexDemoBench: warning — failed to write \(realJSONURL.path): \(error)")
  }

  print("CortexDemoBench --real — SEAM A, software-timed glass-to-glass over the REAL replay")
  print("  session = \(export.sidecar.sessionId)   sidecar sha256 = \(sidecarDigest)")
  print("  export  = \(export.binCount) bins, \(realSource.windowCount) whole "
    + "\(realSource.numBins)-bin windows; measured ticks = \(realTickCount) (min of 10000 and the "
    + "window count — the replay's length is bounded by the export)")
  print("  model in loop = \(realPipeline.modelBackedTicks)/\(realPipeline.totalTicks) ticks "
    + "(includes the 8 warmup ticks)")
  print("  p50 = \(realHistogram.p50) ns  (\(String(format: "%.3f", Double(realHistogram.p50) / 1_000_000)) ms)")
  print("  p99 = \(realHistogram.p99) ns  (\(String(format: "%.3f", Double(realHistogram.p99) / 1_000_000)) ms)")
  print("  max = \(realHistogram.max) ns  (\(String(format: "%.3f", Double(realHistogram.max) / 1_000_000)) ms)")
  print("  device = \(deviceAnnotation)")
  print("  methodology: \(GlassToGlassTimer.methodologyLabel)")
  print("  cadence: \(realReport.cadenceProvenance)")
  print("  frame_period_ns = \(framePeriodNs); frames_modelled = \(realReport.framesModelled)")
  print("  Phase-8 synthetic p99 for comparison: 8318256 ns (8.318 ms).")
  print("  The two ARE comparable BECAUSE only the spike source and the decode changed; the warmup, the")
  print("  tick loop, the modelled 120 Hz present arithmetic and GlassToGlassTimer.sample are identical.")
  print("  Seam B (Plan 10-06) measures a strictly WIDER boundary and is comparable to NEITHER.")
  print("  D-09: no pass/fail bar is applied to a real-data measurement. The 25 ms PERF-04 budget gates "
    + "the SYNTHETIC path only (--smoke / --full).")
  print("  wrote: \(realJSONURL.path)")
  exit(0)
}

// MARK: - Drive the replay loop + record software-timed latencies

// One warm pipeline driven continuously (the live replay loop). Each tick: record intent emission,
// time the pipeline cost inline, model the present timestamp, sample the software-timed latency.
let pipeline = ReplayPipeline(seed: seed)
var samplesNs = [UInt64]()
samplesNs.reserveCapacity(tickCount)

// Warm up a few ticks so the first sample is not a cold-start outlier (mirrors the decoder bench warmup).
for _ in 0 ..< 8 {
  _ = pipeline.tick()
}

for _ in 0 ..< tickCount {
  // Intent emission: the decoder's clock at the start of the pipeline tick (§1.3).
  let intentEmissionNs = Time.machAbsoluteNanoseconds()

  // Run one decode -> filter -> integrate tick (the REAL pipeline work — this is the measured cost).
  _ = pipeline.tick()

  // Measured pipeline cost = elapsed since intent emission on the same clock.
  let afterTickNs = Time.machAbsoluteNanoseconds()
  let pipelineCostNs = afterTickNs >= intentEmissionNs ? afterTickNs - intentEmissionNs : 0

  // Model the on-glass present time as a SIMULATED targetPresentationTimestamp: the pipeline finishes at
  // intent + cost, then the beam-raced present lands at the NEXT 120Hz frame boundary after that.
  let pipelineDoneNs = intentEmissionNs + pipelineCostNs
  let framesElapsed = pipelineDoneNs / framePeriodNs
  let presentNs = (framesElapsed + 1) * framePeriodNs
  let presentTimestampSeconds = Double(presentNs) / 1_000_000_000

  // Sample via the SAME GlassToGlassTimer the live GUI uses (present - intent, clamped ≥0).
  let latencyNs = GlassToGlassTimer.sample(
    intentEmissionNs: intentEmissionNs,
    presentTimestampSeconds: presentTimestampSeconds
  )
  samplesNs.append(latencyNs)
}

let histogram = GlassToGlassTimer.histogram(samplesNs: samplesNs, deviceAnnotation: deviceAnnotation)

// MARK: - JSON evidence (gitignored .bench/, mirrors the sibling benches)

/// The committed-evidence shape for the software-timed glass-to-glass run. Snake-case keys; `.sortedKeys`
/// so the byte order is deterministic. Carries the VERBATIM methodology label (D-07) + the device
/// annotation (D-08) + the PERF-04 budget + the PASS/FAIL verdict so the JSON is self-describing.
struct GlassToGlassReport: Codable {
  let p50Ns: UInt64
  let p99Ns: UInt64
  let maxNs: UInt64
  let count: Int
  let budgetNs: UInt64
  let passed: Bool
  let deviceAnnotation: String
  let methodology: String
  let note: String

  /// The JSON keys are snake_case and LOAD-BEARING: the emitted artifacts are read back by
  /// `Decoder/tests/test_real_replay_schema.py` and by the Tools/scripts policy gates, which match the
  /// key strings literally. A key rename breaks them. CodingKeys keeps Swift camelCase (SwiftLint
  /// identifier_name) and the wire format snake_case (byte identity) at the same time. Do not remove.
  enum CodingKeys: String, CodingKey {
    case p50Ns = "p50_ns"
    case p99Ns = "p99_ns"
    case maxNs = "max_ns"
    case count
    case budgetNs = "budget_ns"
    case passed
    case deviceAnnotation = "device_annotation"
    case methodology
    case note
  }
}

let passed = histogram.p99 < budgetNs

let report = GlassToGlassReport(
  p50Ns: histogram.p50,
  p99Ns: histogram.p99,
  maxNs: histogram.max,
  count: histogram.count,
  budgetNs: budgetNs,
  passed: passed,
  deviceAnnotation: deviceAnnotation,
  methodology: GlassToGlassTimer.methodologyLabel,
  note: "M5-Pro corroborating; the canonical iPad-M4 capture (real CAMetalDisplayLink "
    + "targetPresentationTimestamp) is the Plan 07 never-auto-approve HUMAN-UAT gate (D-08)."
)

let outputDir = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent() // CortexDemoBench
  .deletingLastPathComponent() // Sources
  .deletingLastPathComponent() // CortexDemo (package root)
  .appendingPathComponent(".bench", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let jsonURL = outputDir.appendingPathComponent("glass_to_glass.json")
do {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(report).write(to: jsonURL)
} catch {
  print("CortexDemoBench: warning — failed to write \(jsonURL.path): \(error)")
}

// MARK: - Report

print(
  "CortexDemoBench — software-timed glass-to-glass latency (n=\(histogram.count) ticks, seed=0x\(String(seed, radix: 16, uppercase: true)))"
)
print("  p50 = \(histogram.p50) ns  (\(String(format: "%.3f", Double(histogram.p50) / 1_000_000)) ms)")
print("  p99 = \(histogram.p99) ns  (\(String(format: "%.3f", Double(histogram.p99) / 1_000_000)) ms)")
print("  max = \(histogram.max) ns  (\(String(format: "%.3f", Double(histogram.max) / 1_000_000)) ms)")
print("  device = \(deviceAnnotation)")
print("  methodology: \(GlassToGlassTimer.methodologyLabel)")
print("  NOTE: M5-Pro CORROBORATING. The canonical iPad-M4 capture (real CAMetalDisplayLink")
print("        targetPresentationTimestamp) is the Plan 07 never-auto-approve HUMAN-UAT gate (D-08).")
print("  wrote: \(jsonURL.path)")

if passed {
  print(
    "  PASS (PERF-04): p99 \(histogram.p99) ns < 25 ms budget (\(budgetNs) ns) — software-timed, M5-Pro corroborating."
  )
  exit(0)
} else {
  print(
    "  FAIL (PERF-04): p99 \(histogram.p99) ns >= 25 ms budget (\(budgetNs) ns) — software-timed pipeline over budget."
  )
  exit(1)
}
