// CortexDecoder — the Swift in-process inference path for the NDT1 cursor-velocity
// decoder (~1.3M params, h=1-2 attention heads, 6 layers, 128 hidden dim, 20ms binning,
// BC1S layout). Phase 5, Plan 05-03 (DEC-07/DEC-09/DEC-10/DEC-12).
//
// The real surface lives in:
//   • NeuralDecoder.swift — loads the (vx,vy) .mlpackage with computeUnits =
//     .cpuAndNeuralEngine (DEC-07) and runs MLModel.prediction -> SIMD2<Float>.
//   • ZeroCopyInput.swift — SpikeInputBuffer: one IOSurface shared by a
//     OneComponent16Half CVPixelBuffer + a storageModeShared MTLBuffer; yields an
//     MLMultiArray(pixelBuffer:) with no host copy (DEC-09).

/// Namespace + build metadata for the CortexDecoder Swift inference path.
public enum CortexDecoder {
  /// The phase that owns this package (5 — CoreML/ANE deployment).
  public static let phase: Int = 5

  /// Number of recording channels the decoder consumes (matches `CORTEX_CHANNEL_COUNT`
  /// reconciled in Phase 4 / Phase-2 D-11 across the native homes). The spike input is
  /// `(1, channelCount, 1, S)` fp16; see ``ZeroCopyInput`` and the Plan-01 contract.
  public static let channelCount: Int = 96

  /// Dimensionality of the decoded cursor velocity `(vx, vy)` — the Plan-01 `.mlpackage`
  /// output contract (fp16, shape `(1, 2, 1, 1)`). See ``NeuralDecoder/decode(_:)``.
  public static let velocityDimension: Int = 2
}
