// swift-tools-version: 6.2
// CortexDemo — Phase 8 (SYS-06, PERF-04, D-09/D-10): the v0 replay-loop ASSEMBLY package.
//
// This is the HEART of v0 (08-CONTEXT D-09/D-10, 08-RESEARCH §0.3/§5). It wires the prior phases'
// halves into ONE running synthetic-spike → NDT1 (CoreML) → ReFIT-Kalman → CursorIntegrator → 30×30
// webgrid replay loop, so the DECODER + KALMAN are GENUINELY in the loop (NOT the Phase-6 Lissajous
// shortcut, which bypasses the decoder and would make SYS-06 hollow — D-10).
//
//   • ReplayPipeline  — the assembly: SyntheticSpikeSource → [NeuralDecoder.decode | synthetic
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
    .executable(name: "CortexDemoBench", targets: ["CortexDemoBench"]),
    // The RD-07 four-arm real-data ablation over the D-06 replay export (Phase 10, Plan 10-05).
    //
    // A SEPARATE executable rather than a fourth `Arm` case in CortexReFITBench, on purpose. That
    // bench's `--smoke` output is a byte-identity build gate in two places - the refit_bps.json diff
    // at ci.yml:378-388 and the committed-webgrid_bps.json leg of bps-policy.sh - and D-09 requires
    // those bytes to hold so a real-data finding can never redden the build. A fourth case would put
    // the real-data path inside the frozen fixture. Separating them means the fixture keeps guarding
    // the filter code on the frozen Phase-7 gain while this executable exercises the shipped re-fit
    // gain on real spikes (RESEARCH Pitfall 6).
    .executable(name: "CortexReplayBench", targets: ["CortexReplayBench"]),
    // The RD-08 Seam B chain smoke (Phase 10, Plan 10-06): the D-05 chain end to end — export bin,
    // AES-GCM seal, shm ring, doorbell, decrypt, ordering, 32-bin accumulation, SpikeInputBuffer fill,
    // decode, cursor integration, HID pointer-report encode. A SwiftPM executable rather than a mode
    // on CortexDaemon because `Apps/` is built by xcodebuild, and a CI step has to be `swift run`.
    .executable(name: "CortexSeamBSmoke", targets: ["CortexSeamBSmoke"])
  ],
  dependencies: [
    // The decoder/filter/render seam the pipeline assembles (already built in Phases 5/6/7).
    .package(path: "../CortexDecoder"), // NeuralDecoder (NDT1 CoreML) + SpikeInputBuffer + LatencyHistogram.
    .package(path: "../CortexReFIT"), // KalmanFilter.step (the ReFIT-Kalman stage) + WebgridAcquisition.
    .package(path: "../CortexRender"), // CursorIntegrator + CursorVelocity + VelocityRing + WebgridView.
    .package(path: "../CortexBCIHID"), // ScanInfoRoundTrip — the SYS-03/04 instrumented round trip the GUI surfaces.
    .package(path: "../CortexCore"), // Time.machAbsoluteNanoseconds — the intent-emission clock (PERF-04).
    // Phase 10 (Plan 10-06): the Phase-2 transport + session layer, reached ONLY by CortexSeamBSmoke.
    //
    // NOTE the naming asymmetry, and which name goes where, because it is easy to get backwards.
    // Plan 02-01 split the bare CortexIPC product in two and named the MANIFEST `CortexIPCPackage`
    // while the DIRECTORY stayed `CortexIPC`. For a local path dependency SwiftPM derives the package
    // IDENTITY from the directory, not from the manifest's `name:`, so BOTH `.package(path:)` and
    // `.product(package:)` below take `CortexIPC`. Writing `.product(package: "CortexIPCPackage")`
    // fails to resolve with "unknown package 'CortexIPCPackage'" - measured, not assumed; this is the
    // first SwiftPM consumer of that package, so nothing in the repo had pinned the answer before.
    .package(path: "../CortexIPC")
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
    // actor by default (fine for a sequential bench). It drives ReplayPipeline for n ≥ 10,000
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
    // The RD-07 four-arm real-data ablation (Plan 10-05). Same dependency list as CortexDemoBench:
    // CortexDemo already depends on everything it needs, so the new target adds no package edge.
    .executableTarget(
      name: "CortexReplayBench",
      dependencies: [
        "CortexDemo",
        .product(name: "CortexDecoder", package: "CortexDecoder"),
        .product(name: "CortexReFIT", package: "CortexReFIT"),
        .product(name: "CortexRender", package: "CortexRender"),
        .product(name: "CortexCore", package: "CortexCore")
      ]
    ),
    // The RD-08 Seam B chain smoke (Plan 10-06). The IPC products are declared HERE ONLY: the
    // `CortexDemo` library stays exactly as it was, with no CortexIPC edge, so the app-side assembly
    // does not silently acquire a transport dependency it does not use (10-RESEARCH Correction 2).
    .executableTarget(
      name: "CortexSeamBSmoke",
      dependencies: [
        "CortexDemo", // RollingSpikeWindow + RecordedSpikeSource.modelSeqLen.
        .product(name: "CortexDecoder", package: "CortexDecoder"), // SpikeInputBuffer + NeuralDecoder.
        .product(name: "CortexRender", package: "CortexRender"), // CursorIntegrator - the [0,1] clamp seam.
        .product(name: "CortexBCIHID", package: "CortexBCIHID"), // BCIInputPointerReport.encode().
        .product(name: "CortexCore", package: "CortexCore"), // ReplayExport - the ONE D-06 reader.
        // `package:` is the DIRECTORY-derived identity `CortexIPC`, NOT the manifest's
        // `CortexIPCPackage` (see the dependencies note above).
        .product(name: "CortexIPCSession", package: "CortexIPC"),
        .product(name: "CortexIPCTransport", package: "CortexIPC")
      ]
    ),
    .testTarget(
      name: "CortexDemoTests",
      dependencies: [
        "CortexDemo",
        // RecordedSpikeSourceTests opens the committed replay-export fixture through
        // CortexCore.ReplayExport, so the module is a DECLARED dependency rather than one the test
        // target happens to reach transitively through CortexDemo.
        .product(name: "CortexCore", package: "CortexCore")
      ]
    )
  ]
)
