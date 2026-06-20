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
    .library(name: "CortexRingPing", targets: ["CortexRingPing"])
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
    .testTarget(
      name: "CortexRingTests",
      dependencies: ["CortexRingPing"]
    )
  ]
)
