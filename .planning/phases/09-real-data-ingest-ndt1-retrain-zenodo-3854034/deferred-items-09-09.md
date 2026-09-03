# Plan 09-09 deferred items

Out-of-scope discoveries from the D-19 provenance gate and the D-18 `decoder-python` CI job.
Logged, not fixed. Written to a plan-scoped file for the same reason 09-06, 09-06b, 09-06c and
09-08 were: a shared append caused an add/add conflict earlier in this phase.

## 1. The committed slow co-bps gate is GREEN, and the recommendation it was handed is half stale

`Decoder/tests/test_heldout_cobps.py::test_heldout_cobps_beats_mean_rate_null` was handed to this
plan by `deferred-items-09-06c.md` item 2 as a red test with two tangled problems. It was measured
rather than assumed, and one of the two is closed.

Run at HEAD 288910a on Apple M5 Pro, macOS-26.5-arm64, python 3.12.13, numpy 2.4.6, torch 2.12.1,
seed 0, the committed 12-epoch configuration, real sessions:

```
uv run --project Decoder pytest Decoder/tests/test_heldout_cobps.py -m slow -q
1 passed in 850.93s (0:14:10)
```

| | 09-06b (no clipping) | 09-06c (clip 1.0) | now (09-06d stabilizer) |
|---|---|---|---|
| outcome | finite, never recovers | `nan` from epoch 4 | passes |
| held-out co-bps | not reached | not reached | 0.679732 |

Per-epoch loss, all 12 epochs finite:

```
0.598218 0.587946 0.582616 18128.334631 0.580501 0.578968
0.576679 0.575874 0.575050 27949.680435 0.574470 0.573794
```

Two observations, both of which matter more than the pass:

**The linearized Poisson NLL is not an inert safety net on this path; it BINDS, twice.** Epochs 4
and 10 are three to four orders of magnitude above the surrounding epochs and the model recovers
from both. That is exactly the designed behaviour of 09-06d's `stable_exp`: the same excursion that
produced `nan` under 09-06c now produces a large finite loss with a finite, correctly-signed
gradient. The test's `all(math.isfinite(...))` assertion is doing real work on this data, not
standing by.

**The observed 0.679732 is not the same quantity as the committed 0.4096, and the gap is the
gate's real remaining defect.** See item 2.

**Decision, which is this plan's answer to the question 09-06c delegated:**

- The margin stays at **0.054**. It is cleared 12.6x by the observation above, so there is no
  pressure to move it in either direction, and it was re-derived upward from 0.0094 by a rule that
  has now gone unchanged through four derivations.
- The **stability gate** 09-06c recommended extracting already exists inside this test. Its two
  "did it train" assertions (finite, and final loss below the first) are ordered ahead of the
  co-bps assertion precisely so a diverged run reports the divergence, and they are what would
  have caught every divergence in this phase. Extracting them into a separate module would move
  code without adding an assertion.
- The **reproduction check** is still owed and is the substantive repair. See item 2.
- Nothing was changed in `test_heldout_cobps.py` here. This plan's files are the two gate scripts,
  the schema test module and `ci.yml`; editing a decoder training path would put a second variable
  into a CI-wiring plan, and the gate is `@pytest.mark.slow`, so it never runs in the new CI job
  and blocks nothing.

## 2. The slow gate asserts a headline-path margin against a different generalization task

This is the half of 09-06c item 2 that is still open, and it is now quantified. Two claims in the
original write-up separate cleanly:

**The cross-session window fabrication is real but negligible.** `_load_binned()` concatenates the
four sessions and `IndySpikeDataset` chunks into non-overlapping 32-bin windows. Only a window that
straddles an internal boundary is fabricated, and there are only three internal boundaries:

```
boundaries at bin 24999, 193146, 266307; none lands on a 32-bin edge
3 straddling windows out of 8917 total = 0.0336%
```

**The split composition is the real defect.** `chronological_split(concatenated, test_frac=0.2)`
takes the last 57,072 of 285,359 bins, which is:

| split | composition |
|---|---|
| train | all of indy_20160624_03, all of indy_20160627_01, the first 48.0% of indy_20160630_01 |
| test | the last 52.0% of indy_20160630_01, and 100% of indy_20160915_01 |

The model never sees a single bin of `indy_20160915_01`. So the gate's held-out co-bps mixes a
within-session temporal holdout with a full cross-session transfer to an unseen session, scored
against a null estimated on a train split that session is absent from. The headline path
(`ndt1.sessions.pooled_splits`, D-12) holds out the last 20% of EVERY session: 7,132 train and
1,782 test windows, against the gate's 7,133 and 1,783. The sizes are within one window of each
other, so this is purely a composition difference, not a budget difference.

That is why 0.679732 at 12 epochs sits ABOVE the headline's 0.4096 at 200. A per-channel mean rate
estimated without `indy_20160915_01` is a weak null on `indy_20160915_01`, and a weak null is easy
to beat. The committed evidence corroborates the direction: `loso_summary.test_mean_null` has mean
-0.3498 across the four folds, so cross-session transfer scored against the held-out session's OWN
mean is negative, while `loso_summary` against the training-pool null is +0.2446.

**What closing it looks like.** Two changes, neither of which touches the margin:

1. Repoint `_load_binned()` at `ndt1.sessions.pooled_splits` so the gate produces the same quantity
   the margin was derived from. Its own docstring already names that function as the D-12-correct
   path and calls the concatenation "only the smoke path for this single test".
2. Add the reproduction check: re-score the committed `ndt1_real_pooled.pt` on the D-12 splits and
   assert it reproduces `co_bps.pooled.train_null = 0.40956884089908474` to a tolerance. That is
   what the repository actually wants to defend, it costs seconds rather than 14 minutes because it
   scores instead of training, and unlike a margin it does not go vacuous when the observation is
   near zero. It stays `@pytest.mark.slow`: it needs the gitignored dataset and checkpoint, so it
   cannot be a CI-blocking test under D-21.

The measurement above is recorded here as the evidence behind a decision, NOT as a published
number. 0.679732 is a 12-epoch value on the concatenated split and must not be presented as this
phase's held-out co-bps; the headline remains 0.4096 on the D-12 path.

## 3. astral-sh/setup-uv publishes no floating major tags, so `@v8` does not resolve

`09-09-PLAN` Task 3 and `09-RESEARCH` section 11 (lines 751, 790 and the checklist at 1021) all
specify `astral-sh/setup-uv@v8`. That ref does not exist:

```
gh api repos/astral-sh/setup-uv/git/ref/tags/v8   -> 404
gh api repos/astral-sh/setup-uv/git/ref/tags/v9   -> 404
gh api repos/astral-sh/setup-uv/git/ref/tags/v10  -> 404
```

The publisher ships full semver tags only (v8.3.2, v9.0.0, v10.0.0, v10.0.1 as of 2026-09-02), plus
some v7-era minor floats. A workflow pinned at `@v8` fails at action resolution before the job
starts, so the research snippet as written would not have run. The job now pins `@v10.0.1` per the
plan's own fallback rule. `09-RESEARCH.md` still carries the unusable snippet and was not edited: it
is a prior wave's artifact.

## 4. The new job pins an action by tag, which is mutable

`astral-sh/setup-uv@v10.0.1` is a git tag, and a tag can be re-pointed by its publisher. Pinning by
full commit SHA is the stronger supply-chain posture. It was not done here because the repo pins
`actions/checkout@v4` and `maxim-lobanov/setup-xcode@v1` the same way, and switching one action to
SHA pinning while the others stay on tags is a repo-wide convention change, not a Phase 9 decision.

## 5. coremltools 9.0 prints two version warnings on every import, now on every CI run

The `decoder-python` job's toolchain step surfaces them:

```
scikit-learn version 1.9.0 is not supported. Minimum required version: 0.17.
Maximum required version: 1.5.1. Disabling scikit-learn conversion API.
Torch version 2.12.1 has not been tested with coremltools. You may run into unexpected errors.
Torch 2.7.0 is the most recent version that has been tested.
```

Neither is a failure and neither is new: 09-08 added scikit-learn precisely because the palettizer
falls through to it for tensors under 10,000 elements, and that path is a different one from the
`sklearn` MODEL CONVERTER this warning disables. Recorded because CI will now print both on every
run, and a reader who does not know the distinction may take the first line as evidence that the
palettization path is broken. It is not.

## 6. The Swift SwiftLint/SwiftFormat `--strict` gate is still unexercised

Noted, not touched, per this plan's scope. The new `decoder-python` job is Python-only and
deliberately pulls in none of the Swift lint surface. One incidental consequence worth recording:
because it is a sibling job rather than a step inside `build-and-lint`, the Python gate's result is
independent of whatever the Swift `--strict` gate does on the first PR that arms it.

## 7. VALIDATION rows remain marked pending

`09-VALIDATION.md` rows RD-01a, RD-03c, RD-04a, RD-04b, RD-05b and RD-06c are all still
`pending` even though this plan implements and negative-controls every one of them. Reconciling
that file is `/donny-validate-phase`'s job, not an executor's, and it is a known repo-wide pattern
(see the vault note on stale plan-time VALIDATION seeds).

## Note on pre-existing items

The two entries in the shared `deferred-items.md` still stand and were not re-logged. Item 2 (`ty`
reports `unresolved-import` on every file under `Decoder/`) reproduces on the new test module;
`uv run --project Decoder ruff check Decoder` and the quick pytest run both exit 0.
