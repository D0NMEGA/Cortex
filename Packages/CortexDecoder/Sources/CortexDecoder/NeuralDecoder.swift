// NeuralDecoder — loads the NDT1 (vx,vy) Core ML package and runs in-process inference
// pinned to the Apple Neural Engine. Phase 5, Plan 05-03 (DEC-07, DEC-10).
//
// DEC-07 contract: the production MLModelConfiguration MUST set
//   computeUnits = .cpuAndNeuralEngine   (NOT .all)
// `productionConfiguration()` is the SINGLE source of truth for that value, and
// `ComputeUnitsTests` build-fails if it ever becomes `.all`.
//
// Latency (DEC-11) is NOT measured here — that is Plan 04's in-process 10k-pass histogram
// (05-RESEARCH Decision 5). This file is correctness-only: config value + (vx,vy) output.
import CoreML

/// Errors raised while loading the model or decoding a spike window. Typed-throws so callers
/// (and the audio-callback-adjacent hot path) handle every failure explicitly — no force-unwrap
/// of fallible CoreML calls (threat T-05-03-05).
public enum NeuralDecoderError: Error, Sendable {
  /// `MLModel(contentsOf:configuration:)` failed (missing/corrupt `.mlpackage`/`.mlmodelc`).
  case modelLoadFailed(url: URL, underlying: String)
  /// The model exposed no multi-array output feature to read `(vx, vy)` from.
  case missingVelocityOutput(available: [String])
  /// The velocity output was present but not the expected 2-element fp16 vector.
  case unexpectedVelocityShape(dataType: MLMultiArrayDataType, count: Int)
  /// `MLModel.prediction(from:)` threw while running inference.
  case predictionFailed(underlying: String)
}

/// In-process NDT1 cursor-velocity decoder. Loads a self-produced `.mlpackage`/`.mlmodelc`
/// (built by the Decoder pytest — never a remote/untrusted source, threat T-05-03-01) and
/// decodes a zero-copy spike window into a `(vx, vy)` velocity.
public final class NeuralDecoder {
  /// The loaded Core ML model, configured for `.cpuAndNeuralEngine`.
  private let model: MLModel

  /// The production compute-units configuration — the **single source of truth** for DEC-07.
  ///
  /// `.cpuAndNeuralEngine` (NOT `.all`): `.all` lets the scheduler hand operations to the GPU,
  /// which defeats the ANE-residency claim and adds latency variance (05-RESEARCH Decision 4).
  /// `ComputeUnitsTests` asserts this is `.cpuAndNeuralEngine` and, as a build gate, that it is
  /// never `.all`.
  public static func productionConfiguration() -> MLModelConfiguration {
    let config = MLModelConfiguration()
    config.computeUnits = .cpuAndNeuralEngine
    return config
  }

  /// Loads the model at `modelURL` with the production (ANE) configuration.
  ///
  /// The URL is supplied by the caller/test/bench from an env var or a built artifact under the
  /// gitignored Decoder checkpoints — the `.mlpackage` is an R&D artifact and is never committed.
  /// - Parameter modelURL: a compiled `.mlmodelc` or a `.mlpackage` produced by the Decoder pytest.
  public init(modelURL: URL) throws(NeuralDecoderError) {
    do {
      self.model = try MLModel(contentsOf: modelURL, configuration: Self.productionConfiguration())
    } catch {
      throw .modelLoadFailed(url: modelURL, underlying: String(describing: error))
    }
  }

  /// The model's compute-units configuration (for introspection/tests).
  public var computeUnits: MLComputeUnits { model.configuration.computeUnits }

  // NOTE: `decode(_:)` (taking a `SpikeInputBuffer` and returning `SIMD2<Float>`) is completed in
  // Plan 05-03 Task 3 once `ZeroCopyInput.swift` lands. Task 1 establishes only the load path +
  // the `productionConfiguration()` single source of truth that the DEC-07 build gate asserts on.
}
