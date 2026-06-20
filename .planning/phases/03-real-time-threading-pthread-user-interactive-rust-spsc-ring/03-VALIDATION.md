---
phase: 3
slug: real-time-threading-pthread-user-interactive-rust-spsc-ring
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
updated: 2026-06-20
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `03-RESEARCH.md` §5 (Validation Architecture). Task IDs reconciled to the
> `gsd-planner` output (Plans 03-01..03-04). Every task that maps to a row below carries an
> `<automated>` verify command; `gsd-validate-phase` confirms task IDs after execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` (ring: unit + 1M stress + `--cfg loom` permutation) · Swift Testing via `swift test` (SC#4 cbindgen integration + the Ping cross-build smoke) · `bash` (hot-path policy self-test) |
| **Config file** | `Packages/CortexRing/rust/Cargo.toml` (incl. `[target.'cfg(loom)'.dependencies]` + `[profile.loom]`); `Packages/CortexRing/Package.swift`; `Tools/scripts/hotpath-policy.sh`; `Tools/scripts/build-rust.sh` — Plan 03-01 installs the Rust toolchain (`rustup` + Apple targets) + `cbindgen` and pre-arms the CI gates |
| **Quick run command** | `cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml` |
| **Full suite command** | `Tools/scripts/build-rust.sh && cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml && RUSTFLAGS="--cfg loom" cargo test --profile loom --manifest-path Packages/CortexRing/rust/Cargo.toml && swift test --package-path Packages/CortexRing && ./Tools/scripts/hotpath-policy.sh` |
| **Estimated runtime** | ~60–120 s (loom tiny-scenario exhaustive search dominates; 1M stress ~seconds; xcframework build ~tens of seconds, cached in CI) |

---

## Sampling Rate

- **After every task commit:** Run `cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml` (quick: unit + stress, no loom) — Swift-side tasks additionally run `swift test --package-path Packages/CortexRing`
- **After every plan wave:** Run the full suite command (adds the xcframework build + loom + Swift integration + policy gate)
- **Before `/gsd-verify-work`:** Full suite must be green; SC#1 Instruments trace captured on M4 (manual, `instruments-evidence.md`)
- **Max feedback latency:** ~120 seconds (CI); SC#1 hardware trace is per-milestone, not per-commit (the always-on policy gate is its CI proxy)

---

## Per-Task Verification Map

> Every row has an automated CI command except SC#1's Instruments trace, which is M4-hardware-gated
> manual evidence with the policy gate as its continuous CI proxy. Wave column = the plan's execution
> wave. All commands are correctness/model only — no timing assertion in CI (D-18 split).

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01 T1 | 03-01 | 1 | THREAD-06 (ABI freeze) | T-03-01-01/02 | repr(C) Frame layout-locked to CORTEX_CHANNEL_COUNT; extern "C" ABI + catch_unwind panic guard | unit | `cd Packages/CortexRing/rust && cargo build --release` (+ size_of static assert, header tokens) | ⬜ Plan 03-01 | ⬜ pending |
| 03-01 T2 | 03-01 | 1 | THREAD-06 (SC#4 chain) | T-03-01-03/04 | Rust extern "C" callable from Swift via xcframework .binaryTarget under swift build AND xcodebuild | integration | `Tools/scripts/build-rust.sh && swift test --package-path Packages/CortexRing` (PingSmokeTests) | ⬜ Plan 03-01 | ⬜ pending |
| 03-01 T3 | 03-01 | 1 | THREAD-06 (CI scaffold) | T-03-01-03 | CI installs Rust + builds xcframework before resolve; loom/stress/drift/integration gates pre-armed | structural | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` (+ gate-presence greps) | ⬜ Plan 03-01 | ⬜ pending |
| 03-02 T1 | 03-02 | 2 | THREAD-04/05 (SC#3c) | T-03-02-06 | 128-byte cache-line-padded head/tail; Release/Acquire (no SeqCst) | unit | `cd Packages/CortexRing/rust && cargo test --release spsc` (align_of==128 assert) | ⬜ Plan 03-02 | ⬜ pending |
| 03-02 T2 | 03-02 | 2 | THREAD-07 (SC#3a) | T-03-02-06 | no reorder/torn-read/data-race under the C11 model (loom) | loom | `RUSTFLAGS="--cfg loom" cargo test --profile loom --test loom_spsc` | ⬜ Plan 03-02 | ⬜ pending |
| 03-02 T2 | 03-02 | 2 | THREAD-04 (SC#3b) | T-03-02-03 | 1M frames, strict FIFO, zero loss (std atomics, 2 threads) | stress | `cargo test --release --test stress_fifo` (1M-frame test) | ⬜ Plan 03-02 | ⬜ pending |
| 03-02 T3 | 03-02 | 2 | THREAD-06 (ABI bodies) | T-03-02-01..05 | extern "C" create/push/pop/destroy drive the real ring; pointer-safe; header un-drifted | unit | `cargo test --release ffi && git diff --exit-code include/cortex_ring.h` | ⬜ Plan 03-02 | ⬜ pending |
| 03-03 T1 | 03-03 | 2 | THREAD-01/02/03 (SC#1 struct.) | T-03-03-01/04 | pthread @ USER_INTERACTIVE pushing to the ring; Foundation-free; no ARC/dispatch/Task on the loop | structural | `swift build --package-path Packages/CortexRing` (+ QoS/push greps; no Foundation/Task) | ⬜ Plan 03-03 | ⬜ pending |
| 03-03 T2 | 03-03 | 2 | THREAD-03 (SC#2) | T-03-03-02 | gate fails on dispatch_async/lazy var/pthread_mutex/Foundation/ObjC/Mutex/RwLock/.lock(/println!/panic! across .swift/.c/.rs | static-analysis | `./Tools/scripts/hotpath-policy.sh` (+ negative-control self-test bites each token) | ⬜ Plan 03-03 | ⬜ pending |
| 03-03 T3 | 03-03 | 2 | THREAD-01/02 (SC#1 wiring) | T-03-03-03 | hot-path product wired into daemon build; SC#1 M4 System-Trace runbook authored (manual evidence) | structural | `python3 -c "import yaml; yaml.safe_load(open('project.yml'))"` + `instruments-evidence.md` present | ⬜ Plan 03-03 | ⬜ pending |
| 03-04 T1 | 03-04 | 3 | THREAD-06 (SC#4 wrapper) | T-03-04-01/02/03 | safe RAII Swift wrapper over the cbindgen C ABI; repr(C) CortexFrame used directly (no drift mirror) | unit | `swift build --package-path Packages/CortexRing` (+ cortex_spsc_* greps) | ⬜ Plan 03-04 | ⬜ pending |
| 03-04 T2 | 03-04 | 3 | THREAD-06 (SC#4) | T-03-04-02 | Swift creates the ring via C ABI, produces N frames, pops+verifies value AND order | integration | `swift test --package-path Packages/CortexRing` (RingIntegrationTests) | ⬜ Plan 03-04 | ⬜ pending |
| 03-04 T2 | 03-04 | 3 | THREAD-06 (SC#4 drift) | T-03-04-02 | cbindgen header matches Rust source (no drift) — SC#4 structural negative control | drift-gate | `cargo build --release && git diff --exit-code include/cortex_ring.h` (pre-armed CI, Plan 03-01) | ⬜ Plan 03-01 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 / Foundational Requirements (Plan 03-01, Wave 1)

> Phase 3's "Wave 0" is **Plan 03-01** — the FFI/build spine + ABI freeze + CI scaffold (Spike A).
> It gates every Wave-2/3 task (the crate, the loom/stress harness, the Swift wrapper, the hot path).

- [ ] `Packages/CortexRing/rust/Cargo.toml` + `src/lib.rs` + `src/frame.rs` + `src/ffi.rs` — crate skeleton, crate-type `["staticlib","rlib"]`, frozen ABI, repr(C) Frame (Plan 03-01 T1)
- [ ] `src/loom.rs` (std↔loom shim) — landed in Plan 03-02 T1 (the shim ships with the ring it serves; Cargo.toml pre-wires `[target.'cfg(loom)']` + `[profile.loom]` in Plan 03-01 T1)
- [ ] Rust toolchain install (CI + local): `rustup` + `rustup target add aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim` + `cargo install cbindgen` (Plan 03-01 T1/T3)
- [ ] `Tools/scripts/build-rust.sh` — cargo build per Apple target + cbindgen header + xcframework assembly (D-R1) (Plan 03-01 T2)
- [ ] CI gates pre-armed in `ci.yml`: toolchain install, xcframework build (before resolve/xcodegen), loom, 1M-stress, cbindgen-drift, Swift-integration (Plan 03-01 T3)
- [ ] `Packages/CortexRing/rust/tests/` — loom test + 1M-stress test (THREAD-04/05/07) (Plan 03-02 T2)
- [ ] `Packages/CortexRing/Tests/` — Swift integration test (THREAD-06/SC#4) (Plan 03-04 T2; PingSmokeTests stub from Plan 03-01 T2)
- [ ] Extend `Tools/scripts/hotpath-policy.sh` `DIRS_ARRAY` + `.rs` token set + negative-control self-test (D-R7) (Plan 03-03 T2)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Zero Swift cooperative-runtime activity on the hot-path thread under load | THREAD-01/02 (SC#1) | Instruments → System Trace cannot run in CI; M4-hardware-gated (mirrors Phase 2 `sc1-evidence.md`) | Run the daemon/app driving `CortexAcquisition.run(...)` under load on M4, capture System Trace, confirm the worker thread shows no `swift_task_*`/libdispatch frames; commit trace + `instruments-evidence.md` (authored in Plan 03-03 T3). CI proxy: `hotpath-policy.sh` green every run. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 (Plan 03-01) dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every task carries an `<automated>` command)
- [x] Wave 0 (Plan 03-01) covers all foundational/MISSING references (toolchain, xcframework, ABI, CI scaffold)
- [x] No watch-mode flags (all commands are single-shot `cargo`/`swift test`/`bash`)
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter (tasks carry verify commands)

**Approval:** planner-approved 2026-06-20 (task IDs reconciled to Plans 03-01..03-04; `gsd-validate-phase` confirms after execution). `wave_0_complete` flips true once Plan 03-01 lands.
