//! SC#3b — the **1,000,000-frame, two-real-thread, std-atomic** FIFO + zero-loss stress test.
//!
//! This is the *throughput / no-loss* half of the D-R5 two-test split. It runs the SAME ring as the
//! loom test (`crate::spsc`), but with the production `core::sync::atomic` primitives and two OS
//! threads — proving the ring moves a large stream producer→consumer with **strict FIFO** (seq
//! 0,1,2,…,N-1 in order) and **zero loss** (exactly N frames out). It is gated `#![cfg(not(loom))]`
//! so it is NEVER compiled or run under `--cfg loom`: 1M operations would explode loom's exhaustive
//! state space and never terminate (Pitfall #4). The tiny exhaustive ordering proof is the SEPARATE
//! loom test (`tests/loom_spsc.rs`, SC#3a).
//!
//! Run with:  `cargo test --release --test stress_fifo`
//!
//! ## Negative control (SC#3b) — PROVE the FIFO assertion bites
//! Toggling `FRAME_COUNT` vs the consumer's expected count, or an off-by-one in the producer's
//! `seq`, makes the strict-monotonic `assert_eq!(f.seq, expected)` fail. The documented one-line
//! mutation (see `NEGATIVE CONTROL` comment in the consumer loop) proves the check is real; revert
//! after observing the failure.

#![cfg(not(loom))]

use cortex_ring::frame::{CortexFrame, CORTEX_CHANNEL_COUNT};
use cortex_ring::spsc::channel;
use std::thread;

/// One million frames — the SC#3b / VALIDATION requirement.
const FRAME_COUNT: u64 = 1_000_000;
/// Modest power-of-two ring capacity: small enough to force constant wrapping (so the wrap path is
/// exercised ~1000× over the run), large enough that the producer is rarely blocked.
const CAPACITY: usize = 1024;

#[test]
fn stress_1m_frames_strict_fifo_zero_loss() {
    let (tx, rx) = channel::<CortexFrame>(CAPACITY);

    // Producer thread: push frames 0..FRAME_COUNT, busy-retrying while the ring is full. The
    // payload is fully determined by `seq` (ts_ns == seq) so the consumer can assert identity.
    let producer = thread::spawn(move || {
        let mut next: u64 = 0;
        while next < FRAME_COUNT {
            let f = CortexFrame {
                ts_ns: next,
                seq: next,
                channel_data: [0u16; CORTEX_CHANNEL_COUNT],
            };
            match tx.push(f) {
                Ok(()) => next += 1,
                // Ring full — the consumer is behind; spin-hint and retry (busy-poll, the
                // audio-callback-regime discipline — no blocking, no locks).
                Err(_) => std::hint::spin_loop(),
            }
        }
    });

    // Consumer (this thread): pop exactly FRAME_COUNT frames, asserting strict-monotonic seq.
    let mut expected: u64 = 0;
    let mut received: u64 = 0;
    while received < FRAME_COUNT {
        match rx.pop() {
            Some(f) => {
                // Strict FIFO: the n-th frame out MUST be the n-th frame in. A dropped, duplicated,
                // or reordered frame trips this immediately.
                //
                // NEGATIVE CONTROL (SC#3b): change `expected` below to `expected + 1` (or make the
                // producer push `seq: next + 1`) and this assertion fails on the first frame —
                // proving the FIFO check is real. Revert after observing the failure.
                assert_eq!(
                    f.seq, expected,
                    "strict FIFO violated at position {received}: expected seq {expected}, got {}",
                    f.seq
                );
                assert_eq!(
                    f.ts_ns, expected,
                    "frame payload integrity at position {received} (ts_ns tied to seq)"
                );
                expected += 1;
                received += 1;
            }
            // Ring empty — the producer is behind; spin-hint and retry.
            None => std::hint::spin_loop(),
        }
    }

    producer.join().expect("producer thread completes");

    // Zero loss: exactly FRAME_COUNT frames came out, and the ring is now empty (no frame is
    // still buffered, none was produced beyond the count).
    assert_eq!(
        received, FRAME_COUNT,
        "exactly {FRAME_COUNT} frames consumed (zero loss)"
    );
    assert!(
        rx.pop().is_none(),
        "ring fully drained after the stream (no leftover frame)"
    );
}
