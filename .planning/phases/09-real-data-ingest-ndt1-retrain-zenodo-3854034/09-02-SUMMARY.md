---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 02
subsystem: testing
tags: [h5py, hdf5, matlab-v73, numpy, pytest, ruff, fixtures, indy, ndt1]

# Dependency graph
requires:
  - phase: 04-decoder-training
    provides: "ndt1.data.load_session, bin_spikes, the 96-channel width contract, and the Indy session manifest"
provides:
  - "Decoder/tests/fixtures/tiny_v73.mat: a committed 413 KB synthetic-value, real-structure MATLAB v7.3 file, byte-reproducible from its generator"
  - "Decoder/scripts/make_tiny_v73.py: seeded generator emitting the clean fixture plus the no_matlab_empty, width_192, inflated_10x and finger6 variants"
  - "load_session skips MATLAB_empty cells instead of appending their dimension payload as timestamps"
  - "load_session names the chan_names-derived width (96 or 192) in its ValueError instead of the unit count"
  - "load_session returns planar_cm: sign-corrected (x, y) cm kinematics from finger_pos rows 1-2, for both (3, k) and (6, k) sessions"
  - "11 quick fixture tests, each mutation-verified to fail when its fix is reverted"
affects: [09-03, 09-04, 09-05, real-data ingest, NDT1 retrain, velocity head refit, Phase 10 ReFIT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Synthetic-value/real-structure CI fixture: fabricated numbers inside a genuine MATLAB v7.3 HDF5 container, so CI exercises the real parse path with no dataset redistribution"
    - "Generator-side ground truth: the fixture generator writes a <stem>.truth.json sidecar, so tests assert against what was written rather than against a reimplementation of the loader"
    - "Every correctness assertion carries a negative control that is mutation-verified to bite"

key-files:
  created:
    - Decoder/scripts/make_tiny_v73.py
    - Decoder/tests/fixtures/tiny_v73.mat
    - Decoder/tests/fixtures/tiny_v73.truth.json
    - Decoder/tests/test_fixture_v73.py
  modified:
    - Decoder/src/ndt1/data.py
    - .gitignore

key-decisions:
  - "The fixture clock starts at exactly 0.0 s, which is what makes the C-05 control bite: the spurious 0.0/1.0 timestamps an empty-cell bug injects only land inside the window when the clock starts near zero, which is why the real indy_20160630_01 (t0 = 148.984 s) hides the defect"
  - "Ground truth lives in a committed .truth.json written by the generator, not recomputed in the test, so the count assertions are independent of the loader they check"
  - "n_samples is 2501, not the plan's 2500: at 250 Hz from 0.0, 2500 samples span 9.996 s and yield 499 bins, missing the plan's stated 10.0 s / 500 bins by one"
  - "MATLAB_class is set on each variable rather than on the root group, because that is where real MATLAB v7.3 writes it"
  - "planar_cm and t are added to load_session's return dict; no existing key is renamed or removed, so every Phase 4-8 caller is unaffected"

patterns-established:
  - "Mutation verification: before claiming a control works, revert the fix, confirm exactly the intended tests fail, and restore byte-identically"
  - "Fixture reproducibility: the committed .mat regenerates byte-for-byte from a fixed seed and a fixed header timestamp"

requirements-completed: [RD-02]

# Metrics
duration: 15min
completed: 2026-08-31
---

# Phase 9 Plan 02: Tiny v7.3 Fixture and load_session Correctness Summary

**A committed 413 KB MATLAB v7.3 fixture that pins three silent-corruption defects in `load_session` - truthy `MATLAB_empty` cells, a width error reporting the unit count, and a planar pair taken from the wrong `finger_pos` rows - each fixed and each guarded by a mutation-verified negative control.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-08-31T05:00:00Z (approximate; first task commit at 05:06:45Z)
- **Completed:** 2026-08-31T05:14:16Z
- **Tasks:** 3 of 3
- **Files modified:** 6 (4 created, 2 modified)

## Accomplishments

- `Decoder/tests/fixtures/tiny_v73.mat` is committed and tracked despite `Decoder/**/*.mat`, is 413,032 bytes, opens as a genuine MATLAB v7.3 file (first 16 bytes are the `MATLAB 7.3 MAT-f` magic in a 512-byte userblock), and regenerates byte-for-byte from its generator.
- The fixture reproduces the exact structure the defects hide in: `spikes` is `(5, 96)` as h5py sees it, 300 of its 480 cells are `MATLAB_empty` across all 96 channels using both the `0x0` and `0x1` payload shapes, 6 channels are fully dead, the clock starts at exactly 0.0 s and spans 10.0 s at 250 Hz for exactly 500 bins, and `finger_pos` row 0 is a near-constant depth axis (std 0.0020 cm) against planar rows at std 2.10 and 2.12 cm.
- Firing rates land inside the band Plan 09-04 pins: 13.54 Hz mean per live channel (12,185 timestamps over 90 channels in 10 s), with no 20 ms bin exceeding 5 counts.
- `load_session` now discriminates empty cells on the `MATLAB_empty` attribute. On the fixture this removes 600 spurious timestamps: the loader returned 12,785 counts before and returns exactly the 12,185 the generator wrote, with bin 0 dropping from 470 to the correct 20.
- A 192-channel M1+S1 structure now raises `ValueError` naming `chan_names declares 192 channels` instead of the old "yielded 3 channels", which reported the unit count.
- `load_session` returns `planar_cm`, the `(n_samples, 2)` sign-corrected `(x, y)` kinematics from `finger_pos` rows 1-2, validated for shape and sample count against `t` first, and verified for both `(3, k)` and `(6, k)` row layouts.
- 11 quick tests run in 0.23 s with `Decoder/data/` absent entirely. The full quick suite is 83 passed, 1 skipped, 9 deselected; `ruff check Decoder` is clean.

## Task Commits

1. **Task 1: Generate and commit the tiny v7.3 fixture (D-20)** - `eb66745` (chore)
2. **Task 2: Fix load_session (TDD)** - `b7a3c5c` (test, RED) then `3342a60` (fix, GREEN)
3. **Task 3: Fixture test module** - `5d6c85e` (test)

No refactor commit: the Task 2 changes were already minimal and no cleanup was warranted.

## Files Created/Modified

- `Decoder/scripts/make_tiny_v73.py` (created, 368 lines) - seeded (`default_rng(0)`) generator for the fixture and its four negative-control variants, writing a real MAT userblock, a `#refs#` payload group, MATLAB-style empty cells and `MATLAB_class` attributes.
- `Decoder/tests/fixtures/tiny_v73.mat` (created, 413,032 bytes) - the committed fixture.
- `Decoder/tests/fixtures/tiny_v73.truth.json` (created) - generator-side ground truth: 12,185 real timestamps, 20 in bin 0, 300 empty cells, 500 bins, `t_start` 0.0, `t_end` 10.0.
- `Decoder/tests/test_fixture_v73.py` (created, 257 lines) - 11 tests covering RD-02a/b/c plus the P10 windowing controls and the T-04-02-02 `wf` guard.
- `Decoder/src/ndt1/data.py` (modified, +79/-12) - the three fixes plus the amended module and `load_session` docstrings.
- `.gitignore` (modified, +2) - one negation re-including the fixture. `Decoder/data/` is untouched.

## Decisions Made

- **Ground truth is a committed sidecar, not a test-side recomputation.** Task 3 offered either a sidecar JSON or a `dict[str, int]` return, while Task 1 pinned `build_fixture(...) -> Path`. Writing `<stem>.truth.json` satisfies both: the signature stays `-> Path`, and the count assertions compare against what the generator recorded writing rather than against a reimplementation of the loader they are testing.
- **The 0.0 s clock start is load-bearing and deliberate.** It is the single property that makes the C-05 control bite at all.
- **The transpose heuristic was left completely untouched.** Research verified it correct; `test_channel_axis_transpose_is_correct` pins that behavior rather than changing it, and it was the one test that passed during the RED run.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `n_samples` corrected from 2500 to 2501**
- **Found during:** Task 1
- **Issue:** The plan specified "Use `n_samples = 2500` (10.0 s -> 500 bins at 20 ms)". At 250 Hz starting from 0.0, 2500 samples span `[0.0, 9.996]`, giving `floor(9.996 / 0.02) = 499` bins - not the 10.0 s or the 500 bins the same sentence requires.
- **Fix:** Used 2501 samples, which spans exactly `[0.0, 10.0]` and yields exactly 500 bins, honoring the stated intent.
- **Files modified:** `Decoder/scripts/make_tiny_v73.py`
- **Verification:** `t_end` is exactly 10.0 and `binned.shape == (500, 96)`; `test_trailing_partial_bin_is_clipped_into_the_last_bin` cross-checks against `int(np.floor((t_end - t_start) / 0.020))`.
- **Committed in:** `eb66745`

**2. [Rule 2 - Missing Critical] Added a `finger6` variant to cover the `(6, k)` layout**
- **Found during:** Task 3
- **Issue:** The plan's must-have truths require the planar extraction to hold "for both k x 3 and k x 6 sessions", but the four specified variants and the Task 3 test list only ever exercise a `(3, k)` `finger_pos`. The real Indy files are `(6, k)`, so the layout the fix will actually meet in Phase 9 was untested.
- **Fix:** Added a fifth generator variant and `test_six_row_finger_pos_uses_the_same_planar_rows`, asserting the extra azimuth/elevation/roll rows do not shift the planar indices.
- **Files modified:** `Decoder/scripts/make_tiny_v73.py`, `Decoder/tests/test_fixture_v73.py`
- **Verification:** The test passes, and mutation 2 below fails it alongside the two `(3, k)` tests.
- **Committed in:** `eb66745`, `5d6c85e`

**3. [Rule 1 - Bug] `MATLAB_class` written on variables, not on the root group**
- **Found during:** Task 1
- **Issue:** The plan says to "set `f.attrs["MATLAB_class"]` where MATLAB would". Real MATLAB v7.3 writes no `MATLAB_class` on the root group; it writes one per variable. Fabricating a root attribute would make the fixture less faithful to a real file, which is the fixture's entire value.
- **Fix:** `MATLAB_class` is set on `spikes`, `wf`, `chan_names` (`cell`), `t` and `finger_pos` (`double`), and on every `#refs#` payload (`double` or `char`), matching real MATLAB.
- **Files modified:** `Decoder/scripts/make_tiny_v73.py`
- **Verification:** The loader's `MATLAB_empty` discriminator reads these attributes and all fixture tests pass; no acceptance criterion covers root attributes.
- **Committed in:** `eb66745`

### Non-issue deviations

**4. The 480 `wf` cells share one payload dataset.** The plan asked for "a `(5, 96)` object-reference array of small dummy datasets". Pointing all 480 references at a single payload keeps the committed file at 413 KB rather than roughly 650 KB, and the guard is unaffected: the loader can no more open a shared reference than a per-cell one. `test_wf_is_never_opened` still asserts the array exists, that no returned key derives from it, and that `data.py`'s source contains no `f["wf"]` subscript.

**5. `Decoder/tests/fixtures/tiny_v73.truth.json` is a committed file not listed in the plan's `files_modified`.** It is the sidecar Task 3 explicitly sanctions; see Decisions Made.

**6. The plan cited `test_download_integrity.py` as the `importlib` precedent to mirror; that file does not exist in the repo.** The nearest analogue, `test_manifest.py`, reads its manifest by plain `Path` and imports nothing. The `importlib.util.spec_from_file_location` approach the plan describes was implemented directly.

---

**Total deviations:** 3 auto-fixed (2 bugs in the plan text, 1 missing critical coverage) plus 3 documented non-issues.
**Impact on plan:** No scope creep. Every deviation either corrects arithmetic in the plan or closes coverage the plan's own must-haves demand.

## Issues Encountered

**The plan's `git check-ignore -v ... exits nonzero` criterion is not achievable as written.** With `-v`, git reports the matching *negative* pattern and exits 0; the exit code only distinguishes ignored from not-ignored when `-v` is omitted. Verified the underlying intent three independent ways instead:

```
git check-ignore -q Decoder/tests/fixtures/tiny_v73.mat   -> exit 1 (NOT ignored, correct)
git check-ignore -q Decoder/tests/fixtures/other.mat      -> exit 0 (a sibling .mat is STILL ignored)
git ls-files --error-unmatch Decoder/tests/fixtures/tiny_v73.mat -> tracked
```

`Decoder/data/` remains ignored by its own unchanged rule, so the 1.77 GB dataset cannot be committed.

**Mutation verification of the negative controls.** Rather than assert the controls work, each fix was reverted in turn and the suite re-run, restoring `data.py` byte-identically after each (confirmed by an empty `git diff`):

| Mutation | Tests that failed | Expected |
|---|---|---|
| Remove the `MATLAB_empty` guard | `test_empty_cells_contribute_no_counts`, `test_matlab_empty_attribute_is_the_discriminator` | RD-02a, both |
| `finger[0:2]` instead of `finger[1:3]` | the three `finger_pos` tests | RD-02c, all |
| Drop `chan_names` from the width message | `test_192_channel_session_raises_naming_the_true_width` | RD-02b |

No control is vacuous.

## Deferred Items

One item, logged to `deferred-items.md` and NOT fixed: `ty` reports `unresolved-import` for `h5py`, `torch`, `pytest` and `ndt1.*` on every file under `Decoder/`, because the ambient checker does not see `Decoder/.venv`. Reproduced on `Decoder/tests/test_data.py` and `Decoder/src/ndt1/data.py`, which this plan did not touch, so it is pre-existing and repo-wide. It is a tool-configuration gap, not a code defect: `ruff check Decoder` and the quick pytest run both exit 0. Deferred because no plan in this phase owns the Python tooling configuration.

This single deferred item is why `status` is `PARTIAL` rather than `PASS`. All three plan tasks are complete, committed, and green; nothing in 09-02's own scope is outstanding.

## Known Stubs

None. No hardcoded empty value, placeholder string, or unwired data path was introduced. `Decoder/scripts/make_tiny_v73.py` produces fabricated *values*, which is the fixture's stated design (D-20), and every number it produces is confined to the test fixture. It is never presented as a measurement: the only numbers this plan reports about real data are the counts recorded in 09-RESEARCH, cited as research findings.

## Verification

```
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests -m "not slow" -q   -> exit 0 (83 passed, 1 skipped, 9 deselected)
uv run --project Decoder ruff check Decoder                      -> exit 0
git check-ignore -q Decoder/tests/fixtures/tiny_v73.mat          -> exit 1 (not ignored)
```

Everything runs with `Decoder/data/` absent. No task downloaded, trained, or asserted a measured number.

## User Setup Required

None.

## Next Phase Readiness

- `load_session` now returns `planar_cm` and `t`, which is the input D-05's velocity readout and the Phase 10 ReFIT refit both need. Additive only; no Phase 4-8 caller is affected.
- The `inflated_10x` variant is generated but not asserted here. RD-02d (the firing-rate band control) is Plan 09-04's, and that plan can build the variant with `build_fixture(path, variant="inflated_10x")` and read its expected counts from the sidecar.
- The width fix means a 192-channel session now fails with an operator-readable message, which RD-02e's per-session channel-yield table depends on to populate its excluded list with a measured width.
- Unblocked but untouched: no real session has been loaded yet. Every number in this summary is from the synthetic fixture and is labeled as such.

## Self-Check: PASSED

Files claimed created, verified present:
- `Decoder/scripts/make_tiny_v73.py` FOUND
- `Decoder/tests/fixtures/tiny_v73.mat` FOUND (413,032 bytes, tracked)
- `Decoder/tests/fixtures/tiny_v73.truth.json` FOUND
- `Decoder/tests/test_fixture_v73.py` FOUND

Commits claimed, verified in `git log`:
- `eb66745` FOUND, `b7a3c5c` FOUND, `3342a60` FOUND, `5d6c85e` FOUND

Working tree clean after the final regeneration check; the regenerated fixture is byte-identical to the committed one.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-08-31*
