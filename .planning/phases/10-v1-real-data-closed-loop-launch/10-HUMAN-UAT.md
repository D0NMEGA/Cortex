---
status: partial
phase: 10-v1-real-data-closed-loop-launch
source: [10-VALIDATION.md "Manual-Only Verifications", 10-CONTEXT.md D-15 and D-17, 10-replay-evidence.md, 08-HUMAN-UAT.md, 09-HUMAN-UAT.md]
gates: 6
deferred: 6
corroborating_captures: 0
started: 2026-09-06T00:00:00Z
updated: 2026-09-06T00:00:00Z
---

# Phase 10 human UAT: the six device gates carried into v1

> **These six gates are never auto-approved.**
>
> Every one of them is a hardware or account measurement. An agent cannot take it, and an agent that
> approved one for itself would be inventing one of this project's load-bearing credibility numbers.
> That is the exact failure the v1 milestone exists to eliminate. The milestone was re-pointed on
> 2026-08-28 because every decoder figure in the repository had been produced on a synthetic Poisson
> fallback, and replacing one unearned number with a different unearned number is not progress.
>
> The rule holds even though `.planning/config.json` sets `workflow.auto_advance: true`. It held the
> same way for the three Phase-8 gates deferred on 2026-06-23 (`08-HUMAN-UAT.md`) and for the Phase-9
> gate deferred on 2026-09-02 (`09-HUMAN-UAT.md`). A gate is either CAPTURED on real hardware with
> the real numbers written down, or DEFERRED with its missing prerequisite named. There is no third
> state, and neither state is reached by an agent deciding on the user's behalf.

## Scope

Six gates. Four are inherited and still open; two are new to Phase 10.

| # | Gate | Origin | Requirement |
|---|---|---|---|
| 1 | Canonical iPad Pro M4 software-timed glass-to-glass latency | Phase 8 Gate 2 | PERF-04, D-08 |
| 2 | Live TestFlight submission | Phase 8 Gate 1 | DIST-01 / DIST-02 / DIST-03 |
| 3 | On-device HID registration as a Switch Control provider | Phase 8 Gate 3 | SYS-01 / SYS-02, D-06 |
| 4 | Canonical iPad Pro M4 p99 for the real-data decoder | Phase 9 RD-06b | RD-06, D-17 |
| 5 | Canonical iPad Pro M4 Seam A glass-to-glass p99 on the real-data path | New in Phase 10 | RD-08 |
| 6 | Canonical iPad Pro M4 120 Hz real-data webgrid demonstration | New in Phase 10 | RD-08 |

D-15 says v1 is declarable with these gates still deferred. They are carried forward as disclosed
boundaries, not silently closed. Nothing downstream in this phase waits on any of them.

## What is already measured and committed

Transcribed verbatim from `10-replay.json`, `10-refit-real.json` and `09-decoder-metrics.json`.
Every row below is an **Apple M5 Pro** number at **corroborating** status. None of them is an
iPad-Pro-M4 number and none may be quoted as one.

### Seam A, the real-data closed loop in the Phase-8 measurement geometry

| Field | Value |
|---|---|
| Boundary | intent emission (`mach_absolute_time`) to a MODELLED 120 Hz present boundary, in-process, no IPC leg |
| p50 (debug) | 4,753,046 ns (4.753 ms), median of 5 runs |
| **p99 (debug)** | **8,831,017 ns (8.831 ms)**, median of 5 runs, run-to-run spread 0.249 percent |
| p50 (release) | 4,302,424 ns (4.302 ms), median of 5 runs |
| p99 (release) | 8,386,219 ns (8.386 ms), median of 5 runs, run-to-run spread 0.388 percent |
| n | 2,286 windows per run |
| Ticks model-backed | 2,294 / 2,294 |
| Device | Apple M5 Pro, macOS 26.5 (25F71) |
| Toolchain | Xcode 26.3 (17C529) / Swift 6.2.4 |
| Methodology | software-timed, excludes the compositor's scanout |

### Seam B, the wider chain over the real ShmRing, Doorbell, AES-GCM and FlatBuffers codec

| Field | Value |
|---|---|
| p50 | 136,167 ns, median of 5 runs, stable to 0.55 percent |
| p99 and max | recorded but labeled unstable, p99 swings 58 percent run to run |
| Windows / decodes / dropped | 73,128 / 73,128 / 0 |
| Doorbell wakes | 73,159 / 73,159 |
| Process boundary | `in_process`. The `posix_spawn` path is broken independently of this phase |
| Device | Apple M5 Pro |

### The webgrid outcome

| Arm | Rotation target | Hits of 1,025 |
|---|---|---|
| `raw` | none | 0 |
| `kalman_only` | none | 0 |
| `refit` | `true_track` | 70, target-determined by construction |
| `refit_reversed_target` | `reversed_track` | 2, target-determined by construction |

Recorded-cursor replay reference: 147 of 1,025 at acquisition radius 2.8613660406415042 mm and
dwell 0.30 s, committed at `864259b` before any decoded number existed.

### The real-data decoder, from Phase 9

| Field | Value |
|---|---|
| p99 | 0.141083 ms, Apple M5 Pro, MEASURED CPU placement |
| Corroborating device capture | iPad Air 11-inch (M2), iPadOS 18.7.8: p50 0.2240 ms, p99 0.5790 ms, 239/239 ANE eligible, preferred tally `{cpu: 239}` |

The iPad Air M2 rows are the only device-captured numbers in the repository. M2 is not M4, and an M2
result is never promoted to an M4 one.

## Gate 1: canonical iPad Pro M4 software-timed glass-to-glass latency (PERF-04, D-08)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| p50 | `not measured` |
| p99 | `not measured` |
| n | `not measured` |
| Device and OS | `not measured` |

**What it would add.** The canonical device number for the project's defining latency claim. Today
the claim rests on an M5 Pro measurement labeled corroborating.

**Missing prerequisite.** A provisioned iPad Pro M4 running iPadOS 26, paired and trusted in
Xcode 26.3. Not available. The only local signing identity is the free Personal team `57YW6M29S7`,
which signs GUI-only, so any on-device run must be launched from the Xcode GUI.

**Corroborating stand-in that holds today.** The Seam A debug p99 of 8,831,017 ns on an Apple M5 Pro,
device-labeled everywhere it appears.

**Runbook.** `08-HUMAN-UAT.md` Gate 2, unchanged.

## Gate 2: live TestFlight submission (DIST-01 / DIST-02 / DIST-03)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| Submission date | `not measured` |
| Build number accepted | `not measured` |
| App Store Connect processing result | `not measured` |

**What it would add.** Proof that the distribution pipeline works end to end against Apple's real
service, rather than only as CI-green code.

**Missing prerequisite.** An Apple Developer Program membership. Not enrolled. The fastlane lanes are
Phase-1 placeholders by D-09 and D-10, and the Matchfile deliberately points at a local `file://`
certificate store that never traverses the network.

**Corroborating stand-in that holds today.** The full distribution pipeline as real, CI-green code,
plus the committed privacy manifests and the notarization configuration.

**Runbook.** `08-HUMAN-UAT.md` Gate 1, unchanged.

## Gate 3: on-device HID registration as a Switch Control provider (SYS-01 / SYS-02, D-06)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| Registration result | `not measured` |
| Switch Control provider visible | `not measured` |
| Device and OS | `not measured` |

**What it would add.** Confirmation that the BCI HID integration actually registers with the system
as an assistive input provider, which is the difference between a tech demo and a deployable
assistive input device.

**Missing prerequisite.** The `com.apple.developer.hid.virtual.device` entitlement is Apple-managed
and request-gated. It is declared but inert in this repository, so the entitlement cannot be
exercised without Apple granting it.

**Corroborating stand-in that holds today.** The structural CI gate asserting the entitlement is
declared, plus the BCI HID code paths under test.

**Runbook.** `08-HUMAN-UAT.md` Gate 3, unchanged.

## Gate 4: canonical iPad Pro M4 p99 for the real-data decoder (RD-06b, D-17)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| p50 | `not measured` |
| p99 | `not measured` |
| n | `not measured` |
| Device annotation | `not measured` |
| `MLComputePlan` preferred tally | `not measured` |
| Device and OS | `not measured` |

**What it would add.** The canonical placement answer on the target chip. Eligibility is closed on
the Mac at 239 of 239 ops; placement is a scheduler decision that only the target device can settle.

**Missing prerequisite.** A provisioned iPad Pro M4 on iPadOS 26. Not available.

**Corroborating stand-in that holds today.** The M5 Pro p99 of 0.141083 ms with MEASURED CPU
placement, plus the iPad Air M2 capture committed as `09-perf-report-ipad-m2.json`.

**Runbook.** `09-HUMAN-UAT.md` step 3, unchanged.

## Gate 5: canonical iPad Pro M4 Seam A glass-to-glass p99 on the real-data path (RD-08)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| p50 | `not measured` |
| p99 | `not measured` |
| n | `not measured` |
| Runs | `not measured` |
| Build configuration | `not measured` |
| Device and OS | `not measured` |

**What it would add.** The canonical device number for RD-08's re-derived latency, on the real-data
path rather than the synthetic one. This is new in Phase 10 because RD-08 re-derives the number on
real spikes, so the Phase-8 canonical gate does not cover it.

**Missing prerequisite.** A provisioned iPad Pro M4 on iPadOS 26, paired with Xcode 26.3 and signed
through the GUI on the free Personal team.

**Corroborating stand-in that holds today.** The Seam A distribution above: debug p99 median
8,831,017 ns and release p99 median 8,386,219 ns over 5 runs each on an Apple M5 Pro, with every
per-run value carried in `10-replay.json` so any other summary can be recomputed.

**Runbook.** Rebuild the export with `Decoder/scripts/export_replay.py --session indy_20160630_01`,
copy it into the host app's container, then build and run `CortexDemoBench --real` from the Xcode
GUI against the paired iPad. Record five runs, not one: the percentiles move run to run.

## Gate 6: canonical iPad Pro M4 120 Hz real-data webgrid demonstration (RD-08)

**Value fields: `not measured`.**

| Field | Value |
|---|---|
| Measured display cadence | `not measured` |
| Frames presented / dropped | `not measured` |
| Hits by arm | `not measured` |
| Device and OS | `not measured` |

**What it would add.** A measured display cadence rather than a modelled one. `10-replay.json`
records `cadence_provenance` as a MODELLED 120 Hz present boundary computed from a
`frame_period_ns` of 8,333,333, explicitly **not** a `CAMetalDisplayLink` reading. Only a device run
on a ProMotion panel turns that into a measurement.

**Missing prerequisite.** A provisioned iPad Pro M4 on iPadOS 26 with a ProMotion display.

**Corroborating stand-in that holds today.** The committed headless artifacts `10-replay.json` and
`10-refit-real.json`, which are the evidentiary basis for RD-08's webgrid result. A GUI recording
illustrates them; it is not their evidence.

**Runbook.** Build the CortexiOS scheme from the Xcode GUI against the paired iPad, run the
real-data replay, and capture both a screen recording and an Instruments Display trace so the
presented cadence is read from the tool rather than assumed.

## Disposition

Recorded from the user's reply on 2026-09-06. The gate was presented, not decided by an agent.
The user's verbatim answer was "Defer all six".

| # | Gate | Requirement | Status | Date | Prerequisite |
|---|---|---|---|---|---|
| 1 | Canonical iPad Pro M4 glass-to-glass latency | PERF-04, D-08 | **DEFERRED** | 2026-09-06 | An iPad Pro M4 is not provisioned. |
| 2 | Live TestFlight submission | DIST-01 / 02 / 03 | **DEFERRED** | 2026-09-06 | An Apple Developer Program membership is not enrolled. |
| 3 | On-device HID registration | SYS-01 / SYS-02, D-06 | **DEFERRED** | 2026-09-06 | `com.apple.developer.hid.virtual.device` is Apple-managed and request-gated, and has not been granted. |
| 4 | Canonical iPad Pro M4 real-data decoder p99 | RD-06, D-17 | **DEFERRED** | 2026-09-06 | An iPad Pro M4 is not provisioned. |
| 5 | Canonical iPad Pro M4 Seam A p99, real-data path | RD-08 | **DEFERRED** | 2026-09-06 | An iPad Pro M4 is not provisioned. |
| 6 | Canonical iPad Pro M4 120 Hz webgrid demonstration | RD-08 | **DEFERRED** | 2026-09-06 | An iPad Pro M4 is not provisioned. |

`not measured` is the literal placeholder used throughout this file. It is used deliberately so that
nothing here can later be mistaken for a measurement.

**why_human:** these captures require real iPad Pro M4 hardware, GUI provisioning under a free
Personal team, an Apple Developer Program membership, and an Apple-granted entitlement. None of that
runs on a CI runner or on the dev Mac, and no software substitute exists, because placement and
system registration are precisely the properties that change with the device and the account. This
follows the eligibility-closed-on-Mac, placement-gated-on-device split already applied in Phase 3
SC#1, Phase 5 SC#1 and DEC-08, Phase 6 SC#2 and SC#4, Phase 8 Gate 2 and Phase 9 RD-06b.

## Honesty clause

If a gate is deferred, no iPad-M4 number is written anywhere. Not in this file, not in
`10-replay-evidence.md`, not in `10-replay.json`, not in the README, not in a summary. A deferred
gate is recorded as deferred, with the date and the missing prerequisite, and the phase is not
marked complete on the strength of a measurement that was never taken. Every corroborating M5 Pro
number keeps its device label and its `corroborating` status in every place it appears.

If a gate is captured, the numbers written down are the numbers the device printed, including an
unflattering one.

## Summary

total: 6
verified: 0
deferred: 6
corroborating_captures: 0
auto_approved: 0

All six gates are **DEFERRED** as of 2026-09-06. None was auto-approved despite
`workflow.auto_advance: true`, and **no iPad-Pro-M4 value exists in this repository.**

Four gates wait on the same missing prerequisite, a provisioned iPad Pro M4. One waits on an Apple
Developer Program membership, and one on an entitlement only Apple can grant. Each flips to CAPTURED
the day its prerequisite is met, and each is recorded here with the corroborating M5 Pro or iPad Air
M2 number that stands in its place at the corroborating tier, never as a substitute for the
canonical claim.

D-15 permits v1 to be declared with these six open. They are carried into v1 as disclosed
boundaries.
