---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 09
subsystem: ci
tags: [ci, provenance, gate, self-test, schema, uv, github-actions, rd-01, rd-03, rd-04, rd-05, rd-06]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 03
    provides: "Decoder/manifests/indy_sessions.json with four verified sha256 entries, zero PENDING"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06d
    provides: "09-decoder-metrics.json co_bps, loso, config and sessions sections"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 07
    provides: "09-decoder-metrics.json velocity section with the lag and lambda sweeps"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 08
    provides: "09-decoder-metrics.json palettization, ane and latency sections, and scikit-learn as a real dependency the CI sync must pick up"
provides:
  - "Tools/scripts/decoder-policy.sh: the D-19 gate tying every published decoder number to the manifest bytes it came from, with a four-case --self-test that proves a clean tree passes and all three assertions bite"
  - "Tools/scripts/check_decoder_provenance.py: the stdlib-only bare-python3 (id, sha256) set comparison across manifest and metrics, which no grep can do"
  - "Decoder/tests/test_metrics_schema.py: 10 quick tests over the committed metrics artifact, gating shape and provenance and nothing measured, with a source self-check that enforces that rule on itself"
  - ".github/workflows/ci.yml decoder-python job: the first blocking CI coverage the 3,582-line Python subsystem has ever had"
  - "The measured finding that the committed slow co-bps gate is GREEN at HEAD (0.679732 in 14m10s), so 09-06c's divergence premise is closed by 09-06d's loss stabilizer"
  - "The quantified diagnosis of what remains wrong with that gate: its held-out split is 52% of one session plus 100% of another, not the four chronological tails the 0.054 margin was derived from"
affects: [09-10, 09-11, Phase 10, RD-01, RD-03, RD-04, RD-05, RD-06]

# Tech tracking
tech-stack:
  added: ["astral-sh/setup-uv@v10.0.1 (GitHub Actions, uv install plus its own cache save/restore)"]
  patterns:
    - "Make the negative control prove the CLEAN case too: a gate that always fails is as useless as one that never does, so case 0 of every self-test is a clean synthetic tree that must exit 0"
    - "Isolate one leg per negative-control case by keeping the mutation well-formed: the perturbed checksum is still 64 lowercase hex, so it satisfies the regex leg and only the set comparison can catch it"
    - "Split the gate by what a regex can and cannot see: token presence stays in the shell script, agreement between two files goes to a stdlib-only helper"
    - "Enforce a testing rule on the test module itself with a source self-check, splitting the file at a marker so the guard is not scanned by its own patterns"
    - "Write the gate so the honest path stays green: allow a declared exclusion, do not pin the epoch count, and assert the LINKED invariant (a non-iPad device may not be labeled canonical) rather than a literal status string a future measurement will legitimately change"
    - "Verify the no-dataset claim literally by moving Decoder/data and Decoder/checkpoints aside and re-running, rather than asserting it from reading the tests"

key-files:
  created:
    - Tools/scripts/decoder-policy.sh
    - Tools/scripts/check_decoder_provenance.py
    - Decoder/tests/test_metrics_schema.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-09.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-09-SUMMARY.md
  modified:
    - .github/workflows/ci.yml

key-decisions:
  - "setup-uv is pinned at v10.0.1, not the plan's and the research's @v8: this publisher ships no floating major tags, so refs/tags/v8, v9 and v10 all 404 and the specified workflow would have failed at action resolution. Both inputs whose defaults changed since v8 are set explicitly"
  - "The slow co-bps gate was RUN before deciding about it, and it passes: 09-06c's recommendation was written before the 09-06d stabilizer landed, and the divergence half of its diagnosis is now closed. The margin was not lowered, raised, or touched"
  - "The stability gate 09-06c recommended extracting already exists inside test_heldout_cobps.py as its two ordered did-it-train assertions, so extracting it would move code without adding an assertion"
  - "test_heldout_cobps.py was NOT edited: this plan's files are two gate scripts, a test module and ci.yml, and changing a decoder training path would put a second variable into a CI-wiring plan"
  - "The palettization schema test asserts presence and model labels only, taking no position on which package ships, because that is an open decision from 09-08 that this gate must not silently answer"
  - "A manifest session missing from the metrics is allowed when named under excluded_sessions, so an honest exclusion does not have to lie to pass; with no exclusions that reduces to the set equality the plan specified"

patterns-established:
  - "Before writing a gate that asserts a threshold, check whether the number it reads was produced by the same path: 0.679732 and 0.4096 are both real held-out co-bps values and they are not the same quantity"
  - "Resolve an action pin against the publisher's actual refs rather than trusting the convention that floating major tags exist"

requirements-completed: [RD-01, RD-03, RD-04, RD-05, RD-06]

# Metrics
duration: about 30m
completed: 2026-09-03
---

# Phase 9 Plan 09: the provenance gate and the Python subsystem's first CI job Summary

**Every number this phase publishes is now structurally tied to the bytes it was measured on, and
the 3,582 lines of Python that produced them run in CI for the first time. `decoder-policy.sh`
asserts zero PENDING checksums, a declared `data_source`, and set-equality of the (id, sha256)
pairs across the manifest and the metrics, and its `--self-test` proves a clean tree passes while
each of the three assertions bites. A new `decoder-python` job on `macos-15` runs the sync, ruff,
the 208-test quick suite, a proof that `Decoder/data/` was empty while it ran, and both gate
invocations. Separately, the slow co-bps gate that Plan 09-06c handed to this plan as a red test
was measured rather than assumed: it is GREEN at HEAD, 0.679732 in 14m10s, because 09-06d's
linearized Poisson NLL turns the excursion that used to produce `nan` into a large finite loss the
model recovers from, twice in twelve epochs. Its margin was not touched. What remains wrong with
it was quantified instead: its held-out split is 52% of one session plus 100% of another, so it
asserts a headline-path margin against a different generalization task.**

## Performance

- **Duration:** about 30 minutes, of which 14 minutes was the slow-gate measurement
- **Tasks:** 3 of 3
- **Files:** 5 created, 1 modified
- **Commits:** 4 (3 task commits plus this metadata commit)

## Accomplishments

### The provenance gate, and what makes its self-test a real negative control

`Tools/scripts/decoder-policy.sh` (266 lines) is structurally the Phase-8 `bps-policy.sh`:
env-overridable scope, a `require_re_in_file` helper, a `scan` that accumulates `rc`, a `SELF` path
so the self-test can re-invoke the gate with a repointed scope, and the same `PASS [` / `SELF-TEST
OK` output shape. Its three assertions:

| Leg | Assertion | Why it exists |
|---|---|---|
| (a) no-pending | zero `"PENDING"` lines in `indy_sessions.json` | an unverified session pins nothing, so a number attributed to it is unprovenanced (D-19a, RD-01a) |
| (b) declared | the metrics carry `data_source`, a `sessions` array, and at least one 64-lowercase-hex `sha256` | a number that does not say what data produced it is not traceable, and a placeholder checksum must not satisfy the grep (D-19b) |
| (c) agreement | the (id, sha256) pairs agree across the two files | a well-formed checksum that is simply the WRONG one is invisible to any regex over either file alone (D-19c) |

The self-test's four cases each mutate exactly one thing relative to a clean synthetic pair:

```
== decoder-policy self-test ==
  PASS [clean tree] exit=0 (expected 0)
  PASS [reintroduce a PENDING sha256] exit=1 (expected 1)
  PASS [strip data_source] exit=1 (expected 1)
  PASS [perturb one metrics checksum] exit=1 (expected 1)
SELF-TEST OK
```

Case 3 is the one that carries the design. The perturbed digest is 64 lowercase `c` characters, so
it passes leg (b)'s regex unchanged, and only the set comparison in leg (c) can catch it. A case
that used an obviously malformed value would have been caught by leg (b) and would have proven
nothing about leg (c).

Case 0 matters for the opposite reason. A gate that always exits 1 satisfies every negative control
and gates nothing; the clean-tree case is what rules that out.

### The leg that cannot be a grep

`Tools/scripts/check_decoder_provenance.py` (230 lines) is stdlib-only and runs under the runner's
preinstalled `python3` with no uv environment, mirroring `check_refit_uplift.py` exactly: `main(argv)
-> int`, `raise SystemExit(main(sys.argv))`, every failure mode caught by its specific type
(`json.JSONDecodeError`, `OSError`), and no bare or blind `except`. It reports the offending pair by
name:

```
ERROR: session 'x' checksum disagrees -- metrics ccccccccccccc...d vs manifest aaaaaaaa...a
```

All eight of its failure modes were exercised by hand before it was wired into the gate: clean pair,
PENDING checksum, missing `data_source`, perturbed checksum, an undeclared missing session, a
declared exclusion (which passes), malformed JSON, and a wrong argument count.

### The metrics artifact's contract

`Decoder/tests/test_metrics_schema.py` adds 10 quick tests over the committed
`09-decoder-metrics.json`. They cover the RD-03c checksum agreement, RD-04a per-session co-bps
coverage, the RD-04b four-fold LOSO rotation with unique held-out sessions and a summarized spread,
RD-05b's two palettization legs each carrying its own `model` label and delta, the ANE section's
`real-data` provenance string, the device-labeled latency, the training knobs, and the velocity
section's lag and lambda sweeps.

Fifteen negative controls were run by hand, each mutating the committed JSON, running the test,
and restoring the file byte-for-byte. Every one turned the intended test red:

| Mutation | Test that went red |
|---|---|
| drop one session from `co_bps.per_session` | `test_per_session_cobps_covers_every_session` |
| truncate `loso` to 3 folds | `test_loso_is_a_full_rotation` |
| repeat a `held_out_session` across folds | `test_loso_is_a_full_rotation` |
| delete `shipped_model.model` | `test_palettization_reports_both_models` |
| delete `reconstruction_model.nll_delta` | `test_palettization_reports_both_models` |
| delete `shipped_model.r2_delta` | `test_palettization_reports_both_models` |
| set `velocity_head_palettized` true | `test_palettization_reports_both_models` |
| drop one session from `velocity.per_session` | `test_velocity_section_is_complete` |
| truncate the lag sweep to 4 points | `test_velocity_section_is_complete` |
| rewrite `ane.provenance` as random-init | `test_ane_section_records_measurement_not_assumption` |
| label the Mac latency `canonical` | `test_latency_is_device_labeled_and_corroborating` |
| perturb a session checksum | `test_session_ids_and_checksums_match_the_manifest` |
| publish `real-smoke` as the headline | `test_metrics_json_parses_and_declares_provenance` |
| change the seed to 1 | `test_config_records_the_training_knobs` |
| inject `assert metrics["co_bps"]...> 0.054` | `test_no_number_is_a_measured_threshold_assertion` |

The last one is the module policing itself. It reported the offending line verbatim:

```
E  assert not [(308, 'assert metrics["co_bps"]["pooled"]["train_null"] > 0.054', 'co_bps.*>')]
```

### The CI job, and the empty-dataset proof done literally

The `decoder-python` job is a sibling of `build-and-lint`, not a step inside it: that job is already
near its 30-minute timeout with the Rust toolchain, SwiftPM, DerivedData and seven policy gates, and
the Python suite shares none of it.

The plan's hard requirement was that every CI-blocking test pass on a checkout with an empty
`Decoder/data/` and no checkpoints. That was verified literally, by moving both gitignored
directories out of the repo and re-running, not by reading the tests:

```
=== dataset + checkpoints absent ===
ls: Decoder/checkpoints: No such file or directory
ls: Decoder/data: No such file or directory
ruff:            All checks passed!
quick suite:     207 passed, 1 skipped, 9 deselected in 3.35s
                 SKIPPED test_data.py:157: no loadable real .mat present (dataset is gitignored)
empty-data step: OK  (exit 0)
decoder-policy:  exit 0
--self-test:     exit 0
schema module:   10 passed
```

The single skip is a clean, intentional one. The empty-data step was also shown to BITE: with a
`leaked.mat` planted in `Decoder/data/`, it exits 1 with the intended message. Both directories were
restored and the tree verified clean afterward.

`actionlint` reports the whole workflow clean.

### The slow co-bps gate: measured, then decided

Plan 09-06c delegated a decision about
`test_heldout_cobps.py::test_heldout_cobps_beats_mean_rate_null` to this plan, describing it as red
and diverging. That premise was checked rather than inherited, because 09-06d's loss stabilizer
landed after 09-06c's write-up and 09-06d deliberately did not re-run this gate.

```
uv run --project Decoder pytest Decoder/tests/test_heldout_cobps.py -m slow -q
1 passed in 850.93s (0:14:10)
held_out_co_bps 0.679732 against the asserted margin 0.054
```

The per-epoch loss shows why it now finishes, and shows that the stabilizer is not sitting idle:

```
0.598218 0.587946 0.582616 18128.334631 0.580501 0.578968
0.576679 0.575874 0.575050 27949.680435 0.574470 0.573794
```

Epochs 4 and 10 are four orders of magnitude above their neighbours and the model recovers from
both. That is exactly what `stable_exp` was built for: the same log-rate excursion that produced
`nan` under 09-06c now produces a large finite loss with a finite, correctly-signed gradient. The
`all(math.isfinite(...))` assertion already in the test is doing real work on this data.

**The margin stays at 0.054.** It is cleared 12.6x, so there is no pressure to move it in either
direction. It was re-derived upward from 0.0094 by a rule that has now gone unchanged through four
derivations, and nothing here changes the rule or the observation it reads.

What remains wrong with the gate was quantified rather than assumed. Of 09-06c's two complaints,
the cross-session window fabrication turns out to be negligible (3 straddling windows out of 8,917,
0.034%), while the split composition is the real defect:

| split | composition |
|---|---|
| train | all of indy_20160624_03, all of indy_20160627_01, the first 48.0% of indy_20160630_01 |
| test | the last 52.0% of indy_20160630_01, and 100% of indy_20160915_01 |

The model never sees a bin of `indy_20160915_01`, so the gate's number mixes a within-session
temporal holdout with a full cross-session transfer, scored against a null estimated without that
session. The headline path holds out the last 20% of every session: 7,132 / 1,782 windows against
the gate's 7,133 / 1,783, so this is a composition difference and not a budget difference. That is
why a 12-epoch model scores 0.679732 where the 200-epoch headline scores 0.4096: a per-channel mean
rate estimated without a session is a weak null on that session. The repair is in
`deferred-items-09-09.md` item 2, and it belongs to a plan whose files include the decoder training
path.

**0.679732 is recorded as the evidence behind a decision, not as a published number.** The phase's
held-out co-bps remains 0.4096 on the D-12 path.

## Task Commits

| Task | Name | Commit | Files |
|---|---|---|---|
| 1 | decoder-policy.sh + check_decoder_provenance.py with a four-case self-test | `5dcf816` | `Tools/scripts/decoder-policy.sh`, `Tools/scripts/check_decoder_provenance.py` |
| 2 | test_metrics_schema.py, the committed artifact's contract | `1e6b7df` | `Decoder/tests/test_metrics_schema.py` |
| 3 | the decoder-python CI job (D-18, RD-06c) | `288910a` | `.github/workflows/ci.yml` |

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] `astral-sh/setup-uv@v8` does not resolve**

- **Found during:** Task 3
- **Issue:** The plan and `09-RESEARCH` section 11 both specify `astral-sh/setup-uv@v8`. That ref
  does not exist. The publisher ships full semver tags only; `refs/tags/v8`, `refs/tags/v9` and
  `refs/tags/v10` all return 404. A workflow pinned at `@v8` fails at action resolution before the
  job starts, so the job as specified would never have run.
- **Fix:** Pinned `@v10.0.1`, the latest tag that resolves, per the plan's own fallback rule.
  `action.yml` at that tag was fetched and confirmed to accept all four inputs the plan uses
  (`enable-cache`, `cache-dependency-glob`, `cache-suffix`, `prune-cache`). Both inputs whose
  defaults changed between v8 and v10 are set explicitly in the job, so v10's two breaking changes
  (`enable-cache: auto` now disables the cache for `pull_request_target` / `workflow_run` /
  `release`; `prune-cache` now defaults to false) do not apply. The substitution and its reasoning
  are in the job's comment block, not silent.
- **Files modified:** `.github/workflows/ci.yml`
- **Commit:** `288910a`

**2. [Rule 2 - Missing correctness] A declared exclusion must not have to lie to pass**

- **Found during:** Task 1
- **Issue:** The plan specifies that the metrics and manifest session id sets be equal. The metrics
  JSON already carries an `excluded_sessions` array, written by `train_real.py` because
  `available_sessions` legitimately skips a session that is absent or too short. Strict equality
  would fail a fully honest artifact that recorded such an exclusion, which is the same class of
  gate the plan itself warns against for the epoch count.
- **Fix:** A manifest session missing from `metrics.sessions` is accepted only when it is named in
  `metrics.excluded_sessions`. With no exclusions, which is the committed case, this reduces exactly
  to the set equality the plan specified, and the self-test's checksum case is unaffected.
- **Files modified:** `Tools/scripts/check_decoder_provenance.py`, `Decoder/tests/test_metrics_schema.py`
- **Commits:** `5dcf816`, `1e6b7df`

**3. [Rule 2 - Missing correctness] The latency test asserts the linked invariant, not a literal status**

- **Found during:** Task 2
- **Issue:** The plan specifies `latency.status == "corroborating"`. D-17 and Plan 09-11 schedule an
  optional iPad-M4 capture in this same phase; if it happens, the honest artifact's status becomes
  canonical and a literal pin would go red on correct data.
- **Fix:** The test asserts what D-17 actually requires: `status` is one of the two allowed labels,
  `canonical` names the iPad capture, and a device that does not name an iPad may not be labeled
  canonical. On today's artifact that resolves to `status == "corroborating"`, so it asserts exactly
  what the plan asked for, and it survives an honest iPad capture instead of forbidding one.
- **Files modified:** `Decoder/tests/test_metrics_schema.py`
- **Commit:** `1e6b7df`

### Non-issue deviations

**4. One test renamed.** The plan names a test `test_config_is_the_phase4_budget`. The committed
config is not the Phase-4 budget (200 epochs against Phase 4's 12), and the plan itself forbids
asserting the epoch count, so that name would have labeled the test with a claim it does not check.
It is `test_config_records_the_training_knobs`, which is what it does. None of the acceptance greps
reference the old name.

**5. Ten tests, not the specified nine.** The plan lists ten assertions; all ten were implemented.
`grep -c 'def test_'` returns 11 because the guard test contains the string
`"def test_palettization_reports_both_models"` as a literal in its own sanity check.

**6. ASCII prose in files that copy a non-ASCII template.** `bps-policy.sh` uses box-drawing rules
and em dashes in its comment banners. Both new scripts copy its structure but keep to ASCII per the
project writing rule; both files are verified 0 non-ASCII bytes.

## Issues Encountered

**The slow gate took 14 minutes and had to be run to answer the question honestly.** The alternative
was to accept 09-06c's description of it as red, which was written before the fix that made it
green. The measurement changed the decision: what looked like "the gate cannot finish training"
turned out to be a closed problem, and the open problem turned out to be a different one that
09-06c's write-up mentioned second.

**No other issues.** All three tasks executed as planned, with the deviations above.

## Deferred Items

Seven items in `deferred-items-09-09.md`:

1. The slow co-bps gate is green; its full trajectory, environment and the decision are recorded there.
2. The gate still asserts a headline-path margin against a different generalization task; the repair is specified and belongs to a plan that owns the decoder training path.
3. `09-RESEARCH.md` still carries the unusable `@v8` snippet at lines 751, 790 and 1021.
4. The new job pins an action by tag, which is mutable; SHA pinning would be a repo-wide convention change.
5. coremltools 9.0 prints two version warnings on every import, now on every CI run; neither is a failure and the sklearn one is easy to misread.
6. The Swift `--strict` lint gate remains unexercised; the new job is Python-only by design and pulls in none of it.
7. `09-VALIDATION.md` rows RD-01a, RD-03c, RD-04a, RD-04b, RD-05b and RD-06c are still marked pending.

## Known Stubs

None. Every assertion in all three new files runs against the real committed artifacts; nothing is
hardcoded, mocked, or awaiting a data source.

## Threat Flags

None. Nothing here adds a network endpoint, an auth path, a file-access pattern or a schema change
at a trust boundary. The one new external dependency, `astral-sh/setup-uv`, is the third-party
action T-09-09-05 already covers, and it is pinned to an exact tag from the official publisher; the
residual tag-versus-SHA question is deferred item 4 rather than a new surface.

## Verification

```
./Tools/scripts/decoder-policy.sh                                   exit 0
./Tools/scripts/decoder-policy.sh --self-test                       exit 0, 4 PASS lines
python3 Tools/scripts/check_decoder_provenance.py <manifest> <metrics>   exit 0
uv sync --project Decoder --extra dev                               ok
uv run --project Decoder ruff check Decoder                         All checks passed!
uv run --project Decoder pytest Decoder/tests -m "not slow" -q      208 passed, 9 deselected
grep -cE '^  decoder-python:$' .github/workflows/ci.yml             1
grep -cE '^  build-and-lint:$' .github/workflows/ci.yml             1 (unchanged)
git diff --numstat .github/workflows/ci.yml                         70 additions, 0 deletions
actionlint .github/workflows/ci.yml                                 clean
```

With `Decoder/data/` and `Decoder/checkpoints/` moved out of the repo: ruff clean, 207 passed with
1 clean skip, the empty-data step exits 0 (and exits 1 when a file is planted), and both gate
invocations exit 0.

Negative controls: 4 in the shell self-test, 8 by hand against the python helper, 15 by hand against
the schema module, and 1 against the empty-data CI step. Every one bites.

## Next Phase Readiness

D-18 and D-19 are both closed. The Python subsystem has blocking CI coverage for the first time, and
every number in `09-decoder-metrics.json` is now tied to the manifest bytes it came from by a gate
that has been shown to bite.

Two things a following plan should pick up. First, the slow gate's split composition (deferred item
2): repointing `_load_binned()` at `ndt1.sessions.pooled_splits` and adding the reproduction check
against the committed 0.40956884089908474 would make the gate assert the quantity its margin was
derived from. Second, the open decision from 09-08 about which package ships is untouched here by
design; the schema test asserts both palettization legs are reported with their model labels and
takes no position on the answer.

## Status rationale

PARTIAL, not PASS. All three tasks executed, committed and verified green, and every success
criterion in the plan is met. The status reflects seven deferred items, one of which (the slow
gate's split composition) is a real open defect in a committed test that this plan diagnosed and
quantified but is not scoped to repair.

## Self-Check: PASSED

All six files claimed above exist on disk:

```
FOUND: Tools/scripts/decoder-policy.sh
FOUND: Tools/scripts/check_decoder_provenance.py
FOUND: Decoder/tests/test_metrics_schema.py
FOUND: .planning/phases/09-.../deferred-items-09-09.md
FOUND: .planning/phases/09-.../09-09-SUMMARY.md
FOUND: .github/workflows/ci.yml
```

All three task commits exist in the repository:

```
FOUND: 5dcf816   FOUND: 1e6b7df   FOUND: 288910a
```

Every measured value quoted in this summary was produced by a command run in this session and is
reproducible from the runbooks above. The 0.679732 slow-gate figure is labeled with the path that
produced it and is explicitly not presented as this phase's held-out co-bps.
