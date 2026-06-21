# Phase 5 DEC-11 Evidence — in-process Swift decoder latency (Mac corroborating; iPad-M4 canonical)

**Date:** 2026-06-21
**Result:** ✅ **Mac corroborating measurement recorded** + ⏳ **canonical `<2ms` p99 claim handed to
the iPad-M4 run (Plan 05 HUMAN-UAT)**. An in-process Swift bench (`CortexDecoderBench`) ran warmup +
**10,000** `MLModel.prediction` passes through the Plan-03 zero-copy decoder and recorded a p50/p99
latency histogram annotated with the device the ops actually ran on. On this **M5 Mac the ops
CPU-placed** (`device = CPU` — the 1.29M-param scale trap), so the number below is **CORROBORATING,
not canonical**. The canonical sub-threshold (`< 2 ms`) p99-on-ANE claim is the iPad-M4 run of this
**same executable** in Plan 05's HUMAN-UAT runbook.

> **DEC-11:** "Decoder inference latency measured in-process in Swift (warmup + 10,000
> `MLModel.prediction` passes, `ContinuousClock` per-call nanoseconds), reported as a p50/p99
> histogram, with the canonical `< 2 ms` p99 claim on the iPad-M4 Neural Engine." Per 05-RESEARCH
> Decision 5, latency MUST be measured in Swift in-process — Python `predict()` wall-time is
> IPC/marshalling-dominated and misleads on a tiny (~1.3M-param) model.

This is the **MAC-CORROBORATING** half of DEC-11. The number is annotated with the per-op preferred
compute device (from `MLComputePlan`), because on a Mac a 1.29M-param model can CPU-place (the scale
trap, 05-RESEARCH Risk #1) — in which case the number reflects **CPU** latency, which is exactly why
the Mac value is corroborating and the canonical `< 2 ms`-on-ANE claim belongs to the iPad-M4 device
artifact (DEC-08/SC#4, Plan 05). **The Mac bench never gates on `< 2 ms`** — it prints the number and
always succeeds. This mirrors the Phase-2 SC#1 / Phase-3 SC#1 "measure on Mac, gate the canonical
claim on the target device" precedent (D-18).

---

## The venue split (load-bearing — the single biggest credibility guard)

| Claim | Tool / API | Device/scale dependent? | Where it is proven |
|-------|-----------|-------------------------|--------------------|
| **CORROBORATING** — in-process p50/p99 over 10k passes, **device-annotated** | `CortexDecoderBench` (Swift, `ContinuousClock`) + `MLComputePlan` placement | **Yes** (Mac may CPU-place at this scale) | **dev Mac (this doc)** |
| **CANONICAL** — `< 2 ms` p99 with `preferred == neuralEngine` (100% ANE residency) | the **same** `CortexDecoderBench`, run on the connected device + Instruments → Core ML | **Yes** (mobile scheduler is ANE-eager) | **iPad-M4 HUMAN-UAT (DEC-08/SC#4, Plan 05)** |

The Mac measurement here CPU-placed (`device = CPU`), corroborating Plan 05-02's independent
`MLComputePlan` eligibility scan, whose Mac **preferred** tally was likewise `{CPU: 226}` — the same
scale-trap signature from a different tool (Python op-scan vs Swift in-process timer).

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple **M5 Pro** (`arm64`) — ≥ the M4 spec floor; newer ANE than the iPad target |
| **OS** | macOS 26 Tahoe (`arm64-apple-macosx26.0`) |
| **Toolchain** | **Xcode 26.3** / **Swift 6.2.4** (`swiftlang-6.2.4`, `clang-1700.6.4.2`) — full Xcode, not CommandLineTools |
| **coremltools** (model build) | **9.0** (locked); torch 2.12.1 (Phase-4 disposition) |
| **Model** | `NDT1ANEWithVelocity(seq_len=32)` 4-bit k-means palettized `.mlpackage` — the shipping artifact (1,292,544-param NDT1ANE encoder + 1×1 `Conv2d(96→2)` velocity head; input `spikes` fp16 `(1,96,1,32)`; output fp16 `(1,2,1,1)`) |
| **Compute units** | `.cpuAndNeuralEngine` (the DEC-07 production config, NOT `.all`) |
| **Sample size** | **n = 10,000** timed passes, **50** warmup passes |
| **Timing** | `ContinuousClock` per-call, in-process Swift (NOT Python `predict()`) |
| **Input** | the Plan-03 zero-copy `SpikeInputBuffer` (one IOSurface shared by a `OneComponent16Half` CVPixelBuffer + a `storageModeShared` MTLBuffer); filled once, reused across passes so the loop times inference, not buffer setup |

---

## Methodology

The proof is the executable `Packages/CortexDecoder/Sources/CortexDecoderBench/main.swift` driving the
Plan-03 in-process inference path (05-RESEARCH Decision 5):

1. **Resolve the model** from `CORTEX_DECODER_MODEL_URL` (or `argv[1]`); compile the `.mlpackage` →
   `.mlmodelc` once (Core ML cannot load a raw `.mlpackage` at runtime — Risk #4); if absent, the
   bench prints a usage message and exits 0 (clean-clone / CI safe).
2. **Build the zero-copy input once** (`SpikeInputBuffer(device:seqLen:32)`), fill it with a
   representative fp16 spike pattern through the shared MTLBuffer, and reuse it across all passes.
3. **Warm up** 50 passes (`decoder.decode(input)`) — the first prediction triggers Core ML
   compile/load (Decision 5), excluded from timing.
4. **Time** 10,000 in-process `decode` passes, recording per-call nanoseconds with `ContinuousClock`,
   into a `[UInt64]`.
5. **Annotate the device** — load `MLComputePlan` for the compiled model and summarize the per-op
   **preferred** compute device (`MLComputeDevice.{neuralEngine,cpu,gpu}`) into a single string
   (`"NeuralEngine"` / `"CPU"` / `"mixed (...)"`). This is the corroborating-vs-canonical pivot.
6. **Summarize + emit** — build a pure, unit-tested `LatencyHistogram` (nearest-rank p50/p99), print
   `p50/p99/device`, and write `latency_histogram.json` (+ a bins CSV and a headless CoreGraphics
   PNG) under the gitignored `Packages/CortexDecoder/.bench/`.

The bench **never** asserts `< 2 ms`; it records and reports. Only the **pure** `LatencyHistogram`
percentile math is unit-tested (`swift test`); timing stays out of the test suite so CI carries no
flaky latency gate (D-18).

---

## Results — Mac corroborating number (`latency_histogram.json`, gitignored)

| Quantity | Value (ns) | ≈ (µs) |
|----------|-----------:|-------:|
| Samples (`count`) | 10,000 | — |
| **p50** | **123,250** | **≈ 123 µs** |
| **p99** | **139,333** | **≈ 139 µs** |
| min | 105,000 | ≈ 105 µs |
| max | 181,959 | ≈ 182 µs |
| **`deviceAnnotation`** | — | **`CPU`** |

```json
{
  "count" : 10000,
  "deviceAnnotation" : "CPU",
  "max_ns" : 181959,
  "min_ns" : 105000,
  "p50_ns" : 123250,
  "p99_ns" : 139333
}
```

**Reading the number honestly (the scale trap, Risk #1).** `deviceAnnotation = CPU` means the Core ML
scheduler preferred the **CPU** for the ops on this M5 Mac — so **≈ 123 µs p50 / ≈ 139 µs p99 is a CPU
latency**, not an ANE latency. At ~1.29M params Cortex NDT1 is below the Mac runtime ANE-placement
scale threshold (prior art: `meridian-mcp/ane_encoder` — a small transformer can be 100% ANE-eligible
yet 0% ANE-placed on Mac until compute-per-op amortises ANE dispatch, ~5–10M params). This is the
**same** signature Plan 05-02's eligibility scan reported independently (`preferred` tally
`{CPU: 226}`). The number is therefore **CORROBORATING evidence that the in-process Swift path is
fast and the bench works end-to-end** — NOT the canonical `< 2 ms`-on-ANE claim. (For context, even
this CPU p99 of ≈ 139 µs is comfortably inside the 2 ms budget; the canonical iPad-M4 ANE number is
expected to be substantially lower, but it is **measured** on device, not assumed here.)

---

## The iPad-M4 canonical hand-off (DEC-08 / SC#4 — Plan 05 HUMAN-UAT)

The canonical `< 2 ms` p99-on-ANE claim is produced by running **this same `CortexDecoderBench`
executable** on the connected **iPad Pro M4** (the mobile Core ML scheduler is more ANE-eager, so
`preferred == neuralEngine` placement is *expected* there — but it is *measured*, not assumed). Plan
05's HUMAN-UAT runbook:

1. builds + deploys the bench to the iPad (the same `swift run` target, on-device),
2. runs warmup + 10,000 passes against the deployed 4-bit `.mlpackage`,
3. commits the on-device `latency_histogram.{json,png}` whose `deviceAnnotation` is expected to read
   `NeuralEngine`, with **p99 < 2 ms** — the SC#4 canonical artifact,
4. corroborates it with an Instruments → Core ML residency trace (DEC-08 / SC#1).

If the iPad also CPU-places at this scale, the defensible artifact is the same honest narrative as the
eligibility doc: "fully ANE-**eligible**, with the scheduler's device choice reported honestly, and
the in-process latency recorded with its device annotation." The Mac number in this doc is the
device-independent corroboration that makes the iPad measurement meaningful.

---

## Reproduce

```bash
# 1. Build a (vx,vy) 4-bit .mlpackage at seq_len=32 (the bench's window). Decoder is a uv subsystem:
#    `--extra dev` is mandatory (pytest/numpy/torch/coremltools live in the dev extra; a bare
#    `uv run` resolves a different Python and dies with a misleading ModuleNotFoundError: numpy).
uv sync --project Decoder --extra dev
uv run --project Decoder pytest -q -k compute_plan   # the slow DEC-06 gate also builds the .mlpackage

# 2. Build + run the in-process Swift latency bench against the built model:
swift build --package-path Packages/CortexDecoder
CORTEX_DECODER_MODEL_URL=/path/to/ndt1_velocity_4bit_s32.mlpackage \
  swift run --package-path Packages/CortexDecoder CortexDecoderBench
```

This runs 50 warmup + 10,000 timed passes, prints `p50=… p99=… device=…`, and (re)writes
`Packages/CortexDecoder/.bench/latency_histogram.json` (+ bins CSV + PNG, all gitignored). Only the
NUMBER + device annotation + this reproduce command are committed (Phase-4 gitignored-artifact
discipline). With no `CORTEX_DECODER_MODEL_URL` the bench prints a usage message and exits 0.

> The pure `LatencyHistogram` percentile math is unit-tested with no model:
> `swift test --package-path Packages/CortexDecoder` (the `LatencyHistogramTests` suite). The timing
> loop is deliberately NOT a `swift test` assertion — CI must carry no flaky latency gate (D-18).

---
*Phase: 05-ndt1-coreml-deployment-with-ane-residency-verified*
*Plan: 05-04 — DEC-11 in-process latency bench (Mac corroborating; iPad-M4 canonical)*
*Completed: 2026-06-21*
