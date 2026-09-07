/// The spike-window seam the replay loop decodes from (Phase 10, RD-08, Plan 10-04).
///
/// ``SyntheticSpikeSource`` is the deterministic v0 stand-in; ``RecordedSpikeSource`` replays real
/// 20 ms bins from the Phase-10 D-06 export (v1). Injecting this protocol is what lets the real path
/// change ONE variable - the source - while decode, filter, integrate and webgrid stay
/// byte-identical. That is what makes Seam A comparable to the Phase-8 number
/// (10-PREREGISTRATION section 9); any second change would silently invalidate the comparison.
///
/// Deliberately tiny. It is a seam, not an abstraction layer: three members, no associated types, no
/// default implementations, no imports.
///
/// The members are `nonisolated` so both a `nonisolated` value source (``SyntheticSpikeSource``,
/// ``RecordedSpikeSource``) and the MainActor-isolated pipeline that drives them can share the seam
/// under the package's `.defaultIsolation(MainActor.self)` posture.
///
/// ## What a conformance must guarantee (D-13, the determinism contract)
/// ``window(_:)`` must be a PURE function of the conformer's own state and `windowIndex` - no RNG, no
/// wall clock, no mutation. `ReplayPipeline` drives it with its monotonic tick index, and the
/// whole simulation path's reproducibility rests on the same index yielding the same bytes. A source
/// that read a clock would put entropy back into a loop the repo has kept closed-form since Phase 7.
public protocol SpikeWindowSource: Sendable {
  /// Recording channels per bin - the NDT1 `(1, channels, 1, S)` contract (96, DEC-02).
  nonisolated var channels: Int { get }
  /// 20 ms bins per decode window. This is the S the `SpikeInputBuffer` is sized from, and a source
  /// that disagrees with the loaded model's S is exactly the Pattern-2 trap Plan 10-04 removes: the
  /// shipped real model wants 32, and ``SyntheticSpikeSource`` defaults to 8.
  nonisolated var numBins: Int { get }
  /// The window for one decode tick, in BIN-MAJOR order: `window[bin * channels + channel]`.
  nonisolated func window(_ windowIndex: Int) -> [Float16]
}
