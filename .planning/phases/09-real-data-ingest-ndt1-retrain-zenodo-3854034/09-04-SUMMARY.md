---
status: PASS
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 04
subsystem: decoder
tags: [numpy, pytest, ruff, qc, sessions, loso, ndt1, indy, firing-rate-band]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 02
    provides: "the committed tiny_v73.mat fixture with its inflated_10x and width_192 variants, and load_session's planar_cm / MATLAB_empty / chan_names-width contract"
  - phase: 04-decoder-training
    provides: "ndt1.data.chronological_split and the 96-channel width gate"
provides:
  - "ndt1.qc: firing_rate_stats, band_violations, PLAUSIBLE_BAND -- six population bounds with a dead-channel allowance"
  - "ndt1.sessions: available_sessions, pooled_splits, loso_folds, SessionLoad, SessionExclusion"
  - "A rejected .mat in Decoder/data/ is now excluded with its measured width, not raised through the suite (P5 closed)"
  - "Typed session exclusions that carry the loader's own message, so an exclusion is documented data rather than a silent drop"
affects: [09-06, 09-07, 09-08, real-data ingest, NDT1 retrain, LOSO evidence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Quality gates as population statistics with an explicit dead-channel allowance, never per-channel assertions"
    - "Every gate ships with both controls: one proving it does not over-bite on correct data, one proving it still bites on corrupt data"
    - "Exclusions returned as typed data alongside loads, so a dropped session is visible in the evidence artifact"
    - "Bounds cite their measured centre value in-source and state plainly that they are empirical, not a literature constant"

key-files:
  created:
    - Decoder/src/ndt1/qc.py
    - Decoder/src/ndt1/sessions.py
    - Decoder/tests/test_firing_rate_band.py
    - Decoder/tests/test_sessions.py
  modified:
    - Decoder/tests/test_heldout_cobps.py
    - Decoder/tests/test_data.py

key-decisions:
  - "mean_rate_hz is the mean over LIVE channels while median_rate_hz is the median over ALL channels; reporting both makes a disagreement between them visible, and neither needs the dead tail excluded by hand"
  - "A band violation is surfaced on the SessionLoad but never auto-excludes, so D-03's requirement that an exclusion be a documented decision is structural rather than a convention"
  - "loso_folds rejects duplicate session ids, because a repeat would put the same session in both train and held-out of one fold -- exactly the leakage the rotation exists to rule out"
  - "test_short_session_is_excluded_with_a_reason raises min_bins rather than generating a short fixture variant, which would have required editing make_tiny_v73.py outside this plan's files_modified"

patterns-established:
  - "Negative-control pairing: test_dead_channels_do_not_fail_the_band (does not over-bite) alongside test_inflated_density_falls_outside_the_band (still bites)"
  - "P5 repair verified in both directions against a real rejected file on disk, not only against a tmp_path unit test"

requirements-completed: [RD-02]

# Metrics
duration: 12min
completed: 2026-08-31
---

# Phase 9 Plan 04: Firing-Rate Band and the Multi-Session Layer Summary

**A firing-rate plausibility gate asserted as population statistics with a dead-channel allowance, so six silent channels pass and a 10x-density session fails, plus a session-scan layer that excludes a rejected `.mat` with the loader's measured width instead of erroring the whole suite.**

## Performance

- **Duration:** ~12 min (first commit 00:24:03, last 00:30:21 local, plus setup and verification)
- **Tasks:** 3 of 3
- **Files modified:** 6 (4 created, 2 modified)
- **Commits:** 5 (two TDD RED/GREEN pairs plus the P5 repair)

## Accomplishments

- `ndt1.qc.PLAUSIBLE_BAND` carries six population bounds. Every centre value is cited in-source next to its bound, and both the module docstring and the test module state plainly that the bounds are empirical and **not a literature constant** -- research found no paper stating a canonical numeric Hz band for macaque M1 threshold crossings that could be quoted as authoritative.
- The band was checked against four inputs before being committed, all measured in this worktree on the **synthetic** `tiny_v73.mat` fixture (real-data centre values come from 09-RESEARCH, not from this plan):

  | Input | mean (live) | median | live frac | max/bin | zero frac | Violations |
  |---|---|---|---|---|---|---|
  | committed fixture | 13.54 Hz | 13.40 Hz | 0.9375 | 5 | 0.7785 | **0** |
  | fixture, 6 more channels zeroed | 13.52 Hz | 13.30 Hz | 0.8750 | 5 | 0.7933 | **0** |
  | `inflated_10x` variant | 136.86 Hz | 135.75 Hz | 0.9375 | 14 | 0.1242 | 3, incl. `mean_rate_hz` |
  | all-zero `(500, 96)` | 0.0 Hz | 0.0 Hz | 0.0 | 0 | 1.0 | 4, incl. `live_channel_fraction` and `zero_fraction` |

  The first two rows are the P6 control (a per-channel band would fail both); the last two prove the band still bites.
- `band_violations` raises `KeyError` when a bound's statistic is absent rather than skipping the bound, which is what stops the "loosen it until it asserts nothing" failure mode from being invisible in review.
- `firing_rate_stats` returns `mean_rate_hz = 0.0` rather than dividing by zero when no channel is live, and 0.0 is itself outside the mean-rate bound, so an all-zero parse is still caught.
- `ndt1.sessions.available_sessions` attempts every `.mat` and catches exactly `(ValueError, KeyError, OSError)` -- the three types `load_session` documents -- recording a `SessionExclusion` whose `reason` is `f"{type(exc).__name__}: {exc}"`. A 192-channel M1+S1 file's exclusion therefore carries `chan_names declares 192 channels` verbatim into whatever artifact prints it.
- `pooled_splits` is a per-session chronological tail with no pooled shuffle (D-12); `loso_folds` is a full N-fold rotation with each session held out exactly once (D-13).
- **The P5 repair was verified against a real rejected file on disk, not only in `tmp_path`.** A `width_192` fixture was written to `Decoder/data/indy_00000000_00.mat` (a name chosen to sort ahead of every real session id) and the directory removed afterward:

  ```
  alphabetically-first .mat: indy_00000000_00.mat
  OLD PATTERN would ERROR the whole module: session indy_00000000_00.mat yielded 3 channels, ...
  REPAIRED _load_binned -> (4000, 96) | synthetic Poisson fallback (no .mat present)
  test_data.py                        -> 12 passed, 1 skipped   (skip, not error)
  ```

  With a loadable session added alongside it, `_load_binned` returned `(500, 96) | real sessions [indy_20160630_01] (excluded: 1)` and `test_data.py` went to 13 passed. `Decoder/data/` was then deleted and is absent again.
- Quick suite: **116 passed, 1 skipped, 9 deselected** in 1.79 s with `Decoder/data/` absent. `ruff check Decoder` clean across the whole tree. `pytest -m slow --collect-only` still collects 9 tests, so the repaired `test_heldout_cobps.py` did not drop out of collection.

## Task Commits

1. **Task 1: `ndt1/qc.py` (TDD)** - `52a20af` (test, RED) then `3043d11` (feat, GREEN)
2. **Task 2: `ndt1/sessions.py` (TDD)** - `0bbf1cd` (test, RED) then `9fdb2ca` (feat, GREEN)
3. **Task 3: the P5 repair** - `1a6c032` (fix)

No refactor commits: both modules were minimal as first written and no cleanup was warranted.

## Files Created/Modified

- `Decoder/src/ndt1/qc.py` (created, 157 lines) - `PLAUSIBLE_BAND`, `LIVE_CHANNEL_RATE_HZ`, `firing_rate_stats`, `band_violations`.
- `Decoder/src/ndt1/sessions.py` (created, 209 lines) - `SessionLoad`, `SessionExclusion` (both frozen dataclasses), `available_sessions`, `pooled_splits`, `loso_folds`, `DEFAULT_DATA_DIR`, `DEFAULT_MANIFEST`, `MIN_SESSION_BINS`. No torch, training or CoreML code.
- `Decoder/tests/test_firing_rate_band.py` (created, 144 lines) - 9 tests; the band derivation is in the module docstring.
- `Decoder/tests/test_sessions.py` (created, 194 lines) - 11 tests.
- `Decoder/tests/test_heldout_cobps.py` (modified, +14/-8) - `_load_binned` delegates to `available_sessions`; `load_session` import replaced. `CO_BPS_MARGIN` untouched at 0.05.
- `Decoder/tests/test_data.py` (modified, +15/-7) - `test_load_session_real_mat` routes through `available_sessions` and skips in-body; the `_HAS_MAT` module-level probe and its `skipif` are gone. Every other test in the module is unchanged.

## Decisions Made

- **`mean_rate_hz` over live channels, `median_rate_hz` over all channels.** The plan specified both; the reason worth recording is that reporting the pair makes a disagreement between them visible. A parse that empties most channels moves the median hard while barely moving the live-channel mean, and only having both surfaces that.
- **A band violation is attached, not acted on.** `available_sessions` computes `band_violations` for every loaded session and still returns it as loaded. D-03 requires an exclusion to be a documented decision, and a loader that quietly drops an implausible session is exactly the repudiation risk T-09-04-03 names.
- **`DEFAULT_MANIFEST` is defined but deliberately not read.** `available_sessions` scans the directory instead, so a `.mat` on disk but absent from the manifest is still surfaced rather than invisible. The constant is documented as that cross-reference. This also avoided coupling to `manifests/indy_sessions.json`, which plan 09-05 is rewriting in the same wave.
- **`min_bins` defaults to a named `MIN_SESSION_BINS = 320`** rather than a bare literal, so the arithmetic behind it (256 train + 64 test = 8 and 2 whole `seq_len=32` windows) lives next to the number.

## Deviations from Plan

### Commit-boundary deviation

**1. The two new test modules landed in the Task 1 and Task 2 RED commits, not in the Task 3 commit**
- **Found during:** Task 1
- **Issue:** Tasks 1 and 2 carry `tdd="true"`, which mandates a failing-test commit before implementation, but the plan assigned `test_firing_rate_band.py` and `test_sessions.py` to Task 3's `<files>`. Both cannot hold: honoring TDD requires those files to exist and fail before `qc.py` and `sessions.py` are written.
- **Resolution:** Honored the TDD flag. Each RED commit was confirmed to fail for the right reason (`No module named 'ndt1.qc'`, then `No module named 'ndt1.sessions'`), not for an incidental one. Task 3's commit is therefore the P5 repair (3c + 3d) alone.
- **Impact:** None on content. Every test the plan's 3a and 3b lists name is present, plus the extra coverage below. Only the commit boundary moved.

### Auto-fixed issues

**2. [Rule 2 - Missing critical] `loso_folds` rejects duplicate session ids**
- **Found during:** Task 2
- **Issue:** The plan specified only the "fewer than two" guard. A repeated id would place the same session in both `train_ids` and `held_out` of the same fold, which is precisely the leakage T-09-04-05 says `loso_folds` guarantees against, and it would happen silently -- the fold count and the `train_ids` lengths would both still look right.
- **Fix:** Explicit `ValueError` naming the duplicates, plus `test_loso_rejects_duplicate_session_ids`.
- **Files modified:** `Decoder/src/ndt1/sessions.py`, `Decoder/tests/test_sessions.py`
- **Commit:** `0bbf1cd`, `9fdb2ca`

**3. [Rule 2 - Missing critical] `firing_rate_stats` also rejects zero channels and non-positive `bin_ms`**
- **Found during:** Task 1
- **Issue:** The plan requires `ValueError` on a non-2-D input and on `num_bins == 0`. A `(500, 0)` matrix passes both checks and then makes `np.median` return `nan` with a `RuntimeWarning`, while `bin_ms <= 0` divides by zero. A `nan` flowing out of a quality gate is worse than having no gate, which is the whole thesis of this module.
- **Fix:** Both are explicit `ValueError`s with messages naming the offending value.
- **Files modified:** `Decoder/src/ndt1/qc.py`
- **Commit:** `3043d11`

**4. [Rule 3 - Blocking] `cast(float, ...)` instead of a bare `float(...)` on the loader's dict**
- **Found during:** Task 2
- **Issue:** `load_session` is annotated `-> dict[str, object]`, so `float(session["t_start"])` is an `invalid-argument-type` error under the repo's ambient type checker. This was a NEW diagnostic introduced by this plan, unlike the pre-existing `unresolved-import` noise.
- **Fix:** `typing.cast` with a comment stating that these two entries are floats by `load_session`'s documented contract. Zero runtime cost, and no runtime validation added for a value the loader builds with `float()` two functions away (YAGNI). The array fields already narrow through `np.asarray(..., dtype=...)`, which both types and validates them.
- **Files modified:** `Decoder/src/ndt1/sessions.py`
- **Commit:** `9fdb2ca`

### Coverage added beyond the plan's test lists

Eight tests not named in the plan's 3a and 3b lists, each closing a behavior the plan's own
`<behavior>` blocks state (a ninth, `test_loso_rejects_duplicate_session_ids`, is deviation 2):
`test_stats_report_the_dead_channel_tail`, `test_stats_reject_a_non_2d_input`,
`test_stats_reject_an_empty_matrix`, `test_violation_message_names_bound_value_and_range`
(Task 1's "each violation is a human-readable string containing the bound name, the observed value
and the allowed range"), `test_absent_data_dir_returns_nothing`,
`test_session_load_carries_the_full_record`, `test_band_violations_do_not_auto_exclude` and
`test_exclusion_is_a_typed_record`.

### Non-issue deviations

**5. The `key_links` pattern `except ValueError` does not literal-grep against the implementation.** The frontmatter declares `pattern: "except ValueError"` for the `sessions.py -> data.py` link, but Task 2's `<action>` and its acceptance criterion both mandate `except (ValueError, KeyError, OSError)`, which is what is implemented and what `grep -F 'except (ValueError, KeyError, OSError)'` matches. A verifier grepping the bare `key_links` pattern will find nothing; it should grep the tuple form. The acceptance criterion is authoritative and is satisfied.

**6. `test_short_session_is_excluded_with_a_reason` raises `min_bins` rather than building a short fixture.** `make_tiny_v73.py` has a fixed `N_SAMPLES` and adding a short variant would have required editing it, which is outside this plan's `files_modified`. Calling `available_sessions(tmp_path, min_bins=10_000)` on the 500-bin fixture exercises the same exclusion branch and asserts both numbers appear in the reason.

**7. `Decoder/data/` was created and removed during Task 3 verification.** A single `width_192` fixture was written there to prove the P5 repair against a real on-disk rejected session, then the directory was deleted. It is gitignored (`.gitignore:90`), was never staged, and is absent again -- `git status --short` showed only the two intended test-module modifications. No session data was downloaded.

**8. `REQUIREMENTS.md` was not updated.** RD-02 is satisfied by this plan, but the orchestrator owns cross-plan tracking writes while 09-03 and 09-05 run concurrently on this phase, and `REQUIREMENTS.md` is outside this plan's `files_modified`.

---

**Total deviations:** 1 commit-boundary (TDD flag versus file assignment), 3 auto-fixed (2 missing-critical guards, 1 blocking type error), 4 documented non-issues. No scope creep; no architectural change.

## Issues Encountered

**Transient ruff `I001` during both RED states.** While `ndt1.qc` and `ndt1.sessions` did not yet exist, ruff's isort classified them as third-party and asked to move their imports above the first-party block. The finding disappeared the moment each module was created, and `ruff check Decoder` is clean at every commit from the GREEN commits onward. Applying the suggested fix in the RED state would have had to be reverted immediately, so it was left alone.

**Pre-existing `ty` `unresolved-import` noise, not re-logged.** The ambient type checker reports unresolved imports for `pytest`, `torch` and `ndt1.*` on every file under `Decoder/` because it does not see `Decoder/.venv`. This is already deferred-items entry 2 from plan 09-02 and is repo-wide, so it was not duplicated into a new deferred file. It is a tool-configuration gap, not a code defect: `ruff check Decoder` and the quick pytest run both exit 0.

## Deferred Items

None new. The one relevant pre-existing item is `deferred-items.md` entry 2 above; that file was deliberately not touched, since 09-03 and 09-05 are executing concurrently and a shared append caused an add/add conflict in Wave 1.

## Known Stubs

None. No hardcoded empty value, placeholder string, or unwired data path was introduced. `DEFAULT_MANIFEST` is an intentionally unread constant documented as a cross-reference, not a stubbed code path -- `available_sessions` has no manifest-driven branch to fill in later.

Every number reported in this summary is either (a) measured in this worktree on the **synthetic** `tiny_v73.mat` fixture and labeled as such, or (b) a real-data measurement carried over from 09-RESEARCH section 3 and attributed there. This plan loaded no real session, trained nothing, and asserted no real-data measurement.

## Verification

```
uv sync --project Decoder --extra dev
uv run --project Decoder pytest Decoder/tests -m "not slow" -q   -> exit 0 (116 passed, 1 skipped, 9 deselected)
uv run --project Decoder ruff check Decoder                      -> exit 0 (All checks passed)
uv run --project Decoder pytest Decoder/tests -m slow --collect-only -q -> 9 collected (repaired module still collects)
```

Plan-specified per-task verification snippets for Task 1 and Task 2 both printed `OK`. All 23 acceptance-criteria checks across the three tasks pass as specified, including the six negative greps (`except:` / `except Exception` absent from both new modules, `import torch` absent from `sessions.py`, `next(_DATA_DIR.glob` absent from `test_data.py`, and zero `@pytest.mark.slow` in either new test module). `CO_BPS_MARGIN: float = 0.05` is unchanged, as D-22 requires for Plan 09-06 to re-derive.

Artifact minimums met: `qc.py` 157 lines (>= 90), `sessions.py` 209 (>= 110), `test_sessions.py` 194 (>= 90).

Everything runs with `Decoder/data/` absent.

## User Setup Required

None.

## Next Phase Readiness

- Plan 09-06's evidence runner has the pieces it needs: `pooled_splits` for the D-12 per-session split, `loso_folds` for the D-13 rotation, and `SessionExclusion` records to populate the excluded-sessions table with a measured width rather than a bare count.
- `SessionLoad.stats` already carries the per-session channel yield (`dead_channels`, `sub_1hz_channels`, `live_channel_fraction`) that D-04 requires the evidence artifact to report in place of rate normalization.
- The band is wired into `available_sessions` but is not yet run against any real session. The first genuine test of these bounds is the moment plan 09-05's download lands and 09-06 scans it. If a real session violates a bound, that is a finding to document under D-03, not a signal to widen the band.
- `CO_BPS_MARGIN` is untouched and still carries its Phase-4 synthetic-data value, awaiting 09-06's re-derivation.

## Self-Check: PASSED

Files claimed, verified present:
- `Decoder/src/ndt1/qc.py` FOUND (8,426 bytes)
- `Decoder/src/ndt1/sessions.py` FOUND (9,352 bytes)
- `Decoder/tests/test_firing_rate_band.py` FOUND (6,815 bytes)
- `Decoder/tests/test_sessions.py` FOUND (8,604 bytes)
- `Decoder/tests/test_heldout_cobps.py` FOUND (6,556 bytes, modified)
- `Decoder/tests/test_data.py` FOUND (7,458 bytes, modified)

Commits claimed, verified in `git log b789fb1..HEAD`:
- `52a20af` FOUND, `3043d11` FOUND, `0bbf1cd` FOUND, `9fdb2ca` FOUND, `1a6c032` FOUND

`Decoder/data/` verified absent after the Task 3 P5 proof. Working tree clean apart from this summary.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-08-31*
