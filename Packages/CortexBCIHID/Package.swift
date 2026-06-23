// swift-tools-version: 6.2
// CortexBCIHID — Phase 8 (SYS-01/02/05/06): the Swift port of Apple's PUBLIC Brain-Computer-Interface
// HID protocol surface — the 5 report structs, the report descriptor byte array, and the high-level
// button-action enum — plus the declared-but-gated `com.apple.developer.hid.virtual.device`
// instantiation seam and the SMAppService daemon-registration scaffold.
//
// SOURCE OF TRUTH for the ported surface:
//   developer.apple.com/documentation/accessibility/brain-computer-interface-hid-reference-for-connecting-to-apple-platforms
//
// WIRE-AND-GATE DOCTRINE (CONTEXT D-04/D-06, RESEARCH §0.1/§1):
//   - The buildable-now half (structs + descriptor + button enum) is PURE value types — NO external
//     dependencies, NO I/O — so it compiles and unit-tests on the free Personal team today.
//   - The live IOHIDUserDevice / CoreHID HIDVirtualDevice instantiation lives behind a compile-time
//     `#if CORTEX_HID_LIVE` gate (default OFF), so the free-team demo binary links NO live HID symbol
//     and stays AMFI-safe (the CF#1 precedent). Activation is the Plan 07 HUMAN-UAT gate.
//   - `.defaultIsolation(MainActor.self)` matches the other Cortex packages (Approachable Concurrency).
//
// This package is registered under project.yml `packages:` so xcodebuild resolves it; it is NOT yet a
// target dependency (Plan 03 wires it into CortexMac).
import PackageDescription

let package = Package(
  name: "CortexBCIHID",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "CortexBCIHID", targets: ["CortexBCIHID"]),
  ],
  targets: [
    .target(
      name: "CortexBCIHID",
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(
      name: "CortexBCIHIDTests",
      dependencies: ["CortexBCIHID"]
    ),
  ]
)
