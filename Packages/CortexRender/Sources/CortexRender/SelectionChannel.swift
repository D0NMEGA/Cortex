// SelectionChannel — the producer→renderer seam for dwell-to-select display state.
//
// Three values, one word, because they are produced together on the same 20 ms tick and consumed
// together on the same frame: how much of the continuous hold has accumulated, whether this trial's
// target has been acquired, and how recently that happened. Splitting them across separate atomics
// would let a frame draw a full-size cursor beside a green target from a selection that has already
// been released, or a green target from the trial before the one on screen.
//
// Like `TargetChannel` this is store-latest / load-latest with no queue and no back pressure. A
// frame landing between producer ticks reads the previous triple, which is correct for all three:
// there is nothing to interpolate and nothing to miss.
import Synchronization

/// Dwell progress, acquisition and the commit swell, as the renderer draws them.
public nonisolated struct SelectionState: Sendable, Equatable {
  /// Fraction of the continuous hold accumulated, in `[0, 1]`.
  ///
  /// The producer commits the selection and resets to 0 on the tick this would reach 1, so a reader
  /// sees the fraction climb and then snap back. That snap IS the selection.
  public let dwell: Float
  /// True once this trial's target has been acquired, and until the next trial starts.
  ///
  /// A LATCH rather than a fading value. The target stays green for the rest of the trial, so a
  /// viewer scrubbing a recording can see which trials were acquired instead of having to catch the
  /// instant. It is also the only unambiguous signal on screen: the cursor ring releases to full
  /// size both when a selection commits and when a hold is broken, so the ring alone cannot say
  /// whether anything counted.
  public let acquired: Bool
  /// How recently the acquisition happened, decaying `1 → 0`. 0 means it was not just now.
  public let swell: Float

  public init(dwell: Float, acquired: Bool, swell: Float) {
    self.dwell = dwell
    self.acquired = acquired
    self.swell = swell
  }

  public static let idle = SelectionState(dwell: 0, acquired: false, swell: 0)
}

/// The live selection state the renderer draws.
public final nonisolated class SelectionChannel: Sendable {
  /// bits 63..48 dwell, bits 47..32 swell, bit 0 acquired.
  ///
  /// The two fractions are 16-bit fixed point over `[0, 1]`, the same encoding and for the same
  /// reason as `CursorPositionChannel`: three values in ONE word is what makes the read consistent
  /// without a lock, and a reader can never observe a green target beside a stale dwell. 1/65535 is
  /// far finer than the difference either value can make to a pixel — the dwell drives a ring radius
  /// over a handful of pixels, and the swell a colour blend.
  private let packed = Atomic<UInt64>(0)

  public init() {}

  /// Publish the latest state. Non-finite input and out-of-range values clamp into `[0, 1]`, so a
  /// bad producer value can never reach the shader as a NaN radius or a NaN colour blend.
  public func store(dwell: Float, acquired: Bool, swell: Float) {
    let value = UInt64(Self.quantise(dwell)) << 48
      | UInt64(Self.quantise(swell)) << 32
      | (acquired ? 1 : 0)
    packed.store(value, ordering: .releasing)
  }

  /// Read the latest published state.
  public func load() -> SelectionState {
    let value = packed.load(ordering: .acquiring)
    return SelectionState(
      dwell: Float((value >> 48) & 0xFFFF) / 65535,
      acquired: value & 1 != 0,
      swell: Float((value >> 32) & 0xFFFF) / 65535
    )
  }

  private static func quantise(_ value: Float) -> UInt16 {
    guard value.isFinite else { return 0 }
    return UInt16(min(max(value, 0), 1) * 65535 + 0.5)
  }
}
