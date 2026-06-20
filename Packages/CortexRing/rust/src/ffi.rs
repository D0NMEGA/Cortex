//! The FROZEN `extern "C"` ABI surface that Swift consumes through the cbindgen header
//! (`import CortexRingFFI`). Plan 01 (Spike A) froze these signatures with STUB bodies; this plan
//! (03-02) fills them with real delegation to the loom-verified [`crate::spsc`] ring. The
//! signatures are **byte-for-byte identical** to Plan 01's contract, so cbindgen regenerates the
//! same `include/cortex_ring.h` and the Plan-01 CI drift gate stays green — only the bodies and the
//! private backing type changed (Plans 02/04 build against exactly these signatures and the
//! `#[repr(C)] CortexFrame`).
//!
//! ## Panic-across-FFI is undefined behaviour (threat T-03-02-05 / T-03-01-02)
//! A Rust `panic!` unwinding across an `extern "C"` frame into Swift/C is UB. Every exported
//! function wraps its body in `std::panic::catch_unwind` and returns a safe default on unwind
//! (push/pop → `false`, create → null, destroy → no-op). Raw-pointer derefs are additionally
//! null-guarded BEFORE any access (T-03-02-03).
//!
//! ## Pointer-safety contract (the C ABI trust boundary)
//! `r` (`*mut CortexSpsc`), `f` (`*const CortexFrame`), and `out` (`*mut CortexFrame`) arrive from
//! the caller (Swift) and are untrusted at this surface. Each is null-checked; `CortexFrame` is a
//! `#[repr(C)]` POD, so it is copied by value across the boundary (no ARC, no ownership transfer of
//! Rust heap — D-R6, Pitfall #8). The opaque `CortexSpsc` handle owns the ring; the caller must
//! treat it as single-producer/single-consumer and must NOT use it after `cortex_spsc_destroy`.

use crate::frame::CortexFrame;
use crate::spsc::{channel, Consumer, Producer};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Opaque SPSC ring handle. The C side only ever holds a `*mut CortexSpsc`; the layout is private
/// to Rust. `_private: [u8; 0]` is the cbindgen idiom for an opaque type — it emits
/// `typedef struct CortexSpsc CortexSpsc;` with no field exposure, so the C/Swift ABI is unchanged
/// from Plan 01 even though the *real* backing ([`RingHandle`]) is now behind it.
#[repr(C)]
pub struct CortexSpsc {
    _private: [u8; 0],
}

/// The real backing the opaque `*mut CortexSpsc` points at: both ends of one [`crate::spsc`] ring.
///
/// `cortex_spsc_create` `Box`es this and hands back `Box::into_raw(..) as *mut CortexSpsc`; the
/// `extern "C"` bodies recover `&RingHandle` from the handle to call `push`/`pop`; `destroy`
/// reconstructs and drops the `Box` (the ring's `Drop` drains any live slots). The caller's
/// single-producer/single-consumer contract is what keeps the shared `&self` `push`/`pop` sound —
/// the C side must call `push` only from its producer thread and `pop` only from its consumer
/// thread (documented on each function).
struct RingHandle {
    producer: Producer<CortexFrame>,
    consumer: Consumer<CortexFrame>,
}

/// Recover a shared reference to the backing handle from an opaque, non-null `*mut CortexSpsc`.
///
/// # Safety
/// `r` must be non-null (callers check first) and must be a pointer returned by
/// `cortex_spsc_create` (i.e. `Box::into_raw(Box::<RingHandle>::new(..)) as *mut CortexSpsc`) that
/// has not yet been passed to `cortex_spsc_destroy`. The returned reference borrows the boxed
/// `RingHandle` for the duration of the call only (never dropped here).
#[inline]
unsafe fn handle<'a>(r: *mut CortexSpsc) -> &'a RingHandle {
    &*(r as *const RingHandle)
}

/// Spike-A smoke: a non-identity transform (`x XOR 0x5A5A5A5A`) so the Swift test proves a real
/// round-trip through the xcframework C ABI rather than a hard-coded Swift constant. Unchanged from
/// Plan 01.
#[no_mangle]
pub extern "C" fn cortex_ping(x: u32) -> u32 {
    // Pure arithmetic cannot unwind, but wrap uniformly to keep the panic-guard idiom consistent
    // across every exported function (defense-in-depth).
    catch_unwind(|| x ^ 0x5A5A_5A5A).unwrap_or(0)
}

/// Allocate an SPSC ring of `capacity` slots and return an opaque handle, or null on failure.
///
/// `capacity` MUST be a non-zero power of two (the ring's `mask = capacity - 1` wrap arithmetic
/// requires it — threat T-03-02-04, integer/capacity guard). A zero or non-power-of-two capacity
/// returns null rather than panicking. Returns null if allocation logic ever unwinds (T-03-02-05).
#[no_mangle]
pub extern "C" fn cortex_spsc_create(capacity: usize) -> *mut CortexSpsc {
    catch_unwind(|| {
        // Bad-capacity guard (T-03-02-04): reject zero and non-power-of-two BEFORE constructing the
        // ring (which would otherwise panic in `channel`). `0.is_power_of_two()` is false, so the
        // single check covers both.
        if !capacity.is_power_of_two() {
            return core::ptr::null_mut();
        }

        let (producer, consumer) = channel::<CortexFrame>(capacity);
        let handle = Box::new(RingHandle { producer, consumer });
        // The real backing is exported behind the opaque CortexSpsc handle; the cast site is
        // identical to Plan 01's stub, so the ABI never changed.
        Box::into_raw(handle) as *mut CortexSpsc
    })
    .unwrap_or(core::ptr::null_mut())
}

/// Push one frame (copied by value from `*f`). Returns `false` when the ring is full, or when
/// `r`/`f` is null. MUST be called only from the caller's single producer thread (SPSC contract).
///
/// `catch_unwind` + `AssertUnwindSafe`: raw pointers are not `UnwindSafe`, and on unwind we return
/// the safe `false` default without observing any broken invariant (T-03-02-05).
// `not_unsafe_ptr_arg_deref`: this is a `#[no_mangle] extern "C"` export whose signature is FROZEN
// by Plan 01 as `pub extern "C"` (NOT `unsafe`) — marking it `unsafe` is unnecessary for the C/Swift
// ABI (C carries no `unsafe`) and would diverge from the frozen contract. The pointer is null-guarded
// before any deref and the SAFETY invariant is documented; the deref is intentional FFI.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
#[no_mangle]
pub extern "C" fn cortex_spsc_push(r: *mut CortexSpsc, f: *const CortexFrame) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        // Null guard BEFORE any deref (T-03-02-03).
        if r.is_null() || f.is_null() {
            return false;
        }
        // SAFETY: `f` is non-null (checked) and, per the ABI contract, points to a caller-owned,
        // properly-aligned, initialized `CortexFrame`. `CortexFrame` is `#[repr(C)] + Copy` POD, so
        // a by-value read copies it across the boundary without taking ownership of caller memory
        // (D-R6, Pitfall #8 — no ARC/heap transfer).
        let frame = unsafe { *f };
        // SAFETY: `r` is non-null (checked) and is a live handle from `cortex_spsc_create`.
        let handle = unsafe { handle(r) };
        handle.producer.push(frame).is_ok()
    }))
    .unwrap_or(false)
}

/// Pop one frame into `*out`. Returns `false` when the ring is empty, or when `r`/`out` is null.
/// MUST be called only from the caller's single consumer thread (SPSC contract).
// `not_unsafe_ptr_arg_deref`: frozen `pub extern "C"` signature (see `cortex_spsc_push`); null-guarded
// intentional FFI deref.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
#[no_mangle]
pub extern "C" fn cortex_spsc_pop(r: *mut CortexSpsc, out: *mut CortexFrame) -> bool {
    catch_unwind(AssertUnwindSafe(|| {
        // Null guard BEFORE any deref (T-03-02-03).
        if r.is_null() || out.is_null() {
            return false;
        }
        // SAFETY: `r` is non-null (checked) and is a live handle from `cortex_spsc_create`.
        let handle = unsafe { handle(r) };
        match handle.consumer.pop() {
            Some(frame) => {
                // SAFETY: `out` is non-null (checked) and, per the ABI contract, points to
                // caller-owned, properly-aligned, writable storage for one `CortexFrame`. The POD
                // copy initializes it fully.
                unsafe { *out = frame };
                true
            }
            None => false,
        }
    }))
    .unwrap_or(false)
}

/// Destroy a ring previously returned by `cortex_spsc_create`. Null-tolerant and unwind-safe.
///
/// Reconstructs the `Box<RingHandle>` and drops it; dropping the handle drops both ends, dropping
/// the last `Arc<Spsc>`, whose `Drop` drains any still-live slots (no double-free / no
/// uninitialized-slot drop — threats T-03-02-01 / T-03-02-02). The caller MUST NOT use `r` after
/// this call (use-after-free — T-03-02-01).
// `not_unsafe_ptr_arg_deref`: frozen `pub extern "C"` signature (see `cortex_spsc_push`); null-tolerant
// intentional FFI deallocation via `Box::from_raw`.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
#[no_mangle]
pub extern "C" fn cortex_spsc_destroy(r: *mut CortexSpsc) {
    let _ = catch_unwind(AssertUnwindSafe(|| {
        if r.is_null() {
            return; // null-tolerant no-op
        }
        // SAFETY: `r` is non-null (checked above) and, per the ABI contract, was produced by
        // `cortex_spsc_create` via `Box::into_raw(Box::<RingHandle>::new(..))` and not yet freed.
        // Reconstructing the same `Box<RingHandle>` and dropping it is the matching deallocation;
        // single-consumer ownership (SPSC) means no aliasing handle is live concurrently, so this
        // frees exactly once.
        unsafe {
            drop(Box::from_raw(r as *mut RingHandle));
        }
    }));
}

// =================================================================================================
// Rust-side C-ABI round-trip proof (the Swift-side proof is Plan 04's integration test). Exercises
// the exported functions exactly as Swift would: create → push N → pop N → assert FIFO → destroy.
// =================================================================================================
#[cfg(all(test, not(loom)))]
mod tests {
    use super::*;
    use crate::frame::CORTEX_CHANNEL_COUNT;

    fn frame(seq: u64) -> CortexFrame {
        CortexFrame {
            ts_ns: seq,
            seq,
            channel_data: [0u16; CORTEX_CHANNEL_COUNT],
        }
    }

    /// `cortex_ping` is the unchanged Spike-A involution smoke (x ^ 0x5A5A5A5A applied twice == x).
    #[test]
    fn ping_involution() {
        assert_eq!(cortex_ping(0), 0x5A5A_5A5A);
        assert_eq!(cortex_ping(cortex_ping(12345)), 12345);
    }

    /// Full C-ABI round-trip against the REAL ring: create(8) → push 8 → pop 8 → FIFO → destroy.
    #[test]
    fn ffi_round_trip_create_push_pop_destroy() {
        let r = cortex_spsc_create(8);
        assert!(!r.is_null(), "create(8) returns a non-null handle");

        // Push 8 frames through the C ABI (seq 0..8). The 8-slot ring accepts all 8.
        for i in 0..8u64 {
            let f = frame(i);
            assert!(
                cortex_spsc_push(r, &f as *const CortexFrame),
                "push {i} into an 8-slot ring via the C ABI"
            );
        }
        // 9th push must fail (ring full).
        let f = frame(99);
        assert!(
            !cortex_spsc_push(r, &f as *const CortexFrame),
            "9th push into a full 8-slot ring returns false"
        );

        // Pop 8 frames; assert strict FIFO + payload integrity via `out`.
        for i in 0..8u64 {
            let mut out = frame(0);
            assert!(
                cortex_spsc_pop(r, &mut out as *mut CortexFrame),
                "pop {i} via the C ABI"
            );
            assert_eq!(out.seq, i, "FIFO order through the C ABI");
            assert_eq!(out.ts_ns, i, "frame payload integrity through the C ABI");
        }
        // Ring now empty → pop returns false and leaves `out` untouched.
        let mut out = frame(0);
        assert!(
            !cortex_spsc_pop(r, &mut out as *mut CortexFrame),
            "pop on an empty ring returns false"
        );

        // Destroy releases the ring (and drains any live slots — none here).
        cortex_spsc_destroy(r);
        // Destroy is null-tolerant (double-destroy of a *null* is a no-op; re-destroying `r` itself
        // would be a use-after-free per the contract, so we only assert the null no-op).
        cortex_spsc_destroy(core::ptr::null_mut());
    }

    /// Bad-capacity guard (T-03-02-04): zero and non-power-of-two return null, no panic, no leak.
    #[test]
    fn create_rejects_bad_capacity() {
        assert!(cortex_spsc_create(0).is_null(), "capacity 0 → null");
        assert!(
            cortex_spsc_create(3).is_null(),
            "non-power-of-two capacity → null"
        );
        assert!(
            cortex_spsc_create(6).is_null(),
            "non-power-of-two capacity → null"
        );
        // A valid power-of-two still succeeds (and is cleaned up).
        let r = cortex_spsc_create(2);
        assert!(!r.is_null(), "capacity 2 (power of two) → non-null");
        cortex_spsc_destroy(r);
    }

    /// Null-pointer guards (T-03-02-03): push/pop with any null arg return false, never deref.
    #[test]
    fn push_pop_reject_null_pointers() {
        let f = frame(1);
        let mut out = frame(0);

        // Null ring handle.
        assert!(!cortex_spsc_push(
            core::ptr::null_mut(),
            &f as *const CortexFrame
        ));
        assert!(!cortex_spsc_pop(
            core::ptr::null_mut(),
            &mut out as *mut CortexFrame
        ));

        // Null frame / out pointer against a real ring.
        let r = cortex_spsc_create(4);
        assert!(!r.is_null());
        assert!(
            !cortex_spsc_push(r, core::ptr::null()),
            "null frame → false"
        );
        assert!(
            !cortex_spsc_pop(r, core::ptr::null_mut()),
            "null out → false"
        );
        cortex_spsc_destroy(r);
    }
}
