// AnchorChannel — the producer→renderer seam for cursor re-anchoring.
//
// The drawn cursor position does NOT come from the replay pipeline. The pipeline integrates
// decoded velocity for its own filter and scoring; the RENDERER owns a second `CursorIntegrator`
// that consumes the velocity ring at display rate. So moving the pipeline's cursor does not move
// what is on screen, and a re-anchor has to reach the renderer explicitly. This channel is how.
//
// Like `TargetChannel` and `DwellChannel` it is one atomic word, store-latest / load-latest. Unlike
// them it carries a GENERATION counter, because an anchor is an EVENT rather than a level: the
// consumer must apply each one exactly once and then go back to integrating. Reading a level would
// re-apply the same anchor on every frame and freeze the cursor on it.
import Synchronization

/// One re-anchor event: where to move the cursor, and which event this is.
public nonisolated struct CursorAnchor: Sendable, Equatable {
  /// Anchor position in grid-normalised `[0, 1]` space.
  public let x: Float
  public let y: Float
  /// Monotonic event id. A consumer stores the last one it applied and passes it back, so each
  /// anchor moves the cursor exactly once however fast the consumer polls.
  public let generation: UInt32

  public init(x: Float, y: Float, generation: UInt32) {
    self.x = x
    self.y = y
    self.generation = generation
  }
}

/// A latest-value channel carrying "move the cursor here, once".
///
/// The position is packed as two 16-bit fixed-point values over the grid's `[0, 1]` extent, which
/// resolves to about 1/2000 of a 30x30 cell -- far finer than a pixel at any plausible size -- and
/// leaves 32 bits for the generation. Packing all three into ONE word is what makes the read
/// consistent without a lock: a consumer can never observe a new generation beside a stale position.
/// `nonisolated` explicitly: the package default is `MainActor`, but the CONSUMER here is the
/// display-link callback, not the main actor. `CursorIntegrator` next to it is annotated the same
/// way for the same reason.
public final nonisolated class AnchorChannel: Sendable {
  /// bits 63..32 generation, bits 31..16 x, bits 15..0 y.
  private let packed = Atomic<UInt64>(0)

  public init() {}

  /// Publish a new anchor. Non-finite input is dropped rather than published, so a bad producer
  /// value can never teleport the cursor; out-of-range values clamp to the grid.
  public func store(x: Float, y: Float) {
    guard x.isFinite, y.isFinite else { return }
    let qx = UInt64(min(max(x, 0), 1) * 65535 + 0.5)
    let qy = UInt64(min(max(y, 0), 1) * 65535 + 0.5)
    let generation = UInt64(truncatingIfNeeded: currentGeneration &+ 1)
    packed.store(generation << 32 | qx << 16 | qy, ordering: .releasing)
  }

  /// The generation currently published (0 before the first store).
  private var currentGeneration: UInt32 {
    UInt32(truncatingIfNeeded: packed.load(ordering: .acquiring) >> 32)
  }

  /// The published anchor, or `nil` if nothing has been published since `lastSeen`.
  ///
  /// The caller keeps `lastSeen` and updates it from the returned generation, so each anchor is
  /// applied exactly once even though the consumer polls far faster than the producer publishes.
  public func take(after lastSeen: UInt32) -> CursorAnchor? {
    let value = packed.load(ordering: .acquiring)
    let generation = UInt32(truncatingIfNeeded: value >> 32)
    guard generation != 0, generation != lastSeen else { return nil }
    return CursorAnchor(
      x: Float((value >> 16) & 0xFFFF) / 65535,
      y: Float(value & 0xFFFF) / 65535,
      generation: generation
    )
  }
}
