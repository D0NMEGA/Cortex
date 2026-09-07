# Phase 10 deferred items

Out-of-scope discoveries logged during execution. Each was found while doing other work, is not
caused by the task that found it, and was deliberately NOT fixed.

## The `ty` type-check hook resolves imports against the wrong Python environment

**Found during:** Plan 10-01, Tasks 2 and 3.

**Symptom:** the editor hook's `ty` pass reports `error[unresolved-import] Cannot resolve imported
module 'h5py'` and the same for `pytest` on any file under `Decoder/`.

**Why it is not a defect in this plan's code.** `h5py` is a declared dependency in
`Decoder/pyproject.toml` and `pytest` is in its `dev` optional-dependency extra; both are installed
in the uv-managed `Decoder/.venv`. The same diagnostic appears on the pre-existing
`Decoder/src/ndt1/data.py`, which has been committed since Phase 9, and `ty`'s own output names its
search path as `/opt/homebrew/lib/python3.14/site-packages`, not `Decoder/.venv`. So `ty` is
type-checking `Decoder/` against the Homebrew interpreter rather than the project environment.

**Evidence it is environmental, not real:** under the project's own toolchain,
`uv run --project Decoder ruff check Decoder` passes with zero findings and
`uv run --project Decoder pytest Decoder/tests -m "not slow" -q` is green at 220 passed, 1 skipped.

**Fix when someone picks it up:** point the hook's `ty` at the project environment (for example
`uv run --project Decoder ty check ...`, or set the interpreter path per-directory) so `Decoder/`
is checked against the environment it actually runs in. Not done here because it is a tooling
configuration change outside this plan's files, and changing it would touch the shared hook
configuration while other Phase 10 worktrees are running.

## `test_heldout_cobps_beats_mean_rate_null` fails on synthetic Poisson fallback

**Found during:** Plan 10-09, Task 1 gates.

**Symptom:** `pytest` reports `AssertionError: held-out co_bps -0.02177 did not beat the
mean-rate null by the documented margin 0.054 (source: synthetic Poisson fallback (no .mat
present))`.

**Why it is not a defect in this plan's code.** The only files touched by Plan 10-09 are in
`Tools/scripts/`. The failure fires on `Decoder/tests/test_heldout_cobps.py` which was
unchanged. The failure is attributed to the NDT1 masking-objective fix (committed 2026-08-31):
the masking defect caused the synthetic synthetic co-bps to be measured against self-reconstruction;
after the fix the synthetic number is honest and lower. The threshold `CO_BPS_MARGIN = 0.054`
pre-dates the fix. Running without the real Indy .mat dataset, the test uses the synthetic
Poisson fallback, which no longer beats the pre-fix threshold.

**Fix when someone picks it up:** Either update `CO_BPS_MARGIN` to the post-fix honest synthetic
threshold, or mark the test `@pytest.mark.slow` so it only runs when the real dataset is present.
Owner: whoever lands Phase 10 plan that re-verifies the synthetic training baseline.

## `ClosedLoopPipelineTests` Test 2 cannot pass against the shipped 32-bin model

**Found during:** Plan 10-04, Task 3, while verifying that every pre-existing case still passes.

**Symptom.** With `CORTEX_MODEL_URL` pointing at the shipped
`Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage`, the Phase-8 case
`ClosedLoopPipelineTests.modelBackedDecodePathPresent` ("Test 2: NDT1 model-backed decode path is
present + compiled") fails at `ClosedLoopPipelineTests.swift:71` with `Expectation failed:
anyModelTick`. Without the variable set it returns early and passes, which is why it has always
looked green.

**Why.** The case builds `ClosedLoopPipeline(seed:target:modelURL:)`, which uses the default
`SyntheticSpikeSource` at `numBins` 8, and then asserts that at least one tick reported
`decodedByModel`. The shipped model's `spikes` input is `(1, 96, 1, 32)`, so it rejects the 8-bin
buffer on every tick and the pipeline falls back. This IS RESEARCH Pattern 2: the case asserts
"NDT1 genuinely in loop" against a configuration in which NDT1 structurally cannot be in the loop.

**Proven pre-existing, not caused by this plan.** The identical failure reproduces on a clean
checkout of commit `5bb164d`, which is before any `CortexDemo` file in this plan was touched:

```
git archive 5bb164d | tar -x -C <scratch>
CORTEX_MODEL_URL=<repo>/Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift test --package-path <scratch>/Packages/CortexDemo --filter modelBackedDecodePathPresent
# -> Expectation failed: anyModelTick   (identical to the post-change tree)
```

The `try?` the old code used and the `do`/`catch` the new code uses both return nil and both fall
back, so the observable outcome is unchanged; only the reason is now recorded.

**Deliberately NOT fixed here.** Plan 10-04 Task 2 says in writing "Do not modify or delete any
existing case", and the repair is a one-line change to a Phase-8 artifact. Repairing it means
constructing that case's pipeline with a source at `RecordedSpikeSource.modelSeqLen` (32) so the
assertion exercises what it claims. `RecordedSpikeSourceTests` Test 9 already covers the same
ground for the new code and skips cleanly when no model is present.

**Who should pick it up.** Any later Phase-10 plan that runs the CortexDemo suite with
`CORTEX_MODEL_URL` set (10-06 and 10-09 are the likely ones) will see a red suite from this case
alone. Fix it in the same commit that first needs a model-wired green suite.

---

## From Plan 10-06 (2026-09-05): five out-of-scope findings

### 1. RESOLVED, not deferred: the model-wired CortexDemo suite is green

The item immediately above predicted that "10-06 and 10-09 are the likely ones" to see a red
`ClosedLoopPipelineTests` suite once `CORTEX_MODEL_URL` is set. Measured in this plan:

```
CORTEX_MODEL_URL=<repo>/Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift test --package-path Packages/CortexDemo
# -> Test run with 44 tests in 5 suites passed
```

The Plan 10-05 repair at `b18c6fa` held. Nothing is owed here; this note exists so the prediction
above is not read as still open.

### 2. `xcodegen generate` STRIPS hand-added Info.plist keys (not fixed, reverted)

Running `xcodegen generate` deletes four hand-added SYS-05 keys from two TRACKED files:

- `Apps/CortexMac/Info.plist` and `Apps/CortexiOS/Info.plist` each lose
  `CortexBCIHIDProtocolVersion` (`may-2025`) and `NSAccessibilityUsageDescription`, plus the comment
  block documenting why they are there.

Those keys are not declared in `project.yml`'s `info.properties`, so XcodeGen regenerates the plists
without them. Plan 10-06 had to run `xcodegen` for the daemon build and reverted both files with
`git checkout --`; nothing was committed. Any future plan that runs `xcodegen` will hit this and must
do the same, or the SYS-05 HID-provider surface silently disappears from the shipped bundles.

**Fix when someone owns it:** move the four keys into `project.yml` under each target's
`info.properties`, so regeneration is idempotent. That is a `project.yml` edit with a bundle-content
consequence, which is why it was not done inside a plan scoped to the daemon producer.

### 3. `ci.yml` names a `Cortex.xcworkspace` that nothing generates

Three CI steps invoke `xcodebuild -workspace Cortex.xcworkspace` (`ci.yml:435`, `:451`, `:467`), and
`project.yml:1` describes itself as generating "Cortex.xcodeproj and Cortex.xcworkspace". After
`xcodegen generate` only `Cortex.xcodeproj` exists, in this worktree AND in the canonical checkout;
`xcodebuild -workspace Cortex.xcworkspace` fails with "'Cortex.xcworkspace' does not exist". Plan
10-06 built the daemon with `-project Cortex.xcodeproj` instead and reached `BUILD SUCCEEDED`.

This has never been noticed because CI has never executed (see `cortex-ci-lint-gate-never-ran`). The
first real CI run trips it. Either add a `workspace:` section to `project.yml` or change the three
steps to `-project Cortex.xcodeproj`.

### 4. The Float16-on-macOS deferred item did NOT reproduce under Xcode 26.3

`STATE.md`'s Deferred Items row "xcodebuild of the CortexDaemon Xcode target fails on `'Float16' is
unavailable in macOS`" (deferred 2026-06-20, Plan 02-05) did not reproduce. With Xcode 26.3:

```
xcodegen generate
xcodebuild build -project Cortex.xcodeproj -scheme CortexDaemon -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
# -> ** BUILD SUCCEEDED **
```

The daemon binary runs, and its `bench` mode (Option A in `sc1-evidence.md`) is now reachable. That
row is a candidate for closure by whoever owns STATE.md; Plan 10-06 does not write STATE.md.

### 5. A fresh worktree cannot run `xcodebuild` until the Rust xcframework exists

`Packages/CortexRing/CortexRingFFI.xcframework` is a gitignored build artifact. Without it the whole
package graph fails to resolve ("local binary target 'CortexRingFFI' ... does not contain a binary
artifact"), so EVERY `xcodebuild` invocation fails in a fresh worktree regardless of what changed.
Run `Tools/scripts/build-rust.sh`, or symlink the artifact from the canonical checkout as Plan 10-06
did for `Decoder/exports` and `Decoder/data`. Worth one line in the worktree setup notes.

### 6. swiftformat/swiftlint are repo-wide non-compliant (unchanged by this plan)

Confirming `cortex-ci-lint-gate-never-ran` with fresh numbers. `swiftformat --lint` reports
`swiftTestingTestCaseNames` on every existing CortexDemo test file (`ClosedLoopPipelineTests` 16,
`ArmStatisticsTests` 24, `GlassToGlassTimerTests` 8) and `fileHeader` on every line of files such as
`Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift`. `swiftlint` reports 40
`identifier_name` violations in `Sources/CortexReplayBench/main.swift` alone, from the snake_case
`Encodable` fields that ARE the emitted JSON keys.

Plan 10-06 left every new file at or below the sibling baseline and added no new violation class:
`Apps/CortexDaemon/{Producer,main}.swift` measured 9 swiftlint findings before the change and 9
after; `RollingSpikeWindow.swift` and the new smoke are clean under both tools apart from the same
snake_case-JSON-key and file-length idioms `CortexReplayBench` already established. The repo-wide
sweep is still owed before the first PR.

## Plan 10-12 deferred item

**PERF-02 wording in REQUIREMENTS.md (line 125)**
- File: `.planning/REQUIREMENTS.md`
- Line: `- [ ] **PERF-02**: Document path toward Neuralink P1 verified peak (8.5 BPS) -- what gaps remain`
- Issue: "verified peak" applies authority to the 8.5 figure that D-17 explicitly denies ("not independently sourceable to a Neuralink primary; an access date does not authenticate a number"). Should read "retrieved / not independently sourceable" consistent with README and PROJECT.md.
- Out of scope for 10-12: REQUIREMENTS.md not in this plan's file list.
- Route to: Plan 10-14 honesty-sweep.sh (already reads REQUIREMENTS.md for LAT-0N check).

## Widen honesty-sweep.sh to the .planning root tracking files

**Deferred from:** Plan 10-14 residue, orchestrator follow-up 2026-09-07
**Blocking:** nothing. The residue it would have caught is already fixed by hand.

`honesty-sweep.sh` excludes all of `.planning/` from its label scan. `.planning/phases/` is correctly
excluded (bannered historical evidence, owned by assertion (b)). The three root tracking files
(`ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`) are a different case: they are read as current truth
and become public at Plan 10-17.

Two things were established by test, not assumed:

- The stated reason for excluding them ("machine-maintained ... so a label added there by hand is not
  durable") does not hold for the phase-completion bullets. `donny-tools roadmap
  update-plan-progress 10` rewrites only the progress-table row; hand-added labels on lines 30/32/33
  survived it intact.
- With the seven labels added on 2026-09-07 (ROADMAP 30/32/33, PROJECT 61/153, REQUIREMENTS 47/49) a
  widened scan that excludes only `.planning/phases/` and `.planning/STATE.md` reports zero findings.

So widening is now free of content churn. It was not done here because a scan-scope change needs its
own negative control in the same commit, which is plan work rather than an orchestrator edit. Pick it
up in a v1.1 hardening plan: exclude `.planning/phases/` and `.planning/STATE.md` instead of
`.planning/`, and add a control that puts an unlabeled superseded number into a root tracking file
and requires exit 1.

## Plan 10-16 deferred items

### 1. `xcodegen` Info.plist stripping reproduced again (item 2 above, still open)

Plan 10-16's Task-3d battery runs `xcodegen generate`, and it stripped the same four SYS-05 keys from
`Apps/CortexMac/Info.plist` and `Apps/CortexiOS/Info.plist` that Plan 10-06 documented above. Both
files were reverted with `git checkout --` and neither appears in any 10-16 commit. Confirming that
the finding is live and reproducible under Xcode 26.3 / XcodeGen as of 2026-09-07, and that every
plan running `xcodegen` still has to revert by hand. 10-16 could not fix it: its execution boundary
forbids editing `project.yml`, which is where the fix belongs.

Also re-confirmed: item 5 above. This worktree could not run any `xcodebuild` until
`Tools/scripts/build-rust.sh` produced `Packages/CortexRing/CortexRingFFI.xcframework`, failing with
the exact "does not contain a binary artifact" error quoted there.

### 2. SwiftLint prints two config warnings on every invocation

`unused_declaration` and `unused_import` are listed in BOTH `opt_in_rules` and `analyzer_rules` in
`.swiftlint.yml`. Every `swiftlint` run therefore emits to stderr:

```
warning: 'unused_declaration' should be listed in the 'analyzer_rules' configuration section for more clarity as it is only run by 'swiftlint analyze'.
warning: 'unused_import' should be listed in the 'analyzer_rules' configuration section for more clarity as it is only run by 'swiftlint analyze'.
```

Exit code is unaffected and no violation is reported, so `--strict` still passes. Not fixed in 10-16:
deleting the two `opt_in_rules` entries is behaviour-neutral but unrelated to clearing the roster,
and 10-16's `.swiftlint.yml` diff has to be read line by line for its deliberate exceptions. These
two lines will appear in 10-17's first CI log and are cosmetic.
