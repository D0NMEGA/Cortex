// DEC-07 — the build-failing compute-units gate.
//
// `NeuralDecoder.productionConfiguration()` is the single source of truth for the production
// compute units. These tests need NO model (pure config introspection) so they always run green
// in a clean clone. The `!= .all` expectation is the regression gate: if anyone sets `.all`,
// `swift test` FAILS — `.all` lets the scheduler hand ops to the GPU, defeating ANE residency
// and adding latency variance (05-RESEARCH Decision 4). Proven with a negative control during
// execution (temporarily flip to `.all` → this suite goes red → restore).
import CoreML
@testable import CortexDecoder
import Testing

// `@MainActor`: the CortexDecoder library target sets `.defaultIsolation(MainActor.self)`, so
// `NeuralDecoder` and its statics are MainActor-isolated (the model is driven from the app side).
// The test suite adopts the same isolation to call the API synchronously.
@Suite("DEC-07: production compute units pin to the Apple Neural Engine")
@MainActor
struct ComputeUnitsTests {
  @Test
  func `productionConfiguration() uses .cpuAndNeuralEngine`() {
    let config = NeuralDecoder.productionConfiguration()
    #expect(config.computeUnits == .cpuAndNeuralEngine)
  }

  /// Build gate: the production config must NEVER be `.all`. `.all` would let Core ML place ops
  /// on the GPU, defeating the DEC-06/DEC-08 residency claim. This is the assertion the negative
  /// control bites.
  @Test
  func `productionConfiguration() is never .all (DEC-07 build gate)`() {
    let config = NeuralDecoder.productionConfiguration()
    #expect(config.computeUnits != .all)
  }

  @Test
  func `productionConfiguration() rejects CPU-only and CPU+GPU placement`() {
    // Tightens the gate beyond just `.all`: the only acceptable production value is the ANE pin.
    let units = NeuralDecoder.productionConfiguration().computeUnits
    #expect(units != .cpuOnly)
    #expect(units != .cpuAndGPU)
  }
}
