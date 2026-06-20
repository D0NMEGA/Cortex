//! The in-house, loom-verifiable, lock-free **single-producer / single-consumer** bounded ring —
//! the heart of Phase 3 (THREAD-04/05/07, SC#3). It mirrors `rtrb`'s wait-free algorithm but routes
//! every atomic and every slot cell through [`crate::loom`] (D-R3/D-R5) so the *same* code is, with
//! **zero algorithm duplication** between production and the model checker, all three of:
//!
//! 1. the production ring the `extern "C"` ABI drives (Task 3);
//! 2. the body of a 1M-frame std-atomic stress test (`tests/stress_fifo.rs`, SC#3b); and
//! 3. the body of a tiny exhaustive `loom` permutation test (`tests/loom_spsc.rs`, SC#3a).
//!
//! ## Memory ordering — Release-publish / Acquire-observe ONLY (D-R4, RESEARCH §1, Pitfall #5)
//! A core reloads *its own* index `Relaxed`. The producer observes the consumer's progress with
//! `head.load(Acquire)` and publishes a written slot with `tail.store(.., Release)`; the consumer
//! observes the producer's progress with `tail.load(Acquire)` and publishes a freed slot with
//! `head.store(.., Release)`. This Release→Acquire edge is what makes the slot write
//! *happen-before* the slot read, so the data transfer is race-free. The sequentially-consistent
//! ordering is deliberately never used here — loom models it as `AcqRel` and cannot soundly verify
//! its global total order, so relying on it would make the loom proof invalid (D-R4, Pitfall #5).
//!
//! ## Cache-line padding — 128 bytes, NOT 64 (D-R4, RESEARCH §1, Pitfall #3)
//! Apple Silicon's cache-line / prefetch granularity is 128 B (`crossbeam-utils::CachePadded`
//! special-cases `aarch64` to `align(128)`). `head` (consumer-owned) and `tail` (producer-owned)
//! are each `#[repr(align(128))]` so they never share a line — false sharing on those two atomics
//! would silently halve SPSC throughput.
//!
//! ## Soundness (the SPSC contract)
//! The `Producer`/`Consumer` split makes multi-producer/multi-consumer misuse a *type error*
//! (neither is `Clone`; each is the sole writer of its index). That single-producer/single-consumer
//! invariant is precisely what makes the `UnsafeCell` slot access sound — see each `// SAFETY:`.

use crate::loom::atomic::{AtomicUsize, Ordering};
use crate::loom::cell_compat::CortexCell;
use crate::loom::sync::Arc;
use core::mem::MaybeUninit;

/// A 128-byte cache-line-aligned atomic index (D-R4, Pitfall #3). `head` and `tail` are each one of
/// these so the producer's and consumer's hot atomics never land on the same line.
#[repr(align(128))]
struct CachePad(AtomicUsize);

// Cache-line discipline, proven at compile time (SC#3c). The negative control in the test module
// flips this to `align(64)` to prove the assertion actually bites; restore to 128 after.
const _: () = assert!(core::mem::align_of::<CachePad>() == 128);

impl CachePad {
    #[inline]
    fn new(value: usize) -> Self {
        Self(AtomicUsize::new(value))
    }

    #[inline]
    fn load(&self, order: Ordering) -> usize {
        self.0.load(order)
    }

    #[inline]
    fn store(&self, value: usize, order: Ordering) {
        self.0.store(value, order);
    }
}

/// The shared ring state. Both ends hold an `Arc<Spsc<T>>`; the buffer is a power-of-two run of
/// uninitialized slots, and `head`/`tail` are free-running monotonic counters masked into the
/// buffer with `& mask` (the classic rtrb scheme — the gap between `tail` and `head` is the live
/// element count, and the power-of-two capacity makes `& mask` the wrap).
pub struct Spsc<T> {
    /// `capacity` (power-of-two) uninitialized slots. A slot in `[head, tail)` (mod wrap) is
    /// initialized; all others are uninitialized. Race-free because Release/Acquire orders the
    /// slot write before the slot read (D-R4).
    buffer: Box<[CortexCell<MaybeUninit<T>>]>,
    /// `capacity - 1`. Valid only because `capacity.is_power_of_two()` (checked in `channel`), so
    /// `index & mask == index % capacity` (Pitfall: non-pow2 capacity → wrong wrap → silent loss).
    mask: usize,
    /// Consumer-owned monotonic read index (the next slot to pop). 128-B padded.
    head: CachePad,
    /// Producer-owned monotonic write index (the next slot to push). 128-B padded.
    tail: CachePad,
}

// SAFETY: `Spsc<T>` is shared across the producer and consumer threads via `Arc`. It is safe to
// send/share when `T: Send` because the `Producer`/`Consumer` split guarantees exactly one writer
// of each index and disjoint slot access ordered by the Release/Acquire edge — there is no shared
// mutable access to the same slot at the same time. `CortexCell`/`MaybeUninit` are otherwise not
// `Sync`, so these impls assert the hand-proved SPSC invariant.
unsafe impl<T: Send> Send for Spsc<T> {}
unsafe impl<T: Send> Sync for Spsc<T> {}

impl<T> Spsc<T> {
    /// Number of live (pushed-but-not-popped) elements, computed from the two monotonic counters.
    /// `wrapping_sub` keeps it correct across `usize` counter wraparound.
    #[inline]
    fn len(head: usize, tail: usize) -> usize {
        tail.wrapping_sub(head)
    }
}

impl<T> Drop for Spsc<T> {
    /// Drain the slots still live at drop so initialized `T`s are dropped exactly once and no
    /// `MaybeUninit` slot outside `[head, tail)` is ever touched (threat T-03-02-02: no
    /// double-free, no uninitialized-memory drop, no leak of a live element).
    fn drop(&mut self) {
        // At drop there are no other threads (both `Producer` and `Consumer` are gone — they hold
        // the only `Arc`s), so a plain `Relaxed`/`Acquire` load of each index is sufficient.
        let head = self.head.load(Ordering::Acquire);
        let tail = self.tail.load(Ordering::Acquire);
        let mut idx = head;
        while idx != tail {
            let slot = &self.buffer[idx & self.mask];
            // SAFETY: every index in `[head, tail)` (mod wrap) was written by `Producer::push` and
            // not yet read by `Consumer::pop`, so the slot holds an initialized `T`. We are the
            // sole owner at drop (no concurrent access), and we visit each such slot exactly once,
            // so `assume_init_drop` drops each live `T` exactly once.
            slot.with_mut(|p| unsafe { (*p).assume_init_drop() });
            idx = idx.wrapping_add(1);
        }
    }
}

/// The producer end — the **only** writer of `tail`. Not `Clone`: a second producer would violate
/// the single-producer invariant the `UnsafeCell` soundness rests on (compile-time SPSC enforcement
/// — T-03-02-06).
pub struct Producer<T> {
    ring: Arc<Spsc<T>>,
}

// SAFETY: a `Producer<T>` may be moved to another thread when `T: Send` (the established pattern is
// to spawn the producer thread and move the `Producer` into it — the in-repo `Benchmark.swift`
// idiom, RESEARCH §4). It is the sole writer of `tail`; no shared mutable aliasing.
unsafe impl<T: Send> Send for Producer<T> {}

impl<T> Producer<T> {
    /// Push one value. Returns `Err(val)` (giving the value back) when the ring is full.
    ///
    /// Wait-free: a bounded number of steps, no spinning, no locks (THREAD-04/05).
    pub fn push(&self, val: T) -> Result<(), T> {
        let ring = &*self.ring;
        // Our own index — Relaxed: only this (single) producer writes `tail`, so no other thread's
        // store needs to be observed here (D-R4 "own index reload").
        let tail = ring.tail.load(Ordering::Relaxed);
        // Observe the consumer's progress — Acquire: synchronizes-with the consumer's
        // `head.store(.., Release)`, so a slot the consumer has freed is safe to overwrite.
        let head = ring.head.load(Ordering::Acquire);

        if Spsc::<T>::len(head, tail) == ring.buffer.len() {
            return Err(val); // full
        }

        let slot = &ring.buffer[tail & ring.mask];
        // SAFETY: `tail & mask` is a slot OUTSIDE the live range `[head, tail)` (the fullness check
        // above guarantees there is room), so the consumer is not reading it. As the sole producer
        // we are the only writer. We `write` (not assign) because the slot is `MaybeUninit` and may
        // be uninitialized; this initializes it without dropping prior (uninit) contents.
        slot.with_mut(|p| unsafe { (*p).write(val) });

        // Publish — Release: makes the slot write above happen-before the consumer's matching
        // `tail.load(Acquire)`, so the consumer never reads a torn/stale slot (D-R4).
        //
        // NEGATIVE CONTROL (SC#3a, Spike B): under `--cfg loom_negative_control` this becomes a
        // `Relaxed` store, deliberately dropping the happens-before edge. The loom permutation test
        // (`tests/loom_spsc.rs`) must then FAIL — loom finds an interleaving where the consumer sees
        // the advanced `tail` without the slot write being ordered before its read. The executor
        // toggles this cfg once to prove the proof bites, then drops it. The cfg is absent in every
        // real build (production AND a normal `--cfg loom` run), so production is always `Release`.
        #[cfg(not(loom_negative_control))]
        let publish = Ordering::Release;
        #[cfg(loom_negative_control)]
        let publish = Ordering::Relaxed;
        ring.tail.store(tail.wrapping_add(1), publish);
        Ok(())
    }
}

/// The consumer end — the **only** writer of `head`. Not `Clone` (single-consumer invariant —
/// T-03-02-06).
pub struct Consumer<T> {
    ring: Arc<Spsc<T>>,
}

// SAFETY: symmetric to `Producer` — the sole writer of `head`, movable to a thread when `T: Send`.
unsafe impl<T: Send> Send for Consumer<T> {}

impl<T> Consumer<T> {
    /// Pop one value. Returns `None` when the ring is empty.
    ///
    /// Wait-free: a bounded number of steps, no spinning, no locks.
    pub fn pop(&self) -> Option<T> {
        let ring = &*self.ring;
        // Our own index — Relaxed: only this (single) consumer writes `head`.
        let head = ring.head.load(Ordering::Relaxed);
        // Observe the producer's publish — Acquire: synchronizes-with the producer's
        // `tail.store(.., Release)`, so a slot the producer has published is safe (and fully
        // written) to read.
        let tail = ring.tail.load(Ordering::Acquire);

        if Spsc::<T>::len(head, tail) == 0 {
            return None; // empty
        }

        let slot = &ring.buffer[head & ring.mask];
        // SAFETY: `head & mask` is the oldest slot in the live range `[head, tail)` (non-empty per
        // the check above), so the producer published it (Release→Acquire edge) and is not writing
        // it. As the sole consumer we are the only reader/taker. `assume_init_read` moves the
        // initialized `T` out, leaving the slot logically uninitialized — which is correct, since
        // we immediately advance `head` past it so it is no longer in the live range.
        let val = slot.with(|p| unsafe { (*p).assume_init_read() });

        // Publish the freed slot — Release: makes this read complete before the producer's matching
        // `head.load(Acquire)` lets it reuse the slot (D-R4).
        ring.head.store(head.wrapping_add(1), Ordering::Release);
        Some(val)
    }
}

/// Build a bounded SPSC ring of `capacity_pow2` slots and split it into a [`Producer`]/[`Consumer`]
/// pair sharing the ring via `Arc` (`loom::sync::Arc` under `--cfg loom`).
///
/// # Panics
/// Panics if `capacity_pow2` is not a power of two (mask arithmetic requires it — Pitfall: a
/// non-pow2 capacity makes `& mask` wrap incorrectly and silently lose/duplicate frames). The
/// `extern "C"` `cortex_spsc_create` (Task 3) turns this into a null-return instead of a panic.
pub fn channel<T>(capacity_pow2: usize) -> (Producer<T>, Consumer<T>) {
    assert!(
        capacity_pow2.is_power_of_two(),
        "SPSC ring capacity must be a power of two (got {capacity_pow2}); mask = capacity-1 \
         arithmetic requires it (RESEARCH §1, D-R4)"
    );

    // One uninitialized slot per capacity. `(0..capacity).map(..).collect()` builds the boxed slice
    // without requiring `T: Clone` (which a `vec![cell; n]` would).
    let buffer: Box<[CortexCell<MaybeUninit<T>>]> = (0..capacity_pow2)
        .map(|_| CortexCell::new(MaybeUninit::uninit()))
        .collect();

    let ring = Arc::new(Spsc {
        buffer,
        mask: capacity_pow2 - 1,
        head: CachePad::new(0),
        tail: CachePad::new(0),
    });

    (Producer { ring: ring.clone() }, Consumer { ring })
}

// =================================================================================================
// Unit tests — std atomics, single-threaded (the `<behavior>` GREEN targets). These run under a
// plain `cargo test` (NOT loom); the loom permutation test and the 1M stress test live in `tests/`.
// =================================================================================================
#[cfg(all(test, not(loom)))]
mod tests {
    use super::*;
    use crate::frame::CortexFrame;

    fn frame(seq: u64) -> CortexFrame {
        CortexFrame {
            ts_ns: seq, // tie ts to seq so the test value is fully determined by `seq`
            seq,
            channel_data: [0u16; crate::frame::CORTEX_CHANNEL_COUNT],
        }
    }

    /// SC#3c: the padded index cell is 128-byte-aligned (Apple Silicon cache line, D-R4).
    /// Negative control: changing `#[repr(align(128))]` on `CachePad` to `align(64)` makes BOTH
    /// this assertion AND the crate-level `const _` assert FAIL — proven during execution, then
    /// restored to 128.
    #[test]
    fn cache_pad_is_128() {
        assert_eq!(
            core::mem::align_of::<CachePad>(),
            128,
            "head/tail must be 128-byte cache-line padded on Apple Silicon (D-R4, Pitfall #3)"
        );
    }

    /// Bounded ring is full after `capacity` pushes; the next push returns the value back.
    #[test]
    fn full_ring_rejects_push() {
        let (tx, _rx) = channel::<CortexFrame>(4);
        for i in 0..4 {
            assert!(tx.push(frame(i)).is_ok(), "push {i} of a 4-slot ring");
        }
        // 5th push must fail (ring full) and hand the value back unchanged.
        let overflow = tx.push(frame(99));
        assert!(overflow.is_err(), "5th push into a 4-slot ring must be Err");
        assert_eq!(
            overflow.unwrap_err().seq,
            99,
            "Err returns the rejected value"
        );
    }

    /// After a pop frees a slot, a previously-full ring accepts a push again (the wrap works).
    #[test]
    fn wrap_after_pop() {
        let (tx, rx) = channel::<CortexFrame>(4);
        for i in 0..4 {
            assert!(tx.push(frame(i)).is_ok(), "fill slot {i}");
        }
        assert!(tx.push(frame(4)).is_err(), "full before pop");
        let popped = rx.pop().expect("one element to pop");
        assert_eq!(popped.seq, 0, "FIFO: first popped is the first pushed");
        // A slot is now free → push succeeds and lands in the wrapped slot.
        assert!(
            tx.push(frame(4)).is_ok(),
            "push succeeds after a pop frees a slot"
        );
    }

    /// Single-threaded strict FIFO across a multi-lap workload: push 0..N, pop 0..N in order,
    /// interleaving pushes and pops so the indices wrap multiple times around a small ring.
    #[test]
    fn single_threaded_fifo_multilap() {
        let (tx, rx) = channel::<CortexFrame>(8);
        let mut next_push: u64 = 0;
        let mut next_expect: u64 = 0;
        let total: u64 = 100; // >> capacity, forces many wraps

        while next_expect < total {
            // Fill opportunistically, then drain one — exercises wrap + the full/empty edges.
            while next_push < total && tx.push(frame(next_push)).is_ok() {
                next_push += 1;
            }
            if let Some(f) = rx.pop() {
                assert_eq!(f.seq, next_expect, "strict FIFO order");
                assert_eq!(
                    f.ts_ns, next_expect,
                    "frame payload integrity (ts tied to seq)"
                );
                next_expect += 1;
            }
        }
        assert!(
            rx.pop().is_none(),
            "ring empty after draining all {total} frames"
        );
    }

    /// Empty ring pops `None`; this also covers the len==0 branch.
    #[test]
    fn empty_ring_pops_none() {
        let (_tx, rx) = channel::<CortexFrame>(2);
        assert!(rx.pop().is_none(), "fresh ring is empty");
    }

    /// Non-power-of-two capacity is rejected (mask arithmetic requires pow2). The `extern "C"`
    /// layer (Task 3) turns this panic into a null return instead.
    #[test]
    #[should_panic(expected = "power of two")]
    fn non_pow2_capacity_panics() {
        let _ = channel::<CortexFrame>(3);
    }

    /// `Drop` drains live slots without touching uninitialized ones (T-03-02-02). Uses a payload
    /// with an observable `Drop` to prove exactly the live count is dropped — no double-free, no
    /// drop of an empty slot.
    #[test]
    fn drop_drains_only_live_slots() {
        use std::sync::atomic::{AtomicUsize, Ordering as O};
        use std::sync::Arc as StdArc;

        struct DropCounter(StdArc<AtomicUsize>);
        impl Drop for DropCounter {
            fn drop(&mut self) {
                // Single-threaded test counter — `Relaxed` is sufficient (and keeps this file free
                // of the strongest ordering token, so the ring's no-strong-ordering grep is
                // literal, not just intent-level).
                self.0.fetch_add(1, O::Relaxed);
            }
        }

        let drops = StdArc::new(AtomicUsize::new(0));
        {
            let (tx, rx) = channel::<DropCounter>(8);
            // Push 5, pop 2 → 3 live slots remain at drop; 2 were already moved out (and dropped
            // by the test when the popped values fall out of scope below). `DropCounter` is not
            // `Debug`, so assert on `is_ok()` rather than `.unwrap()` (which would need `T: Debug`).
            for _ in 0..5 {
                assert!(
                    tx.push(DropCounter(drops.clone())).is_ok(),
                    "push live element"
                );
            }
            let popped: Vec<_> = (0..2).map(|_| rx.pop().expect("two elements")).collect();
            drop(popped); // the 2 popped DropCounters drop here → count == 2
            assert_eq!(drops.load(O::Relaxed), 2, "the 2 popped values dropped");
            // tx + rx drop here → the ring's Drop must drain the 3 still-live slots.
        }
        assert_eq!(
            drops.load(O::Relaxed),
            5,
            "ring Drop drained the 3 remaining live slots (2 popped + 3 drained == 5); no \
             uninitialized slot was dropped"
        );
    }
}
