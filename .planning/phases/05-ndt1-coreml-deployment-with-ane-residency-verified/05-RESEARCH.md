# Phase 5 Research: NDT1 → CoreML deployment with ANE residency verified

**Researched:** 2026-06-21 (main-thread browser-harness + Context7 pass — not the HTTP-only subagent)
**Phase goal:** The 4-bit palettized NDT1 checkpoint becomes a `.mlpackage` that runs entirely on the M4 Neural Engine in <2ms p99, input arriving zero-copy from a `MTLBuffer storageModeShared`, output a 2-vector cursor velocity at fp16 every 20ms.
**Requirements:** DEC-06, DEC-07, DEC-08, DEC-09, DEC-10, DEC-11, DEC-12
**Phase-4 handoff (verified in code):** `Decoder/src/ndt1/{model_ane.py,convert.py,palettize.py}` deterministically build an fp16 `mlprogram` `.mlpackage` + a 4-bit kmeans-palettized `.mlpackage` (coremltools 9.0 + torch 2.12.1, confirmed). `NDT1ANE.forward(x:(1,96,1,S)) -> rates:(1,96,1,S)` — encoder→Poisson-rates only; **no kinematics head** (`model_ane.py:14` "deferred to DEC-10 / Phase 5"). `CortexDecoder` Swift package is an 8-line stub (macOS 26 / iOS 26).

---

## TL;DR — the load-bearing findings

1. **ANE residency is now CI-assertable, not Instruments-only.** Both Swift (`MLComputePlan`, macOS 14.4+) and **Python coremltools** (`ct.models.compute_plan.MLComputePlan.load_from_path`) expose **per-operation compute-device usage**. DEC-06 (no fallback) can be proven programmatically on the dev Mac. This decouples the *eligibility* proof from iPad-M4 hardware.

2. **THE TRAP — model is below the ANE runtime-placement scale threshold.** Prior art (`meridian-mcp/ane_encoder`) proves that a *small* transformer can be **100% ANE-eligible yet 0% ANE-placed at runtime on Mac**, because the scheduler picks CPU as `.preferred` until compute-per-op amortises ANE dispatch (~5–10M params on Apple Silicon). **Cortex NDT1 is ~1.29M params** → on the **M5 Mac**, `.preferred` may be CPU. ⇒ Split the verification: *eligibility* (`.supported` ⊇ ANE) = Mac CI gate (DEC-06); *placement* (`.preferred == ANE`, 100% residency) = **iPad-M4 device artifact** (DEC-08), via Instruments/Performance Report, which use the more ANE-eager mobile scheduler.

3. **Zero-copy (DEC-09) = `MLMultiArray(pixelBuffer:shape:)` over a shared IOSurface.** Apple docs: this initializer "reduces inference latency by avoiding the buffer copy to and from some compute units" and **requires `kCVPixelFormatType_OneComponent16Half` (fp16)** — exactly Cortex's input dtype. An `MTLBuffer storageModeShared` and the `CVPixelBuffer` share one `IOSurface` ⇒ true zero-copy to ANE. The spec's `MPSGraphTensorData(mtlBuffer:)` is the MPSGraph-native equivalent; for a CoreML `.mlpackage` the pixel-buffer path is the documented mechanism.

4. **Velocity head (DEC-10) is a linear ridge readout appended pre-conversion.** Standard iBCI practice: rates → velocity is a linear decoder (Wiener/ridge/OLE); the Kalman/ReFIT refinement is **Phase 7**. Append a `1×1 Conv2d(96→2)` (BC1S-preserving) + last-bin selection, fit by ridge regression on the Indy synthetic velocity labels, so the `.mlpackage` itself emits `(vx, vy)` fp16.

5. **DEC-11 latency must be measured in Swift in-process.** Python `predict()` wall-time is IPC-dominated and "obscures absolute speedup on tiny models" (meridian). Measure with an in-process Swift loop (`MLModel.prediction`, warmup + 10k passes, `ContinuousClock`/`mach_absolute_time` histogram). Mac M5 = informational; iPad M4 = canonical.

6. **einsum attention is an ANE-residency risk to verify.** Cortex's `ndt1.attention` uses `bchq,bkhc->bkhq` einsum (per `apple/ml-ane-transformers`). meridian's ANE allowlist *excludes* einsum (they rewrote attention as Conv2d projections + element-wise mul + reduce_sum). einsum *can* lower to ANE-resident matmuls, but the `MLComputePlan` op scan is the arbiter — if any einsum-derived op shows `.supported` without ANE, contingency = the Conv2d+mul+reduce_sum rewrite.

---

## Decision 1 — Velocity readout head (DEC-10)

**Problem:** model emits 96-ch rates; DEC-10/SC#3 require a 2-vector `(vx,vy)` fp16 emitted every 20ms.

**Recommendation:** append a kinematics readout to `NDT1ANE` *before* CoreML conversion so the `.mlpackage` output is `(1,2,1,1)` (or `(1,2)`) fp16:
- **Layer:** `nn.Conv2d(num_channels=96, 2, kernel_size=1)` operating on the last time-bin of the rates (BC1S preserved; 1×1 conv is ANE-eligible). Select the last bin via a static slice `x[..., -1:]` (ANE-friendly) rather than dynamic indexing.
- **Fit:** ridge regression (closed-form `(XᵀX+λI)⁻¹XᵀY`) of rates→velocity on the Indy/Loco synthetic replay used in Phase 4 (the data pipeline already exists: `Decoder/src/ndt1/data.py`). Load the ridge weights into the Conv2d via a state-dict hook (mirrors Phase-4's dense→Conv2d `load_state_dict` pre-hook in `model_ane.py:125`).
- **Why linear, not Kalman:** ReFIT-Kalman is REFIT-01/Phase 7 (Swift, post-CoreML). Phase 5's CoreML output is the *raw* linear velocity; Phase 7 refines it closed-loop. Keeping the head linear also keeps the graph ANE-resident.
- **20ms cadence (DEC-10):** the model consumes one 20ms spike-bin window per call; "every 20ms" is the *call cadence* driven by the Swift caller (the 50Hz decode loop), not something inside the graph.

**Evidence:** standard iBCI decode reviews — Neural Decoding for Intracortical BCIs (PMC10380541; spj.science.org/doi/10.34133/cbsystems.0044); "Simple decoding of behavior from a complicated neural manifold" (eLife 89421). Neural Latents Benchmark convention: NDT predicts rates; a separate linear/ridge readout maps rates→behaviour.

**Open question for the planner:** fit the ridge head on (a) ground-truth held-out rates or (b) the model's *predicted* rates (recommended — matches inference distribution). Either is defensible; (b) avoids train/serve skew. Record the velocity-decode R² as the head's quality evidence (not a hard SC, but credibility).

---

## Decision 2 — ANE residency verification (DEC-06 eligibility + DEC-08 placement)

### The two distinct claims (do NOT conflate)
| Claim | API surface | Device/scale dependent? | Where it runs |
|---|---|---|---|
| **Eligibility** — every op *can* run on ANE (`.supported` ⊇ neuralEngine) + static MIL allowlist | `MLComputePlan` `.supported`; MIL op parse | **No** (compiler property) | **Mac CI gate** ✅ |
| **Placement** — every op *will* run on ANE (`.preferred == neuralEngine`), 100% residency | `MLComputePlan` `.preferred`; Instruments; Xcode Performance Report | **Yes** (scheduler + scale + chip) | **iPad M4 artifact** |

### Programmatic API (confirmed)
**Python (coremltools — runs in the existing Decoder pytest on the M5 Mac):**
```python
import coremltools as ct
plan = ct.models.compute_plan.MLComputePlan.load_from_path(
    path=compiled_mlmodelc_path,            # must be COMPILED: ct.compile_model() or model.get_compiled_path()
    compute_units=ct.ComputeUnit.CPU_AND_NE,
)
prog = plan.model_structure.program
for op in prog.functions["main"].block.operations:
    usage = plan.get_compute_device_usage_for_mlprogram_operation(op)  # -> MLComputePlanDeviceUsage | None
    # usage.preferred, usage.supported  (mirror the Swift struct)
    cost  = plan.get_estimated_cost_for_mlprogram_operation(op)
```
**Swift (`MLComputePlan`, macOS 14.4+ / iOS 17.4+ — CortexDecoder XCTest, or `inspect_ane.swift` via `xcrun coremlcompiler compile` + `swift inspect_ane.swift`):**
```swift
let plan = try await MLComputePlan.load(contentsOf: url, configuration: config)
guard case let .program(program) = plan.modelStructure,
      let main = program.functions["main"] else { fatalError() }
for op in main.block.operations {
    let usage = plan.deviceUsage(for: op)     // .preferred: MLComputeDevice, .supported: [MLComputeDevice]
    let cost  = plan.estimatedCost(of: op)
}
// MLComputeDevice = .cpu(_) | .gpu(_) | .neuralEngine(_)
```

### Recommended test design (robust — avoids flakiness)
- **DEC-06 Mac CI gate (automatable, deterministic):** load compute plan with `CPU_AND_NE`; assert for **every** schedulable op `neuralEngine ∈ usage.supported` and **zero** ops with `usage.supported == [cpu]` only. Emit `residency.txt` + `runtime_plan.json` artifacts (meridian convention). This catches the real regression — an op that *cannot* go on ANE (e.g. an einsum lowering that needs GPU/CPU).
- **DEC-08 iPad-M4 artifact (device-gated, HUMAN-UAT):** on the connected iPad Pro M4, capture **either** the Instruments → Core ML template trace **or** the Xcode `.mlpackage` Performance Report **or** run `MLComputePlan` on-device, showing 100% `.preferred == neuralEngine`. Commit the screenshot/trace + `runtime_plan_ipad.json` to the repo for reviewer verification (SC#1).
- **Do NOT** assert `.preferred == neuralEngine` on the M5 Mac as a build gate — the 1.29M-param scale may legitimately yield CPU-preferred placement there (the trap). If desired as informational, log it, don't fail on it.

### The four ANE constraints (DEC-06 op-support) — Cortex status
Per `apple/ml-ane-transformers` (github.com/apple/ml-ane-transformers) + meridian:
| Constraint | Requirement | Cortex `model_ane.py` |
|---|---|---|
| Precision | fp16 weights+activations; `compute_precision=ct.precision.FLOAT16` | fp16 TensorType ✓ — **verify `compute_precision=FLOAT16` is explicit** in `convert.py` |
| Layout | `(B,C,1,S)` 4-D, matmuls as 1×1 Conv2d | BC1S + Conv2d read_in/readout/FFN ✓ |
| Operators | split-axis LayerNorm, **tanh-GELU**, no concat/bmm/einsum/SDPA | LayerNormANE ✓; **GELU — verify `approximate='tanh'`**; **einsum attention ⚠ (see Decision 6)** |
| Shapes | static (or RangeDim) at convert | fixed `seq_len S` ✓ (better than RangeDim for ANE) |

---

## Decision 3 — Zero-copy input (DEC-09)

**Apple-documented mechanism (confirmed):** `MLMultiArray(pixelBuffer: CVPixelBuffer, shape: [NSNumber])` (iOS 16+/macOS 12+) — "creates an IOSurface-backed MLMultiArray that **reduces inference latency by avoiding the buffer copy to and from some compute units**." Constraints: pixel format **`kCVPixelFormatType_OneComponent16Half`**, data type `MLMultiArrayDataType.float16`, `shape.last == pixelBuffer.width`, `product(rest) == height`.

**Recommended path:**
1. Create one `IOSurface` (or `CVPixelBuffer` via `CVPixelBufferCreate` with an IOSurface-backed pool, format `OneComponent16Half`, width = `S`, height = `96`).
2. Create the `MTLBuffer` over the **same** IOSurface (`device.makeBuffer(bytesNoCopy: surface.baseAddress …)` / `MTLTextureDescriptor` over the surface) — `storageModeShared`, so the renderer/IPC side writes spikes there with no copy.
3. `MLMultiArray(pixelBuffer:shape:[96, S])` → wrap in `MLFeatureValue(multiArray:)` → `MLDictionaryFeatureProvider(dictionary:["spikes": …])` → `model.prediction(from:)`.

**Fallback (simpler, weaker):** `MLMultiArray(dataPointer: mtlBuffer.contents(), shape:, dataType:.float16, strides:, deallocator: nil)` (iOS 11+). On unified memory `.contents()` is the shared CPU pointer → no CPU memcpy, but does **not** guarantee avoiding the ANE-side copy that the pixel-buffer path elides. Keep the `MTLBuffer` alive for the array's lifetime (deallocator nil + retained reference).

**DEC-09 test:** assert no `memcpy`/`Array`-copy on the inference path (the `MLMultiArray` is constructed over the surface, not from a Swift array); a Metal frame-capture or pointer-identity check (`multiArray.dataPointer == surface.baseAddress`) proves sharing. Note honestly in evidence: "zero host-side copy; ANE DMA is internal to CoreML."

---

## Decision 4 — Compute units + private-API hygiene (DEC-07, DEC-12)

- **DEC-07:** `MLModelConfiguration().computeUnits = .cpuAndNeuralEngine` (NOT `.all`). `MLComputeUnits` cases: `.all`, `.cpuOnly`, `.cpuAndGPU`, `.cpuAndNeuralEngine` (last added iOS16/macOS13). Python equiv: `ct.ComputeUnit.CPU_AND_NE`. **Build-failing unit test:** a Swift test asserting the production config value `== .cpuAndNeuralEngine` and a CI grep that fails if `.all` is set on the inference config. Rationale: `.all` lets the scheduler hand ops to the GPU, defeating the residency claim and adding latency variance.
- **DEC-12:** zero `_ANEClient` (private API → guaranteed App Store rejection). CI grep over the whole tree (`grep -rn '_ANEClient'` must be empty) — extends the existing Phase-4 negative-control discipline. `MLComputePlan` + public `MLModel` cover everything; no private API is ever needed.

---

## Decision 5 — Latency measurement (DEC-11)

- **Measure in Swift, in-process** (CortexDecoder XCTest or a small bench executable): warm up (first `prediction` triggers compile/load), then 10,000 `model.prediction(from:)` calls, record per-call ns via `ContinuousClock` / `mach_absolute_time`, compute p50/p99, write a histogram artifact.
- **Why not Python:** coremltools `predict()` wall-time is IPC/marshalling-dominated and misleads on tiny models (meridian: "runtime plan is the load-bearing proof").
- **Targets:** SC#4 is <2ms p99 on **iPad M4** (canonical artifact, device-gated). The **M5 Mac** measurement is strong corroborating evidence now (newer ANE; for a 1.3M model expect well under 1ms *when ANE-placed* — but if Mac places on CPU per the scale trap, the Mac number reflects CPU latency, so annotate which device each op ran on, taken from the compute plan).
- Commit `latency_histogram.{json,png}` + the device/placement annotation alongside the Instruments trace.

---

## Decision 6 — einsum attention ANE risk + contingency

Cortex `ndt1.attention` = `bchq,bkhc->bkhq` einsum (from `apple/ml-ane-transformers`, which itself ships einsum attention that *is* meant to lower to ANE ops). meridian took the conservative route (no einsum; attention = Conv2d Q/K/V/Out + element-wise mul + `reduce_sum`). **Verdict:** verify, don't assume.
- **Verify:** the DEC-06 `MLComputePlan` op scan will show the device usage of every einsum-derived op (coremltools lowers `einsum` to `matmul`/`transpose`/`reduce` MIL ops). If all land ANE-eligible → keep as-is.
- **Contingency (only if an op falls back):** rewrite `attention.py` to the meridian formulation (Conv2d projections + broadcast mul + `reduce_sum` over the contraction axis) — mathematically equivalent, allowlist-clean. This is a bounded, well-precedented change; flag it as a conditional task, not a default one.

---

## Hardware strategy — what's gated on what (mirrors THREAD-02/SC#1 precedent)

| Requirement | Mac (M5) — automatable CI gate NOW | iPad M4 — device artifact (HUMAN-UAT runbook) |
|---|---|---|
| DEC-06 op eligibility (`.supported` ⊇ ANE, MIL allowlist) | ✅ primary proof | (corroborated by Performance Report) |
| DEC-07 `.cpuAndNeuralEngine` config | ✅ unit test + grep | — |
| DEC-08 100% runtime placement (`.preferred==ANE`) | ⚠ informational only (scale trap) | ✅ **canonical** (Instruments/Performance Report) |
| DEC-09 zero-copy input | ✅ code + pointer-identity test | (latency benefit visible on device) |
| DEC-10 `(vx,vy)` fp16 every 20ms | ✅ output-shape + parity test | — |
| DEC-11 <2ms p99 | ⚠ corroborating (annotate device) | ✅ **canonical** histogram |
| DEC-12 no `_ANEClient` | ✅ CI grep | — |

**Implication for SC mapping:** SC#1 (Instruments residency) and SC#4 (<2ms p99) are iPad-M4-gated → a `05-HUMAN-UAT.md` runbook (precedent: `03-HUMAN-UAT.md`). SC#2 (`.cpuAndNeuralEngine` test + no `_ANEClient`) and SC#3 (`(vx,vy)` zero-copy) are fully closeable on the Mac now.

---

## Recommended build order (for the planner — not prescriptive on plan count)

1. **Velocity head + ridge fit (Python, Decoder/):** extend `model_ane.py` with the Conv2d(96→2) head + last-bin slice; fit ridge on Indy replay; update `convert.py` so the `.mlpackage` output is `(vx,vy)` fp16; ensure `compute_precision=FLOAT16` + tanh-GELU. Parity test (PyTorch fp32 vs CoreML fp16, max-abs-delta tolerance). → DEC-10 + feeds all.
2. **ANE eligibility gate (Python, Decoder/):** `MLComputePlan.load_from_path` op scan asserting ANE eligibility for every op; emit `residency.txt`/`runtime_plan.json`; verify einsum ops (Decision 6). → DEC-06 (+ contingency rewrite if needed).
3. **Swift inference path (CortexDecoder):** load the `.mlpackage` with `computeUnits=.cpuAndNeuralEngine`; zero-copy `MLMultiArray(pixelBuffer:)` over a shared IOSurface; emit `(vx,vy)` fp16; XCTest for config value, output shape/dtype, zero-copy pointer identity. CI grep for `.all` and `_ANEClient`. → DEC-07, DEC-09, DEC-10, DEC-12.
4. **Latency bench (Swift):** in-process 10k-pass histogram on M5 Mac (corroborating) + the device runbook. → DEC-11 (Mac) / SC#4 (iPad).
5. **iPad-M4 HUMAN-UAT runbook (`05-HUMAN-UAT.md`):** verbatim steps for Instruments Core ML residency trace + on-device p99 + Performance Report; lists the repo artifacts a reviewer checks. → DEC-08 + SC#1/SC#4 canonical.

**Decoder/ env reminder (project memory):** `uv sync --project Decoder --extra dev` before any pytest/ruff; coremltools locked at **9.0**; no bare/blind `except` (ruff BLE gate).

---

## Validation Architecture (Nyquist)

Each requirement gets a *characterization* (the measured value + a bound with margin, R&D-style, mirroring Phase-4's `sc4_*.json` + evidence-doc discipline), not just a boolean.

| Req | Validation method | Sampling / N | Pass condition | Artifact |
|---|---|---|---|---|
| DEC-06 | `MLComputePlan` op scan (Python, Mac) | all schedulable ops (100%) | every op: `neuralEngine ∈ supported`; 0 ops CPU-only | `residency.txt`, `runtime_plan.json` |
| DEC-07 | Swift unit test on production config | 1 (build gate) | `computeUnits == .cpuAndNeuralEngine`; grep `.all` empty | test + CI log |
| DEC-08 | Instruments Core ML / on-device `MLComputePlan` (iPad M4) | full graph | 100% `preferred == neuralEngine`, 0 CPU/GPU | trace/screenshot, `runtime_plan_ipad.json` |
| DEC-09 | pointer-identity + frame-capture (Swift) | inference path | `multiArray.dataPointer == surface.baseAddress`; no host copy | test + capture note |
| DEC-10 | output shape/dtype + parity (Python+Swift) | fixed window | output `(…,2)` fp16; PyTorch-vs-CoreML max-abs-δ ≤ tol | `parity.txt` |
| DEC-11 | in-process Swift 10k-pass timer | n=10,000 | p99 < 2ms on iPad M4 (Mac annotated) | `latency_histogram.{json,png}` |
| DEC-12 | tree-wide grep | whole repo | `_ANEClient` count == 0 | CI log |

---

## Risks & open questions

1. **(HIGH) Scale-threshold placement** — 1.29M params may be CPU-preferred on Mac; iPad-M4 placement is *expected* (mobile scheduler more ANE-eager) but **not yet proven**. If the iPad also CPU-places, options: (a) accept ANE-*eligible* + document the scheduler choice (still a defensible, honest artifact), (b) increase compute-per-op (wider d_model / fused ops) — but that's a retrain (Phase 4 scope), (c) `MLModelConfiguration.allowLowPrecisionAccumulationOnGPU`/hints — does not force ANE. **Recommend:** plan for eligibility as the hard gate; treat 100% placement as the device-measured artifact with an honest fallback narrative. This is the single biggest credibility risk — surface it explicitly in the plan.
2. **(MED) einsum lowering** — see Decision 6; contingency bounded.
3. **(MED) IOSurface↔MTLBuffer↔CVPixelBuffer plumbing** — three-way sharing has format/stride pitfalls (row padding: `CVPixelBufferGetBytesPerRow` may exceed `width*2`); the `MLMultiArray(pixelBuffer:)` shape must account for it. Verify with a known-pattern round-trip.
4. **(LOW) compiled-model requirement** — `MLComputePlan.load_from_path` needs a compiled `.mlmodelc` (via `ct.compile_model()` / `xcrun coremlcompiler compile`), not the raw `.mlpackage`. Add the compile step to the test fixture.
5. **(LOW) palettized vs fp16 for residency** — verify the *4-bit palettized* package is the one tested for residency/latency (the deployment artifact), not only the fp16 one. Palettized weights are decompressed for ANE; confirm the op set/placement is unchanged.

## Main-thread-gated research
None outstanding — this pass was run on the main thread (browser-harness + Context7). No items deferred to a browser-only follow-up.

## Citations
- Apple — `MLComputePlan`: https://developer.apple.com/documentation/coreml/mlcomputeplan ; `DeviceUsage` (`preferred`/`supported`): https://developer.apple.com/documentation/coreml/mlcomputeplan/deviceusage ; `MLComputeDevice` (.cpu/.gpu/.neuralEngine): https://developer.apple.com/documentation/coreml/mlcomputedevice
- Apple — `MLMultiArray(pixelBuffer:shape:)` (IOSurface zero-copy, OneComponent16Half): https://developer.apple.com/documentation/coreml/mlmultiarray/init(pixelbuffer:shape:) ; `init(dataPointer:…)`: https://developer.apple.com/documentation/coreml/mlmultiarray/init(datapointer:shape:datatype:strides:deallocator:)
- Apple — `MLModelConfiguration.computeUnits` / `MLComputeUnits`: https://developer.apple.com/documentation/coreml/mlmodelconfiguration/computeunits
- coremltools — Python `MLComputePlan.load_from_path` + `get_compute_device_usage_for_mlprogram_operation`, `ComputeUnit.CPU_AND_NE`: docs/source/mlmodel-utilities.md & coremltools.models.md (via Context7 /apple/coremltools)
- Apple — ANE Transformers principles (BC1S, 1×1 conv, allowlist): https://github.com/apple/ml-ane-transformers ; https://machinelearning.apple.com/research/apple-neural-engine
- **Prior art** — `meridian-mcp/ane_encoder` (small transformer → CoreML → 100% ANE verified via MLComputePlan; the scale-threshold finding; 4-constraint recipe; proof-artifact convention): https://github.com/LuuOW/meridian-mcp/blob/main/mlcore/ane_encoder/README.md
- iBCI linear/ridge velocity decode: Neural Decoding for Intracortical BCIs (https://pmc.ncbi.nlm.nih.gov/articles/PMC10380541/ ; https://spj.science.org/doi/10.34133/cbsystems.0044) ; "Simple decoding of behavior from a complicated neural manifold" (https://elifesciences.org/reviewed-preprints/89421v1)
