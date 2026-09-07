// SelectionChannel — the producer→renderer seam for dwell-to-select display state.
//
// Two values, one word, because they are produced together on the same 20 ms tick and consumed
// together on the same frame: how much of the continuous hold has accumulated, and how recently a
// selection committed. Splitting them across two atomics would let a frame draw a full-size cursor
// beside a fading flash from the selection that just released it.
//
// Like `TargetChannel` this is store-latest / load-latest with no queue and no back pressure. A
// frame landing between producer ticks reads the previous pair, which is correct for both: there is
// nothing to interpolate and nothing to miss.
import Synchronization

/// Dwell progress and selection flash, as the renderer draws them.
public nonisolated struct SelectionState: Sendable, Equatable {
  /// Fraction of the continuous hold accumulated, in `[0, 1]`.
  ///
  /// The producer commits the selection and resets to 0 on the tick this would reach 1, so a reader
  /// sees the fraction climb and then snap back. That snap IS the selection.
  public let dwell: Float
  /// How recently a selection committed, decaying `1 → 0`. 0 means no recent selection.
  public let flash: Float

  public init(dwell: Float, flash: Float) {
    self.dwell = dwell
    self.flash = flash
  }

  public static let idle = SelectionState(dwell: 0, flash: 0)
}

/// The live selection state the renderer draws.
public final nonisolated class SelectionChannel: Sendable {
  /// High 32 bits the dwell's `Float.bitPattern`, low 32 the flash's. Both whole floats, so the
  /// values cross the seam exactly rather than being quantised, and a reader can never observe one
  /// updated beside the other stale.
  private let packed = Atomic<UInt64>(0)

  public init() {}

  /// Publish the latest state. Non-finite input and out-of-range values clamp into `[0, 1]`, so a
  /// bad producer value can never reach the shader as a NaN radius or a NaN colour blend.
  public func store(dwell: Float, flash: Float) {
    let safeDwell = dwell.isFinite ? min(max(dwell, 0), 1) : 0
    let safeFlash = flash.isFinite ? min(max(flash, 0), 1) : 0
    let value = UInt64(safeDwell.bitPattern) << 32 | UInt64(safeFlash.bitPattern)
    packed.store(value, ordering: .releasing)
  }

  /// Read the latest published state.
  public func load() -> SelectionState {
    let value = packed.load(ordering: .acquiring)
    return SelectionState(
      dwell: Float(bitPattern: UInt32(truncatingIfNeeded: value >> 32)),
      flash: Float(bitPattern: UInt32(truncatingIfNeeded: value))
    )
  }
}
