# Phase 5 DEC-08 Evidence — runtime ANE *placement* (100% residency) of the 4-bit `(vx,vy)` model

**Date:** 2026-06-21 (disposition + staging authored; the iPad-M4 placement capture is the human step at the Plan-05-05 checkpoint — see "Capture status" below)
**Result:** ⏳ **PENDING-iPad-capture** — runtime ANE **placement** (`preferred == neuralEngine`, 100% residency, zero CPU/GPU fallback) is the **iPad Pro M4 device-gated artifact**, staged by `05-HUMAN-UAT.md` and captured by the human at the `checkpoint:human-verify`. The device-independent precondition — ANE **eligibility** — is already **✅ closed on the Mac CI gate** (DEC-06, `05-ane-eligibility-evidence.md`).

> **DEC-08:** "100% ANE runtime placement on a connected iPad Pro M4 — `preferred == neuralEngine` for the full graph, zero CPU/GPU fallback — captured via Instruments → Core ML template **or** the Xcode `.mlpackage` Performance Report **or** an on-device `MLComputePlan` dump, committed as `runtime_plan_ipad.json` + the trace/screenshot." This is the canonical **SC#1** (ANE residency) artifact, and it gates alongside the canonical **SC#4** (`< 2 ms` p99) on the same device.

This is **hardware-gated, manual evidence (D-18)**, mirroring the THREAD-02 / SC#1 device-gating precedent (`03-HUMAN-UAT.md`, `instruments-evidence.md`) and the Phase-1 SC#2 / Phase-2 SC#1 splits. **Instruments → Core ML and the Xcode Performance Report cannot run in CI** — they are GUI profilers that attach to a live process on real Apple Silicon (here, a paired iPad Pro M4). So CI attests the *eligibility* invariant — the always-on `MLComputePlan` op-scan gate (DEC-06, below) — and the per-milestone *placement* capture is the device-measured proof.

---

## The eligibility / placement split (load-bearing — the single biggest credibility guard)

There are **two distinct claims**; DEC-06 proves the first on the Mac and **deliberately does not assert the second**, which is this doc's (pending) iPad-M4 artifact:

| Claim | API surface | Device/scale dependent? | Where it is proven |
|-------|-------------|-------------------------|--------------------|
| **ELIGIBILITY** — every op *can* run on ANE (`neuralEngine ∈ supported_compute_devices`) | `MLComputePlan` `.supported_compute_devices` | **No** (compiler property) | **Mac CI gate ✅** (DEC-06, `05-ane-eligibility-evidence.md` — `226/226` eligible, `0` CPU-only) |
| **PLACEMENT** — every op *will* run on ANE (`preferred == neuralEngine`), 100% residency | `MLComputePlan` `.preferred`; Instruments → Core ML; Xcode Performance Report | **Yes** (scheduler + scale + chip) | **iPad-M4 HUMAN-UAT** (DEC-08 — **this doc, PENDING**, staged by `05-HUMAN-UAT.md`) |

**Why placement is the iPad artifact, not a Mac gate (the scale trap, 05-RESEARCH Decision 2 / Risk #1).** Prior art (`meridian-mcp/ane_encoder`) shows a *small* transformer can be **100% ANE-eligible yet 0% ANE-placed at runtime on Mac**, because the Core ML scheduler keeps small ops on CPU until compute-per-op amortises ANE dispatch (~5–10M params on Apple Silicon). At **~1.29M params** Cortex NDT1 (`NDT1ANEWithVelocity`, 1,292,544 params) is **below** that Mac runtime-placement scale threshold — the meridian "scale trap." This is observed, not hypothetical: Plan 05-02's `MLComputePlan` op-scan reported a Mac `preferred` tally of **`{CPU: 226}`** (every op CPU-preferred on the M5 Pro), and Plan 05-04's in-process Swift bench independently read **`device = CPU`** (p50 ≈ 123 µs / p99 ≈ 139 µs — a CPU latency). Asserting `preferred == neuralEngine` on the Mac would therefore **false-fail** a model that is genuinely, fully ANE-*eligible*. The iPad-M4 mobile scheduler is more ANE-eager, so 100% `preferred == neuralEngine` is *expected* there — but it is **measured on device, not assumed**.

**The honest fallback narrative (Risk #1 — the single biggest credibility risk).** Eligibility is the **hard gate** and is closed (Plan 02). Placement is the **device-measured artifact**. **If the iPad ALSO CPU-places at this scale, the defensible artifact is NOT a fabricated placement** — it is "fully ANE-**eligible** (the Plan-02 Mac CI verdict), with the iPad scheduler's device choice reported honestly as captured in `runtime_plan_ipad.json` / the trace." The Plan-02 scanner *never* encodes a `preferred == neuralEngine` assertion (enforced by the `! grep assert.*preferred.*Neural` acceptance check on both `compute_plan.py` and its test), and this disposition carries the same discipline forward: the runbook records the *observed* placement, whatever it is. Eligibility + an honestly-reported scheduler choice is a credible, reviewer-defensible artifact; a fabricated placement is not.

---

## Where the canonical artifacts live (reviewer checklist)

All committed into this phase dir (`.planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/`) by the human capture per `05-HUMAN-UAT.md`:

| Artifact | Claim | Capture tool | Status |
|----------|-------|--------------|--------|
| `runtime_plan_ipad.json` | DEC-08 / SC#1 — per-op `preferred` device on iPad-M4 (the iPad complement of the Plan-02 Mac `runtime_plan.json`) | on-device `MLComputePlan` (option c) | ⏳ pending |
| Instruments **`.trace`** (e.g. `coreml-residency-ipad.trace`) | DEC-08 / SC#1 — per-op compute-unit lane, every op on the Neural Engine | Instruments → Core ML template (option a) | ⏳ pending |
| Xcode **Performance-Report screenshot** (e.g. `performance-report-ipad.png`) | DEC-08 / SC#1 — alternative to the `.trace`; 100% ANE prediction path | Xcode `.mlpackage` Performance Report (option b) | ⏳ pending |
| `latency_histogram.{json,png}` (on-device annotation) | SC#4 / DEC-11 **canonical** — `< 2 ms` p99 with `device == NeuralEngine` over 10k passes | Plan-04 `CortexDecoderBench` run on-device | ⏳ pending |

The reviewer needs **one** of the placement captures (a/b/c) **plus** `runtime_plan_ipad.json`, and the on-device `latency_histogram` pair. These are the device-measured complements of the already-committed Mac artifacts: the eligibility verdict numbers (`05-ane-eligibility-evidence.md`, `226/226` eligible) and the Mac-corroborating latency number (`05-latency-evidence.md`, `device = CPU`).

---

## Why this is the iPad complement of the Mac eligibility verdict (not a parallel path)

The placement capture is the **device-measured complement of the committed Mac artifacts**, deliberately tied to the same code so the runbook cannot drift (threat T-05-05-02):

- It scans the **same** compiled 4-bit palettized `(vx,vy)` model that the Plan-02 Mac gate proved ANE-**eligible** (`neuralEngine ∈ supported` for all `226` schedulable ops, `0` CPU-only — the einsum `bchq,bkhc->bkhq` lowers to ANE-eligible MIL ops, so the contingency rewrite was not triggered).
- It runs the **same** `CortexDecoderBench` (Plan 04) for the canonical p99 that produced the Mac-corroborating number — `runtime_plan_ipad.json` (iPad) is the device-measured counterpart of `runtime_plan.json` (Mac), and the on-device `latency_histogram` is the canonical counterpart of the Mac-corroborating one.
- The eligibility(Mac CI)/placement(iPad UAT) split is stated identically in this doc and in `05-HUMAN-UAT.md`, so the two halves of the residency story are consistent and independently inspectable.

---

## Capture status (the human step at the Plan-05-05 checkpoint — D-18 precedent)

The **`05-HUMAN-UAT.md` runbook + this disposition doc are the committed deliverable of Plan 05-05.** The `.trace`/screenshot + `runtime_plan_ipad.json` + on-device `latency_histogram` capture is the **human step at the `checkpoint:human-verify`**, exactly as the Phase-1 SC#2, Phase-2 SC#1, and Phase-3 SC#1 hardware evidence were produced on a dedicated profiler session rather than during automated execution. Until then:

- The **eligibility precondition is fully in force every CI run** via `uv run --project Decoder pytest -q -k compute_plan` (DEC-06) — every op of the shipping 4-bit model provably *can* run on the ANE.
- This placement claim **refines** that from "every op *can* run on the ANE" to "every op *does* run on the ANE on the iPad-M4 (or the scheduler's choice is documented honestly)." It does not change the eligibility verdict.

**Status:** ⏳ **PENDING-iPad-capture.** On capture, this doc's Result header moves from PENDING to the recorded verdict (100% ANE placement, OR the honest ANE-eligible-+-documented-scheduler-choice fallback), the artifact-checklist rows move from ⏳ to ✅ with the committed filenames, and `05-HUMAN-UAT.md`'s two `result: [pending]` lines + `## Summary` totals are updated.

---
*Phase: 05-ndt1-coreml-deployment-with-ane-residency-verified*
*Plan: 05-05 — DEC-08 runtime ANE placement (iPad-M4 device-gated) + the eligibility/placement split*
*Authored: 2026-06-21 (disposition + staging; placement capture pending the iPad-M4 HUMAN-UAT)*
