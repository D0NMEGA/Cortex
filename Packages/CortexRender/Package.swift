// swift-tools-version: 6.2
// Reserved for Phase 6 — CAMetalDisplayLink 120Hz renderer with 30x30 webgrid.
// See REQUIREMENTS.md RENDER-01 through RENDER-09.
import PackageDescription

let package = Package(
  name: "CortexRender",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [.library(name: "CortexRender", targets: ["CortexRender"])],
  targets: [
    .target(
      name: "CortexRender",
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "CortexRenderTests",
      dependencies: ["CortexRender"]
    ),
  ]
)
