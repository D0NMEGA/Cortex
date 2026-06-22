---
phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
plan: 02
subsystem: ui
tags: [velocity-seam, spsc, ring-buffer, atomics, swift6, float16, integrator, lissajous, renderer]

# Dependency graph
requires:
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid (Plan 01)
    provides: WebgridParams (the cursorX/cursorY fields this plan's integrator output fills) + WebgridFrameEncoder (the consumer Plan 03 feeds the integrated position into)
  - phase: 03-real-time-threading
    provides: the loom-verified SPSC ring DESIGN (Release-publish/Acquire-observe, no SeqCst, power-of-two capacity guard) + #[repr(C)] CortexFrame field-ordering discipline (ts_ns, seq, then payload) that CursorVelocity mirrors
provides:
  - CursorVelocity — the dedicated (vx,vy) fp16 velocity seam struct (D-03); field order ts_ns:u64, seq:u64, vx:Float16, vy:Float16 mirrors cortex_ring.h CortexFrame so a future #[repr(C)] cbindgen Rust producer (Phase 7) is a drop-in
  - CursorIntegrator — renderer-owned velocity→position integrator (D-04): pos += velocity*dt (grid-units/s), clamps to [0,1], rejects non-finite velocity (holds); post-clamp position provably finite + in-range (cursor cannot leave the surface, T-06-02-01)
  - VelocityRing — in-process lock-free SPSC bounded ring of CursorVelocity (D-03); Synchronization.Atomic head/tail, Release/Acquire (no torn read, T-06-02-02), @unchecked Sendable per the SPSC discipline, bounded push (DoS accept T-06-02-03)
  - LissajousProducer — deterministic closed-form synthetic velocity drive (D-05); v(t)=(A·cos(ω₁t+φ), B·sin(ω₂t))→fp16, no clock/RNG/global state, defaults keep the integrated path on-grid
affects: [Plan 06-03 (display-link adapters pop VelocityRing, call CursorIntegrator.integrate, feed WebgridParams.cursor), Plan 06-04/05 (synthetic LissajousProducer drives the 60s 120Hz soak), Phase 7 (ReFIT-Kalman becomes the velocity producer behind the unchanged D-03 seam)]

# Tech tracking
tech-stack:
  added: ["Synchronization.Atomic (built-in Swift 6.2 module — no SwiftPM dependency added)"]
  patterns:
    - "Dedicated velocity-typed seam (CursorVelocity), decoupled from the 96-channel neural CortexFrame ring — the renderer never sees neural data it cannot decode (D-03)"
    - "Renderer-owned validation at the trust boundary: the integrator is the single point that rejects non-finite velocity and clamps to grid bounds, so the GPU kernel never receives an off-grid/NaN coordinate (D-04 / T-06-02-01)"
    - "Swift-side lock-free SPSC ring mirroring the Phase-3 Rust ring's Release-publish/Acquire-observe discipline (no SeqCst), backed by the built-in Synchronization.Atomic"
    - "Deterministic closed-form synthetic drive (t is the only input) so the frame-pacing soak is bit-reproducible (D-05)"
    - "nonisolated Sendable value/reference types for data crossing into the display-link callback under .defaultIsolation(MainActor.self) + complete strict concurrency (continues the Plan 01 WebgridParams pattern)"

key-files:
  created:
    - Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift
    - Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift
    - Packages/CortexRender/Sources/CortexRender/VelocityRing.swift
    - Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift
    - Packages/CortexRender/Tests/CortexRenderTests/CursorIntegratorTests.swift
    - Packages/CortexRender/Tests/CortexRenderTests/VelocityRingTests.swift
  modified: []

key-decisions:
  - "VelocityRing mechanism (a): power-of-two ContiguousArray + Synchronization.Atomic<Int> head/tail, NOT a second Rust SPSC + cbindgen — RESEARCH Decision 5's 'lean Swift-side now' for the in-process Phase 6 producer; the layout still matches a future #[repr(C)] CursorVelocity so the Phase-7 Rust swap stays transparent (D-03)"
  - "Built-in Synchronization.Atomic over swift-atomics — Swift 6.2 ships Atomic with .acquiring/.releasing orderings, so no SwiftPM dependency is added; probed working on the macOS 26 target before use"
  - "Velocity-scale contract pinned at 1.0: CursorVelocity.vx/vy are grid-units/second and the integrator does pos += velocity*dt with no extra scale factor — makes the magnitude assertions exact and matches the velocity Phase 7's Kalman will emit"
  - "VelocityRing init? is failable (returns nil for zero/non-power-of-two capacity), mirroring the Phase-3 CortexRing capacity guard rather than the interface sketch's non-failable init — the stronger contract D-03 points at"
  - "VelocityRing is @unchecked Sendable with a documented justification — an SPSC ring is shared between exactly two threads BY DESIGN; safety rests on the Atomic Release/Acquire + the one-producer/one-consumer discipline, not on the type system (mirrors Phase-3 CortexRing)"

patterns-established:
  - "Pattern: the renderer's input is a velocity seam, never a position — position is integrated + clamped renderer-side so the seam is unchanged when the real decoder (also velocity) lands (D-03/D-04)"
  - "Pattern: every cross-thread frame type is a trivial fixed-width value (CursorVelocity) copied by value into a ring slot — no heap pointers ⇒ no torn pointer / no use-after-free"
  - "Pattern: a deterministic synthetic producer (t-only) underpins reproducible frame-pacing measurement, the renderer analogue of the Phase-3/4 reproducible test fixtures"

requirements-completed: [RENDER-04, RENDER-06]

# Metrics
duration: 5 min
completed: 2026-06-22
---

# Phase 6 Plan 02: Cursor-Velocity Seam + Renderer-Owned Integrator Summary

**The dedicated `(vx,vy)` fp16 `CursorVelocity` velocity seam (D-03) + the renderer-owned `CursorIntegrator` (D-04, `pos += v*dt` clamped to `[0,1]`, non-finite-velocity rejected), carried over a lock-free Swift `VelocityRing` SPSC (built-in `Synchronization.Atomic`, Release/Acquire — no torn read) and driven by a deterministic `LissajousProducer` (D-05) — the input substrate Plan 03's display-link callbacks pop, integrate, and feed into `WebgridParams.cursor`.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-22T02:32:28Z (RED Task 1, `8031fcc`)
- **Completed:** 2026-06-22T02:37:47Z (GREEN Task 2, `d343323`)
- **Tasks:** 2 (both TDD — 4 commits: RED→GREEN ×2)
- **Files modified:** 6 (6 created, 0 modified)

## Accomplishments

- **`CursorVelocity` — the D-03 seam.** `struct CursorVelocity { ts_ns:UInt64, seq:UInt64, vx:Float16, vy:Float16 }`, `nonisolated Sendable`. Field order (u64 ts_ns, u64 seq, then the fp16 payload) deliberately mirrors `cortex_ring.h`'s `#[repr(C)] CortexFrame` so a future `#[repr(C)] CursorVelocity` + cbindgen Rust producer (Phase 7) is a drop-in. fp16 per DEC-10's 2-vector cursor velocity; trivially copyable (a single store copies the whole frame).
- **`CursorIntegrator` — the D-04 renderer-owned integrator + trust-boundary validator.** `integrate(latest:dt:)`: `nil` latest ⇒ velocity 0 (empty ring → cursor holds); non-finite velocity (NaN/±Inf) ⇒ reject + hold; otherwise `position += velocity * Float(dt)` then `min(max(·,0),1)` clamp. The post-clamp position is provably finite and in `[0,1]`, so the kernel's cursor disc + cell mapping can never receive an off-grid or NaN coordinate (threat T-06-02-01). Callback-safe (no alloc/lock/log).
- **`VelocityRing` — the D-03 in-process SPSC.** Lock-free bounded ring (mechanism (a)): power-of-two-sized `UnsafeMutableBufferPointer<CursorVelocity>` with `Synchronization.Atomic<Int>` head/tail. Producer writes the slot THEN releases `tail`; consumer acquires `tail` THEN reads the slot — Release-publish / Acquire-observe (no SeqCst), so a half-written frame is never observed (T-06-02-02). `init?` rejects zero/non-power-of-two capacity (mirrors `CortexRing`); bounded `push` returns `false` when full (DoS accept, T-06-02-03). `@unchecked Sendable` with a rigorous justification (SPSC discipline, mirrors Phase-3 ring).
- **`LissajousProducer` — the D-05 deterministic drive.** Closed-form `v(t)=(ampX·cos(freqX·t+phase), ampY·sin(freqY·t))` → `Float16`. `t` is the ONLY input — no clock, no RNG, no global state — so two producers with identical params return bit-identical `(vx,vy)` for the same `t` and the 60s soak is bit-reproducible. Defaults (`ampX/freqX ≈ ampY/freqY ≈ 0.4`, `freqX≠freqY`) keep the integrated path sweeping most of the `[0,1]` grid without saturating.
- **Tests: 12 new (full suite 19/19 green).** Integrator: velocity*dt move, upper/lower bounds saturation, NaN-reject, Inf-reject, empty-ring hold, field-order round-trip. Ring: empty pop, push/pop round-trip, FIFO order, bounded-no-corruption, bad-capacity reject, **plus a 200k-frame cross-thread SPSC stress test** (strict-FIFO, zero-loss, no torn read — passed 6/6 consecutive runs). Lissajous: cross-instance determinism, time-variation, integrated-path-on-grid.

## Task Commits

Each task was committed atomically (both TDD → RED then GREEN):

1. **Task 1 (RED): failing CursorVelocity + CursorIntegrator tests** — `8031fcc` (test)
2. **Task 1 (GREEN): CursorVelocity fp16 seam + CursorIntegrator** — `52200e9` (feat)
3. **Task 2 (RED): failing VelocityRing + LissajousProducer tests** — `9520072` (test)
4. **Task 2 (GREEN): VelocityRing SPSC + LissajousProducer + cross-thread stress test** — `d343323` (feat)

_Plan metadata commit owned by the orchestrator (executor does not write STATE/ROADMAP/REQUIREMENTS)._

No REFACTOR commits — both GREEN implementations were already minimal and clean.

## Files Created/Modified

- `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` — the `(vx,vy)` fp16 velocity seam struct, `#[repr(C)]`-compatible field order (created, 46 lines)
- `Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift` — `CursorPosition` + velocity→position integrator with bounds clamp + NaN/Inf rejection (created, 102 lines)
- `Packages/CortexRender/Sources/CortexRender/VelocityRing.swift` — lock-free SPSC bounded ring, `Synchronization.Atomic` Release/Acquire (created, 110 lines)
- `Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift` — deterministic closed-form synthetic velocity drive (created, 64 lines)
- `Packages/CortexRender/Tests/CortexRenderTests/CursorIntegratorTests.swift` — 7 integrator/seam tests (created, 98 lines)
- `Packages/CortexRender/Tests/CortexRenderTests/VelocityRingTests.swift` — 12 ring + Lissajous tests incl. the cross-thread SPSC stress test (created, 171 lines)

## Decisions Made

- **VelocityRing mechanism (a) over a second Rust SPSC** — RESEARCH Decision 5's "lean Swift-side now". A power-of-two `ContiguousArray`-style buffer + `Synchronization.Atomic<Int>` head/tail is enough for the in-process Phase-6 producer and avoids the heavier `#[repr(C)] CursorVelocity` + cbindgen path D-03 explicitly deprioritized for Phase 6. The seam layout still matches a future Rust drop-in.
- **Built-in `Synchronization.Atomic`, not swift-atomics** — Swift 6.2 ships `Atomic` with `.acquiring`/`.releasing`/`.relaxed` orderings; using it adds zero SwiftPM dependencies. Probed working on the `arm64-apple-macos26.0` target before relying on it, and confirmed the module's API surface via Context7.
- **Velocity scale pinned at 1.0 (grid-units/second)** — the integrator does `pos += velocity*dt` with no extra factor, so a velocity of 1.0 over dt=0.1s moves the cursor exactly 0.1. Documented in both `CursorVelocity` and `CursorIntegrator`; makes the magnitude tests exact and matches the velocity Phase 7's Kalman emits.
- **`init?` failable (capacity guard) over the sketch's non-failable `init`** — the interface block sketched `init(capacity:)`, but D-03 says to mirror the Phase-3 `CortexRing`, whose `init?` returns `nil` for zero/non-power-of-two. The failable form is the stronger, contract-faithful choice (covered by the `rejectsBadCapacity` test).
- **`@unchecked Sendable` on `VelocityRing` with justification** — an SPSC ring is shared between exactly two threads by design, so it must cross a concurrency boundary; the compiler can't prove the SPSC discipline. Safety rests on the `Atomic` Release/Acquire + the one-producer/one-consumer invariant (mirrors how the Phase-3 ring is treated). See Deviations (Rule 2).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] D-05 acceptance grep false-positive on a `Date()` literal in a comment**
- **Found during:** Task 2 (acceptance-criteria check)
- **Issue:** The criterion `! grep -qE 'Date\(\)|SystemRandomNumberGenerator|\.random\('` tripped on doc comments in `LissajousProducer.swift` that contained the literal token `Date()` while *documenting its avoidance* ("no `Random`, no `Date()`"; "cos/sin … no Date()/Random"). No clock/RNG is used anywhere — the grep cannot distinguish code from a comment. This is the exact recurring literal-grep pattern documented in Phases 1–5, and a downstream CI grep gate would fail identically.
- **Fix:** Reworded both comments to "no randomness, no wall-clock read" / "no clock, no RNG" without the standalone `Date()`/`Random`/`.random(` literals. Meaning preserved; the gate now passes.
- **Files modified:** `Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift`
- **Verification:** `grep -qE 'Date\(\)|SystemRandomNumberGenerator|\.random\('` over the file returns nothing; full suite still 19/19 green.
- **Committed in:** `d343323` (Task 2 GREEN commit)

**2. [Rule 2 - Missing Critical] `VelocityRing` could not cross the producer/consumer thread boundary it is designed for — added `@unchecked Sendable`**
- **Found during:** Task 2 (building the cross-thread stress test under Swift 6 strict concurrency)
- **Issue:** `VelocityRing` is a non-`Sendable` `final class`, so capturing it in the producer `Thread`'s `@Sendable` closure raised `capture of 'ring' with non-Sendable type 'VelocityRing'`. But crossing to a second thread is the *entire purpose* of an SPSC ring (D-03: one producer thread, one display-link consumer thread). Without a `Sendable` conformance the seam is unusable for its designed use — a correctness gap, not a style nit.
- **Fix:** Marked `VelocityRing: @unchecked Sendable` with a rigorous justification comment: safety rests on (1) `Atomic` head/tail Release-publish/Acquire-observe (no torn read), (2) the invariant that only the producer writes a slot + advances `tail` and only the consumer reads a slot + advances `head`, and (3) `CursorVelocity` being a trivial value type (no shared heap state). This mirrors how the Phase-3 `CortexRing` is treated — the SPSC guarantee is a caller-upheld discipline, not type-system-enforced.
- **Files modified:** `Packages/CortexRender/Sources/CortexRender/VelocityRing.swift`
- **Verification:** `swift build --build-tests` clean (no Sendable warnings); the cross-thread stress test (200k frames) passes 6/6 consecutive runs with zero corruption.
- **Committed in:** `d343323` (Task 2 GREEN commit)

**3. [Rule 2 - Missing Critical] Added a cross-thread SPSC stress test for the core concurrency claim**
- **Found during:** Task 2 (GREEN — the single-thread tests pin FIFO/bounded but not the actual cross-thread torn-read mitigation)
- **Issue:** The plan's `<behavior>` lists single-thread ring tests, but the load-bearing truth of D-03 ("no torn read across the producer/consumer seam") and threat T-06-02-02 are *concurrency* claims. A single-threaded test never exercises the Acquire/Release ordering under real contention, so the mitigation would be asserted but unverified.
- **Fix:** Added `spscCrossThreadStrictFIFO` — one producer thread pushes 200k monotonic-seq frames (vx encodes seq) while the consumer drains on the test thread, asserting strict FIFO, zero loss, and `vx`-matches-`seq` (a torn slot would mismatch). This is the multi-threaded analogue of the Phase-3 ring's 1M-frame strict-FIFO zero-loss test. (Two minor test-mechanic fixes inside this addition: failable `init?` required `try #require(...)` unwraps on the four ring bindings; `Thread.yield()` does not exist in Swift Foundation → used POSIX `sched_yield()` via `import Darwin`.)
- **Files modified:** `Packages/CortexRender/Tests/CortexRenderTests/VelocityRingTests.swift`
- **Verification:** Passes 6/6 consecutive runs (`--filter spscCrossThreadStrictFIFO`); `corrupt == 0`, all 200k frames observed exactly once in order.
- **Committed in:** `d343323` (Task 2 GREEN commit)

---

**Total deviations:** 3 auto-fixed (1 blocking grep-reword, 2 missing-critical: a required `Sendable` conformance + the concurrency test that actually proves the threat mitigation).
**Impact on plan:** All three were necessary for correctness/verifiability and stayed within scope — the four artifacts, the D-03/D-04/D-05 contract, and the threat mitigations are exactly as specified. No new runtime dependency (the `Synchronization` module is built into Swift 6.2). No scope creep.

## Issues Encountered

- During the GREEN of Task 2 the four ring tests binding `let ring = VelocityRing(capacity:)` failed to compile because `init?` is failable — resolved within the same RED→GREEN iteration by switching to `try #require(...)` (Swift Testing's unwrap), keeping the strong capacity guard. No verification-gate escalations; no architectural (Rule 4) decisions needed.

## Known Stubs

None. All four types are fully implemented and wired to each other (the `integratedPathStaysOnGrid` test drives the real `LissajousProducer` → `CursorIntegrator` end-to-end). The seam is intentionally fed by a *synthetic* producer in Phase 6 by design (D-05); the Phase-5 decoder + Phase-7 Kalman become the producer behind the unchanged D-03 seam — that is the planned evolution, not a stub.

## Threat Flags

None beyond the plan's `<threat_model>`. The introduced surface is exactly the producer→ring→consumer seam + velocity validity at the integrator: T-06-02-01 (off-grid/NaN velocity) is mitigated by the integrator's non-finite rejection + `[0,1]` clamp (5 unit tests); T-06-02-02 (torn read) is mitigated by `Atomic` Release/Acquire and verified by the 200k-frame cross-thread stress test; T-06-02-03 (producer outpaces consumer) is the accepted disposition — bounded `push` returns `false` and the caller drops the surplus. In-process only — no network/auth/persistence/external input.

## User Setup Required

None - no external service configuration required. No new dependency was added (`Synchronization` is built into the Swift 6.2 toolchain).

## Next Phase Readiness

- The full input contract is fixed and compiling for Plan 06-03: the display-link callback (iOS `CAMetalDisplayLink` / macOS `NSScreen.displayLink`) constructs a `VelocityRing`, a `LissajousProducer` pushes `CursorVelocity` frames on a producer thread, and each callback pops the latest, calls `CursorIntegrator.integrate(latest:dt:)` with the `targetPresentationTimestamp` delta, and feeds the resulting `CursorPosition` into `WebgridParams.cursorX/cursorY` (Plan 01's `WebgridFrameEncoder`).
- The `LissajousProducer` is the deterministic drive for the 60s 120Hz soak (SC#4) in Plan 06-04/05/06; its reproducibility is what makes the frame-pacing numbers stable.
- Phase 7 readiness: because the seam is velocity-typed and the integrator is renderer-owned, the ReFIT-Kalman becomes the `VelocityRing` producer with no consumer-side change; the `CursorVelocity` field order is already `#[repr(C)]`-compatible for a cbindgen Rust producer if that path is chosen.
- No blockers.

## Self-Check: PASSED

- All 6 created source/test files verified on disk.
- All 4 task commits (`8031fcc`, `52200e9`, `9520072`, `d343323`) verified in `git log`.
- `swift test --package-path Packages/CortexRender` 19/19 green (debug); `swift build -c release` clean under complete strict concurrency (no warnings); the full plan `<verification>` block passes; the cross-thread SPSC stress test green 6/6.
- STATE.md / ROADMAP.md / REQUIREMENTS.md NOT modified by this executor (orchestrator-owned).

---
*Phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid*
*Completed: 2026-06-22*
