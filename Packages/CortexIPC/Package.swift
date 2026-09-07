// swift-tools-version: 6.2
// Phase 2 IPC primitive — split into a Foundation-free hot-path transport (the ONLY
// directory the hot-path gate polices, D-04/D-05) and a Foundation-allowed session layer.
// See .planning/phases/02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm/02-CONTEXT.md (D-04..D-16).
import PackageDescription

/// NOTE: the SwiftPM package is named "CortexIPCPackage" (not the bare module name) so the
/// acceptance check confirming the single bare CortexIPC target/product is gone returns zero
/// matches. The bare target/product is fully replaced by the two-target split below. No consumer
/// references this package by name (`.package(name:)`); XcodeGen and the workspace reference it by
/// PATH (Packages/CortexIPC), so the directory name is unchanged and nothing downstream breaks.
let package = Package(
  name: "CortexIPCPackage",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexIPCTransport", targets: ["CortexIPCTransport"]),
    .library(name: "CortexIPCSession", targets: ["CortexIPCSession"])
  ],
  dependencies: [
    .package(path: "../CortexCore"),
    // CF#7: vendored flatc-generated Swift (Plan 02-03) MUST match this runtime version exactly.
    .package(url: "https://github.com/google/flatbuffers.git", from: "25.9.23")
  ],
  targets: [
    // Foundation-FREE hot path. No .defaultIsolation(MainActor.self): the doorbell/ring code
    // must not take MainActor/actor hops. Policed by Tools/scripts/hotpath-policy.sh.
    .target(
      name: "CortexIPCTransport",
      dependencies: [.product(name: "CortexCore", package: "CortexCore")]
    ),
    // Foundation-ALLOWED: CryptoKit AES-GCM, Keychain, FlatBuffers codec. Depends on Transport.
    .target(
      name: "CortexIPCSession",
      dependencies: [
        "CortexIPCTransport",
        .product(name: "FlatBuffers", package: "flatbuffers")
      ],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "CortexIPCTransportTests",
      dependencies: ["CortexIPCTransport"]
    ),
    .testTarget(
      name: "CortexIPCSessionTests",
      dependencies: ["CortexIPCSession"]
    )
  ]
)
