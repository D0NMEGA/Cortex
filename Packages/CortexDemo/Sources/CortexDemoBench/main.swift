// CortexDemoBench — Phase 8 (PERF-04, D-07/D-08): the headless SOFTWARE-TIMED glass-to-glass latency
// bench. Mirrors CortexReFITBench / CortexDecoderBench (a dedicated bench executable, NOT a swift-test
// timing gate — D-18 precedent keeps a flaky latency assertion out of CI).
//
// ## What it measures (08-RESEARCH §0.3/§5, D-07)
// It drives the `ClosedLoopPipeline` for n ≥ 10,000 ticks. For each tick it records the intent-emission
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
import CortexCore // Time.machAbsoluteNanoseconds — the intent-emission clock (PERF-04, §1.3).
import CortexDecoder // LatencyHistogram (reused percentile value type).
import CortexDemo // ClosedLoopPipeline + GlassToGlassTimer (the software-timed measurement under test).
import Foundation
import simd

// MARK: - CLI flags

let arguments = CommandLine.arguments
let isSmoke = arguments.contains("--smoke")
let isFull = arguments.contains("--full")

let usage = """
CortexDemoBench — headless SOFTWARE-TIMED glass-to-glass latency bench (PERF-04, D-07/D-08).

  No flag was passed, so there is nothing to measure — exiting 0 (the expected clean-clone / CI path
  when this bench is invoked without a mode).

  Run the CI-fast smoke budget (still proves the bench + the determinism + the PERF-04 assertion):

    swift run --package-path Packages/CortexDemo CortexDemoBench --smoke

  Run the full n = 10,000-tick corroborating bench (M5 Pro):

    swift run --package-path Packages/CortexDemo CortexDemoBench --full

  It drives ClosedLoopPipeline, records intent-emission mach_absolute_time -> ns, models the on-glass
  present time as a SIMULATED targetPresentationTimestamp (intent + measured pipeline cost, advanced to
  the next 120Hz present boundary), builds a device-annotated LatencyHistogram, prints p50/p99/max + the
  verbatim methodology label, writes .bench/glass_to_glass.json, and ASSERTS p99 < 25 ms (PERF-04).

  This is the SOFTWARE-TIMED number (excludes the compositor scanout — the v1 photodiode delta). The
  canonical iPad-M4 capture is the Plan 07 never-auto-approve HUMAN-UAT gate (D-08); this M5-Pro number
  is CORROBORATING.
"""

// Clean-clone / CI: no flag -> usage/skip, exit 0.
if !isSmoke, !isFull {
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
/// The determinism seed for the driven pipeline (matches the closed-loop tests).
let seed: UInt64 = 0xC0FFEE
/// The device annotation — WHY this is an M5-Pro CORROBORATING number, NOT the iPad-M4 canonical claim.
let deviceAnnotation = "M5-Pro-software-timed-corroborating"

// MARK: - Drive the closed loop + record software-timed latencies

// One warm pipeline driven continuously (the live closed loop). Each tick: record intent emission,
// time the pipeline cost inline, model the present timestamp, sample the software-timed latency.
let pipeline = ClosedLoopPipeline(seed: seed)
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
  let p50_ns: UInt64
  let p99_ns: UInt64
  let max_ns: UInt64
  let count: Int
  let budget_ns: UInt64
  let passed: Bool
  let device_annotation: String
  let methodology: String
  let note: String
}

let passed = histogram.p99 < budgetNs

let report = GlassToGlassReport(
  p50_ns: histogram.p50,
  p99_ns: histogram.p99,
  max_ns: histogram.max,
  count: histogram.count,
  budget_ns: budgetNs,
  passed: passed,
  device_annotation: deviceAnnotation,
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
