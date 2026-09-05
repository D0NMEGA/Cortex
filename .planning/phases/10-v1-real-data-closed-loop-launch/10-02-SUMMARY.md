---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 02
subsystem: database
tags: [numpy, h5py, binary-format, provenance, indy, target-pos, export, asvs-v5, asvs-v12]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: load_session's finger_pos contract, the kinematics layer (planar_velocity_250hz, bin_velocity, apply_lag), the checksum-pinned manifest, the two real checkpoints and their digests
  - phase: 10-v1-real-data-closed-loop-launch
    provides: 10-PREREGISTRATION section 3 (the cursor_bbox_square workspace box), section 11 (the sidecar key list) and section 12 (the verbatim open-loop disclosure)
provides:
  - load_session returns target_mm (last-sample-per-bin) and target_distinct, with a membership guard armed on every load
  - SessionLoad carries target_mm and target_distinct with no default
  - ndt1.replay_export - the D-06 424-byte record format, its sidecar schema, the writer, the validating reader and workspace_from_cursor
  - Decoder/scripts/export_replay.py, the committed materializer, plus the materialized real indy_20160630_01 export (73,160 bins, gitignored)
  - Decoder/tests/fixtures/tiny_replay.{bin,json}, a committed 256-bin synthetic export so CI covers the format with no dataset
affects: [10-03, 10-04, 10-05, 10-06, 10-07, 10-08, 10-09, 10-10, rd-08-replay, daemon-real-spike-source]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One module owns a binary format in both directions, and is the only writer and only Python reader of it"
    - "Declared shape is bounded against the file's actual byte length before any allocation (ASVS V5)"
    - "The sidecar is written LAST, after the binary is digested, so an interrupted write has no sidecar to be read as valid"
    - "A committed synthetic fixture written through the SAME writer as the real path, disclosed as synthetic in its own sidecar"
    - "Aggregation rules differ per array and the forbidden one is named in the docstring with its failure mode"

key-files:
  created:
    - Decoder/src/ndt1/replay_export.py
    - Decoder/scripts/export_replay.py
    - Decoder/scripts/make_tiny_replay.py
    - Decoder/tests/test_target_track.py
    - Decoder/tests/test_replay_export.py
    - Decoder/tests/fixtures/tiny_replay.bin
    - Decoder/tests/fixtures/tiny_replay.json
  modified:
    - Decoder/src/ndt1/data.py
    - Decoder/src/ndt1/sessions.py
    - Decoder/scripts/make_tiny_v73.py
    - Decoder/tests/fixtures/tiny_v73.mat
    - Decoder/tests/fixtures/tiny_v73.truth.json
    - .gitignore

key-decisions:
  - "bin_target_track takes the LAST sample per bin and the docstring names the mean as forbidden with its failure mode: a bin spanning a target change would emit an off-grid target the subject never saw"
  - "first_off_grid_index is a public, directly tested function rather than an inline assertion, so the Pitfall-4 control is falsifiable in a test instead of unreachable through the loader"
  - "bin_target_track rejects a non-monotone clock, because 'the last sample in the bin' is undefined when samples are out of order and would silently depend on storage order"
  - "trials is the SEGMENT count (changes + 1 = 1,025), matching webgrid_ceiling.py::trial_bounds and 10-ceiling.json, not the raw change count of 1,024"
  - "The record is a packed little-endian numpy structured dtype pinned at 424 bytes, with an import-time check that the dtype and the constant have not drifted"
  - "The binary carries no header: the header is the sidecar, so a human and a gate read the same thing and the reader can bound the file before reading it"
  - "write_export validates shapes and the key set only; header validation lives in read_export, where the trust boundary is"
  - "The synthetic fixture's source_sha256 is the sha256 of its own generator script, and its checkpoint digests are 64 zeros because no checkpoint produced it"
  - "Row semantics under the 1-bin lag are stated in writing: spikes[i] and t_start[i] are bin i, velocity[i] and target[i] are bin i + lag_bins"

patterns-established:
  - "Fixture truth computed in closed form from the fixture's own geometry, never by calling the code under test"
  - "A negative control is executed and its raised message recorded verbatim in the summary, not merely asserted in a test"
  - "Literal-grep acceptance criteria are satisfied by dropping the type annotation on the pinned constant rather than by rewording the criterion"

requirements-completed: [RD-07, RD-08]

# Metrics
duration: 22min
completed: 2026-09-05
---

# Phase 10 Plan 02: Target track and the D-06 replay export Summary

**The session's real `target_pos` now reaches the loader as a last-sample-per-bin track with an on-grid membership guard, and `ndt1.replay_export` turns one pinned `.mat` into a 424-byte-per-bin binary plus a provenance-bearing sidecar - materialized for `indy_20160630_01` at 73,160 bins and covered on a clean clone by a committed 256-bin synthetic fixture.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-09-05T21:48Z
- **Completed:** 2026-09-05T22:10Z
- **Tasks:** 3
- **Files modified:** 13 (7 created, 6 modified)

## Accomplishments

- `load_session` reads a third behavior array (D-01) and returns `target_mm` plus `target_distinct`; the aggregation is last-sample-per-bin and a membership guard runs on every load, so a regression to mean aggregation cannot reach an artifact quietly.
- `ndt1.replay_export` owns the D-06 format in both directions. The reader refuses a schema bump, a wrong channel width, a non-positive bin count, a wrong record size, a `source_sha256` that is not 64 lowercase hex, a `binary_path` resolving outside the sidecar's directory, and a size that disagrees with the header - all before `np.fromfile` runs.
- The real `indy_20160630_01` export exists on disk (gitignored), read back through `read_export(verify_digest=True)` and confirmed bit-identical to a fresh `load_session` derivation over all 73,160 rows.
- The x10 cursor/finger frame relation was verified on the exported session rather than assumed, and reproduced 10-RESEARCH's independent fit to eight decimal places.
- A committed 256-bin synthetic fixture (108,544 bytes, byte-reproducible) makes every export test run with `Decoder/data/` and `Decoder/exports/` both absent; the whole quick suite (260 tests) passes in that state.

## Task Commits

Each task was committed atomically:

1. **Task 1: target_pos through load_session and SessionLoad** - `121e6c0` (test, RED) then `881a48e` (feat, GREEN)
2. **Task 2: ndt1.replay_export, the D-06 writer and reader** - `2425257` (test, RED) then `3c15428` (feat, GREEN)
3. **Task 3: export_replay.py, the synthetic fixture and the gitignore entry** - `f573fd8` (feat)

**Provenance docstring follow-up:** `5d84b8b` (docs - the `source_sha256`-from-manifest link required by the plan's `key_links`)

## Files Created/Modified

- `Decoder/src/ndt1/data.py` - `bin_target_track` (last sample per bin, same edges as `bin_spikes`), `first_off_grid_index` (the membership control), the `target_pos` read, and the hard-rules docstring block naming the third behavior array
- `Decoder/src/ndt1/sessions.py` - `SessionLoad.target_mm` and `.target_distinct`, no default; the single construction site updated
- `Decoder/src/ndt1/replay_export.py` - the 424-byte record dtype, `SIDECAR_KEYS`, `workspace_from_cursor`, `build_sidecar`, `write_export`, `read_export`, `ReplayExport`
- `Decoder/scripts/export_replay.py` - the D-07 materializer: manifest digest, loader, locked 1-bin lag, x10 frame verification, workspace box, reported firing-rate band, sidecar assembly
- `Decoder/scripts/make_tiny_replay.py` - the committed synthetic fixture generator, deterministic and self-provenanced
- `Decoder/scripts/make_tiny_v73.py` - a `target_pos` step function on a 15.0 mm grid with 3 of 4 steps landing mid-bin, plus five new truth fields
- `Decoder/tests/test_target_track.py` - 13 tests including the mean-aggregation control
- `Decoder/tests/test_replay_export.py` - 20 test functions (26 collected), hermetic, none `slow`
- `Decoder/tests/fixtures/tiny_replay.{bin,json}` - the committed synthetic export
- `Decoder/tests/fixtures/tiny_v73.{mat,truth.json}` - regenerated; every pre-existing truth field is byte-identical (verified by diff)
- `.gitignore` - `Decoder/exports/` plus negations for the two tracked fixture files

## Measured results

Machine: **Apple M5 Pro**, macOS-26.5-arm64, python 3.12.13, numpy 2.4.6, h5py 3.16.0. These are data-derivation numbers, not performance numbers; no device-class claim attaches to them.

### The real export (step 3e)

| Field | Value |
|---|---|
| Binary | `Decoder/exports/indy_20160630_01.replay.bin`, **31,019,840 bytes** = 73,160 x 424 |
| Sidecar | `Decoder/exports/indy_20160630_01.replay.json`, 1,603 bytes |
| `n_bins` | **73,160** (73,161 loader bins minus the locked 1-bin lag) |
| `binary_sha256` | `5107b00911de761a60fe9ecc83dfef9b195d387ba42467586ef899755e57c48f` |
| sidecar sha256 | `020272235bbf8cea83c0c07a091a572df008dfe3ec9de45755d4b052ce94d42d` |
| `source_sha256` | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` (verbatim from the manifest) |
| `workspace.side_mm` | **171.0725351294064** |
| `workspace.cell_mm` | **5.7024178376468795** |
| `workspace.acquisition_radius_mm` | **2.8512089188234397** |
| `workspace.grid_units_per_cm` | **0.05845473671408203** |
| workspace bounds | x [-73.84889606362775, 97.22363906577863], y [-30.20853147605429, 140.86400365335209], centre (11.68737150107544, 55.327736088648905) |
| `target_grid` | **64** distinct targets, **15.0 mm** pitch, `log2_n_task` **6.0** |
| `trials` | **1025** |
| Checkpoint digests | encoder `f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e`, velocity `9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65` (both match `09-decoder-metrics.json`) |
| `env` | python 3.12.13, numpy 2.4.6, h5py 3.16.0 |

**x10 frame-relation fit, printed at write time and re-verified against 10-RESEARCH:**

```
cursor_x = 10.005060 * planar_x(cm) + 0.000528   R2 = 0.99996642
cursor_y = 10.004078 * planar_y(cm) + -0.023824  R2 = 0.99997487
```

Identical to the values 10-RESEARCH measured independently ("Ground truth from the dataset"), to every digit printed there.

**QC firing-rate band over the exported spikes:** mean 14.84 Hz, median 6.63 Hz, live channel fraction 0.927, zero fraction 0.787. **No band violations.** The band is reported and never enforced (D-09).

**Read-back cross-check.** `read_export(verify_digest=True)` succeeds and all four arrays are bit-identical to a fresh `load_session` -> `planar_velocity_250hz` -> `bin_velocity` -> `apply_lag(1)` derivation over 73,160 rows. All 64 emitted target pairs are on the session grid. `bin_starts` spans 148.984 s to 1612.164 s. Exported velocity magnitude p50 **1.8218 cm/s**, p99 **36.8465 cm/s**, which reproduces 10-RESEARCH's independently measured p50 1.822 / p99 36.846. Total exported spike counts: 1,932,272.

`git status --short Decoder/exports/` produces no output; `git check-ignore -v Decoder/exports/x.bin` reports `.gitignore:99:Decoder/exports/`.

### The loader on the real session (Task 1)

73,161 bins by 96 channels; 64 distinct `(x, y)` target pairs; 8 distinct x and 8 distinct y; 15.0 mm pitch on both axes; x range -52.5 to 52.5 mm, y range 7.5 to 112.5 mm. All match 10-RESEARCH's table for `indy_20160630_01` exactly. The binned track carries **1,024** target changes, so no trial boundary is lost to 20 ms binning (the sample-level track also has 1,024 changes = 1,025 trials).

### The committed synthetic fixture

108,544 bytes = 256 x 424, `binary_sha256` `69db628905ff51155b857c42e07a86ee5f9267b789c4cbf7c29b6732a07da2c0`, byte-identical across two independent generator runs. `source_sha256` `5577e3c7607bbc85ce7b4f14a5fba7d6bcc075d2c32c15b2727d8cc639780d01` is the sha256 of `make_tiny_replay.py` itself. Its `disclosure` reads `synthetic fixture - not real neural data; exists so the export format is covered on a clean clone` and its `session_id` is `tiny_replay_synthetic`.

### Negative controls, executed (not merely asserted)

```
CONTROL 0 (valid export): 3392 bytes = 8 x 424, reads OK (8, 96)

CONTROL 1 (truncate by 1 byte) RAISED:
  c.replay.json declares 8 bins = 3392 bytes but c.replay.bin is 3391 bytes on disk.
  Refusing to size a read from a header the file does not support

CONTROL 2 (symlink escape) RAISED:
  c.replay.json names binary_path 'c.replay.bin', which resolves to
  /private/var/.../tmpe9dqezde/outside/c.replay.bin -- outside the sidecar's own
  directory /private/var/.../tmpe9dqezde/exports. Refusing to follow it
```

Both mitigate their register entries: T-10-02-01 (allocation sized from an untrusted header) and T-10-02-05 (symlinked `binary_path`).

## Verification

| Command | Result |
|---|---|
| `uv run --project Decoder ruff check Decoder` | All checks passed |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | **260 passed**, 9 deselected |
| Quick suite with `Decoder/data/` AND `Decoder/exports/` moved away | **259 passed, 1 skipped** (the skip is the pre-existing dataset-gated `test_data.py::test_load_session_real_mat`) |
| `./Tools/scripts/decoder-policy.sh` | exit 0 |
| `./Tools/scripts/decoder-policy.sh --self-test` | exit 0, all four controls bite |
| `grep -c 'def test_' Decoder/tests/test_target_track.py` | 13 (>= 6) |
| `grep -c 'def test_' Decoder/tests/test_replay_export.py` | 20 (>= 8) |
| `grep -c '@pytest.mark.slow' Decoder/tests/test_replay_export.py` | 0 |
| `grep -nE '"wf"' Decoder/src/ndt1/data.py` | no match (T-10-02-06 holds) |
| `grep -rn 'cursor_pos' Decoder/src/ndt1/*.py \| grep -v '#'` | no match (D-01 holds in the loader) |
| `grep -nE 'except\s*:\|except Exception'` over every touched Python file | no match |
| Fixture truth diff, pre-existing fields | byte-identical |

## Decisions Made

Recorded in the frontmatter `key-decisions` block. The two that later plans must know about:

- **`trials` is the segment count.** 1,025, not the 1,024 raw changes, so the export and `10-ceiling.json` describe the same trials.
- **Row semantics under the lag.** Row `i` pairs spike bin `i` with kinematics at bin `i + lag_bins`. `spikes[i]` and `t_start[i]` are bin `i`; `velocity[i]` and `target[i]` are 20 ms later. Both `lag_bins` and `lag_ms` are in the sidecar so a consumer recovers the kinematic time. This is stated in the `export_replay.py` module docstring, not left to be inferred.

## Cross-artifact discrepancies (flagged, not resolved here)

Both are recorded rather than silently reconciled, per the evidence discipline. Neither is edited, because 10-PREREGISTRATION governs and it has already been measured against.

1. **`side_mm` differs from `10-ceiling.json`.** This export computes **171.0725 mm**; Plan 10-01's `10-ceiling.json` records **171.68196 mm**. Both are `cursor_bbox_square`, and the difference is the input: 10-PREREGISTRATION section 3 defines `cursor_mm = 10.0 * planar_cm` and this export follows that literally, while `webgrid_ceiling.py` boxed the recorded `cursor_pos` array directly. The frame relation is slope 10.005 with a small intercept, so the two spans differ by 0.61 mm (0.35 percent). Consequences: `cell_mm` 5.7024 vs 5.7227, `acq_radius_mm` 2.8512 vs 2.8614, and `grid_units_per_cm` 0.0584547 vs 0.0582470. **Plan 10-03 matters here:** 10-PREREGISTRATION section 4 fits R with `k = 10.0 / side_mm`, so which `side_mm` it takes changes R by about 0.7 percent. The pre-registration's own formula points at the export's value; 10-01's number came from the recorded cursor. The phase should state which one the artifacts quote and use it consistently.
2. **Key naming.** The export sidecar uses `acquisition_radius_mm` (the name in 10-PREREGISTRATION section 11 and 10-RESEARCH Pattern 1); `10-ceiling.json` uses `acq_radius_mm`. Both were specified that way in their own plans. A downstream reader of both must handle the two spellings.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `trials` counts segments (1,025), not raw changes (1,024)**
- **Found during:** Task 3 (sidecar assembly)
- **Issue:** The plan said `trials` = "the number of target changes in the binned track", which yields 1,024. `Decoder/scripts/webgrid_ceiling.py::trial_bounds`, `10-ceiling.json` (`trials: 1025`) and 10-RESEARCH ("1,025 trials") all count segments. Two Phase-10 artifacts reporting different trial counts for the same session would be an unexplained discrepancy at exactly the point where decoded hits are compared with the recorded-cursor replay reference.
- **Fix:** `count_trials` returns `changes + 1` and its docstring names `trial_bounds` as the definition it matches.
- **Files modified:** `Decoder/scripts/export_replay.py`
- **Verification:** The export sidecar reads `trials: 1025`, equal to `10-ceiling.json`.
- **Committed in:** `f573fd8`

**2. [Rule 2 - Missing critical] `bin_target_track` rejects a non-monotone clock**
- **Found during:** Task 1
- **Issue:** The contract is "the LAST sample in each bin". On an out-of-order clock that phrase has no meaning, and the emitted target would silently depend on array storage order - a fabrication risk of exactly the class D-01 exists to close.
- **Fix:** A `np.diff(clock) < 0` check that raises a `ValueError` naming the offending index pair, plus `test_bin_target_track_rejects_a_non_monotone_clock`.
- **Files modified:** `Decoder/src/ndt1/data.py`, `Decoder/tests/test_target_track.py`
- **Verification:** Test passes; the real session's clock is strictly increasing and is unaffected.
- **Committed in:** `881a48e`

**3. [Rule 2 - Missing critical] The membership guard is a public tested function, not an inline assertion**
- **Found during:** Task 1
- **Issue:** The plan asked for an inline assertion in `load_session`. As written it is unreachable by any input, because `bin_target_track` structurally cannot emit an off-grid value, so an inline assertion could never be shown to bite - and an untested guard is indistinguishable from a missing one.
- **Fix:** `first_off_grid_index(track, distinct)` is public and documented as the Pitfall-4 control; `load_session` calls it and raises naming the offending row and value. `test_first_off_grid_index_catches_the_mean_aggregation_artifact` feeds it the exact `(7.5, 0.0)` a mean aggregator would produce and asserts the reported index.
- **Files modified:** `Decoder/src/ndt1/data.py`, `Decoder/tests/test_target_track.py`
- **Verification:** The control test passes and fails if the guard is removed.
- **Committed in:** `881a48e`

**4. [Rule 3 - Blocking] Worktree lacked the gitignored dataset and checkpoints**
- **Found during:** Setup, before Task 1
- **Issue:** `Decoder/data/` and `Decoder/checkpoints/*.pt` are gitignored, so a fresh worktree has neither, and the sidecar needs both checkpoint digests. A bare symlink at `Decoder/data` also left the tree dirty: `.gitignore`'s `Decoder/data/` has a trailing slash and matches only a real directory, so git saw the symlink as an untracked file.
- **Fix:** `Decoder/data/` is a real directory holding four symlinks to the canonical `.mat` files, and the two `.pt` checkpoints are symlinked into `Decoder/checkpoints/`. Nothing was committed; `git status --short` is clean.
- **Files modified:** none (untracked, ignored paths only)
- **Verification:** `git status --short` clean; `checkpoint_sha256` reproduces `f95b257bf247...` and `9d542cb51d4a...` exactly.
- **Committed in:** n/a

**5. [Rule 1 - Bug] Header-refusal tests retargeted at an on-disk tampered sidecar**
- **Found during:** Task 2 (GREEN)
- **Issue:** The tests first tried to induce a bad header through `build_sidecar` overrides, but `write_export`'s own `n_bins` check fires first (arrays of 8 rows against a declared 0), so the writer refused the setup before the reader could be tested.
- **Fix:** A `_tamper()` helper rewrites the written sidecar's header fields on disk. This is also the faithful threat: a hand-edited, truncated or substituted export, not a writer talked into emitting one.
- **Files modified:** `Decoder/tests/test_replay_export.py`
- **Verification:** All refusal tests pass and each names the field it refused.
- **Committed in:** `3c15428`

**6. [Rule 3 - Blocking] Two acceptance greps are literal, so two constants dropped their annotations**
- **Found during:** Task 2
- **Issue:** The acceptance criteria grep for the fixed strings `RECORD_BYTES = 424` and `EXPORT_SCHEMA_VERSION = 1`; `RECORD_BYTES: int = 424` does not match.
- **Fix:** Both constants are written without the redundant `: int` annotation (inference gives `int` regardless). This is the documented literal-grep pattern from earlier phases.
- **Files modified:** `Decoder/src/ndt1/replay_export.py`
- **Verification:** Both greps match; ruff and the suite are green.
- **Committed in:** `3c15428`

**Total deviations:** 6 auto-fixed (2 bug, 2 missing critical, 2 blocking)
**Impact on plan:** No scope creep. Every fix is inside the plan's own file list, and the two that change a plan-specified value (`trials`, the constants' annotations) are recorded above with the number they produce.

## Issues Encountered

- **The `ty` type checker reports unresolved imports and structured-dtype assignment errors.** It runs outside the project's `uv` environment, so `h5py`, `torch`, `pytest` and `ndt1` are all unresolvable to it, and it does not model numpy structured-array field assignment (`records["spikes"] = counts`). Pre-existing and environmental: the same diagnostics appear on untouched files such as `Decoder/scripts/make_tiny_v73.py`. The project's gates are `ruff check` and `pytest`, both green. Not fixed, and logged here rather than in `deferred-items.md` because there is nothing in the repository to change.
- **Ruff's isort classification of `ndt1` flipped mid-task**, treating it as third-party before `replay_export.py` existed and first-party after. Resolved by running `ruff check --fix` once the module was in place.

## User Setup Required

None - no external service configuration required. Downstream plans that need the real export must run, on a machine where `Decoder/data/` is materialized:

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/export_replay.py --session indy_20160630_01
```

Expected: `Decoder/exports/indy_20160630_01.replay.{bin,json}`, 31,019,840 bytes and 73,160 bins, with the sidecar values tabulated above.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: unverified_by_default | `Decoder/src/ndt1/replay_export.py` | `read_export`'s `verify_digest` defaults to `False`, so an ordinary read checks the file's SIZE against the header but not its CONTENT hash. That is deliberate (re-hashing 31 MB on every read), and truncation or substitution at a different length is still caught. A consumer that publishes a number from an export - the Plan 10-09 provenance gate, and the daemon path in the D-05 chain - should pass `verify_digest=True` or hash the binary itself, so the published number is bound to the exact bytes the sidecar describes. |

## Next Phase Readiness

- **10-03 (Kalman R re-fit):** the export's `workspace.side_mm` is 171.0725 mm and `grid_units_per_cm` is 0.05845473671408203. See the cross-artifact discrepancy above before choosing `k`.
- **10-04 onward (the Swift replay source):** the format is `RECORD_BYTES = 424`, little-endian, no header; per bin, 96 `float32` counts then 2 `float64` velocity then 2 `float64` target then 1 `float64` bin start. `Decoder/tests/fixtures/tiny_replay.bin` is a committed 256-record file for a Swift-side round-trip test that needs no dataset.
- **10-09 (schema and provenance gate):** the sidecar key set is pinned in `ndt1.replay_export.SIDECAR_KEYS`; the real sidecar's own sha256 is `020272235bbf8cea83c0c07a091a572df008dfe3ec9de45755d4b052ce94d42d` and its `binary_sha256` is `5107b00911de761a60fe9ecc83dfef9b195d387ba42467586ef899755e57c48f`.
- **No blockers.** STATE.md and ROADMAP.md were deliberately not touched: the orchestrator owns those writes after the wave completes.

## Self-Check: PASSED

Files claimed as created, all confirmed present:
`Decoder/src/ndt1/replay_export.py`, `Decoder/scripts/export_replay.py`, `Decoder/scripts/make_tiny_replay.py`, `Decoder/tests/test_target_track.py`, `Decoder/tests/test_replay_export.py`, `Decoder/tests/fixtures/tiny_replay.bin`, `Decoder/tests/fixtures/tiny_replay.json`, `Decoder/exports/indy_20160630_01.replay.bin`, `Decoder/exports/indy_20160630_01.replay.json`.

Commits claimed, all confirmed in `git log`:
`121e6c0`, `881a48e`, `2425257`, `3c15428`, `f573fd8`, `5d84b8b`.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
