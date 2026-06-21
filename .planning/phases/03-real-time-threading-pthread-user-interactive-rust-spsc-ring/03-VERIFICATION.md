---
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
verified: 2026-06-21T00:35:57Z
status: human_needed
score: 3/4 success criteria verified (SC#1 .trace deferred to M4 hardware session)
human_verification:
  - test: "Instruments System Trace — SC#1 behavioural proof"
    expected: "Zero swift_task_*/libdispatch frames on the acquisition worker thread under load; thread shows QOS_CLASS_USER_INTERACTIVE band"
    why_human: "Instruments System Trace cannot run in CI (GUI profiler on a live process, M4 hardware required). The always-on CI proxy (hotpath-policy.sh) is green; the .trace file capture per instruments-evidence.md runbook is a per-milestone deferred manual step following the D-18 evidence split established in Phase 1/Phase 2."
deferred:
  - truth: "The Instruments System Trace .trace file for SC#1 committed to repo"
    addressed_in: "Phase 3 milestone hardware session"
    evidence: "instruments-evidence.md explicitly labels capture status as deferred: 'Runbook + always-on CI proxy committed; .trace capture deferred to an M4/M5 Instruments session (the established Phase-1 SC#2 / Phase-2 SC#1 hardware-evidence split, D-18).' No later numbered phase owns this item — it is hardware-gated, not scope-deferred."
---

# Phase 3: Real-Time Threading — pthread USER_INTERACTIVE + Rust SPSC Ring — Verification Report

**Phase Goal:** The acquisition/DSP hot path runs under audio-callback rules — pthread with `QOS_CLASS_USER_INTERACTIVE`, no Swift `Task`, no `dispatch_async`, no ARC retain/release on the path — and a `loom`-verified lock-free SPSC ring carries samples from that thread to the Swift UI layer via a `cbindgen` bridge.
**Verified:** 2026-06-21T00:35:57Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP.md success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC#1 | pthread_create worker calls `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`; Instruments System Trace shows zero Swift cooperative-runtime activity under load | ? HUMAN NEEDED | Code-level truth VERIFIED: `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` is the FIRST executable statement (line 96, after comment) in `cortexAcquisitionThread`; `pthread_create` call confirmed (line 199 of Acquisition.swift); `import Darwin` only (no Foundation). Behavioural proof (.trace file showing zero `swift_task_*/libdispatch` frames) is M4-hardware-gated per D-18 split; `instruments-evidence.md` runbook committed; `hotpath-policy.sh` is the always-on CI proxy. |
| SC#2 | Static-analysis CI gate fails if any hot-path source calls `dispatch_async`, contains `lazy var`, holds a `pthread_mutex`, or imports `Foundation`/Obj-C runtime headers | ✓ VERIFIED | `hotpath-policy.sh` polices `CortexAcquisitionHotPath` + `CortexRingHotPath` dirs (Swift/C tokens) AND RUST_HOTPATH_FILES (Rust tokens: `Mutex`, `RwLock`, `.lock(`, `println!(`, `panic!(`). `--self-test` mode injects every forbidden token into temp files across .swift/.c/.rs and asserts each one causes the gate to fail (negative-control with 11 tokens per self-test run). CI (`ci.yml` line 200) runs `./Tools/scripts/hotpath-policy.sh` on every push. |
| SC#3 | In-house Rust SPSC ring with 128B-padded atomics and Acquire/Release ordering moves 1M frames producer→consumer with zero reorderings under `loom` permutation testing in CI | ✓ VERIFIED | (a) `loom_spsc.rs`: `#![cfg(loom)]` gate (line 29), `loom::model(|| {...})` exhaustive search, relaxed-mutant negative control (`#[cfg(loom_negative_control)]` swaps Release→Relaxed; loom reports causality violation). (b) `stress_fifo.rs`: `#![cfg(not(loom))]` gate (line 19), 1,000,000-frame strict-FIFO zero-loss test on std atomics + two OS threads. (c) `spsc.rs`: `#[repr(align(128))] struct CachePad` (line 37), `const _: () = assert!(core::mem::align_of::<CachePad>() == 128)` (line 42), zero `SeqCst` in entire Rust source tree (only mentioned in comments), head/tail publish uses Release, observation uses Acquire, own-index reload uses Relaxed. (d) CI gates: `RUSTFLAGS="--cfg loom" cargo test --profile loom` (loom step) + `cargo test --release --test stress_fifo` (stress step). Orchestrator pre-confirmed all 11+1 Rust tests GREEN on HEAD commit 1c02ecd. |
| SC#4 | `cbindgen`-generated header lets Swift consume the Rust ring via a stable C ABI; Swift integration test reads frames produced from the C/Rust side | ✓ VERIFIED | `cortex_ring.h` contains all four frozen symbols (`cortex_spsc_create`, `cortex_spsc_push`, `cortex_spsc_pop`, `cortex_spsc_destroy`) plus `CortexFrame` typedef. `Ring.swift` uses `@_exported import CortexRingFFI` (no hand-written `struct CortexFrame`). `RingIntegrationTests.swift` produces 1000 frames with known (seq, ts_ns, channel_data) pattern, interleaves push-until-full + drain-via-pop, and asserts VALUE + strict FIFO ORDER. CI cbindgen drift gate (`git diff --exit-code Packages/CortexRing/rust/include/cortex_ring.h` after regeneration) pre-armed in `ci.yml`. Orchestrator pre-confirmed 7/7 `swift test` GREEN. |

**Score:** 3/4 truths fully verified (SC#1 code-side VERIFIED; SC#1 behavioural trace HUMAN NEEDED)

---

### Deferred Items

Items not yet met but explicitly constrained by hardware availability (D-18 split), not by scope order.

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | Instruments System Trace `.trace` file showing zero `swift_task_*`/libdispatch frames on the acquisition worker under load | Phase 3 milestone hardware session (M4/M5 machine) | `instruments-evidence.md` line 3–17: "Runbook + always-on CI proxy committed; `.trace` capture deferred to an M4/M5 Instruments session (the established Phase-1 SC#2 / Phase-2 SC#1 hardware-evidence split, D-18)." Follows precedent from Phase 1 `sc1-evidence.md` and Phase 2 `sc1-evidence.md`. The runbook is fully authored. |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Packages/CortexRing/rust/src/spsc.rs` | SPSC ring: 128B CachePad, Release/Acquire, no SeqCst | ✓ VERIFIED | `#[repr(align(128))]` + `assert!(align_of == 128)` confirmed; Release publish / Acquire observe throughout; zero SeqCst in entire Rust source tree |
| `Packages/CortexRing/rust/src/loom.rs` | std↔loom cfg shim routing AtomicUsize, UnsafeCell, Arc | ✓ VERIFIED | `#[cfg(loom)]` arm routes to `loom::*`; `#[cfg(not(loom))]` arm routes to `core::sync::atomic::*`; `CortexCell<T>` wrapper with `with`/`with_mut` closure API |
| `Packages/CortexRing/rust/src/ffi.rs` | Four frozen `extern "C"` exports with catch_unwind | ✓ VERIFIED | All four `#[no_mangle] pub extern "C"` exports present; every body wraps in `std::panic::catch_unwind` / `AssertUnwindSafe`; returns safe defaults on unwind |
| `Packages/CortexRing/rust/src/frame.rs` | `#[repr(C)] CortexFrame` with layout-lock assert | ✓ VERIFIED | `#[repr(C)] pub struct CortexFrame { ts_ns: u64, seq: u64, channel_data: [u16; 96] }`; `const _: () = assert!(size_of::<CortexFrame>() == 16 + CORTEX_CHANNEL_COUNT * 2)` |
| `Packages/CortexRing/rust/tests/loom_spsc.rs` | `#![cfg(loom)]` gate + loom::model + negative control | ✓ VERIFIED | `#![cfg(loom)]` on line 29; `loom::model(|| {...})` call; relaxed-mutant `#[cfg(loom_negative_control)]` control path confirmed |
| `Packages/CortexRing/rust/tests/stress_fifo.rs` | `#![cfg(not(loom))]` gate + 1M frames + FIFO assert | ✓ VERIFIED | `#![cfg(not(loom))]` on line 19; 1,000,000-frame strict FIFO zero-loss test with two OS threads on production std atomics |
| `Packages/CortexRing/rust/include/cortex_ring.h` | cbindgen-generated header with all four C ABI symbols | ✓ VERIFIED | `typedef struct CortexFrame {...}` + all four function declarations present; drift gate in CI (`git diff --exit-code`) |
| `Tools/scripts/build-rust.sh` | cargo build per Apple target + cbindgen + xcframework | ✓ VERIFIED | CI line 126 invokes `./Tools/scripts/build-rust.sh`; Rust toolchain install step precedes it |
| `Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift` | pthread_create worker, QoS FIRST action, import Darwin, cortex_spsc_push | ✓ VERIFIED | `import Darwin` only (no Foundation); `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` is first executable statement in `cortexAcquisitionThread` (line 96); `cortex_spsc_push(ring, frame)` call confirmed (line 121); `pthread_create` call confirmed (line 199) |
| `Packages/CortexRing/Sources/CortexRing/Ring.swift` | Safe RAII wrapper, `@_exported import CortexRingFFI`, no hand-written CortexFrame | ✓ VERIFIED | `@_exported import CortexRingFFI` on line 5; `OpaquePointer` stored; `init?(capacity:)` guards null; `deinit` calls `cortex_spsc_destroy` exactly once; zero `struct CortexFrame` definition in file |
| `Packages/CortexRing/Tests/CortexRingTests/RingIntegrationTests.swift` | Swift Testing `@Test`, produce N frames, verify VALUE + FIFO ORDER | ✓ VERIFIED | `import Testing`; `@Test` on line 21; 1000-frame push/drain loop; VALUE + strict FIFO seq assertion; three additional @Test functions for nil-on-empty and false-on-full |
| `Tools/scripts/hotpath-policy.sh` | CortexRingHotPath in DIRS_ARRAY, Rust forbidden in call form, --self-test | ✓ VERIFIED | `DIRS_ARRAY` includes both `CortexAcquisitionHotPath` and `CortexRingHotPath`; `RUST_FORBIDDEN=("Mutex" "RwLock" ".lock(" "println!(" "panic!(")` in call form; `--self-test` mode with 11-token injection across .swift/.c/.rs |
| `.planning/phases/.../instruments-evidence.md` | SC#1 System Trace runbook; .trace capture deferred per D-18 | ✓ VERIFIED (runbook) | 153-line runbook authored; documents expected System Trace evidence, CI proxy rationale, and exact M4 capture steps. `.trace` file itself is pending hardware session. |
| `.github/workflows/ci.yml` | All six Phase-3 gates pre-armed | ✓ VERIFIED | Rust toolchain install, xcframework build, loom permutation, 1M stress, cbindgen drift gate, hotpath-policy.sh — all present in ci.yml |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Acquisition.swift` | `cortex_spsc_push` (Rust FFI) | `import CortexRingFFI` + `cortex_spsc_push(ring, frame)` | ✓ WIRED | Call confirmed on line 121; CortexRingFFI imported on line 39 |
| `Ring.swift` | `CortexFrame` (cbindgen type) | `@_exported import CortexRingFFI` | ✓ WIRED | Line 5; no hand-written mirror; consumers of CortexRing see CortexFrame directly |
| `Ring.swift` | `cortex_spsc_create/push/pop/destroy` | `OpaquePointer(raw)` + `UnsafeMutablePointer<CortexSpsc>(handle)` | ✓ WIRED | All four C ABI calls confirmed in Ring.swift |
| `spsc.rs` | `loom.rs` shim | `use crate::loom::atomic::*` | ✓ WIRED | Producer and consumer use `crate::loom::atomic::Ordering::Acquire/Release/Relaxed` throughout |
| `ffi.rs` | `spsc.rs` | `Spsc::new(capacity)` + `ring.push(frame)` + `ring.pop(out)` | ✓ WIRED | All four extern "C" bodies drive the real ring (not stubs) |
| `stress_fifo.rs` | `spsc.rs` | `use cortex_ring::spsc::Spsc` | ✓ WIRED | Stress test creates real ring and drives it for 1M frames |
| `loom_spsc.rs` | `spsc.rs` | `use cortex_ring::spsc::Spsc` (via `crate::loom` shim) | ✓ WIRED | Loom test instantiates real ring; `loom::model` exhaustive search exercises all orderings |
| `ci.yml` | `build-rust.sh` | `run: ./Tools/scripts/build-rust.sh` | ✓ WIRED | Step confirmed after toolchain install step |
| `ci.yml` | cbindgen drift gate | `git diff --exit-code Packages/CortexRing/rust/include/cortex_ring.h` | ✓ WIRED | Step confirmed on line 177 |
| `ci.yml` | loom gate | `RUSTFLAGS="--cfg loom" cargo test --profile loom` | ✓ WIRED | Step confirmed on line 168 |
| `ci.yml` | hotpath-policy.sh | `run: ./Tools/scripts/hotpath-policy.sh` | ✓ WIRED | Step confirmed on line 200 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `Acquisition.swift` | `CortexFrame` pushed to ring | `mach_absolute_time()` (ts_ns), monotonic seq counter, zeroed channel_data | Ring call confirmed; channel_data zeroed this phase (Phase 4 adds real decoder output per PLAN) | ✓ FLOWING (Phase 3 scope: synthetic frames; real spike data is Phase 4) |
| `Ring.swift` | `CortexFrame` popped from ring | C/Rust ring buffer via `cortex_spsc_pop` | Ring pop call returns cbindgen C type populated by Rust side | ✓ FLOWING |
| `RingIntegrationTests.swift` | Collected frames | `ring.push(frame)` with known ts_ns/seq pattern | 1000 frames with verified VALUE + FIFO ORDER assertion | ✓ FLOWING |

---

### Behavioral Spot-Checks

Orchestrator pre-confirmed on HEAD commit 1c02ecd; not re-run in this verification pass (no server/hardware available in CI-equivalent context).

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Rust unit + 1M stress | `cargo test --release` (11 unit + 1 stress) | 12/12 GREEN | ✓ PASS (orchestrator-confirmed) |
| loom permutation (SC#3a) | `RUSTFLAGS="--cfg loom" cargo test --profile loom --test loom_spsc` | `loom_spsc_fifo_no_loss_all_interleavings` GREEN 0.13s | ✓ PASS (orchestrator-confirmed) |
| Swift tests 7/7 | `swift test --package-path Packages/CortexRing` | 7/7 GREEN | ✓ PASS (orchestrator-confirmed) |
| CortexCore + CortexIPC build | `swift build` | GREEN | ✓ PASS (orchestrator-confirmed) |
| Instruments System Trace | Manual M4 session per `instruments-evidence.md` | NOT YET RUN (runbook authored) | ? SKIP (hardware-gated) |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| THREAD-01 | 03-03-PLAN | Acquisition/DSP hot path runs on a pthread, never on Swift Task | ✓ SATISFIED | `pthread_create` call in Acquisition.swift line 199; `@convention(c)` entry point; no `Task {}` in hot-path source tree (hotpath-policy.sh enforces) |
| THREAD-02 | 03-03-PLAN | Hot-path thread uses `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` | ✓ SATISFIED | Line 96 of Acquisition.swift is FIRST executable statement in `cortexAcquisitionThread`; comment on line 87 explicitly states "FIRST action" |
| THREAD-03 | 03-03-PLAN | Hot path obeys audio-callback rules — no dispatch_async, no Obj-C runtime, no locks, no ARC retain/release | ✓ SATISFIED | hotpath-policy.sh CI gate enforces all forbidden tokens; `import Darwin` only; `cortex_spsc_push` is a plain C call (no ARC/dispatch/Task per comment lines 5–6); negative-control self-test bites each forbidden token |
| THREAD-04 | 03-02-PLAN | Lock-free SPSC ring buffer bridges decoder thread to UI | ✓ SATISFIED | In-house `spsc.rs` with wait-free push/pop; `ffi.rs` exports real ring via C ABI; Ring.swift and Acquisition.swift wire it end-to-end |
| THREAD-05 | 03-02-PLAN | Ring buffer uses cache-line-padded atomics with Acquire/Release memory ordering | ✓ SATISFIED | `#[repr(align(128))] struct CachePad` with compile-time `align_of == 128` assert; Release publish / Acquire observe; zero SeqCst in entire Rust source tree |
| THREAD-06 | 03-01-PLAN / 03-04-PLAN | Rust SPSC bridged to Swift via cbindgen-generated header | ✓ SATISFIED | `cortex_ring.h` with all four C ABI symbols; `@_exported import CortexRingFFI`; no hand-written CortexFrame mirror; cbindgen drift gate in CI; 7/7 Swift tests GREEN including RingIntegrationTests |
| THREAD-07 | 03-02-PLAN | Memory ordering verified with loom permutation testing | ✓ SATISFIED | `loom_spsc.rs` with `#![cfg(loom)]` + `loom::model` exhaustive search; relaxed-mutant negative control confirms loom catches ordering violations; GREEN per orchestrator |

---

### Design Decision Adherence

Spot-checks on D-R2..D-R8 per user-specified verification focus:

| Decision | Claim | Code Evidence | Status |
|----------|-------|--------------|--------|
| D-R4: Release/Acquire ONLY | No SeqCst on ring hot atomics; 128B CachePad not 64B | `grep -rn "SeqCst" .../rust/src/` returns zero hits (only comments); `#[repr(align(128))]` + `assert!(align_of == 128)` both present | ✓ HONORED |
| D-R5: Two separate tests | Tiny loom test + separate 1M std-atomic stress test | `loom_spsc.rs #![cfg(loom)]` (line 29); `stress_fifo.rs #![cfg(not(loom))]` (line 19) — never 1M under loom | ✓ HONORED |
| D-R2: QoS FIRST action | `pthread_set_qos_class_self_np` as first action; `import Darwin` not Foundation | Line 96 of Acquisition.swift is first executable statement; only imports are `CortexRingFFI` and `Darwin` | ✓ HONORED |
| D-R7: Policy gate scope + self-test | Gates CortexRingHotPath AND .rs ring sources; negative-control bites each forbidden token | `DIRS_ARRAY` includes `CortexRingHotPath`; `RUST_HOTPATH_FILES` set; `--self-test` injects all 11 tokens; Rust tokens in call form (`.lock(`, `println!(`, `panic!(`) | ✓ HONORED |
| D-R8: AES-GCM off hot path | AES-GCM stays on Phase-2 IPC side; ring is the decoupling boundary | Lines 28–31 of Acquisition.swift: "D-R8 (resolves Phase 2 D-06): AES-GCM is NOT on this hot path. The SPSC ring is the decoupling boundary — encryption stays on the Phase-2 cross-process IPC session side, never on this Foundation-free thread." | ✓ HONORED |
| THREAD-06 / cbindgen: no drift-prone mirror | Swift uses `#[repr(C)]` CortexFrame from cbindgen header directly; drift gate in CI | `@_exported import CortexRingFFI` in Ring.swift; zero `struct CortexFrame` definition in Swift sources; CI `git diff --exit-code cortex_ring.h` gate confirmed | ✓ HONORED |

---

### Anti-Patterns Found

No blockers or functional stubs detected. Specific checks:

| File | Pattern | Severity | Notes |
|------|---------|----------|-------|
| `Acquisition.swift` | `channel_data` zeroed (not real spike data) | ℹ️ Info | Intentional Phase 3 scope; Phase 4 adds NDT1 synthetic spike replay. Comment in source confirms design. Not a stub — it's the documented Phase 3 deliverable boundary. |
| `instruments-evidence.md` | `.trace` file not yet committed | ℹ️ Info | D-18 hardware-evidence deferral; runbook authored and committed; CI proxy active. |

---

### Human Verification Required

#### 1. Instruments System Trace — SC#1 Behavioural Proof

**Test:** Run `CortexAcquisition.run(ring:frames:)` driving the pthread acquisition worker for 50,000,000 frames on M4-class Apple Silicon (M4, M4 Pro, M5, M5 Pro — any M4+ SoC). Capture Instruments → System Trace. Full step-by-step procedure in `instruments-evidence.md`.

**Expected:**
- The worker thread shows `QOS_CLASS_USER_INTERACTIVE` band in the thread state lane
- Call tree contains NO `swift_task_*` symbols (`swift_task_create`, `swift_task_switch`, `swift_continuation_*`, `swift_asyncLet_*`)
- Call tree contains NO `_dispatch_*` / libdispatch symbols on the worker thread
- Worker thread stays in its band continuously (no preemption to lower QoS)

**Why human:** Instruments System Trace requires a live GUI process on real Apple Silicon hardware with a physical Instruments session. Cannot run in CI. M4-class hardware is required to exercise `CAMetalDisplayLink`, ProMotion, and the `FEAT_AES` ANE path that the full v1 latency claim depends on.

**Runbook:** `.planning/phases/03-real-time-threading-pthread-user-interactive-rust-spsc-ring/instruments-evidence.md`

---

### Gaps Summary

No gaps blocking goal achievement. All four success criteria are implemented and wired:

- SC#2 (policy gate), SC#3 (ring correctness), and SC#4 (cbindgen + Swift integration) are fully verified programmatically with orchestrator-confirmed GREEN test suite.
- SC#1 code-side is verified: `pthread_create` + `QOS_CLASS_USER_INTERACTIVE` as first action + `import Darwin` only + `cortex_spsc_push` call all confirmed in source. The only unverified part is the `.trace` file proving zero Swift cooperative-runtime frames at runtime, which is M4-hardware-gated per the D-18 split applied consistently across Phases 1, 2, and 3.

The phase achieves its stated goal. Human verification is required only for the runtime behavioural proof of SC#1.

---

_Verified: 2026-06-21T00:35:57Z_
_Verifier: gsd-verifier_
