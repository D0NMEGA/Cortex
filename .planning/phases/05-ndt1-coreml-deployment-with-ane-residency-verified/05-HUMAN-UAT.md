---
status: partial
phase: 05-ndt1-coreml-deployment-with-ane-residency-verified
source: [05-VALIDATION.md]
started: 2026-06-21T22:10:26Z
updated: 2026-06-21T22:10:26Z
---

## Current Test

[awaiting human testing on iPad Pro M4 hardware]

## Tests

### 1. ANE runtime placement — SC#1 / DEC-08 (100% `preferred == neuralEngine`)
expected: On a **connected iPad Pro M4**, capture the runtime *placement* of the compiled 4-bit palettized `(vx,vy)` model and confirm **100% `preferred == neuralEngine`** (zero CPU/GPU fallback). The reviewer needs only **ONE** of the three capture options below; (a) is the canonical reviewer artifact, (b)/(c) are equally acceptable corroboration.

  **Build + deploy the artifact (prerequisite for all three options):**
  1. Materialize the pinned Decoder venv and build the **4-bit palettized `.mlpackage`** (gitignored): `uv sync --project Decoder --extra dev && uv run --project Decoder pytest -q -k compute_plan` — the slow DEC-06 gate rebuilds the `(vx,vy)` `.mlpackage` and palettizes it to 4-bit k-means under `Decoder/checkpoints/` (Plan 05-02). Note the resulting `.mlpackage` path.
  2. `export CORTEX_DECODER_MODEL_URL=<that .mlpackage path>` (the Plan-03/04 convention; `NeuralDecoder.init` compiles a `.mlpackage` → `.mlmodelc` on load — CoreML cannot load a raw `.mlpackage` at runtime, 05-RESEARCH Risk #4).
  3. In Xcode 26.3, select the **connected iPad Pro M4** as the run destination (Window → Devices and Simulators → confirm it is paired and trusted). Deploy the bench/host that loads the model with `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` (the `NeuralDecoder.productionConfiguration()` from Plan 03 — NOT `.all`).

  **(a) Instruments → Core ML template** (canonical artifact):
  1. Xcode → **Open Developer Tool → Instruments** → choose the **Core ML** template.
  2. Target the running on-device process (the deployed `CortexDecoderBench`/host on the iPad Pro M4); **Record** while it runs a representative batch of `decode` passes.
  3. In the Core ML track, open the per-prediction detail and read the **compute-unit lane for each operation**. Confirm **every op is on the Neural Engine** — **0 CPU, 0 GPU** events on the inference path.
  4. **Save the `.trace`** (`File → Save`) and commit it into this phase dir (e.g. `coreml-residency-ipad.trace`).

  **(b) Xcode `.mlpackage` Performance Report**:
  1. Open the **`.mlpackage` in Xcode** (the 4-bit package from step 1).
  2. In the model editor's **Performance** tab, **+ Add** the **connected iPad Pro M4** as the device and **generate the Performance Report**.
  3. Confirm the report shows the prediction path as **Neural Engine** with **100% ANE** compute-unit mapping (no "Compute Unit: CPU/GPU" rows on the prediction path).
  4. **Screenshot** the Performance Report and commit it into this phase dir (e.g. `performance-report-ipad.png`).

  **(c) on-device `MLComputePlan`**:
  1. Run a tiny on-device build that calls `MLComputePlan.load(contentsOf:configuration:)` with `configuration.computeUnits = .cpuAndNeuralEngine`, walks `program.functions["main"].block.operations`, and reads `plan.deviceUsage(for: op).preferred` for every schedulable op.
  2. Confirm **all** ops report `preferred == .neuralEngine`.
  3. **Dump the per-op preferred device to `runtime_plan_ipad.json`** (the iPad complement of the Plan-02 Mac `runtime_plan.json`) and commit it into this phase dir.

  **Pass condition (verbatim from 05-VALIDATION Manual-Only):** 100% `preferred == neuralEngine`, **zero CPU/GPU**, over the full graph.
  **Artifacts to commit:** the Instruments **`.trace`** (option a) **OR** the Xcode **Performance-Report screenshot** (option b) — AND `runtime_plan_ipad.json` (option c, or alongside a/b). At least the placement capture + `runtime_plan_ipad.json` must land in this phase dir for reviewer verification.

  **Honest fallback (Risk #1 — the scale trap, 05-RESEARCH Decision 2):** the ~1.29M-param NDT1 model is below the Mac ANE runtime-placement scale threshold, so the M5 Mac legitimately CPU-places it (Plan 05-02's `preferred` tally was `{CPU: 226}`; Plan 05-04's Mac bench read `device = CPU`). 100% `preferred == neuralEngine` is *expected* on the more ANE-eager iPad-M4 mobile scheduler — but it is **measured, not assumed**. **If the iPad ALSO CPU-places at this scale, do NOT fabricate a placement.** Record the honest, defensible artifact: the model is **ANE-ELIGIBLE** (the Plan-02 Mac CI verdict — `226/226` ops `neuralEngine ∈ supported`, 0 CPU-only) and the iPad scheduler's *device choice is reported as observed* (the captured `runtime_plan_ipad.json` / trace stands as the evidence of the actual placement). Eligibility is the hard gate (closed, Plan 02); placement is the device-measured artifact captured honestly here.

result: [pending]
why_human: Instruments → Core ML and the Xcode `.mlpackage` Performance Report are **GUI profilers on a live process** and require **real iPad Pro M4 hardware** — they cannot run in CI (no GUI, no Instruments, no paired device on the `macos` runner). The always-on CI proxy for residency is the **Plan-02 ANE op-*eligibility* gate** (`uv run --project Decoder pytest -q -k compute_plan`, green: `226/226` eligible, 0 CPU-only — `05-ane-eligibility-evidence.md`); this `.trace`/Performance-Report capture is the per-milestone hardware-*placement* evidence step following the **D-18** eligibility/placement split already applied in Phases 1–3 (the THREAD-02 / SC#1 precedent, `03-HUMAN-UAT.md`). Eligibility (compiler property, device-independent) is closeable on Mac; placement (`preferred`, scheduler + scale + chip dependent) is intentionally **not** closeable on Mac — by design.

### 2. On-device inference latency — SC#4 / DEC-11 canonical (`< 2 ms` p99 over 10k passes)
expected: On the **same connected iPad Pro M4**, run the **Plan-04 `CortexDecoderBench`** executable on-device to capture the **canonical** in-process p50/p99 latency, and confirm **`p99 < 2 ms`** with **`device == NeuralEngine`**.

  1. Build the artifact and set the model URL exactly as in Test 1 steps 1–2: `uv sync --project Decoder --extra dev && uv run --project Decoder pytest -q -k compute_plan` to (re)build the 4-bit `.mlpackage`, then `export CORTEX_DECODER_MODEL_URL=<that .mlpackage path>`.
  2. Build **`CortexDecoderBench`** for the iPad Pro M4 (the same `swift run --package-path Packages/CortexDecoder CortexDecoderBench` target, run **on-device** — embed it in a thin host app if the run destination requires it). It loads the model with `.cpuAndNeuralEngine`, builds the zero-copy `SpikeInputBuffer` once, runs **50 warmup** passes, then times **10,000** (`10_000`) in-process `decode` passes with `ContinuousClock`.
  3. Read the printed **`p50 / p99 / device`** line. Confirm **`p99 < 2 ms`** (the SC#4 budget) and that the **`deviceAnnotation`** (from the on-device `MLComputePlan` per-op `.preferred`) reads **`NeuralEngine`**.
  4. Commit the on-device **`latency_histogram.{json,png}`** (the bench writes them under `Packages/CortexDecoder/.bench/`, gitignored — copy the canonical pair into this phase dir, annotated *on-device / iPad Pro M4*) for reviewer verification.

  **Pass condition:** `p99 < 2 ms` on iPad M4, with `device == NeuralEngine`.
  **Artifact to commit:** `latency_histogram.{json,png}` (on-device annotation) into this phase dir.

result: [pending]
why_human: The **canonical** `< 2 ms` p99 claim is on **iPad-M4 hardware** running the *same* bench executable; the Mac measurement is **corroborating only** (Plan 04, `05-latency-evidence.md`: `device = CPU`, p50 ≈ 123 µs / p99 ≈ 139 µs — a CPU latency under the scale trap, not the canonical ANE number). Python `predict()` timing is IPC/marshalling-dominated and misleads on a ~1.3M-param model (05-RESEARCH Decision 5), so latency is measured **in-process in Swift**. The Mac-corroborating number is already recorded; only the iPad-M4 canonical capture is manual. This follows the same D-18 "measure on Mac, gate the canonical claim on the target device" precedent (Phase-2 SC#1 / Phase-3 SC#1).

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
