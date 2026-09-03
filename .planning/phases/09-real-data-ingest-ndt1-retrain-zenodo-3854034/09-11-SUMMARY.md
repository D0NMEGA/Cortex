---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 11
subsystem: testing
tags: [coreml, ane, latency, human-uat, evidence-discipline, ipad-m4, mlcomputeplan]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: "Plan 09-08's corroborating M5 Pro decoder latency (p99 0.141083 ms, MEASURED CPU placement) and the 239/239 ANE eligibility scan, both committed in 09-coreml-evidence.md and 09-decoder-metrics.json"
provides:
  - "09-HUMAN-UAT.md: the RD-06b canonical iPad Pro M4 p99 gate, documented as a verbatim runbook and PRESENTED for a human decision"
  - "The prerequisite list for the capture, including the free-Personal-team GUI-only signing constraint that rules out a CLI xcodebuild path"
  - "An explicit restatement of the eligibility-versus-placement split, which is the reason the gate exists"
affects: [phase-10, deployment-artifact-choice, requirements-RD-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A device-gated measurement is documented, presented, and left unresolved rather than approximated"
    - "The literal placeholder `not measured` occupies every value slot a capture would fill"

key-files:
  created:
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-HUMAN-UAT.md
  modified: []

key-decisions:
  - "The gate is PRESENTED, not auto-approved, despite workflow.auto_advance being true: a hardware measurement an agent approves for itself is a fabricated credibility number"
  - "No iPad-M4 latency value exists anywhere in the repository; every value slot in the disposition table reads the literal string `not measured`"
  - "The runbook's device leg is written for the Xcode GUI because the only local signing identity is a free Personal team, which a command-line xcodebuild cannot provision"
  - "The runbook points at the package the phase now recommends shipping (fp16) while keeping the 4-bit path, because the committed corroborating latency entry was measured on the 4-bit package"

patterns-established:
  - "Disposition table with an explicit PRESENTED state, distinct from CAPTURED and DEFERRED, so an unresolved gate cannot read as a pass"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: []

# Metrics
duration: 7min
completed: 2026-09-02
---

# Phase 9 Plan 11: RD-06b device gate Summary

**The canonical iPad Pro M4 p99 capture is documented as a copy-pasteable runbook with its prerequisites and presented for a human decision; it was not performed, not auto-approved, and no iPad-M4 number was written anywhere.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-09-03T02:33:00Z
- **Completed:** 2026-09-03T02:40:00Z
- **Tasks:** 1 of 2 complete; task 2 is the checkpoint and is PRESENTED, awaiting the user
- **Files modified:** 1 created, 0 modified

## Accomplishments

- `09-HUMAN-UAT.md` written (254 lines): one gate, RD-06b, with a never-auto-approved banner that
  states the reason rather than asserting the rule.
- The committed corroborating measurement transcribed exactly from the `latency` section of
  `09-decoder-metrics.json`: p50 0.130708 ms, p99 0.141083 ms, n 10,000 after 50 warmup passes,
  min 0.110458 ms, max 0.355584 ms, on Apple M5 Pro (arm64) / macOS-26.5-arm64-arm-64bit under
  `.cpuAndNeuralEngine`, placement MEASURED as CPU, `status: corroborating`. Stated plainly that
  this number is sufficient for the phase to complete and that the canonical capture is an optional
  refinement under D-17, not a gate on RD-06.
- The eligibility-versus-placement distinction preserved as its own section: 239/239 ANE-eligible
  with 0 CPU-only is a compiler property, closed on the dev Mac and device-independent; placement is
  a runtime scheduler decision that the 1.29M-parameter scale trap pushes to CPU on Mac, and that
  only a run on the target device can answer. The section also records that a capture returning CPU
  placement is a valid result to be written down, not a run to be repeated until it reads
  `NeuralEngine`.
- Four prerequisites listed with their real current status, including the one that matters
  operationally: the only local signing identity is the free Personal team `57YW6M29S7`, which signs
  GUI-only, so the device leg is written for the Xcode GUI and no unusable command line is offered.
- Runbook split into three steps: rebuild the artifact with `rederive_coreml.py`, an optional
  same-day Mac A/B with `CortexDecoderBench`, and the device leg via the Xcode GUI plus an
  Instruments Core ML trace. The exact fields to transcribe back are named (`p50_ns`, `p99_ns`,
  `min_ns`, `max_ns`, `count`, `deviceAnnotation`, the `MLComputePlan` preferred-device tally, the
  device and OS string), along with an explicit instruction not to transcribe a serial number, UDID,
  or account identifier.
- Two honest operational details found by reading the bench source rather than assuming: `swift run`
  builds for the host and cannot target an iPad, so the device leg needs an Xcode-built host; and
  the bench's `.bench/` output path derives from `#filePath`, which does not exist in the iOS
  sandbox, so on device the histogram write fails non-fatally and the numbers must be read from the
  Xcode console.

## Task Commits

1. **Task 1: Write 09-HUMAN-UAT.md, the runbook and the prerequisites** - `1a88d9e` (docs)
2. **Task 1 follow-up: point the runbook at the artifact the phase now ships** - `f617b68` (docs)
3. **Task 2: Present the RD-06b gate** - no commit; the checkpoint is PRESENTED and unresolved

## Files Created/Modified

- `.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-HUMAN-UAT.md` - the single
  RD-06b device gate: the never-auto-approved statement and its reason, the committed corroborating
  Mac number, the eligibility-versus-placement section, four prerequisites with status, the
  three-step runbook, what a capture would add, the disposition table, and the honesty clause.

## The checkpoint: presented, not resolved

**Task 2 is `type="checkpoint:human-verify"` with `gate="blocking"`, and the plan is
`autonomous: false`. Execution stopped here.**

**User response: none yet. The gate was presented to the orchestrator for the user; no reply has
been received, so no disposition was recorded.** The disposition table in `09-HUMAN-UAT.md` reads
`PRESENTED, awaiting user decision` dated 2026-09-02, and every value slot reads the literal string
`not measured`.

`workflow.auto_advance` is `true` in `.planning/config.json` and the plan-level verification
commands are green, but this gate was still not auto-approved. Green software verification is not
the thing this gate measures. It measures what a physical iPad Pro M4 does with the model, and no
such device is present. Auto-approving it would have produced a fabricated iPad-M4 p99, which is the
precise failure Phase 9 was opened to eliminate and which the three Phase-8 gates deferred on
2026-06-23 correctly refused.

The two outcomes are already specified in the artifact so that whoever resumes has no discretion to
invent a third:

- **captured** plus values: write a `CAPTURED` row with the date and the reported p50, p99, pass
  count, device annotation and preferred-device tally, and add a second, clearly labeled canonical
  entry to `latency` in `09-decoder-metrics.json`. The corroborating Mac entry stays byte-identical
  and is never relabeled.
- **defer**: write a `DEFERRED` row with the date and the blocking prerequisite (a provisioned iPad
  Pro M4 on iPadOS 26, paired with Xcode 26.3, signed through the GUI). Write no iPad-M4 number
  anywhere. RD-06 stands on the corroborating Mac measurement, which is what D-17 permits.

## Decisions Made

- `requirements-completed` is left empty. RD-06's corroborating half was closed by plan 09-08 and is
  committed; its canonical half is the gate presented here and is unresolved. Marking RD-06 complete
  from this plan would assert a device measurement that was never taken.
- The artifact is pure ASCII with sentence-case headings, unlike the Phase-5 and Phase-8 precedents
  it mirrors structurally. The project's writing convention (no em dashes, no emoji, ASCII only) was
  applied over the older files' formatting.
- The disposition table carries a third state, `PRESENTED`, distinct from `CAPTURED` and `DEFERRED`.
  The plan's own Task-2 verify only accepts the latter two, which is correct for a resolved gate;
  `PRESENTED` is what an unresolved one honestly reads as, and it will be replaced by one of the two
  terminal states when the user decides.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The runbook named an artifact the phase had just stopped shipping**

- **Found during:** Task 1, after the artifact was first committed at `1a88d9e`.
- **Issue:** The plan's runbook text points `CORTEX_DECODER_MODEL_URL` at
  `ndt1_real_vel_4bit.mlpackage`. While this plan was executing, the concurrent 09-08 palettization
  follow-up committed `a222bca`, which settles the deployment-artifact question on the **fp16**
  package (4-bit per-tensor palettization collapses held-out velocity R2 to -1.786971; per-channel
  recovers it only to +0.191784) and adds a third committed latency candidate at p99 0.165042 ms. A
  canonical capture that measured a package the project had decided not to ship would be a
  misleading instruction.
- **Fix:** Named all three committed corroborating figures, recorded that the recommendation is to
  ship fp16, and pointed the runbook's device leg at the shipping package while keeping the 4-bit
  path documented, since the committed `latency` entry was measured on it. No number was changed.
- **Files modified:** `09-HUMAN-UAT.md`
- **Verification:** the plan's Task-1 automated verify re-run green, including the assertion that
  `latency.p99_ms` (0.141083) appears verbatim; every numeric latency token in the file was
  enumerated and matched against committed values.
- **Committed in:** `f617b68`

**Total deviations:** 1 auto-fixed (1 bug).
**Impact on plan:** contained to this plan's single declared file. No scope creep; the concurrent
agent's files were read but never written.

## Issues encountered

- A concurrent agent held uncommitted changes to `09-decoder-metrics.json` for part of this run. It
  committed them at `a222bca` before either of this plan's commits, so nothing was co-staged; both
  commits here were verified to contain exactly one file. Files were staged individually and the
  donny `commit` wrapper was avoided in favor of plain git, because a state-sync step that reverts
  uncommitted `.planning` edits is a documented hazard in this repo and would have destroyed the
  other agent's in-flight work. No git post-commit hook that does this is currently installed
  (`.git/hooks` holds only samples), so the risk did not materialize.
- The plan's `<verification>` block ran clean: `decoder-policy.sh` and its `--self-test` both exit
  0 (4 negative controls bite as designed), `latency.status` is still `corroborating` on
  `Apple M5 Pro (arm64), macOS-26.5-arm64-arm-64bit`, and the Decoder quick suite passes 208 tests
  in 5.23 s (one more than the 207 recorded at the start of this run; the extra test came from the
  concurrent agent's commit).
- Nothing was deferred. `deferred-items-09-11.md` was not created because no out-of-scope discovery
  was made.

## User setup required

None from this plan. The gate itself describes hardware the user may or may not choose to obtain;
that is the decision being presented, not a setup step.

## Next phase readiness

- RD-06 is closed on its corroborating half and open on its canonical half. Phase 9 can complete on
  the corroborating measurement, which is exactly what D-17 permits, provided the gate's disposition
  is recorded honestly as unresolved or deferred rather than passed.
- The open question this plan does not touch, and which belongs to Phase 10, is the deployment
  artifact: shipping fp16 gives up the 3.4x size reduction, and the untested candidates are
  refitting the readout on the palettized encoder's output and excluding the encoder from
  palettization.
- If an iPad Pro M4 is ever provisioned, the runbook in `09-HUMAN-UAT.md` flips this gate with no
  code change.

## Self-Check: PASSED

- `09-HUMAN-UAT.md` exists at the specified path: FOUND (254 lines, pure ASCII, 0 non-ASCII bytes).
- Commit `1a88d9e` exists: FOUND (1 file, 245 insertions).
- Commit `f617b68` exists: FOUND (1 file, 15 insertions, 6 deletions).
- Plan Task-1 automated verify: PASSED (all seven required tokens present; committed `p99_ms`
  0.141083 transcribed verbatim; zero matches for either of the two retired v1 glass-to-glass
  tokens the plan forbids).
- No fabricated measurement: every numeric latency token in the artifact was enumerated and each one
  maps to a committed value in `09-decoder-metrics.json` (0.110458, 0.130666, 0.130708, 0.131291,
  0.141083, 0.141959, 0.165042, 0.355584 ms) or to the 2 ms budget. No iPad-M4 value exists.
- Cross-file check: `grep -rn "iPad" .planning/phases/09-*/ | grep -iE 'p99|latency'` returns only
  canonical-capture and deferral framing. No file labels a Mac measurement as an iPad-M4 result.
- Gate state: PRESENTED, not auto-approved, not resolved.

*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Plan: 09-11 - the RD-06b canonical device gate*
*Completed: 2026-09-02*
