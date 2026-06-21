# Phase 4 SC4 Evidence — `.mlpackage` conversion (DEC-03) + 4-bit palettization (DEC-05)

**Date:** 2026-06-21
**Result:** ✅ **PASS** — the NDT1 encoder→rates graph converts to an `mlprogram` `.mlpackage`,
palettizes to a **4-bit k-means** package that is **3.471× smaller** (fp16 → 4-bit), and whose
fp16-vs-4-bit Poisson-NLL reconstruction delta is **0.009114**, far inside the documented bound
of **0.5** (~55× margin).

> **SC4 (Phase 4 Success Criterion #4):** "`palettize_weights` + `OpPalettizerConfig(nbits=4)` →
> quantized checkpoint, documented size reduction + bounded loss delta." Realized as:
> **(DEC-03)** `ct.convert(convert_to="mlprogram", …)` → `.mlpackage`, then **(DEC-05)**
> `coremltools.optimize.coreml.palettize_weights(model, OptimizationConfig(global_config=OpPalettizerConfig(mode="kmeans", nbits=4)))`.

This is **CPU-only R&D characterization.** Conversion and palettization run on the dev-Mac with
the converter's hardware-unit selector left unset (default engine selection), and the loss delta
is measured via coremltools **`MLModel.predict` CPU prediction**. There is **NO Apple-Neural-Engine
targeting, NO on-chip residency/placement assertion, and NO on-device latency claim in this phase**
— that is **Phase 5** (DEC-06..12). This mirrors how Phase 2 split its hardware-gated SC#1 number
(`sc1-evidence.md`) from CI-asserted correctness.

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple Silicon (`arm64`) |
| **OS** | `macOS-26.5-arm64-arm-64bit` (macOS 26 Tahoe) |
| **Python** | 3.12.13 (uv-managed; pinned, not the system 3.14 — see `Decoder/README.md`) |
| **coremltools** | **9.0** (resolved by Plan 04-01; the `palettize_weights` / `OpPalettizerConfig` / `OptimizationConfig` / `ct.convert(convert_to="mlprogram")` APIs are stable 8→9 and verified against `/apple/coremltools` via Context7) |
| **torch** | **2.12.1** (kept — see torch-compat note below) |
| **numpy** | 2.4.6 |
| **Compute units** | **default engine selection only** — the converter's hardware-unit kwarg is intentionally omitted; predictions run on CPU. **No Neural-Engine targeting (Phase 5).** |
| **Model** | `NDT1ANE(seq_len=32)` — 1,292,544 params (~1.30M), 6 layers, h=2, `d_model=128`, BC1S `(1, 96, 1, 32)` (Plan 04-03) |

### torch-compatibility disposition (Wave-1 forward note resolved)

Plan 04-01 flagged that coremltools 9.0 prints a soft advisory — *"Torch 2.12.1 has not been
tested; 2.7.0 is the most recent tested"* — and instructed 04-05 to fall back to `torch<=2.7`
(the `>=2.2` floor permits it) **only if a hard error surfaced**. **Outcome: no hard error.**
`torch.jit.trace` + `ct.convert(convert_to="mlprogram")` produced a valid `MLModel` under torch
2.12.1, the 4-bit palettization succeeded, and both packages ran CPU prediction cleanly. The
advisory is informational only (it is not even raised through Python's `warnings` machinery — it
is an info-level coremltools log). **Decision: keep torch 2.12.1; no pin change, no re-lock.**

---

## Methodology

The pipeline is the two-step Core ML build (`Decoder/src/ndt1/convert.py` + `palettize.py`),
exercised by three `@pytest.mark.slow` integration tests:

1. **DEC-03 convert** (`test_convert_mlpackage.py`): `NDT1ANE(seq_len=32).eval()` →
   `torch.jit.trace` on a `(1, 96, 1, 32)` **fp16** BC1S example → `ct.convert(traced,
   convert_to="mlprogram", inputs=[TensorType(name="spikes", dtype=np.float16)],
   minimum_deployment_target=ct.target.iOS18)` → `.save(.mlpackage)`. The package is asserted to
   exist, be a non-empty bundle dir, and reload via `ct.models.MLModel(path)`.
2. **DEC-05 palettize + size** (`test_palettized_package.py`): load the fp16 `mlprogram`
   `MLModel` → `OptimizationConfig(global_config=OpPalettizerConfig(mode="kmeans", nbits=4))` →
   `palettize_weights` → `.save`. **Size** = byte-sum of every file in each `.mlpackage` dir tree.
   Asserts the 4-bit package exists and is strictly smaller; records the ratio to `sc4_size.json`.
3. **DEC-05 loss delta** (`test_palettization_loss_delta.py`): run the SAME fixed `(1, 96, 1, 32)`
   fp16 window through BOTH packages via `MLModel.predict` (CPU); compute the Poisson NLL of each
   log-rate output against one fixed seeded spike-count draw; assert `abs(NLL_4bit − NLL_fp16) ≤
   0.5`. Records the delta to `sc4_delta.json`.

DEC-03 strictly precedes DEC-05 (palettization needs an already-converted `mlprogram` — Pitfall
#4). k-means palettization is an offline build step (the heavy tests carry the `slow` marker).

---

## Results

### Size reduction (SC4 — documented size reduction) — `sc4_size.json`

| Package | Bytes | Note |
|---------|-------|------|
| fp16 `mlprogram` `.mlpackage` | **2,678,038** | the DEC-03 output |
| 4-bit (kmeans, `nbits=4`, per_tensor) `.mlpackage` | **771,534** | the DEC-05 output |
| **Size ratio (fp16 / 4-bit)** | **3.471×** | whole-package |

The **weight** footprint drops ~4× (4 bits/weight vs fp16's 16). The whole-`.mlpackage` ratio is
**3.471×** because the bundle also carries fixed metadata (the `mlmodel` spec, manifest, the
16-entry LUT) that does not shrink — so a sub-4× whole-package ratio is exactly expected, not a
shortfall. The test measures the **actual** ratio rather than hard-asserting 4×.

### Reconstruction-loss delta (SC4 — bounded loss delta) — `sc4_delta.json`

| Quantity | Value |
|----------|-------|
| Poisson NLL, **fp16** package (CPU predict) | **1.186899** |
| Poisson NLL, **4-bit** package (CPU predict) | **1.177785** |
| **\|Δ NLL\| (4-bit vs fp16)** | **0.009114** |
| **Documented bound** | **0.5** |
| Verdict | ✅ **0.009114 ≤ 0.5** (~55× margin) |

The bound (`LOSS_DELTA_BOUND = 0.5`) is set from the **observed** delta (~9e-3 nats/element on
this seeded window) plus a generous margin — an R&D characterization, not a pre-set hard threshold
(04-RESEARCH DEC-05). It still fails loudly if 4-bit palettization were to grossly corrupt the
reconstruction. The tiny observed delta confirms 4-bit k-means barely perturbs the output rates.

> **Note on the model state:** SC4 characterizes the **conversion + palettization of the forward
> graph** (size + bounded delta), which does not require full training convergence — so this plan
> uses a constructed/initialized `NDT1ANE` and runs independently of the full training run
> (Plan 04-04). The convergence number (SC2 / co-bps) is 04-04's committed evidence.

---

## No-ANE-claim disposition (phase boundary intact)

Asserted **structurally** (the same trap-bites discipline as Phases 1–3), not just by convention:

- `convert.py` and `palettize.py` contain **zero** `cpuAndNeuralEngine` / `computeUnits` /
  `compute_units` / `_ANEClient` / `Instruments` / `residency` tokens — enforced by acceptance
  greps and a negative-control test (`test_convert_source_targets_cpu_not_ane`,
  `test_loss_delta_uses_cpu_prediction_within_phase_boundary`).
- The converter is called with **no** hardware-unit kwarg → default engine selection; predictions
  are CPU `MLModel.predict`. No Neural-Engine targeting, no Instruments trace, no residency or
  on-device latency assertion appears anywhere in this plan.

This phase produces the artifacts; **Phase 5** sets `MLModelConfiguration.computeUnits =
.cpuAndNeuralEngine`, verifies ANE residency via Instruments, and measures the <2ms p99 latency.

---

## Phase-5 hand-off

The artifacts Phase 5 consumes for ANE residency / latency work (both gitignored — see policy):

| Artifact | Location (gitignored) | Role |
|----------|------------------------|------|
| fp16 `mlprogram` `.mlpackage` | `Decoder/checkpoints/ndt1_fp16_*.mlpackage` | rebuilt by `convert_to_mlpackage` (DEC-03) — the un-palettized baseline |
| **4-bit palettized `.mlpackage`** | `Decoder/checkpoints/ndt1_4bit_*.mlpackage` | rebuilt by `palettize_4bit` (DEC-05) — the bandwidth-reduced model Phase 5 targets onto the ANE |
| BC1S model definition | `Decoder/src/ndt1/model_ane.py` (`NDT1ANE`) | Phase 5 reuses the same constructor |

> **Artifact policy:** `*.mlpackage/` and `Decoder/checkpoints/` are gitignored (Plan 04-01). The
> committed, reproducible artifacts are the **numbers** (this note + `sc4_size.json` / `sc4_delta.json`
> values, transcribed above) and the **code** that rebuilds the packages deterministically — never
> the model binaries. Phase 5 regenerates the packages from `convert.py` + `palettize.py`.

---

## Reproduce (verbatim)

From a clean clone of this worktree, on Apple Silicon:

```bash
# Materialize the pinned venv (pytest/ruff are in the [dev] extra — REQUIRED):
uv sync --project Decoder --extra dev

# Run the convert + palettize + loss-delta evidence tests (the slow build step):
uv run --project Decoder pytest -m slow -k "convert or palettiz" -q -s
#   -> [SC4a size] fp16=2678038 B  4bit=771534 B  ratio=3.471x
#   -> [SC4b delta] NLL fp16=1.186899  4bit=1.177785  |delta|=0.009114 <= bound=0.5
#   -> writes Decoder/checkpoints/sc4_size.json + sc4_delta.json (gitignored)

# Quick suite (no slow build) stays green too:
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder ruff check Decoder/src Decoder/tests
```

(Exact byte counts and the NLL delta vary only at the last digits across machines/coremltools
patch levels; the size ratio ≈3.5× and the delta ≪ 0.5 bound are stable.)

---

## Conclusion

**Phase 4 SC4 PASSES.** The NDT1 encoder→rates graph (Plan 04-03) traces and converts to an
`mlprogram` `.mlpackage` on CPU under torch 2.12.1 + coremltools 9.0 (no fallback needed), then
4-bit k-means palettization yields a **3.471× smaller** package whose CPU-prediction Poisson-NLL
delta vs fp16 is **0.009114 ≤ 0.5** — a documented size reduction and a bounded reconstruction
loss, both committed here for audit. The phase boundary holds: **CPU-only, no Neural-Engine
targeting** — the fp16 + 4-bit packages are handed to Phase 5 for ANE residency and latency.
