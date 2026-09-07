// TargetChannel — the producer→renderer channel carrying the ACTIVE TASK TARGET cell.
//
// The velocity ring (`VelocityRing`) carries motion; this carries the thing the motion is aimed at.
// They are deliberately separate: the ring is a queue the consumer drains sample by sample, while
// the target is a LATEST-VALUE signal with no history worth keeping. A renderer that fell a frame
// behind on velocity still wants the newest target, not a backlog of stale ones.
//
// Concurrency posture matches `VelocityRing`: a single `Atomic` load/store on the display-link
// callback path, no locks, no allocation, no ARC traffic in the hot path (the audio-callback-regime
// discipline this project holds renderer-side code to).
//
// The cell is packed into one 32-bit word so a reader observes column and row from the SAME write.
// Two separate atomics could tear across a target change and render a cell that never existed.

import Synchronization

/// The active task target, as a grid cell, shared producer to renderer.
///
/// `Sendable` and lock-free: the producer calls ``store(column:row:)`` (or ``clear()``) on its own
/// cadence and the renderer calls ``load()`` once per frame.
public final class TargetChannel: Sendable {
  /// Packed `(column << 16) | row`, or ``TargetChannel/empty`` when no target is active.
  ///
  /// `UInt32.max` is the empty sentinel rather than a separate flag word, so "is there a target"
  /// and "which cell" are answered by one atomic load and cannot disagree.
  private static let empty: UInt32 = .max

  private let packed = Atomic<UInt32>(TargetChannel.empty)

  public init() {}

  /// Publish the active target cell. Columns and rows above `UInt16.max` are refused rather than
  /// truncated, because a silently wrapped cell would render a target in the wrong place.
  public func store(column: Int, row: Int) {
    guard column >= 0, row >= 0, column <= Int(UInt16.max), row <= Int(UInt16.max) else {
      clear()
      return
    }
    let value = UInt32(UInt16(column)) << 16 | UInt32(UInt16(row))
    // The sentinel is a legal packing of (65535, 65535); a grid that large is not reachable here,
    // but treat it as empty rather than let it alias.
    packed.store(value == TargetChannel.empty ? TargetChannel.empty : value, ordering: .releasing)
  }

  /// Withdraw the active target, so the renderer draws none.
  public func clear() {
    packed.store(TargetChannel.empty, ordering: .releasing)
  }

  /// The active target cell, or `nil` when none is set.
  public func load() -> (column: UInt32, row: UInt32)? {
    let value = packed.load(ordering: .acquiring)
    guard value != TargetChannel.empty else { return nil }
    return (column: value >> 16, row: value & 0xFFFF)
  }
}
