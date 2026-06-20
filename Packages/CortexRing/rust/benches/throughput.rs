//! Throughput benchmark placeholder (pre-wired for Plan 02, RESEARCH §2/D-R3).
//!
//! Plan 02 fills this with a criterion benchmark of the in-house SPSC ring's push/pop throughput
//! and the optional `rtrb` cross-check (the only place `rtrb` appears — never a production dep,
//! never the loom target). For Spike A (this plan) it is an empty `main` so the `[[bench]]` target
//! declared in `Cargo.toml` resolves and `cargo build`/`cargo test` succeed against a valid
//! manifest. `harness = false` (set in Cargo.toml) means this is a plain executable, not a
//! libtest harness, so an empty `main` is a valid no-op bench.

fn main() {
    // Intentionally empty: the real throughput + rtrb-cross-check benchmark lands in Plan 02.
}
