---
status: pending
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
source: [09-VALIDATION.md "Manual-Only Verifications", 09-CONTEXT.md D-17, 09-coreml-evidence.md "Latency with real weights (RD-06b)"]
gates: 1
started: 2026-09-02T00:00:00Z
updated: 2026-09-02T00:00:00Z
---

# Phase 9 human UAT: the one device-gated measurement

> **This gate is never auto-approved.**
>
> It is a hardware measurement. An agent cannot take it, and an agent that approved it for itself
> would be inventing one of this project's load-bearing credibility numbers. That is the exact
> failure Phase 9 exists to eliminate: the phase was opened because every decoder figure in the repo
> had been measured on synthetic Poisson spikes rather than on real recorded neural data, and
> replacing one unearned number with a different unearned number is not progress. So the rule holds
> even though `.planning/config.json` sets `workflow.auto_advance: true`, and it holds the same way
> it held for the three Phase-8 gates deferred on 2026-06-23 (`08-HUMAN-UAT.md`) and for the Phase-6
> renderer capture. A gate is either CAPTURED on real hardware with the real numbers written down,
> or DEFERRED with its missing prerequisite named. There is no third state, and neither state is
> reached by an agent deciding on the user's behalf.

## Scope

One gate, RD-06b: the canonical iPad Pro M4 p99 for the real-data `(vx, vy)` decoder.

Everything else in RD-06 is already closed on the dev Mac and committed. This file exists only to
carry the one measurement that cannot be taken here, to state what it would add, and to record what
the user decided about it.

## What is already measured and committed

Transcribed verbatim from the `latency` section of `09-decoder-metrics.json`, written by Plan 09-08
and narrated in [`09-coreml-evidence.md`](09-coreml-evidence.md) under "Latency with real weights
(RD-06b)".

| Field | Value |
|---|---|
| Model | `ndt1_real_vel_4bit.mlpackage` (the 4-bit palettized real-data with-velocity model) |
| p50 | 0.130708 ms (130,708 ns) |
| **p99** | **0.141083 ms** (141,083 ns) |
| min / max | 0.110458 ms / 0.355584 ms |
| n | 10,000 timed passes, after 50 warmup passes |
| Device | Apple M5 Pro (arm64), macOS-26.5-arm64-arm-64bit |
| Toolchain | Xcode 26.3 / Swift 6.2.4 (`swiftlang-6.2.4.1.4`, `clang-1700.6.4.2`) |
| Compute units | `.cpuAndNeuralEngine` (the DEC-07 production set, not `.all`) |
| Placement | **CPU, MEASURED** (not assumed, not inferred) |
| `status` | **`corroborating`** |
| Provenance | real-data checkpoint `ndt1_real_with_velocity.pt` sha256=`9d542cb51d4a` |
| Tool | `CortexDecoderBench`, in-process Swift `ContinuousClock` |

Two other candidate packages were measured on the same machine in the same corroborating tier: the
fp16 package at p50 0.131291 ms and p99 0.141959 ms, and the per-channel 4-bit package at p50
0.130666 ms and p99 0.165042 ms. All three are CPU-placed and all three sit more than ten times
inside the 2 ms decoder budget, so the deployment-artifact choice does not move the latency picture.
That choice has since been settled: `09-coreml-evidence.md` recommends shipping the **fp16** package,
because 4-bit per-tensor palettization collapses the held-out velocity R2 and per-channel
palettization only partly recovers it. The `latency` entry transcribed in the table above is still
the 4-bit package's, which is why that is the one this file transcribes. Point the runbook at
whichever package is actually being shipped on the day the capture is taken.

**This Mac number is sufficient for the phase to complete.** D-17 carries the DEC-08 / DEC-11 device
disposition forward unchanged: M5 Pro corroborating, iPad Pro M4 canonical, the canonical capture
optional and never auto-approved. RD-06 stands on the corroborating measurement plus the
239/239-eligible ANE scan. The gate below is a refinement that would strengthen the claim on the
target device. It is not a blocker on RD-06 and nothing downstream waits on it.

**What the Mac number is not.** 0.141083 ms is a CPU latency measured on an Apple M5 Pro. It is
labeled with the device that produced it in every place it appears, and it may not be quoted as an
iPad-M4 number or as an ANE number. A capture under this gate would sit beside it, never on top of
it.

## The distinction this gate exists to test: eligibility is not placement

This is the whole reason the gate is here, so it is worth stating precisely rather than in passing.

**Eligibility** means `neuralEngine` appears in a schedulable op's `supported_compute_devices`. It
is a compiler property. It is device-independent, it is assertable on the dev Mac, and it is the
hard gate. Plan 09-08 re-established it on the real-data graph: **239 of 239 ops ANE-eligible, 0
CPU-only**, up from the 226 Phase 5 recorded, because a trained positional encoding stops folding
away and twelve `LayerNormANE` modules survive into the traced graph. That is closed and committed.

**Placement** means `preferred_compute_device == neuralEngine` at runtime. It is a scheduler
decision and depends on the chip, the OS scheduler and the model's scale. At roughly 1.29M
parameters this model sits below the Mac runtime ANE-placement threshold, so Core ML CPU-places it
and the Mac `preferred` tally reads `{CPU: 239}`. That is the scale trap that Phase 5 hit and that
SC#1 / DEC-08 was reframed around: the honest claim is placement measured and reported, not
placement assumed from eligibility. The Phase-5 iPad Air M2 capture reproduced the same CPU
placement on real iPad silicon (226/226 `preferred == cpu`), which is evidence that the trap is real
and not a Mac artifact.

So an eligible model is not a placed model, and no amount of Mac work can close the placement
question. Only running on the target device answers it. That is what this gate would do, and it is
also why a capture that comes back CPU-placed is a perfectly good result: it would be recorded as
measured, exactly as Phase 5 recorded it, and it would not be retried until it read
`NeuralEngine`.

## Prerequisites

| # | Prerequisite | Status today |
|---|---|---|
| 1 | A provisioned **iPad Pro M4** running iPadOS 26, paired and trusted in Xcode | **NOT AVAILABLE.** The same missing hardware deferred Phase-8 Gate 2 (the canonical glass-to-glass capture) on 2026-06-23 and left the Phase-6 renderer capture open. Phase 5 captured on an iPad Air M2 instead, which is corroborating, not the M4 target. |
| 2 | The real-data `(vx, vy)` `.mlpackage` on the machine driving the device: `Decoder/checkpoints/ndt1_real_vel_4bit.mlpackage` | **REGENERATE, do not fetch.** Every `.mlpackage`, `.mlmodelc` and `.pt` in `Decoder/checkpoints/` is gitignored, so it is not in the repo and cannot be pulled. It is rebuilt by step 1 of the runbook, which itself needs the two real-data checkpoints present (`ndt1_real_pooled.pt`, `ndt1_real_with_velocity.pt`) and exits nonzero rather than quietly measuring random weights. |
| 3 | Xcode 26.3 with the device paired (Window > Devices and Simulators) | Xcode 26.3 / Swift 6.2.4 is the toolchain that produced the committed Mac number, so the Swift leg is ready. No device is paired. |
| 4 | A signing identity that can provision the iPad | **CONSTRAINED.** The only local identity is the free Personal team `57YW6M29S7`, and a free team signs **GUI-only**: a command-line `xcodebuild` cannot provision it. Any on-device run therefore has to be launched from the Xcode GUI. There is no command line that works around this, so none is written below. |

## Runbook

Copy-pasteable, and split into the leg that runs here and the leg that needs the device.

### Step 1: rebuild the model artifact (dev Mac)

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/rederive_coreml.py     # regenerates the .mlpackage
```

`--extra dev` is mandatory: pytest and ruff live in the dev extra, and a bare `uv run` resolves a
different interpreter and fails with a misleading numpy error. `rederive_coreml.py` writes
`ndt1_real_vel_fp16.mlpackage` and `ndt1_real_vel_4bit.mlpackage` into `Decoder/checkpoints/`, and it
also rewrites `09-decoder-metrics.json` in place with the freshly measured values, which is the
intended behavior for a re-derivation. Add `--smoke` for a wiring check that scores only a few
held-out rows and writes to a scratch metrics file instead of the published one. Never publish a
`--smoke` number.

### Step 2: the corroborating leg, for a same-day A/B (dev Mac)

```bash
swift build --package-path Packages/CortexDecoder
CORTEX_DECODER_MODEL_URL="$PWD/Decoder/checkpoints/ndt1_real_vel_4bit.mlpackage" \
  swift run --package-path Packages/CortexDecoder CortexDecoderBench
cat Packages/CortexDecoder/.bench/latency_histogram.json
```

This reproduces the committed Mac number. It is optional and it is not the gate; it is here so the
device figure can be read against a Mac figure taken from the same rebuilt artifact on the same day.
`CORTEX_DECODER_MODEL_URL` accepts either a `.mlpackage` or a compiled `.mlmodelc`, so the same
command measures any candidate package by pointing the variable at it: swap in
`ndt1_real_vel_fp16.mlpackage` to measure the package the phase recommends shipping. With no model URL set the
bench prints a usage message and exits 0, which is why a clean clone never fails.

### Step 3: the canonical leg (iPad Pro M4, Xcode GUI)

`swift run` builds for the host, so it cannot target an iPad. The device leg runs the same
`CortexDecoderBench` code driven from an Xcode-built host, exactly as the Phase-5 runbook specified.

1. Pair and trust the iPad Pro M4 in Xcode 26.3 (Window > Devices and Simulators).
2. Copy the rebuilt package into the host app's bundle or its Documents directory, and point the
   bench at that on-device path. Use the package that is actually shipping, which under the current
   recommendation is `ndt1_real_vel_fp16.mlpackage`; `ndt1_real_vel_4bit.mlpackage` is the one the
   committed corroborating entry was measured on, so capturing both makes the comparison direct. The `CORTEX_DECODER_MODEL_URL`
   environment variable can be set in the scheme's Run > Arguments > Environment Variables pane; the
   bench also accepts the path as `argv[1]`.
3. Select the iPad as the run destination and build and run **from the Xcode GUI**. The free
   Personal team signs GUI-only, so this step cannot be scripted (prerequisite 4).
4. Let it complete 50 warmup passes plus 10,000 timed passes. It loads the model with
   `.cpuAndNeuralEngine`, times each `decode` call with `ContinuousClock`, and summarizes the
   per-op `MLComputePlan` `preferred` device into a single annotation.
5. Read the printed block from the Xcode console. The bench writes
   `latency_histogram.json` to a path derived from its own source location, which does not exist
   inside the iOS sandbox, so on device expect the "failed to write histogram artifacts" warning and
   take the numbers from the console. The write failure is non-fatal by design and the numbers still
   print.
6. For the placement evidence, capture an Instruments trace: Xcode > Open Developer Tool >
   Instruments > Core ML template, target the running process, record while the timed loop runs,
   and read the compute-unit lane per operation. Save the `.trace` into this phase directory.

### Fields to transcribe back

From the console line `p50=... ns p99=... ns min=... ns max=... ns` and the following `device=...`
line, and from `latency_histogram.json` if it can be retrieved from the device:

- `p50_ns`
- `p99_ns`
- `min_ns` and `max_ns`
- `count` (the pass count, expected 10,000)
- `deviceAnnotation`, which reads `NeuralEngine`, `CPU`, `GPU`, or `mixed (CPU:n,NeuralEngine:m)`
- the `MLComputePlan` preferred-device tally behind that annotation, as ops-per-device, plus the
  Instruments Core ML per-op compute-unit lane if the trace was captured
- the exact device and OS string (for example, iPad Pro M4 / iPadOS 26 with the build number)

Do not transcribe a serial number, a UDID, or an Apple account identifier. The gate needs the device
model, the pass count and the timing percentiles, and nothing else.

## What a capture would change

It would **add** a canonical entry, and only add one.

- `09-coreml-evidence.md` gains a canonical row next to the corroborating Mac row in the "Latency
  with real weights (RD-06b)" table, labeled with the iPad Pro M4 and its OS.
- The `latency` section of `09-decoder-metrics.json` gains a second, clearly labeled entry, for
  example `latency.canonical_capture: {"p50_ms": ..., "p99_ms": ..., "n": ..., "device": "iPad Pro
  M4 (iPadOS 26)", "placement": "<as measured>"}`.
- The existing corroborating Mac entry stays byte-identical. It is not deleted, not moved, and not
  relabeled. `latency.status` stays `corroborating` for the Mac measurement, because that is what it
  is.
- If the device capture reports CPU placement, that is written down as CPU placement. The number is
  not re-run until it reads `NeuralEngine`, and the budget check is reported against whatever
  placement actually occurred. A low or unremarkable number is published as-is (D-25).

## Disposition

| Gate | Requirement | Status | Date | Prerequisite |
|---|---|---|---|---|
| RD-06b canonical iPad Pro M4 p99, real-data `(vx, vy)` decoder | RD-06 (D-17) | **PRESENTED, awaiting user decision** | 2026-09-02 | A provisioned iPad Pro M4 on iPadOS 26, paired with Xcode 26.3, signed through the GUI on the free Personal team |

Captured values, to be filled in only from a real device run:

| Field | Value |
|---|---|
| p50 | `not measured` |
| p99 | `not measured` |
| n | `not measured` |
| Device annotation | `not measured` |
| `MLComputePlan` preferred tally | `not measured` |
| Device and OS | `not measured` |

`not measured` is the literal placeholder. It is used deliberately so that nothing in this file can
later be mistaken for a measurement.

**why_human:** the capture requires real iPad Pro M4 hardware, GUI provisioning under a free
Personal team, and a live Instruments session. None of that runs on a CI runner or on the dev Mac,
and no software substitute exists for it, because placement is precisely the property that changes
with the chip. This follows the eligibility-closed-on-Mac, placement-gated-on-device split already
applied in Phase 3 SC#1, Phase 5 SC#1 / DEC-08, Phase 6 SC#2 / SC#4, and Phase 8 Gate 2. The
always-available proxy is the committed corroborating Mac measurement plus the 239/239 ANE
eligibility scan, and that proxy is never substituted for the canonical claim.

## Honesty clause

If this gate is deferred, no iPad-M4 number is written anywhere. Not in this file, not in
`09-coreml-evidence.md`, not in `09-decoder-metrics.json`, not in `PROJECT.md`, not in a summary. A
deferred gate is recorded as deferred, with the date and the missing prerequisite, and the phase is
not marked complete on the strength of a measurement that was never taken. The corroborating Mac
number keeps its device label and its `corroborating` status in every place it appears.

If this gate is captured, the numbers written down are the numbers the device printed, including an
unflattering one.

## Summary

total: 1
verified: 0
deferred: 0
presented: 1
auto_approved: 0

The single RD-06b gate is **PRESENTED** and unresolved as of 2026-09-02. It was not auto-approved
despite `workflow.auto_advance: true`, and no iPad-M4 value exists in this repository. RD-06 rests
on the committed corroborating M5 Pro measurement (p99 0.141083 ms, MEASURED CPU placement) and the
239/239 ANE eligibility scan, which is what D-17 permits. The gate flips to CAPTURED or DEFERRED
when the user decides.
