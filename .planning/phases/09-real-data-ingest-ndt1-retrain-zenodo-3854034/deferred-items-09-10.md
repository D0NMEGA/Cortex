# Deferred items from Plan 09-10 (D-24 citation sweep)

Out-of-scope discoveries found while sweeping the decoder-owned surfaces. None of these was fixed
here; D-24 scopes this plan to `PROJECT.md`, the ROADMAP Phase-4 bullet, REQUIREMENTS RD-03, and
superseded banners on three Phase-4/5 evidence artifacts.

## For RD-09 (Phase 10 repo-wide sweep)

1. **`README.md` cites the 226 op tally twice** (lines 37 and 147: "226/226 ops ANE-eligible"). The
   trained real-data graph is **239/239 eligible, 0 CPU-only**. README is explicitly Phase 10's
   (RD-09), and it is also gated by `readme-policy.sh`, so it must be edited in lockstep with RD-10.

2. **`.planning/phases/05-.../05-ane-eligibility-evidence.md` carries the 226 tally in 7 places.**
   It is not in this plan's `files_modified`. It needs the same treatment the other three Phase-5/4
   artifacts got here: a superseded banner pointing at `09-coreml-evidence.md`, with its measured
   content left intact. Note the correction is twofold: the scan read a stale compiled artifact AND
   the graph it scanned was untrained.

3. **`.planning/phases/05-.../05-latency-evidence.md` and `05-placement-evidence.md`** were measured
   on a randomly-initialized graph (`09-decoder-metrics.json` records
   `latency.phase5_baseline.note` as exactly that). Phase 9's real-weights p99 of 0.141083 ms
   reproduces the 0.139333 ms baseline, so no number is wrong, but the provenance label is missing.

4. **ReFIT BPS numbers are still synthetic-derived and unlabeled in places.** `PROJECT.md`'s Active
   ReFIT bullet cites "refit_bps 0.374 >= raw 0.161" without a synthetic label on that line (the Key
   Decisions row does say "on synthetic replay"). ReFIT 1.953 BPS in the ROADMAP Phase-8 bullet and
   the README is likewise synthetic. Phase 10 owns re-deriving these (RD-07); this plan deliberately
   did not relabel or re-derive any BPS figure, and took care that none of its edits sit adjacent to
   a BPS number in a way that implies real-data provenance.

## A defect in a Phase-9 artifact (not a Phase-4/5 one)

5. **`09-velocity-evidence.md` line 69 and `Decoder/scripts/fit_velocity_real.py` line 13 attribute
   the superseded 0.99985 to the wrong test.** Both cite
   `Decoder/tests/test_convert_velocity_output.py:55`. The number in `velocity_r2.json` is actually
   written by `Decoder/tests/test_velocity_head.py::test_load_ridge_reproduces_linear_map_and_records_r2`
   (line 155), whose `n = 800` with `split = 600` gives the `n=200` the Phase-5 artifact reports;
   `test_convert_velocity_output.py` uses `n_windows = 64`. The substance is unaffected, since both
   tests build labels as a seeded linear map of the design matrix plus noise and are therefore both
   self-consistency checks. Only the file reference is wrong.

   The banner this plan added to `05-velocity-head-evidence.md` cites the **correct** producer.
   Fixing the two Phase-9 references is left to whoever next touches those files.

## Stale pointer

6. **`.planning/PROJECT.md`'s Evolution footer still says "Next: Phase 9 —
   photodiode-rig-hardware-build (the v1 canonical-claim path)."** That was falsified by the
   2026-08-28 re-point: Phase 9 is real-data ingest and the photodiode path is retired to Future
   work. Not corrected here because the footer cites no superseded decoder number, and the plan's
   action is explicit that lines which do not cite one are not to be touched. It belongs to the next
   `/donny-transition` or to RD-09.

## Noted, no action needed

7. **`Tools/scripts/readme-policy.sh` still REQUIRES the literal tokens `photodiode` and `24.7`** in
   the README, and its `--self-test` proves the gate bites when they are stripped. That is RD-10's
   job to rewrite in lockstep with the README. Left completely untouched here; verified still green
   (`readme-policy.sh` and `--self-test` both exit 0 after this plan's edits).
