//! The FROZEN `extern "C"` ABI surface that Swift consumes through the cbindgen header
//! (`import CortexRingFFI`). Signatures are frozen in this plan (Spike A); bodies are stubs that
//! Plan 02 replaces with the real loom-verified SPSC algorithm — Plans 02 and 04 build against
//! exactly these signatures and the `#[repr(C)] CortexFrame`.
//!
//! ## Panic-across-FFI is undefined behaviour (threat T-03-01-02)
//! A Rust `panic!` unwinding across an `extern "C"` frame into Swift/C is UB. Every exported
//! function that runs Rust logic and/or dereferences a raw pointer wraps its body in
//! `std::panic::catch_unwind` and returns a safe default on unwind (push/pop → `false`,
//! create → null). Plan 02 hardens the *real* bodies the same way (plus null/bounds checks that
//! live with the algorithm). `cortex_ping` is pure arithmetic but is wrapped too, to establish
//! the idiom uniformly.

use crate::frame::CortexFrame;
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Opaque SPSC ring handle. The C side only ever holds a `*mut CortexSpsc`; the layout is private
/// to Rust (Plan 02 fills it with the real ring). `_private: [u8; 0]` is the cbindgen idiom for an
/// opaque type — it emits `typedef struct CortexSpsc CortexSpsc;` with no field exposure.
#[repr(C)]
pub struct CortexSpsc {
    _private: [u8; 0],
}

/// Placeholder ring backing the stub handle until Plan 02 lands the real algorithm.
/// Heap-allocated so `create`/`destroy` exercise the real `Box::into_raw`/`from_raw` lifecycle
/// the production ring will use.
struct StubRing {
    _capacity: usize,
}

/// Spike-A smoke: a non-identity transform (`x XOR 0x5A5A5A5A`) so the Swift test proves a real
/// round-trip through the xcframework C ABI rather than a hard-coded Swift constant.
#[no_mangle]
pub extern "C" fn cortex_ping(x: u32) -> u32 {
    // Pure arithmetic cannot unwind, but wrap uniformly to keep the panic-guard idiom consistent
    // across every exported function (defense-in-depth; Plan 02 fills bodies that genuinely can).
    catch_unwind(|| x ^ 0x5A5A_5A5A).unwrap_or(0)
}

/// Allocate an SPSC ring of `capacity` slots (the real algorithm in Plan 02 requires a power of
/// two). STUB: allocates the placeholder backing and returns its raw pointer; returns null if the
/// allocation logic ever panics (threat T-03-01-02).
#[no_mangle]
pub extern "C" fn cortex_spsc_create(capacity: usize) -> *mut CortexSpsc {
    catch_unwind(|| {
        let boxed = Box::new(StubRing {
            _capacity: capacity,
        });
        // The placeholder is exported behind the opaque CortexSpsc handle. Plan 02 swaps StubRing
        // for the real ring; the cast site stays identical so the ABI never changes.
        Box::into_raw(boxed) as *mut CortexSpsc
    })
    .unwrap_or(core::ptr::null_mut())
}

/// Push one frame. Returns `false` when the ring is full. STUB: always returns `false` (the real
/// publish lands in Plan 02). Wrapped in `catch_unwind` because it dereferences caller-supplied
/// raw pointers (`AssertUnwindSafe` — raw pointers are not `UnwindSafe`, and on unwind we return
/// the safe `false` default without observing any broken invariant).
#[no_mangle]
pub extern "C" fn cortex_spsc_push(r: *mut CortexSpsc, f: *const CortexFrame) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        let _ = (r, f);
        false
    }))
    .unwrap_or(false)
}

/// Pop one frame into `out`. Returns `false` when the ring is empty. STUB: always returns `false`
/// (the real consume lands in Plan 02). Same `catch_unwind` rationale as `push`.
#[no_mangle]
pub extern "C" fn cortex_spsc_pop(r: *mut CortexSpsc, out: *mut CortexFrame) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        let _ = (r, out);
        false
    }))
    .unwrap_or(false)
}

/// Destroy a ring previously returned by `cortex_spsc_create`. Reconstructs the box and drops it.
/// Null-safe and unwind-safe: a null handle is a no-op, and a panic during drop is swallowed so it
/// never crosses the C frame (threat T-03-01-02).
#[no_mangle]
pub extern "C" fn cortex_spsc_destroy(r: *mut CortexSpsc) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if r.is_null() {
            return;
        }
        // Reconstruct the StubRing box from the opaque handle and let it drop.
        // SAFETY: `r` is non-null (checked above) and, per the ABI contract, was produced by
        // `cortex_spsc_create` via `Box::into_raw(Box::<StubRing>::new(..))` and not yet freed.
        // Reconstructing the same `Box<StubRing>` and dropping it is the matching deallocation;
        // single-consumer ownership (SPSC) means no aliasing handle is live concurrently.
        unsafe {
            drop(Box::from_raw(r as *mut StubRing));
        }
    }));
}
