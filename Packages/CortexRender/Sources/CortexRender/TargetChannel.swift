// TargetChannel — the active task target, published to the renderer once per tick.
//
// ## Why this carries a POSITION and not a cell
// It used to carry a 30x30 cell index, and the shader filled that cell. But the acquisition
// criterion is a distance to the target's ACTUAL position, which is wherever the task put it, not
// wherever the grid quantises it to. On this session those differ by a median 2.26 mm against a
// 2.86 mm acquisition radius, and for 15 of the 64 targets the cell centre falls OUTSIDE the radius
// altogether -- so a cursor drawn dead centre in the red square was scored as a miss.
//
// That is the worst kind of display bug: the viewer sees the cursor land, sees the ring close, and
// nothing registers, with no way to tell from the screen that the square and the criterion are not
// the same place. The target is now published where it actually is, and the shader draws it at the
// acquisition radius, so "the cursor is in the square" and "the criterion is satisfied" agree.
import Synchronization

/// The active target's position in grid-normalised `[0, 1]` space.
public nonisolated struct ActiveTarget: Sendable, Equatable {
  public let x: Float
  public let y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }
}

/// A latest-value channel for the active target. One atomic word, no queue, no back pressure.
public final class TargetChannel: Sendable {
  /// "No target" sentinel. A real target always sets the high bit, so 0 can never be a live value.
  private static let empty: UInt64 = 0
  /// bit 32 validity, bits 31..16 x, bits 15..0 y, as 16-bit fixed point over `[0, 1]`. That
  /// resolves to about 1/2000 of a cell, far finer than a pixel at any plausible window size.
  private let packed = Atomic<UInt64>(TargetChannel.empty)

  public init() {}

  /// Publish the active target. Non-finite or out-of-grid input clears instead of publishing: a
  /// target the task never showed must not be drawn, and clamping one into range would invent a
  /// location for it.
  public func store(x: Float, y: Float) {
    guard x.isFinite, y.isFinite, x >= 0, x < 1, y >= 0, y < 1 else {
      clear()
      return
    }
    let qx = UInt64(x * 65535 + 0.5)
    let qy = UInt64(y * 65535 + 0.5)
    packed.store(1 << 32 | qx << 16 | qy, ordering: .releasing)
  }

  public func clear() {
    packed.store(TargetChannel.empty, ordering: .releasing)
  }

  /// The active target, or `nil` when none is showing.
  public func load() -> ActiveTarget? {
    let value = packed.load(ordering: .acquiring)
    guard value & (1 << 32) != 0 else { return nil }
    return ActiveTarget(
      x: Float((value >> 16) & 0xFFFF) / 65535,
      y: Float(value & 0xFFFF) / 65535
    )
  }
}
