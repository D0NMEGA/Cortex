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
  products: [.library(name: "CortexReFIT", targets: ["CortexReFIT"])],
  dependencies: [
    // D-14: depend on CortexRender (the seam owner), do not hoist the seam to CortexCore.
    .package(path: "../CortexRender"),
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
    .testTarget(
      name: "CortexReFITTests",
      dependencies: ["CortexReFIT"]
    ),
  ]
)
