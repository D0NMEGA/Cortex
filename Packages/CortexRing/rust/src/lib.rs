//! `cortex_ring` — the in-house, loom-verifiable SPSC ring and Swift↔Rust FFI spine for Phase 3.
//!
//! This plan (03-01, Spike A) establishes the crate skeleton: the frozen `#[repr(C)] CortexFrame`
//! (D-R6), the frozen `extern "C"` ABI surface with stub bodies (D-R3/D-R6), the cbindgen header
//! generation (THREAD-06), and the panic-across-FFI guard (threat T-03-01-02). Plan 02 adds the
//! real loom-verified ring (`pub mod loom; pub mod spsc;`) behind exactly these signatures.
//!
//! `improper_ctypes_definitions` is denied crate-wide: any `extern "C"` function whose signature
//! uses a non-FFI-safe type is a hard compile error, so the ABI Swift links cannot silently take
//! on a non-`#[repr(C)]` type.
#![deny(improper_ctypes_definitions)]

pub mod ffi;
pub mod frame;

// Re-export the frozen frame type + channel constant at the crate root so downstream Rust
// (the Plan 02 ring, the stress + loom tests) and cbindgen both resolve them from one place.
pub use frame::{CortexFrame, CORTEX_CHANNEL_COUNT};
