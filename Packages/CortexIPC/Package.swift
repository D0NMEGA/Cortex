// swift-tools-version: 6.2
// Reserved for Phase 2 — POSIX shm + kqueue + recvmsg + FlatBuffers + AES-GCM transport.
// See REQUIREMENTS.md IPC-01 through IPC-07.
import PackageDescription

let package = Package(
  name: "CortexIPC",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [.library(name: "CortexIPC", targets: ["CortexIPC"])],
  targets: [
    .target(
      name: "CortexIPC",
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
  ]
)
