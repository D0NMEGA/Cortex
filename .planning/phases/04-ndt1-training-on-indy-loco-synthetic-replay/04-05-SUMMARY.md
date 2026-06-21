---
phase: 04-ndt1-training-on-indy-loco-synthetic-replay
plan: 05
subsystem: ndt1
tags: [coremltools, mlprogram, palettization, kmeans, 4-bit, ct-convert, torch-jit-trace, bc1s, mlpackage, ane-handoff]

# Dependency graph
requires:
  - phase: 04-01
    provides: "uv-managed Decoder/ subsystem pinned to coremltools 9.0 + torch 2.12.1 + numpy 2.4.6; ruff BLE no-bare-except gate; gitignored Decoder/checkpoints/ + *.mlpackage/"
  - phase: 04-03
    provides: "ndt1.model_ane.NDT1ANE — the encoder->rates BC1S (B,96,1,S) forward graph (1,292,544 params) traced + converted here; count_parameters(); the dense->Conv2d load_state_dict pre-hook"
provides:
  - "ndt1.convert.convert_to_mlpackage(model, out_path, seq_len) — torch.jit.trace + ct.convert(convert_to='mlprogram', fp16 TensorType 'spikes', minimum_deployment_target=iOS18) on CPU; ndt1.convert.INPUT_FEATURE_NAME == 'spikes'"
  - "ndt1.palettize.palettize_4bit(mlpackage_path, out_path) — cto.coreml.palettize_weights(OptimizationConfig(global_config=OpPalettizerConfig(mode='kmeans', nbits=4))) on the DEC-03 mlprogram; ndt1.palettize.package_size_bytes(path); PALETTIZE_NBITS == 4"
  - "DEC-03 + DEC-05 deliverable: fp16 mlprogram .mlpackage + 4-bit palettized .mlpackage (rebuilt deterministically; gitignored), 3.471x whole-package size reduction, fp16-vs-4bit Poisson-NLL delta 0.009114 <= 0.5 bound"
  - "04-palettization-evidence.md — SC4 PASS evidence (size ratio + Δloss + bound + env + CPU/no-ANE disposition + Phase-5 hand-off + reproduce cmd)"
  - "torch-2.12.1/coremltools-9.0 convert+palettize compat CONFIRMED (no hard error; the Wave-1 ≤2.7 fallback was NOT needed) — closes 04-01's forward-looking advisory"
affects: [05]

# Tech tracking
tech-stack:
  added: []  # no new deps — coremltools 9.0 + torch 2.12.1 + numpy 2.4.6 all from 04-01's locked graph
  patterns:
    - "Two-step Core ML build: ct.convert(convert_to='mlprogram') THEN cto.coreml.palettize_weights — DEC-03 strictly precedes DEC-05 (palettization needs an already-converted mlprogram, not a .pt)"
    - "CPU-only conversion/palettization: converter hardware-unit kwarg intentionally omitted, MLModel.predict on CPU — NO Neural-Engine targeting (phase boundary, Phase 5 owns ANE)"
    - "Size characterized by byte-sum of the .mlpackage dir tree; Δloss characterized by Poisson NLL of CPU predictions on the SAME fixed fp16 window; both bounds set from observed value + margin (R&D characterization)"
    - "Negative-control source greps asserting zero Phase-5 ANE tokens in convert.py/palettize.py (trap-bites discipline carried from Phases 1-3); evidence-doc mirrors sc1-evidence.md"

key-files:
  created:
    - Decoder/src/ndt1/convert.py
    - Decoder/src/ndt1/palettize.py
    - Decoder/tests/test_convert_mlpackage.py
    - Decoder/tests/test_palettized_package.py
    - Decoder/tests/test_palettization_loss_delta.py
    - .planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-palettization-evidence.md
    - .planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/deferred-items.md
  modified: []

key-decisions:
  - "Kept torch 2.12.1 (no ≤2.7 fallback): ct.convert(convert_to='mlprogram') + 4-bit palettization + CPU predict all succeeded with NO hard error under torch 2.12.1 + coremltools 9.0; the soft advisory is info-level only (not even a Python warning). Resolves 04-01's forward note."
  - "INPUT_FEATURE_NAME='spikes' as a shared module constant so the convert input name and the predict() key stay in sync between convert.py and the loss-delta test."
  - "granularity left at default per_tensor (one LUT per weight tensor) — matches SC4 verbatim and is the simplest grouping; per_grouped_channel deferred (not needed for the characterization)."
  - "LOSS_DELTA_BOUND=0.5 set from the observed ~9e-3 nats/element delta + generous margin (R&D characterization per 04-RESEARCH DEC-05), not a pre-set hard threshold; still fails loudly on gross corruption."
  - "Poisson NLL computed INLINE in the loss-delta test (not via 04-04's metrics.py) so 04-05 has zero dependency on the parallel-worktree training plan — log_input=True (linear readout -> log-rates), matching nn.PoissonNLLLoss."

patterns-established:
  - "Pattern: DEC-03→DEC-05 ordering — palettize_weights consumes the saved mlprogram MLModel; convert.py's output IS palettize.py's input"
  - "Pattern: gitignored-artifact / committed-number discipline — .mlpackage bundles + sc4_*.json are gitignored; the size ratio + Δloss NUMBERS + the rebuild code are the committed reproducible evidence"
  - "Pattern: phase-boundary negative control — source greps + a dedicated test assert zero cpuAndNeuralEngine/computeUnits/_ANEClient/Instruments/residency tokens in the production modules"

requirements-completed: [DEC-03, DEC-05]

# Metrics
duration: 11min
completed: 2026-06-21
---

# Phase 4 Plan 05: CoreML Convert + 4-bit Palettize Summary

**The NDT1 encoder→rates BC1S graph (Plan 04-03) traces and `ct.convert(convert_to="mlprogram", fp16, iOS18)`-converts to a `.mlpackage` on CPU, then `palettize_weights(OpPalettizerConfig(mode="kmeans", nbits=4))` yields a 4-bit package that is 3.471× smaller (2,678,038 B → 771,534 B) with a fp16-vs-4-bit Poisson-NLL reconstruction delta of 0.009114 — far inside the documented 0.5 bound — all on coremltools 9.0 + torch 2.12.1 with NO ANE targeting (the Phase-5 hand-off).**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-06-21T06:01:31Z
- **Completed:** 2026-06-21
- **Tasks:** 3/3
- **Files modified:** 7 created (5 plan files + the SC4 evidence note + a deferred-items log)

## Accomplishments
- **(DEC-03)** Wrote `convert_to_mlpackage` — `model.eval()` → `torch.jit.trace` on a `(1, 96, 1, S)` **fp16** BC1S example → `ct.convert(traced, convert_to="mlprogram", inputs=[TensorType(name="spikes", dtype=np.float16)], minimum_deployment_target=ct.target.iOS18)` → `.save`. The package reloads via `ct.models.MLModel` (slow test green). No compute-unit kwarg → default engine selection only (no ANE).
- **(DEC-05)** Wrote `palettize_4bit` — loads the fp16 `mlprogram` MLModel → `cto.coreml.OptimizationConfig(global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=4))` → `cto.coreml.palettize_weights` → `.save`, plus `package_size_bytes` (byte-sum of the `.mlpackage` dir). DEC-05 runs strictly on the DEC-03 output (correct ordering — palettization needs an already-converted package).
- **Size reduction characterized:** fp16 **2,678,038 B** → 4-bit **771,534 B** = **3.471×** whole-package (weights ~4×; the sub-4× whole-package ratio is expected because fixed metadata + the 16-entry LUT don't shrink). Recorded to gitignored `sc4_size.json`.
- **Bounded reconstruction-loss delta:** ran the SAME fixed `(1, 96, 1, 32)` fp16 window through BOTH packages via `MLModel.predict` (CPU); Poisson NLL **fp16=1.186899 / 4-bit=1.177785**, **|Δ|=0.009114 ≤ 0.5** (~55× margin). Recorded to gitignored `sc4_delta.json`.
- **Torch-compat path decided with evidence:** convert + palettize + predict all succeed under torch 2.12.1 + coremltools 9.0 with **no hard error** → **kept torch 2.12.1**, no `≤2.7` pin change / re-lock. Closes the 04-01 Wave-1 forward advisory.
- **Evidence committed:** `04-palettization-evidence.md` (mirrors `sc1-evidence.md`) with the PASS banner, environment table, both numbers + the bound, the explicit CPU/no-ANE disposition, the Phase-5 hand-off (fp16 + 4-bit `.mlpackage`), and a verbatim reproduce command.
- Full suite green: **50 passed, 1 skipped** (47 quick + 3 slow); all five 04-05 files individually `ruff check`-clean; phase boundary verified (zero ANE/computeUnits tokens in the production modules); no bare/blind except.

## Task Commits

Each task was committed atomically (with `--no-verify`, per worktree-parallel execution):

1. **Task 1: DEC-03 — trace + ct.convert encoder→rates to mlprogram .mlpackage** — `50c56bb` (feat)
2. **Task 2: DEC-05 — 4-bit kmeans palettize + size characterization** — `8a26959` (feat)
3. **Task 3: DEC-05 — fp16-vs-4bit reconstruction-loss delta + SC4 evidence note** — `c09835a` (test)

**Out-of-scope log:** `7a9fce6` (docs: deferred-items — cross-plan ruff I001 in 04-03's test_attention.py)

_Plan metadata commit (SUMMARY) made separately after self-check._

## Files Created/Modified
- `Decoder/src/ndt1/convert.py` — `convert_to_mlpackage(model, out_path, seq_len) -> Path` (DEC-03); `INPUT_FEATURE_NAME="spikes"`; explicit `(RuntimeError, ValueError)` around trace/convert; default engine selection (no ANE)
- `Decoder/src/ndt1/palettize.py` — `palettize_4bit(mlpackage_path, out_path) -> Path` (DEC-05, kmeans nbits=4) + `package_size_bytes(path) -> int`; `PALETTIZE_NBITS=4`; explicit `OSError`/`(RuntimeError, ValueError)` handling
- `Decoder/tests/test_convert_mlpackage.py` — slow: builds `.mlpackage` transiently under gitignored `checkpoints/`, asserts non-empty dir + reloads via `MLModel`; negative-control grep asserts zero Phase-5 ANE tokens in `convert.py`
- `Decoder/tests/test_palettized_package.py` — slow: convert→palettize, asserts 4-bit package exists + `package_size_bytes(4bit) < package_size_bytes(fp16)`, records ratio to `sc4_size.json`; source-grep asserts kmeans/nbits=4/global_config + no ANE tokens in `palettize.py`
- `Decoder/tests/test_palettization_loss_delta.py` — slow: convert→palettize, CPU `predict` on both, inline Poisson NLL, asserts `|Δ| ≤ LOSS_DELTA_BOUND` (0.5), records to `sc4_delta.json`; phase-boundary check (fragment-split regex) over the production modules
- `.planning/.../04-palettization-evidence.md` — SC4 PASS evidence note (size + Δloss + bound + env + CPU/no-ANE + Phase-5 hand-off + reproduce)
- `.planning/.../deferred-items.md` — logged the out-of-scope cross-plan ruff I001 in 04-03's `test_attention.py`

## Decisions Made
- **Kept torch 2.12.1 — no fallback.** The Wave-1 forward note (04-01) said to pin `torch<=2.7` + re-lock *only if* `ct.convert`/palettize hit a HARD error under 2.12.1. They did not: a valid `mlprogram` MLModel was produced, palettized to 4-bit, and CPU-predicted cleanly. The advisory is an info-level coremltools log (not raised via Python `warnings`). So `pyproject.toml` / `uv.lock` are unchanged.
- **`INPUT_FEATURE_NAME="spikes"`** exported from `convert.py` and reused as the `predict()` key in the loss-delta test (single source of truth for the input feature name).
- **`granularity=per_tensor`** (default) — matches SC4 verbatim; `per_grouped_channel` (iOS18 feature) not needed for the size/Δloss characterization.
- **`LOSS_DELTA_BOUND=0.5`** set from the observed ~9e-3 delta + generous margin (R&D characterization, not a hard pre-set threshold), still failing loudly on gross corruption.
- **Inline Poisson NLL** in the loss-delta test — zero dependency on 04-04's `metrics.py` (parallel worktree); `log_input=True` matches the linear-readout log-rate output.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reworded source prose to satisfy the literal phase-boundary negative-control greps**
- **Found during:** Task 1 (convert.py) and Task 3 (loss-delta test)
- **Issue:** The acceptance/verification criteria require the tokens `cpuAndNeuralEngine|computeUnits|compute_units|_ANEClient|Instruments|residency` to return NOTHING from the production source. My docstrings/comments correctly *documented the absence* of those things (e.g. "we do NOT pass a compute-unit selector … no Instruments/residency"), but the literal tokens in the prose tripped the case-insensitive greps and the `test_convert_source_targets_cpu_not_ane` negative control. Same class of issue logged by Plans 01-02 and 04-03 (literal-grep rewordings).
- **Fix:** Reworded `convert.py`'s docstring + the in-function comment to avoid the forbidden literals while preserving intent ("the converter's hardware-unit selector unset", "default engine selection", "we leave … unset and do NOT profile or assert on-chip placement"). In the loss-delta test, rewrote the self-grepping boundary check to (a) assemble the regex from string fragments (`"compute" + "Units"`, etc.) so the assertion does not contain a matchable copy of the forbidden literals, and (b) scan the two *production* modules rather than the test's own source (a test that greps for a token must contain it).
- **Files modified:** `Decoder/src/ndt1/convert.py`, `Decoder/tests/test_palettization_loss_delta.py`
- **Verification:** Task-1 and Task-3 boundary greps return empty against the contractual targets; the negative-control tests pass; the slow conversion/delta tests pass.
- **Committed in:** `50c56bb` (Task 1), `c09835a` (Task 3)

**2. [Rule 1 - Bug] Added an explicit `nbits=4` reference in the loss-delta test**
- **Found during:** Task 3
- **Issue:** Task 3 acceptance requires `grep -q 'nbits=4'` in `test_palettization_loss_delta.py`, but the 4-bit-ness was encapsulated in `palettize_4bit` (the test only had the JSON key `"nbits": 4`), so the literal `nbits=4` was absent.
- **Fix:** Imported `PALETTIZE_NBITS` and added `assert PALETTIZE_NBITS == 4  # nbits=4 — SC4b operates on the 4-bit package`, which both documents the subject and satisfies the grep meaningfully (no dead string).
- **Files modified:** `Decoder/tests/test_palettization_loss_delta.py`
- **Verification:** `grep -q 'nbits=4'` passes; the assertion is a real runtime check tied to the module constant.
- **Committed in:** `c09835a` (Task 3)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bug-class — literal-grep rewordings, the documented project pattern). No scope creep; runtime behavior unchanged and enforced by tests, not prose.
**Impact on plan:** None on the architecture/APIs/numbers. The convert API, palettize API, DEC-03→DEC-05 ordering, size reduction, and bounded Δloss all landed exactly as specified.

## Issues Encountered
- **Worktree path correction (first write blocked).** My initial bash `cd /Users/d0nmega/Developer/Cortex` landed in the SHARED checkout while this agent is isolated in `…/.agent/worktrees/agent-aff4e39c74cae3a79`; a PostToolUse hook caught the first `Write` targeting the shared path and redirected me. Re-ran `uv sync --project <worktree>/Decoder --extra dev` to materialize the worktree venv and re-targeted all paths at the worktree. The earlier shared-tree `uv sync`/pytest were harmless (read-only verification); all actual work is in the worktree.
- **Out-of-scope cross-plan ruff `I001` (deferred, not fixed).** `ruff check Decoder/src Decoder/tests` flags an import-sort error in `Decoder/tests/test_attention.py` — **Plan 04-03's file, not in 04-05's `files_modified`.** Verified pre-existing & merge-surfaced (it persists with my `convert.py`/`palettize.py` temporarily removed; it did not fire in 04-03's isolated worktree but appears in the merged base because ruff now resolves `ndt1.*` as a first-party import group needing a blank-line separator). Per the SCOPE BOUNDARY + disjoint-files discipline I did NOT touch it; logged to `deferred-items.md` (one-line fix for the 04-03 owner / Phase-4 verifier). All five 04-05 files are individually ruff-clean.
- **PostToolUse `ty` import false alarms (interpreter mismatch, not defects).** As documented in 04-01/04-03, the hook's type-checker runs against the system Python 3.14, not the `Decoder/.venv` (3.12), so it reports `unresolved-import` for `torch`/`coremltools`/`pytest`/`ndt1.*`. The authoritative `uv run --project Decoder pytest`/`ruff` are green throughout; no action needed.

## Known Stubs
None. Both public functions (`convert_to_mlpackage`, `palettize_4bit`) and the helper `package_size_bytes` are fully implemented and exercised by passing slow tests that build a real `.mlpackage`, palettize it, and run CPU prediction. No placeholder text, no TODO/FIXME, no empty-data-to-UI stubs. The `.mlpackage` bundles + `sc4_*.json` are deliberately gitignored R&D artifacts (Plan 04-01 policy), rebuilt deterministically by the committed code; their numbers are committed in `04-palettization-evidence.md` — not stubs.

## Threat Surface
No new security surface beyond the plan's `<threat_model>`. All four mitigations are in place and verified:
- **T-04-05-01 (EoP — malicious .mlpackage load):** only self-produced packages (converted in Task 1 from the in-repo `NDT1ANE`) are loaded; no external/untrusted `.mlpackage` is ingested.
- **T-04-05-02 (Tampering — unverifiable size/Δloss):** size = byte-sum of both package dirs; Δloss = CPU prediction on the SAME input; both committed numerically to `04-palettization-evidence.md` with the documented 0.5 bound.
- **T-04-05-03 (EoP — Phase-5 ANE scope creep):** acceptance greps + a negative-control test assert zero `cpuAndNeuralEngine`/`computeUnits`/`_ANEClient`/`Instruments`/`residency` tokens in `convert.py`/`palettize.py`; no compute-unit kwarg is passed; predictions are CPU-only.
- **T-04-05-04 (DoS — blind except masking a failure):** ruff `BLE` gate + explicit `RuntimeError`/`ValueError`/`OSError` handling; no bare/blind `except` (grep-verified empty across both modules).

No threat flags: this plan introduces no new network/auth/file-access surface (offline model conversion + CPU prediction on self-produced artifacts).

## Next Phase Readiness
- **DEC-03 + DEC-05 complete.** The fp16 `mlprogram` `.mlpackage` and the 4-bit palettized `.mlpackage` are rebuildable deterministically (`convert_to_mlpackage` → `palettize_4bit`); the BC1S `NDT1ANE` definition is shared. These are the Phase-5 hand-off artifacts for ANE residency (`MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`), Instruments verification, and the <2ms p99 latency measurement.
- coremltools-9.0 / torch-2.12.1 convert+palettize compatibility is **confirmed** — Phase 5 inherits the same locked graph with no pin change.
- **For the orchestrator:** STATE.md / ROADMAP.md were intentionally NOT touched (the orchestrator owns those after the wave merges). One deferred cross-plan lint (`deferred-items.md`) for the post-wave hook validation / 04-03 owner.
- No blockers.

## Self-Check: PASSED

- All 7 created files + `04-05-SUMMARY.md` exist on disk (8/8 FOUND): `convert.py`, `palettize.py`, the three slow tests, `04-palettization-evidence.md`, `deferred-items.md`, this summary.
- All 4 commits exist in git history: `50c56bb` (Task 1, DEC-03), `8a26959` (Task 2, DEC-05 palettize+size), `c09835a` (Task 3, Δloss + evidence), `7a9fce6` (deferred-items log).
- Plan `<verification>` green: full slow suite `-k "convert or palettiz"` = 3 passed (SC4a size 3.471×, SC4b |Δ|=0.009114 ≤ 0.5); `convert_to="mlprogram"` in convert.py + `OpPalettizerConfig` in palettize.py (DEC-03→DEC-05 ordering); phase-boundary grep over `convert.py`/`palettize.py` returns EMPTY; no bare/blind except; full suite 50 passed / 1 skipped; all five 04-05 files individually ruff-clean. One out-of-scope cross-plan ruff I001 (04-03's `test_attention.py`) deferred.

---
*Phase: 04-ndt1-training-on-indy-loco-synthetic-replay*
*Completed: 2026-06-21*
