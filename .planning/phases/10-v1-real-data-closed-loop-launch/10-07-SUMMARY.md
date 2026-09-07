---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 07
subsystem: evidence
tags: [rd-07, ablation, refit, kalman, webgrid-bps, fitts, real-data, d-09, d-11, d-12, willett, provenance]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: Plan 10-05's CortexReplayBench and ArmStatistics; Plan 10-02's D-06 export of indy_20160630_01; Plan 10-03 and 10-03a's real-data Kalman re-fit on the corrected cursor_bbox_square box; Plan 10-01's 10-ceiling.json recorded-cursor replay reference; 10-PREREGISTRATION sections 1, 2, 3a, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: the shipped ndt1_real_vel_sweep_fp16.mlpackage, the per-session held-out velocity R2 figures, and the leave-one-session-out co-bps bounds
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: the synthetic seed-locked Webgrid and Fitts triple this artifact supersedes and preserves
provides:
  - 10-refit-real.json - the committed four-arm real-data ablation metrics, bound to the session digest, the export sidecar digest and both checkpoint digests
  - 10-refit-real-evidence.md - the narrated result, with the zero-hit finding, the target-determined caveat, the three-ground non-comparability disclosure and a reproducible runbook
  - The measured answer to RD-07 - ReFIT's uplift does not survive contact with real spikes on the target-blind arms
affects: [10-06, 10-09, 10-10, 10-11, 10-12, 10-14, rd-08, rd-09, sc2-adjudication]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A zero is published with a hit-independent proxy beside it, so a floored count still discriminates arms"
    - "A hand-edit to a generated artifact is preceded by a proven byte-identical round-trip, so diff shows only the intended keys"
    - "A pre-registered line-number citation that drifted under a later commit is carried with BOTH the registered form and the form that resolves today"
    - "A reference figure is never quoted bare: its grid, participant, formula and retrieval date travel with it"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md
  modified: []

key-decisions:
  - "The run used -c release. 10-05's own note records debug as roughly two orders of magnitude slower over the 224 million SpikeInputBuffer.write calls; the plan's bare swift run would have cost roughly 20 minutes for an identical result"
  - "ticks_model_backed and ticks_total went inside env, not at the top level, so 10-PREREGISTRATION section 10's written requirement is literally satisfied without changing the section-11 top-level key set"
  - "ceiling_ref carries a note stating what the reference is and is not, because the key NAME imports the framing section 16 rejected and the note is the mitigation"
  - "references.note was NOT hand-edited: the bench already emits a note naming each external figure's condition, so the plan's third hand-add was already satisfied by the generator"
  - "The section 15 row is NAMED (row A on the literal first column) and explicitly NOT adjudicated; sc2_disposition is a key of 10-replay.json and the choice is the user's at Plan 10-10 Task 3"

patterns-established:
  - "A derived number narrated in prose is computed by script from the committed JSON, never by hand arithmetic in the writing step"
  - "Acceptance greps are written as at-least and exactly assertions and run before the commit, not asserted afterwards"

requirements-completed: [RD-07]

# Metrics
duration: 16min
completed: 2026-09-05
---

# Phase 10 Plan 07: The four-arm ReFIT ablation on real spikes Summary

**The two arms attributable to the decode scored zero of 1,025 trials on real `indy_20160630_01` spikes, and the zero is published as the finding with a hit-independent distance proxy showing it is not a near miss: the target-blind cursor's 1st-percentile approach was 16.58 mm against a 2.86 mm acquisition radius.**

## Performance

- **Duration:** 16 min
- **Tasks:** 2
- **Files:** 2 created, 0 modified
- **Commits:** 2

## Task commits

| # | Task | Commit | Type |
|---|---|---|---|
| 1 | Run the ablation and commit the metrics JSON | `0b7ad67` | feat |
| 2 | `10-refit-real-evidence.md`, the narrated result | `3fbd2b1` | docs |

## Task 1: the measurement

**The stale `.bench` deletion was performed before the run**, as RESEARCH's runtime-state inventory
requires: `rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench`
ran first, so no stale methodology label from an earlier phase could be transcribed into this
evidence. None of the three existed in this fresh worktree; the command ran anyway.

Run on **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Xcode 26.3 (17C529), Swift 6.2.4, release build,
**10.39 s** wall (`/usr/bin/time -p`).

**`ticks_model_backed == ticks_total == 73129`. 0 decode fallbacks of 73,129.** The bench's
`precondition` was never lowered and never fired. 73,160 bins, 1,025 trials, 96 channels, 32-bin
window, `cursor_bbox_square`, `side_mm` 171.68196243849025, `acq_radius_mm` 2.8613660406415042,
dwell 0.30 s, timeout 5.0 s, `r_acq` 0.5/30 grid units, none relaxed.

### Every arm, recorded verbatim as measured

| Arm | rotation target | `correct` | `bps_n900` | `bps_n64` | `fitts_tp` | `realized_gain` | `realized_smoothing` |
|---|---|---|---|---|---|---|---|
| `raw` | none | **0** | 0.0 | 0.0 | 0.35633985317879746 | 1.0 | 0.5990227782859924 |
| `kalman_only` | none | **0** | 0.0 | 0.0 | 0.35556893592912375 | 0.9235813543578141 | 0.9429371798329478 |
| `refit` | true_track | 70 | 0.4879842326711893 | 0.29834630902994863 | 0.6728824763633123 | 0.9098011600664915 | 0.9238483284881621 |
| `refit_reversed_target` | reversed_track | 2 | 0.013635364916311735 | 0.008336459505647958 | 0.3478549059169072 | 0.8841935821651777 | 0.9001339403308999 |

`incorrect` (Si) is 0 in every arm and that is structural, not measured. Elapsed seconds: `raw` and
`kalman_only` 1440.259999999999, `refit` 1407.7599999999984, `refit_reversed_target`
1439.459999999999.

Both deltas:

| Delta | `bps_n900` | `bps_n64` | `fitts_tp` |
|---|---|---|---|
| `refit_minus_kalman_only` (**the attributable one**) | 0.4879842326711893 | 0.29834630902994863 | 0.3173135404341886 |
| `refit_minus_raw` (**the confounded one**) | 0.4879842326711893 | 0.29834630902994863 | 0.31654262318451487 |
| `refit_minus_reversed` (the attribution control) | 0.47434886775487756 | 0.29000984952430064 | 0.3250275704464051 |

Hits beside the pre-registered recorded-cursor replay reference of **147 of 1,025 trials (14.34
percent)** at radius 2.8613660406415042 mm and dwell 0.30 s: `raw` 0 (0.0000 of the reference),
`kalman_only` 0 (0.0000), `refit` 70 (0.4762), `refit_reversed_target` 2 (0.0136).

### The prompt's table was re-derived, not copied, and it agrees

The orchestrator's prompt supplied a rounded version of this table and asked for any disagreement to
be reported loudly. There is none. Every value reproduces to the digit that was quoted: 73,129
decoded ticks, 0 fallbacks, 1,025 trials, hits 0 / 0 / 70 / 2, `bps_n900` 0.0 / 0.0 / 0.488 / 0.014,
realized gain 1.000 / 0.924 / 0.910 / 0.884, realized smoothing 0.599 / 0.943 / 0.924 / 0.900. The
prompt's 11.8 s is 10-05's first-run wall clock; this run measured 10.39 s on the same machine, which
is run-to-run variation in the same build configuration, not a different result. The emitted JSON is
**byte-identical across two independent runs in this worktree** (`diff` empty), which is the stronger
statement.

### Provenance, checked rather than asserted

| Check | Result |
|---|---|
| `source_sha256` vs `Decoder/manifests/indy_sessions.json` `indy_20160630_01` | **byte-equal**, `2ca8f6b7...03ef6a8` |
| `export_sidecar_sha256` vs `shasum -a 256` of the sidecar | **equal**, `a452ed69...6dec4e3` |
| `encoder_checkpoint_sha256` vs the sidecar's | **equal**, `f95b257bf247...` |
| `velocity_checkpoint_sha256` vs the sidecar's | **equal**, `9d542cb51d4a...` |
| Section-11 top-level key set | 0 missing; 2 beyond it, both named by the plan |
| Arm order and `rotation_target_source` | `raw`/none, `kalman_only`/none, `refit`/true_track, `refit_reversed_target`/reversed_track |
| Every float in the file finite | **yes**, 0 non-finite |
| `grep -c '"passed"'` | **0** (D-09: the artifact carries no verdict) |
| grep for the synthetic re-fit Webgrid figure 10-05 flagged as a guard rail | **0** in both artifacts |
| `ceiling_ref.canonical_hits` / `.trials` vs `10-ceiling.json` | **147 / 1025**, equal |
| Plan's inline verification script | `OK 4 arms, provenance bound, all finite` |

### The hand-adds, and how they were made safe

The bench cannot know three of the things the plan requires, so they were hand-added. Before any
edit, a Python round-trip of the generated file was proven **byte-identical** to the Swift
`JSONEncoder` output (7,109 bytes in, 7,109 bytes out, `==` on the raw bytes), so the diff between
the generated and the committed artifact is provably only the added keys. `diff` confirms exactly
three hunks: `ceiling_ref`, `phase9_bounds`, and the two `env.ticks_*` entries. Nothing else moved.

Every added value was copied field by field from a committed artifact, not typed from memory, and
the script cross-printed the Phase-9 source values it was quoting: pooled held-out velocity R2
0.4237569742298172, this session's 0.14460174271291293 (weakest of four against 0.5046, 0.5069,
0.4797), and the leave-one-session-out co-bps `test_mean_null` mean -0.34980664275259915 with max
-0.12376034887251157, so all four folds are negative.

## Task 2: the narration

443 lines. Eleven sections in the pre-registered order, plus 8b. Every number is transcribed from
`10-refit-real.json`.

**Spot-check, recorded as the acceptance criterion requires.** Twenty values narrated in the prose
were checked back against the committed JSON programmatically, not three. All twenty matched:
`refit`'s `bps_n900` and `bps_n64`, `kalman_only`'s realized gain, `raw`'s realized smoothing, the
reversed arm's `bps_n900`, both Fitts deltas, the ceiling reference's hits and radius, all four
digests, `env.ticks_total`, the synthetic 1.953047884, all three `phase9_bounds` figures, and the
`raw` and `refit` p1 distances. 0 missing.

**Every acceptance grep was run before the commit.** 36 checks, 0 failures, including the ones that
are easiest to get wrong: `verified` never appears on a line carrying `8.5` (0 hits); the unverified
figure RESEARCH Correction 6 struck is absent;
the `4.16` to `8.5` cross-system causal join absent under the plan's own regex; `published
expectation` absent; the four unverified Finding-4 URLs absent; `maximum any decoder`, `perfect
decoder` and `theoretical maximum` all absent. ASCII-only, no em dashes, no smart quotes, no emoji.

**The D-5 requirement was enforced line by line, not just by presence.** Every line carrying the
headline `0.487984` value was checked to carry `counterfactual 30x30 grid score` or `N=64` on the
same line. Five of six failed on the first pass because the label was in the table HEADER rather than
the row, which is exactly the drop the criterion exists to prevent. Every BPS cell in all three
tables now carries its own `(N=900)` or `(N=64)` tag, which is also what 10-PREREGISTRATION section 6
literally requires ("stated immediately beside it, in the same table row"). Re-checked: 6 of 6 OK.

### What the artifact says, in the words that matter

- The zero is the headline for the decode: `raw` and `kalman_only` are the only target-blind arms and
  both are 0 of 1,025.
- The `refit` arm's 70 hits are **target-determined by construction**, and section 7's limitation
  paragraph is reproduced **verbatim**, including the `IntentRotation.swift:75-85` citation, so the
  limit sits beside the number instead of being left for a reader to derive.
- Realized gain spans 0.923581 to 0.884194 across the three filtered arms, a spread of 4.26 percent
  of the largest, so the Willett confound is **measured and ruled out** here rather than assumed
  away. Smoothing does separate: `raw` 0.599023 against `kalman_only` 0.942937, a factor of 1.574.
- On the synthetic before-and-after: `kalman_only` was below `raw` on both synthetic metrics. On real
  data that holds on Fitts TP (0.355569 below 0.356340) and is **undefined on BPS**, because both are
  exactly 0 and a comparison between two floored values carries no information. The artifact says so
  rather than claiming the direction survived.
- The zero is decomposed over the five pre-registered factors with amplitude shrinkage first, and the
  acquisition parameters are recorded as **not relaxed**. Both R2 figures, +0.1446 and 0.1523, are
  carried with the method that produced each and neither is adjusted toward the other.
- Section 15's row is **named** (row A on the literal first column, `hits >= 1` on the `refit` arm)
  and explicitly **not adjudicated**, with both facts that complicate it stated beside it.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] The plan's run command would have taken roughly 20 minutes for an identical result**

- **Found during:** Task 1, before the run.
- **Issue:** the plan's command is a bare `swift run --package-path Packages/CortexDemo
  CortexReplayBench`, which builds and runs debug. 10-05's own closing note records debug as roughly
  two orders of magnitude slower over the 224 million `SpikeInputBuffer.write` calls this bench makes.
- **Fix:** `-c release` on both the build and the run. The runbook in the evidence artifact carries
  `-c release` and a one-line note explaining why, so the published command is the one that was run.
- **Why this is safe:** the numbers are not timing-sensitive. The emitted JSON was verified
  byte-identical across two independent release runs, and every value reproduces 10-05's independent
  run of the same bench.
- **Files:** none (a command-line change, recorded in the runbook)
- **Committed in:** `3fbd2b1` (the runbook)

**2. [Rule 2 - Missing critical] `ticks_model_backed` and `ticks_total` were not in the emitted JSON**

- **Found during:** Task 1, checking the emitted schema against the pre-registration.
- **Issue:** 10-PREREGISTRATION section 10 requires in writing that "every real-data run counts
  `decodedByModel` per tick and **commits `ticks_model_backed` and `ticks_total` in its JSON**". The
  bench emits `env.ticks` and enforces equality with a `precondition`, but neither named key is in
  the file. Section 11's top-level key list for this artifact does not include them either, so the two
  sections are in tension.
- **Fix:** both keys were added **inside `env`**, where they equal the already-emitted `env.ticks`
  (73129). Section 10's requirement is now literally checkable in the artifact, and the section-11
  **top-level** key set is unchanged.
- **Why not the alternative:** adding them at the top level would have put two more keys beyond
  section 11's pinned list, and fixing it in the bench source was out of bounds
  (`Packages/CortexDemo/` belongs to the concurrently-running Plan 10-06).
- **Files:** `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json`
- **Committed in:** `0b7ad67`

**3. [Rule 2 - Missing critical] `ceiling_ref`'s key name imports the framing section 16 rejected**

- **Found during:** Task 1, writing the hand-add.
- **Issue:** the plan directs a `ceiling_ref` key. 10-PREREGISTRATION section 11 states that
  `ceiling_ref` is deliberately **not** emitted in `10-replay.json` "because the ceiling framing was
  rejected", and section 16 says the framing that this reference is what any decoder could at best
  achieve "must not appear in any Phase 10 artifact". A bare key named `ceiling_ref` carries that
  framing in its name.
- **Fix:** the object carries a `note` stating what the reference is (the hit rate from replaying the
  animal's own recorded cursor under one acceptance rule) and what it is not (a bound on what a
  decoder can achieve), and recording that the key name mirrors a filename that predates the framing
  decision while `10-replay.json` names the same quantity `replay_reference_hits`.
- **Files:** `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json`
- **Committed in:** `0b7ad67`

**4. [Rule 1 - Bug] The pre-registered `CortexReFITBench/main.swift:283-285` citation no longer resolves**

- **Found during:** Task 2, writing the structural-Si ground of the non-comparability disclosure.
- **Issue:** at HEAD, `:283-285` points at `endpointOnAxis`, `effectiveDistance` and `trial`, not at
  the structurally-zero comment, which sits at `:286-288`. Publishing the registered citation
  unchanged would have shipped a reference a reader cannot follow.
- **Fix:** checked out `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` at `a72344b`, the
  pre-registration commit, and confirmed `:283-285` **was** exactly the structural-Si comment there.
  Plan 10-05 removed a three-line `let source` block earlier in the same file, shifting it by three.
  The evidence carries both forms and says which commit each resolves against.
- **Why not just correct it:** the pre-registration is a frozen contract and its citation was correct
  when registered. Silently replacing it would hide that the code moved.
- **Files:** `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md`
- **Committed in:** `3fbd2b1`

**Total: 4 auto-fixed (1 blocking, 2 missing-critical, 1 bug). No Rule 4 escalation, no fix-limit
escalation, no auth gate, no checkpoint.**

### Deliberately not done

- **`references.note` was not hand-edited.** The plan lists it as one of three hand-adds, but the
  bench already emits a `references.note` naming each external figure's condition (the dense 9x9
  grid for 4.16, the 6x6 figures beside it, the D-17 status and the 2026-09-05 "over 10 BPS" wording
  for 8.5, and the three non-comparability grounds). Rewriting a correct generated string by hand
  would have introduced a transcription risk for no gain. Verified by reading it; quoted in this
  summary's verification table.
- **The quantitative decoded-to-true velocity amplitude ratio was not measured.** The evidence states
  the shrinkage mechanism qualitatively with attribution to the pre-execution measurement recorded in
  10-PREREGISTRATION section 14, and points at `10-replay.json`'s
  `decomposition.velocity_amplitude_shrinkage` for the mean and p95 ratio, which section 14 assigns to
  a later plan. Manufacturing a number here would have needed a new decode path and a new provenance
  chain that this plan does not own.
- **`Packages/CortexDemo/`, `Apps/CortexDaemon/` and `.github/workflows/ci.yml` were not touched.**
  Plan 10-06 owns them concurrently. `git diff` over `Packages/` for this plan is empty; the bench was
  run, never edited.
- **STATE.md and ROADMAP.md were not updated**, per the objective. The orchestrator owns those writes.
- **No number was tuned toward a magnitude, and no acquisition parameter was relaxed.**

## Notes for later plans

- **10-09 (the schema gate):** `10-refit-real.json`'s top-level key set is now section 11's fifteen
  keys **plus two**, `ceiling_ref` and `phase9_bounds`, both directed by Plan 10-07's task text and
  both asserted present by its verification script. 10-05's note that a schema test could bind with
  "0 missing and 0 extra" is no longer true of the committed file; bind to "0 missing" and an
  allow-list of those two. The section-10 counts are at `env.ticks_model_backed` and `env.ticks_total`,
  not at the top level.
- **10-09 and 10-10 (SC#2):** this artifact deliberately does **not** adjudicate SC#2. It names
  section 15's row on the literal first column (row A, because the `refit` arm's count is 70) and
  records the two facts that complicate that reading: the refit arm's heading is target-determined,
  and both target-blind arms are 0 of 1,025, which is row B's shape. The adjudication belongs to
  `10-replay.json`'s `sc2_disposition` and to the user at Plan 10-10 Task 3.
- **10-11 (`WebgridBPS.swift`'s doc comment):** the long-form non-comparability disclosure is written
  out in section 5 of the evidence with all four grounds and their citations. Reuse it verbatim. The
  structural-Si citation must be given as `:283-285` at `a72344b` **and** `:286-288` at HEAD.
- **10-12 (the README headline, D-12):** the real-data headline attributable to the decode is
  **0.000000 BPS** on both normalisations, with 1.953 preserved beside it and labeled synthetic. The
  `refit` arm's 0.487984 is not a decoding result and must not become the headline.
- **10-14 (`honesty-sweep.sh`):** the canonical short-form non-comparability line from
  10-PREREGISTRATION section 12 is present verbatim in section 5 of the evidence, as a single
  unwrapped line inside a fenced block, so byte identity is checkable.
- **Anyone re-running this:** `Decoder/{data,exports,checkpoints}` must be real directories holding
  symlinks, never bare symlinks, or `git status` goes dirty. Use `-c release`.

## Known Stubs

None. This plan created two data artifacts and no code. No hardcoded empty value, no placeholder
text, and no unwired component was introduced. The two zero-valued fallbacks 10-05 recorded in
`CortexReplayBench` are unchanged and were not reachable on this run (0 decode failures of 73,129).

The zeros in the published table are **measured results**, not stubs: `raw` and `kalman_only` scored
0 hits, so their `bps_n900` and `bps_n64` are legitimately 0.0. They are the finding.

## Threat Flags

None. This plan created no network endpoint, no auth path, no file-access pattern and no schema
change at a trust boundary. The two artifacts are read-only committed data. The plan's own STRIDE
register (T-10-07-01 through T-10-07-06) is fully mitigated:

| Threat | Mitigation, executed |
|---|---|
| T-10-07-01 repudiation of unbound numbers | all four digests checked and recorded above |
| T-10-07-02 synthetic under a real label | `ticks_model_backed == ticks_total == 73129`, 0 fallbacks, the `precondition` never lowered |
| T-10-07-03 relaxed parameters after a bad result | radius, dwell and timeout read from the export sidecar, unchanged, recorded as not relaxed in the evidence; the ceiling is an older committed artifact |
| T-10-07-04 a real result reddening the build | `grep -c '"passed"'` = 0; the Phase-7 `refit_bps.json` and Phase-8 `webgrid_bps.json` fixtures both `diff` clean after a fresh `--smoke` |
| T-10-07-05 a bare external benchmark | acceptance greps for `dense 9x9` beside `4.16`, `over 10 BPS` and the 2026-09-05 date beside `8.5`, no unverified struck figure, no causal join, all pass |
| T-10-07-06 a stale `.bench` transcribed | all three `.bench` directories deleted before the run |

## Verification

Every command run in this worktree on **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Xcode 26.3,
Swift 6.2.4.

| Command | Result |
|---|---|
| `rm -rf Packages/{CortexReFIT,CortexDemo,CortexDecoder}/.bench` | done before the run; none existed |
| `swift build -c release ... --product CortexReplayBench` | **exit 0**, 8.94 s |
| `CortexReplayBench --out <phase dir>/10-refit-real.json` | **exit 0**, 73,129 ticks, **0 fallbacks**, 10.39 s |
| Second run to a scratch path, then `diff` | **byte-identical** |
| The plan's inline Task-1 verification script | `OK 4 arms, provenance bound, all finite` |
| `shasum -a 256 Decoder/exports/indy_20160630_01.replay.json` | `a452ed69...6dec4e3`, equals `export_sidecar_sha256` |
| `source_sha256` vs the manifest entry | **byte-equal** |
| `python3 -c "import json;json.load(...)"` on the artifact | parses |
| `grep -c '"passed"'` on the artifact | **0** |
| `swift test --package-path Packages/CortexDemo` | **33 tests in 4 suites passed** |
| `CortexReFITBench --smoke` | **exit 0** |
| `diff .bench/refit_bps.json <Phase-7 committed>` | **empty**, exit 0 |
| `diff .bench/webgrid_bps.json <Phase-8 committed>` | **empty**, exit 0 |
| 36 evidence acceptance greps (at-least / exactly) | **0 failures** |
| D-5 per-line headline-label check | **6 of 6 OK** after the row-tag fix |
| 20-value spot-check of prose against the JSON | **0 missing** |
| `wc -l` on the evidence | **443** (>= 160) |
| ASCII-only / no em dash / no smart quote / no emoji | **clean** |
| `git status --short` | clean; nothing from `Decoder/{data,exports,checkpoints}` or `.bench/` |

### What was NOT run, and why

- **`readme-policy.sh` and `honesty-sweep.sh`.** This plan touches neither the README nor
  `docs/cortex-spec.md`; those gates are Plans 10-12 and 10-14. Noted for them: this artifact's
  section 5 already contains the section-12 canonical line verbatim.
- **The `slow` Decoder pytest set and `uv sync`.** No Python ran in this measurement's loop. The
  Python provenance quoted in the evidence is read from the artifacts the Python stages emitted
  (`indy_20160630_01.replay.json` `env` and `09-decoder-metrics.json` `velocity.env`), which is the
  authoritative record for the bytes this run consumed.
- **The repo-wide `swiftformat --strict` sweep.** D-18 work in a later plan, and this plan changed no
  Swift.
- **Any iPad-M4 or device measurement.** Every number here is an M5 Pro number, labeled
  `corroborating` in the emitted JSON and in the evidence.

## Self-Check: PASSED

Files claimed as created, both confirmed present on disk:

- `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real.json` (169 lines; `wc -l`
  reports 168 because the Swift `JSONEncoder` writes no trailing newline)
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md` (443 lines)

Commits claimed, both resolving as commit objects on top of the expected base
`b74c4ac0be51cc097203c88304125e04bb91498a`: `0b7ad67`, `3fbd2b1`. `git merge-base HEAD b53bd20`
returns `b53bd20`.

The load-bearing claims were executed, not asserted. The ablation was run twice and the two outputs
`diff` clean. The Python round-trip used for the hand-edit was proven byte-identical to the Swift
encoder output before it was used, and `diff` between the generated and committed artifact shows only
the three intended hunks. All four provenance digests were compared against their sources in code,
not read by eye. The drifted `CortexReFITBench` line citation was confirmed against the file as it
stood at `a72344b`. Twenty narrated numbers were matched back to the committed JSON by script.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
