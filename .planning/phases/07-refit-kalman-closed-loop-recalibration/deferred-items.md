# Phase 07 — Deferred / Out-of-Scope Discoveries

Items found during execution that are NOT caused by this phase's changes (per the executor SCOPE
BOUNDARY rule) — logged, not fixed.

## Plan 07-01

### Pre-existing, environment-dependent: `test_ane_compute_plan.py` CoreML-compile failures

- **Discovered during:** Plan 07-01, Task 1 (the PostToolUse hook runs the full Decoder pytest suite).
- **Symptom:** `Decoder/tests/test_ane_compute_plan.py::test_palettized_op_eligibility_matches_fp16`
  (and sibling `test_*_ane_eligible` tests) fail with a `RuntimeError` raised at
  `Decoder/src/ndt1/compute_plan.py:90` inside `ct.models.utils.compile_model(...)` — the CoreML
  `.mlpackage → .mlmodelc` compile for the on-device `MLComputePlan` ANE-eligibility analysis.
- **Why out of scope:** these are Phase-5 (DEC-06/08) ANE compute-plan tests. Plan 07-01 touches
  ONLY `Decoder/pyproject.toml` (added `scipy>=1.11`), `Decoder/src/ndt1/kalman_gain.py`,
  `Decoder/scripts/fit_kalman_gain.py`, and `Decoder/tests/test_kalman_gain.py`. `compute_plan.py`
  is untouched (`git diff --name-only HEAD -- src/ndt1/compute_plan.py` is empty). The failure
  reproduces against the pre-existing tree and is an environmental CoreML-compiler issue in this
  worktree, not a regression from the scipy add (coremltools stayed pinned at 9.0 — verified by the
  unchanged `coremltools>=8.0` spec criterion).
- **Action:** none taken (do NOT fix per SCOPE BOUNDARY). The plan's own acceptance gate
  (`uv run --project Decoder --extra dev pytest Decoder/tests/test_kalman_gain.py -x`) is green.
  These ANE tests are device/runtime-gated per the project's CoreML scale-trap + device-checkpoint
  culture; their canonical evidence is the iPad-M4 run, not this worktree's CoreML compiler.
