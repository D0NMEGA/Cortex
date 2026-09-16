---
status: PARTIAL
agent: donny-integration-checker
phase: 10-v1-real-data-closed-loop-launch
connected: 5
orphaned: 3
missing: 3
broken_flows: 0
---

## Integration Check Complete

Scope: milestone v1.0 "Real-Data Decoding", all 10 roadmap phases
(`01-foundation-2026-toolchain` through `10-v1-real-data-closed-loop-launch`). This report is
filed under Phase 10 (the milestone-closing phase) but every seam below was checked against the
live source tree, not against phase-local docs alone.

This is a Swift/Rust/Python native pipeline, not a web app: there are no HTTP API routes and no
auth routes in the REST sense. "API Coverage" below is read as SwiftPM product boundaries / C-ABI
headers and whether anything imports/calls them; "Auth Protection" is read as the entitlement/App
Group boundary that gates cross-process access to the shared-memory transport.

### Wiring Summary

**Connected:** 5 of 8 named seams fully wired end-to-end with file:line evidence (Seams 1, 4, 5,
6, 8).
**Orphaned:** 3 exports built, tested in isolation, and never consumed by any production code path
(all three are the Phase-3 Rust-ring surface).
**Missing:** 3 expected connections not found in source (hot-path thread -> decoder; daemon's
actual producer -> a `QOS_CLASS_USER_INTERACTIVE` pthread; interactive-app cursor -> real BCI HID
pointer report).

### API Coverage (SwiftPM product / C-ABI surface)

**Consumed:** `CortexCoreC` (shm/fdmsg/rendezvous headers) by `CortexIPCTransport`; `CortexIPC`
(`CortexIPCTransport`/`CortexIPCSession`) by `Apps/CortexDaemon` and `CortexSeamBSmoke`;
`CortexDecoder` by `CortexDemo`/`CortexReFIT`; `CortexReFIT`/`CortexRender` by `CortexDemo`;
`CortexBCIHID` by `CortexDemo`/`Apps/CortexMac`; `cortex_ring.h` (Rust C ABI) by `CortexRing`'s own
Swift wrapper.
**Orphaned:** `CortexRingHotPath` (product) and `CortexRing` (product, the consumer wrapper) are
declared, build, and link, but have zero non-test / non-self consumers anywhere in the repo. See
Detailed Findings.

### Auth Protection (App Group / entitlement boundary)

**Protected:** the one cross-process trust boundary in this repo is the App Group container
(`group.com.donovansantine.cortex.shared`) plus the mach-fileport handoff. Both ends agree:
`Packages/CortexCore/Sources/CortexCore/AppGroup.swift:10` defines the identifier;
`project.yml:119,166,223` declares the identical string in `com.apple.security.application-groups`
for `CortexiOS`, `CortexMac`, and `CortexDaemon`. The shm fd itself is never handed over BSD
`SCM_RIGHTS`; it crosses via `fileport_makeport` inside one `MACH_MSG_PORT_DESCRIPTOR`
(`Packages/CortexCore/Sources/CortexCoreC/cortex_fdmsg.c:1-16`, called from
`Apps/CortexDaemon/Producer.swift:142`), and CI greps for a stray `SCM_RIGHTS` token. Session keys
are Keychain-stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(`SessionKeychain.swift`, IPC-06).
**Unprotected:** none found in scope. Cross-process Keychain access-group sharing stays the
pre-existing, previously-accepted Phase-2 risk (single-process fallback under the free signing
team) — not a new finding here.

### E2E Flows

**Flow A — real Indy session -> ingest -> decoder -> ReFIT-Kalman -> cursor -> 120Hz webgrid
render (Phase 10 replay, v1 headline path).**
Status: **COMPLETE** (every stage is genuinely wired; the published result is a pre-registered
negative finding, not a break).
1. `Decoder/scripts/export_replay.py:50,246` — `from ndt1.data import BIN_MS, load_session`;
   `session = load_session(mat_path)` on the real, SHA-pinned Indy `.mat` file -> writes
   `Decoder/exports/indy_20160630_01.replay.bin` + `.replay.json` (present on disk).
2. `Packages/CortexCore/Sources/CortexCore/ReplayExport.swift` is the one Swift reader of that
   export; `Packages/CortexDemo/Sources/CortexDemo/RecordedSpikeSource.swift` wraps it as a
   `SpikeWindowSource`.
3. `Packages/CortexDemo/Sources/CortexDemo/ReplayPipeline.swift:506-517` (`tick()`) and `:727-768`
   (`runToHit`) route the window through `decode(window:...)`, which calls
   `NeuralDecoder.decode` when `CORTEX_MODEL_URL` is set. The RD-08 canonical run set it to the
   real Phase-9 checkpoint: `CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage`
   (`.planning/phases/10-v1-real-data-closed-loop-launch/10-replay-evidence.md:27,437,441,447`),
   and 10-PREREGISTRATION section 10 requires a hard `precondition` failure if any tick silently
   fell back to the synthetic decoder — i.e. the real run is asserted model-backed on every tick,
   not just configured to be.
4. `filter.step(measurement: decoded, target:, acquisitionRadius:)` — `CortexReFIT.KalmanFilter`,
   gains fit on real data: `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift:9`
   literally carries `noise source = indy-heldout   seed = 0` and
   `session=indy_20160630_01 sha256=2ca8f6b7fcfc...`.
5. `integrator.integrate(...)` (Phase-6 `CursorIntegrator`) -> `ring.push(CursorVelocity(...))`
   (`Apps/CortexMac/ReplayDriver.swift:290-295`) -> the SAME `VelocityRing` instance is handed to
   `WebgridView(ring: driver.ring, ...)` (`Apps/CortexMac/ContentView.swift:137-138`) -> drained by
   `MacDisplayLinkAdapter.swift:162-163` and drawn.
6. Measured outcome, `10-replay.json`: 0/1025 webgrid hits on both target-blind arms. Per the task
   scope and RD-08/RD-09, this is a pre-registered published negative result, not a wiring gap —
   the pipe carries real data through every stage; the number it produces is honest, not missing.

One accuracy caveat for the record, not a break: steps 3-5 run on a `Timer` dispatched onto
`MainActor` (`Apps/CortexMac/ReplayDriver.swift:158-159`), not on the Phase-3
`QOS_CLASS_USER_INTERACTIVE` pthread. `ReplayDriver.swift`'s own doc comment (line 17) says so
outright: "the PRODUCER runs on the main actor — a timer, not a background thread (the Phase-3
acquisition pthread is a separate concern)." Flow A completes, just not through the audio-callback
hot path THREAD-01..03 describe. Detail under Seam 2/3 below.

**Flow B — decoder intent -> BCI HID report -> system cursor (structural path; live device
registration correctly deferred).**
Status: **COMPLETE at the structural level, but only inside the CI-only smoke tool** — the
interactive app does not exercise this same path.
1. `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift` (run in CI:
   `.github/workflows/ci.yml:540`) replays the real export through AES-GCM seal -> `ShmRing` ->
   `Doorbell` (in-process, producer/consumer lock-step over the real Phase-2 transport) -> decrypt
   -> `RollingSpikeWindow` 32-bin accumulation -> `SpikeInputBuffer` -> `NeuralDecoder.decode` ->
   `CursorIntegrator.integrate` -> `BCIInputPointerReport(position: pointerTriple(for: position))`
   at line 467, built from the real decoded/integrated position and encoded.
2. Live `IOHIDUserDevice`/Switch-Control registration is `#if CORTEX_HID_LIVE`-gated
   (`Packages/CortexBCIHID/Sources/CortexBCIHID/VirtualDeviceGate.swift`) and deferred to a paid
   Apple Developer account + iPad Pro M4 (`08-VERIFICATION.md` Gate 3). Per the task's explicit
   instruction this is not counted as an integration gap.
3. Caveat: `Apps/CortexMac` and `Apps/CortexiOS` never construct a `BCIInputPointerReport` from the
   real cursor position (grep-confirmed zero hits outside `CortexSeamBSmoke`/tests/the
   `CortexBCIHID` package itself). The interactive app's only BCI-HID exercise is
   `roundTrip.respond(to: scanInfo)` (`Apps/CortexMac/ReplayDriver.swift:305-310`), and `scanInfo`
   is built from a raw sequence counter, not `state.position`. This is a documented, deliberate
   design, not an oversight — `ScanInfoRoundTrip.swift:39-42`: "'Closed loop' here means the HID
   PROTOCOL loop... and nothing about neural control: callers drive it with their own
   selectedItem... `CortexMac` drives it from a sequence counter for exactly this reason." So the
   real decoder-position -> HID-pointer-report capability is proven, but only reachable by running
   the CLI tool, not the shipped GUI app.

### Detailed Findings

#### Orphaned Exports

1. **`CortexRingHotPath.CortexAcquisition.run`**
   (`Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift:168-`) — the Phase-3
   THREAD-01/02/03 pthread entry point. Repo-wide grep for `CortexAcquisition.run` /
   `CortexAcquisition\b` returns exactly two hits, both inside `Acquisition.swift` itself (a doc
   comment referencing itself and the `enum` declaration). Nothing calls it — not `Apps/CortexDaemon`
   (which declares the product dependency in `project.yml` but has zero `import CortexRingHotPath`
   in its 4 source files), not even `CortexRing`'s own `RingIntegrationTests.swift`, which drives
   `Ring.swift`'s `push`/`pop` directly and never touches `CortexAcquisition`. `03-VERIFICATION.md`'s
   own "Human Verification Required" section confirms the one place this was ever meant to run (a
   50M-frame Instruments capture) is still pending, hardware-gated, never executed.
   No deferral text schedules production wiring for this in a later phase: `10-06-PLAN.md:186`
   explicitly instructs the opposite — "Packages/CortexRing/Sources/CortexRingHotPath (the repo's
   existing ring-buffer idiom, for naming and index arithmetic style only - do NOT reuse it; this
   accumulator is not on the hot path)." Classified ORPHANED, with the caveat that non-reuse is a
   documented decision by Phase 10, not a silent miss.

2. **`CortexRing`** (the safe RAII Swift consumer wrapper,
   `Packages/CortexRing/Sources/CortexRing/Ring.swift`) — `import CortexRing` occurs exactly once
   in the whole repo outside its own package: nowhere. The only hit is its own
   `Tests/CortexRingTests/RingIntegrationTests.swift`. Its own package header comment states the
   intended role: "producer -> ring -> Phase-6 CAMetalDisplayLink consumer" — that consumer was
   never built against `CortexRing`. Phase 6 instead built a parallel, Swift-native ring
   (`Packages/CortexRender/Sources/CortexRender/VelocityRing.swift`) with an explicit rationale:
   "Per D-03 the velocity seam reuses the Phase-3... ring DESIGN — but in-process and Swift-side"
   (i.e., mirrored, not reused). Classified ORPHANED for the actual artifact; the requirement it
   was meant to satisfy (THREAD-04's "bridges decoder thread to UI") is satisfied instead by
   `VelocityRing`, a different, later-built component.

3. **`CortexRingPing`** (`Packages/CortexRing/Sources/CortexRingPing/Ping.swift`) — an FFI
   link-smoke target; `import CortexRingPing` occurs only in its own
   `Tests/CortexRingTests/PingSmokeTests.swift`. Minor — by name and purpose this appears to be a
   link-only smoke check, not a component anything downstream was ever meant to call. Listed for
   completeness, not weighted as a defect on its own.

#### Deferred Connections

- **SYS-01/SYS-02 live half** (on-device `IOHIDUserDevice`/`SMAppService` registration as a Switch
  Control HID provider) — `Packages/CortexBCIHID/Sources/CortexBCIHID/DaemonRegistration.swift`
  and `VirtualDeviceGate.swift` are consumed by nothing outside their own package/tests, gated
  behind `#if CORTEX_HID_LIVE` (default off). `08-VERIFICATION.md` lines 144-145 and its Gate 3
  section explicitly carry this as a HUMAN-UAT deferral (paid Apple Developer enrollment + live
  device), matching the task's instruction that a deferred device capture is not an integration
  gap. Informational, not a break.
- **DIST-01..03 live half** (notarytool submission, `fastlane match`, TestFlight upload) —
  structurally present (`fastlane/Fastfile`, `Tools` policy gates) but the live run is
  `08-VERIFICATION.md` Gate 1, HUMAN-UAT-deferred for the same paid-account reason. Informational.
- **LAT-01..08** (photodiode latency rig) — explicitly RETIRED to Future work in `ROADMAP.md` /
  `REQUIREMENTS.md`, not scheduled for v1. Correctly out of scope for this check.

#### Missing Connections

1. **Phase-3 hot-path pthread -> Phase-5 CoreML decoder call path (the task's Seam 3).**
   No hot-path/`CortexRingHotPath` code feeds `NeuralDecoder.decode` anywhere. The decoder's actual
   callers are: `Apps/CortexMac/ReplayDriver.swift:158-159` — a `Timer` dispatched via
   `MainActor.assumeIsolated { self?.step() }` — and
   `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift`, which runs its whole chain
   sequentially in `main()` with no `pthread_create` ("The chain below runs IN ONE PROCESS, in
   producer/consumer lock-step," per its own header comment). This is self-acknowledged in-repo
   (`ReplayDriver.swift` line 17: "the Phase-3 acquisition pthread is a separate concern"), so it
   is a known, named gap rather than a hidden one, but the requirement text (THREAD-04: "bridges
   decoder thread to UI") and the Acquisition.swift header ("producer -> ring -> Phase-6
   CAMetalDisplayLink consumer") both describe a production role that never materialized.
   Affects: THREAD-01, THREAD-02, THREAD-03, THREAD-04, THREAD-06.

2. **The daemon's actual production producer never runs on a `QOS_CLASS_USER_INTERACTIVE`
   pthread.** `Apps/CortexDaemon/main.swift`'s default ("produce") path calls
   `Harness.runParent(frameCount:)` (`Apps/CortexDaemon/Harness.swift:35`) ->
   `Producer.produce(frameCount:)` (`Apps/CortexDaemon/Producer.swift:195`) on the daemon's
   ordinary calling thread. Grep for `pthread_create` across `Producer.swift`, `Harness.swift`,
   and `main.swift` returns zero hits; the only `pthread_create` in `Apps/CortexDaemon` is
   `Benchmark.swift:162`, used only by the separate `bench` CLI mode that measures round-trip
   latency, not the mode that actually produces the daemon's data. `project.yml` links
   `CortexRingHotPath` into the `CortexDaemon` target (confirmed by
   `03-03-SUMMARY.md:80`: "ProcessXCFramework links libcortex_ring.a into the daemon"), but no
   `.swift` file under `Apps/CortexDaemon` imports it — a link-level dependency with zero
   source-level consumption.
   Affects: THREAD-01, THREAD-02, IPC-02 (the shm producer exists and works, just not on the
   hot-path thread the requirement specifies).

3. **Interactive app (CortexMac/CortexiOS) never constructs a `BCIInputPointerReport` from the
   real decoded cursor position.** Confirmed by grep: `BCIInputPointerReport` appears only in
   `CortexSeamBSmoke/main.swift`, the `CortexBCIHID` package's own sources/tests. The GUI's only
   BCI-HID exercise, `ScanInfoRoundTrip`, is deliberately fed by a sequence counter, not real
   cursor state (see Flow B above). The real-cursor -> HID-pointer-report capability exists and is
   tested, but only via the CI-only `CortexSeamBSmoke` binary.
   Affects: SYS-03, SYS-04 (satisfied on their own protocol-round-trip terms) and SYS-06
   (the "closed loop" claim's HID leg, for the interactive app specifically).

#### Broken Flows

None. Both assessed flows (A and B) complete end-to-end through at least one real, exercised code
path; see the caveats recorded inline under each flow above and under Missing Connections.

#### Unprotected Routes

None found. See Auth Protection above.

#### Requirements Integration Map

| Requirement | Integration Path | Status | Issue |
|-------------|-------------------|--------|-------|
| FOUND-02 | `AppGroup.identifier` (Phase 1) -> `project.yml` entitlements (Phase 1) -> consumed by `ShmRing`/`Producer` (Phase 2) | WIRED | - |
| FOUND-04 | SwiftPM package graph (Phase 1) -> `CortexIPC`/`CortexRing`/etc. `.package(path:)` graph (Phases 2-10) | WIRED | - |
| IPC-01 | `ShmRing`/`cortex_shm.h` (Phase 2) -> `Apps/CortexDaemon/Producer.swift` (Phase 2 target) -> `CortexSeamBSmoke` (Phase 10) | WIRED | - |
| IPC-02 | `Doorbell` kqueue/recvmsg (Phase 2) -> `Producer.swift`/`HarnessConsumer` (Phase 2), reused by `CortexSeamBSmoke` (Phase 10) | WIRED | Producer runs on the daemon's ordinary thread, not a dedicated pthread (see Missing Connections #2) |
| IPC-03 | `cortex_fdmsg.c` fileport (Phase 2) -> `Producer.swift:142` `FDChannel.send` (Phase 2) | WIRED | - |
| IPC-04, IPC-05 | `SampleCodec`/`SessionCrypto` (Phase 2) -> reused verbatim by `CortexSeamBSmoke` (Phase 10, `import CortexIPCSession`) | WIRED | - |
| THREAD-01, THREAD-02, THREAD-03 | `Acquisition.swift` pthread (Phase 3) -> intended consumer: decoder call path (Phase 5) | UNWIRED | No caller anywhere; decoder fed via `MainActor` `Timer` / sequential `main()` instead (Missing Connection #1) |
| THREAD-04, THREAD-06 | `cortex_ring.h`/`Ring.swift` (Phase 3) -> intended consumer: renderer (Phase 6) | PARTIAL | Bridge itself wired + tested (`RingIntegrationTests`); production "UI" consumer never built against it — Phase 6 built `VelocityRing` instead (Orphaned Export #2) |
| THREAD-05, THREAD-07 | Rust ring internal correctness (loom, atomics) | WIRED (self-contained) | No cross-phase consumer expected; property of the ring itself |
| DEC-03, DEC-09 | `coremltools` export (Phase 4/9) -> `.mlpackage` -> `NeuralDecoder`/`ZeroCopyInput` (Phase 5) -> `ReplayPipeline`/`CortexSeamBSmoke` (Phase 10) | WIRED | Confirmed the *real* `ndt1_real_vel_sweep_fp16.mlpackage` (Phase 9), not a stale Phase-4 synthetic artifact, via `10-replay-evidence.md:437` |
| DEC-06, DEC-08 | Phase 5 ANE-eligibility methodology -> re-applied to the real-data graph (Phase 9, RD-06) | WIRED | Op tally corrected 226->239 in Phase 9, methodology reused |
| DEC-10 | `NeuralDecoder.decode` (vx,vy) output (Phase 5) -> `ReplayPipeline.decode(window:)` (Phase 10) | WIRED | - |
| REFIT-01, REFIT-02 | `KalmanFilter.step` (Phase 7) -> `ReplayPipeline.tick()`/`runToHit` (Phase 10) | WIRED | - |
| REFIT-03 | Phase 7 synthetic BPS ablation -> re-run on real data (Phase 10, RD-07) | WIRED | Uplift did not survive real spikes; published as negative, not a wiring gap |
| RENDER-01, RENDER-04, RENDER-06, RENDER-07, RENDER-08 | `CAMetalDisplayLink`/`NSScreen.displayLink` + `VelocityRing` + `WebgridView` (Phase 6) -> driven by Phase 7/10 Kalman output | WIRED | `ReplayDriver.swift:290-295` push -> `ContentView.swift:137-138` same-ring handoff -> `MacDisplayLinkAdapter.swift:162-163` pop |
| SYS-01, SYS-02 | HID protocol surface (Phase 8) -> live registration | DEFERRED | Structural only; live half is a HUMAN-UAT hardware/account gate (not a gap per task scope) |
| SYS-03, SYS-04 | `ScanInfoRoundTrip` (Phase 8) -> `Apps/CortexMac/ReplayDriver.swift:305-310` | WIRED (by its own protocol-only definition) | Deliberately decoupled from real cursor position (documented in `ScanInfoRoundTrip.swift:39-42`) |
| SYS-06 | `ReplayPipeline`/`ClosedLoopPipeline` (Phase 8) genuinely chains decoder + Kalman | WIRED | - |
| RD-01, RD-02 | `ndt1.data.load_session` (Phase 9) -> `export_replay.py` -> `Decoder/exports/*.replay.{bin,json}` | WIRED | - |
| RD-03..RD-06 | Phase 9 real-data retrain/palettization/CoreML re-verify -> feeds Phase 10 measurements | WIRED | - |
| RD-07 | Phase 9 real spikes -> `Decoder/scripts/fit_kalman_gain.py` -> `KalmanConstants.swift:9` (`noise source = indy-heldout`) -> Phase 7 filter (Phase 10) | WIRED | - |
| RD-08 | Real export -> decoder -> Kalman -> cursor -> webgrid (Flow A) | WIRED | 0/1025 hits is a published negative result, not a broken seam |
| RD-09, RD-10 | `honesty-sweep.sh`/`readme-policy.sh` (Phase 10) -> scan every phase's evidence docs/README | WIRED | CI-wired (`ci.yml:334-335`, `:360-361`) with `--self-test` |
| DIST-04 | README aggregates claims from Phases 4-10 | WIRED (cross-cutting) | Policed by `readme-policy.sh`/`honesty-sweep.sh` |
| PERF-04 | `GlassToGlassTimer` (Phase 8) -> reused for Seam A real-data measurement (Phase 10) | WIRED | - |

**Requirements with no cross-phase wiring** (single-phase, self-contained by design — not flagged
as gaps):
FOUND-01, FOUND-03, FOUND-05 (toolchain/privacy-manifest/CI infra); IPC-06, IPC-07 (Phase-2-internal
Keychain storage and latency measurement); DEC-01, DEC-02, DEC-04, DEC-05, DEC-07, DEC-11, DEC-12
(Phase-4/5-internal architecture, training, layout, compute-units, latency and private-API gates);
RENDER-02, RENDER-03, RENDER-05, RENDER-09 (Phase-6-internal frame-rate/GPU-time measurement,
Info.plist flag, HUD diagnostic); DIST-01, DIST-02, DIST-03 (Phase-8-internal distribution tooling,
live half HUMAN-UAT-deferred); PERF-01, PERF-02, PERF-03 (reporting/methodology text, not runtime
wiring); LAT-01..LAT-08 (retired, not scheduled for v1).
