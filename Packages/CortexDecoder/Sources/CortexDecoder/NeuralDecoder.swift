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

  /// The spike input feature name, frozen by the Plan-01 `.mlpackage` contract:
  /// `spikes`, fp16, shape `(1, 96, 1, S)`.
  public static let inputFeatureName = "spikes"

  /// Decodes one zero-copy spike window into a cursor velocity `(vx, vy)`.
  ///
  /// Feeds the shared-surface `MLMultiArray` (DEC-09) through `MLModel.prediction(from:)` and reads
  /// the 2-element fp16 velocity output by name from the model description (the Plan-01 output
  /// contract: fp16, shape `(1, 2, 1, 1)`). NOT timed here — DEC-11 latency is Plan 04.
  /// - Parameter input: the shared-surface spike buffer (its lifetime must exceed this call).
  /// - Returns: the decoded `(vx, vy)` as a `SIMD2<Float>` (fp16 output widened to `Float`).
  public func decode(_ input: SpikeInputBuffer) throws(NeuralDecoderError) -> SIMD2<Float> {
    let arr: MLMultiArray
    do {
      arr = try input.makeMultiArray()
    } catch {
      throw .predictionFailed(underlying: String(describing: error))
    }

    let out: any MLFeatureProvider
    do {
      let provider = try MLDictionaryFeatureProvider(
        dictionary: [Self.inputFeatureName: MLFeatureValue(multiArray: arr)]
      )
      out = try model.prediction(from: provider)
    } catch {
      throw .predictionFailed(underlying: String(describing: error))
    }

    let velocity = try velocityMultiArray(from: out)
    guard velocity.dataType == .float16, velocity.count == CortexDecoder.velocityDimension else {
      throw .unexpectedVelocityShape(dataType: velocity.dataType, count: velocity.count)
    }
    return SIMD2<Float>(velocity[0].floatValue, velocity[1].floatValue)
  }

  /// Finds the velocity output `MLMultiArray` in a prediction result.
  ///
  /// Reads the output feature by NAME from `model.modelDescription.outputDescriptionsByName`
  /// rather than hardcoding it (coremltools may auto-name the output): prefer the single/first
  /// multi-array output feature. Fails closed with the available names if none is a multi-array.
  private func velocityMultiArray(from output: any MLFeatureProvider) throws(NeuralDecoderError) -> MLMultiArray {
    let names = model.modelDescription.outputDescriptionsByName
      .filter { $0.value.type == .multiArray }
      .keys
      .sorted()
    for name in names {
      if let value = output.featureValue(for: name), let array = value.multiArrayValue {
        return array
      }
    }
    throw .missingVelocityOutput(available: Array(model.modelDescription.outputDescriptionsByName.keys))
  }
}
