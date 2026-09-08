// SelectionChannel — the producer→renderer seam for click-to-select display state.
//
// Four values, one word: the click pinch on the cursor, and the green hit marker's position and
// fade. They are produced together on the same 20 ms tick and consumed together on the same frame,
// and a frame must never draw a marker at a stale position beside a fresh fade.
//
// Like `TargetChannel` this is store-latest / load-latest with no queue and no back pressure. A
// frame landing between producer ticks reads the previous state, which is correct: there is nothing
// to interpolate and nothing to miss.
import Synchronization

/// The click pinch and the green hit marker, as the renderer draws them.
public nonisolated struct SelectionState: Sendable, Equatable {
  /// The click animation, `1 → 0` over its release. Contracts the cursor ring.
  ///
  /// A click is instantaneous, so this exists to make it visible: the ring pinches and releases the
  /// way a selection reads on a cursor with no button.
  public let clickPulse: Float
  /// Where the last click landed a hit, in grid-normalised `[0, 1]`. Meaningless when `hitFade` is 0.
  public let hitX: Float
  public let hitY: Float
  /// How recently that hit happened, `1 → 0`. 0 means there is no marker to draw.
  ///
  /// The click lands AT the trial boundary -- the moment the recorded task moves its target on --
  /// so the square that was just hit is no longer the active target. The marker is what keeps it on
  /// screen, green, beside the new red target, for long enough to read.
  public let hitFade: Float

  public init(clickPulse: Float, hitX: Float, hitY: Float, hitFade: Float) {
    self.clickPulse = clickPulse
    self.hitX = hitX
    self.hitY = hitY
    self.hitFade = hitFade
  }

  public static let idle = SelectionState(clickPulse: 0, hitX: 0, hitY: 0, hitFade: 0)
}

/// The live selection state the renderer draws.
public final nonisolated class SelectionChannel: Sendable {
  /// bits 63..48 clickPulse, 47..32 hitX, 31..16 hitY, 15..0 hitFade.
  ///
  /// All four are 16-bit fixed point over `[0, 1]`, the same encoding and for the same reason as
  /// `CursorPositionChannel`: four values in ONE word is what makes the read consistent without a
  /// lock. 1/65535 is far finer than a pixel at any plausible window size, and finer than a ring
  /// radius or a colour blend can resolve.
  private let packed = Atomic<UInt64>(0)

  public init() {}

  /// Publish the latest state. Non-finite input and out-of-range values clamp into `[0, 1]`, so a
  /// bad producer value can never reach the shader as a NaN radius or a NaN colour blend.
  public func store(clickPulse: Float, hitX: Float, hitY: Float, hitFade: Float) {
    let value = UInt64(Self.quantise(clickPulse)) << 48
      | UInt64(Self.quantise(hitX)) << 32
      | UInt64(Self.quantise(hitY)) << 16
      | UInt64(Self.quantise(hitFade))
    packed.store(value, ordering: .releasing)
  }

  /// Read the latest published state.
  public func load() -> SelectionState {
    let value = packed.load(ordering: .acquiring)
    return SelectionState(
      clickPulse: Float((value >> 48) & 0xFFFF) / 65535,
      hitX: Float((value >> 32) & 0xFFFF) / 65535,
      hitY: Float((value >> 16) & 0xFFFF) / 65535,
      hitFade: Float(value & 0xFFFF) / 65535
    )
  }

  private static func quantise(_ value: Float) -> UInt16 {
    guard value.isFinite else { return 0 }
    return UInt16(min(max(value, 0), 1) * 65535 + 0.5)
  }
}
