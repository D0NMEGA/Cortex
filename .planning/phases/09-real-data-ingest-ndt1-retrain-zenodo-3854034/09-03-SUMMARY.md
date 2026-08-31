---
status: PASS
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 03
subsystem: decoder
tags: [numpy, kinematics, velocity, ridge, r2, lag, ndt1, pytest, ruff, tdd]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 02
    provides: "load_session's planar_cm and t keys, and the committed tiny_v73.mat fixture"
  - phase: 04-decoder-training
    provides: "ndt1.data.bin_spikes and its BIN_MS / num_bins arithmetic"
  - phase: 05-coreml-ane-deployment
    provides: "ndt1.velocity_head.ridge_fit and VelocityHead's rates[..., -1:] readout geometry"
provides:
  - "ndt1.kinematics.planar_velocity_250hz: finite-difference (x, y) cm -> (vx, vy) cm/s at the native behavior rate, with no smoothing filter (D-07)"
  - "ndt1.kinematics.bin_velocity: mean aggregation onto bin_spikes' exact bin edges, raising on an empty bin rather than emitting a NaN"
  - "ndt1.kinematics.apply_lag: pairs the window ending at bin i with the velocity at bin i + k, dropping the unpaired tail (D-08)"
  - "ndt1.kinematics.heldout_r2: per-axis and pooled R2 against a constant TRAIN-split mean null, unclamped (D-10)"
  - "ndt1.kinematics.lag_sweep_r2: the full 0-160 ms lag curve fit and scored on TRAIN rows only"
  - "ndt1.kinematics.LAG_BINS_SWEEP and BEHAVIOR_HZ"
  - "24 quick tests (25 cases), each discriminating control mutation-verified to bite"
affects: [09-07, 09-06, Phase 10 ReFIT R fit, the shipped velocity .mlpackage]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Row alignment by construction: bin_velocity imports BIN_MS and reuses bin_spikes' floor arithmetic and high-edge clip, so the rates and velocity matrices cannot drift apart by a row"
    - "The null is a required positional argument: heldout_r2 cannot be called without naming which split the mean came from, so the D-10 substitution is a visible edit rather than a default"
    - "Planted-signal recovery as a convention proof: a synthetic 5-bin offset between rates and velocity pins the lag pairing against VelocityHead's static last-bin slice"

key-files:
  created:
    - Decoder/src/ndt1/kinematics.py
    - Decoder/tests/test_kinematics.py
  modified: []

key-decisions:
  - "bin_ms defaults to ndt1.data.BIN_MS rather than a second hardcoded 20.0, so the bin width the labels use and the bin width the spikes use are the same object and cannot drift"
  - "_AXIS_NAMES is a local ('vx', 'vy') constant rather than an import of velocity_head.VELOCITY_DIM, because the plan pins the exact import line 'from ndt1.velocity_head import ridge_fit' and widening that import would break its literal grep"
  - "test_bin_count_matches_bin_spikes is parametrized over a whole-bin span and a partial-bin span; mutation verification proved the whole-bin case alone does not catch a floor-to-ceil drift"
  - "lag_sweep_r2 reuses heldout_r2 for its in-sample score rather than reimplementing the arithmetic, so there is exactly one definition of R2 in the module"

patterns-established:
  - "Mutation verification before claiming a control works: revert the behavior, confirm exactly the intended tests fail, restore byte-identically (git diff empty)"

requirements-completed: [RD-02]

# Metrics
duration: 13min
completed: 2026-08-31
---

# Phase 9 Plan 03: Kinematics Layer and the Held-Out R2 Discipline Summary

**A dataset-free kinematics module that derives 20 ms velocity labels by finite difference at 250 Hz, aligns them to the rates matrix on `bin_spikes`' own bin edges, and scores a readout against a constant TRAIN-split mean null that cannot be silently swapped for the test set's own mean.**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-08-31T05:20:50Z
- **Completed:** 2026-08-31T05:33:23Z
- **Tasks:** 3 of 3
- **Files modified:** 2 (both created)

## Accomplishments

- `ndt1.kinematics` exports `planar_velocity_250hz`, `bin_velocity`, `apply_lag`, `heldout_r2`, `lag_sweep_r2`, `LAG_BINS_SWEEP` and `BEHAVIOR_HZ`, in 332 lines with no file I/O, no session loading and no training loop.
- The velocity derivation is a plain backward finite difference with the undefined first row repeating the second, so the result keeps `t.size` rows and stays index-aligned with both `t` and `planar_cm`. No smoothing filter is applied and the module records in-source why a Savitzky-Golay derivative was rejected.
- `bin_velocity` computes `num_bins` with the identical `floor((t_end - t_start) / bin_s)` arithmetic `bin_spikes` uses, imports `BIN_MS` from `ndt1.data` rather than restating 20.0, and reuses the same high-edge clip. `test_bin_count_matches_bin_spikes` calls both functions and compares, on a whole-bin span and a partial-bin span.
- An empty 20 ms bin raises a `ValueError` naming the bin index and stating how many of the bins are empty, instead of dividing zero by zero. A non-monotone or duplicated behavior timestamp raises naming the offending index and its `dt`.
- `heldout_r2` takes `train_mean` as a required positional argument. It reports `vx`, `vy`, `pooled` and `n`, where pooled is `1 - sum_axes SS_res / sum_axes SS_tot` and not the mean of the per-axis values. Nothing is clamped: a worse-than-null readout returns its true negative magnitude.
- `lag_sweep_r2` returns the whole 9-point curve rather than the argmax, fits through the existing `ridge_fit` unchanged (D-09), and adds no lambda selection logic.
- 24 test functions (25 cases) run in 0.11 s with `Decoder/data/` absent from the worktree entirely. The full quick suite is 121 passed, 1 skipped, 9 deselected; `ruff check Decoder` is clean.

## Task Commits

1. **Task 1: kinematics.py - velocity, 20 ms aggregation, whole-bin lag (TDD)** - `b85ba1b` (test, RED) then `1ce63ef` (feat, GREEN)
2. **Task 2: heldout_r2 against a TRAIN-mean null (TDD)** - `e551963` (test, RED) then `f68b1c9` (feat, GREEN)
3. **Task 3: complete the test module** - `147e339` (test)

No refactor commit: both GREEN implementations were already minimal and no cleanup was warranted.

## Files Created/Modified

- `Decoder/src/ndt1/kinematics.py` (created, 332 lines) - the five functions plus `LAG_BINS_SWEEP` and `BEHAVIOR_HZ`, with a module header documenting the pipeline and the hard rules, and Google-style docstrings carrying explicit `Raises:` sections.
- `Decoder/tests/test_kinematics.py` (created, 376 lines) - 24 quick tests covering the analytic derivation, the bin-edge alignment against `bin_spikes`, the lag pairing convention, the D-10 null discipline, and the end-to-end path over the committed `tiny_v73.mat`.

## Verification

```
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests/test_kinematics.py -q   -> exit 0 (25 passed in 0.11s)
uv run --project Decoder pytest Decoder/tests -m "not slow" -q        -> exit 0 (121 passed, 1 skipped, 9 deselected)
uv run --project Decoder ruff check Decoder                           -> exit 0
```

Both of the plan's inline `python -c` verify blocks print `OK`. Every acceptance grep passes, including the negative controls: no bare or blind `except`, no `savgol` / `gaussian_filter` / `lfilter` / `convolve` call, and no `max(0` or `clip(... 0.0 ... 1.0)` clamping anywhere in the module.

`Decoder/data/` does not exist in this worktree, so the whole suite is proven to run without the dataset (tier split D-21). No task in this plan downloaded anything, trained anything, or asserted a measured number about real data.

Environment for the numbers above: Python 3.12.13, numpy 2.4.6, torch 2.12.1, h5py 3.16.0, ruff 0.15.18, on the M5 Pro. These are test counts and timings, not measurements of decoder behavior.

## Mutation Verification

Following the 09-02 precedent, each discriminating control was proven to bite before being claimed to work. `kinematics.py` was restored with `git checkout` after every mutation and confirmed byte-identical (`git diff` empty) before the next.

| Mutation | Test that failed | Guards |
|---|---|---|
| `ss_tot` recomputed from `y_true.mean(axis=0)` | `test_train_mean_null_differs_from_test_mean_null` (`assert 0.0 > 1e-06`) | D-10, T-09-03-03 |
| `pooled` returned as `per_axis.mean()` | `test_pooled_is_not_the_mean_of_axes` (`assert 0.0 > 1e-06`) | D-10 pooled definition |
| `per_axis` clamped with `np.maximum(..., 0.0)` | `test_worse_than_null_is_negative_and_unclamped` (`assert 0.0 < 0.0`) | D-25, T-09-03-05 |
| `apply_lag` direction reversed | `test_apply_lag_seven_drops_seven_rows` and `test_lag_sweep_recovers_a_planted_lag` | D-08 pairing convention |
| `num_bins` `floor` changed to `ceil` | `test_bin_count_matches_bin_spikes[750]` (`assert 150 == 149`) | row alignment with `bin_spikes` |
| empty-bin guard disabled | `test_bin_with_no_samples_raises`, with a `RuntimeWarning: invalid value encountered in divide` confirming the NaN path | T-09-03-01 |

No control is vacuous. The floor-to-ceil mutation is the reason the bin-count test is parametrized: the 751-sample whole-bin span passed it unchanged, and only the 750-sample partial-bin span caught the one-row drift.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] `bin_ms` defaults to `ndt1.data.BIN_MS` instead of a second literal `20.0`**
- **Found during:** Task 1
- **Issue:** The plan's action text specifies `bin_ms: float = 20.0`. That restates the bin width in a second place, which is exactly the drift the same task's must-have truth guards against ("produces bin counts identical to `bin_spikes` for the same window"). A future edit to `BIN_MS` in `data.py` would silently desynchronize the labels from the rates.
- **Fix:** `from ndt1.data import BIN_MS` and `bin_ms: float = BIN_MS`. The value is unchanged at 20.0, so every call site and every stated behavior is identical; only the source of the constant moved.
- **Files modified:** `Decoder/src/ndt1/kinematics.py`
- **Verification:** `test_bin_count_matches_bin_spikes` calls both binners and compares row counts; mutation 5 above proves it bites on a drift.
- **Committed in:** `1ce63ef`

**2. [Rule 2 - Missing Critical] Five tests added beyond the plan's named list**
- **Found during:** Tasks 1-3
- **Issue:** The plan's Task 1 `<behavior>` block requires `LAG_BINS_SWEEP == (0..8)` and `LAG_BINS_SWEEP[-1] * 20 == 160`, but Task 3's test list has no test for it. Three other stated contracts had the same gap: a duplicated timestamp (`dt == 0`) is a distinct failure mode from a backwards step and only the latter was listed, `bin_velocity`'s `vel`/`t` row-count validation was unlisted, and `heldout_r2`'s three documented shape validations were unlisted.
- **Fix:** Added `test_lag_sweep_constant_spans_zero_to_160_ms`, `test_duplicate_timestamp_raises`, `test_bin_velocity_rejects_mismatched_rows`, `test_heldout_r2_rejects_bad_shapes`, and `test_behavior_hz_is_250`.
- **Files modified:** `Decoder/tests/test_kinematics.py`
- **Verification:** All 24 tests pass; the count exceeds the plan's floor of 15.
- **Committed in:** `b85ba1b`, `e551963`

**3. [Rule 2 - Missing Critical] `test_bin_count_matches_bin_spikes` parametrized over two window spans**
- **Found during:** Task 3 mutation verification
- **Issue:** With a single whole-bin window the test does not distinguish `floor` from `ceil`, so it would have passed against the exact row-alignment defect it exists to catch.
- **Fix:** Parametrized over 751 samples (a 3.0 s span, a whole number of bins) and 750 samples (a 2.996 s span, a dropped partial trailing bin).
- **Files modified:** `Decoder/tests/test_kinematics.py`
- **Verification:** Mutation 5 fails only the `[750]` case, confirming the second parameter is the load-bearing one.
- **Committed in:** `b85ba1b`

### Non-issue deviations

**4. Task 1 and Task 2's RED tests were written into `test_kinematics.py`, which the plan assigns to Task 3.** Both tasks carry `tdd="true"` but their `<files>` lists name only `kinematics.py`, so a literal reading leaves nowhere to put a failing test. `test_kinematics.py` is in the plan's `files_modified`, so each task's RED tests land there and Task 3 closes the module with the end-to-end fixture test. Every Task 3 acceptance criterion holds on the final file.

**5. `_AXIS_NAMES` is a local `("vx", "vy")` constant rather than an import of `velocity_head.VELOCITY_DIM`.** Importing the shared constant would have required `from ndt1.velocity_head import VELOCITY_DIM, ridge_fit`, which does not contain the substring the plan's acceptance criterion greps for (`from ndt1.velocity_head import ridge_fit`). The local tuple serves double duty as the axis width for the shape checks and as the result-dict keys, so the two cannot disagree.

**6. The RED commit `b85ba1b` carries one transient ruff `I001`.** Ruff classifies `ndt1.kinematics` as first-party only once the file exists on disk, so during RED it sorted the import into the third-party block. Its `--fix` output was discarded in favor of the repo's existing idiom; the classification and the lint both resolve in the GREEN commit. `ruff check Decoder` exits 0 at HEAD.

---

**Total deviations:** 3 auto-fixed (all closing coverage the plan's own must-haves demand) plus 3 documented non-issues. No scope creep, no new dependency, and no change to any file outside this plan's `files_modified`.

## Issues Encountered

None blocking. Two notes:

The `ty` checker reports `unresolved-import` for `pytest`, `ndt1.data` and `ndt1.kinematics` on every edit under `Decoder/`, because the ambient checker does not see `Decoder/.venv`. This is the pre-existing, repo-wide tooling gap Plan 09-02 already logged to `deferred-items.md`; it reproduces on files this plan never touched, and both gates that actually run (`ruff check Decoder` and the quick pytest run) exit 0. Not re-logged, to avoid duplicating an item another plan already owns.

No out-of-scope discoveries were made, so no `deferred-items-09-03.md` was created.

## Known Stubs

None. Every function is fully implemented and exercised. `kinematics.py` contains no hardcoded empty value, placeholder string, `TODO` or `FIXME`, and no unwired data path. The only fabricated values in this plan live inside test inputs (hand-built ramps, seeded normal draws and the planted-lag construction), and none is presented as a measurement.

## User Setup Required

None.

## Next Phase Readiness

- Plan 09-07's runner can be a thin composition over these five functions: `load_session` to `planar_velocity_250hz` to `bin_velocity` to `chronological_split` to `lag_sweep_r2` on the train split to `apply_lag` at the locked lag to `ridge_fit` to `heldout_r2` on the tail. No inline math is left for it to reimplement.
- `lag_sweep_r2` returns the full curve in a JSON-ready shape (`lag_bins`, `lag_ms`, `train_r2`, `lambda`), so D-08's published sweep and the evidence artifact's table can be serialized straight from it.
- The lambda sweep D-09 leaves to the caller is a loop over `lag_sweep_r2(..., lam=...)`; no change to this module is needed for it.
- Nothing here has seen a real session. The functions are proven on hand-built analytic inputs and on the synthetic-value fixture, and the first real numbers are Plan 09-07's to measure and label.
- If the selected lag lands far outside 5-8 bins, `LAG_BINS_SWEEP`'s in-source comment records the correct reading: treat it as evidence that the alignment or the sign is wrong, not as a discovery.

## Self-Check: PASSED

Files claimed created, verified present on disk and tracked:
- `Decoder/src/ndt1/kinematics.py` FOUND (332 lines)
- `Decoder/tests/test_kinematics.py` FOUND (376 lines)

Commits claimed, verified in `git log b789fb1..HEAD`:
- `b85ba1b` FOUND, `1ce63ef` FOUND, `e551963` FOUND, `f68b1c9` FOUND, `147e339` FOUND

Exports verified by import at runtime: `planar_velocity_250hz`, `bin_velocity`, `apply_lag`, `heldout_r2`, `lag_sweep_r2`, `LAG_BINS_SWEEP` all present; `LAG_BINS_SWEEP == (0, 1, 2, 3, 4, 5, 6, 7, 8)` and `BEHAVIOR_HZ == 250.0`.

Working tree clean for `kinematics.py` after the final mutation restore, confirmed byte-identical to its committed state.

Files this plan did NOT touch, as required by the parallel-agent file discipline: `Decoder/manifests/indy_sessions.json` (09-05), `Decoder/src/ndt1/qc.py` and `Decoder/src/ndt1/sessions.py` (09-04), and the shared `deferred-items.md`.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-08-31*
