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
  /// Bins the window advances between consecutive `windowIndex` values.
  ///
  /// Defaults to `numBins`, i.e. NON-OVERLAPPING windows: index `i` covers bins `[i*numBins,
  /// (i+1)*numBins)`. That is the right cadence for a throughput bench, which only needs distinct
  /// windows to decode and does not integrate a cursor.
  ///
  /// A caller that drives a CLOSED LOOP must pass `stride: 1` instead, so one tick advances the
  /// session clock by one bin and the trailing window ends at that bin. With the default stride a
  /// 20 ms tick advances 640 ms of recorded time, which desynchronises the loop from the data two
  /// ways at once: the integrator moves the cursor by `velocity * 0.020` when 0.640 s actually
  /// elapsed (a 32x under-travel), and the per-trial target advances ~32x faster than real time, so
  /// the task target changes every couple of frames. `CortexReplayBench` already decodes one window
  /// per bin for exactly this reason; `stride` is what lets the GUI loop match it.
  public let stride: Int

  /// - Parameters:
  ///   - export: the session to replay.
  ///   - numBins: window length; must match the model's sequence length.
  ///   - stride: bins advanced per window index. `nil` means `numBins` (non-overlapping).
  public init(
    export: ReplayExport,
    numBins: Int = RecordedSpikeSource.modelSeqLen,
    stride: Int? = nil
  ) {
    precondition(numBins > 0, "RecordedSpikeSource requires a positive window length")
    let step = stride ?? numBins
    precondition(step > 0, "RecordedSpikeSource requires a positive stride")
    self.export = export
    self.numBins = numBins
    self.stride = step
    channels = export.channelCount
    // Whole windows only. At the default stride this is `binCount / numBins`, unchanged.
    windowCount = export.binCount < numBins ? 0 : (export.binCount - numBins) / step + 1
  }

  /// The `numBins`-bin window at `windowIndex`, in bin-major order.
  ///
  /// Out-of-range indices CLAMP to the first or last whole window rather than reading past the end;
  /// `windowCount` is what tells a caller where the replay actually stops. The `(try?)` below can only
  /// fire if the export holds fewer than `numBins` bins, in which case `windowCount` is already 0 and
  /// the caller's own tick budget is 0 - a loop that runs zero ticks fails the model-in-loop assertion
  /// loudly rather than reporting numbers from a zero window.
  public func window(_ windowIndex: Int) -> [Float16] {
    let endingAt = lastBin(forWindow: windowIndex)
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
    return min(numBins - 1 + clamped * stride, export.binCount - 1)
  }
}
