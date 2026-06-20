# Phase 3 Research — Real-Time Threading (pthread USER_INTERACTIVE + Rust SPSC Ring)

**Researched:** 2026-06-20 (main-thread browser-harness + scraper pass per project AGENTS.md — browser-harness cannot run in a GSD subagent, so this RESEARCH.md is pre-staged so `plan-phase` skips the HTTP-only subagent researcher)
**Phase requirements:** THREAD-01 … THREAD-07
**Method:** browser-harness `http_get` (loom/rtrb/cbindgen READMEs, branchout.dev cbindgen→Swift, strathweb Rust→Swift macOS, thingbuf loom shim) + `research_topic.py` multi-source digest + in-repo precedent analysis. Context7 has **no** Rust `loom`/`rtrb`/`cbindgen` coverage (verified — all "loom" hits are the video product / Gradle plugin), so crate READMEs + docs.rs are the primary sources here.

## RESEARCH COMPLETE

---

## 0. The single most important finding (read this first)

**Phase 3 introduces the first Rust into a Swift+C / XcodeGen / `macos-15`-CI repo. There is no `cargo` or `cbindgen` on the machine or in CI today** (verified: `command -v cargo` → not found). The dominant risk is **not** the ring algorithm — it is the **Swift↔Rust build integration across the dual build** (`swift build --package-path` *and* `xcodebuild -scheme`, both run in CI). De-risk that with a hello-world FFI spike **before** writing the real ring (§3, §7-Spike-A), exactly as Phase 2 spiked CF#1/CF#3 before building the transport.

**Second most important finding — a literal contradiction in SC#3 that the planner MUST resolve up front:** SC#3 says *"Rust `rtrb` SPSC ring … under `loom` permutation testing."* **You cannot run `loom` on `rtrb`.** `loom` only instruments code that imports `loom::sync::atomic` / `loom::cell::UnsafeCell` under `#[cfg(loom)]`; `rtrb` is a third-party crate built on `core::sync::atomic` and is tested with **Miri + ThreadSanitizer, not loom** (confirmed in rtrb's own README). The roadmap's *intent* is "a loom-verified, rtrb-quality SPSC ring." Satisfying that intent requires an **in-house SPSC ring with cfg(loom)-swappable atomics+cells** (the thingbuf pattern, §2). See D-R3 for the recommended resolution and the explicit note the plan-checker must honor (do **not** flag an in-house ring as non-compliant with the literal "rtrb" wording).

---

## 1. Requirement-by-requirement findings

### THREAD-01/02/03 + SC#1/SC#2 — pthread USER_INTERACTIVE hot path

**The exact pattern already exists in-repo.** `Apps/CortexDaemon/Benchmark.swift` (Plan 02-05, the SC#1 benchmark) already implements the audio-callback-regime worker Phase 3 must productionize:

```
private struct BenchThreadArg { … POD only … }          // no Swift class crosses the boundary

private func cortexBenchConsumerThread(_ arg: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
  let a = arg.assumingMemoryBound(to: BenchThreadArg.self).pointee
  _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)   // first action on the thread
  … reconstruct ring from an UNRETAINED handle (no ARC) …
  … busy-poll …
}
// create: pthread_create(&t, nil, cortexBenchConsumerThread, UnsafeMutableRawPointer(argPtr)); pthread_join(t, nil)
```

Phase 3 = lift this from "benchmark" to "the real acquisition/DSP hot path," and add the policy gate. Findings:

- **`pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`** is the documented Darwin API and is **called from inside the spawned thread** (it sets the *calling* thread's QoS). The in-repo benchmark already uses it. `QOS_CLASS_USER_INTERACTIVE` is the highest QoS band — the scheduler treats the worker like an audio render thread. (Alternative: set at create time via a `pthread_attr_t` + `pthread_attr_set_qos_class_np`; the in-thread `_self_np` call is simpler and is the established in-repo idiom — keep it.)
- **`pthread_*` and `QOS_CLASS_USER_INTERACTIVE` come from `Darwin`, not `Foundation`.** The new Foundation-free hot-path Swift can `import Darwin` (or call a C entry in `CortexCoreC`) and still pass the policy gate (gate forbids `import Foundation`/`import ObjectiveC`, not `import Darwin`). This is how the hot path stays gate-clean while still creating threads / reading `mach_absolute_time`.
- **"Zero Swift cooperative-runtime activity" (SC#1) is hardware-gated, manual evidence — CI cannot run Instruments.** Mirror the established pattern: `sc2-evidence.md` (Phase 1) and `sc1-evidence.md` (Phase 2) are committed manual runbooks + captured traces on M-series hardware. Phase 3 needs an **`instruments-evidence.md`** (System Trace template, worker thread shows no `swift_task_*` / libdispatch frames under load) + a committed screenshot/`.trace`. CI gets the *structural proxy* instead (the policy gate, below).
- **SC#2 — the static-analysis gate already exists and is pre-armed for exactly this.** `Tools/scripts/hotpath-policy.sh` greps `Packages/CortexIPC/Sources/CortexIPCTransport` for `dispatch_async`, `lazy var`, `pthread_mutex`, `import Foundation`, `import ObjectiveC`, and its own comment says *"When Phase 3 adds the pthread USER_INTERACTIVE hot path … extend `DIRS_ARRAY` then."* Phase 3 work = add the new hot-path dir(s) to `DIRS_ARRAY` and (recommended) extend the gate to police `.rs` hot-path files (§D-R7).

### THREAD-04/05 + SC#3 — lock-free SPSC ring, cache-line-padded atomics, Acquire/Release

- **`rtrb` 0.3** (`mgeier/rtrb`) is a **wait-free** SPSC ring, `no_std`-capable (needs `alloc`), MSRV 1.38. It is the named reference design and the right *algorithm* to mirror. It hands out a `Producer`/`Consumer` split so the type system enforces single-producer/single-consumer.
- **Cache-line padding on Apple Silicon is 128 bytes, not 64.** Apple M-series cache lines / prefetch granularity are 128 B; `crossbeam-utils::CachePadded` special-cases `aarch64` to `#[repr(align(128))]`. SC#3 says "cache-line-padded atomics" → **pad the producer index and consumer index to 128-byte-aligned cells** so the head and tail never share a line (false-sharing kills SPSC throughput). State this explicitly; don't default to 64.
- **Acquire/Release ordering (the SPSC discipline):** producer publishes with `tail.store(…, Release)` and reads the consumer's progress with `head.load(Acquire)`; consumer publishes with `head.store(…, Release)` and reads `tail.load(Acquire)`. A core can use `Relaxed` for *its own* index reload. **loom fully supports Acquire/Release** (good fit). **loom treats `SeqCst` as `AcqRel`** (README "Unsupported features") — so do **not** rely on `SeqCst` in the ring; Acquire/Release is both correct and what loom verifies soundly.
- Slots are `UnsafeCell<MaybeUninit<Frame>>`; under `cfg(loom)` they become `loom::cell::UnsafeCell` so loom checks for data races on slot memory, **not just** the atomic indices (this is why an in-house ring is required — §2).

### THREAD-06 + SC#4 — cbindgen → Swift via a stable C ABI

- **cbindgen** (`mozilla/cbindgen`, Rust 1.70+) generates a C header from `pub unsafe extern "C"` functions + `#[repr(C)]` types. Two equivalent modes (README + branchout.dev):
  - standalone: `cbindgen --config cbindgen.toml --crate cortex_ring --lang c --output cortex_ring.h`
  - **build.rs (recommended)**: `cbindgen::generate(crate_dir)?.write_to_file("include/cortex_ring.h")` with `cbindgen` as a `[build-dependencies]`. Default output is C++; **add `language = "C"` in `cbindgen.toml`** (or `--lang c`).
- The Frame crossing the boundary is a **`#[repr(C)]` POD struct** consistent with Phase 2's `Sample` f16 layout (D-10/D-11): `{ ts_ns: u64, seq: u64, channel_data: [u16; CORTEX_CHANNEL_COUNT] }` (f16 carried as raw `u16` bits, hardware Float16 on both sides). The C ABI surface: `cortex_spsc_create`, `cortex_spsc_push`, `cortex_spsc_pop`, `cortex_spsc_destroy` (+ optional split producer/consumer handles).
- **Swift consumes the header via a Clang modulemap** (strathweb: `…FFI.h` + `module.modulemap`); Swift then `import CortexRingC` and calls the C functions. This mirrors the existing `CortexCoreC` C target (header in `include/` consumed by a Swift target).

### THREAD-07 + SC#3 — loom permutation testing

- **loom 0.7** (`tokio-rs/loom`): add `[target.'cfg(loom)'.dependencies] loom = "0.7"`; run with `RUSTFLAGS="--cfg loom" cargo test --release` (a dedicated `[profile.loom]` with `opt-level=3` keeps it fast — thingbuf does this). loom runs **native test threads** and permutes their interleavings under the C11 model — it is **target-independent and runs fine on the `macos-15` CI runner** (it is *not* M4-gated, unlike SC#1).
- **The std↔loom swap idiom (verbatim from thingbuf `src/loom.rs`)** — the canonical production pattern:
  ```rust
  // crate::loom — one import site the whole ring uses
  #[cfg(loom)]
  pub(crate) use loom::{cell, hint, sync, thread};
  #[cfg(loom)]
  pub(crate) mod atomic { pub use loom::sync::atomic::*; pub use std::sync::atomic::Ordering; }

  #[cfg(not(loom))]
  pub(crate) mod atomic { pub use core::sync::atomic::*; }
  #[cfg(not(loom))]
  pub(crate) use core::{cell, hint, sync}; // + std::thread for the stress test
  ```
  The ring uses `crate::loom::atomic::AtomicUsize` and `crate::loom::cell::UnsafeCell` everywhere. Production = std atomics; `--cfg loom` = instrumented atomics + cells. **Zero algorithm duplication.**

---

## 2. Why an in-house ring (resolving the rtrb-vs-loom contradiction) — D-R3

`loom` must *own* the atomics and cells of the code under test. `rtrb`'s internals use `core::sync::atomic` and cannot be redirected to loom. Therefore:

- **Write one minimal SPSC ring in `cortex_ring` whose atomics/cells route through `crate::loom`** (the shim above). Production build → std; `--cfg loom` test build → loom. This is *exactly* how `thingbuf` and `crossbeam` loom-verify their queues.
- **Mirror `rtrb`'s algorithm** (bounded power-of-two ring, 128-B-padded head/tail, Release-publish/Acquire-observe, `Producer`/`Consumer` split). Optionally keep `rtrb` as a **`criterion` benchmark cross-check** (THREAD-04 names it) — our ring should be within ~the same throughput envelope.
- **This is one ring, used for everything**: production (cbindgen-exported), the 1M-frame stress test (std atomics, 2 real threads), and the loom permutation test (`--cfg loom`, tiny). No model/production divergence.

> **Plan-checker note (carry into CONTEXT/PLAN):** Implementing an in-house `rtrb`-style ring **is** the correct, intended way to satisfy "rtrb SPSC ring … under loom." Do **not** flag the absence of a literal `rtrb = "0.3"` production dependency as a coverage gap — the literal wording is technically unsatisfiable and the intent is met by the loom-verifiable in-house ring (rtrb may appear only as a dev/bench cross-check).

---

## 3. Build integration — the load-bearing decision (RQ1) — D-R1

Goal: a Rust `staticlib` + cbindgen header must be consumable by a SwiftPM package **and** build under both `swift build --package-path …` and `xcodebuild -scheme …` on `macos-15`.

**Crate:** `crate-type = ["staticlib", "rlib"]` — `staticlib` → the `.a` to link; `rlib` → so `cargo test` (stress + loom) can build the ring as a normal Rust lib.

**Apple targets via rustup** (strathweb): `aarch64-apple-darwin` (Mac), `aarch64-apple-ios`, `aarch64-apple-ios-sim`. (x86_64 Mac/sim targets optional — repo is Apple-Silicon-only per AGENTS.md, but the `macos-15` GitHub runner may be Intel; build the host triple too so CI links.)

**Two viable wiring approaches — recommend (A), spike both:**

- **(A) `.xcframework` + SwiftPM `.binaryTarget` (RECOMMENDED).** `Tools/scripts/build-rust.sh` runs `cargo build --release` per target + cbindgen header, then `xcodebuild -create-xcframework` bundles the per-platform `.a`s + the header + a modulemap into `CortexRing.xcframework`. Package.swift references `.binaryTarget(name: "CortexRingFFI", path: "…/CortexRing.xcframework")`. **No brittle manual `-L/-l` linker flags** — SwiftPM *and* Xcode both link an xcframework natively, which is why this survives the dual build. This is the Mozilla-Glean / uniffi production path. Cost: the xcframework must exist before `swift package resolve`/`xcodegen`, so CI builds it in an early step (and a local `make bootstrap` does the same); gitignore the built xcframework.
- **(B) C-target + modulemap + vendored cbindgen header + link-by-script (FALLBACK).** A `CortexRingC` SwiftPM **C target** holding only the cbindgen header + `module.modulemap` (mirrors `CortexCoreC`); the header is **committed and CI-drift-checked exactly like the flatc-generated Swift (Phase 2 D-13)**; a Swift `CortexRing` target links the `.a` via `linkerSettings: [.unsafeFlags(["-L…","-lcortex_ring"])]`. Simpler conceptually and reuses two existing repo patterns, but `.unsafeFlags` link paths are fragile across `swift build` vs `xcodebuild` working dirs — the reason (A) is preferred.

**CI (`ci.yml`) additions** (consistent with the existing `brew install xcodegen swiftformat swiftlint xcbeautify` step — "CI installs its tools" is already the norm, so this does **not** violate the bundled-tools ethos):
- install Rust (`rustup` or `brew install rustup-init` + `rustup target add …`) + `cargo install cbindgen` (or `brew install cbindgen`);
- early step: `Tools/scripts/build-rust.sh` → produce `CortexRing.xcframework` **before** `xcodegen`/`swift build`;
- new gates: `RUSTFLAGS="--cfg loom" cargo test --profile loom` (SC#3 ordering), `cargo test --release` 1M-frame FIFO stress (SC#3 no-loss), cbindgen-header drift check (`cbindgen … | git diff --exit-code`, only when cbindgen present — mirror D-13), and the Swift integration test (SC#4). All are M1/Intel-runner-safe (correctness/model only); SC#1's Instruments trace stays M4-hardware-gated evidence.

**Clean-clone caveat (FOUND-04 tension):** a `.binaryTarget` xcframework that's gitignored means a fresh clone needs `make bootstrap` (or CI's build step) before `swift package resolve` succeeds. Document this as the Phase-3 analogue of the Phase-1 "toolchain-deferral" disposition (a named, documented bootstrap step), not a silent break.

---

## 4. Threading topology (resolves Phase 2 D-06) — D-R8

The Phase 3 Rust SPSC ring is the **in-process, intra-app** bridge (distinct from the Phase 2 **cross-process** shm ring):

```
[acquisition/DSP pthread, QOS_CLASS_USER_INTERACTIVE, Foundation-free]  ── push ──▶  [Rust SPSC ring]  ── pop ──▶  [Swift UI/render layer, Foundation-allowed]
        = SPSC PRODUCER                                                     (cbindgen C ABI)                     = SPSC CONSUMER
```

- The producer side is the policed hot path (no Task/dispatch/locks/Foundation/ARC). It calls the Rust `push` through the C ABI (a C call — no ARC, no Swift runtime).
- **AES-GCM stays OFF the USER_INTERACTIVE hot path.** Encryption is the Phase 2 *cross-process* session concern; the in-process producer→ring→UI path does not encrypt. **This resolves D-06** ("Phase 3 profiles whether the encrypt step must move onto the Foundation-free hot path"): the SPSC ring is the decoupling boundary, so the answer is *no* — encrypt remains on the cross-process IPC side, off the acquisition hot path.
- Phase 6 (RENDER SC#4) consumes "a synthetic cursor-velocity stream from the Phase 3 ring buffer" — confirming the ring's consumer is the renderer/UI. Keep the C ABI shaped so the consumer can be driven from a `CAMetalDisplayLink` callback later.

---

## 5. Validation Architecture

> Drives `03-VALIDATION.md` (Nyquist) and the planner's Dimension-8 (validation) tasks. Each success criterion maps to a validation signal, an execution venue (CI vs M4-hardware-gated), a sampling cadence, and a **negative control** (a deliberately-broken variant proving the check actually bites — the established Cortex discipline from the Phase-1 privacy-manifest negative control and loom's own `#[should_panic]` buggy test).

| SC | What must be true | Validation signal | Venue / cadence | Negative control |
|----|-------------------|-------------------|-----------------|------------------|
| **SC#1** | Hot path on raw pthread @ USER_INTERACTIVE; zero Swift cooperative-runtime activity under load | (a) Instruments → System Trace: worker thread shows no `swift_task_*`/libdispatch frames; (b) **structural proxy**: hot-path policy gate green | (a) **M4 hardware**, manual `instruments-evidence.md` + committed trace, per-milestone; (b) **CI**, every run | A Swift `Task`/`DispatchQueue.async` added to the hot-path dir makes the policy gate exit 1 |
| **SC#2** | CI fails on `dispatch_async`/`lazy var`/`pthread_mutex`/`import Foundation`/ObjC in any hot-path source (Swift/C/Rust) | `hotpath-policy.sh` exit code over extended `DIRS_ARRAY` (+ `.rs` token set) | **CI**, every run | Self-test: inject each forbidden token into a temp copy → assert exit 1 (extend the Plan 01-06 `DIRS=/tmp/synthetic` self-test) |
| **SC#3a** | Memory ordering correct (no reordering/torn read/data race) | `RUSTFLAGS="--cfg loom" cargo test` over a tiny ring (cap 2–3, 2–3 ops/thread, exhaustive interleavings) passes | **CI**, every run (model-checker, runner-arch-independent) | A `Relaxed`-where-`Release`-is-required variant under loom must FAIL (loom finds the reordering) |
| **SC#3b** | 1M frames producer→consumer, strict FIFO, zero loss | `cargo test --release` stress: 2 std-atomic threads, 1,000,000 frames, assert monotonic `seq` + count==1e6 | **CI**, every run | Off-by-one capacity / dropped-slot mutant fails the FIFO assertion |
| **SC#3c** | Cache-line padding present | Static assert / test on `align_of` of the padded index cells == 128 (Apple Silicon) | **CI**, every run | Removing `#[repr(align(128))]` fails the alignment assertion |
| **SC#4** | Swift reads frames produced from the C/Rust side over the cbindgen ABI | Swift integration test: create ring via C ABI, produce N frames one side, pop+verify other side (value + order) | **CI**, every run | cbindgen-header drift check: regenerate header, `git diff --exit-code` (mirror D-13) |

**Nyquist sampling rationale:** the structural/CI signals (policy gate, loom, stress, drift, integration test) run **every CI push** — the highest meaningful rate, since the protected invariants can regress on any commit. The one continuous-but-not-CI-able signal (SC#1 Instruments trace) is sampled **per milestone on M4 hardware**, with the always-on policy gate as its CI proxy so a regression can't sit undetected between manual captures.

---

## 6. Pitfalls (field-checked)

1. **`cargo`/`cbindgen` absent today** — first CI run after Phase 3 lands must install the Rust toolchain or every Rust gate errors. Wire the install step *and prove it* before relying on it.
2. **`loom` ≠ `rtrb`** (§2). Naively `cargo add rtrb` then trying to "loom-test rtrb" is a dead end — loom can't see its atomics. Build the in-house ring.
3. **128-byte cache lines on Apple Silicon** — don't pad to 64; head/tail false-sharing silently halves throughput.
4. **loom state-space explosion** — loom is exhaustive; a ring of capacity 8 with 100 ops will not terminate. Keep loom scenarios tiny (cap 2–3, ≤3 ops/thread). The 1M test is the *separate* std-atomic stress test, never under loom.
5. **loom `SeqCst` → `AcqRel`** (false alarms / not sound for `SeqCst`) — design the ring on Acquire/Release only.
6. **`.unsafeFlags` link paths break across `swift build` vs `xcodebuild`** — the reason to prefer the xcframework/`.binaryTarget` path (§3-A).
7. **Foundation creeps in via `NSLog`** — the Phase 2 daemon logs with `NSLog` (Foundation). The new hot path must not; use `os_log`/`fputs`/a C shim for any diagnostics, or none on the steady-state path.
8. **ARC on the boundary** — pass a POD `@convention(c)`-compatible arg and an **unretained** ring handle into the pthread entry (the Benchmark.swift idiom), never a Swift class instance as a tracked value.
9. **Frame-layout drift vs Phase 2** — the repr(C) Frame must stay consistent with `CORTEX_CHANNEL_COUNT` and the f16/`[ubyte]` layout (D-10/D-11); add a static assert tying the two so a channel-count change can't silently desync the ring and the FlatBuffers `Sample`.

---

## 7. Recommended topology, spikes, and decision summary

**Proposed files / module topology** (planner refines):
- `Packages/CortexRing/` — new SwiftPM package: `rust/` (Cargo crate `cortex_ring`, `staticlib`+`rlib`, `src/lib.rs` ring + `src/loom.rs` shim + loom & stress tests + `cbindgen.toml` + `build.rs`), `Sources/CortexRing*` (Swift wrapper + C/header consumption), `Tests/` (Swift integration test, SC#4).
- `Tools/scripts/build-rust.sh` — cargo build per Apple target + cbindgen header + `xcframework` assembly.
- New Foundation-free Swift hot-path target/dir for the acquisition pthread (or a C entry in `CortexCoreC`) — added to `hotpath-policy.sh` `DIRS_ARRAY`.
- `…/03-…/instruments-evidence.md` — SC#1 M4 manual runbook + trace (mirrors `sc1-evidence.md`/`sc2-evidence.md`).
- `ci.yml` — Rust toolchain install + xcframework build + loom/stress/drift/integration gates.

**Recommended spikes (do before the full build — Phase 2 precedent):**
- **Spike A (load-bearing):** hello-world `cortex_ring` → `pub unsafe extern "C" fn cortex_ping(x:u32)->u32` → cbindgen header → xcframework → Swift `import` + call, building under BOTH `swift build` and `xcodebuild -scheme` on `macos-15`. Proves the whole FFI/build chain before the ring.
- **Spike B:** minimal loom test (cap-2 ring, 1 push / 1 pop, 2 threads) green under `--cfg loom`, and a `Relaxed`-mutant red. Proves the loom harness + the shim.

**Decision summary (carry into CONTEXT.md / honor in PLAN.md):**

| ID | Decision |
|----|----------|
| **D-R1** | Build integration: in-house Rust `staticlib`+`rlib` → cbindgen header → **`.xcframework` + SwiftPM `.binaryTarget`** (primary); C-target+modulemap+link-script fallback. CI installs Rust+cbindgen and builds the xcframework before `swift build`/`xcodegen`. |
| **D-R2** | Hot path = productionized `Benchmark.swift` idiom: top-level `@convention(c)` entry, POD arg, unretained ring handle, `pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE,0)` first; `import Darwin` (not Foundation). |
| **D-R3** | **In-house `rtrb`-style SPSC ring with `cfg(loom)` atomics+cells** (thingbuf shim). One ring for production + stress + loom. `rtrb` only as optional bench cross-check. Plan-checker must not treat the missing literal `rtrb` production dep as a gap. |
| **D-R4** | Memory ordering: Release-publish / Acquire-observe only (no `SeqCst` — loom-unsound). 128-byte cache-line padding on head/tail (Apple Silicon). |
| **D-R5** | SC#3 is **two tests**: tiny loom permutation test (ordering) + 1M-frame std-atomic stress test (FIFO/no-loss). Never 1M under loom. |
| **D-R6** | Frame = `#[repr(C)] { ts_ns:u64, seq:u64, channel_data:[u16; CORTEX_CHANNEL_COUNT] }`, layout-locked to Phase 2 D-10/D-11 via a static assert. |
| **D-R7** | Extend `hotpath-policy.sh` `DIRS_ARRAY` to the new pthread hot-path dir(s) **and** police `.rs` hot-path files for `Mutex`/`RwLock`/`.lock(`/`println!`/`panic!`; extend the negative-control self-test. |
| **D-R8** | AES-GCM stays off the USER_INTERACTIVE hot path; the SPSC ring is the decoupling boundary (resolves Phase 2 D-06). |

---

## 8. Sources (verifiable)

- loom README — https://raw.githubusercontent.com/tokio-rs/loom/master/README.md (cfg(loom), `loom::sync::atomic`, `RUSTFLAGS="--cfg loom"`, Acquire/Release supported, SeqCst→AcqRel caveat, loom 0.7)
- rtrb README — https://raw.githubusercontent.com/mgeier/rtrb/master/README.md (wait-free SPSC, no_std, v0.3, tested with Miri/TSan — **not loom**)
- cbindgen README — https://raw.githubusercontent.com/mozilla/cbindgen/master/README.md (staticlib, `cbindgen.toml`, build.rs `cbindgen::generate`, `--lang c`, Rust 1.70+)
- thingbuf `src/loom.rs` + `Cargo.toml` — https://github.com/hawkw/thingbuf (canonical std↔loom cfg-shim incl. `loom::cell::UnsafeCell`; `[target.'cfg(loom)']` deps; `[profile.loom]`)
- "Bridging Rust to Swift, pt. 2: cbindgen" — https://www.branchout.dev/rust/swift/c/2022/08/10/rust_to_swift_pt2.html (build.rs + cbindgen.toml, header generation)
- "Calling Rust code from Swift on iOS and macOS" — https://www.strathweb.com/2023/07/calling-rust-code-from-swift/ (rustup `aarch64-apple-darwin`/`-ios`/`-ios-sim`, staticlib `.a`, modulemap, linking)
- StackOverflow: combine a static Rust lib + C FFI layer + Swift bindings — https://stackoverflow.com/questions/75913273 (SwiftPM staticlib integration)
- Mozilla Data@Glean: building/deploying a Rust library on iOS — https://blog.mozilla.org/data/2022/01/31/this-week-in-glean-building-and-deploying-a-rust-library-on-ios/ (xcframework production path)
- crossbeam-utils `CachePadded` — 128-byte alignment on `aarch64` (Apple Silicon cache-line size)
- In-repo precedent — `Apps/CortexDaemon/Benchmark.swift` (pthread+QoS idiom), `Tools/scripts/hotpath-policy.sh` (pre-armed gate), `Packages/CortexCore/Sources/CortexCoreC` (C-target/header pattern), Phase 2 `02-CONTEXT.md` D-06/D-10/D-11/D-13.
