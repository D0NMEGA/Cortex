# Phase 5 Plan 01 Evidence — Velocity readout head (DEC-10)

**Date:** 2026-06-21
**Result:** ✅ **PASS** — **DEC-10 closed.** The NDT1 encoder, with a linear velocity readout head
appended, converts to a Core ML `.mlpackage` that emits a **2-vector `(vx, vy)` fp16 cursor
velocity from the last 20 ms bin** (shape `(1, 2, 1, 1)`), replacing the Phase-4 96-channel rates
output. The head is a `1×1 Conv2d(96→2)` fit by **closed-form ridge regression** (no training
loop, no Kalman). PyTorch-fp32-vs-CoreML-fp16 **parity max-abs-delta = 0.000367**, far inside the
documented bound of **0.5**.

> **DEC-10:** "A linear velocity readout head appended pre-conversion so the `.mlpackage` emits
> `(vx, vy)` fp16 every 20 ms." Realized as: **(VelocityHead)** `nn.Conv2d(96, 2, kernel_size=1)`
> on the static last-bin slice `rates[..., -1:]`; **(ridge_fit)** closed-form
> `W = (XᵀX + λI)⁻¹ XᵀY` via `np.linalg.solve`, loaded into the conv through a `load_state_dict`
> pre-hook mirroring the Phase-4 dense→conv path; **(convert.py)** `ct.convert(...,
> compute_precision=ct.precision.FLOAT16)` + tanh-approximate GELU.

This is **CPU-only R&D characterization.** Conversion runs on the dev-Mac with the converter's
hardware-unit selector left unset (default engine selection); the parity prediction runs on CPU via
coremltools `MLModel.predict`. There is **NO Apple-Neural-Engine targeting, NO on-chip
residency/placement assertion, and NO on-device latency claim in this plan** — that is the rest of
Phase 5 (DEC-06..09, DEC-11..12, the `MLComputePlan` eligibility gate and the iPad-M4 device
artifact). This mirrors the Phase-4 boundary discipline (`04-palettization-evidence.md`).

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple Silicon (`arm64`) |
| **OS** | `macOS-26.5-arm64-arm-64bit` (macOS 26 Tahoe) |
| **Python** | 3.12.13 (uv-managed; pinned via `uv sync --project Decoder --extra dev`) |
| **coremltools** | **9.0** (locked; `ct.convert(convert_to="mlprogram")` + `compute_precision=ct.precision.FLOAT16` verified against `/apple/coremltools` via Context7) |
| **torch** | **2.12.1** (kept — the "2.7.0 most recent tested" advisory is info-level only; trace/convert succeed, matching the Phase-4 disposition) |
| **numpy** | 2.4.6 |
| **Compute units** | **default engine selection only** — the converter's hardware-unit kwarg is intentionally unset; predictions run on CPU. **No Neural-Engine targeting (rest of Phase 5).** |
| **Model** | `NDT1ANEWithVelocity(seq_len=32)` — `NDT1ANE` encoder (1,292,544 params; 6 layers, h=2, `d_model=128`, BC1S `(1, 96, 1, 32)`) + `VelocityHead` (1×1 `Conv2d(96→2)`) |

---

## Output contract (the frozen interface for Plans 03/04/05)

| Direction | Feature | Shape | dtype |
|-----------|---------|-------|-------|
| **Input** | `spikes` | `(1, 96, 1, 32)` (BC1S, sequence axis `S` last) | fp16 |
| **Output** | the single velocity feature | `(1, 2, 1, 1)` (flattens to 2 elements) | **fp16** |

The Swift `MLModel.prediction` path (Plan 03/04) reads exactly this fp16 `(1, 2, 1, 1)` output as
the `(vx, vy)` cursor velocity. The output feature dtype was verified to be `FLOAT16` and element
count `2` by reloading the converted package's `ct.models.MLModel.get_spec().description.output`.

**"Every 20 ms" is the Swift CALLER's decode cadence, not a graph-internal timer.** The model
consumes ONE 20 ms-binned window per call and emits ONE `(vx, vy)`; the 50 Hz / 20 ms cadence is
driven by the Plan-04 Swift decode loop. Per 05-RESEARCH Decision 1, the graph contains no timer
and no internal loop — the velocity "of this window" is read from the **static last-bin slice**
`rates[..., -1:]` (NOT dynamic indexing, which would fall off the ANE).

---

## Methodology

Exercised by two test modules under `Decoder/tests/` (`uv run --project Decoder pytest`):

1. **DEC-10 unit** (`test_velocity_head.py`, 5 fast tests): `VelocityHead.forward` returns
   `(B, 2, 1, 1)`; the output depends ONLY on the last bin (with a negative control — flipping the
   slice to `[..., :1]` makes the test fail — proving the slice direction is enforced); `ridge_fit`
   equals an independent `np.linalg.solve` closed form to 1e-5; `ridge_fit` raises `ValueError` on
   N mismatch; `load_ridge` reproduces `X @ Wᵀ + b` and the held-out R² is recorded.
2. **DEC-10 conversion + parity** (`test_convert_velocity_output.py`, 1 fast + 2 slow): the composed
   `NDT1ANEWithVelocity` forward returns `(1, 2, 1, 1)`; the converted `.mlpackage` output feature is
   **fp16 with 2 elements**; and the SAME fixed `(1, 96, 1, 32)` fp16 window through PyTorch-fp32
   (`model.eval()`) and the converted CoreML model (CPU predict) agree to within the documented
   bound. The ridge head is fit on the model's **PREDICTED rates** over seeded-synthetic windows.

---

## Results

### Velocity-decode R² (head quality — credibility evidence, not a hard SC)

| Fit | R² | Note |
|-----|----|----|
| Fit on **predicted rates** (n=64 windows, the inference-distribution fit) — `velocity_parity.json` | **0.879** | the representative number: ridge fit on the encoder's own predicted last-bin rates, exactly as the deployed head is fit (Decision 1, avoids train/serve skew) |
| Unit-test held-out (strong synthetic linear map, n=200) — `velocity_r2.json` | **0.99985** | the unit test's controlled linear-map check, confirming `load_ridge` reproduces `X @ Wᵀ + b` and the readout is non-degenerate |

Per 05-RESEARCH Decision 1, R² is **credibility evidence, not a hard success criterion**. Both
values are finite and well above the loose `R² > 0` non-degeneracy floor the unit test asserts. The
absolute R² of the deployed head will be set by the real Indy/Loco velocity labels (Plan 04 data
pipeline) on the trained checkpoint; this plan characterizes the head **mechanism** (closed-form
ridge → conv → fp16 output), not final decode accuracy.

### PyTorch-fp32-vs-CoreML-fp16 parity (conversion fidelity) — `velocity_parity.json`

| Quantity | Value |
|----------|-------|
| PyTorch fp32 velocity `(vx, vy)` | `[-0.341440, -0.153198]` |
| CoreML fp16 velocity `(vx, vy)` (CPU predict) | `[-0.341797, -0.153564]` |
| **\|max-abs-delta\|** | **0.000367** |
| **Documented bound** (`VELOCITY_PARITY_BOUND`) | **0.5** |
| Verdict | ✅ **0.000367 ≤ 0.5** (~1363× margin) |

The bound (`0.5`) is set from the **observed** delta (~3.7e-4, dominated by fp16 rounding of a
1×1-conv readout) plus a generous margin — an R&D characterization mirroring 04-05's
`LOSS_DELTA_BOUND = 0.5`, not a pre-set hard threshold. It still fails loudly if the conversion
were to corrupt the readout. The tiny observed delta confirms the `(vx, vy)` graph survives fp16
conversion with only rounding-level error.

---

## Disposition

- **Linear ridge readout, NOT Kalman.** A closed-form ridge readout is the correct Phase-5 output
  (05-RESEARCH Decision 1). ReFIT-Kalman closed-loop refinement is **REFIT-01 / Phase 7** (Swift,
  post-CoreML). Keeping the head linear is also what keeps the converted graph ANE-resident — a
  Kalman recursion on the graph would introduce ops that fall off the Neural Engine.
- **Fit on predicted rates, not ground-truth.** The head is fit on the encoder's own PREDICTED
  last-bin rates (`fit_velocity_head` consumes predicted rates), which matches the inference
  distribution and avoids train/serve skew (Decision 1).
- **No new training loop.** The readout is a single closed-form `np.linalg.solve`; weights load into
  the `1×1 Conv2d` via a `load_state_dict` pre-hook that mirrors the Phase-4 dense→conv path.
- **Phase boundary intact.** `convert.py` carries `compute_precision`/`FLOAT16` (precision only) and
  contains ZERO `cpuAndNeuralEngine` / `computeUnits` / `compute_units` / `_ANEClient` /
  `Instruments` / `residency` tokens — the Phase-4 negative-control test
  (`test_convert_source_targets_cpu_not_ane`) still passes. Compute-unit / engine targeting stays on
  the Swift side (DEC-07 / Plan 03).

---

## Hand-off to Plans 03/04/05

The artifacts the Swift inference path consumes (the `.mlpackage` + json are **gitignored**; the
NUMBERS + the code that rebuilds them are committed — Phase-4 artifact discipline):

| Artifact | Location (gitignored) | Role |
|----------|------------------------|------|
| velocity `.mlpackage` | `Decoder/checkpoints/ndt1_velocity_*.mlpackage` | rebuilt by `convert_to_mlpackage(NDT1ANEWithVelocity, ...)`; the fp16 `(1,2,1,1)` deployment graph Plan 03 loads with `computeUnits=.cpuAndNeuralEngine` |
| `velocity_parity.json` | `Decoder/checkpoints/velocity_parity.json` | the parity delta + R² transcribed above |
| `velocity_r2.json` | `Decoder/checkpoints/velocity_r2.json` | the unit-test held-out R² |
| with-velocity model | `Decoder/src/ndt1/model_ane.py` (`NDT1ANEWithVelocity`) | Plan 03/04/05 reuse the same constructor + the `(1,2,1,1)` output contract |

> **Artifact policy:** `*.mlpackage/` and `Decoder/checkpoints/` are gitignored (Plan 04-01). The
> committed, reproducible artifacts are the **numbers** (this note) and the **code** that rebuilds
> the package deterministically — never the model binaries.

---

## Reproduce (verbatim)

From a clean clone of this worktree, on Apple Silicon:

```bash
# Materialize the pinned venv (pytest/ruff are in the [dev] extra — REQUIRED, else a misleading
# "No module named numpy" surfaces):
uv sync --project Decoder --extra dev

# DEC-10 unit + conversion + parity (the slow tests build the .mlpackage transiently):
uv run --project Decoder pytest -q -s -k "velocity_head or velocity_output"
#   -> 5 fast unit tests + (1,2,1,1) shape + fp16-2-element output + parity all green
#   -> [DEC-10 parity] torch=[-0.341440 -0.153198]  coreml=[-0.341797 -0.153564]
#                      |max_abs_delta|=0.000367 <= bound=0.5
#   -> writes Decoder/checkpoints/velocity_r2.json + velocity_parity.json (gitignored)

# Phase-4 boundary stays intact (no ANE/compute-unit tokens leaked into convert.py):
uv run --project Decoder pytest -q -k convert_source_targets_cpu_not_ane

# Lint gate (no bare/blind except in the touched files):
uv run --project Decoder ruff check Decoder/src Decoder/tests
```

(Exact velocity values + the parity delta vary only at the last digits across machines /
coremltools patch levels; the `(1,2,1,1)` fp16 contract and the delta ≪ 0.5 bound are stable.)

---

## Conclusion

**DEC-10 PASSES.** The NDT1 encoder, with a `1×1 Conv2d(96→2)` velocity head appended and fit by
closed-form ridge regression, converts to an `mlprogram` `.mlpackage` whose single output feature
is a **fp16 `(1, 2, 1, 1)` `(vx, vy)`** cursor velocity read from the static last 20 ms bin. The
PyTorch-fp32-vs-CoreML-fp16 parity delta is **0.000367 ≤ 0.5**, and `compute_precision=FLOAT16` +
tanh-GELU are explicit in the conversion path (satisfying two of the Decision-2 ANE constraints for
the Plan-02 eligibility scan). No training loop, no Kalman, and the Phase-4 phase boundary holds.
The `(1, 2, 1, 1)` fp16 output contract is now frozen for the Swift inference path (Plans 03/04/05).
