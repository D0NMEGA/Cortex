//! Criterion throughput benchmark for the in-house SPSC ring (THREAD-04, D-R3 bench-only role).
//!
//! Measures single-threaded push→pop throughput of `crate::spsc` over a batch of frames (the steady
//! state of the acquisition→UI bridge). An OPTIONAL `rtrb` cross-check (the SPSC ring THREAD-04
//! names) runs the identical workload through `rtrb`'s `Producer`/`Consumer` so the two sit in the
//! same throughput envelope — this is the ONLY place `rtrb` appears (never the loom target, never a
//! production dependency; loom cannot instrument rtrb's std atomics — D-R3, RESEARCH §2).
//!
//! The `rtrb` cross-check is behind the off-by-default `rtrb-xcheck` feature so the bench compiles
//! and runs whether or not `rtrb` resolves:
//!   cargo build --release --benches                          # in-house ring only
//!   cargo bench --bench throughput                           # in-house ring only
//!   cargo bench --bench throughput --features rtrb-xcheck    # + rtrb cross-check
//!
//! `harness = false` (Cargo.toml) → criterion provides `main` via `criterion_main!`.

use cortex_ring::frame::{CortexFrame, CORTEX_CHANNEL_COUNT};
use cortex_ring::spsc::channel;
use criterion::{criterion_group, criterion_main, BatchSize, Criterion, Throughput};

/// Power-of-two ring capacity for the bench (matches the stress test's wrap-heavy 1024).
const CAPACITY: usize = 1024;
/// Frames per measured iteration. A multiple of CAPACITY so each iteration wraps many times.
const BATCH: u64 = 4096;

#[inline]
fn frame(seq: u64) -> CortexFrame {
    CortexFrame {
        ts_ns: seq,
        seq,
        channel_data: [0u16; CORTEX_CHANNEL_COUNT],
    }
}

/// In-house ring: push BATCH frames then drain them, single-threaded. A fresh ring per iteration
/// (via `iter_batched`) keeps each measured run independent and avoids cross-iteration state.
fn bench_cortex_ring(c: &mut Criterion) {
    let mut group = c.benchmark_group("spsc_push_pop");
    group.throughput(Throughput::Elements(BATCH));

    group.bench_function("cortex_ring", |b| {
        b.iter_batched(
            || channel::<CortexFrame>(CAPACITY),
            |(tx, rx)| {
                // Interleave push/pop so the ring stays near-full but never overflows CAPACITY.
                let mut produced: u64 = 0;
                let mut consumed: u64 = 0;
                while consumed < BATCH {
                    while produced < BATCH && tx.push(frame(produced)).is_ok() {
                        produced += 1;
                    }
                    while let Some(f) = rx.pop() {
                        std::hint::black_box(f);
                        consumed += 1;
                    }
                }
            },
            BatchSize::SmallInput,
        );
    });

    group.finish();
}

/// OPTIONAL rtrb cross-check (THREAD-04 reference design). Only compiled with `--features
/// rtrb-xcheck`, so the default bench build does not depend on `rtrb` resolving (D-R3).
#[cfg(feature = "rtrb-xcheck")]
fn bench_rtrb_xcheck(c: &mut Criterion) {
    use rtrb::RingBuffer;

    let mut group = c.benchmark_group("spsc_push_pop");
    group.throughput(Throughput::Elements(BATCH));

    group.bench_function("rtrb_xcheck", |b| {
        b.iter_batched(
            || RingBuffer::<CortexFrame>::new(CAPACITY),
            |(mut tx, mut rx)| {
                let mut produced: u64 = 0;
                let mut consumed: u64 = 0;
                while consumed < BATCH {
                    while produced < BATCH && tx.push(frame(produced)).is_ok() {
                        produced += 1;
                    }
                    while let Ok(f) = rx.pop() {
                        std::hint::black_box(f);
                        consumed += 1;
                    }
                }
            },
            BatchSize::SmallInput,
        );
    });

    group.finish();
}

#[cfg(feature = "rtrb-xcheck")]
criterion_group!(benches, bench_cortex_ring, bench_rtrb_xcheck);
#[cfg(not(feature = "rtrb-xcheck"))]
criterion_group!(benches, bench_cortex_ring);

criterion_main!(benches);
