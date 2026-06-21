// Re-export the cbindgen FFI module so consumers of `CortexRing` automatically see the `CortexFrame`
// type that `push`/`pop` traffic in — without it, the public API would be unusable (you could not
// name its parameter/return type). This keeps `CortexFrame` the single C-defined type (D-R6); we
// re-export it, never re-declare it.
@_exported import CortexRingFFI

/// A safe, single-producer/single-consumer (SPSC) bounded ring of `CortexFrame`s, backed by the
/// loom-verified Rust ring over the `cbindgen` C ABI.
///
/// ## Threading contract (SPSC)
/// This wrapper does NOT enforce thread-affinity. The underlying Rust ring is wait-free for exactly
/// **one producer thread** (`push`) and **one consumer thread** (`pop`) — the same contract the
/// Rust `Producer`/`Consumer` split encodes (Plan 03-02). Calling `push` from two threads, or `pop`
/// from two threads, is undefined behavior. The Phase-3 producer is the `QOS_CLASS_USER_INTERACTIVE`
/// pthread hot path (`CortexRingHotPath`); the Phase-6 consumer is the renderer's display-link
/// callback.
///
/// ## Lifetime (RAII)
/// `init?` allocates the ring (`cortex_spsc_create`) and returns `nil` if the C side rejects the
/// capacity (zero / non-power-of-two) by returning null. `deinit` destroys it
/// (`cortex_spsc_destroy`) exactly once. There is deliberately **no public manual `destroy`** — that
/// would invite a double-free (threat T-03-04-01); the handle's lifetime is bound to this object.
public final class CortexRing {
  /// The opaque `*mut CortexSpsc` handle returned by `cortex_spsc_create`, owned by this instance.
  ///
  /// Stored as `OpaquePointer` (the ring's layout is private to Rust — the C/Swift side only ever
  /// holds a pointer). It is bridged to the cbindgen-imported `UnsafeMutablePointer<CortexSpsc>`
  /// only at each C call site, so no layout is ever assumed on the Swift side.
  private let handle: OpaquePointer

  /// Allocates a ring with `capacity` slots, or returns `nil` if the C side rejects the capacity.
  ///
  /// - Parameter capacity: MUST be a non-zero power of two — the Rust ring's `mask = capacity - 1`
  ///   wrap arithmetic requires it (threat T-03-02-04). A zero or non-power-of-two value makes
  ///   `cortex_spsc_create` return null, which this initializer surfaces as `nil` (no handle is
  ///   constructed, so `deinit` never destroys a null — T-03-04-01).
  public init?(capacity: Int) {
    // A negative count can never be a valid power-of-two capacity; reject it before the C boundary
    // (the C side takes `uintptr_t`/`UInt`, so a negative `Int` must not be bit-cast through).
    guard capacity > 0, let raw = cortex_spsc_create(UInt(capacity)) else { return nil }
    handle = OpaquePointer(raw)
  }

  deinit {
    // RAII: destroy the ring exactly once. `cortex_spsc_destroy` reconstructs and drops the
    // backing `Box`, draining any still-live slots (no double-free / no uninitialized-slot drop —
    // T-03-02-01 / T-03-02-02). After this the handle must never be used again; nothing else holds
    // it, so there is no use-after-free path (T-03-04-01).
    cortex_spsc_destroy(UnsafeMutablePointer<CortexSpsc>(handle))
  }

  /// Pushes one frame into the ring (copied by value). Call ONLY from the single producer thread.
  ///
  /// - Parameter frame: the `CortexFrame` to enqueue. `channel_data` is copied as opaque bytes.
  /// - Returns: `true` if the frame was enqueued; `false` if the ring is full.
  @discardableResult
  public func push(_ frame: CortexFrame) -> Bool {
    withUnsafePointer(to: frame) { ptr in
      cortex_spsc_push(UnsafeMutablePointer<CortexSpsc>(handle), ptr)
    }
  }

  /// Pops one frame from the ring. Call ONLY from the single consumer thread.
  ///
  /// - Returns: the next `CortexFrame` in FIFO order, or `nil` if the ring is empty.
  ///
  /// The output is zero-initialized before being passed to `cortex_spsc_pop`, and is returned ONLY
  /// when the C side reports `true` — so the caller never observes an uninitialized frame
  /// (information-disclosure mitigation, T-03-04-03).
  public func pop() -> CortexFrame? {
    var out = CortexFrame() // zero-init: never read uninitialized (T-03-04-03)
    let got = cortex_spsc_pop(UnsafeMutablePointer<CortexSpsc>(handle), &out)
    return got ? out : nil
  }
}
