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
// The std↔loom cfg-shim (D-R3/D-R5) and the in-house SPSC ring it powers. The ring's atomics/cells
// route through `crate::loom` so the SAME source is the production ring (driven by `ffi`), the body
// of the 1M-frame std-atomic stress test, and the body of the tiny `--cfg loom` permutation test.
pub mod loom;
pub mod spsc;

// Re-export the frozen frame type + channel constant at the crate root so downstream Rust
// (the Plan 02 ring, the stress + loom tests) and cbindgen both resolve them from one place.
pub use frame::{CortexFrame, CORTEX_CHANNEL_COUNT};
