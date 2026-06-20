//! SC#3a — the tiny **exhaustive** `loom` permutation test for the SPSC ring's memory ordering.
//!
//! `loom` (tokio-rs/loom 0.7) explores *every* legal interleaving of the producer and consumer
//! threads under the C11 memory model and checks for reordering, torn reads, and data races on the
//! slot memory (the ring's atomics AND its `UnsafeCell` slots route through `crate::loom`, so loom
//! instruments both — RESEARCH §1/§2, the reason an in-house ring is required, D-R3).
//!
//! Run with:  `RUSTFLAGS="--cfg loom" cargo test --profile loom --test loom_spsc`
//!
//! ## Why this scenario is TINY (Pitfall #4 — state-space explosion)
//! loom is exhaustive, so the interleaving count explodes super-linearly with operations/threads.
//! The scenario is therefore deliberately minimal: a **capacity-2** ring, the producer pushes
//! exactly **3** frames, the consumer pops until it has all 3. That is enough to force the ring to
//! WRAP (3 pushes through 2 slots) and to exercise the full Release→Acquire publish/observe edge in
//! both directions, while still terminating in well under the VALIDATION ~120s budget. The 1M-frame
//! throughput/no-loss proof is a SEPARATE std-atomic test (`tests/stress_fifo.rs`, SC#3b) — it is
//! NEVER run under loom (D-R5).
//!
//! ## Negative control (SC#3a, Spike B) — PROVE loom catches a real bug
//! Building with `RUSTFLAGS="--cfg loom --cfg loom_negative_control"` swaps the producer's publish
//! store from `Release` to `Relaxed` (in `crate::spsc`, behind the same cfg). With the publish
//! ordering broken, the consumer can observe an advanced `tail` WITHOUT the happens-before edge that
//! orders the slot write before the slot read — loom finds that interleaving and FAILS. The
//! executor toggles this cfg once to confirm the proof bites, then drops it. (Under a normal
//! `--cfg loom` build the cfg is absent, so this is a no-op and the test passes.)

// Entire file is loom-only: it must NOT be compiled or run under a normal `cargo test` (it would
// pull in the production std atomics, where the model checker has nothing to instrument).
#![cfg(loom)]

use cortex_ring::frame::{CortexFrame, CORTEX_CHANNEL_COUNT};
use cortex_ring::spsc::channel;

/// Build a frame whose payload is fully determined by `seq`, so a popped frame's `seq` is a
/// complete identity check (FIFO order + no value substitution).
fn frame(seq: u64) -> CortexFrame {
    CortexFrame {
        ts_ns: seq,
        seq,
        channel_data: [0u16; CORTEX_CHANNEL_COUNT],
    }
}

/// Exhaustively model a 2-slot ring with a producer thread (3 pushes) and an inline consumer
/// (pops 3). Across EVERY interleaving loom explores, the consumer must observe the 3 frames in
/// strict FIFO order (0, 1, 2) with none lost or torn.
#[test]
fn loom_spsc_fifo_no_loss_all_interleavings() {
    loom::model(|| {
        // Capacity 2 + 3 pushes forces a wrap; ≤3 ops/thread keeps the search tiny (Pitfall #4).
        let (tx, rx) = channel::<CortexFrame>(2);
        const N: u64 = 3;

        // Producer thread: push 0..N, busy-retrying on `Err` (full). `loom::thread::yield_now`
        // hands control back to the model so the consumer's interleavings are explored rather than
        // the producer spinning forever within one schedule.
        let producer = loom::thread::spawn(move || {
            let mut next = 0u64;
            while next < N {
                match tx.push(frame(next)) {
                    Ok(()) => next += 1,
                    Err(_) => loom::thread::yield_now(),
                }
            }
        });

        // Consumer (inline = the model's second thread): pop N frames, asserting strict FIFO.
        let mut expect = 0u64;
        while expect < N {
            match rx.pop() {
                Some(f) => {
                    assert_eq!(f.seq, expect, "FIFO order under this interleaving");
                    assert_eq!(f.ts_ns, expect, "frame payload integrity (ts tied to seq)");
                    expect += 1;
                }
                None => loom::thread::yield_now(),
            }
        }

        producer.join().expect("producer thread completes");

        // Ring fully drained — no frame left behind in ANY interleaving (no-loss).
        assert!(
            rx.pop().is_none(),
            "ring empty after {N} frames consumed (zero loss)"
        );
    });
}
