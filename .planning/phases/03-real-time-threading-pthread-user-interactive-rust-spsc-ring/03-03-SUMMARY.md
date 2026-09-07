---
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
plan: 03
subsystem: infra
tags: [pthread, qos, user-interactive, swift, ffi, rust, spsc, hotpath, static-analysis, instruments, audio-callback]

# Dependency graph
requires:
  - phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring (Plan 01)
    provides: "CortexRingFFI xcframework + frozen C ABI (cortex_spsc_create/push/pop/destroy, #[repr(C)] CortexFrame{ts_ns,seq,channel_data:[u16;96]}, CortexSpsc opaque handle) consumed via `import CortexRingFFI`"
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
    provides: "Benchmark.swift pthread+QoS idiom (D-R2) productionized here; the Foundation-free CortexIPCTransport hot-path-target precedent; the sc1/sc2-evidence.md hardware-gated-evidence pattern; the Float16 xcodebuild deferral"
  - phase: 01-foundation-2026-toolchain
    provides: "hotpath-policy.sh pre-armed gate (its own comment anticipated the Phase-3 DIRS_ARRAY extension); the Plan 01-06 DIRS=/tmp/synthetic self-test; project.yml/XcodeGen topology"
provides:
  - "CortexRingHotPath SwiftPM target/product — the Foundation-free pthread USER_INTERACTIVE acquisition producer (CortexAcquisition.run + the @convention(c) cortexAcquisitionThread)"
  - "The real hot path: raw pthread_create worker, QOS_CLASS_USER_INTERACTIVE pinned first, no-alloc/no-lock produce loop pushing CortexFrames into the Rust ring over cortex_spsc_push (THREAD-01/02/03)"
  - "Extended hotpath-policy.sh (SC#2/D-R7): policies CortexRingHotPath + the Rust ring sources (rust/src/{spsc,ffi}.rs) for Mutex/RwLock/.lock(/println!(/panic!( plus the existing Swift/C token set, with a 3-language negative-control self-test"
  - "instruments-evidence.md — the SC#1 M4 System-Trace runbook (zero swift_task_*/libdispatch on the worker), with hotpath-policy.sh as its always-on CI proxy"
  - "D-R8 / Phase 2 D-06 RESOLVED: AES-GCM is OFF this hot path — the SPSC ring is the decoupling boundary"
affects: [03-04-swift-integration, 04-decoder-pipeline, 06-renderer]

# Tech tracking
tech-stack:
  added:
    - "(no new dependency) — CortexRingHotPath depends only on the existing CortexRingFFI xcframework + Darwin"
  patterns:
    - "Productionized Benchmark.swift pthread idiom: top-level @convention(c) entry with a NON-OPTIONAL UnsafeMutableRawPointer arg (the Swift-6 SendNonSendable-crash workaround), POD AcqThreadArg, unretained *mut CortexSpsc handle, QOS_CLASS_USER_INTERACTIVE pinned as the first action"
    - "Foundation-free Swift hot-path target (import Darwin only, no .defaultIsolation(MainActor.self)) — the CortexIPCTransport precedent extended to the in-process ring producer"
    - "Static-analysis hot-path gate with DISTINCT Swift/C and Rust token sets; Rust tokens matched in CALL form (.lock( / println!( / panic!() so the gate bites on invocations, not doc-comment prose; skip-if-missing on not-yet-created files"
    - "Hardware-gated manual evidence (Instruments) + always-on CI structural proxy (the policy gate) — the D-18 split, third instance (after Phase-1 SC#2, Phase-2 SC#1)"

key-files:
  created:
    - "Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift — the pthread USER_INTERACTIVE acquisition worker (CortexAcquisition.run + cortexAcquisitionThread)"
    - ".planning/phases/03-real-time-threading-pthread-user-interactive-rust-spsc-ring/instruments-evidence.md — SC#1 M4 System-Trace runbook"
  modified:
    - "Packages/CortexRing/Package.swift — added the CortexRingHotPath target + library product (Wave-1 CortexRingFFI/CortexRingPing untouched)"
    - "Tools/scripts/hotpath-policy.sh — DIRS_ARRAY + .rs scan + RUST_HOTPATH_FILES/RUST_FORBIDDEN + --self-test (D-R7)"
    - "project.yml — CortexDaemon depends on the CortexRingHotPath product"
    - ".planning/phases/03-.../deferred-items.md — added the SC#1 System-Trace manual-capture deferral row"

key-decisions:
  - "Rust forbidden tokens matched in CALL form (.lock( / println!( / panic!() not the bare word, so the gate ignores ffi.rs's catch_unwind panic-across-FFI doc comment (which would false-positive the clean tree) while still biting on a real macro invocation — mirrors the plan's own .lock( token form"
  - "Ring-full policy = bounded busy-spin + RETRY the same frame (no sequence skipped), so the FIFO/no-loss invariant the Plan-02 stress test asserts holds end-to-end; lock-free and allocation-free"
  - "CortexFrame zero-initialized via raw-byte fill (the C fixed array imports as a 96-UInt16 tuple — no Swift array literal); synthetic zeroed channel_data of the correct stride this phase (real O'Doherty spikes land Phase 4)"
  - "hotpath-policy.sh skips not-yet-existing Rust files (spsc.rs lands in Plan 02) so the gate stays green before AND after the parallel 03-02 work — clean merge by construction"
  - "@convention(c) entry takes a NON-OPTIONAL UnsafeMutableRawPointer (Benchmark.swift anomaly #1): an optional arg crashes the Swift-6 SendNonSendable SIL pass"

patterns-established:
  - "Foundation-free pthread USER_INTERACTIVE worker over a C-ABI ring — the production template for every hot-path producer (Phase 4 spike source, Phase 6 consumer driving)"
  - "3-language (.swift/.c/.rs) negative-control self-test in the hot-path gate, proving it bites on every forbidden token"

requirements-completed: [THREAD-01, THREAD-02, THREAD-03]

# Metrics
duration: 10min
completed: 2026-06-20
---

# Phase 3 Plan 03: pthread USER_INTERACTIVE Acquisition Hot Path Summary

**The real acquisition hot path now runs on a raw pthread pinned to `QOS_CLASS_USER_INTERACTIVE`, Foundation-free (`import Darwin`), pushing `CortexFrame`s into the Rust SPSC ring over the frozen C ABI with no ARC/dispatch/Task/locks/allocation on the loop — the productionized Benchmark.swift idiom — and the static-analysis gate now polices it (and the Rust ring sources) across Swift/C/Rust with a 3-language negative-control self-test.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-06-20T23:12:40Z
- **Completed:** 2026-06-20T23:22:xxZ
- **Tasks:** 3 (all complete)
- **Files modified/created:** 5 (2 created, 3 modified)

## Accomplishments

- **The audio-callback-regime hot path is real (THREAD-01/02/03; SC#1 structural):** `Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift` lifts the proven `Benchmark.swift` pthread idiom (D-R2) from "benchmark" to "the production acquisition producer." A raw `pthread_create` worker calls `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` as its **first** action, then runs an allocation-free, lock-free produce loop that stamps a cached-timebase `mach_absolute_time` `ts_ns` + monotonic `seq` into one reused `CortexFrame` and calls `cortex_spsc_push` (a C call — no ARC/dispatch/Task). `import Darwin` only — never Foundation.
- **The Swift-6 boundary contract is honored:** a POD `AcqThreadArg` (raw handles + Ints) crosses the `@convention(c)` boundary and the entry takes a **non-optional** `UnsafeMutableRawPointer` — the exact shape `Benchmark.swift`/`sc1-evidence.md` anomaly #1 documents as the workaround for the Swift-6 `SendNonSendable` SIL-pass crash. The ring is reconstructed from an **unretained** `*mut CortexSpsc` handle (no ARC).
- **The static-analysis gate (SC#2/D-R7) now covers the new hot path AND the Rust ring sources:** `hotpath-policy.sh` adds `CortexRingHotPath` to `DIRS_ARRAY`, adds `--include='*.rs'`, and adds a distinct Rust token set (`Mutex`/`RwLock`/`.lock(`/`println!(`/`panic!(`) scoped to `rust/src/{spsc,ffi}.rs`. The extended `--self-test` injects **every** forbidden token across `.swift`/`.c`/`.rs` (5 Swift + 1 C + 5 Rust) and asserts the gate exits 1 on each, then asserts a clean tree exits 0. This is SC#1's always-on CI proxy.
- **SC#1 captured as hardware-gated manual evidence:** `instruments-evidence.md` mirrors `sc1-evidence.md`/`sc2-evidence.md` — the SC#1 claim (zero `swift_task_*`/libdispatch frames on the worker under load), the why-manual rationale, the exact M4 System-Trace runbook, the pass criterion + the policy-gate negative control cross-referenced to Task 2. The `.trace` capture is a deferred manual M4/M5 step (the D-18 precedent); the runbook + the CI proxy are the committed deliverable.
- **D-R8 / Phase 2 D-06 CLOSED:** AES-GCM is **not** on this hot path — the SPSC ring is the decoupling boundary; the worker does zero crypto. Stated in `Acquisition.swift`, `instruments-evidence.md`, and here.
- **Integration proven both build legs:** `swift build`/`-c release` AND `xcodebuild` both compile `CortexRingHotPath/Acquisition.swift` and `ProcessXCFramework` links `libcortex_ring.a` into the daemon. `swiftformat --lint` (0/1) + `swiftlint --strict` (0 errors) + `CortexRing` tests 2/2.

## Task Commits

Each task was committed atomically (`--no-verify`, per the parallel-executor protocol — the orchestrator validates hooks once after all wave agents complete):

1. **Task 1: pthread USER_INTERACTIVE acquisition worker pushing to the Rust ring** — `b750baa` (feat)
2. **Task 2: extend hotpath-policy gate to CortexRingHotPath + .rs ring sources (SC#2, D-R7)** — `40a0da1` (feat)
3. **Task 3: wire CortexRingHotPath into CortexDaemon + author SC#1 instruments runbook** — `2f0cef7` (feat)

**Plan metadata:** (final docs commit — this SUMMARY + the deferred-items.md row)

## How the worker differs from Benchmark.swift (the productionization)

| Aspect | Benchmark.swift (Plan 02-05) | Acquisition.swift (this plan) |
|--------|------------------------------|-------------------------------|
| Purpose | MEASURE sub-µs round-trip (SC#1 timing) | PRODUCE frames into the in-process ring (the real hot path) |
| Channel | Phase-2 cross-process `ShmRing` (write + ack-bounce) | Phase-3 in-process Rust SPSC ring (`cortex_spsc_push` over the C ABI) |
| Topology | producer ↔ consumer ack-bounce (two threads, timed) | producer → ring → (Phase-6 CAMetalDisplayLink consumer) |
| Handle | unretained `Unmanaged<ShmRing>` (a Swift class) | unretained `*mut CortexSpsc` (a raw C handle — no Swift object at all) |
| Foundation | Apps-target, `import Foundation` allowed (CSV/histogram write) | Foundation-FREE target, `import Darwin` only (gate-policed) |
| Crypto | off the timed path (D-01) | off the path entirely (D-R8 — the ring decouples) |

Shared (the load-bearing idiom carried forward verbatim): raw `pthread_create`/`pthread_join`, `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)` first, POD thread arg, non-optional `@convention(c)` entry, cached-timebase `mach_absolute_time`, zero allocation on the loop.

## Files Created/Modified

- `Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift` (new, 213 lines) — `CortexAcquisition.run(ring:frames:fullBackoffSpins:)` + the `@convention(c)` `cortexAcquisitionThread` + the cached-timebase timer. D-R8 + audio-callback-rules header.
- `Packages/CortexRing/Package.swift` (+15) — added `.target(CortexRingHotPath, deps:[CortexRingFFI])` + `.library(CortexRingHotPath)`. Wave-1 `CortexRingFFI` binaryTarget / `CortexRingPing` untouched.
- `Tools/scripts/hotpath-policy.sh` (+241/−34) — `DIRS_ARRAY` += `CortexRingHotPath`; `--include='*.rs'`; `RUST_HOTPATH_FILES`/`RUST_FORBIDDEN` (call-form tokens); `scan_tree` (also Rust-scans `.rs` inside policed dirs); `--self-test` (3-language negative control); `RUST_FILES`/`DIRS` overrides for the self-test.
- `project.yml` (+8) — `CortexDaemon.dependencies` += `{package: CortexRing, product: CortexRingHotPath}`.
- `.planning/phases/03-.../instruments-evidence.md` (new, 153 lines) — SC#1 System-Trace runbook.
- `.planning/phases/03-.../deferred-items.md` (+1 row) — SC#1 `.trace` manual-capture deferral.

## Decisions Made

- **Rust tokens matched in CALL form (`.lock(` / `println!(` / `panic!(`), not the bare word.** The committed `ffi.rs` (03-01) documents "a `panic!` unwinding across an `extern "C"` frame is UB" in a doc comment and wraps every body in `catch_unwind`. A bare-word `panic!` token would false-positive that clean, intentional documentation and fail my own "gate exits 0 on the real tree" acceptance criterion. The call form is also the more accurate invariant ("no panic/println **call** on the hot path") and mirrors the `.lock(` token the plan itself lists. The negative-control self-test injects the call forms (`println!("x")`, `panic!("x")`), so the gate is still proven to bite. (See Deviations — Rule 1.)
- **The gate also Rust-scans `.rs` files found inside a policed `DIRS` dir** (in addition to the dedicated `rust/src/{spsc,ffi}.rs` list) — this is what the plan's verify command exercises (`DIRS=$tmp` + a `bad.rs` containing `println!`). The dedicated file list polices the ring sources (which live in `rust/src/`, not under a Swift dir); the dir scan catches a `.rs` dropped into a hot-path dir. Token sets stay distinct (Swift/C vs Rust).
- **Ring-full → bounded busy-spin + retry the SAME frame** (no `seq` skipped), so the Plan-02 1M-frame FIFO/no-loss stress assertion holds end-to-end through the producer. Lock-free, allocation-free.
- **`CortexFrame` zero-initialized via raw-byte fill.** cbindgen emits `channel_data` as a C fixed array, which Swift imports as a 96-`UInt16` tuple (no array-literal init possible Foundation-free); allocating one `CortexFrame` and zero-filling its bytes is the clean stride-correct construction. Synthetic zeroed payload this phase — real spikes Phase 4.
- **`hotpath-policy.sh` skips not-yet-existing files.** `spsc.rs` is created by the parallel 03-02 agent; the skip-if-missing keeps the gate green before/after it lands and guarantees a clean merge (my lane = Swift/build; 03-02's lane = `rust/**`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rust forbidden tokens policed in CALL form to avoid false-positives on ffi.rs's panic-across-FFI doc comment**
- **Found during:** Task 2 (extending the gate)
- **Issue:** The plan's `.rs` token list is written `…/println!/panic!`. Policing the bare word `panic!` (via `grep -F`) would match line 7 of the committed `Packages/CortexRing/rust/src/ffi.rs` (`//! A Rust panic! unwinding across an extern "C" frame … is UB`) — a clean, intentional doc comment — making `./Tools/scripts/hotpath-policy.sh` exit 1 on the real tree and violating the Task-2 acceptance criterion that it exit 0. (`ffi.rs` is owned by the parallel 03-02 agent / 03-01; I must not edit it.)
- **Fix:** Police the **call forms** `println!(` and `panic!(` (open-paren), mirroring the `.lock(` token the plan itself lists. This bites on a real macro **invocation**, not the word in prose, and is the more accurate hot-path invariant. The negative-control self-test injects `println!("x")`/`panic!("x")`, so the gate is still proven to bite on every token; the plan's verify command (`println!("no")` in a temp `.rs`) still triggers exit 1.
- **Files modified:** Tools/scripts/hotpath-policy.sh
- **Verification:** real tree exit 0; `--self-test` all-pass (11 tokens + clean); plan verify command emits `CLEAN_PASS`/`RUST_TOKEN_BITES`/`SWIFT_TOKEN_BITES`.
- **Committed in:** `40a0da1` (Task 2 commit)

**2. [Rule 1 - Bug] Reworded Acquisition.swift forbidden-token comments to prose so the gate stays green on this file**
- **Found during:** Task 1 (verify) — the same intent-vs-literal-token trap `Benchmark.swift`/Plan 02-04 document.
- **Issue:** My explanatory comments literally contained `dispatch_async`, `lazy var`, `pthread_mutex`, `import Foundation`, `import ObjectiveC`, `DispatchQueue`, `Task {`, `NSLog` (describing what the hot path avoids). `hotpath-policy.sh` greps the **whole file** (it cannot read intent), so these comments would make the gate (Task 2) bite on the very file it polices.
- **Fix:** Reworded each comment to describe the forbidden constructs in prose (e.g. "the libdispatch async-enqueue call", "lazily-initialized storage") without the literal tokens — the documented `Benchmark.swift`/Plan 02-04 discipline. Intent preserved and explicitly noted in the file header.
- **Files modified:** Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift
- **Verification:** all 5 Swift/C `grep -F` tokens absent from the file; the gate is clean on `CortexRingHotPath`.
- **Committed in:** `b750baa` (Task 1 commit)

**3. [Rule 1 - Bug] swiftformat/swiftlint conformance on Acquisition.swift (the Plan 03-01 lint precedent)**
- **Found during:** Task 1 (running the repo's actual `swiftformat --lint`/`swiftlint --strict` CI commands)
- **Issue:** New file failed the existing repo-wide lint gates: `#if arch(arm64)` block indentation (swiftformat `indent`) and single/double-char identifiers `a`/`rc` (swiftlint `identifier_name` ≥3 chars). The CI runs `swiftformat --lint .` + `swiftlint --strict` repo-wide (03-01 SUMMARY).
- **Fix:** `swiftformat` autofix (indented the `#if` body); renamed `a`→`args`, `rc`→`createResult`.
- **Files modified:** Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift
- **Verification:** `swiftformat --lint` 0/1; `swiftlint --strict` 0 errors; `swift build` + tests 2/2 still green.
- **Committed in:** `b750baa` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (all Rule 1 — bug/false-positive avoidance). **Impact:** all necessary for a building, gate-clean, lint-clean hot path; no scope creep — every change stays within the Swift/build remit (no `rust/**` touched, the 03-02 agent's lane untouched).

## Known Stubs

- **`CortexFrame.channel_data` synthetic zeroed payload** (`Acquisition.swift`, the produce loop). The worker stamps a real monotonic `ts_ns`/`seq` but writes a **zeroed** channel payload of the correct stride (`CORTEX_CHANNEL_COUNT` u16) this phase. This is **intentional and documented**: real O'Doherty Indy/Loco spike data arrives in **Phase 4** (Decoder Pipeline — "Training loop on O'Doherty Indy/Loco synthetic spike replay"). The stub does NOT block the plan's goal (SC#1 = the threading regime + the ring push, which the synthetic frame exercises at the correct layout/stride). Resolved by Phase 4 wiring the acquisition source into the worker.

## Threat Surface

No new attack surface beyond the plan's `<threat_model>`. Mitigations applied as planned:
- **T-03-03-01** (ARC/region-analysis crash on the boundary): POD `AcqThreadArg` of raw handles + non-optional `@convention(c)` entry + `assumingMemoryBound` unretained handle. ✓
- **T-03-03-02** (cooperative-runtime/Foundation creep): `import Darwin` only + the extended gate biting on every forbidden token across Swift/C/Rust (self-test proven). ✓
- **T-03-03-03** (silent SC#1 regression between manual M4 captures): the always-on policy gate is the CI proxy, cross-referenced in `instruments-evidence.md`. ✓
- **T-03-03-04** (use-after-free of the unretained ring handle): `CortexAcquisition.run` `pthread_join`s before returning (caller holds the strong ring reference for the worker's whole lifetime). ✓

The path carries no PII/secret this phase (synthetic frame; AES-GCM deliberately OFF per D-R8). No `threat_flag` raised.

## Issues Encountered

- **`xcodebuild -scheme CortexDaemon` BUILD FAILED on the pre-existing `Float16` deferral.** The failure is `'Float16' is unavailable in macOS` in `CortexIPCSession/{HarnessConsumer,SampleCodec}.swift` (the `x86_64-apple-macos10.14` slice) — the **pre-existing** Plan 02-05 deferral already tracked in STATE/deferred-items, NOT my code. **My wiring is proven correct regardless:** the build log shows `Target 'CortexRingHotPath'` is an explicit CortexDaemon dependency, `Acquisition.swift` SwiftCompiles cleanly for both arm64 + x86_64, and `ProcessXCFramework CortexRingFFI.xcframework → libcortex_ring.a` runs (the hot-path product + xcframework link end-to-end). `swift build -c release` of the whole CortexRing package also links them green. This is the documented "toolchain/config-deferral closed by CI" disposition the Task-3 acceptance criterion explicitly permits.

## User Setup Required

None — no external service configuration. (Rust toolchain bootstrap `Tools/scripts/build-rust.sh` is the existing Plan-01 `make bootstrap` analogue; already installed locally + in ci.yml.)

## Next Phase Readiness

- **Plan 03-04 (Swift integration):** `CortexAcquisition.run(ring:frames:)` is the producer; once Plan 02 fills the real `cortex_spsc_push`/`pop` bodies, the SC#4 integration test can create a ring via the C ABI, run this worker on one thread, and pop+verify (value + monotonic `seq`) on another. The worker's bounded `frames` arg and ring-full retry-same policy make a deterministic produce→pop test straightforward.
- **Parallel 03-02 (Rust ring internals):** clean-merge by construction — I touched zero `rust/**` files; the gate skips the not-yet-existing `spsc.rs` and Rust-scans `ffi.rs` (clean). When 03-02 lands `spsc.rs`, the gate automatically begins policing it (and the Plan-02 stress test exercises the FIFO/no-loss the worker's retry-same policy upholds).
- **Phase 6 (renderer):** the C ABI is shaped so a `CAMetalDisplayLink` callback can drive the consumer (`cortex_spsc_pop`) — RENDER SC#4's synthetic cursor-velocity stream from this ring.
- **Concern (carry-forward):** the `.trace` System-Trace capture is deferred to an M4/M5 Instruments session (deferred-items + the runbook); the structural SC#1 guarantee is in force every CI run via the gate in the meantime. The pre-existing `Float16` xcodebuild deferral still blocks a full `-scheme CortexDaemon` BUILD SUCCEEDED (owned by a Plan-02-05 follow-up).

## Self-Check: PASSED

- All 7 claimed files verified present on disk (Acquisition.swift, Package.swift, hotpath-policy.sh, project.yml, instruments-evidence.md, 03-03-SUMMARY.md, deferred-items.md).
- All 3 task commit hashes verified in git history: `b750baa` (Task 1), `40a0da1` (Task 2), `2f0cef7` (Task 3).
- Overall verification re-run green: `swift build` CortexRing PASS; `hotpath-policy.sh` real-tree exit 0 + `--self-test` all-pass; QoS+push present / Foundation+Task+dispatch_async+NSLog absent in Acquisition.swift; instruments-evidence.md has System Trace + swift_task pass criterion.

---
*Phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring*
*Completed: 2026-06-20*
