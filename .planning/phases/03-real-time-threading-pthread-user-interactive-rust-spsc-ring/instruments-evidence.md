# Phase 3 SC#1 Evidence — pthread USER_INTERACTIVE acquisition hot path, zero Swift cooperative-runtime activity

**Date:** 2026-06-20 (runbook authored; the M4 System-Trace capture is a deferred manual step — see "Capture status" below)
**Result:** ⏳ **Runbook + always-on CI proxy committed; `.trace` capture deferred to an M4/M5 Instruments session** (the established Phase-1 SC#2 / Phase-2 SC#1 hardware-evidence split, D-18).

> **SC#1 (Phase 3 Success Criterion #1):** "The acquisition/DSP hot path runs on a raw `pthread_create`
> worker pinned to `QOS_CLASS_USER_INTERACTIVE` with **zero Swift cooperative-runtime activity under
> load** — no `swift_task_*` / libdispatch (`_dispatch_*`) frames execute on that thread while it
> produces frames into the Rust SPSC ring." This is the structural guarantee the sub-25 ms
> glass-to-glass budget rests on: the hot path must be in the audio-callback regime (no cooperative
> scheduler, no locks, no ARC, no Foundation), exactly as the project constraints mandate.

This is **hardware-gated, manual evidence (D-18)**, mirroring Phase 1 `sc2-evidence.md` and Phase 2
`sc1-evidence.md`. **Instruments → System Trace cannot run in CI** (no GUI, no Instruments on the
`macos-15` runner, and a profiler attaches to a live process on real Apple Silicon). So CI attests the
*structural* invariant — the always-on hot-path policy gate (below) — and the per-milestone System-Trace
capture is the *behavioural* proof on M4-class hardware.

---

## What SC#1 claims (the behavioural invariant)

The acquisition worker is `CortexAcquisition.run(ring:frames:)` →
`cortexAcquisitionThread` in `Packages/CortexRing/Sources/CortexRingHotPath/Acquisition.swift`. It is a
raw `pthread_create` thread whose **first action** is
`pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)`. It then runs an allocation-free,
lock-free produce loop that stamps a monotonic `ts_ns`/`seq` into one reused `CortexFrame` and calls
`cortex_spsc_push` (a Rust C-ABI call). The invariant to prove on hardware:

- the worker thread shows the **QoS = USER_INTERACTIVE** band in the System-Trace thread state, and
- **NO `swift_task_*` frames** (no `swift_task_create` / `swift_task_switch` / `swift_continuation_*` /
  `swift_job_run`) and **NO libdispatch frames** (`_dispatch_*` / `dispatch_async`) appear on that
  thread's call-tree under load. (ARC traffic — `swift_retain`/`swift_release` — is likewise absent on
  the steady-state loop because the worker reconstructs the ring from an **unretained** raw handle and
  allocates nothing per frame.)

This is the in-process producer half of the Phase-3 topology (RESEARCH §4):
`[acquisition pthread @ USER_INTERACTIVE] —push→ [Rust SPSC ring] —pop→ [Phase-6 CAMetalDisplayLink consumer]`.

---

## Why this is manual / hardware-gated (and what CI does instead)

| Signal | Venue | Cadence | What it proves |
|--------|-------|---------|----------------|
| Instruments → **System Trace** (this runbook) | **M4 / M5 hardware**, manual | per milestone | The *behavioural* SC#1 claim: zero `swift_task_*`/libdispatch frames on the worker under load. |
| **`Tools/scripts/hotpath-policy.sh`** (the CI proxy) | **CI** (`ci.yml` "Hot-path policy" step) | **every push** | The *structural* SC#1 claim: no cooperative-dispatch / `Task` / lock / Foundation / `import ObjectiveC` token can enter the policed hot-path sources (Swift/C **and** the Rust ring `.rs`). A regression cannot land silently between manual captures. |

The split is the same one Phase 1 used for SC#2 (`sc2-evidence.md` — entitlement behaviour proven on
hardware, structural grep in CI) and Phase 2 used for SC#1 (`sc1-evidence.md` — the sub-µs number on
hardware, correctness harness in CI). Instruments is a GUI profiler on a live process; it is not
scriptable on a headless runner, so the trace belongs to M-series hardware and CI never asserts it.

---

## Exact runbook (reproducible on M4-class Apple Silicon)

**Prerequisites:** real Apple Silicon, **M4-class or better** (an **M5 Pro ≥ M4** is acceptable — the
Phase-2 `sc1-evidence.md` precedent), `xcode-select -p` → Xcode 26.3 (not CommandLineTools), Swift 6.2.x.
Build the Rust xcframework first (the `make bootstrap` analogue): `Tools/scripts/build-rust.sh`.

1. **Drive the worker under load.** Add a tiny throwaway probe (or a `bench`-mode entry in the daemon)
   that creates a ring and runs the worker for a large frame count, so the System Trace has a long,
   steady window to sample:
   ```swift
   // probe main (Release; the loop must be optimized — an -Onone loop muddies the trace)
   import CortexRingFFI
   import CortexRingHotPath
   let ring = cortex_spsc_create(1024)!                 // consumer-side allocation
   defer { cortex_spsc_destroy(ring) }
   CortexAcquisition.run(ring: ring, frames: 50_000_000) // long enough to capture under System Trace
   ```
   Build it **Release**: `swift build -c release` (or run the daemon Release binary). A consumer that
   pops on another thread can be added, but is not required to prove the *producer* thread's regime.

2. **Record a System Trace.**
   - Open **Instruments** → **System Trace** template (or **Time Profiler** + the **Thread State**
     track).
   - Target the running probe/daemon process; **Record** for ~5–10 s while the worker is producing.

3. **Locate the acquisition worker thread.** In the trace's thread list, find the thread whose
   **QoS = User Interactive** and whose busy time is dominated by `cortexAcquisitionThread` /
   `cortex_spsc_push`. (It is a raw pthread, so it has no GCD queue label — that absence is itself part
   of the proof.)

4. **Confirm the invariant on that thread:**
   - **QoS band == User Interactive** for the whole capture (Thread State track).
   - **Call tree contains NO `swift_task_*`** symbols and **NO `_dispatch_*` / libdispatch** symbols.
     The hot frames should be only `cortexAcquisitionThread` → `cortex_spsc_push` (+ `mach_absolute_time`).
   - **No `swift_retain`/`swift_release`** churn on the steady-state loop (the unretained-handle /
     no-alloc contract).

5. **Capture the evidence.** Save the `.trace` and a screenshot of the worker thread's call tree +
   QoS band, and commit them next to this runbook:
   - `instruments-systemtrace.trace` (the System Trace document)
   - `instruments-worker-calltree.png` (screenshot: worker thread, QoS = User Interactive, no
     `swift_task_*`/libdispatch frames)

   Then change the **Result** header above to ✅ **PASS** and record the machine/OS/Xcode line (mirror
   `sc1-evidence.md`'s Environment table).

---

## Pass criterion + negative control

- **PASS** ⟺ on the acquisition worker thread, under load: QoS = USER_INTERACTIVE **and** zero
  `swift_task_*` frames **and** zero libdispatch (`_dispatch_*`) frames in the call tree.
- **Negative control (the gate bites):** add a Swift cooperative-runtime construct to the hot-path
  directory — e.g. a `Task { … }` or a `DispatchQueue.global().async { … }` inside
  `Packages/CortexRing/Sources/CortexRingHotPath/` — and run `./Tools/scripts/hotpath-policy.sh`. It
  **exits 1** (the cooperative-dispatch / structured-task token is forbidden), failing the build before
  such a regression could ever reach a System-Trace capture. This is the **always-on CI proxy** for
  SC#1 and is cross-referenced to **Plan 03-03 Task 2** (the extended gate + its negative-control
  self-test, which injects every forbidden token across `.swift`/`.c`/`.rs` and asserts exit 1 on each).
  The structural proxy is what guarantees a cooperative-runtime regression on the hot path cannot sit
  undetected between the per-milestone manual captures (threat T-03-03-03).

---

## Capture status (deferred manual step — D-18 precedent)

The **runbook and the always-on CI proxy are the committed deliverable of Plan 03-03.** The `.trace` +
screenshot capture is a **deferred manual step**, exactly as the Phase-1 SC#2 and Phase-2 SC#1
hardware evidence were produced on a dedicated Instruments session rather than during automated
execution. It is recorded in the phase's deferred items and STATE Deferred Items, and is closed by
running this runbook on an M4/M5 Instruments session. Until then:

- The **structural guarantee is fully in force every CI run** via `hotpath-policy.sh` (SC#2 row) — the
  hot path provably contains no cooperative-runtime / lock / Foundation token in Swift, C, or the Rust
  ring sources.
- The **code is structurally correct by construction**: `Acquisition.swift` `import Darwin` only,
  pins QoS as its first action, uses a POD `@convention(c)` boundary with an unretained handle, and
  pushes over the C ABI with no allocation on the loop (verified by `swift build` + the gate +
  swiftformat/swiftlint, Plan 03-03 Task 1).

The System-Trace capture refines this from "structurally guaranteed" to "behaviourally observed on
hardware"; it does not change the verdict, mirroring how the Phase-2 quiet-machine re-run would refine
the tail, not the sub-µs verdict.

---

## Cross-phase notes

- **D-R8 / Phase 2 D-06 (closed):** AES-GCM is **not** on this hot path — the SPSC ring is the
  decoupling boundary, so the worker does zero crypto. There is therefore no crypto cost to attribute
  on the System Trace (the SC#1 regime is transport/produce only), and the Phase-2 D-06 follow-up
  ("does the encrypt step move onto the Foundation-free hot path?") is resolved **No**.
- **Phase 4** lands the real O'Doherty Indy/Loco spike payload into `CortexFrame.channel_data` (this
  phase uses a synthetic zeroed payload of the correct stride). The SC#1 regime is unchanged — Phase 4
  must keep the produce loop allocation-free and cooperative-runtime-free; re-capture if the source
  integration touches the worker thread.
- **Phase 6** consumes the ring from a `CAMetalDisplayLink` callback (RENDER SC#4). The consumer is a
  separate thread; this runbook proves only the **producer** worker's regime.
