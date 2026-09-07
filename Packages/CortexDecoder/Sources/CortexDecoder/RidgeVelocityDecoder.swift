// RidgeVelocityDecoder — the matched causal linear velocity decoder, run on device.
//
// `Decoder/scripts/fit_baseline_decoders.py` measured that a ridge filter on RAW binned spikes
// reaches a higher held-out velocity R2 than the NDT1 encoder readout on this dataset (0.4616
// against 0.4238, pooled over 56,943 held-out rows). This is that filter, not a reimplementation of
// it: `export_ridge_decoder.py` ships the weights the measurement was made with, and refuses to
// write them unless they reproduce the published score.
//
// ## Why a linear decoder is worth shipping
// Not because linear is elegant. Because on this data it wins, and a demo driven by the losing
// decoder while the README reports the winner would be showing the reader something other than the
// result. Whether the transformer earns its parameters is a question about prediction; whether the
// pipeline hits its latency budget is a question about engineering. This decoder answers the first
// one honestly and costs the second one nothing: it is 3,072 multiply-adds per axis.
//
// ## Feature order, which is load-bearing
// The fit's design row is bin-major, oldest bin first: feature `i` is `bin * channels + channel`
// with bin 0 the oldest of the 32-bin window. `RecordedSpikeSource` hands out its window in exactly
// that order, so the weight vector is consumed straight through with no transpose. A reordering
// here would not crash; it would silently decode a different function, so the parity self-check in
// the sidecar exists to catch it.
import Foundation
import simd

/// Why a ridge decoder could not be loaded.
public enum RidgeDecoderError: Error, Sendable, CustomStringConvertible {
  case resourceMissing
  case truncated(expected: Int, got: Int)
  case unsupportedSchema(Float)
  case implausibleShape(historyBins: Int, channels: Int)

  public var description: String {
    switch self {
    case .resourceMissing:
      "ridge_velocity_k32.bin is not in the bundle; run Decoder/scripts/export_ridge_decoder.py"
    case let .truncated(expected, got):
      "ridge weights are \(got) floats, expected \(expected)"
    case let .unsupportedSchema(version):
      "ridge weights declare schema \(version), which this build does not know how to read"
    case let .implausibleShape(historyBins, channels):
      "ridge weights declare \(historyBins) bins x \(channels) channels, which is not a decoder shape"
    }
  }
}

/// A causal linear map from a spike-count window to a 2-D velocity in cm/s.
public final nonisolated class RidgeVelocityDecoder {
  /// Bins of history the decoder consumes, oldest first. 32 at 20 ms is 640 ms.
  public let historyBins: Int
  /// Electrode channels per bin.
  public let channels: Int
  /// `weights[feature * 2 + axis]`, feature-major so one pass reads both axes per feature.
  private let weights: [Float]
  private let bias: SIMD2<Float>

  /// Features the decoder expects: `historyBins * channels`.
  public var featureCount: Int {
    historyBins * channels
  }

  /// Load from raw little-endian float32 bytes, as written by `export_ridge_decoder.py`.
  ///
  /// Layout: `[schema, historyBins, channels, reserved]`, then `historyBins * channels * 2` weights,
  /// then 2 bias terms. Every field is float32 so the read is one homogeneous pass.
  public init(bytes: Data) throws {
    let floats: [Float] = bytes.withUnsafeBytes { raw in
      let count = raw.count / MemoryLayout<Float>.size
      // The file is little-endian and every Apple Silicon target is little-endian, so a direct
      // reinterpretation is correct here; `loadUnaligned` covers a Data whose base is not aligned.
      return (0 ..< count).map {
        raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self)
      }
    }
    guard floats.count > 4 else { throw RidgeDecoderError.truncated(expected: 5, got: floats.count) }
    guard floats[0] == 1 else { throw RidgeDecoderError.unsupportedSchema(floats[0]) }

    let bins = Int(floats[1])
    let chans = Int(floats[2])
    guard bins > 0, chans > 0, bins <= 512, chans <= 4096 else {
      throw RidgeDecoderError.implausibleShape(historyBins: bins, channels: chans)
    }
    let expected = 4 + bins * chans * 2 + 2
    guard floats.count == expected else {
      throw RidgeDecoderError.truncated(expected: expected, got: floats.count)
    }

    historyBins = bins
    channels = chans
    weights = Array(floats[4 ..< (4 + bins * chans * 2)])
    bias = SIMD2<Float>(floats[expected - 2], floats[expected - 1])
  }

  /// Load the decoder shipped in this package's bundle.
  ///
  /// `@MainActor` only because `Bundle.module` is, under this package's default isolation. Loading
  /// happens once at setup; `decode(window:)` stays nonisolated so the hot path is unaffected.
  @MainActor
  public convenience init() throws {
    guard let url = Bundle.module.url(forResource: "ridge_velocity_k32", withExtension: "bin") else {
      throw RidgeDecoderError.resourceMissing
    }
    try self.init(bytes: Data(contentsOf: url))
  }

  /// Decode one window into a velocity in cm/s.
  ///
  /// - Parameter window: `historyBins * channels` spike counts, bin-major and oldest bin first --
  ///   the order `RecordedSpikeSource.window(_:)` produces. A window of the wrong length returns
  ///   `nil` rather than decoding a misaligned prefix, because a misaligned decode looks like a
  ///   plausible velocity and would be indistinguishable from a working decoder on screen.
  public func decode(window: [Float16]) -> SIMD2<Float>? {
    guard window.count == featureCount else { return nil }
    var vx: Float = 0
    var vy: Float = 0
    for feature in 0 ..< featureCount {
      let x = Float(window[feature])
      vx += weights[feature * 2] * x
      vy += weights[feature * 2 + 1] * x
    }
    return SIMD2<Float>(vx + bias.x, vy + bias.y)
  }
}
