// RecordedSpikeSource - Phase 10 (RD-08, Plan 10-04): the real-bin `SpikeWindowSource` over a
// `CortexCore.ReplayExport`.
//
// This is the v1 half of the seam. It hands the closed loop the session's OWN 20 ms binned spike
// counts, read from the D-06 export that `Decoder/scripts/export_replay.py` materialized from the
// SHA-256-pinned `.mat`. Nothing here re-bins, re-scales or re-derives anything: the bins are handed
// through exactly as the export stored them, because a second binner in Swift would be a silent drift
// hole (D-06).
//
// ## Alignment
// `window(i)` is the export's bins `[i * numBins ..< (i + 1) * numBins]`, and `target(forWindow:)` and
// `trueVelocity(forWindow:)` take that window's LAST bin. That matches `apply_lag`'s convention, where
// row i pairs the spike window ENDING at bin i with the kinematics one bin later, so the rotation
// target and the decoded window describe the same instant rather than drifting apart by a window.
//
// ## Determinism (D-13, unchanged by swapping in real data)
// Every member is a pure function of the mapped export and the window index: no RNG, no wall clock, no
// mutation. Replaying a recorded session is therefore just as reproducible as the v0 synthetic stream,
// and two runs over the same export produce byte-identical windows. That is what keeps Seam A's
// comparability to the Phase-8 number resting on the source swap alone rather than on run-to-run
// variation in the data the loop saw.
import CortexCore

/// A replay of one recorded session's spike bins, at the shipped model's window length.
public nonisolated struct RecordedSpikeSource: SpikeWindowSource {
  /// The shipped `ndt1_real_vel_sweep_fp16` input is `(1, 96, 1, 32)`. A source that reports anything
  /// else here produces a `SpikeInputBuffer` the model rejects, and `decodeWithModel` used to swallow
  /// that rejection into the synthetic fallback - the Pattern-2 trap. 32 is locked by
  /// 10-PREREGISTRATION section 2 and is not a tunable.
  public static let modelSeqLen = 32

  /// The export being replayed. Retained so the caller can reach its sidecar (session id, provenance
  /// digests, the `cursor_bbox_square` workspace) without opening the file a second time.
  public let export: ReplayExport
  public let channels: Int
  public let numBins: Int
  /// The number of WHOLE `numBins`-long windows the export contains. The replay ends here; there is no
  /// partial final window, because a short window would be zero-padded spikes the session never had.
  public let windowCount: Int

  public init(export: ReplayExport, numBins: Int = RecordedSpikeSource.modelSeqLen) {
    precondition(numBins > 0, "RecordedSpikeSource requires a positive window length")
    self.export = export
    self.numBins = numBins
    channels = export.channelCount
    windowCount = export.binCount / numBins
  }

  /// The `numBins`-bin window at `windowIndex`, in bin-major order.
  ///
  /// Out-of-range indices CLAMP to the first or last whole window rather than reading past the end;
  /// `windowCount` is what tells a caller where the replay actually stops. The `(try?)` below can only
  /// fire if the export holds fewer than `numBins` bins, in which case `windowCount` is already 0 and
  /// the caller's own tick budget is 0 - a loop that runs zero ticks fails the model-in-loop assertion
  /// loudly rather than reporting numbers from a zero window.
  public func window(_ windowIndex: Int) -> [Float16] {
    let clamped = max(0, windowIndex)
    let endingAt = min((clamped + 1) * numBins - 1, export.binCount - 1)
    guard let bins = try? export.window(endingAt: endingAt, length: numBins) else {
      return [Float16](repeating: 0, count: numBins * channels)
    }
    return bins
  }

  /// The session's real target position (mm) at the LAST bin of `windowIndex`'s window.
  public func target(forWindow windowIndex: Int) -> SIMD2<Double> {
    (try? export.target(at: lastBin(forWindow: windowIndex))) ?? SIMD2<Double>(0, 0)
  }

  /// The session's true binned cursor velocity (cm/s) at the LAST bin of `windowIndex`'s window.
  public func trueVelocity(forWindow windowIndex: Int) -> SIMD2<Double> {
    (try? export.velocity(at: lastBin(forWindow: windowIndex))) ?? SIMD2<Double>(0, 0)
  }

  /// The export bin index the window at `windowIndex` ends on, under the same clamp as `window(_:)`.
  public func lastBin(forWindow windowIndex: Int) -> Int {
    let clamped = max(0, windowIndex)
    return min((clamped + 1) * numBins - 1, export.binCount - 1)
  }
}
