// swift-tools-version: 6.2
// Reserved for Phase 5 — CoreML deployment of the NDT1 decoder with verified ANE residency.
// See REQUIREMENTS.md DEC-06 through DEC-12.
import PackageDescription

let package = Package(
  name: "CortexDecoder",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [.library(name: "CortexDecoder", targets: ["CortexDecoder"])],
  targets: [
    .target(
      name: "CortexDecoder",
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
  ]
)
