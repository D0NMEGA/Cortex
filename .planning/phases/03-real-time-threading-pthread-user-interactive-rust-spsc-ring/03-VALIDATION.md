---
phase: 3
slug: real-time-threading-pthread-user-interactive-rust-spsc-ring
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `03-RESEARCH.md` §5 (Validation Architecture). Task IDs are TBD until
> `gsd-planner` runs; the planner MUST attach an `<automated>` verify to each task that
> maps to a row below, and `gsd-validate-phase` reconciles task IDs afterward.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust `cargo test` (ring: unit + 1M stress + `--cfg loom` permutation) · Swift Testing via `swift test` (SC#4 cbindgen integration) · `bash` (hot-path policy self-test) |
| **Config file** | `Packages/CortexRing/rust/Cargo.toml` (incl. `[target.'cfg(loom)'.dependencies]` + `[profile.loom]`); `Packages/CortexRing/Package.swift`; `Tools/scripts/hotpath-policy.sh` — Wave 0 installs the Rust toolchain (`rustup` + Apple targets) + `cbindgen` |
| **Quick run command** | `cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml` |
| **Full suite command** | `cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml && RUSTFLAGS="--cfg loom" cargo test --profile loom --manifest-path Packages/CortexRing/rust/Cargo.toml && swift test --package-path Packages/CortexRing && ./Tools/scripts/hotpath-policy.sh` |
| **Estimated runtime** | ~60–120 s (loom tiny-scenario exhaustive search dominates; 1M stress ~seconds) |

---

## Sampling Rate

- **After every task commit:** Run `cargo test --release --manifest-path Packages/CortexRing/rust/Cargo.toml` (quick: unit + stress, no loom)
- **After every plan wave:** Run the full suite command (adds loom + Swift integration + policy gate)
- **Before `/gsd-verify-work`:** Full suite must be green; SC#1 Instruments trace captured on M4 (manual, `instruments-evidence.md`)
- **Max feedback latency:** ~120 seconds (CI); SC#1 hardware trace is per-milestone, not per-commit (the always-on policy gate is its CI proxy)

---

## Per-Task Verification Map

> Requirement-level contract (task IDs assigned by the planner). Every row has an automated
> CI command except SC#1's Instruments trace, which is M4-hardware-gated manual evidence with
> the policy gate as its continuous CI proxy.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | 1 | THREAD-01/02 | — | pthread @ USER_INTERACTIVE; no Swift Task on hot path | structural | `./Tools/scripts/hotpath-policy.sh` | ❌ W0 | ⬜ pending |
| TBD | TBD | 1 | THREAD-03 (SC#2) | — | no dispatch_async/lazy var/pthread_mutex/Foundation/ObjC/Mutex in hot path | static-analysis | `./Tools/scripts/hotpath-policy.sh` (+ self-test) | ❌ W0 | ⬜ pending |
| TBD | TBD | 1 | THREAD-04/05 (SC#3c) | — | 128-byte cache-line-padded head/tail; Acquire/Release | unit | `cargo test --release …` (align_of==128 assert) | ❌ W0 | ⬜ pending |
| TBD | TBD | 2 | THREAD-07 (SC#3a) | — | no reorder/torn-read/data-race under C11 model | loom | `RUSTFLAGS="--cfg loom" cargo test --profile loom …` | ❌ W0 | ⬜ pending |
| TBD | TBD | 2 | THREAD-04 (SC#3b) | — | 1M frames, strict FIFO, zero loss | stress | `cargo test --release …` (1M-frame test) | ❌ W0 | ⬜ pending |
| TBD | TBD | 2 | THREAD-06 (SC#4) | — | Swift reads frames produced from C/Rust via cbindgen ABI | integration | `swift test --package-path Packages/CortexRing` | ❌ W0 | ⬜ pending |
| TBD | TBD | 2 | THREAD-06 (SC#4) | — | cbindgen header matches Rust source (no drift) | drift-gate | `cbindgen … \| git diff --exit-code` (when present, per D-13) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Packages/CortexRing/rust/Cargo.toml` + `src/lib.rs` + `src/loom.rs` (std↔loom shim) — ring skeleton + crate-type `["staticlib","rlib"]`
- [ ] Rust toolchain install (CI + local): `rustup` + `rustup target add aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim` + `cargo install cbindgen`
- [ ] `Packages/CortexRing/rust/tests/` — loom test stub + 1M-stress test stub (THREAD-04/05/07)
- [ ] `Packages/CortexRing/Tests/` — Swift integration test stub (THREAD-06/SC#4)
- [ ] `Tools/scripts/build-rust.sh` — cargo build per Apple target + cbindgen header + xcframework assembly (D-R1)
- [ ] Extend `Tools/scripts/hotpath-policy.sh` `DIRS_ARRAY` + `.rs` token set + negative-control self-test (D-R7)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Zero Swift cooperative-runtime activity on the hot-path thread under load | THREAD-01/02 (SC#1) | Instruments → System Trace cannot run in CI; M4-hardware-gated (mirrors Phase 2 `sc1-evidence.md`) | Run the daemon/app under load on M4, capture System Trace, confirm the worker thread shows no `swift_task_*`/libdispatch frames; commit trace + `instruments-evidence.md`. CI proxy: `hotpath-policy.sh` green every run. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter (set by planner once tasks carry verify commands)

**Approval:** pending
