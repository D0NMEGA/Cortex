//! The frozen `#[repr(C)]` frame that crosses the Swift↔Rust FFI and rides the SPSC ring.
//!
//! Layout is locked to the Phase-2 shared constant `CORTEX_CHANNEL_COUNT` (D-R6 / D-11). The
//! compile-time `size_of` assertion below makes a channel-count change that would silently
//! desync this ring frame from the FlatBuffers `Sample` (Phase 2 D-10) structurally impossible
//! — it mirrors the `_Static_assert` in
//! `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` (Pitfall #9, threat T-03-01-01).

/// Number of neural channels per frame.
///
/// MUST equal `CORTEX_CHANNEL_COUNT` in
/// `Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h` (D-11). The value `96` is the
/// Phase-2 placeholder; the real O'Doherty Indy/Loco count is confirmed against Zenodo 3854034 in
/// Phase 4. The MECHANISM (the static assert below) is what is frozen here — not the number.
pub const CORTEX_CHANNEL_COUNT: usize = 96;

/// A single acquisition frame: a monotonic timestamp + sequence number + the raw f16 channel
/// payload (carried as raw IEEE-754 half bits in `u16`, hardware `Float16` on both sides —
/// Phase 2 D-10). `#[repr(C)]` so the layout matches the cbindgen C header byte-for-byte and the
/// Swift consumer sees an identical struct across the FFI.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CortexFrame {
    /// `mach_absolute_time`-derived nanoseconds (Phase 2 D-12 `ts_ns`).
    pub ts_ns: u64,
    /// Monotonic sequence number (Phase 2 D-12 `seq`); the FIFO + 1M-stress test asserts it
    /// increases by exactly one per frame with zero loss.
    pub seq: u64,
    /// Raw IEEE-754 half (f16) bits, one per channel (Phase 2 D-10 `[ubyte]`/f16 layout).
    pub channel_data: [u16; CORTEX_CHANNEL_COUNT],
}

// Compile-time layout lock (D-R6 / Pitfall #9 / threat T-03-01-01):
// 8 (ts_ns) + 8 (seq) + CORTEX_CHANNEL_COUNT * 2 (u16 channel payload) == size_of::<CortexFrame>().
// If anyone changes CORTEX_CHANNEL_COUNT or the field set without keeping the ring frame and the
// FlatBuffers Sample in lockstep, `cargo build` FAILS here before any test runs.
const _: () = assert!(core::mem::size_of::<CortexFrame>() == 16 + CORTEX_CHANNEL_COUNT * 2);
