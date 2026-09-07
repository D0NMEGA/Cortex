// DEC-10 (Swift-side) + DEC-12 (Swift-side mirror).
//
//  • Model-backed: NeuralDecoder(modelURL:).decode(SpikeInputBuffer) returns a 2-element fp16
//    (vx,vy) SIMD2<Float>. The (vx,vy) `.mlpackage` is a gitignored R&D artifact (Phase-4
//    discipline), so this test resolves the model URL from the `CORTEX_DECODER_MODEL_URL`
//    env var and SKIPS CLEANLY (early return) when it is absent — `swift test` stays green in a
//    clean clone. Run the Decoder pytest to build the artifact, then export the env var to
//    exercise it.
//  • DEC-12 Swift-side scan (always-run): the Sources tree contains zero `_ANEClient`. A unit-
//    test mirror of the CI grep gate so the private-API assertion is also enforced in `swift test`.
//    The forbidden token is assembled from fragments so THIS test's source is not itself a hit.
//
// This suite is correctness-only — it asserts the output shape/dtype, never a speed/timing number
// (that claim is owned by Plan 04 in-process + the iPad-M4 canonical artifact; D-18 precedent).
import CoreML
@testable import CortexDecoder
import Foundation
import Metal
import Testing

@Suite("DEC-10 output contract + DEC-12 no private API (Swift-side)")
@MainActor
struct VelocityOutputTests {
  /// Env var pointing at a self-produced `.mlpackage`/`.mlmodelc` (gitignored). Absent ⇒ skip.
  private static let modelURLEnvKey = "CORTEX_DECODER_MODEL_URL"

  @Test
  func `decode() returns a finite 2-element fp16 (vx,vy) — skips cleanly if no model artifact`() throws {
    // The `.mlpackage` is gitignored; skip cleanly when it (or a Metal device) is absent so the
    // suite stays green in a clean clone / CI without the built artifact.
    guard let raw = ProcessInfo.processInfo.environment[Self.modelURLEnvKey], !raw.isEmpty else {
      return // model artifact not built — run the Decoder pytest + export CORTEX_DECODER_MODEL_URL
    }
    guard let device = MTLCreateSystemDefaultDevice() else { return }

    let modelURL = URL(fileURLWithPath: raw)
    let decoder = try NeuralDecoder(modelURL: modelURL)
    let input = try SpikeInputBuffer(device: device, seqLen: 8)

    let velocity = try decoder.decode(input)
    #expect(velocity.x.isFinite)
    #expect(velocity.y.isFinite)
  }

  @Test
  func `DEC-12: zero _ANEClient anywhere in the CortexDecoder Sources tree`() throws {
    // Assemble the forbidden token from fragments so this assertion's own source is NOT a match.
    let forbidden = "_ANE" + "Client"

    let testFileURL = URL(fileURLWithPath: #filePath)
    // .../Tests/CortexDecoderTests/VelocityOutputTests.swift -> .../Sources
    let sourcesDir = testFileURL
      .deletingLastPathComponent() // CortexDecoderTests/
      .deletingLastPathComponent() // Tests/
      .deletingLastPathComponent() // CortexDecoder/  (package root)
      .appendingPathComponent("Sources", isDirectory: true)

    let fm = FileManager.default
    let enumerator = try #require(
      fm.enumerator(at: sourcesDir, includingPropertiesForKeys: [.isRegularFileKey]),
      "CortexDecoder Sources directory must be enumerable at \(sourcesDir.path)"
    )

    var scanned = 0
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
      let contents = try String(contentsOf: fileURL, encoding: .utf8)
      #expect(!contents.contains(forbidden), "DEC-12 violation: \(forbidden) found in \(fileURL.lastPathComponent)")
      scanned += 1
    }
    // Guard the guard: ensure we actually scanned the real source files (path math is correct).
    #expect(scanned >= 3, "expected to scan CortexDecoder/NeuralDecoder/ZeroCopyInput sources")
  }
}
