// CortexRenderBench — the macOS GPU-time / frame-pacing measurement executable (RENDER-05/09, SC#2/SC#4).
//
// Plan 04 wired the `type: tool` target + scheme + a one-line stub so xcodegen/xcodebuild resolve it
// end-to-end. Plan 05 fills it with the real measurement on the M5 Pro MacBook Pro ProMotion panel
// (CONTEXT D-11 corroborating-canonical):
//   • GPUTimeHistogram — the real `webgrid` compute pass over n≥10k offscreen frames via
//     commandBuffer.gpuStartTime/gpuEndTime → a p50/p95/p99 histogram vs the ≤0.4ms SC#2 bound.
//   • FrameSoak — a 60s sustained-throughput soak counting per-frame intervals and flagging any
//     interval > 8.33ms (the 120Hz budget, SC#4), driven by the deterministic LissajousProducer (D-05).
// In-process bench, NOT a swift-test timing gate (D-18 — a flaky latency assertion stays out of CI).
//
// ## Usage (all args optional; defaults are the load-bearing ≥10k-frame run)
//   CortexRenderBench [frames] [WxH] [--warmup K] [--soak [seconds]] [--out DIR]
//     frames        measured GPU-time frames (default 10000; clamped to ≥10000 per RENDER-05)
//     WxH           offscreen drawable extent (default 2752x2064 — iPad-Pro-M4-13"-ish)
//     --warmup K    discarded warmup frames (default 200)
//     --soak [sec]  ALSO run the FrameSoak throughput soak (default 60s) after the histogram
//     --out DIR     where to write gpu_time_hist.json + soak_log.json
//                   (default: the phase dir under .planning/…/06-…)
// Examples:
//   CortexRenderBench                         # 10k-frame histogram, default extent, default out dir
//   CortexRenderBench 20000 2752x2064 --soak  # 20k histogram + a full 60s soak
//   CortexRenderBench --soak 5                # quick 5s soak smoke (CI-friendly subset)

import Foundation

/// ── argument parsing (tiny, no dependency) ───────────────────────────────────────────────────────
struct BenchArgs {
  var frames = 10000
  var warmup = 200
  var width = 2752
  var height = 2064
  var runSoak = false
  var soakSeconds = 60.0
  var outDir: URL = defaultOutDir()

  /// Default output dir: the Phase-6 planning dir (where the evidence doc + artifacts live), resolved
  /// relative to the current working directory (the repo root when run via the scheme/xcodebuild).
  static func defaultOutDir() -> URL {
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: cwd)
      .appendingPathComponent(".planning/phases/06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid")
  }
}

// One `while` over argv with one `switch` case per accepted flag. The complexity IS the flag
// count: extracting cases into helpers moves the branches without removing any, and splits a
// parser that is easiest to audit as one table.
// swiftlint:disable:next cyclomatic_complexity
func parseArgs(_ argv: [String]) -> BenchArgs {
  var a = BenchArgs()
  var i = 0
  let args = Array(argv.dropFirst()) // drop the executable path
  while i < args.count {
    let tok = args[i]
    switch tok {
    case "--warmup":
      if i + 1 < args.count, let k = Int(args[i + 1]) { a.warmup = max(0, k)
        i += 1
      }
    case "--soak":
      a.runSoak = true
      // Optional numeric seconds immediately after --soak.
      if i + 1 < args.count, let s = Double(args[i + 1]) { a.soakSeconds = max(0.1, s)
        i += 1
      }
    case "--out":
      if i + 1 < args.count { a.outDir = URL(fileURLWithPath: args[i + 1])
        i += 1
      }
    default:
      // Positional: a bare integer is `frames`; a WxH token sets the extent.
      if let f = Int(tok) {
        a.frames = f
      } else if let x = tok.firstIndex(where: { $0 == "x" || $0 == "X" }) {
        let wStr = String(tok[tok.startIndex ..< x])
        let hStr = String(tok[tok.index(after: x)...])
        if let w = Int(wStr), let h = Int(hStr), w > 0, h > 0 { a.width = w
          a.height = h
        }
      }
    }
    i += 1
  }
  // RENDER-05: the GPU-time histogram MUST be over n ≥ 10_000 frames. Clamp up, never silently below.
  a.frames = max(a.frames, 10000)
  return a
}

/// ── ISO-8601 timestamp for the artifacts ──────────────────────────────────────────────────────────
func isoNow() -> String {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime]
  return f.string(from: Date())
}

// ── run ───────────────────────────────────────────────────────────────────────────────────────────
let args = parseArgs(CommandLine.arguments)
let date = isoNow()

try FileManager.default.createDirectory(at: args.outDir, withIntermediateDirectories: true)

/// The bench body. `@MainActor` because it drives the MainActor-isolated `WebgridFrameEncoder`
/// (CortexRender's `.defaultIsolation(MainActor.self)`). `main.swift` top-level code runs on the main
/// thread, so we enter it via `MainActor.assumeIsolated` (sound: the tool has no other threads).
@MainActor
func runBench(_ args: BenchArgs, date: String) throws {
  // RENDER-05 / SC#2 — GPU-time histogram over the real webgrid compute pass.
  print(
    "CortexRenderBench — GPU-time histogram: \(args.frames) frames "
      + "(\(args.warmup) warmup) @ \(args.width)x\(args.height) offscreen"
  )
  let r = try GPUTimeHistogram.run(
    frames: args.frames, warmup: args.warmup, width: args.width, height: args.height
  )
  let s = r.stats
  print("  device      : \(r.deviceName)  (M5 Pro ProMotion — corroborating-canonical, D-11)")
  print("  samples     : \(s.count)")
  print(
    String(
      format: "  GPU time ms : p50=%.4f  p95=%.4f  p99=%.4f  min=%.4f  max=%.4f  mean=%.4f",
      s.p50Ms, s.p95Ms, s.p99Ms, s.minMs, s.maxMs, s.meanMs
    )
  )
  let bound = 0.4
  let verdict = s.p99Ms <= bound ? "PASS" : "OVER"
  print(
    String(
      format: "  SC#2 <=%.1fms: %@  (p99=%.4fms, margin=%.4fms / %.1fx)",
      bound, verdict, s.p99Ms, bound - s.p99Ms, bound / max(s.p99Ms, 1e-9)
    )
  )
  try GPUTimeHistogram.writeJSON(to: args.outDir, run: r, iso8601Date: date)
  print("  wrote       : \(args.outDir.appendingPathComponent("gpu_time_hist.json").path)")

  // SC#4 — sustained-throughput soak (optional; --soak). The soak measurement lives in
  // FrameSoak.swift: `runFrameSoak(args:date:)` measures the frame intervals, flags any > 8.33ms,
  // and writes soak_log.json.
  if args.runSoak {
    try runFrameSoak(args: args, date: date)
  }
}

MainActor.assumeIsolated {
  do {
    try runBench(args, date: date)
  } catch {
    FileHandle.standardError.write(Data("CortexRenderBench ERROR: \(error)\n".utf8))
    exit(1)
  }
}
