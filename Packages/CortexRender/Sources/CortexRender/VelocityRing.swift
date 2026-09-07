// VelocityRing — an in-process, lock-free, single-producer/single-consumer (SPSC) bounded ring of
// `CursorVelocity` frames (Phase 6 D-03).
//
// Per D-03 the velocity seam reuses the Phase-3 loom-verified ring DESIGN — but in-process and
// Swift-side, because the Phase-6 producer is synthetic and lives in the app process (no
// cross-process daemon hop, unlike the Phase-2 neural ring). RESEARCH Decision 5 recommends the
// "lean Swift-side" ring now; the layout is chosen so a future `#[repr(C)] CursorVelocity` +
// `cbindgen` Rust producer (Phase 7) swaps in transparently to consumers — exactly as `CortexRing`
// wraps the Rust SPSC today.
//
// ## Threading contract (SPSC)
// EXACTLY ONE producer thread calls `push`; EXACTLY ONE consumer thread calls `pop`. The Phase-6
// producer is the synthetic/decoder thread; the consumer is the renderer's display-link callback
// (Plan 03). `pop` is callback-safe: no locks, no allocation — a single `Atomic` acquire, one value
// copy, one `Atomic` release. Calling `push` from two threads, or `pop` from two threads, is
// undefined behavior (the same contract the Phase-3 `CortexRing` encodes).
//
// ## Memory ordering — torn-read mitigation (threat T-06-02-02)
// Backed by the built-in `Synchronization.Atomic` (no extra SwiftPM dependency). The producer
// WRITES the slot THEN RELEASES the tail index; the consumer ACQUIRES the tail THEN READS the slot.
// The release/acquire pair publishes the slot write before the index becomes visible, so a
// half-written frame is NEVER observed by the consumer. This mirrors the Phase-3 ring's
// Release-publish / Acquire-observe discipline (NO SeqCst). `CursorVelocity` is a trivial value type
// copied by value (no heap pointers ⇒ no use-after-free). A bounded `push` returns `false` when full
// (it never overwrites an unconsumed frame — DoS disposition T-06-02-03 is "accept + drop surplus").

import Synchronization

/// A lock-free SPSC bounded ring of `CursorVelocity` frames (D-03). `init?` returns `nil` for a
/// zero / non-power-of-two capacity (mirrors the `CortexRing` capacity guard).
///
/// ## `@unchecked Sendable` justification
/// The ring instance is shared between EXACTLY TWO threads BY DESIGN (the producer calls `push`, the
/// display-link consumer calls `pop`), so it must cross a concurrency boundary — that is the entire
/// purpose of the seam. The compiler cannot prove the SPSC discipline, so the conformance is
/// `@unchecked`. Safety rests on: (1) the `Atomic` head/tail with Release-publish / Acquire-observe
/// ordering (no torn read — T-06-02-02); (2) the protocol invariant that ONLY the producer writes a
/// slot and advances `tail`, and ONLY the consumer reads a slot and advances `head`, so no two
/// threads touch the same memory without an intervening release/acquire; (3) `CursorVelocity` is a
/// trivial value type (no shared heap state). This mirrors the Phase-3 ring's contract exactly — the
/// SPSC guarantee is a discipline the caller upholds (one producer thread, one consumer thread), not
/// a property the type system enforces.
public final nonisolated class VelocityRing: @unchecked Sendable {
  /// Backing storage: `capacity` slots. A trivial value type, so a slot store is a single copy.
  /// `nonatomic_unsafe` accessor pattern: only the producer writes a slot (before releasing `tail`)
  /// and only the consumer reads it (after acquiring `tail`), so the release/acquire on the indices
  /// is what orders the slot accesses — the buffer itself needs no per-element atomic.
  private let buffer: UnsafeMutableBufferPointer<CursorVelocity>

  /// `capacity - 1`; wrap arithmetic requires `capacity` to be a power of two (so `& mask`
  /// replaces a modulo). One slot is kept empty to disambiguate full from empty, so the usable
  /// depth is `capacity - 1` frames.
  private let mask: Int

  /// Write cursor — advanced by the producer only. Published with `.releasing`.
  private let tail = Atomic<Int>(0)
  /// Read cursor — advanced by the consumer only. Published with `.releasing`.
  private let head = Atomic<Int>(0)

  /// Allocate a ring with `capacity` slots, or return `nil` if `capacity` is zero or not a power of
  /// two (the `mask = capacity - 1` wrap arithmetic requires a power-of-two capacity — mirrors
  /// `cortex_spsc_create` / the Phase-3 ring's T-03-02-04 capacity guard).
  public init?(capacity: Int) {
    guard capacity > 0, (capacity & (capacity - 1)) == 0 else { return nil }
    mask = capacity - 1
    buffer = UnsafeMutableBufferPointer<CursorVelocity>.allocate(capacity: capacity)
    // Zero-initialize every slot so no slot is ever read uninitialized (defensive; the SPSC
    // protocol never reads a slot the producer has not written, but this removes UB entirely).
    buffer.initialize(repeating: CursorVelocity(ts_ns: 0, seq: 0, vx: 0, vy: 0))
  }

  deinit {
    // The slots hold a trivial value type (no class refs), so deinitialize is a no-op for ARC, but
    // we still balance the `initialize` before freeing the allocation (no leak, no double-free).
    buffer.deinitialize()
    buffer.deallocate()
  }

  /// Push one frame (copied by value). Call ONLY from the single producer thread.
  ///
  /// - Returns: `true` if enqueued; `false` if the ring is full (the caller drops the surplus —
  ///   DoS disposition T-06-02-03).
  @discardableResult
  public func push(_ v: CursorVelocity) -> Bool {
    // Producer owns `tail`: a relaxed load of our own cursor is sufficient. We must observe the
    // consumer's latest `head` to know whether the next slot is free — acquire it.
    let t = tail.load(ordering: .relaxed)
    let h = head.load(ordering: .acquiring)
    let next = (t + 1) & mask
    if next == h { return false } // full — never overwrite an unconsumed frame
    buffer[t] = v // write the slot FIRST …
    tail.store(next, ordering: .releasing) // … THEN publish it (release pairs with pop's acquire)
    return true
  }

  /// Pop one frame in FIFO order. Call ONLY from the single consumer thread. Callback-safe.
  ///
  /// - Returns: the next `CursorVelocity`, or `nil` if the ring is empty.
  public func pop() -> CursorVelocity? {
    // Consumer owns `head`: relaxed load of our own cursor. Acquire `tail` so that, if a new frame
    // is visible, the slot write the producer did BEFORE releasing `tail` is also visible to us
    // (the torn-read mitigation, T-06-02-02).
    let h = head.load(ordering: .relaxed)
    let t = tail.load(ordering: .acquiring)
    if h == t { return nil } // empty
    let v = buffer[h] // read the published slot
    head.store((h + 1) & mask, ordering: .releasing) // free the slot for the producer
    return v
  }
}
