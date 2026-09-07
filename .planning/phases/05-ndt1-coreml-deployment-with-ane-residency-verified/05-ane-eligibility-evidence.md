# Phase 5 DEC-06 Evidence — ANE op-eligibility of the compiled 4-bit `(vx,vy)` model

> **SUPERSEDED FOR THE OP TALLY (Phase 9, 2026-09-02).** The 226/226 count below was read from a
> stale compiled artifact: `compile_model` nested each new `.mlmodelc` inside the existing destination
> due to a `shutil.move` defect, so every MLComputePlan scan since 2026-06-21 read the same
> zero-weight graph. Isolating each compile under `tmp_path` fixed it. The trained real-data graph
> carries 12 `batch_norm` ops and one extra `add` that a zero-initialized `pos_encoding` folds away.
> The corrected tally is **239/239 ANE-eligible, 0 CPU-only ops**, re-measured on the trained
> real-data graph. See
> [`09-coreml-evidence.md`](../09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-coreml-evidence.md).
> The eligibility verdict (100% ANE-eligible) survives the correction; only the count changes.
>

**Date:** 2026-06-21
**Result:** ✅ **PASS** — DEC-06 closed. Every schedulable op of the **compiled 4-bit palettized**
`(vx, vy)` Core ML model is **ANE-ELIGIBLE** (`neuralEngine ∈ supported_compute_devices`), with
**zero CPU-only ops** (`226/226` eligible, `cpu_only = 0`). The `bchq,bkhc->bkhq` einsum attention
lowers to ANE-eligible MIL ops, so the Decision-6 contingency rewrite (Plan 05-02 Task 3) was
**NOT triggered**.

> **DEC-06:** "Programmatic `MLComputePlan` proof on the dev Mac that every op of the compiled 4-bit
> palettized `(vx,vy)` model is ANE-eligible (`neuralEngine ∈ supported`), zero CPU-only ops."
> Realized as: `coremltools.models.utils.compile_model(.mlpackage) → .mlmodelc`, then
> `MLComputePlan.load_from_path(path, compute_units=ComputeUnit.CPU_AND_NE)`, then a per-op walk of
> `program.functions["main"].block.operations` recording each op's
> `get_compute_device_usage_for_mlprogram_operation(op).supported_compute_devices`.

This is the **ELIGIBILITY** claim — a *compiler* property, device-independent and CI-assertable on
the dev Mac. It is the hard gate. Runtime **PLACEMENT** (100% residency, `preferred == neuralEngine`)
is a *separate*, scale-/scheduler-/chip-dependent claim (DEC-08) reserved for the iPad-M4 HUMAN-UAT
artifact (Plan 05). **This gate does NOT assert placement** — see "The eligibility / placement
split" below for why that would false-fail on Mac.

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple **M5 Pro** (`arm64`) — ≥ the M4 spec floor; newer ANE |
| **OS** | `macOS-26.5-arm64-arm-64bit` (macOS 26 Tahoe) |
| **Python** | 3.12.13 (uv-managed; pinned, not the system 3.14) |
| **coremltools** | **9.0** (locked) — the `MLComputePlan.load_from_path` / `get_compute_device_usage_for_mlprogram_operation` / `ComputeUnit.CPU_AND_NE` / `models.utils.compile_model` APIs verified against `/apple/coremltools` via Context7 and by runtime introspection |
| **torch** | **2.12.1** (kept — Phase-4 disposition; soft advisory only, no hard error) |
| **numpy** | 2.4.6 |
| **Compute units (scan scope)** | **`ComputeUnit.CPU_AND_NE`** — the DEC-07 production set (CPU + Neural Engine), **not** `.all` |
| **Model** | `NDT1ANEWithVelocity(seq_len=32)` — the Plan 05-01 `(vx,vy)` graph: NDT1ANE encoder (1,292,544 params, 6 layers, h=2, `d_model=128`, BC1S `(1,96,1,32)`) + 1×1 `Conv2d(96→2)` velocity head on the static last bin; output fp16 `(1,2,1,1)` |
| **Deployment artifact scanned** | the **4-bit k-means palettized** `.mlpackage` (Risk #5 — the shipping artifact, not only the fp16 one) |

---

## Methodology

The proof is the scanner `Decoder/src/ndt1/compute_plan.py` exercised by the slow Mac CI gate
`Decoder/tests/test_ane_compute_plan.py` (`@pytest.mark.slow`), reproducing the meridian
`MLComputePlan` op-scan convention (05-RESEARCH Decision 2):

1. **Build the deployment artifact.** `NDT1ANEWithVelocity(seq_len=32)` →
   `convert_to_mlpackage` (fp16 `mlprogram`, `compute_precision=FLOAT16`, `tanh`-GELU) →
   `palettize_4bit` (k-means, `nbits=4`). Transient packages build under `Decoder/checkpoints/`
   (gitignored), isolated by `tmp_path.name`.
2. **Compile (Risk #4).** `MLComputePlan.load_from_path` requires a compiled `.mlmodelc`, not a raw
   `.mlpackage`. `compiled_model_path` calls `coremltools.models.utils.compile_model(.mlpackage,
   destination_path=…)`, which writes a **persistent** `.mlmodelc` and returns its path. (We do NOT
   use `MLModel(...).get_compiled_model_path`: that path is documented to live only for the lifetime
   of the transient `MLModel` Python object and can be reclaimed before the scan reads it.)
3. **Scan.** `scan_ane_eligibility(compiled, CPU_AND_NE)` loads the plan, walks
   `program.functions["main"].block.operations`, and for every **schedulable** op (device usage not
   `None`) records `{op_type, ane_eligible, supported, preferred, cost}`. Non-schedulable nodes
   (consts, etc.) are excluded from the eligibility denominator. Verdict =
   `all_eligible` (every op ANE-eligible) ∧ `cpu_only_ops == []` (no op pinned CPU-only).
4. **Emit artifacts.** `write_residency_artifacts` writes `runtime_plan.json` (full records +
   verdict) and `residency.txt` (per-op table + summary) into `Decoder/checkpoints/` (gitignored).

Two corroborating slow tests: **(a)** palettized-vs-fp16 **op-eligibility parity** (Risk #5 — the
ANE-eligible op-type set is identical for the 4-bit and fp16 packages, since 4-bit weights are
decompressed for the ANE); **(b)** the **einsum disposition** (Decision 6, below). A fast test pins
`ANE_ATTENTION_EINSUM == "bchq,bkhc->bkhq"`.

---

## Results — per-op verdict (`runtime_plan.json`, gitignored)

| Quantity | Value |
|----------|-------|
| Schedulable ops scanned (`n_schedulable`) | **226** |
| ANE-eligible ops (`neuralEngine ∈ supported`) | **226 / 226** |
| `all_eligible` | ✅ **True** |
| CPU-only ops (`supported == [CPU]`) — the regression | **0** |
| **Verdict** | ✅ **every schedulable op ANE-eligible, zero CPU-only** |

The op mix (226 schedulable ops) is the BC1S Conv2d Transformer + einsum attention + velocity head:
`conv ×39`, `reduce_mean ×24`, `einsum ×24`, `add ×24`, `split ×18`, `sub/square/sqrt/real_div/mul
×12 each`, `transpose ×12`, `softmax ×12`, `gelu ×6`, `concat ×6`, `slice_by_index ×1`. **Every one**
reports `supported = [CPU, NE]` (sample, from `residency.txt`):

```
op_type                  eligible  supported          preferred  cost
ios18.conv               True      CPU,NE             CPU        0.00465178
ios16.reduce_mean        True      CPU,NE             CPU        0.000815818
ios16.einsum             True      CPU,NE             CPU        …
ios18.transpose          True      CPU,NE             CPU        …
ios18.gelu               True      CPU,NE             CPU        …
------------------------------------------------------------------------
ANE-eligible: 226/226 ops; CPU-only: 0; preferred tally (Mac, INFORMATIONAL): {'CPU': 226}
```

### einsum disposition (Decision 6) — the contingency was NOT triggered

coremltools 9.0 lowers the `bchq,bkhc->bkhq` scaled-dot-product einsum to native MIL ops. The scan
detects **60 einsum-derived ops** (`einsum ×24`, `transpose ×12`, `reduce_mean ×24`; matched
robustly to the `ios16.`/`ios18.` opset prefix):

| einsum-derived op | `supported_compute_devices` | CPU-only? |
|-------------------|------------------------------|-----------|
| `ios16.einsum` | `[CPU, NE]` | no |
| `ios18.transpose` | `[CPU, NE]` | no |
| `ios16.reduce_mean` | `[CPU, NE]` | no |

**Every einsum-derived op is ANE-eligible** (supports the Neural Engine). Therefore the Decision-6
arbiter resolves in favor of keeping the existing einsum attention as-is: **Plan 05-02 Task 3 (the
meridian Conv2d + broadcast-mul + `reduce_sum` rewrite of `ANEAttention.forward`) was NOT triggered**
— `Decoder/src/ndt1/attention.py` is byte-identical to its pre-plan state. This is the expected
common case per 05-RESEARCH Decision 6 (`apple/ml-ane-transformers` ships einsum attention *meant* to
lower to ANE ops). Had any einsum op been CPU-only, the gate would have failed loudly with a message
pointing to Task 3.

### palettized ≡ fp16 op-eligibility (Risk #5)

The set of ANE-eligible op types is **identical** for the compiled 4-bit palettized package and the
compiled fp16 package — palettization (which decompresses weights for the ANE) does not change the op
set or its eligibility. Residency is therefore correctly characterized on the **deployment artifact**
(4-bit), not only on the fp16 package.

---

## The eligibility / placement split (load-bearing — the single biggest credibility guard)

There are two distinct claims; this plan proves the first and **deliberately does not assert the
second**:

| Claim | API surface | Device/scale dependent? | Where it is proven |
|-------|-------------|-------------------------|--------------------|
| **ELIGIBILITY** — every op *can* run on ANE (`neuralEngine ∈ supported_compute_devices`) | `MLComputePlan` `.supported_compute_devices` | **No** (compiler property) | **Mac CI gate ✅ (this doc, DEC-06)** |
| **PLACEMENT** — every op *will* run on ANE (`preferred_compute_device == neuralEngine`), 100% residency | `MLComputePlan` `.preferred`; Instruments; Xcode Performance Report | **Yes** (scheduler + scale + chip) | **iPad-M4 HUMAN-UAT (DEC-08, Plan 05)** |

**Why the Mac `preferred` tally is INFORMATIONAL, not a pass/fail input.** The scan's Mac
preferred-device tally is **`{CPU: 226}`** — on this M5 Pro the Core ML scheduler prefers CPU for
**every** op. This is **expected** and does **NOT** fail the gate. Prior art (`meridian-mcp/ane_encoder`)
shows a *small* transformer can be **100% ANE-eligible yet 0% ANE-placed at runtime on Mac**, because
the scheduler keeps small ops on CPU until compute-per-op amortises ANE dispatch (~5–10M params on
Apple Silicon). At **~1.29M params** Cortex NDT1 is below that Mac runtime-placement scale threshold —
the meridian "scale trap" (05-RESEARCH Decision 2, Risk #1). Asserting `preferred == neuralEngine` on
the Mac would therefore **false-fail** a model that is genuinely, fully ANE-*eligible*.

**The honest fallback narrative (Risk #1).** Eligibility is the **hard gate** and is closed here.
Placement is the **device-measured artifact**: the iPad-M4 mobile scheduler is more ANE-eager, so 100%
`preferred == neuralEngine` is *expected* there — but it is *measured*, not assumed. If the iPad also
CPU-places at this scale, the defensible artifact is "fully ANE-**eligible**, with the scheduler's
device choice reported honestly" — which is exactly what this scan already proves on Mac. The scanner
**never** encodes a `preferred == neuralEngine` assertion (enforced by the
`! grep assert.*preferred.*Neural` acceptance check on both `compute_plan.py` and the test). This
mirrors the THREAD-02 / SC#1 device-gating precedent (`03-HUMAN-UAT.md`).

SC#1 (Instruments residency) is intentionally **not closeable on Mac** — that is by design.

---

## Phase-5 hand-off (to Plan 05 — the iPad-M4 placement artifact)

DEC-08 / SC#1 (100% runtime placement) is captured on the connected iPad Pro M4 via the HUMAN-UAT
runbook: an Instruments → Core ML residency trace **and/or** the Xcode `.mlpackage` Performance
Report **and/or** an on-device `MLComputePlan` run, showing `preferred == neuralEngine` for the full
graph, committed as `runtime_plan_ipad.json` + the trace/screenshot. The eligibility verdict in this
doc is the device-independent precondition that makes that placement claim meaningful.

The gitignored evidence this plan regenerates on demand (never committed; only the verdict numbers
above are committed, per the Phase-4 discipline):

- `Decoder/checkpoints/runtime_plan.json` — full per-op records + verdict + einsum disposition.
- `Decoder/checkpoints/residency.txt` — human-readable per-op table + summary line.

---

## Reproduce

```bash
uv sync --project Decoder --extra dev && uv run --project Decoder pytest -q -k compute_plan
```

This rebuilds the `(vx,vy)` `.mlpackage`, palettizes it to 4-bit, compiles it to a `.mlmodelc`,
scans the compute plan scoped to `CPU_AND_NE`, asserts `226/226` ANE-eligible with `0` CPU-only,
records the einsum disposition, and regenerates `runtime_plan.json` + `residency.txt`.

> **Note:** the `--extra dev` flag is mandatory — pytest/numpy/torch/coremltools live in the
> `Decoder` project's optional-dependencies `dev` extra; a bare `uv run … pytest` resolves a
> separate Python and fails with a misleading `ModuleNotFoundError: numpy`.

---
*Phase: 05-ndt1-coreml-deployment-with-ane-residency-verified*
*Plan: 05-02 — DEC-06 ANE op-eligibility*
*Completed: 2026-06-21*
