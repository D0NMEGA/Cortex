// swift-tools-version: 6.2
// Source of truth for shared types, time utilities, App Group helpers, and the
// load-bearing CORTEX_SHM_NAME compile-time invariant. See
// .planning/phases/01-foundation-2026-toolchain/01-CONTEXT.md (D-02, D-08).
import PackageDescription

let package = Package(
  name: "CortexCore",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexCore", targets: ["CortexCore"]),
  ],
  targets: [
    .target(
      name: "CortexCoreC",
      // SwiftPM auto-generates the module map from Sources/CortexCoreC/include/.
      // No publicHeadersPath override needed.
      cSettings: [
        .define("CORTEX_PHASE", to: "1"),
      ]
    ),
    .target(
      name: "CortexCore",
      dependencies: ["CortexCoreC"],
      swiftSettings: [
        // Approachable Concurrency (Swift 6.2): default isolation to MainActor.
        // Per RESEARCH.md Q6, advisory at this stage; drop only if Xcode 26.3 rejects syntax.
        .defaultIsolation(MainActor.self),
      ]
    ),
    .testTarget(
      name: "CortexCoreTests",
      dependencies: ["CortexCore"]
    ),
  ]
)
