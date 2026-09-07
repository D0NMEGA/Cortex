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
      // The 30x30 webgrid compute shader (RENDER-04). A bare `swift build` treats `.metal` as an
      // unhandled asset (SwiftPM has no native Metal compile); declaring it a `.process` resource
      // routes it through the Apple build system's Metal pipeline, which compiles it into
      // `default.metallib` inside this module's resource bundle. `WebgridFrameEncoder` then loads it
      // at runtime via `device.makeDefaultLibrary(bundle: .module)`. Required for both app targets
      // (CortexiOS/CortexMac) built through Xcode/XcodeGen.
      resources: [.process("Webgrid.metal")],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "CortexRenderTests",
      dependencies: ["CortexRender"]
    )
  ]
)
