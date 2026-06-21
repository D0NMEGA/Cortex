---
phase: 05-ndt1-coreml-deployment-with-ane-residency-verified
plan: 01
subsystem: decoder
tags: [coreml, coremltools, pytorch, ane, velocity-head, ridge-regression, fp16, dec-10]

# Dependency graph
requires:
  - phase: 04-ndt1-training-on-indy-loco-synthetic-replay
    provides: "NDT1ANE encoder->rates BC1S graph (1,292,544 params), convert.py (torch.jit.trace + ct.convert mlprogram), the dense->conv state-dict pre-hook, the slow-test + checkpoints/ json discipline"
provides:
  - "VelocityHead: 1x1 Conv2d(96->2) + static last-bin slice rates[..., -1:] -> (B,2,1,1) velocity"
  - "ridge_fit: closed-form ridge (XtX+lam*I)^-1 XtY via np.linalg.solve + load_ridge into the conv"
  - "NDT1ANEWithVelocity: composes the encoder with the velocity head; fit_velocity_head on predicted rates"
  - "convert.py emits a fp16 (1,2,1,1) (vx,vy) .mlpackage with explicit compute_precision=FLOAT16 + tanh-GELU"
  - "Frozen output contract for the Swift inference path: spikes (1,96,1,S) fp16 -> velocity (1,2,1,1) fp16"
affects: [05-02 ANE eligibility scan, 05-03 Swift inference path, 05-04 latency bench, 05-05 iPad UAT, Phase 7 ReFIT-Kalman]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Closed-form ridge readout (no training loop) loaded into a 1x1 Conv2d via a load_state_dict pre-hook (mirrors Phase-4 dense->conv)"
    - "Static last-bin slice rates[..., -1:] (NOT dynamic indexing) as the ANE-friendly 'velocity of this window' mechanism"
    - "Composition-over-mutation: NDT1ANEWithVelocity wraps the unchanged NDT1ANE encoder (Phase-4 signature preserved)"
    - "Explicit compute_precision=ct.precision.FLOAT16 in the source (not implicit default) — precision contract is grep-visible"
    - "PyTorch-fp32-vs-CoreML-fp16 parity bound (R&D characterization, observed + margin) mirroring 04-05 LOSS_DELTA_BOUND"

key-files:
  created:
    - Decoder/src/ndt1/velocity_head.py
    - Decoder/tests/test_velocity_head.py
    - Decoder/tests/test_convert_velocity_output.py
    - .planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/05-velocity-head-evidence.md
  modified:
    - Decoder/src/ndt1/model_ane.py
    - Decoder/src/ndt1/convert.py

key-decisions:
  - "Linear ridge readout, NOT Kalman — ReFIT-Kalman is REFIT-01/Phase 7 (Swift, post-CoreML); linear keeps the graph ANE-resident"
  - "Fit the head on the encoder's PREDICTED rates (not ground-truth) to avoid train/serve skew (05-RESEARCH Decision 1)"
  - "Static last-bin slice rates[..., -1:] instead of dynamic indexing — dynamic gathers fall off the ANE"
  - "Set compute_precision=ct.precision.FLOAT16 explicitly even though mlprogram defaults to it — the fp16 contract belongs in the source"
  - "Type NDT1ANEWithVelocity **ndt1_kwargs as int|float (every NDT1ANE param is int|float) rather than object"

patterns-established:
  - "DEC-10 velocity head mechanism: rates -> static last-bin -> 1x1 Conv2d(96->2) -> (vx,vy), ridge-fit weights via state-dict pre-hook"
  - "Conversion-fidelity evidence = committed numbers (R^2, parity delta) + reproduce command; .mlpackage/json stay gitignored"

requirements-completed: [DEC-10]

# Metrics
duration: 13min
completed: 2026-06-21
---

# Phase 5 Plan 01: Velocity readout head (DEC-10) Summary

**Appended a linear `(vx, vy)` velocity readout head (1x1 `Conv2d(96->2)` on the static last 20ms bin, fit by closed-form ridge regression) to the NDT1 encoder so the converted Core ML `.mlpackage` emits a fp16 `(1,2,1,1)` cursor velocity — PyTorch-vs-CoreML parity 0.000367 ≤ 0.5, with explicit `compute_precision=FLOAT16` + tanh-GELU and the Phase-4 phase boundary intact.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-06-21T21:11:17Z
- **Completed:** 2026-06-21T21:24:02Z
- **Tasks:** 3
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments
- `VelocityHead` (`velocity_head.py`): a BC1S-preserving 1x1 `Conv2d(96->2)` on the static last-bin slice `rates[..., -1:]` -> `(B,2,1,1)`; closed-form `ridge_fit` (`np.linalg.solve`) + `load_ridge` via a `load_state_dict` pre-hook mirroring the Phase-4 dense->conv path.
- `NDT1ANEWithVelocity` (`model_ane.py`): composes the unchanged `NDT1ANE` encoder with the velocity head; `fit_velocity_head` ridge-fits on the encoder's PREDICTED rates and returns R^2. tanh-approximate GELU made explicit in `_EncoderLayer.forward` (ANE constraint).
- `convert.py`: explicit `compute_precision=ct.precision.FLOAT16` (fp16 weights+activations); the converted `.mlpackage` output feature is fp16 with exactly 2 elements.
- DEC-10 evidence doc committed (output contract, ridge R^2, parity delta + bound, reproduce command), mirroring `04-palettization-evidence.md`.

## Task Commits

Each task was committed atomically:

1. **Task 1: VelocityHead + closed-form ridge fit + load hook** — `da6f91b` (feat) — TDD (test+impl in one iteration; 5 unit tests + impl)
2. **Task 2: NDT1ANEWithVelocity + tanh-GELU + convert.py fp16** — `9088dab` (feat) — TDD (1 fast + 2 slow tests + impl)
3. **Task 3: 05-velocity-head-evidence.md** — `123231a` (docs)

**Plan metadata:** (this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md) — see final docs commit.

## Files Created/Modified
- `Decoder/src/ndt1/velocity_head.py` (created) — `VelocityHead`, `ridge_fit`, `load_ridge`, `VELOCITY_DIM=2`, `_ridge_to_conv_pre_hook`.
- `Decoder/src/ndt1/model_ane.py` (modified) — added `NDT1ANEWithVelocity` + `fit_velocity_head`; tanh-GELU in `_EncoderLayer.forward`; `NDT1ANE` signature unchanged.
- `Decoder/src/ndt1/convert.py` (modified) — explicit `compute_precision=ct.precision.FLOAT16`.
- `Decoder/tests/test_velocity_head.py` (created) — 5 DEC-10 unit tests (shape, last-bin-only + negative control, ridge closed-form parity, shape-mismatch raise, load + R^2).
- `Decoder/tests/test_convert_velocity_output.py` (created) — `(1,2,1,1)` shape (fast) + fp16-2-element output + PyTorch-vs-CoreML parity (slow).
- `.planning/phases/05-.../05-velocity-head-evidence.md` (created) — committed DEC-10 evidence.

## Decisions Made
- **Linear ridge, not Kalman:** ReFIT-Kalman is REFIT-01/Phase 7 (Swift); a linear readout keeps the converted graph ANE-resident.
- **Fit on predicted rates:** `fit_velocity_head` consumes the encoder's predicted last-bin rates, matching the inference distribution (avoids train/serve skew; Decision 1).
- **Static last-bin slice `rates[..., -1:]`:** dynamic indexing would fall off the ANE; the negative-control test enforces the slice direction.
- **Explicit `compute_precision=FLOAT16`:** `mlprogram` defaults to FLOAT16, but the fp16 contract is set in source so it is grep-visible and cannot silently regress.
- **`**ndt1_kwargs: int | float`** rather than `object` (every `NDT1ANE` constructor param is `int|float`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] convert.py comment leaked the forbidden token `residency`**
- **Found during:** Task 2 (convert.py `compute_precision` edit)
- **Issue:** My explanatory comment for `compute_precision=FLOAT16` contained the word "residency", which is in the Phase-4 boundary negative-control's forbidden token set (`cpuAndNeuralEngine|computeUnits|compute_units|_ANEClient|Instruments|residency`). This broke `test_convert_source_targets_cpu_not_ane`.
- **Fix:** Reworded the comment to avoid `residency` (and the other forbidden tokens) while preserving the fp16/precision-only intent — the documented Phase-4 "literal-grep comment rewording" project pattern.
- **Files modified:** `Decoder/src/ndt1/convert.py`
- **Verification:** forbidden-token scan returns NONE; `test_convert_source_targets_cpu_not_ane` passes.
- **Committed in:** `9088dab` (Task 2 commit)

**2. [Rule 1 - Bug] Test fixture mis-indexed the last-bin assignment**
- **Found during:** Task 1 (GREEN run of `test_load_ridge_reproduces_linear_map_and_records_r2`)
- **Issue:** `rates[..., -1] = x_te` (shape `(N,96,1)` target vs `(N,96)` source) raised a broadcast `RuntimeError` — a bug in my own test fixture, not the impl.
- **Fix:** Assigned into the slice `rates[..., -1:]` with `x_te` reshaped to `(N,96,1,1)`, keeping the height/last-bin singleton dims.
- **Files modified:** `Decoder/tests/test_velocity_head.py`
- **Verification:** the test passes and reproduces `X @ W.T + b` to 1e-4.
- **Committed in:** `da6f91b` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs — one source comment, one test fixture). **Impact:** Both were self-introduced during this plan and corrected inline; no scope change, no architectural impact, no Phase-4 regression.

## Issues Encountered
- The editor's `ty` type-checker hook reports `unresolved-import` for `torch`/`numpy`/`coremltools` (it runs against a bare interpreter, not the uv venv) and an `invalid-argument-type` on `**ndt1_kwargs` forwarding to `NDT1ANE.__init__`. `ty` is NOT a configured project gate (not in the venv, not in `pyproject.toml`, not in CI) — the actual gates are **ruff** (clean) and **pytest** (62 fast + 8 DEC-10 + boundary all green). No action needed beyond the precise `int|float` kwargs annotation already applied.

## Threat Surface
The plan's STRIDE register is fully addressed:
- **T-05-01-01 (Tampering):** parity computed on the SAME fixed fp16 window through both PyTorch fp32 and the converted CoreML model; committed delta (0.000367) + documented bound (0.5) fail loudly on a corrupted conversion — `test_pytorch_vs_coreml_velocity_parity`.
- **T-05-01-02 (Spoofing):** only the in-repo `NDT1ANEWithVelocity` is traced/converted; ridge labels are seeded-synthetic — no untrusted artifact ingested.
- **T-05-01-03 (Info Disclosure / scope creep):** `convert.py` carries zero `cpuAndNeuralEngine`/`computeUnits`/`_ANEClient`/`Instruments`/`residency` tokens; `test_convert_source_targets_cpu_not_ane` still green.
- **T-05-01-04 (DoS / blind except):** ruff clean; zero bare/blind `except` in the touched files (only a specific `ImportError` fallback + explicit `ValueError`/`RuntimeError`).

No new threat surface beyond the register (no new endpoints/auth/file-access; the `.mlpackage` is the same deployment-artifact boundary Phase 4 established).

## No Known Stubs
No stub patterns: the head has a real ridge fit and the conversion emits a real fp16 `(1,2,1,1)` graph. The absolute decode R^2 of the *deployed* head awaits the trained checkpoint + real Indy/Loco velocity labels (Plan 04 pipeline) — this plan characterizes the head mechanism, which is fully wired and tested.

## User Setup Required
None — no external service configuration. (No `user_setup` block in the plan.)

## Next Phase Readiness
- **Ready for 05-02** (ANE eligibility scan via `MLComputePlan`): the with-velocity `.mlpackage` is the graph 05-02 scans for ANE op-eligibility; `compute_precision=FLOAT16` + tanh-GELU (two of the four Decision-2 ANE constraints) are now explicit.
- The frozen `(1,2,1,1)` fp16 output contract is committed for Plans 03/04/05 (Swift `MLModel.prediction`).
- **STATE.md / ROADMAP.md / the `milestone:` field were NOT touched by the task work** (only the final metadata commit updates STATE.md/ROADMAP.md/REQUIREMENTS.md per the workflow; `milestone:` stays `v1.0`).

## Self-Check: PASSED

- All 4 created files + 2 modified files present on disk.
- All 3 task commits found in git history (`da6f91b`, `9088dab`, `123231a`).
- Plan-level verification green: 8 DEC-10 tests + 62 fast-suite tests + Phase-4 boundary test pass; ruff clean.

---
*Phase: 05-ndt1-coreml-deployment-with-ane-residency-verified*
*Completed: 2026-06-21*
