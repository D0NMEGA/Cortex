---
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
plan: 01
subsystem: infra
tags: [rust, ffi, cbindgen, xcframework, swiftpm, binaryTarget, staticlib, loom, spsc, ci]

# Dependency graph
requires:
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
    provides: "CORTEX_CHANNEL_COUNT (cortex_shm.h), the f16/[ubyte] Sample layout (D-10), the Sample{ts_ns,seq,channel_data} fields (D-12), and the vendored-codegen drift-check pattern (D-13)"
  - phase: 01-foundation-2026-toolchain
    provides: "Xcode 26.3 + Swift 6.2 toolchain, project.yml/XcodeGen topology, the ci.yml 16-gate workflow + pre-armed-trap idiom (hotpath-policy.sh, SCM_RIGHTS grep)"
provides:
  - "cortex_ring Rust crate (staticlib+rlib) — the Swift↔Rust FFI spine and future loom/stress target"
  - "Frozen #[repr(C)] CortexFrame { ts_ns:u64, seq:u64, channel_data:[u16; 96] } layout-locked to CORTEX_CHANNEL_COUNT (compile-time static assert)"
  - "Frozen extern \"C\" ABI: cortex_ping + cortex_spsc_create/push/pop/destroy (stub bodies, catch_unwind panic guard) — Plans 02/04 build against this"
  - "CortexRingFFI.xcframework build chain (Tools/scripts/build-rust.sh) + SwiftPM .binaryTarget consuming it, callable from Swift under BOTH swift build AND xcodebuild"
  - "Vendored cbindgen header (Packages/CortexRing/rust/include/cortex_ring.h), CI drift-gated"
  - "All Phase-3 CI gates pre-armed on macos-15 (Rust toolchain install, xcframework build, loom, 1M-stress, cbindgen-drift, Swift-integration)"
affects: [03-02-ring-internals, 03-03-pthread-hot-path, 03-04-swift-integration, 06-renderer]

# Tech tracking
tech-stack:
  added:
    - "Rust 1.96.0 (rustup stable) + 5 Apple targets (aarch64/x86_64-apple-darwin, aarch64-apple-ios, aarch64-apple-ios-sim, x86_64-apple-ios)"
    - "cbindgen 0.29.4 (CLI via brew + [build-dependencies] 0.29)"
    - "loom 0.7 (cfg(loom)-gated, off production), criterion 0.5 + rtrb 0.3 (dev-deps, bench cross-check only)"
    - "SwiftPM .binaryTarget(xcframework) consumption pattern"
  patterns:
    - "In-house Rust staticlib → cbindgen C header → xcframework → SwiftPM .binaryTarget (zero .unsafeFlags; survives the swift build + xcodebuild dual build) — D-R1"
    - "Compile-time #[repr(C)] layout lock via const _: () = assert!(size_of::<Frame>() == ...) tying the Rust frame to the Phase-2 shared CORTEX_CHANNEL_COUNT — D-R6 / Pitfall #9"
    - "catch_unwind panic guard on every extern \"C\" body (no Rust unwind across the C frame) + #![deny(improper_ctypes_definitions)] — threat T-03-01-02"
    - "Vendored cbindgen header + CI git-diff --exit-code drift gate (mirrors the Phase-2 flatc D-13 pattern)"
    - "build-rust.sh as the documented `make bootstrap` analogue (gitignored xcframework built before resolve/xcodegen)"

key-files:
  created:
    - "Packages/CortexRing/rust/Cargo.toml — crate-type [staticlib,rlib], cbindgen build-dep, cfg(loom) loom dep, [profile.loom]"
    - "Packages/CortexRing/rust/src/frame.rs — frozen #[repr(C)] CortexFrame + size_of static assert"
    - "Packages/CortexRing/rust/src/ffi.rs — frozen extern \"C\" ABI (5 fns), stub bodies, catch_unwind guard"
    - "Packages/CortexRing/rust/src/lib.rs — #![deny(improper_ctypes_definitions)] + re-exports"
    - "Packages/CortexRing/rust/cbindgen.toml — language=C, include_guard, pragma_once, export include"
    - "Packages/CortexRing/rust/build.rs — cbindgen::generate → vendored include/cortex_ring.h"
    - "Packages/CortexRing/rust/include/cortex_ring.h — committed cbindgen header (the C contract Swift links)"
    - "Packages/CortexRing/rust/benches/throughput.rs — placeholder bench (Plan 02 fills)"
    - "Packages/CortexRing/Package.swift — .binaryTarget(CortexRingFFI) + CortexRingPing + tests"
    - "Packages/CortexRing/Sources/CortexRingPing/Ping.swift — cortexPing(value) over the C ABI"
    - "Packages/CortexRing/Tests/CortexRingTests/PingSmokeTests.swift — Spike-A round-trip + involution"
    - "Tools/scripts/build-rust.sh — cargo×5 targets → lipo fat macOS → xcodebuild -create-xcframework"
  modified:
    - ".github/workflows/ci.yml — 6 pre-armed Phase-3 Rust gates on macos-15"
    - "project.yml — register CortexRing under packages:"
    - ".gitignore — ignore rust/target + CortexRingFFI.xcframework (header IS committed)"
    - ".swiftformat — exclude Packages/CortexRing/.build"

key-decisions:
  - "cbindgen pinned to 0.29 (build-dep) to match the brew-installed 0.29.4 CLI used by the drift gate — supersedes the plan's 0.27 (identical generate()/write_to_file API + cbindgen.toml schema)"
  - "[[bench]] throughput needs benches/throughput.rs to exist for the manifest to parse — added an empty-main placeholder (harness=false) so cargo build/test succeed; Plan 02 fills it"
  - "Spike-A xcodebuild leg proven via `xcodebuild -scheme CortexRingPing` (BUILD SUCCEEDED, ProcessXCFramework + GeneratePcm CortexRingFFI) — the CortexMac scheme is blocked only by the pre-existing CortexIPC Float16 deferral (out of scope)"
  - "nm LLVM-version warnings (Rust 1.96/LLVM22 vs Xcode 26.3 nm/LLVM17) on Rust std objects are an nm-DISPLAY artifact only — ld links the archive cleanly (BUILD SUCCEEDED, zero ld: errors); the 5 cortex_* symbols still resolve under Xcode nm"

patterns-established:
  - "Rust crate as a SwiftPM-consumable binary artifact via xcframework .binaryTarget (the production Mozilla-Glean/uniffi path)"
  - "Compile-time ABI/layout freeze with const static asserts + #![deny(improper_ctypes_definitions)]"
  - "Pre-armed CI gates that pass on the skeleton and turn green when Wave-2/3 code lands (Phase-1 trap idiom extended to Rust)"

requirements-completed: [THREAD-06]

# Metrics
duration: 16min
completed: 2026-06-20
---

# Phase 3 Plan 01: Swift↔Rust FFI/Build Spine (Spike A) Summary

**Established the cortex_ring Rust staticlib → cbindgen C header → CortexRingFFI.xcframework → SwiftPM .binaryTarget chain, callable from Swift under BOTH `swift build` and `xcodebuild` with zero linker flags; froze the C ABI (cortex_ping + 4 ring fns) and the `#[repr(C)] CortexFrame` layout-locked to CORTEX_CHANNEL_COUNT; pre-armed all six Phase-3 Rust CI gates.**

## Performance

- **Duration:** ~16 min
- **Started:** 2026-06-20T22:50:45Z
- **Completed:** 2026-06-20T23:06:xxZ
- **Tasks:** 3 (all complete)
- **Files modified/created:** 18 tracked

## Accomplishments

- **Spike A retired the dominant Phase-3 risk (D-R1):** a Rust `extern "C"` function (`cortex_ping`) is callable from Swift through an xcframework `.binaryTarget` with NO `.unsafeFlags`, proven GREEN under BOTH `swift build`/`swift test` (2/2) AND `xcodebuild -scheme CortexRingPing` (BUILD SUCCEEDED).
- **Froze the C ABI surface for parallel downstream work:** `cortex_ping` + `cortex_spsc_create/push/pop/destroy` (stub bodies) and the `#[repr(C)] CortexFrame { ts_ns:u64, seq:u64, channel_data:[u16; 96] }`. Plans 02 (ring internals) and 04 (Swift integration) now build against a stable contract.
- **Layout-locked the Frame to the Phase-2 shared constant** with a compile-time `size_of` static assert (D-R6/D-11). Negative control proven: changing the array length to `CORTEX_CHANNEL_COUNT + 1` makes `cargo build` FAIL with `error[E0080]` before any test runs.
- **Panic-across-FFI guard (threat T-03-01-02):** every `extern "C"` body wraps in `catch_unwind` returning a safe default; `#![deny(improper_ctypes_definitions)]` at crate root.
- **loom pre-wired but cfg-gated off production** (`[target.'cfg(loom)'.dependencies] loom = "0.7"` + `[profile.loom]`), so Plan 02 lands the model checker without touching production linkage.
- **All six Phase-3 CI gates pre-armed on macos-15** (toolchain install + prove, xcframework build before resolve/xcodegen, 1M-stress, loom, cbindgen-drift, Swift-integration) — correctness/model only; the M4 SC#1 Instruments trace is deliberately left as manual hardware evidence (D-18). Verified locally on the skeleton: stress/loom/drift gates pass (0 tests / no drift), YAML valid.

## Task Commits

1. **Task 1: cortex_ring crate — frozen ABI, repr(C) Frame, panic guard, loom config** — `99f3c00` (feat)
2. **Task 2: build-rust.sh + xcframework + .binaryTarget + cortex_ping smoke (Spike A)** — `9ef752c` (feat)
3. **Task 3: pre-arm all Phase-3 CI gates** — `890875e` (ci)
4. **Lint fix (Rule 1): swiftformat/swiftlint on the Swift glue** — `93ab143` (style)

**Plan metadata:** (final docs commit — this SUMMARY + deferred-items.md)

## Frozen ABI (cite from Plans 02/04)

```rust
// Packages/CortexRing/rust/src/frame.rs
pub const CORTEX_CHANNEL_COUNT: usize = 96;          // == cortex_shm.h CORTEX_CHANNEL_COUNT (D-11)
#[repr(C)] #[derive(Clone, Copy)]
pub struct CortexFrame { pub ts_ns: u64, pub seq: u64, pub channel_data: [u16; CORTEX_CHANNEL_COUNT] }
const _: () = assert!(core::mem::size_of::<CortexFrame>() == 16 + CORTEX_CHANNEL_COUNT * 2);

// Packages/CortexRing/rust/src/ffi.rs  (stub bodies in this plan; Plan 02 fills the real algorithm)
#[repr(C)] pub struct CortexSpsc { _private: [u8; 0] }   // opaque handle
#[no_mangle] pub extern "C" fn cortex_ping(x: u32) -> u32;                              // x ^ 0x5A5A_5A5A
#[no_mangle] pub extern "C" fn cortex_spsc_create(capacity: usize) -> *mut CortexSpsc;  // capacity = power-of-two (Plan 02)
#[no_mangle] pub extern "C" fn cortex_spsc_push(r: *mut CortexSpsc, f: *const CortexFrame) -> bool; // false = full
#[no_mangle] pub extern "C" fn cortex_spsc_pop(r: *mut CortexSpsc, out: *mut CortexFrame) -> bool;   // false = empty
#[no_mangle] pub extern "C" fn cortex_spsc_destroy(r: *mut CortexSpsc);
```

Swift consumes these via `import CortexRingFFI` (the xcframework modulemap). The Swift wrapper is `cortexPing(_ value: UInt32) -> UInt32` in `CortexRingPing`.

## Toolchain / Bootstrap (FOUND-04 clean-clone caveat)

- **rustup** installed via `brew install rustup` → `rustup default stable` (Rust 1.96.0). Homebrew's rustup does NOT symlink `cargo`/`rustc` onto PATH; this executor linked the `/opt/homebrew/opt/rustup/bin` shims into `/opt/homebrew/bin` so `command -v cargo` resolves. (CI uses `rustup-init -y` + `$GITHUB_PATH` instead — see ci.yml.)
- **5 Apple targets:** `aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios` (the host x86_64 covers an Intel macos-15 runner).
- **cbindgen 0.29.4** via `brew install cbindgen` (matches the `[build-dependencies] cbindgen = "0.29"` pin).
- **The xcframework is the `make bootstrap` analogue:** it is gitignored, so a fresh clone (and CI) must run `Tools/scripts/build-rust.sh` BEFORE `swift package resolve`/`xcodegen`. `build-rust.sh` prints an explicit bootstrap hint and exits 1 if `cargo` is absent (not a silent break). The CI step ordering enforces this.

## Files Created/Modified

See `key-files` frontmatter. Highlights:
- `Packages/CortexRing/rust/` — the crate (Cargo.toml, src/{lib,frame,ffi}.rs, build.rs, cbindgen.toml, include/cortex_ring.h, benches/throughput.rs, Cargo.lock).
- `Packages/CortexRing/{Package.swift, Sources/CortexRingPing/Ping.swift, Sources/CortexRingFFI/.gitkeep, Tests/CortexRingTests/PingSmokeTests.swift}`.
- `Tools/scripts/build-rust.sh` — the xcframework assembler (3 slices: macos-arm64_x86_64, ios-arm64, ios-arm64-simulator).
- `.github/workflows/ci.yml`, `project.yml`, `.gitignore`, `.swiftformat`.

## Decisions Made

- **cbindgen 0.29 not 0.27:** brew ships cbindgen 0.29.4; pinning the build-dep to 0.29 keeps the build.rs-generated header byte-identical to what the drift gate's CLI regenerates. The `generate()`/`write_to_file()` API and `cbindgen.toml` schema are identical across 0.27→0.29 (Context7-verified). (Rule 3 — blocking version skew.)
- **Empty placeholder bench:** `[[bench]] throughput` in Cargo.toml makes cargo require `benches/throughput.rs` to parse the manifest; added an empty-`main` (`harness=false`) placeholder so `cargo build`/`test` succeed now. Plan 02 fills it with the real throughput + `rtrb` cross-check. (Rule 3.)
- **`.gitignore` rust/target added in Task 1** (not deferred to Task 2) so the 17 MB `target/` was never staged in the Task-1 commit. The xcframework gitignore entry (a Task-2 deliverable) was added in the same edit. (Rule 3.)
- **Spike-A xcodebuild leg via `-scheme CortexRingPing`** rather than `-scheme CortexMac`: CortexMac transitively pulls in CortexDaemon→CortexIPCSession, which hits the **pre-existing** `Float16 is unavailable in macOS` xcodebuild deferral (Plan 02-05). `xcodebuild -scheme CortexRingPing` exercises the identical xcframework link path and reports BUILD SUCCEEDED, so the FFI spine is proven without touching out-of-scope code.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pinned cbindgen 0.29 (plan said 0.27) to match the available toolchain**
- **Found during:** Task 1 (crate skeleton)
- **Issue:** The plan's `Cargo.toml` pins `cbindgen = "0.27"`, but the current stable line installed via `brew install cbindgen` is 0.29.4; a 0.27 build-dep vs 0.29 CLI could drift the generated header and fail the Task-3 drift gate.
- **Fix:** Pinned `[build-dependencies] cbindgen = "0.29"`. Verified the `generate()`/`write_to_file()` API and `cbindgen.toml` schema (language=C, include_guard, pragma_once, export.include) are unchanged via Context7.
- **Files modified:** Packages/CortexRing/rust/Cargo.toml
- **Verification:** `cargo build --release` regenerates the header; drift gate (`git diff --exit-code`) returns 0.
- **Committed in:** `99f3c00`

**2. [Rule 3 - Blocking] Added benches/throughput.rs placeholder so the manifest parses**
- **Found during:** Task 1 (first `cargo build`)
- **Issue:** `cargo build` failed: "can't find `throughput` bench at `benches/throughput.rs`" — the `[[bench]]` target the plan pre-wires for Plan 02 makes cargo require the file to parse the manifest.
- **Fix:** Created `benches/throughput.rs` with an empty `main` (`harness = false`). Plan 02 fills it with the real throughput + `rtrb` cross-check benchmark.
- **Files modified:** Packages/CortexRing/rust/benches/throughput.rs (new)
- **Verification:** `cargo build --release` and `cargo test --release` both exit 0.
- **Committed in:** `99f3c00`

**3. [Rule 3 - Blocking] Added Rust build-artifact .gitignore entries in Task 1**
- **Found during:** Task 1 (pre-commit)
- **Issue:** `.gitignore` (a Task-2 file) had no `rust/target/` entry; committing Task 1 would have staged ~17 MB of build output.
- **Fix:** Added `Packages/CortexRing/rust/target/` (Task-1 need) and `Packages/CortexRing/CortexRingFFI.xcframework/` (Task-2 deliverable) to `.gitignore` in one edit.
- **Files modified:** .gitignore
- **Verification:** `git check-ignore` confirms `target/`+xcframework excluded; the committed cbindgen header is NOT ignored (D-13).
- **Committed in:** `99f3c00`

**4. [Rule 1 - Bug] Reformatted CortexRing Swift to pass the existing swiftformat/swiftlint gates**
- **Found during:** SUMMARY prep (running the repo's actual `swiftformat --lint`/`swiftlint --strict` CI commands)
- **Issue:** My new Swift files failed the existing lint gates: missing trailing commas + unformatted `@Test` names (swiftformat) and single-char `x` identifiers (swiftlint identifier_name ≥3 chars). The Task-3 CI scaffold runs `swift test --package-path Packages/CortexRing` alongside the existing repo-wide `swiftformat --lint .`/`swiftlint --strict`, so my files had to pass.
- **Fix:** Applied the project `.swiftformat` (autofix → backtick-identifier `@Test` names, trailing commas, `self` removal), renamed `x`→`value`/`input`, and added `Packages/CortexRing/.build` to the `.swiftformat` exclude (mirrors the other packages).
- **Files modified:** Package.swift, Ping.swift, PingSmokeTests.swift, .swiftformat
- **Verification:** `swiftformat --lint` (0/3) + `swiftlint --strict` (0 violations) on my files; `swift test` still 2/2 green.
- **Committed in:** `93ab143`

---

**Total deviations:** 4 auto-fixed (3 blocking, 1 bug). **Impact:** All necessary for a building, gate-clean skeleton. No scope creep — every change stays within the FFI/build-spine remit.

## Issues Encountered

- **xcodegen produces no standalone `Cortex.xcworkspace`** (only the embedded `project.xcworkspace`); the existing CI's `-workspace Cortex.xcworkspace` invocation is affected equally on the base commit. Worked around for local Spike-A verification by using `-project Cortex.xcodeproj`/`-scheme CortexRingPing`. Logged to deferred-items.md (pre-existing, not Plan-03-01 scope).
- **`nm` LLVM-version warnings** on Rust std/compiler_builtins objects (Rust 1.96/LLVM22 vs Xcode 26.3 nm/LLVM17). Confirmed display-only: the 5 `cortex_*` symbols still resolve under Xcode `nm`, and `xcodebuild` links the archive cleanly (BUILD SUCCEEDED, zero `ld:` errors). Worth noting for Plan 02/04 (`nm`-based checks are noisy; the link/test gates are authoritative).
- **Pre-existing repo-wide lint debt** (`swiftformat --lint .` reports 34/40 files, e.g. Benchmark.swift) and the **pre-existing CortexIPC `Float16` xcodebuild deferral** are both present on base `2a0b42a` and out of scope; logged to deferred-items.md.

## Out-of-Scope / Deferred

See `.planning/phases/03-real-time-threading-pthread-user-interactive-rust-spsc-ring/deferred-items.md`:
1. Pre-existing CortexIPC `Float16` xcodebuild error (Plan 02-05).
2. xcodegen standalone-workspace gap in the existing CI xcodebuild steps.
3. Pre-existing repo-wide swiftformat/swiftlint debt.

## Threat Surface

No new attack surface beyond the plan's `<threat_model>` (Swift→Rust C ABI, Rust panic→C, build-rust.sh→xcframework). `cortex_ping` is pure arithmetic (no secret); build-rust.sh logs only target triples + tool versions; the xcframework is built in-CI/locally from in-repo source (not a downloaded blob) and gitignored. Mitigations applied as planned: T-03-01-01 (size_of static assert — negative control proven), T-03-01-02 (catch_unwind on every extern "C" body), T-03-01-03 (vendored header + CI drift gate). No `threat_flag` raised.

## User Setup Required

None — no external service configuration. The only setup is the Rust toolchain bootstrap (`brew install rustup cbindgen` + `rustup target add …`), already installed locally and wired into ci.yml; documented as the `make bootstrap` analogue in build-rust.sh.

## Next Phase Readiness

- **Plan 02 (ring internals):** the crate, the `crate::loom` swap point (Cargo.toml `cfg(loom)` + `[profile.loom]`), the frozen ABI, and the loom/stress/bench CI gates are ready. Plan 02 adds `src/loom.rs` + `src/spsc.rs`, fills the 5 ABI bodies, and lands the loom permutation test + 1M-frame stress test + the real `benches/throughput.rs`.
- **Plan 04 (Swift integration):** `import CortexRingFFI` + the `cortexPing` precedent show the consumption pattern; the produce→pop integration test slots into the pre-armed "Swift integration" CI gate.
- **Concern:** the CI Rust gates have NOT yet been exercised by a real macos-15 run (same "gate armed — first PR exercises it" status as the Phase-1 gates). The first PR after this lands will be the first true end-to-end CI proof of the Rust toolchain install + xcframework build on the runner.

## Self-Check: PASSED

- All 20 claimed files verified present on disk (crate sources, header, Swift glue, build-rust.sh, ci.yml, project.yml, .gitignore, .swiftformat, SUMMARY, deferred-items).
- All 4 commit hashes verified in git history: `99f3c00` (Task 1), `9ef752c` (Task 2), `890875e` (Task 3), `93ab143` (lint fix).

---
*Phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring*
*Completed: 2026-06-20*
