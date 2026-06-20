//! The std↔loom cfg-shim — the single import site the SPSC ring routes its atomics, cells, and
//! (under test) its `Arc`/`thread` through (D-R3/D-R5, RESEARCH §1).
//!
//! This is the canonical `thingbuf`/`crossbeam` pattern. The ring NEVER names `core::sync::atomic`,
//! `core::cell::UnsafeCell`, or `std::sync::Arc` directly — it uses `crate::loom::atomic::*`,
//! `crate::loom::cell::UnsafeCell`, and `crate::loom::sync::Arc`. That single indirection is what
//! lets a `--cfg loom` build swap the real concurrency primitives for loom's instrumented ones so
//! the model checker can observe every interleaving (the loom permutation test, Task 2 / SC#3a),
//! while a production / non-`loom` build compiles down to the zero-overhead `core`/`std` types.
//!
//! ## Ordering discipline (D-R4, RESEARCH §6 Pitfall #5)
//! The ring uses Release-publish / Acquire-observe ONLY. `SeqCst` is deliberately never used:
//! loom models `SeqCst` as `AcqRel` (it cannot soundly verify the global `SeqCst` total order), so
//! relying on it would make the loom proof unsound. `Ordering` is re-exported from `core` in BOTH
//! configurations — only the atomic *types* differ between std and loom.

// ----- loom build: instrumented atomics + cells + sync + thread -------------------------------
// `RUSTFLAGS="--cfg loom" cargo test --profile loom --test loom_spsc` selects this arm. loom's
// `AtomicUsize`/`UnsafeCell`/`Arc`/`thread` carry the model-checker bookkeeping that records and
// permutes every memory operation and thread interleaving.
//
// `cell`/`hint`/`thread` are part of the shim's deliberate re-export surface (the loom test crate
// names `loom::thread::spawn`/`yield_now` through it), but the *library* compilation unit only
// consumes `sync::Arc` + `atomic` + `cell_compat`, so allow the otherwise-"unused" re-exports here
// (symmetric to the non-loom arm below).
#[cfg(loom)]
#[allow(unused_imports)]
pub(crate) use loom::{cell, hint, sync, thread};

#[cfg(loom)]
pub(crate) mod atomic {
    //! `loom::sync::atomic` types + the real `core` `Ordering` (loom does NOT define its own
    //! `Ordering`; it reuses `core::sync::atomic::Ordering`).
    pub use core::sync::atomic::Ordering;
    pub use loom::sync::atomic::*;
}

// ----- production / non-loom build: zero-overhead core/std primitives -------------------------
// The default `cargo build`/`cargo test` path. `cell`/`hint` come from `core`; `sync` (for `Arc`)
// and `thread` (used directly by the std-atomic stress test) come from `std`.
//
// `cell`/`hint`/`thread` are part of the shim's deliberate re-export surface (mirroring the loom
// arm so the ring + tests name `crate::loom::{cell,hint,thread}` identically in both builds), but
// the production *library* itself only consumes `cell_compat` + `atomic` + `sync::Arc` — so allow
// the otherwise-"unused" re-exports here rather than dropping a surface the loom arm provides.
#[cfg(not(loom))]
#[allow(unused_imports)]
pub(crate) use core::{cell, hint};
#[cfg(not(loom))]
#[allow(unused_imports)]
pub(crate) use std::{sync, thread};

#[cfg(not(loom))]
pub(crate) mod atomic {
    //! `core::sync::atomic` — the production atomics (and `Ordering`).
    pub use core::sync::atomic::*;
}

// ----- uniform UnsafeCell with the loom-style `.with`/`.with_mut` closure API -----------------
// loom's `cell::UnsafeCell` does NOT expose `.get()`; it tracks slot access through closures
// (`with`/`with_mut`) so the model checker can detect data races on the slot memory — NOT just on
// the atomic indices (RESEARCH §1, the reason an in-house ring is required, §2/D-R3).
// `core::cell::UnsafeCell` has no such API, so we expose ONE `cell::CortexCell<T>` whose interface
// is identical in both builds. The ring stores `cell::CortexCell<MaybeUninit<T>>` and always
// touches slots via `.with`/`.with_mut`, so the loom build's data-race instrumentation engages and
// the production build is a plain pointer dereference (zero overhead).
pub(crate) mod cell_compat {
    /// Production wrapper over `core::cell::UnsafeCell` exposing loom's `with`/`with_mut` closure
    /// API so the SPSC ring is written once and compiles in both configurations.
    #[cfg(not(loom))]
    #[derive(Debug)]
    pub(crate) struct CortexCell<T>(core::cell::UnsafeCell<T>);

    #[cfg(not(loom))]
    impl<T> CortexCell<T> {
        #[inline]
        pub(crate) fn new(value: T) -> Self {
            Self(core::cell::UnsafeCell::new(value))
        }

        /// Immutable raw-pointer access. SAFETY of the closure body is the caller's (the SPSC
        /// single-producer/single-consumer invariant); this wrapper only forwards the pointer.
        #[inline]
        pub(crate) fn with<R>(&self, f: impl FnOnce(*const T) -> R) -> R {
            f(self.0.get())
        }

        /// Mutable raw-pointer access. Same SAFETY contract as `with`.
        #[inline]
        pub(crate) fn with_mut<R>(&self, f: impl FnOnce(*mut T) -> R) -> R {
            f(self.0.get())
        }
    }

    /// loom build: delegate to `loom::cell::UnsafeCell`, whose `with`/`with_mut` carry the
    /// data-race instrumentation the model checker reads.
    #[cfg(loom)]
    #[derive(Debug)]
    pub(crate) struct CortexCell<T>(loom::cell::UnsafeCell<T>);

    #[cfg(loom)]
    impl<T> CortexCell<T> {
        #[inline]
        pub(crate) fn new(value: T) -> Self {
            Self(loom::cell::UnsafeCell::new(value))
        }

        #[inline]
        pub(crate) fn with<R>(&self, f: impl FnOnce(*const T) -> R) -> R {
            self.0.with(f)
        }

        #[inline]
        pub(crate) fn with_mut<R>(&self, f: impl FnOnce(*mut T) -> R) -> R {
            self.0.with_mut(f)
        }
    }
}
