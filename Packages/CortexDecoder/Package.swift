// swift-tools-version: 6.2
// Phase 5 — CoreML deployment of the NDT1 decoder with verified ANE residency.
// See REQUIREMENTS.md DEC-06 through DEC-12.
//
// Plan 05-03 (Wave 2) grows this from an 8-line stub into the real Swift in-process
// inference path:
//   • NeuralDecoder loads the Plan-01 (vx,vy) .mlpackage with
//     MLModelConfiguration.computeUnits = .cpuAndNeuralEngine (NOT .all) — DEC-07.
//   • ZeroCopyInput feeds spikes zero-copy via MLMultiArray(pixelBuffer:shape:) over an
//     IOSurface shared with an MTLBuffer storageModeShared (OneComponent16Half) — DEC-09.
//   • A NEW CortexDecoderTests target (the package had none) carries the build-failing
//     compute-units gate, the pointer-identity zero-copy proof, and the (vx,vy) output
//     shape/dtype check (DEC-07/09/10 Swift-side; DEC-12 Swift-side mirror).
// CoreML / Metal / IOSurface / CoreVideo are system frameworks: they resolve via `import`
// on Apple platforms, so no explicit linkerSettings are required (mirrors how CortexIPC
// pulls in CryptoKit). Latency (DEC-11) is owned by Plan 04, NOT measured here.
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
    // Net-new in Plan 05-03 (Wave-0 scaffold per 05-VALIDATION): the package had no test
    // target. Carries ComputeUnitsTests (DEC-07 build gate), ZeroCopyInputTests (DEC-09
    // pointer identity), and VelocityOutputTests (DEC-10 output + DEC-12 Swift-side scan).
    .testTarget(
      name: "CortexDecoderTests",
      dependencies: ["CortexDecoder"]
    ),
  ]
)
