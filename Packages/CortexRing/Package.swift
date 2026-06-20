// swift-tools-version: 6.2
// Phase 3 Swift↔Rust FFI spine (D-R1, Spike A). A Rust staticlib + cbindgen header is bundled into
// CortexRingFFI.xcframework by Tools/scripts/build-rust.sh and consumed here as a `.binaryTarget`,
// so BOTH `swift build` and `xcodebuild -scheme` link it natively with ZERO `.unsafeFlags`
// (RESEARCH §3-A / Pitfall #6). The xcframework is gitignored and MUST be built first
// (the `make bootstrap` analogue) — a fresh clone runs Tools/scripts/build-rust.sh before resolve.
// See .planning/phases/03-real-time-threading-pthread-user-interactive-rust-spsc-ring/03-RESEARCH.md.
import PackageDescription

let package = Package(
  name: "CortexRing",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexRingPing", targets: ["CortexRingPing"]),
    // Plan 03-03: the Foundation-free pthread USER_INTERACTIVE acquisition hot path (the real
    // producer that pushes CortexFrames into the Rust SPSC ring over the C ABI). CortexDaemon
    // depends on this product (project.yml); the hot-path policy gate polices its sources.
    .library(name: "CortexRingHotPath", targets: ["CortexRingHotPath"]),
  ],
  targets: [
    // The Rust ABI, bundled as a binary xcframework (per-platform .a + cortex_ring.h + modulemap).
    .binaryTarget(
      name: "CortexRingFFI",
      path: "CortexRingFFI.xcframework"
    ),
    // Thin Swift glue over the C ABI. NO .defaultIsolation(MainActor.self): this is FFI glue that
    // the Foundation-free USER_INTERACTIVE hot path (Plan 03) calls — it must not take actor hops,
    // matching the CortexIPCTransport isolation-free precedent (Plan 02-01).
    .target(
      name: "CortexRingPing",
      dependencies: ["CortexRingFFI"]
    ),
    // The Foundation-free acquisition hot path (Plan 03-03, THREAD-01/02/03; D-R2/D-R8). A raw
    // pthread pinned to QOS_CLASS_USER_INTERACTIVE pushes CortexFrames into the Rust ring via the
    // C ABI (cortex_spsc_push). NO .defaultIsolation(MainActor.self): the hot path must never take
    // a MainActor/actor hop (the CortexIPCTransport precedent, Plan 02-01) — it `import Darwin`,
    // never Foundation, and is policed by Tools/scripts/hotpath-policy.sh.
    .target(
      name: "CortexRingHotPath",
      dependencies: ["CortexRingFFI"]
    ),
    .testTarget(
      name: "CortexRingTests",
      dependencies: ["CortexRingPing"]
    )
  ]
)
