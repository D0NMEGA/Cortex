---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 08
subsystem: decoder
tags: [coreml, palettization, ane, eligibility, latency, provenance, mlcomputeplan, rd-05, rd-06]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 06d
    provides: "Decoder/checkpoints/ndt1_real_pooled.pt (sha256 f95b257b), the reconstruction encoder"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    plan: 07
    provides: "Decoder/checkpoints/ndt1_real_with_velocity.pt (sha256 9d542cb5), the shipped model, and the held-out geometry, lag and null this plan scores through CoreML"
provides:
  - "ndt1.real_checkpoint: load_real_weights_if_present, which returns a provenance label rather than a boolean, so no artifact can record a number without recording which weights produced it"
  - "Decoder/scripts/rederive_coreml.py: both conversions, both palettization deltas, the weight_threshold census, the ANE scan and a two-run determinism check, refusing to start on random weights"
  - "The measured finding that the 4-bit palettized shipped model does NOT decode velocity: held-out R2 -1.786971 against the fp16 package's +0.423870, delta -2.210841"
  - "A pre-registered four-point granularity sweep showing per-channel palettization recovers the decode to +0.191784, positive but 45% of fp16, at 2.6262x compression"
  - "The recommendation on which artifact ships, grounded in R2, size, eligibility and p99: ship fp16"
  - "Two traps recorded for the next caller: enable_per_channel_scale breaks ANE eligibility (38 CPU-only ops), and a group_size that does not divide a channel count silently leaves that tensor uncompressed"
  - "The corrected ANE op tally for the shipped graph: 239 schedulable ops, all eligible, zero CPU-only, superseding Phase 5's 226 which was measured on an untrained graph"
  - "The root cause and fix for the flaky ANE gate: compile_model nests into an existing destination, so every scan since 2026-06-21 read a stale compiled artifact"
  - "Re-measured palettization on real weights: size ratio 3.4134x (reconstruction) and 3.4020x (shipped), Poisson-NLL delta 0.020352"
  - "Device-labeled decoder latency with real weights: 0.130708 ms p50, 0.141083 ms p99, n=10,000, ops MEASURED as CPU-placed on Apple M5 Pro, recorded as corroborating"
  - "A control run with the checkpoints hidden that reproduces Phase 4's 3.471x and Phase 5's 226 exactly, making every published difference attributable to the weights"
affects: [09-09, 09-10, 09-11, Phase 10, RD-05, RD-06]

# Tech tracking
tech-stack:
  added: ["scikit-learn 1.9.0 (coremltools' k-means palettizer requires it for tensors under 10,000 elements)"]
  patterns:
    - "Make the provenance label the RETURN VALUE of the load, so a caller cannot obtain the weights without obtaining the string that names them"
    - "Choose the sentinel string so it cannot satisfy the guard that gates on it: a `random init` label must not contain the substring callers test for"
    - "Run the control before publishing the comparison: hide the real inputs, re-run the same code, and show it reproduces the old numbers, so every difference is attributable to the inputs rather than to the pipeline"
    - "Prove a suspected nondeterminism with a discriminating experiment rather than repeated sampling: compile two models with different op counts to one destination and see which count comes back"
    - "Separate `offset` from `destroyed` with a diagnostic whose correction is estimated on train rows only, so the question can be answered without the answer leaking held-out information"
    - "Validate the measurement apparatus against an independently produced number before reading the new number it produces"

key-files:
  created:
    - Decoder/src/ndt1/real_checkpoint.py
    - Decoder/tests/test_real_checkpoint.py
    - Decoder/scripts/rederive_coreml.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-coreml-evidence.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-08.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-08-SUMMARY.md
  modified:
    - Decoder/tests/test_ane_compute_plan.py
    - Decoder/tests/test_palettization_loss_delta.py
    - Decoder/tests/test_palettized_package.py
    - Decoder/pyproject.toml
    - Decoder/uv.lock
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-decoder-metrics.json

key-decisions:
  - "The `random init` label omits the substring `real-data`, contrary to the plan's literal wording, because the plan's own abort check and verify block gate on that substring and the specified wording would have satisfied the guard it exists to trip"
  - "scikit-learn was added rather than forcing kmeans1d, because it is the unchanged OpPalettizerConfig defaults that make the size ratio comparable to Phase 4 at all; changing the algorithm would have destroyed the comparison the plan asks for"
  - "The 4-bit velocity collapse is published as the measured result rather than investigated into a fix, because every available remedy changes the shipped model and this plan is forbidden from retraining either one"
  - "The bias-corrected R2 estimates its offset on train rows only and is labeled a diagnostic, so the question `offset or destroyed` is answered without a re-centered number entering the headline"
  - "Latency was measured on all three candidate packages, because the R2 collapse makes which artifact ships an open question and the latency cost of that choice is now on the record"
  - "The granularity grid was fixed and committed before the sweep ran, and all four configurations are published including the three that did not help"
  - "The sweep configures palettization locally in the script rather than changing ndt1.palettize, so the per-tensor baseline it is measured against is not quietly redefined"
  - "fp16 is recommended over the best 4-bit configuration because R2 decides and the 1.6 MB saving does not pay for 55% of the decode; latency headroom is at least 12x either way"
  - "The stale-compile bug was fixed at the two call sites this plan owns rather than in compute_plan.py, which is outside the declared files_modified; the library-level footgun is logged as a deferred item"

patterns-established:
  - "When a gate is reported as flaky, look for a stale-input bug before a timing bug: a gate that reads a cached artifact returns a stable wrong answer most of the time and a different one occasionally"
  - "Publish the control table next to the comparison table, so a reader can see that the pipeline was held fixed"

requirements-completed: [RD-05, RD-06]

# Metrics
duration: about 2h
completed: 2026-09-02
---

# Phase 9 Plan 08: the CoreML numbers, re-derived on real data Summary

**Every CoreML-side number in this repository has been re-measured on the real-data checkpoints,
and one of them did not survive the move: the 4-bit palettized shipped model's held-out velocity R2
is -1.786971 against the fp16 package's +0.423870, so the artifact the project has been calling its
deployment model does not decode cursor velocity. Two further Phase-5 claims turn out to have been
measured on an untrained stand-in: the shipped graph schedules 239 ops rather than 226, and the ANE
gate that produced 226 had been reading a compiled artifact from 2026-06-21 on every run since. A
control with the checkpoints hidden reproduces Phase 4's 3.471x and Phase 5's 226 exactly, so every
difference reported here is attributable to the weights and not to the pipeline.**

## Performance

- **Duration:** about 2 hours
- **Tasks:** 3 of 3, plus the blocking flaky-gate investigation the coordinator required first
- **Files:** 6 created, 6 modified
- **Commits:** 8

## Accomplishments

### The blocking issue, resolved before any op tally was published

The coordinator required the flaky `test_ane_compute_plan.py` to be made deterministic, or the
nondeterminism published as the finding, before an op count could be reported as measured. It was
neither flaky in the usual sense nor unfixable. It was reading stale data.

`coremltools.models.utils.compile_model` moves its freshly compiled `.mlmodelc` to
`destination_path` with `shutil.move`. When that destination already exists as a directory,
`shutil.move` nests the new compile **inside** it rather than replacing it, and `compile_model`
returns the unchanged destination anyway. `MLComputePlan.load_from_path` therefore reads the first
compile ever written to that path. Because the build directories were named from the stable test
name under the shared `Decoder/checkpoints/`, the top-level `model.mil` of all four scan
directories was dated **2026-06-21** and 217 unread nested compiles totalling **285 MB** had piled
up behind them.

Proven with a discriminating experiment rather than by repeated sampling: compiling the
encoder-only model (**224** schedulable ops) and then the with-velocity model (**226**) to one
shared destination returns **224 both times**.

The fix is to build every package and compile under the test's own `tmp_path`, which is what the
deferred item itself proposed. After it, **five consecutive runs on random weights and three on the
real weights each returned a byte-identical verdict**, including the full per-op-type histogram, and
nothing accumulates in `Decoder/checkpoints/`. The op tally below rests on a gate that returns the
same answer on the same inputs.

This mattered directly. Without the fix, scanning the real-data model in the shared directory would
have returned the June 21 numbers and this plan would have published them as measured on real
weights.

### The finding: 4-bit palettization destroys the velocity decode

| Model | Held-out R2 over 56,943 rows against the pooled TRAIN-split mean-velocity null |
|---|---|
| fp16 package | **+0.423870** (vx +0.344584, vy +0.531901) |
| 4-bit package | **-1.786971** (vx -0.460860, vy -3.593836) |
| Delta | **-2.210841** |

The apparatus was validated before the result was read: the fp16 figure reproduces Plan 09-07's
PyTorch float32 number (0.4238, vx 0.3430, vy 0.5338) to four decimal places on the same 56,943
rows, across a different framework, a different precision and an independent reimplementation of the
window geometry, lag and null.

The mechanism was measured. Per-tensor 4-bit k-means gives one 16-entry table per weight tensor, so
its error biases rather than cancels: the 4-bit encoder's last-bin output carries a **systematic
per-channel mean shift of up to 1.21573 against a residual scatter of 0.07793**. The reconstruction
objective barely registers it (Poisson-NLL delta 0.020352). The linear readout, fit by ridge on the
un-palettized encoder's output, turns it into a constant velocity error of **[-11.24, +12.92] cm/s**
against a signal whose per-axis standard deviation is only [2.87, 2.02] cm/s.

A diagnostic distinguishes "offset" from "destroyed": subtracting a constant estimated on **train
rows only** recovers part of the loss and leaves R2 at **-0.770991**, still worse than the constant
null. Re-centering is not a fix, and neither remedy was applied, because both change the shipped
model and this plan may not retrain either one.

### The authorized follow-up: per-channel palettization rescues the decode, partly

A pre-registered four-point grid, fixed in the committed script before the sweep ran, scored on
exactly the same 56,943 rows as the baseline. All four are published; three did not help.

| Configuration | Held-out R2 | Bytes | Ratio | LUTs | Eligible | CPU-only | max abs channel shift |
|---|---|---|---|---|---|---|---|
| fp16 | **+0.423870** | 2,708,540 | 1.000x | 0 | yes | 0 | reference |
| 4-bit `per_grouped_channel` group 1 | **+0.191784** | 1,031,338 | 2.6262x | 39 | yes | 0 | **0.16916** |
| 4-bit `per_tensor` (default) | -1.786971 | 796,165 | 3.4020x | 39 | yes | 0 | 1.21573 |
| 4-bit `per_grouped_channel` group 16 | -4.161405 | 814,638 | 3.3248x | 38 | yes | 0 | 0.92612 |
| 4-bit `per_grouped_channel` group 32 | -4.927721 | 1,447,511 | 1.8712x | 32 | yes | 0 | 1.11737 |
| 4-bit `per_tensor` + `per_channel_scale` | -0.242031 | 1,203,108 | 2.2513x | 39 | **NO** | **38** | 0.69615 |

**The mechanism was attenuated, not removed**, which is the direct answer to whether the diagnosis
held. Per-channel cuts the max per-channel shift 7.2x (1.21573 to 0.16916) and the residual scatter
1.5x, but the shift still dominates the residual by 3.35x against per-tensor's 15.6. An R2 that
recovers to positive without recovering to fp16 is exactly what that predicts. Across the grid the
extremes order correctly, but the middle does not: `per_tensor` has the largest shift yet a better
R2 than either group 16 or group 32, so the statistic explains the mechanism without being a
sufficient predictor, and the evidence says so rather than overclaiming.

Two incidental traps, both recorded because they would cost the next person a day.
`enable_per_channel_scale=True` **fails the DEC-06 gate**: 38 CPU-only ops, `all_eligible` false,
found by the `tmp_path`-isolated scan so it is a property of the model. And a `group_size` that does
not divide a tensor's channel count silently leaves it uncompressed: with output-channel counts of
1, 96, 128 and 560 among the 39 palettizable tensors, `group_size=32` skips the positional encoding
**and all six 71,680-element FFN tensors**, palettizes only 32, and so compresses worse (1.8712x)
than per-tensor while also decoding worse. The LUT counts are what make those ratios readable.

### The recommendation: ship fp16

| Candidate | R2 | Bytes | Eligibility | p99, M5 Pro | Headroom vs 2 ms |
|---|---|---|---|---|---|
| **fp16** | **+0.423870** | 2,708,540 | 239/239, 0 CPU-only | 0.141959 ms | 14x |
| 4-bit per-channel | +0.191784 | 1,031,338 | 239/239, 0 CPU-only | 0.165042 ms | 12x |
| 4-bit per-tensor | -1.786971 | 796,165 | 239/239, 0 CPU-only | 0.141083 ms | 14x |

R2 decides and nothing else contradicts it. The best 4-bit configuration costs **55% of the decode**
to save **1,677,202 bytes** on a model already under 3 MB. Latency does not differentiate: all three
sit inside 0.141 to 0.166 ms p99 with at least 12x headroom, so the 24 microsecond spread is noise
against the budget. Eligibility does not differentiate either. The one option that is disqualified
outright is today's `per_tensor` default, which does not decode.

If a memory constraint ever forces 4-bit, the configuration is `per_grouped_channel` with
`group_size=1`, and the still-untested refit of the readout on the palettized encoder's output
should be tried first. That remedy was not run because this plan may not retrain either model, and
the bias-corrected diagnostic (-0.770991) means it is a hypothesis rather than a known fix.

### Phase 5's 226 was never the shipped graph's op count

| Op type | Randomly initialized | Real data | Change |
|---|---|---|---|
| `ios18.add` | 24 | 25 | +1 |
| `ios18.batch_norm` | 0 | 12 | +12 |
| every other op type | identical | identical | 0 |
| **total** | **226** | **239** | **+13** |

`pos_encoding` is initialized to `torch.zeros`, so in an untrained model the positional-encoding
`add` folds away before tracing and the twelve `LayerNormANE` modules simplify rather than lowering
to `batch_norm`. The eligibility verdict survives the correction: **239 of 239 ANE-eligible, zero
CPU-only**, including the twelve `batch_norm` ops Phase 5 never scanned. The claim asserted is
ELIGIBILITY; PLACEMENT is not asserted, and the Mac `preferred` tally is `{CPU: 239}` as expected at
this scale.

### The same root cause produced three separate surprises

Palettizing either real checkpoint failed outright with `ModuleNotFoundError: scikit-learn is
required`, while an identically shaped random model succeeded. coremltools uses its bundled
`kmeans1d` only for tensors of at least 10,000 elements; smaller ones that still clear
`weight_threshold=2048` fall through to scikit-learn. The untrained model palettizes 38 tensors, all
at least 12,288 elements. The real model palettizes 39, and the extra one is the 4,096-element
positional encoding.

So the zero-initialized positional encoding explains the extra palettized tensor, the changed op
count and the new dependency. **No synthetic-weight run of this pipeline ever exercised the code
path the real model takes.**

### Palettization, the threshold disclosure and determinism

| | Reconstruction `NDT1ANE` | Shipped `NDT1ANEWithVelocity` |
|---|---|---|
| fp16 / 4-bit bytes | 2,704,783 / 792,409 | 2,708,540 / 796,165 |
| Size ratio | **3.4134x** | **3.4020x** |
| Delta | Poisson NLL **0.020352** | R2 **-2.210841** |

Phase-4 synthetic baseline, labeled as such and not carried forward: 3.471x and 0.009114.

`weight_threshold=2048` skips any tensor under 2,048 elements. The velocity readout is a 1x1
`Conv2d(96 -> 2)`, that is **2 x 96 = 192** elements, so it is **never palettized**: 39 of 103
parameter tensors clear the threshold and the saved package contains exactly 39
`constexpr_lut_to_dense` ops, with a clean gap between the largest skipped tensor (560 elements) and
the smallest palettized one (4,096). **The shipped model's entire -2.210841 R2 loss is therefore
encoder-attributable**, since the readout is bit-identical between the two packages. The script
raises if the readout ever grows past the threshold, so the claim cannot go stale silently.

Two palettization runs on the same fp16 package produced identical package sizes and identical NLL
deltas, so the committed delta is reproducible rather than assumed to be.

### Latency, labeled with the device that produced it

| | 4-bit package | fp16 package |
|---|---|---|
| p50 | **0.130708 ms** | 0.131291 ms |
| p99 | **0.141083 ms** | 0.141959 ms |
| n | 10,000 | 10,000 |
| `deviceAnnotation`, MEASURED | **CPU** | **CPU** |

Apple M5 Pro (arm64), macOS 26.5, Xcode 26.3 / Swift 6.2.4. **Corroborating, never canonical.** The
ops were measured as CPU-placed, so this is a CPU latency on an M5 Pro; it is not an iPad-M4 number
and is not presented as one. The canonical on-device capture is optional, owned by Plan 09-11,
tracked in `09-HUMAN-UAT.md`, and under D-17 is never auto-approved. Real weights moved p99 by 1.7
microseconds against Phase 5's synthetic 0.139333 ms, so the 13 extra ops cost essentially nothing.

### The control that makes the comparison legitimate

With the two gitignored checkpoints moved aside and the whole pipeline re-run on the resulting
random initialization: size ratio **3.471x** (Phase 4: 3.471x), NLL delta **0.009179** (Phase 4:
0.009114), schedulable ops **226** (Phase 5: 226). The config did not drift, the `tmp_path` fix did
not perturb the scan, and adding scikit-learn changed nothing for tensors that never take that
branch. The same run confirms the five slow tests pass with no checkpoints present, which Plan
09-09's CI job depends on, and that `rederive_coreml.py` exits 1 rather than measuring random
weights.

## Task Commits

1. **Blocking fix** - `94db2e7` (fix): scan the model the run built, not a stale compiled artifact
2. **Task 1 RED** - `7408fdc` (test): failing tests for the provenance label
3. **Task 1 GREEN** - `1c4ca71` (feat): `real_checkpoint.py`
4. **Blocking dependency** - `f6c385b` (fix): scikit-learn, required to palettize real weights
5. **Task 2** - `35e92b9` (feat): provenance recorded in the three slow CoreML tests
6. **Task 3 pre-registration** - `f9dc848` (feat): `rederive_coreml.py`, before its numbers
7. **Task 3 measurement** - `e212769` (feat): the palettization, ANE and latency sections
8. **Task 3 reporting** - `5cbcc61` (docs): the evidence and its deferred items

Ordering verified with `git merge-base --is-ancestor`: the RED tests precede the implementation, the
script precedes the commit carrying its numbers, and the stale-compile fix precedes the op tally it
makes trustworthy.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] The ANE gate was reading a compiled artifact from 2026-06-21**

- **Found during:** the coordinator's mandated pre-task investigation
- **Issue:** `compile_model` nests into an existing destination instead of replacing it. Every scan
  since Phase 5 read a stale `.mlmodelc`; 285 MB of unread nested compiles had accumulated.
- **Fix:** build every package and compile under the test's own `tmp_path`.
- **Verification:** the discriminating experiment (224 vs 226 to one destination returns 224 twice),
  then 5 random-weight and 3 real-weight runs with byte-identical verdicts.
- **Committed in:** `94db2e7`

**2. [Rule 1 - Bug] The plan's `random init` label would have defeated its own guard**

- **Found during:** Task 1, by the test that asserts the two labels are distinguishable
- **Issue:** the plan specifies `"random init (no real-data checkpoint at <path>)"`, while its
  Task 3 abort check and its verify block both gate on `"real-data" in provenance`. The specified
  wording contains that substring, so the guard would have passed on random weights.
- **Fix:** the label reads `"random init (no checkpoint at <path>)"`. It still names the path, so
  the file is still identified.
- **Committed in:** `1c4ca71`

**3. [Rule 2 - Missing critical] A corrupt checkpoint escaped uncontextualized**

- **Found during:** Task 1
- **Issue:** unpickling a corrupt file raises `pickle.UnpicklingError`, which is outside the
  `(RuntimeError, EOFError)` set `ndt1.train.load_checkpoint` catches, so it propagated bare.
- **Fix:** caught explicitly and re-raised with context. The load still never falls back to random
  weights after a failure.
- **Committed in:** `1c4ca71`

**4. [Rule 3 - Blocking] scikit-learn was missing and the plan could not execute without it**

- **Found during:** Task 2, on the first slow run with real weights
- **Issue:** `palettize_4bit` raised `ModuleNotFoundError` on both real checkpoints while succeeding
  on random ones. coremltools falls through to scikit-learn for palettizable tensors under 10,000
  elements, which the trained positional encoding is.
- **Fix:** added `scikit-learn>=1.5` to `Decoder/pyproject.toml`, which is coremltools' own
  documented remedy, rather than forcing `kmeans1d` and changing the algorithm under comparison.
- **Files modified outside `files_modified`:** `Decoder/pyproject.toml`, `Decoder/uv.lock`
- **Committed in:** `f6c385b`

**5. [Rule 2 - Missing critical] A fresh-destination guard in the new script**

- **Found during:** Task 3
- **Issue:** `rederive_coreml.py` writes to `Decoder/checkpoints` by default, so a second run would
  hit the same stale-compile bug the tests were just fixed for.
- **Fix:** remove any existing `.mlmodelc` destination, then assert no nested compile appeared.
- **Committed in:** `f9dc848`

### Non-issue deviations

**6. A bias-corrected R2 diagnostic was added beyond the plan's task list.** The plan asks for the
R2 delta and nothing more. The delta came back at -2.21, and a reader's immediate question is
whether the signal is offset or destroyed, because that is the difference between a refit and a
redesign. The diagnostic estimates its offset on train rows only, is labeled a diagnostic in both
the JSON and the evidence, and is excluded from the reported delta by construction.

**7. Latency was measured on the fp16 package as well as the 4-bit one.** The plan specifies the
4-bit package. The R2 collapse makes which artifact ships an open question, so the latency cost of
that choice (about 0.9 microseconds at p99) is now on the record rather than requiring another run.

**8. The metrics `palettization` section carries keys beyond the plan's sketch:**
`threshold_census`, `determinism_detail`, `velocity_head_note`, per-model `provenance` and `sha256`,
`env` and `smoke`. Every key the plan specifies is present with the specified shape, and the diff is
173 insertions and 0 deletions, so no previously published value was touched.

**9. The granularity sweep was added after the plan's tasks, on coordinator request.** It is this
plan's own deferred item 1, executed rather than deferred. It stays inside the plan's
`files_modified` plus the two documents this plan owns, adds only
`palettization.granularity_sweep` and `latency.per_channel_4bit_comparison` to the metrics JSON, and
leaves every per-tensor number exactly as measured, because the comparison between them is the
finding. The grid was committed in `9b86739` before the run that produced the published numbers. A
`--smoke` wiring check on 1,024 rows ran before that commit, so smoke-scale values were seen before
the full run; the grid was not changed afterwards, and the only edits between were a LUT-count
diagnostic and a smoke-mode file path.

**10. `Decoder/checkpoints/` was found empty at the start of the follow-up**, having lost both
real-data checkpoints, Plan 09-07's 218 MB rates cache and the 09-08 run logs. Nothing in this plan
wipes that directory. Both checkpoints were restored from the scratch backup taken during the
checkpoints-hidden control and verified against their committed sha256 values (`f95b257b...` and
`9d542cb5...`) before any measurement ran, so every number in the sweep is attributable to the same
weights as the baseline it is compared against. Logged as deferred item 5.

## Issues Encountered

**The project's deployment artifact does not do the thing the project exists to do.** The 4-bit
palettized model is what Phases 4 and 5 built, characterized and handed forward as the shipping
artifact, and it decodes velocity worse than a constant. Nobody caught it because the velocity head
was previously fit on synthetic labels generated from the rates it regresses (Plan 09-07 retired
that 0.99985 figure), so the palettized model's velocity output had never been scored against real
kinematics. This plan is the first time the two halves were put together.

**Three Phase-5 claims were measured on an untrained stand-in.** The 226-op tally, and by extension
the "226/226 ANE-eligible" headline, and the shape of the graph the latency bench timed. The
eligibility verdict survives on the corrected 239-op graph, but the number itself is superseded.
Plan 09-10 owns the sweep.

**The stale-compile bug means the DEC-06 evidence gate has been decorative since June.** It passed
because the stale artifact happened to be a valid compile of the same architecture. Had a real
eligibility regression been introduced at any point in Phases 6 through 9, this gate would not have
caught it.

**A favourable-looking result would have been easy to report here.** The size ratio reproduced, the
op count was still fully eligible, the latency barely moved, and the plan's own expectations said
the size ratio should reproduce and the loss delta should not. Reading only those, this plan passes
cleanly. The velocity R2 leg is the one the plan added last and it is the one that failed.

## Deferred Items

Five in `deferred-items-09-08.md`, of which **item 1 is now RESOLVED with a recommendation**: the
granularity sweep answered which artifact should ship, and the answer is fp16. Its remaining open
thread is the untested readout refit on the palettized encoder's output, kept as a hypothesis rather
than promoted to a fix. Item 2 records that `ndt1.compute_plan.compiled_model_path` is still
unhardened for the next caller, since `compute_plan.py` sits outside this plan's `files_modified`.
Items 3 and 4 are the Phase-4/5 supersession sweep (Plan 09-10 owns it) and the absence of any error
bar, the third artifact in this phase to carry that gap. Item 5 is new and is not this plan's doing:
`Decoder/checkpoints/` was emptied between the original plan and the follow-up, destroying both
checkpoints, a 218 MB cache and the run logs. The checkpoints were restored from a scratch backup
and hash-verified, but nothing would have detected the loss except a run that needed them.

## Known Stubs

None. Every path in `real_checkpoint.py` and `rederive_coreml.py` is executed by the published run
or by a committed test: the missing-checkpoint branch, the corrupt-checkpoint branch, the
mismatched-state-dict branch, the smoke mode and the abort-on-random-weights path were each
exercised, the last two during the checkpoints-hidden control. No placeholder value, no hardcoded
empty result and no unwired branch. Values that could be mistaken for results are labeled where they
appear: `diagnostic_bias_corrected` carries a `status` field naming itself a diagnostic, and
`--smoke` output carries `"smoke": true` and writes to a gitignored scratch path that cannot reach
the published JSON.

## Threat Flags

No new network endpoint, no auth path, no schema change at a trust boundary, and no new file-access
pattern beyond reading the gitignored checkpoints through the existing `weights_only=True` path.

One dependency worth flagging rather than burying: **scikit-learn 1.9.0 entered the `Decoder`
dependency tree**, adding joblib, threadpoolctl, cloudpickle and narwhals. It is used only inside
coremltools' offline palettization build step and never at inference time; nothing in the Swift
serving path or the shipped `.mlpackage` links it.

The register's dispositions held. T-09-08-01 (a synthetic number published as a real-data one):
every artifact records a provenance label, `rederive_coreml.py` exits 1 without real weights, and
the label wording was corrected so it cannot satisfy the guard that reads it. T-09-08-02 (a Mac
latency number presented as canonical): `latency.status` is `corroborating`, the exact machine
string is recorded, and both evidence mentions of the iPad target are in deferred framing.
T-09-08-03 (an inherited palettization number): both deltas were re-measured and the Phase-4 values
sit under an explicit `phase4_synthetic_baseline` key. T-09-08-04 (k-means nondeterminism): measured
across two runs and found identical. T-09-08-05 (a traced-graph change silently degrading
eligibility): the graph DID change, the tally is published as measured with the per-op-type diff,
and the mechanism is named. T-09-08-06 (checkpoint deserialization): every load routes through
`weights_only=True` and a test greps for an unguarded call. T-09-08-07 (committing a large
artifact): `git status --porcelain` on `Decoder/checkpoints`, `Decoder/data` and
`Packages/CortexDecoder/.bench` returns 0 lines, and `git ls-files` matches no `.pt`, `.mlpackage`
or `.mlmodelc`.

## Verification

```
uv run --project Decoder ruff check Decoder                              -> All checks passed
uv run --project Decoder pytest Decoder/tests -m "not slow" -q           -> 198 passed, 9 deselected
uv run ... pytest -m slow -k "palettiz or ane_compute or compute_plan"   -> 5 passed (real weights)
uv run ... pytest -m slow (same selection, checkpoints hidden)           -> 5 passed (random init)
uv run --project Decoder python Decoder/scripts/rederive_coreml.py       -> 0 (17.8 s)
uv run ... rederive_coreml.py (checkpoints hidden)                       -> 1, refused
swift build --package-path Packages/CortexDecoder                        -> Build complete
CORTEX_DECODER_MODEL_URL=... CortexDecoderBench (4-bit, then fp16)       -> 0, 0
git status --porcelain Decoder/checkpoints Decoder/data .bench           -> 0 lines
git diff --stat (metrics JSON, first pass)                               -> 173 insertions, 0 deletions

Follow-up (the granularity sweep):
uv run ... rederive_coreml.py --granularity-sweep --smoke                -> 0 (wiring)
uv run ... rederive_coreml.py --granularity-sweep                        -> 0 (4/4 configs scored)
CORTEX_DECODER_MODEL_URL=<per-channel pkg> CortexDecoderBench            -> 0
uv run --project Decoder pytest Decoder/tests -m "not slow" -q           -> 208 passed, 9 deselected
bash Tools/scripts/decoder-policy.sh                                     -> 0 (09-09's gate)
```

The plan's inline verification block prints `palettization/ane/latency sections OK`. Every
acceptance grep passes, including the negative controls: the evidence contains neither of the two
tokens belonging to the retired glass-to-glass claim, contains no non-ASCII character, and both
`iPad-M4` occurrences are in "not presented as one" framing rather than attached to a measured
number.

## Next Phase Readiness

- **Plan 09-09** gains `palettization`, `ane` and `latency` blocks to schema-assert. Useful
  invariants: `palettization.velocity_head_palettized` is `false`, `threshold_census.tensors_over_threshold`
  equals `palettized_tensors_in_package` (both 39), `ane.cpu_only_ops` is 0, and `latency.status`
  is the literal `corroborating`. The CI job is unaffected by this plan: the slow tests pass on a
  checkout with no checkpoints, verified by moving them aside.
- **Plan 09-10** has three more superseded numbers to label, all in Phase-5 artifacts: `226/226` in
  `05-ane-eligibility-evidence.md`, and the p50/p99 pair in `05-latency-evidence.md`. The op count
  in particular is not merely stale, it was never the shipped graph's.
- **Plan 09-11** should present the device capture against 239 ops, not 226, and should be told that
  the 4-bit artifact does not decode, so a device run on it measures the latency of a model that
  produces wrong velocities. That is still a valid latency measurement and an invalid demo.
- **Phase 10 inherits a recommendation rather than an open question:** ship fp16. All three
  candidates are measured on the same rows and the same machine, and the decision rests on R2 with
  size, eligibility and p99 all recorded. The one genuinely open thread is the untested readout
  refit on the palettized encoder's output, which matters only if a memory constraint later forces
  4-bit.
- **Plan 09-11's device capture should run against the fp16 package** if the recommendation is
  accepted, since a device run on the per-tensor 4-bit artifact measures the latency of a model that
  produces wrong velocities: a valid latency measurement and an invalid demo.
- **Open constraint on everything downstream:** `+0.423870` is the **fp16** package's held-out R2 and
  inherits every constraint Plan 09-07 placed on 0.4238 (within-pool, no error bar, constant
  TRAIN-mean null). `-1.786971` is the **4-bit** package's, and neither may be quoted without the
  other. `-0.770991` is a diagnostic and is not a decode result. `+0.191784` is the best 4-bit
  configuration and may not be quoted as "4-bit works" without the fp16 figure beside it. `239/239`
  is an ELIGIBILITY claim on a dev Mac, not a residency claim. `0.141083 ms` is a CPU-placed M5 Pro
  measurement and may never be quoted as an iPad-M4 or an ANE number.

## Status rationale

`PARTIAL`, not `PASS`. All three tasks executed and committed, the blocking flaky-gate investigation
resolved with determinism established over eight runs, every verification command green, every
acceptance criterion met, and no number clamped, re-rolled or inherited. Four flagged gaps prevent a
clean `PASS`:

1. **The 4-bit shipped artifact does not decode velocity.** The follow-up narrowed this from an open
   question to a recommendation (ship fp16), but the recommendation still needs accepting and the
   default configuration in `ndt1.palettize` is still the broken one. The untested readout refit
   remains a hypothesis.
2. **`compiled_model_path` is still unhardened** for callers outside the two this plan owns.
3. **Phase-5 artifacts still publish 226/226 and their latency pair** as properties of the shipped
   graph; the supersession sweep belongs to Plan 09-10.
4. **No error bar on any number here**, the third artifact in this phase to carry that gap, and it
   matters more for a -2.21 delta than it did for the figures it supersedes.
5. **`Decoder/checkpoints/` was wiped between the plan and its follow-up** by something outside this
   plan. Recovered and hash-verified, but the cause is unfound.

## Self-Check: PASSED

Files claimed created, verified present on disk:

- `Decoder/src/ndt1/real_checkpoint.py` FOUND (127 lines)
- `Decoder/tests/test_real_checkpoint.py` FOUND (150 lines)
- `Decoder/scripts/rederive_coreml.py` FOUND (576 lines)
- `.planning/phases/09-.../09-coreml-evidence.md` FOUND (400 lines)
- `.planning/phases/09-.../deferred-items-09-08.md` FOUND (55 lines)
- `.planning/phases/09-.../09-decoder-metrics.json` FOUND (modified, 173 insertions, 0 deletions)

All eight commits verified present in `git log e4aed82..HEAD`: `94db2e7`, `7408fdc`, `1c4ca71`,
`f6c385b`, `35e92b9`, `f9dc848`, `e212769`, `5cbcc61`.

Commit ORDERING verified with `git merge-base --is-ancestor`, all three exiting 0: the RED tests
precede the implementation, `rederive_coreml.py` precedes the commit carrying its numbers, and the
stale-compile fix precedes the op tally it makes trustworthy.

Number provenance verified rather than trusted. The metrics JSON was written by the committed
script, not typed; the `latency` section was derived programmatically from the bench's own
`latency_histogram.json` rather than transcribed by hand; and every figure in the evidence document
was checked back against the committed JSON and the run logs under
`Decoder/checkpoints/09-08-logs/`. One transcription error was found in the first draft of the
evidence table (a Phase-4 NLL value pasted into a Phase-9 row) and corrected before commit.

The determinism claim was verified by comparing full verdict files, not by reading pass/fail: the
five random-weight verdicts hash to one value and the three real-weight verdicts hash to one value,
each including the complete per-op-type histogram.

File discipline verified with `git diff --name-only e4aed82..HEAD`. Files this plan did NOT touch,
as required: `kinematics.py`, `qc.py`, `sessions.py`, `train.py`, `loss.py`, `compute_plan.py`,
`model_ane.py`, `velocity_head.py`, `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `PROJECT.md`, the
shared `deferred-items.md`, and every Phase-4 and Phase-5 artifact. The two files changed outside
the declared `files_modified` are `Decoder/pyproject.toml` and `Decoder/uv.lock`, both for the
blocking scikit-learn dependency and both documented as deviation 4.

Neither model was retrained: `ndt1_real_pooled.pt` and `ndt1_real_with_velocity.pt` still hash to
`f95b257b...` and `9d542cb5...`, re-verified after the checkpoints-hidden control restored them.

---
*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Completed: 2026-09-02*
