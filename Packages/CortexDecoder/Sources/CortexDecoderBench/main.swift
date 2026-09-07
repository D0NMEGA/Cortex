// CortexDecoderBench — the in-process Swift latency bench (DEC-11).
//
// 05-RESEARCH Decision 5: latency MUST be measured IN-PROCESS in Swift, NOT via Python predict()
// (whose wall-time is IPC/marshalling-dominated and misleads on a ~1.3M-param model). This tool:
//   1. resolves the .mlpackage / .mlmodelc from CORTEX_DECODER_MODEL_URL (env) or argv[1];
//      if absent it prints a usage/skip message and exits 0 (a clean clone / CI without the
//      gitignored model artifact must NOT fail — the bench is a manual / on-device tool);
//   2. builds the Plan-03 zero-copy SpikeInputBuffer once and fills it with a representative
//      fp16 spike pattern (reused across passes so the loop times inference, not buffer setup);
//   3. runs `warmup` passes (the first prediction triggers compile/load), then 10,000 timed
//      `decode` passes, recording per-call nanoseconds with ContinuousClock;
//   4. annotates the measurement with the device the ops actually ran on, summarized from
//      MLComputePlan (.preferred over every op) -> "NeuralEngine" / "CPU" / "mixed";
//   5. builds a LatencyHistogram, prints `p50=… p99=… device=…`, and writes
//      latency_histogram.json (+ a bins CSV, and a PNG when headless CoreGraphics rendering
//      succeeds) under a gitignored output dir.
//
// THE VENUE SPLIT (load-bearing, 05-RESEARCH Decision 5 / Risk #1): on the M5 Mac the 1.29M-param
// model may CPU-PLACE (the scale trap), so a Mac number reflects CPU latency — which is exactly why
// the device annotation matters and why this bench NEVER enforces the canonical latency threshold
// (it prints the number; it never fails on a Mac tail percentile). The Mac number is CORROBORATING;
// the canonical sub-threshold-on-ANE claim is the iPad-M4 run of THIS SAME executable in Plan 05's
// HUMAN-UAT runbook.
//
// No force-unwrap of model load / Metal device / prediction (threat T-05-04-03): every fallible
// step fails closed with a clear message and a nonzero exit ONLY for a genuine setup error (never
// for the latency value itself).
import CoreGraphics
import CoreML
import CortexDecoder
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

// MARK: - Configuration

/// DEC-11: 10,000 forward passes (the canonical sample size).
let passCount = 10000
/// Warmup passes before timing — the FIRST prediction triggers Core ML compile/load (Decision 5).
let warmup = 50
/// The spike window length (20ms time bins). The Plan-01 input contract is `(1, 96, 1, S)` fp16.
let sequenceLength = 32

// MARK: - Model URL resolution (env / argv) — skip cleanly when absent

/// Resolves the model URL from `CORTEX_DECODER_MODEL_URL` (preferred) or the first CLI argument.
func resolveModelURL() -> URL? {
  if let envPath = ProcessInfo.processInfo.environment["CORTEX_DECODER_MODEL_URL"],
     !envPath.isEmpty
  {
    return URL(fileURLWithPath: envPath)
  }
  // argv[0] is the executable path; argv[1] (if present) is the model path.
  let args = CommandLine.arguments
  if args.count > 1, !args[1].isEmpty {
    return URL(fileURLWithPath: args[1])
  }
  return nil
}

let usage = """
CortexDecoderBench — in-process NDT1 latency histogram (DEC-11)

  No model URL provided, so there is nothing to measure — exiting 0 (this is the expected path on
  a clean clone / CI, where the .mlpackage is gitignored R&D output).

  To run the bench, point it at a built (vx,vy) .mlpackage or compiled .mlmodelc:

    swift build --package-path Packages/CortexDecoder
    CORTEX_DECODER_MODEL_URL=/path/to/ndt1_4bit.mlpackage \\
      swift run --package-path Packages/CortexDecoder CortexDecoderBench

  It runs \(warmup) warmup + \(passCount) timed passes, prints p50/p99 + the device the ops ran on,
  and writes latency_histogram.json under Packages/CortexDecoder/.bench/ (gitignored).

  NOTE: a Mac number is CORROBORATING (the 1.29M-param model may CPU-place — the scale trap);
  the canonical sub-threshold tail-latency-on-ANE claim is the iPad-M4 run of this same executable.
"""

guard let modelURL = resolveModelURL() else {
  print(usage)
  exit(0)
}

guard FileManager.default.fileExists(atPath: modelURL.path) else {
  print("CortexDecoderBench: model path does not exist: \(modelURL.path)")
  print("Exiting 0 (no model to measure). See usage:\n")
  print(usage)
  exit(0)
}

// MARK: - Compile the model artifact if needed (.mlpackage -> .mlmodelc)

/// Core ML cannot load a raw `.mlpackage` at runtime — `MLModel(contentsOf:)` and
/// `MLComputePlan.load` both require a COMPILED `.mlmodelc` (05-RESEARCH Risk #4). The
/// `CORTEX_DECODER_MODEL_URL` convention (Plan 03) documents that the URL may be either form, so
/// the bench compiles a `.mlpackage` to a `.mlmodelc` ONCE, before the timed loop, via
/// `MLModel.compileModel(at:)` (so compilation never enters the latency measurement). A path that
/// is already a `.mlmodelc` is returned unchanged.
func compileIfNeeded(_ url: URL) async throws -> URL {
  guard url.pathExtension.lowercased() == "mlpackage" else { return url }
  return try await MLModel.compileModel(at: url)
}

// MARK: - Device annotation (which device the ops actually ran on)

/// Summarizes the per-operation PREFERRED compute device from the model's MLComputePlan into a
/// single annotation string. This is what distinguishes a corroborating Mac (likely "CPU" at
/// 1.29M params — the scale trap) from the canonical iPad-M4 "NeuralEngine" placement.
///
/// Returns "NeuralEngine" if every schedulable op prefers the ANE, "CPU"/"GPU" if uniform on one,
/// "mixed (...)" with a tally otherwise, or "unknown-mac" if the plan could not be loaded.
///
/// `@MainActor`: it reads `NeuralDecoder.productionConfiguration()` (the DEC-07 single source of
/// truth, MainActor-isolated) and `MLModelConfiguration` is non-Sendable, so building + using it
/// stays on the main actor (no cross-actor send). The one async hop is `MLComputePlan.load`.
@MainActor
func deviceAnnotation(for url: URL) async -> String {
  // Reflect the production placement: take the compute-units VALUE from the DEC-07 single source of
  // truth, but apply it to a fresh local MLModelConfiguration so this non-Sendable object is not
  // sent across the actor boundary into the nonisolated MLComputePlan.load (it is created and used
  // only here). The placement tally is meaningful precisely because it uses .cpuAndNeuralEngine.
  let units = NeuralDecoder.productionConfiguration().computeUnits
  let configuration = MLModelConfiguration()
  configuration.computeUnits = units
  do {
    let plan = try await MLComputePlan.load(contentsOf: url, configuration: configuration)
    guard case let .program(program) = plan.modelStructure,
          let main = program.functions["main"]
    else {
      return "unknown-mac"
    }
    var tally: [String: Int] = [:]
    for op in main.block.operations {
      guard let usage = plan.deviceUsage(for: op) else { continue }
      // MLComputeDevice is an ENUM: .cpu(_) | .gpu(_) | .neuralEngine(_) (05-RESEARCH Decision 2).
      let key = switch usage.preferred {
      case .neuralEngine: "NeuralEngine"
      case .cpu: "CPU"
      case .gpu: "GPU"
      @unknown default: "Other"
      }
      tally[key, default: 0] += 1
    }
    guard !tally.isEmpty else { return "unknown-mac" }
    if tally.count == 1, let only = tally.keys.first {
      return only
    }
    let summary = tally.sorted { $0.key < $1.key }
      .map { "\($0.key):\($0.value)" }
      .joined(separator: ",")
    return "mixed (\(summary))"
  } catch {
    return "unknown-mac (\(String(describing: error)))"
  }
}

// MARK: - Output paths (gitignored .bench/ dir)

let outputDir = URL(fileURLWithPath: #filePath) // .../Sources/CortexDecoderBench/main.swift
  .deletingLastPathComponent() // CortexDecoderBench
  .deletingLastPathComponent() // Sources
  .deletingLastPathComponent() // CortexDecoder (package root)
  .appendingPathComponent(".bench", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let jsonURL = outputDir.appendingPathComponent("latency_histogram.json")
let csvURL = outputDir.appendingPathComponent("latency_histogram_bins.csv")
let pngURL = outputDir.appendingPathComponent("latency_histogram.png")

// MARK: - Bench run

/// Converts a ContinuousClock Duration to whole nanoseconds (seconds term included for correctness;
/// for a sub-ms prediction the seconds component is 0, but a pathological slow pass must not be
/// silently zeroed).
func nanoseconds(_ duration: Duration) -> UInt64 {
  let c = duration.components
  let fromSeconds = UInt64(Swift.max(0, c.seconds)) &* 1_000_000_000
  let fromAttos = UInt64(Swift.max(0, c.attoseconds) / 1_000_000_000) // 1e18 attos/s ÷ 1e9 = ns
  return fromSeconds &+ fromAttos
}

/// Renders a minimal bin-count bar histogram to a PNG via a headless CoreGraphics bitmap context.
/// Returns true on success; the JSON + CSV are the committed numbers, so PNG failure is non-fatal
/// (honest fallback — the PNG is also produced device-side via Instruments in Plan 05).
func writeHistogramPNG(bins: [Int], to url: URL) -> Bool {
  guard !bins.isEmpty, let maxCount = bins.max(), maxCount > 0 else { return false }
  let width = Swift.max(bins.count * 4, 256)
  let height = 200
  guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  ) else { return false }
  ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))
  ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
  ctx.setFillColor(CGColor(red: 0.30, green: 0.78, blue: 0.95, alpha: 1))
  let barWidth = CGFloat(width) / CGFloat(bins.count)
  for (i, count) in bins.enumerated() {
    let barHeight = CGFloat(count) / CGFloat(maxCount) * CGFloat(height - 8)
    ctx.fill(CGRect(x: CGFloat(i) * barWidth, y: 0, width: Swift.max(1, barWidth - 1), height: barHeight))
  }
  guard let image = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { return false }
  CGImageDestinationAddImage(dest, image, nil)
  return CGImageDestinationFinalize(dest)
}

/// 50-bin linear histogram over [min, max] ns (for the PNG/CSV bin counts).
func binCounts(_ samples: [UInt64], bins: Int = 50) -> (edges: [UInt64], counts: [Int]) {
  guard let lo = samples.min(), let hi = samples.max(), hi > lo else {
    return (edges: [samples.first ?? 0], counts: [samples.count])
  }
  let span = Double(hi - lo)
  var counts = [Int](repeating: 0, count: bins)
  for s in samples {
    let frac = Double(s - lo) / span
    let idx = Swift.min(bins - 1, Int(frac * Double(bins)))
    counts[idx] += 1
  }
  let edges = (0 ... bins).map { lo + UInt64(Double($0) / Double(bins) * span) }
  return (edges: edges, counts: counts)
}

// `@MainActor`: NeuralDecoder / SpikeInputBuffer are MainActor-isolated (the library sets
// `.defaultIsolation(MainActor.self)`), so the decode loop runs on the main actor — the canonical
// way to drive that API (matching the Plan-03 @MainActor test suites). A sequential bench has no
// need for off-actor work; the only async hop is `await MLComputePlan.load` inside deviceAnnotation.
@MainActor
// Same shape as the other bench drivers: guard the device, compile the model once outside the
// timed region, run the measured loop, annotate the device, emit. The branches are the failure
// guards this bench must not skip, and the length is the sequence, not tangled logic.
// swiftlint:disable:next function_body_length cyclomatic_complexity
func runBench() async -> Int32 {
  // Metal device (unified memory) — guard, never force-unwrap (threat T-05-04-03).
  guard let device = MTLCreateSystemDefaultDevice() else {
    print("CortexDecoderBench: no Metal device available — cannot allocate the shared spike buffer.")
    return 1
  }

  // Compile the .mlpackage to a .mlmodelc ONCE (before timing) — Core ML cannot load a raw
  // .mlpackage at runtime (05-RESEARCH Risk #4). A .mlmodelc path passes through unchanged.
  let compiledURL: URL
  do {
    compiledURL = try await compileIfNeeded(modelURL)
  } catch {
    print("CortexDecoderBench: failed to compile model at \(modelURL.path): \(error)")
    return 1
  }

  let decoder: NeuralDecoder
  do {
    decoder = try NeuralDecoder(modelURL: compiledURL)
  } catch {
    print("CortexDecoderBench: failed to load model at \(compiledURL.path): \(error)")
    return 1
  }

  let input: SpikeInputBuffer
  do {
    input = try SpikeInputBuffer(device: device, seqLen: sequenceLength)
  } catch {
    print("CortexDecoderBench: failed to allocate the zero-copy spike buffer: \(error)")
    return 1
  }

  // Fill the input ONCE with a representative fp16 spike pattern (reused across passes so the loop
  // measures inference, not buffer setup). A mild deterministic ramp keeps the rates non-degenerate.
  do {
    for channel in 0 ..< input.channels {
      for bin in 0 ..< input.seqLen {
        let value = Float16(Float((channel + bin) % 5) * 0.5)
        try input.write(value, channel: channel, bin: bin)
      }
    }
  } catch {
    print("CortexDecoderBench: failed to fill the spike buffer: \(error)")
    return 1
  }

  // Warmup — the first prediction triggers Core ML compile/load (Decision 5).
  do {
    for _ in 0 ..< warmup {
      _ = try decoder.decode(input)
    }
  } catch {
    print("CortexDecoderBench: a warmup prediction failed: \(error)")
    return 1
  }

  // Timed loop — 10,000 in-process passes, per-call ns via ContinuousClock.
  let clock = ContinuousClock()
  var samples = [UInt64]()
  samples.reserveCapacity(passCount)
  do {
    for _ in 0 ..< passCount {
      let t0 = clock.now
      _ = try decoder.decode(input)
      let elapsed = clock.now - t0
      samples.append(nanoseconds(elapsed))
    }
  } catch {
    print("CortexDecoderBench: a timed prediction failed: \(error)")
    return 1
  }

  // Device annotation — which device the ops actually ran on (corroborating-vs-canonical pivot).
  // Uses the COMPILED url (MLComputePlan.load also requires a .mlmodelc — 05-RESEARCH Risk #4).
  let annotation = await deviceAnnotation(for: compiledURL)

  let histogram = LatencyHistogram(samplesNs: samples, deviceAnnotation: annotation)

  // Write the committed numbers (JSON) + the bins CSV + a PNG (best-effort).
  let (edges, counts) = binCounts(samples)
  do {
    try histogram.encodedJSON().write(to: jsonURL)
    var csv = "bin_lo_ns,bin_hi_ns,count\n"
    for i in 0 ..< counts.count {
      let lo = edges[Swift.min(i, edges.count - 1)]
      let hi = edges[Swift.min(i + 1, edges.count - 1)]
      csv += "\(lo),\(hi),\(counts[i])\n"
    }
    try csv.write(to: csvURL, atomically: true, encoding: .utf8)
  } catch {
    print("CortexDecoderBench: warning — failed to write histogram artifacts: \(error)")
    // Non-fatal: the printed numbers below are still the measurement.
  }
  let pngOK = writeHistogramPNG(bins: counts, to: pngURL)

  // Report. The bench prints the number and always returns success — it never enforces the
  // canonical latency threshold on a Mac tail percentile (that gate belongs to the iPad-M4 run,
  // Plan 05). The Mac number is corroborating, tagged with the device annotation.
  print("CortexDecoderBench — DEC-11 in-process latency (n=\(passCount), warmup=\(warmup))")
  print("  p50=\(histogram.p50) ns  p99=\(histogram.p99) ns  min=\(histogram.min) ns  max=\(histogram.max) ns")
  print("  device=\(annotation)")
  print("  wrote: \(jsonURL.path)")
  print("         \(csvURL.path)")
  print(pngOK ? "         \(pngURL.path)" :
    "  (PNG skipped — JSON + bins CSV are the committed numbers; PNG is produced device-side in Plan 05)")
  if annotation.hasPrefix("CPU") || annotation.contains("CPU:") {
    print("  NOTE: ops PREFER the CPU here — this Mac number is CORROBORATING (the 1.29M-param scale trap,")
    print("        05-RESEARCH Risk #1), NOT the canonical sub-threshold tail-latency-on-ANE claim (iPad-M4, Plan 05).")
  }
  return 0
}

let status = await runBench()
exit(status)
