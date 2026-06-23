// swift-tools-version: 6.2
// CortexDemo — Phase 8 (SYS-06, PERF-04, D-09/D-10): the v0 closed-loop ASSEMBLY package.
//
// This is the HEART of v0 (08-CONTEXT D-09/D-10, 08-RESEARCH §0.3/§5). It wires the prior phases'
// halves into ONE running synthetic-spike → NDT1 (CoreML) → ReFIT-Kalman → CursorIntegrator → 30×30
// webgrid closed loop, so the DECODER + KALMAN are GENUINELY in the loop (NOT the Phase-6 Lissajous
// shortcut, which bypasses the decoder and would make SYS-06 hollow — D-10).
//
//   • ClosedLoopPipeline  — the assembly: SyntheticSpikeSource → [NeuralDecoder.decode | synthetic
//     decoded-velocity fallback] → KalmanFilter.step → CursorIntegrator.integrate → WebgridAcquisition.
//     The NeuralDecoder.decode call site is present + compiled (D-10) and routes spikes through NDT1
//     when CORTEX_MODEL_URL points at a real model; the deterministic synthetic decoded-velocity
//     (the CortexReFITBench `decodedVelocity` idiom) runs the loop on a clean clone / CI without the
//     gitignored .mlpackage. NO RNG / NO wall-clock on the simulation path (reproducible — D-13).
//   • GlassToGlassTimer   — the software-timed glass-to-glass measurement using the CAMetalDisplayLink
//     `targetPresentationTimestamp` (the ON-GLASS present time), NOT `targetTimestamp` (the render
//     deadline) — 08-RESEARCH §0.3/§5, PERF-04/D-07. Embeds the verbatim D-07 honesty label.
//   • CortexDemoBench     — a headless software-timed latency bench (M5-Pro CORROBORATING) asserting
//     p99 < 25ms (PERF-04). The canonical iPad-M4 capture is the Plan 07 never-auto-approve HUMAN-UAT
//     gate (D-08) — the headless number is M5-Pro-corroborating, NOT the iPad photodiode claim.
//
// Mirrors CortexReFIT/Package.swift's structure (library + bench executable + test target). The
// library carries `.defaultIsolation(MainActor.self)` per Approachable Concurrency (the pipeline is
// driven off the hot path, alongside the SwiftUI demo — it is the assembly, not the audio hot path).
import PackageDescription

let package = Package(
  name: "CortexDemo",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexDemo", targets: ["CortexDemo"]),
    // The headless software-timed latency bench (PERF-04, M5-Pro corroborating). Mirrors the
    // CortexReFITBench / CortexDecoderBench executable entry — a dedicated bench, not a swift-test
    // timing gate (D-18 precedent: keeps a flaky latency assertion out of CI).
    .executable(name: "CortexDemoBench", targets: ["CortexDemoBench"])
  ],
  dependencies: [
    // The decoder/filter/render seam the pipeline assembles (already built in Phases 5/6/7).
    .package(path: "../CortexDecoder"), // NeuralDecoder (NDT1 CoreML) + SpikeInputBuffer + LatencyHistogram.
    .package(path: "../CortexReFIT"), // KalmanFilter.step (the ReFIT-Kalman stage) + WebgridAcquisition.
    .package(path: "../CortexRender"), // CursorIntegrator + CursorVelocity + VelocityRing + WebgridView.
    .package(path: "../CortexBCIHID"), // ScanInfoRoundTrip — the SYS-03/04 instrumented round trip the GUI surfaces.
    .package(path: "../CortexCore") // Time.machAbsoluteNanoseconds — the intent-emission clock (PERF-04).
  ],
  targets: [
    .target(
      name: "CortexDemo",
      dependencies: [
        .product(name: "CortexDecoder", package: "CortexDecoder"),
        .product(name: "CortexReFIT", package: "CortexReFIT"),
        .product(name: "CortexRender", package: "CortexRender"),
        .product(name: "CortexBCIHID", package: "CortexBCIHID"),
        .product(name: "CortexCore", package: "CortexCore")
      ],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    // The headless software-timed latency bench (PERF-04). A top-level main.swift runs on the main
    // actor by default (fine for a sequential bench). It drives ClosedLoopPipeline for n ≥ 10,000
    // ticks, builds a device-annotated LatencyHistogram from a SIMULATED targetPresentationTimestamp,
    // asserts p99 < 25ms (M5-Pro corroborating), writes .bench/glass_to_glass.json (.sortedKeys), and
    // prints the verbatim D-07 methodology label. Exits 0 with usage when no flag (clean-clone skip).
    .executableTarget(
      name: "CortexDemoBench",
      dependencies: [
        "CortexDemo",
        .product(name: "CortexDecoder", package: "CortexDecoder"),
        .product(name: "CortexReFIT", package: "CortexReFIT"),
        .product(name: "CortexRender", package: "CortexRender"),
        .product(name: "CortexCore", package: "CortexCore")
      ]
    ),
    .testTarget(
      name: "CortexDemoTests",
      dependencies: ["CortexDemo"]
    )
  ]
)
