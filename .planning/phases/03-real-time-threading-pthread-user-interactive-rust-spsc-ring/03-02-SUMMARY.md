---
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
plan: 02
subsystem: infra
tags: [rust, spsc, lock-free, loom, atomics, acquire-release, cache-line, ffi, cbindgen, criterion, rtrb]

# Dependency graph
requires:
  - phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring (Plan 01)
    provides: "the cortex_ring crate (staticlib+rlib), the frozen #[repr(C)] CortexFrame, the frozen extern \"C\" ABI (5 fns, stub bodies + catch_unwind), the crate::loom cfg-swap point ([target.'cfg(loom)'] loom 0.7 + [profile.loom]), the vendored cbindgen header + CI drift gate, and the loom/stress/bench CI gates"
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
    provides: "the Release/Acquire ordering discipline (ShmRing T-02-02-01), the Sample{ts_ns,seq,channel_data} f16 layout the CortexFrame mirrors (D-10/D-12)"
provides:
  - "In-house lock-free bounded-power-of-two SPSC ring (src/spsc.rs): Producer/Consumer split, 128-byte cache-line-padded head/tail, Release-publish / Acquire-observe ordering (no SeqCst), drain-on-Drop"
  - "std<->loom cfg-shim (src/loom.rs): one import site routing atomics + a uniform CortexCell (with/with_mut) + sync::Arc + thread through core/std (production) or loom (--cfg loom) — zero algorithm duplication across production/stress/loom"
  - "SC#3a loom permutation test (tests/loom_spsc.rs): cap-2 ring, exhaustive interleavings, FIFO+no-loss, with a --cfg loom_negative_control Relaxed-mutant that loom catches"
  - "SC#3b 1M-frame std-atomic 2-thread strict-FIFO zero-loss stress test (tests/stress_fifo.rs)"
  - "Real extern \"C\" ABI bodies (src/ffi.rs): create/push/pop/destroy delegate to the ring with null-guards, power-of-two capacity guard, catch_unwind, drain-on-drop — frozen signatures unchanged"
  - "criterion throughput bench + guarded rtrb cross-check (benches/throughput.rs, rtrb-xcheck feature)"
affects: [03-03-pthread-hot-path, 03-04-swift-integration, 06-renderer]

# Tech tracking
tech-stack:
  added:
    - "(no new crates — loom 0.7.2 / criterion 0.5 / rtrb 0.3 were pre-locked in Plan 01; Cargo.lock unchanged)"
  patterns:
    - "thingbuf-style std<->loom cfg-shim with a uniform CortexCell<T> (with/with_mut closure API) so one ring source is model-checkable under --cfg loom and zero-overhead in production"
    - "rtrb-style bounded-pow2 SPSC: free-running monotonic head/tail, & mask wrap, len = tail.wrapping_sub(head); 128-byte CachePad on each index (Apple Silicon false-sharing avoidance)"
    - "D-R5 two-test split: a TINY exhaustive loom test for ordering/data-race + a SEPARATE 1M std-atomic test for throughput/no-loss; 1M is NEVER run under loom (Pitfall #4 state-space explosion)"
    - "cfg-gated ordering mutant (cfg(loom_negative_control)) as a one-toggle negative control that proves the loom proof bites, auto-reverting when the flag is dropped"
    - "FFI bodies filled behind byte-identical frozen signatures so the vendored cbindgen header stays in lockstep (drift gate green); #[allow(clippy::not_unsafe_ptr_arg_deref)] keeps the pub extern \"C\" surface unchanged"

key-files:
  created:
    - "Packages/CortexRing/rust/src/loom.rs — std<->loom cfg-shim (atomic/cell_compat::CortexCell/sync/thread); one import site the ring uses"
    - "Packages/CortexRing/rust/src/spsc.rs — the bounded-pow2 SPSC ring + 7 std-atomic unit tests"
    - "Packages/CortexRing/rust/tests/loom_spsc.rs — SC#3a loom permutation test (#![cfg(loom)])"
    - "Packages/CortexRing/rust/tests/stress_fifo.rs — SC#3b 1M-frame std-atomic FIFO/no-loss test (#![cfg(not(loom))])"
  modified:
    - "Packages/CortexRing/rust/src/ffi.rs — stub bodies replaced with real ring delegation (signatures frozen)"
    - "Packages/CortexRing/rust/src/lib.rs — pub mod loom; pub mod spsc;"
    - "Packages/CortexRing/rust/benches/throughput.rs — criterion bench + guarded rtrb cross-check (replaces the Plan-01 placeholder)"
    - "Packages/CortexRing/rust/Cargo.toml — [lints.rust] check-cfg(loom, loom_negative_control); [features] rtrb-xcheck"
    - "Packages/CortexRing/rust/include/cortex_ring.h — regenerated (doc-comments only; C declarations byte-identical)"

key-decisions:
  - "Uniform CortexCell<T> wrapper in the loom shim (with/with_mut), because core::cell::UnsafeCell has no .with API and loom::cell::UnsafeCell has no .get — one wrapper lets the ring touch slots identically in both builds so loom's data-race instrumentation engages on slot memory, not just the indices"
  - "Free-running monotonic head/tail with len = tail.wrapping_sub(head) and & mask wrap (rtrb scheme) rather than wrap-the-index-itself — keeps full/empty unambiguous on a power-of-two ring and is naturally usize-wraparound-safe"
  - "loom Arc via crate::loom::sync::Arc so the --cfg loom build uses loom::sync::Arc (loom tracks the Arc too); production is std::sync::Arc"
  - "Negative controls are cfg-gated (loom_negative_control) / one-line edits, run-and-revert during execution — no permanent #[should_panic] test that would slow every CI run; the biting was proven live in this session"
  - "Regenerated header committed (doc-comments propagated by cbindgen) — the drift gate's true invariant is committed==regenerated, verified idempotent against the brew cbindgen 0.29.4 CLI; the C ABI signatures are byte-identical to Plan 01"

patterns-established:
  - "One loom-verified ring, three roles (production FFI + 1M stress + tiny loom) via crate::loom — the resolution of the rtrb-vs-loom contradiction (D-R3)"
  - "128-byte (NOT 64) cache-line padding on Apple Silicon, compile-time asserted, negative-controlled"
  - "Release-publish / Acquire-observe ONLY; SeqCst forbidden (loom-unsound) and literally absent from the ring source"

requirements-completed: [THREAD-04, THREAD-05, THREAD-07]

# Metrics
duration: 13min
completed: 2026-06-20
---

# Phase 3 Plan 02: In-House Loom-Verified SPSC Ring Summary

**An in-house lock-free bounded SPSC ring (rtrb-style: Producer/Consumer split, 128-byte-padded head/tail, Release-publish/Acquire-observe, no SeqCst) whose atomics and slot cells route through a `crate::loom` cfg-shim, so the SAME source is the production `extern "C"` ring, a 1M-frame std-atomic strict-FIFO stress test (SC#3b), and a tiny exhaustive loom permutation test (SC#3a) with a biting Relaxed-mutant negative control — resolving the rtrb-vs-loom contradiction (D-R3/D-R5) and leaving the frozen cbindgen ABI signatures unchanged.**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-06-20T23:11:52Z
- **Completed:** 2026-06-20T23:25:xxZ
- **Tasks:** 3 (all complete)
- **Files modified/created:** 9 (4 created, 5 modified)

## Accomplishments

- **The heart of Phase 3 — one loom-verified SPSC ring serving three roles with zero algorithm duplication (D-R3/D-R5).** `src/spsc.rs` is a bounded power-of-two ring mirroring `rtrb`'s wait-free algorithm: a `Producer`/`Consumer` split (neither `Clone` → MPMC misuse is a *type error*), free-running monotonic `head`/`tail` with `& mask` wrap, `len = tail.wrapping_sub(head)`. Its atomics (`crate::loom::atomic::AtomicUsize`), slot cells (`crate::loom::cell_compat::CortexCell<MaybeUninit<T>>`), and `Arc` route through the `crate::loom` cfg-shim, so production uses `core`/`std` and `--cfg loom` uses loom's instrumented primitives.
- **Memory ordering proven sound (THREAD-05, THREAD-07, SC#3a).** Producer: `tail.load(Relaxed)` own index, `head.load(Acquire)` observe consumer, write slot, `tail.store(Release)` publish. Consumer: symmetric. **No `SeqCst` anywhere** (loom-unsound; literally absent from `src/spsc.rs`). The loom permutation test (`tests/loom_spsc.rs`, cap-2 ring, 3 pushes forcing a wrap) passes exhaustively in **0.12 s** — far under the 120 s VALIDATION budget (Pitfall #4 respected). Its `--cfg loom_negative_control` mutant (publish `Release`→`Relaxed`) makes loom FAIL with *"Causality violation: Concurrent read and write accesses"* — proving the proof bites.
- **128-byte cache-line padding (THREAD-05, SC#3c).** `#[repr(align(128))] struct CachePad` on `head`/`tail` (Apple Silicon = 128 B, NOT 64) with a compile-time `const _: () = assert!(align_of::<CachePad>() == 128)`. Negative control proven: `align(64)` makes the const assert FAIL at compile time (`error[E0080]`), then restored.
- **1M-frame strict-FIFO zero-loss throughput (THREAD-04, SC#3b).** `tests/stress_fifo.rs` (2 std threads, 1,024-slot ring, busy-poll) pushes/pops 1,000,000 frames asserting strict-monotonic `seq` 0..1e6 and count == 1e6 — passes in **~0.10 s**. Gated `#![cfg(not(loom))]` so it is NEVER run under loom. Negative control proven: off-by-one producer `seq` fails the FIFO assert at position 0, then reverted.
- **The frozen `extern "C"` ABI now drives the real ring (THREAD-04/06).** `src/ffi.rs` create/push/pop/destroy delegate to `crate::spsc` with full pointer safety: power-of-two/zero capacity → null (T-03-02-04), null-guards on every raw pointer before deref (T-03-02-03), `catch_unwind` retained (T-03-02-05), `Box`+drain-on-`Drop` (T-03-02-01/02). The committed cbindgen header's **C declarations are byte-identical** to Plan 01 — the drift gate stays green.
- **rtrb cross-check confirms rtrb-quality (D-R3).** criterion: in-house ring **81.7 Melem/s** vs `rtrb` **84.9 Melem/s** (single-threaded push+pop of 4096 frames on M-series) — within ~4%, same envelope. Cross-check is behind the off-by-default `rtrb-xcheck` feature so `--benches` builds whether or not `rtrb` resolves.

## Task Commits

Each task was committed atomically (TDD: tests-first within each task; `--no-verify` per parallel-executor protocol):

1. **Task 1: SPSC ring + loom shim — 128B-padded head/tail, Release/Acquire, Producer/Consumer split** — `89c37d3` (feat)
2. **Task 2: loom permutation test (SC#3a) + 1M-frame stress test (SC#3b) + criterion bench — D-R5 two-test split** — `8984936` (test)
3. **Task 3: wire the frozen extern "C" ABI to the real ring — create/push/pop/destroy + pointer safety** — `b8f8c1c` (feat)

**Plan metadata:** (final docs commit — this SUMMARY)

## Memory orderings used (cite from Plans 03/04)

```text
Producer::push:  tail.load(Relaxed)   // own index reload (sole writer of tail)
                 head.load(Acquire)   // observe consumer's head.store(Release) → freed slot safe to reuse
                 slot.write(val)      // CortexCell::with_mut — loom checks the data race here
                 tail.store(Release)  // publish: slot write happens-before consumer's tail.load(Acquire)

Consumer::pop:   head.load(Relaxed)   // own index reload (sole writer of head)
                 tail.load(Acquire)   // observe producer's tail.store(Release) → published slot fully written
                 slot.assume_init_read()
                 head.store(Release)  // publish freed slot before producer's head.load(Acquire) reuses it
```
No `SeqCst` (D-R4, Pitfall #5 — loom models it as AcqRel and cannot soundly verify it). `CortexFrame` = 208 bytes (8 `ts_ns` + 8 `seq` + 96×2 `channel_data`).

## Files Created/Modified

- `Packages/CortexRing/rust/src/loom.rs` (created, 118 lines) — the std↔loom cfg-shim: `atomic` (core vs loom), `cell_compat::CortexCell<T>` (uniform `with`/`with_mut` over `core::cell::UnsafeCell` / `loom::cell::UnsafeCell`), `sync` (Arc), `thread`, `hint`.
- `Packages/CortexRing/rust/src/spsc.rs` (created, 393 lines) — `Spsc<T>`, `Producer<T>`, `Consumer<T>`, `channel<T>(pow2)`, `CachePad`, `Drop` drain, 7 std-atomic unit tests.
- `Packages/CortexRing/rust/tests/loom_spsc.rs` (created, 88 lines) — SC#3a, `#![cfg(loom)]`, `loom::model`.
- `Packages/CortexRing/rust/tests/stress_fifo.rs` (created, 95 lines) — SC#3b, `#![cfg(not(loom))]`, 1M frames.
- `Packages/CortexRing/rust/src/ffi.rs` (modified, 293 lines) — real `RingHandle` backing + the 5 frozen `extern "C"` bodies + 4 round-trip tests.
- `Packages/CortexRing/rust/src/lib.rs` (modified) — `pub mod loom; pub mod spsc;`.
- `Packages/CortexRing/rust/benches/throughput.rs` (modified, 102 lines) — criterion bench + `rtrb-xcheck`-gated cross-check.
- `Packages/CortexRing/rust/Cargo.toml` (modified) — `[lints.rust]` check-cfg + `[features] rtrb-xcheck`.
- `Packages/CortexRing/rust/include/cortex_ring.h` (modified) — regenerated; C declarations byte-identical.

## Decisions Made

- **Uniform `CortexCell<T>` (`with`/`with_mut`) in the shim.** `core::cell::UnsafeCell` has no `.with` and `loom::cell::UnsafeCell` has no `.get`; one wrapper presenting loom's closure API in both builds lets the ring touch slots identically and makes loom's **slot-memory** data-race instrumentation engage (the reason an in-house ring is required, §2/D-R3).
- **Free-running monotonic counters + `& mask`** (not wrap-the-index): unambiguous full/empty on a pow2 ring, `usize`-wraparound-safe via `wrapping_sub`/`wrapping_add`.
- **`crate::loom::sync::Arc`** so the loom build shares the ring via `loom::sync::Arc` (loom tracks it); production is `std::sync::Arc`.
- **Negative controls are run-and-revert** (cfg-gated for loom, one-line edit for stress) — proven live this session, not left as permanent `#[should_panic]` CI weight.
- **Committed the regenerated header.** cbindgen propagates the improved `///` docs into the header; the C signatures are byte-identical (verified) and the regen is idempotent vs the brew `cbindgen 0.29.4` CLI, so the CI drift gate (`cargo build` + `git diff --exit-code`) PASSES.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Declared `--cfg loom` / `--cfg loom_negative_control` to Rust 1.96's `check-cfg`**
- **Found during:** Task 1 (first `cargo test`)
- **Issue:** Rust 1.80+ `unexpected_cfgs` lint emitted `unexpected cfg condition name: loom` for every `#[cfg(loom)]`/`#[cfg(not(loom))]` (10 warnings) — the shim keys entirely off `--cfg loom`, so this would spam every production build.
- **Fix:** Added `[lints.rust] unexpected_cfgs = { level = "warn", check-cfg = ['cfg(loom)', 'cfg(loom_negative_control)'] }` to `Cargo.toml` (the canonical loom/thingbuf approach).
- **Files modified:** Packages/CortexRing/rust/Cargo.toml
- **Verification:** `cargo build`/`cargo clippy -- -D warnings` clean; loom build clean.
- **Committed in:** `89c37d3` (Task 1)

**2. [Rule 1 - Bug] Avoided `Result::unwrap()` on `push` in tests (CortexFrame is not `Debug`)**
- **Found during:** Task 1 (first compile of the unit tests)
- **Issue:** `push` returns `Result<(), T>`; `.unwrap()`/`.unwrap_err()` require `T: Debug`, but the frozen `CortexFrame` deliberately does NOT derive `Debug` (adding it could perturb the cbindgen output / was out of scope). Two compile errors (E0277).
- **Fix:** Used `assert!(... .is_ok())` / `.unwrap_err().seq` only where the payload field is read, and asserted on field values rather than the whole frame. Did NOT touch the frozen `CortexFrame`.
- **Files modified:** Packages/CortexRing/rust/src/spsc.rs (tests only)
- **Verification:** 7 unit tests compile and pass; header unchanged.
- **Committed in:** `89c37d3` (Task 1)

**3. [Rule 3 - Blocking] `#[allow(clippy::not_unsafe_ptr_arg_deref)]` on the 3 deref `extern "C"` exports**
- **Found during:** Task 3 (clippy `-D warnings` on the real ffi bodies)
- **Issue:** Once the bodies actually dereference the caller pointers, clippy's `not_unsafe_ptr_arg_deref` (deny-by-default) demands the functions be `unsafe`. But Plan 01 froze them as `pub extern "C"` (NOT `unsafe`); changing the Rust signature is unnecessary for the C/Swift ABI (C has no `unsafe`) and would diverge from the frozen contract.
- **Fix:** `#[allow(clippy::not_unsafe_ptr_arg_deref)]` on push/pop/destroy, with a comment citing the frozen signature + the null-guards/SAFETY notes. The attribute does not appear in the generated header.
- **Files modified:** Packages/CortexRing/rust/src/ffi.rs
- **Verification:** `cargo clippy --all-targets -- -D warnings` exits 0; C declarations byte-identical to Plan 01.
- **Committed in:** `b8f8c1c` (Task 3)

**4. [Rule 3 - Blocking] Committed the regenerated cbindgen header (doc-comments propagated)**
- **Found during:** Task 3 (header drift check after `cargo build`)
- **Issue:** I rewrote the `///` doc-comments on the `extern "C"` functions to describe the real behavior; cbindgen propagates `///` → `/** */`, so `git diff --exit-code include/cortex_ring.h` reported a (comment-only) change. Leaving it uncommitted would make CI's `cargo build` + `git diff --exit-code` FAIL (committed header ≠ regenerated).
- **Fix:** Committed the regenerated header. Proved the **C declarations are byte-identical** to Plan 01 (signatures/structs/`#define` diff-clean — only doc prose differs) and the regen is **idempotent** vs the brew `cbindgen 0.29.4` CLI the gate uses. The ABI is frozen; the gate passes post-commit.
- **Files modified:** Packages/CortexRing/rust/include/cortex_ring.h
- **Verification:** `diff` of stripped C declarations old-vs-new is empty; `cbindgen` CLI regen == committed header.
- **Committed in:** `b8f8c1c` (Task 3)

---

**Total deviations:** 4 auto-fixed (3 blocking, 1 bug). **Impact:** All necessary for a clean, gate-passing crate; none changed the frozen ABI or the ring algorithm. No scope creep — every change stays within `Packages/CortexRing/rust/**` (the assigned lane; Package.swift/project.yml/hotpath-policy.sh untouched for the parallel 03-03 agent).

## Issues Encountered

- **`cargo fmt` not on PATH** (Homebrew rustup shim — same as noted in 03-01-SUMMARY). The `rustfmt` *component* IS installed; ran it directly via `$(rustc --print sysroot)/bin/rustfmt --check` and applied canonical formatting to all new/modified files (ALL RUSTFMT CLEAN). The Rust CI gates use `cargo test`/`cargo build`, not rustfmt, so this is non-blocking.
- **Context7 has no Rust `loom`/`rtrb` coverage** (confirmed — `resolve-library-id "loom"` returns the Gradle/Minecraft plugin + a Python framework + LangGraph, exactly as RESEARCH.md §0 documented). Followed the canonical loom README + the thingbuf shim pattern captured verbatim in RESEARCH.md §1 and the plan's `<interfaces>`.

## Threat Surface

No new attack surface beyond the plan's `<threat_model>`. The `extern "C"` surface is the SAME 5 frozen functions from Plan 01 (no new `#[no_mangle]` exports); no network endpoints, auth paths, file access, or schema. All six STRIDE mitigations are implemented and tied to tests:
- **T-03-02-01** (use-after-free): `destroy` reconstructs+drops the `Box` exactly once, null-tolerant; header documents "no use after destroy". → `ffi_round_trip` (create→…→destroy + null-destroy no-op).
- **T-03-02-02** (double-free / uninit drop): `Drop for Spsc<T>` drains only `[head, tail)` via `assume_init_drop`. → `drop_drains_only_live_slots` (DropCounter proves exactly live-count dropped).
- **T-03-02-03** (null/OOB deref): push/pop/destroy null-guard every raw pointer before any deref; slot index always `& mask`. → `push_pop_reject_null_pointers`.
- **T-03-02-04** (bad capacity / integer): `create` rejects zero/non-pow2 → null. → `create_rejects_bad_capacity`.
- **T-03-02-05** (panic-across-FFI): every body wrapped in `catch_unwind`. → grep + all ffi tests.
- **T-03-02-06** (data race / wrong ordering): Release/Acquire proven by the loom test incl. the Relaxed-mutant that loom catches; `Producer`/`Consumer` split makes MPMC misuse a type error. → `loom_spsc_fifo_no_loss_all_interleavings` + negative control.

No `threat_flag` raised. D-R8 honored: this ring is the decoupling boundary, so AES-GCM stays OFF the producer hot path — no crypto threat surface here.

## Known Stubs

None. This plan's entire purpose was to replace Plan 01's stub bodies. `StubRing` is fully removed (replaced by `RingHandle`); no `TODO`/`FIXME`/`unimplemented!`/placeholder remains in `src/`, `tests/`, or `benches/`. The criterion bench is no longer the Plan-01 empty-`main` placeholder.

## User Setup Required

None — no external service configuration. The Rust toolchain (`rustup` + `cbindgen` via brew) was already bootstrapped in Plan 01 and wired into `ci.yml`.

## Next Phase Readiness

- **Plan 03 (pthread hot path):** can drive `cortex_spsc_push` from the `QOS_CLASS_USER_INTERACTIVE` producer thread through the C ABI (a C call — no ARC, no Swift runtime). The ring is the decoupling boundary (D-R8). 03-03 owns the Swift/policy-gate files; this plan stayed strictly in `Packages/CortexRing/rust/**` so the merge is clean.
- **Plan 04 (Swift integration):** `import CortexRingFFI` → `cortex_spsc_create/push/pop/destroy` now move REAL frames; the Swift produce→pop integration test (SC#4) reads frames the C/Rust side actually produced. The cbindgen header is stable (drift gate green), so no Swift-side regeneration churn.
- **Concern (carried from Plan 01):** the Rust CI gates (loom/stress/drift) have still not been exercised by a real `macos-15` runner — the first PR after the wave lands is the first true end-to-end CI proof. All gates pass locally on this M-series host (loom 0.12 s, stress 0.10 s, drift clean, benches build).

## Self-Check: PASSED

- All 4 created files + 5 modified files verified present on disk.
- All 3 task commit hashes verified in git history: `89c37d3` (Task 1), `8984936` (Task 2), `b8f8c1c` (Task 3).
- Full suite green: 11 unit (7 spsc + 4 ffi) + 1 stress (1M) under `cargo test --release`; loom green under `--cfg loom` (negative control FAILS as required); header drift gate clean; benches build (default + rtrb-xcheck); clippy `--all-targets [--features rtrb-xcheck] -D warnings` exits 0; all files rustfmt-clean.

---
*Phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring*
*Completed: 2026-06-20*
