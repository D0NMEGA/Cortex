// DwellChannel — the producer→renderer latest-value seam for dwell-to-select progress.
//
// Mirrors `TargetChannel`: one atomic word, store-latest / load-latest, no queue and no back
// pressure. The producer is the 20ms replay-loop tick; the consumer is the display-link callback at
// 120Hz. A frame that lands between two producer ticks reads the previous value, which is the
// correct behaviour for a progress bar — there is nothing to interpolate and nothing to miss.
//
// Kept separate from `TargetChannel` rather than folded into it so each channel stays one word and
// one meaning: the target is a grid cell that changes once per trial, the dwell is a fraction that
// changes every tick.
import Synchronization

/// The live dwell-to-select progress the renderer draws, in `[0, 1]`.
///
/// 0 means "not holding on a target"; 1 would mean the hold is complete, but the producer commits
/// the selection and resets to 0 on the tick it would reach 1, so a reader sees the fraction climb
/// and then snap back. That snap IS the selection, visually.
public final class DwellChannel: Sendable {
  /// `Float.bitPattern` of the latest progress. A whole `Float` fits one atomic word, so the value
  /// crosses the seam exactly rather than being quantised into fixed point.
  private let bits = Atomic<UInt32>(Float(0).bitPattern)

  public init() {}

  /// Publish the latest progress. Non-finite input and out-of-range values clamp to `[0, 1]`, so a
  /// bad producer value can never reach the shader as a NaN radius.
  public func store(_ progress: Float) {
    let safe = progress.isFinite ? min(max(progress, 0), 1) : 0
    bits.store(safe.bitPattern, ordering: .releasing)
  }

  /// Read the latest published progress.
  public func load() -> Float {
    Float(bitPattern: bits.load(ordering: .acquiring))
  }
}
