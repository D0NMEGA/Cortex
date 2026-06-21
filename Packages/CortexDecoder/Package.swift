// swift-tools-version: 6.2
// Phase 5 — CoreML deployment of the NDT1 decoder with verified ANE residency.
// See REQUIREMENTS.md DEC-06 through DEC-12.
//
// Plan 05-03 (Wave 2) grows this from an 8-line stub into the real Swift in-process
// inference path:
//   • NeuralDecoder loads the Plan-01 (vx,vy) .mlpackage with
//     MLModelConfiguration.computeUnits = .cpuAndNeuralEngine (NOT .all) — DEC-07.
//   • ZeroCopyInput feeds spikes zero-copy via MLMultiArray(pixelBuffer:shape:) over an
//     IOSurface shared with an MTLBuffer storageModeShared (OneComponent16Half) — DEC-09.
//   • A NEW CortexDecoderTests target (the package had none) carries the build-failing
//     compute-units gate, the pointer-identity zero-copy proof, and the (vx,vy) output
//     shape/dtype check (DEC-07/09/10 Swift-side; DEC-12 Swift-side mirror).
// CoreML / Metal / IOSurface / CoreVideo are system frameworks: they resolve via `import`
// on Apple platforms, so no explicit linkerSettings are required (mirrors how CortexIPC
// pulls in CryptoKit).
//
// Plan 05-04 (Wave 3) adds the in-process latency bench (DEC-11): the LatencyHistogram pure
// value type joins the library (unit-tested with no model), and a NEW CortexDecoderBench
// .executableTarget drives warmup + 10,000 MLModel.prediction passes over the zero-copy decoder,
// times each with ContinuousClock, and writes a device-annotated latency_histogram.json. The
// bench is a MANUAL / on-device tool (the canonical <2ms-p99 claim is the iPad-M4 run in Plan 05);
// it is NOT a `swift test` timing gate — only the histogram math is unit-tested (D-18).
import PackageDescription

let package = Package(
  name: "CortexDecoder",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexDecoder", targets: ["CortexDecoder"]),
    .executable(name: "CortexDecoderBench", targets: ["CortexDecoderBench"]),
  ],
  targets: [
    .target(
      name: "CortexDecoder",
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    // Plan 05-04 (DEC-11): the in-process Swift latency bench. A top-level main.swift runs on the
    // main actor by default (fine for a sequential bench) and supports top-level `await` for
    // MLComputePlan.load. It loads the .mlpackage from CORTEX_DECODER_MODEL_URL / argv[1], runs the
    // 10k-pass timed loop, and writes latency_histogram.json — NEVER gating on <2ms (the canonical
    // gate is the iPad-M4 run, Plan 05). Exits 0 with a usage message when no model is present.
    .executableTarget(
      name: "CortexDecoderBench",
      dependencies: ["CortexDecoder"]
    ),
    // Net-new in Plan 05-03 (Wave-0 scaffold per 05-VALIDATION): the package had no test
    // target. Carries ComputeUnitsTests (DEC-07 build gate), ZeroCopyInputTests (DEC-09
    // pointer identity), VelocityOutputTests (DEC-10 output + DEC-12 Swift-side scan), and
    // LatencyHistogramTests (DEC-11 pure percentile math, no model — Plan 05-04).
    .testTarget(
      name: "CortexDecoderTests",
      dependencies: ["CortexDecoder"]
    ),
  ]
)
