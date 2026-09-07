// CursorPositionChannel — the producer's authoritative cursor position, published every tick.
//
// ## Why this exists
// There were two cursors. The producer integrated `velocity * 0.020` once per tick and used the
// result for the Kalman filter, the target steering and the dwell criterion; the renderer kept its
// own integrator and advanced it by the REAL display-link frame delta. Those are different clocks.
// The producer's 20 ms `Timer` runs on the main actor against SwiftUI and does not fire at exactly
// 50 Hz, while the renderer integrates however much wall time actually passed, so the drawn cursor
// and the scored cursor drift apart within a single trial.
//
// The visible symptom is a cursor sitting inside the target square with its ring closed while
// nothing registers, because the criterion is measuring a point the viewer cannot see. A demo whose
// displayed cursor is not the cursor being scored is showing the wrong thing, however good the
// decode is.
//
// So the producer's position is authoritative and is published here every tick. The renderer snaps
// to it and extrapolates with the held velocity between ticks, which keeps 120 Hz smoothness while
// making the two agree exactly at every producer tick.
//
// One atomic word, store-latest / load-latest, with a generation counter so the consumer applies
// each publication once and extrapolates the rest of the time instead of re-snapping every frame.
import Synchronization

/// The producer's cursor position for one tick.
public nonisolated struct AuthoritativeCursor: Sendable, Equatable {
  /// Position in grid-normalised `[0, 1]` space.
  public let x: Float
  public let y: Float
  /// Monotonic publication id, so a consumer polling faster than the producer applies each once.
  public let generation: UInt32

  public init(x: Float, y: Float, generation: UInt32) {
    self.x = x
    self.y = y
    self.generation = generation
  }
}

/// The latest authoritative cursor position.
public final nonisolated class CursorPositionChannel: Sendable {
  /// bits 63..32 generation, bits 31..16 x, bits 15..0 y.
  ///
  /// Position is 16-bit fixed point over the grid's `[0, 1]` extent, which resolves to about 1/2000
  /// of a 30x30 cell -- far finer than a pixel at any plausible window size -- and leaves 32 bits
  /// for the generation. All three in ONE word is what makes the read consistent without a lock: a
  /// consumer can never observe a new generation beside a stale position.
  private let packed = Atomic<UInt64>(0)

  public init() {}

  /// Publish this tick's position. Non-finite input is dropped rather than published, so a bad
  /// producer value can never teleport the cursor; out-of-range values clamp to the grid.
  public func store(x: Float, y: Float) {
    guard x.isFinite, y.isFinite else { return }
    let qx = UInt64(min(max(x, 0), 1) * 65535 + 0.5)
    let qy = UInt64(min(max(y, 0), 1) * 65535 + 0.5)
    let generation = UInt64(truncatingIfNeeded: currentGeneration &+ 1)
    packed.store(generation << 32 | qx << 16 | qy, ordering: .releasing)
  }

  private var currentGeneration: UInt32 {
    UInt32(truncatingIfNeeded: packed.load(ordering: .acquiring) >> 32)
  }

  /// The published position, or `nil` if nothing new has been published since `lastSeen`.
  public func take(after lastSeen: UInt32) -> AuthoritativeCursor? {
    let value = packed.load(ordering: .acquiring)
    let generation = UInt32(truncatingIfNeeded: value >> 32)
    guard generation != 0, generation != lastSeen else { return nil }
    return AuthoritativeCursor(
      x: Float((value >> 16) & 0xFFFF) / 65535,
      y: Float(value & 0xFFFF) / 65535,
      generation: generation
    )
  }
}
