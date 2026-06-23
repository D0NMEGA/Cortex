// swift-tools-version: 6.2
// CortexReFIT — Phase 7: the 6-DOF steady-state ReFIT-Kalman filter + Gilja-2012 intent-rotation,
// post-CoreML, on the Swift side (REFIT-01 / REFIT-02). See REQUIREMENTS.md REFIT-01..03.
//
// D-14 DECISION — KEEP the CortexRender dependency; do NOT hoist the seam types to CortexCore.
//   The velocity seam (`CursorVelocity`, `VelocityRing`, `CursorIntegrator`) lives in CortexRender
//   and the Phase-6 comments in `CursorVelocity.swift` / `CursorIntegrator.swift` declare it a
//   CONTRACT — "Phase 7's Kalman becomes the producer; because the seam is velocity-typed it is
//   unchanged when the real decoder lands." CortexReFIT is a DROP-IN PRODUCER for that seam, so the
//   producer→seam-owner dependency direction is clean and mirrors how the synthetic
//   `LissajousProducer` already lives beside the seam in CortexRender. Hoisting the seam types to
//   CortexCore would RE-ARCHITECT a frozen seam (5 files + tests + render-policy + project.yml
//   wiring) against CONTEXT's explicit "do not re-architect the seam" directive — so we keep the
//   dependency rather than re-architect.
import PackageDescription

let package = Package(
  name: "CortexReFIT",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexReFIT", targets: ["CortexReFIT"]),
    // Plan 07-03 (D-07, SC#3): the headless deterministic 3-way ablation BPS harness + the
    // filter-step tail-latency bench. Mirrors the CortexDecoderBench executable entry.
    .executable(name: "CortexReFITBench", targets: ["CortexReFITBench"]),
  ],
  dependencies: [
    // D-14: depend on CortexRender (the seam owner), do not hoist the seam to CortexCore.
    .package(path: "../CortexRender"),
    // Plan 07-03: LatencyHistogram (the SC#3 tail-latency value type) lives in CortexDecoder; the
    // bench reuses it (and the bench-executable pattern) rather than duplicating the histogram math.
    .package(path: "../CortexDecoder"),
  ],
  targets: [
    .target(
      name: "CortexReFIT",
      dependencies: [
        // The CursorVelocity / VelocityRing seam this filter produces into (D-14 keep-decision).
        .product(name: "CortexRender", package: "CortexRender"),
      ],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    // Plan 07-03 (D-07, D-12, SC#3): the headless deterministic harness. A top-level main.swift
    // runs on the main actor by default (fine for a sequential, single-threaded bench). It replays a
    // seed-locked velocity+target sequence through raw / Kalman-only / Kalman+rotation, measures
    // S&M-2004 throughput per arm, writes refit_bps.json, and (in --latency mode) times the
    // filter step over n>=10 000 ticks INLINE (no new thread) into a device-annotated
    // LatencyHistogram. Exits 0 with a usage/skip message when no Indy data is present (the --smoke
    // synthetic variant produces a valid raw/kalman_only/refit triple for the committed JSON + CI).
    .executableTarget(
      name: "CortexReFITBench",
      dependencies: [
        "CortexReFIT",
        .product(name: "CortexRender", package: "CortexRender"),
        .product(name: "CortexDecoder", package: "CortexDecoder"),
      ]
    ),
    .testTarget(
      name: "CortexReFITTests",
      dependencies: ["CortexReFIT"]
    ),
  ]
)
