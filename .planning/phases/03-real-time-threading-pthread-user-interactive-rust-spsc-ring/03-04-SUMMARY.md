---
phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring
plan: 04
subsystem: infra
tags: [swift, ffi, cbindgen, spsc, ring, raii, opaquepointer, repr-c, swift-testing, xcframework, binaryTarget]

# Dependency graph
requires:
  - phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring (Plan 01)
    provides: "CortexRingFFI.xcframework .binaryTarget + the cbindgen modulemap (import CortexRingFFI), the frozen #[repr(C)] CortexFrame, the frozen extern \"C\" ABI (cortex_spsc_create/push/pop/destroy), the vendored header + CI drift gate, and the pre-armed Swift-integration CI gate"
  - phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring (Plan 02)
    provides: "the REAL loom-verified ring behind the ABI — create rejects zero/non-pow2 → null (T-03-02-04), push false=full, pop false=empty, strict FIFO, drain-on-Drop; the committed cbindgen header is the source of truth for the C signatures"
  - phase: 02-ipc-primitive-kqueue-recvmsg-flatbuffers-aes-gcm
    provides: "D-10 — channel_data is raw IEEE-754 half (f16) bits carried as u16 lanes (opaque; not converted)"
provides:
  - "CortexRing — a safe RAII Swift consumer wrapper over the cbindgen ring ABI (Sources/CortexRing/Ring.swift): init?(capacity:) → nil on null, deinit → cortex_spsc_destroy exactly once, push(_:)->Bool, pop()->CortexFrame?"
  - "The CortexRing SwiftPM target + library product (isolation-neutral — no MainActor — so the Phase-6 CAMetalDisplayLink consumer can pop() off the main actor)"
  - "Consumes the repr(C) CortexFrame DIRECTLY from the modulemap (@_exported import CortexRingFFI) — no hand-written Swift mirror that could drift (D-R6); the C array imports as a 96-UInt16 tuple"
  - "SC#4 Swift integration test (Tests/CortexRingTests/RingIntegrationTests.swift): create ring via C ABI, produce 1000 frames, pop+verify by VALUE (ts_ns + channel_data bitwise) AND strict FIFO ORDER (seq 0..<1000) — round-trip fidelity proof"
  - "Real coverage on the Plan-01 pre-armed Swift-integration CI gate; the cbindgen drift gate is SC#4's structural negative control (cross-referenced in the test)"
affects: [06-renderer]

# Tech tracking
tech-stack:
  added:
    - "(no new crates/tools — consumes the Plan-01 CortexRingFFI.xcframework + Swift Testing already in the repo)"
  patterns:
    - "Safe RAII Swift wrapper over a cbindgen C ABI: store the handle as OpaquePointer, bridge to the imported UnsafeMutablePointer<CortexSpsc> only at each C call site; init?/deinit own create/destroy (destroy exactly once; no public manual-destroy → no double-free)"
    - "@_exported import of the cbindgen FFI module so the wrapper's public API (which traffics in the C CortexFrame) is self-contained for consumers — re-export the repr(C) type, never re-declare it (D-R6)"
    - "C fixed-size array (channel_data[96]) imports into Swift as a 96-element homogeneous TUPLE, not an array — fill/compare via withUnsafe(Mutable)Bytes raw-byte access (tuples are not subscriptable by a runtime index nor Equatable), keeping the single C-defined layout"
    - "SC#4 round-trip via a bounded ring smaller than N (cap 256, N=1000): interleave push-until-full → drain-via-pop so every frame genuinely traverses the C/Rust ring; assert value + strict FIFO order"
    - "cbindgen header drift gate as the integration test's structural negative control (ABI change without header regen → drift gate fails → the value+order test can never silently pass against a stale ABI)"

key-files:
  created:
    - "Packages/CortexRing/Sources/CortexRing/Ring.swift — the safe RAII wrapper (final class CortexRing; OpaquePointer handle; init?/deinit RAII; push/pop)"
    - "Packages/CortexRing/Tests/CortexRingTests/RingIntegrationTests.swift — SC#4 round-trip (1000 frames, value+order) + capacity/null edges + RAII-cycle test"
  modified:
    - "Packages/CortexRing/Package.swift — added the CortexRing target + library product; CortexRingTests now depends on CortexRing too (CortexRingPing/HotPath/binaryTarget untouched)"

key-decisions:
  - "Handle stored as OpaquePointer (the plan's contract) even though cbindgen's named-but-fieldless `typedef struct CortexSpsc { uint8_t _private[0]; }` makes Swift import cortex_spsc_create as UnsafeMutablePointer<CortexSpsc>? — bridge OpaquePointer(raw) on create and UnsafeMutablePointer<CortexSpsc>(handle) at each call. The OpaquePointer storage matches the ring's private-to-Rust layout and the plan/threat-model intent."
  - "init?(capacity: Int) keeps the idiomatic Swift Int signature (plan <interfaces>) but converts to UInt at the C boundary (the ABI is uintptr_t) with a `capacity > 0` guard so a negative Int is never bit-cast through (it cannot be a valid pow2 capacity anyway)."
  - "@_exported import CortexRingFFI in the wrapper so consumers of CortexRing automatically see CortexFrame — the public push/pop API is otherwise unnameable. Re-export, not re-declare (D-R6)."
  - "Test names use the project's established backtick descriptive-name convention (the Plan-01 PingSmokeTests precedent) rather than the plan's illustrative camelCase identifiers; the names map 1:1 to the required behaviors and pass swiftlint/swiftformat."
  - "swift build/swift test --package-path Packages/CortexRing is the authoritative gate for this plan (the Plan-01-established CI step). The xcodebuild-scheme leg was Plan-01's Spike-A FFI-spine concern and is unchanged here (same xcframework link path)."

patterns-established:
  - "RAII Swift↔Rust handle ownership: OpaquePointer field + init?/deinit, destroy-exactly-once, no public manual destroy (the production uniffi/Glean ownership shape)"
  - "Treat a cbindgen fixed-size C array as a Swift tuple and operate on it via raw bytes — never re-declare the repr(C) struct on the Swift side"
  - "An integration value+order test paired with the cbindgen drift gate as its negative control = end-to-end ABI fidelity proof"

requirements-completed: [THREAD-06]

# Metrics
duration: 5min
completed: 2026-06-20
---

# Phase 3 Plan 04: Swift Integration — Safe Ring Wrapper + SC#4 Round-Trip Summary

**A safe RAII `CortexRing` Swift wrapper exposes the loom-verified Rust SPSC ring over the cbindgen C ABI (init?/deinit own create/destroy; push/pop over the frozen `cortex_spsc_*` functions, consuming the `#[repr(C)] CortexFrame` directly from the modulemap with no drift-prone mirror), and a Swift Testing integration test creates the ring via the C ABI, produces 1000 frames, and pops + verifies them by value (`ts_ns` + `channel_data` bitwise) AND strict FIFO order (`seq` 0..<1000) — closing SC#4 / THREAD-06 with real coverage on the Plan-01 pre-armed CI gates.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-21T00:19:35Z
- **Completed:** 2026-06-21T00:24:35Z
- **Tasks:** 2 (both complete)
- **Files modified/created:** 3 (2 created, 1 modified)

## Accomplishments

- **THREAD-06 Swift side — the safe consumer bridge to the loom-verified ring.** `Sources/CortexRing/Ring.swift` is a `public final class CortexRing` that owns the `*mut CortexSpsc` handle: `init?(capacity:)` calls `cortex_spsc_create` and returns `nil` on null (the zero/non-pow2 reject path), `deinit` calls `cortex_spsc_destroy` exactly once (RAII; no public manual-destroy → no double-free, T-03-04-01), `push(_:)->Bool` / `pop()->CortexFrame?` map the two hot functions. The handle is stored as `OpaquePointer` (the ring's layout is private to Rust) and bridged to the cbindgen-imported `UnsafeMutablePointer<CortexSpsc>` only at each call site.
- **Zero layout drift (D-R6 / T-03-04-02).** The wrapper consumes the `#[repr(C)] CortexFrame` DIRECTLY from the modulemap via `@_exported import CortexRingFFI` — there is no hand-written Swift struct mirror that could diverge from the Rust layout. `channel_data` is treated as opaque `u16` bits (Phase-2 D-10), never converted to/from `Float16`. The cbindgen header drift gate (Plan-01 CI) guarantees the ABI the test measures against is the real, current one.
- **SC#4 round-trip fidelity proven end-to-end.** `Tests/CortexRingTests/RingIntegrationTests.swift` creates a capacity-256 ring (smaller than N on purpose), produces N=1000 `CortexFrame`s with a known `(seq, ts_ns = seq*2+1, channel_data = seq & 0xFFFF in every lane)` pattern, interleaves push-until-full → drain-via-pop so every frame traverses the C/Rust ring, then asserts the popped `seq` sequence is exactly `0..<1000` (strict FIFO **order**) AND each frame's `ts_ns` + `channel_data` match the produced pattern bit-for-bit (**value**). This is the consumer half of the producer→ring→consumer topology (RESEARCH §4).
- **Edge + RAII coverage.** `pop()` on a fresh ring → `nil` (never reads uninitialized — T-03-04-03); fill-to-capacity then `push` → `false`; `CortexRing(capacity: 3)` and `(capacity: 0)` → `nil` (create-null path); 200× create/`push`/`pop`/deinit cycles run without crashing (RAII destroy-once). The Plan-01 `PingSmokeTests` stay green (modulemap import intact).
- **Real coverage on the pre-armed CI gates.** The Plan-01 "Swift-integration" gate (`swift test --package-path Packages/CortexRing`) now exercises the actual produce→pop fidelity (7/7 green), and the test cross-references the cbindgen drift gate as SC#4's structural negative control. Correctness only — **no timing/latency assertion** (D-18 split: the M4 glass-to-glass number is hardware Instruments evidence, not a unit test).

## Task Commits

Each task was committed atomically (TDD: tests-first; `--no-verify` per parallel-executor protocol):

1. **Task 1: Safe RAII Swift wrapper (CortexRing) over the cbindgen C ABI** — `a8ab81f` (feat)
2. **Task 2: SC#4 Swift integration test — produce 1000 frames, pop+verify value+order** — `48945b0` (test)

**Plan metadata:** (final docs commit — this SUMMARY)

_Note: the wrapper-behavior RED tests and the SC#4 integration test live in one file (the shared test target); Task 1 committed the wrapper + Package.swift, Task 2 committed the test file._

## Wrapper API (cite from Phase 6)

```swift
import CortexRing                                  // @_exported re-exports CortexRingFFI → CortexFrame is in scope

public final class CortexRing {
    public init?(capacity: Int)                    // nil if cortex_spsc_create returns null (zero/non-pow2)
    deinit                                          // cortex_spsc_destroy — RAII, exactly once
    @discardableResult public func push(_ frame: CortexFrame) -> Bool   // false = full (producer thread only)
    public func pop() -> CortexFrame?               // nil = empty (consumer thread only)
}
```

SPSC contract: the wrapper does NOT enforce thread-affinity — one producer (`push`), one consumer (`pop`), matching the Rust `Producer`/`Consumer` split. Phase-6 renderer drives `pop()` from a `CAMetalDisplayLink` callback off the main actor (RENDER SC#4).

## Files Created/Modified

- `Packages/CortexRing/Sources/CortexRing/Ring.swift` (created, 75 lines) — the safe RAII wrapper.
- `Packages/CortexRing/Tests/CortexRingTests/RingIntegrationTests.swift` (created, 146 lines) — SC#4 round-trip + edges + RAII cycle + a test-only `CortexFrame` pattern-fill extension (no layout redefinition).
- `Packages/CortexRing/Package.swift` (modified) — added the `CortexRing` target + `.library` product; `CortexRingTests` now also depends on `CortexRing`. `CortexRingFFI` binaryTarget, `CortexRingPing`, and `CortexRingHotPath` (Plan 03-03) left untouched.

## Decisions Made

- **`OpaquePointer` handle despite the `UnsafeMutablePointer<CortexSpsc>?` import (see Issues).** Kept the plan's `OpaquePointer` contract by bridging at the boundary — it matches the "layout private to Rust" intent and the threat model's RAII-ownership framing.
- **`init?(capacity: Int)` with a `> 0` guard, converting to `UInt` at the C boundary** (the ABI is `uintptr_t`). Idiomatic Swift signature (plan `<interfaces>`) without bit-casting a negative `Int`.
- **`@_exported import CortexRingFFI`** so the wrapper's public API is self-contained — consumers of `CortexRing` get `CortexFrame` automatically (the `push`/`pop` types are otherwise unnameable).
- **Backtick descriptive test names** (the Plan-01 `PingSmokeTests` precedent) over the plan's illustrative camelCase identifiers; names map 1:1 to the required behaviors and pass both lint gates.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stored the handle as OpaquePointer via an explicit bridge (cbindgen imports it as `UnsafeMutablePointer<CortexSpsc>?`, not `OpaquePointer`)**
- **Found during:** Task 1 (typechecking the wrapper against the real modulemap)
- **Issue:** The plan's `<interfaces>` and acceptance assume `cortex_spsc_create` yields an `OpaquePointer`. Because the cbindgen header emits a *named* opaque type (`typedef struct CortexSpsc { uint8_t _private[0]; } CortexSpsc;`), Swift actually imports `cortex_spsc_create() -> UnsafeMutablePointer<CortexSpsc>?` and the `cortex_spsc_*` functions take `UnsafeMutablePointer<CortexSpsc>!` — a direct `OpaquePointer` assignment fails to compile.
- **Fix:** Stored the handle as `OpaquePointer` (the plan's contract) and bridged: `OpaquePointer(raw)` on create, `UnsafeMutablePointer<CortexSpsc>(handle)` at each `push`/`pop`/`destroy` call site. Verified the bridge compiles AND runs (a standalone link+run probe returned a correct push/pop round-trip).
- **Files modified:** Packages/CortexRing/Sources/CortexRing/Ring.swift
- **Verification:** `swift build` clean; `grep` proofs (import CortexRingFFI + all four `cortex_spsc_*`) pass; the wrapper handle is an `OpaquePointer` as the acceptance requires.
- **Committed in:** `a8ab81f` (Task 1)

**2. [Rule 1 - Bug] `init?(capacity:)` converts Int → UInt at the C boundary**
- **Found during:** Task 1 (first `swift build`)
- **Issue:** `cortex_spsc_create` takes `uintptr_t`, imported as `UInt`; passing the plan's `Int capacity` directly is a type error (`cannot convert value of type 'Int' to expected argument type 'UInt'`).
- **Fix:** Kept the idiomatic `init?(capacity: Int)` public signature and added `guard capacity > 0, let raw = cortex_spsc_create(UInt(capacity))` — the `> 0` guard prevents bit-casting a negative `Int` (which can never be a valid power-of-two capacity).
- **Files modified:** Packages/CortexRing/Sources/CortexRing/Ring.swift
- **Verification:** `swift build` clean; `CortexRing(capacity: 0)` test → `nil`.
- **Committed in:** `a8ab81f` (Task 1)

**3. [Rule 2 - Missing critical] `@_exported import CortexRingFFI` so the public API is usable**
- **Found during:** Task 2 (first `swift test` — test target imports `CortexRing` but `CortexFrame` was not in scope)
- **Issue:** The wrapper's public `push`/`pop` traffic in `CortexFrame`, but a plain `import CortexRingFFI` does not re-export the type to `CortexRing`'s consumers — the test (and the future Phase-6 renderer) could not name the type the API requires. The public API was effectively unusable without each consumer separately importing the FFI module.
- **Fix:** Changed the wrapper's import to `@_exported import CortexRingFFI`, re-exporting the repr(C) `CortexFrame` (re-export, NOT re-declare — D-R6 preserved).
- **Files modified:** Packages/CortexRing/Sources/CortexRing/Ring.swift
- **Verification:** `swift test` builds and all 7 tests pass; `CortexFrame` resolves in the test with only `import CortexRing`.
- **Committed in:** `a8ab81f` (Task 1)

**4. [Rule 1 - Bug] swiftformat/swiftlint conformance on the new Swift files (CI gates)**
- **Found during:** SUMMARY prep (running the repo's actual `swiftformat --lint` / `swiftlint --strict` CI commands)
- **Issue:** The repo runs `swiftformat --lint .` + `swiftlint --strict` alongside `swift test` (Plan-01 precedent). My files initially failed: `redundantSelf` (`self.handle` in `init`), a stripped leading header (the repo `.swiftformat` uses `--header strip`/`--self remove`), a trailing comma after the new `.library` product, and `identifier_name` (≥3 chars) on test locals `n`/`a`/`b`/`ra`/`rb`.
- **Fix:** Ran the project `swiftformat` (autofix → `self` removed, header stripped, trailing comma normalized) and renamed the short identifiers to descriptive names (`frameCount`, `lhsFrame`/`rhsFrame`/`lhsBytes`/`rhsBytes`). The lost top-of-file prose was redundant with the rich `///` doc comments retained on the type.
- **Files modified:** Packages/CortexRing/Sources/CortexRing/Ring.swift, Packages/CortexRing/Tests/CortexRingTests/RingIntegrationTests.swift, Packages/CortexRing/Package.swift
- **Verification:** `swiftformat --lint` → 0/3 require formatting; `swiftlint --strict` → 0 violations; `swift test` still 7/7 green.
- **Committed in:** `a8ab81f` (Task 1 files) + `48945b0` (Task 2 test file)

---

**Total deviations:** 4 auto-fixed (3 bugs, 1 missing-critical). **Impact:** All necessary for a building, gate-clean wrapper whose public API is usable and whose handle/capacity types match the real cbindgen import. No scope creep — every change stays within the Swift consumer wrapper + its test; the Rust crate, the frozen ABI, the cbindgen header, and the parallel agents' targets (CortexRingPing/HotPath/binaryTarget) were untouched.

## Issues Encountered

- **cbindgen opaque-type import shape (the load-bearing discovery):** the header's `typedef struct CortexSpsc { uint8_t _private[0]; } CortexSpsc;` is a *named* type with a (zero-length) field, so Swift imports the handle as `UnsafeMutablePointer<CortexSpsc>?` rather than `OpaquePointer`. Resolved by the boundary bridge (Deviation #1) — proven by a standalone `swiftc` link+run probe before writing the wrapper.
- **`channel_data` imports as a tuple, not an array:** the C `uint16_t channel_data[96]` becomes a 96-element homogeneous Swift tuple `(UInt16, …, UInt16)` (confirmed at runtime: `Mirror` child count == 96). Swift tuples are neither subscriptable by a runtime index nor `Equatable`, so the test fills/compares `channel_data` via `withUnsafe(Mutable)Bytes` raw-byte access — which also keeps the layout the single C-defined one (no Swift-side reinterpretation).
- **xcframework bootstrap:** `CortexRingFFI.xcframework` is gitignored (the `make bootstrap` analogue), so it was absent in a fresh worktree. Ran `Tools/scripts/build-rust.sh` first (Rule 3 prerequisite — without it `swift build`/`swift test` cannot link the FFI). No Rust source changed, so the cbindgen drift gate (`git diff --exit-code include/cortex_ring.h`) stays clean.

## Known Stubs

None. The wrapper is fully wired to the real loom-verified ring (Plan 02 bodies); no `TODO`/`FIXME`/placeholder remains. `channel_data` carries the producer's opaque f16 bits unmodified (D-10) — that is the intended end-to-end behavior, not a stub.

## Threat Surface

No new attack surface beyond the plan's `<threat_model>`. All three Swift-side STRIDE mitigations are implemented and tested:
- **T-03-04-01** (double-free / leak of the ring handle): RAII `deinit` → `cortex_spsc_destroy` exactly once; no public manual-destroy; `init?` returns `nil` on null (no destroy-of-null). → `repeated create-and-deinit cycles do not crash` (200×) + the null-capacity tests.
- **T-03-04-02** (Swift/Rust layout drift on CortexFrame): the wrapper uses the C `CortexFrame` directly (`@_exported import`, no Swift mirror); the cbindgen drift gate fails on any ABI divergence. → no `struct CortexFrame` redefinition (grep-clean) + the drift-gate cross-reference comment.
- **T-03-04-03** (uninitialized pop output read): `pop()` zero-inits the `CortexFrame` before `&out` and returns it only when `cortex_spsc_pop` is `true`. → `pop on a fresh empty ring returns nil`.

No `threat_flag` raised — the surface is in-process, single signed app, no network/auth/identity; `channel_data` is opaque f16 bits, not PII (D-10). The deep FFI memory-safety hardening (null guards, capacity guards, catch_unwind) lives on the Rust side (Plan 02 T-03-02-xx).

## User Setup Required

None — no external service configuration. The only prerequisite is the Rust toolchain + `Tools/scripts/build-rust.sh` to produce the gitignored `CortexRingFFI.xcframework` (already bootstrapped in Plan 01 and wired into `ci.yml`).

## Next Phase Readiness

- **Phase 6 (renderer, RENDER SC#4):** `CortexRing` is the shaped consumer — isolation-neutral (no MainActor), so the renderer drains a synthetic cursor-velocity stream by calling `pop()` from a `CAMetalDisplayLink` callback off the main actor. `import CortexRing` is self-contained (`CortexFrame` re-exported). The producer side is `CortexRingHotPath` (Plan 03-03); this ring is the decoupling boundary (D-R8).
- **CI:** the Plan-01 "Swift-integration" gate now carries real SC#4 coverage; the cbindgen drift gate is its negative control. **Carried concern (from Plans 01/02):** the macos-15 CI gates (Rust toolchain install + xcframework build + drift + Swift-integration) have still not been exercised by a real runner — the first PR after this wave lands is the first true end-to-end CI proof. All gates pass locally on this Apple-Silicon host (`swift test` 7/7, swiftformat 0/3, swiftlint 0, drift clean).

## Self-Check: PASSED

- Created files verified present on disk: `Sources/CortexRing/Ring.swift`, `Tests/CortexRingTests/RingIntegrationTests.swift`.
- Modified file verified: `Package.swift` (CortexRing target + product).
- Both task commit hashes verified in git history: `a8ab81f` (Task 1), `48945b0` (Task 2).
- Gate replay: `swift build` clean; `swift test --package-path Packages/CortexRing` → 7/7 green (SC#4 round-trip 1000 frames value+order + 4 edge/RAII tests + 2 Ping smoke); `swiftformat --lint` 0/3; `swiftlint --strict` 0 violations; cbindgen drift gate clean; whole package builds (parallel targets undisturbed).

---
*Phase: 03-real-time-threading-pthread-user-interactive-rust-spsc-ring*
*Completed: 2026-06-20*
