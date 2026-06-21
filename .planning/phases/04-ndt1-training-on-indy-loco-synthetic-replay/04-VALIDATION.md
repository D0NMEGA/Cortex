---
phase: 4
slug: ndt1-training-on-indy-loco-synthetic-replay
status: draft
nyquist_compliant: true
wave_0_complete: false  # Wave 0 (04-01) installs pytest/env; flips true at execution
created: 2026-06-21
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Derived from `04-RESEARCH.md` § Validation Architecture. Per-task IDs are bound by the planner; this contract fixes the framework, sampling cadence, and the SC→assertion map.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `pytest` (project standard per AGENTS.md) — **installed in Wave 0** (no Python env exists yet) |
| **Config file** | `Decoder/pyproject.toml` — created Wave 0 (new top-level Python subsystem; Python pinned 3.11/3.12 via `uv`) |
| **Quick run command** | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` |
| **Full suite command** | `uv run --project Decoder pytest Decoder/tests -q` |
| **Estimated runtime** | quick ~10–20 s (structural/param/BC1S asserts, no training); full ~minutes (excludes the long evidence training run, which is a committed artifact) |

> **Hardware-gating (mirrors Phase 2 D-18):** every Phase-4 assertion runs on **any Mac CPU** — there is **no M4/ANE-gated claim** this phase (that starts Phase 5). CI runs the cheap structural asserts; the full training-convergence + palettization-characterization numbers are **committed evidence artifacts** with a short-budget CI smoke.

---

## Sampling Rate

- **After every task commit:** Run quick command (structural/param/BC1S asserts).
- **After every plan wave:** Run full suite.
- **Before `/gsd-verify-work`:** Full suite green; SC2 evidence run + SC4 palettization characterization committed.
- **Max feedback latency:** ~20 s (quick).

---

## Per-Task Verification Map

> Skeleton mapping SC → assertion. Planner binds each row to a concrete task ID (`04-PP-TT`) and `<automated>` command.

| SC | Requirement | Secure Behavior | Test Type | Automated Command (shape) | Notes | Status |
|----|-------------|-----------------|-----------|---------------------------|-------|--------|
| 1a | DEC-01 | N/A (local R&D) | unit | `pytest -k test_architecture_structural` | **`num_layers==6`, `d_model==128`, every attention `num_heads ∈ {1,2}`, bin=20ms** — head-count asserted DIRECTLY (param count is invariant to heads) | bound: 04-03 Task 2 |
| 1b | DEC-01 | N/A | unit | `pytest -k test_param_count` | `1.0e6 ≤ sum(p.numel()) ≤ 1.6e6` guardrail (catches layer/dim/FFN drift) | bound: 04-03 Task 2 |
| 2 | DEC-02 | N/A | integration (slow) | `pytest -m slow -k test_heldout_cobps` | held-out masked Poisson NLL / co-bps beats mean-rate null by documented margin; loss curve committed | bound: 04-04 Task 3 |
| 3a | DEC-04 | N/A | unit | `pytest -k test_bc1s_activations` | forward-hook all activations on `(1,96,1,S)` dummy → assert **all rank-4 with `shape[2]==1`**; **negative control** `(B,S,C)` variant must fail | bound: 04-03 Task 3 |
| 3b | DEC-04 | N/A | unit | `pytest -k test_no_linear_on_inference_path` | inference module tree has **zero `nn.Linear`** (all `nn.Conv2d`); attention uses `bchq,bkhc->bkhq` einsum | bound: 04-03 Task 3 |
| 4a | DEC-03, DEC-05 | N/A | integration | `pytest -k test_palettized_package` | `.mlpackage` converts (DEC-03) + palettizes (DEC-05) + exists + is smaller; record size ratio | bound: 04-05 Task 1+2 |
| 4b | DEC-05 | N/A | integration | `pytest -k test_palettization_loss_delta` | `Δ(NLL/co-bps)` fp16 vs 4-bit ≤ documented bound (CPU prediction via coremltools) | bound: 04-05 Task 3 |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `Decoder/pyproject.toml` + `uv.lock` — pinned Python 3.11/3.12, deps (`torch`, `coremltools>=8`, `numpy`, `h5py`, `pytest`)
- [ ] `Decoder/tests/conftest.py` — shared fixtures (tiny synthetic 96-ch spike tensor; dummy `(1,96,1,S)` input; seeded RNG)
- [ ] `pytest` install (no framework present) + `ruff` config
- [ ] `.gitignore` entries for `.mat` data, checkpoints, `.mlpackage` artifacts

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full training-to-convergence run (vs CI short-budget smoke) | DEC-02 / SC2 | Long-running; produces the committed loss-curve evidence artifact, not a CI gate | Run full training config; commit `04-training-evidence.md` + loss curve + held-out co-bps JSON (mirrors `sc2-evidence.md` discipline) |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (Python env + pytest are MISSING — Wave 0 installs)
- [ ] No watch-mode flags
- [ ] Feedback latency < 20 s (quick)
- [ ] `nyquist_compliant: true` set in frontmatter (planner sets after binding task IDs)

**Approval:** task IDs bound by planner (04-01..04-05); nyquist_compliant=true. Execution flips Wave-0 + statuses to green.
