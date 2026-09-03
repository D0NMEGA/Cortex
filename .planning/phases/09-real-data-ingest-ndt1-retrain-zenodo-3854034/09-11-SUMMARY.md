---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 11
subsystem: testing
tags: [coreml, ane, latency, human-uat, evidence-discipline, ipad-m2, mlcomputeplan, scale-trap]

# Dependency graph
requires:
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: "Plan 09-08's corroborating M5 Pro decoder latency (p99 0.141083 ms, MEASURED CPU placement), the 239/239 ANE eligibility scan, and the 226-to-239 op-count correction, all committed in 09-coreml-evidence.md and 09-decoder-metrics.json"
provides:
  - "09-HUMAN-UAT.md: the RD-06b canonical iPad Pro M4 p99 gate, documented as a verbatim runbook and recorded DEFERRED with its prerequisite"
  - "09-perf-report-ipad-m2.json: a raw Xcode Core ML Performance Report from an iPad Air 11-inch (M2), the phase's first real-hardware measurement of the trained graph"
  - "Independent on-device confirmation of the 226-to-239 op-count correction, through a tool that never touches the compile_model path that caused the stale reads"
  - "The prerequisite list for the canonical capture, including the free-Personal-team GUI-only signing constraint"
affects: [phase-10, deployment-artifact-choice, requirements-RD-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A device-gated measurement is documented, presented, and left deferred rather than approximated"
    - "A capture on non-target silicon is recorded as corroborating and never promoted to the canonical row"
    - "Reported figures are recomputed from the raw artifact rather than transcribed from a message"

key-files:
  created:
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-HUMAN-UAT.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-perf-report-ipad-m2.json
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-11.md
  modified: []

key-decisions:
  - "The gate was presented, not auto-approved, despite workflow.auto_advance being true: a hardware measurement an agent approves for itself is a fabricated credibility number"
  - "The iPad Air M2 capture is recorded as corroborating and does NOT close RD-06's canonical half; the canonical iPad Pro M4 row stays DEFERRED with its prerequisite and reads `not measured`"
  - "Every reported M2 figure was recomputed from the raw report rather than transcribed, which is how the unverifiable hardware string iPad14,8 was caught and dropped"
  - "The runbook's device leg is written for the Xcode GUI because the only local signing identity is a free Personal team, which a command-line xcodebuild cannot provision"
  - "The raw performance report is committed whole, following the Phase-5 precedent, so a reviewer can recompute every figure from the tool's own output"

patterns-established:
  - "Disposition table carries a canonical row and a separate corroborating row, so a non-target-device capture cannot read as closing the gate"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: []

# Metrics
duration: 70min
completed: 2026-09-02
---

# Phase 9 Plan 11: RD-06b device gate Summary

**The canonical iPad Pro M4 gate is documented, presented and recorded DEFERRED; a real capture on an iPad Air M2 is committed beside it as corroborating evidence that independently confirms the 226-to-239 op-count correction on hardware.**

## Performance

- **Duration:** 70 min
- **Started:** 2026-09-03T02:33:00Z
- **Completed:** 2026-09-03T03:43:00Z
- **Tasks:** 2 of 2 resolved. Task 2 was the blocking checkpoint; it was presented, not auto-approved, and the returned decision is recorded.
- **Files modified:** 3 created, 0 modified

## Accomplishments

- `09-HUMAN-UAT.md` written and then updated with the capture (386 lines): one gate, RD-06b, with a
  never-auto-approved banner that states the reason rather than asserting the rule.
- The committed corroborating Mac measurement transcribed exactly from the `latency` section of
  `09-decoder-metrics.json`: p50 0.130708 ms, p99 0.141083 ms, n 10,000 after 50 warmup passes, on
  Apple M5 Pro under `.cpuAndNeuralEngine`, placement MEASURED as CPU, `status: corroborating`.
- A real device capture recorded and committed raw as `09-perf-report-ipad-m2.json`, sha256
  `b3d85f26758346be4e15f43793a7e872d2fdce026ceecaca648fddf4535a9f8b`, byte-identical to the source
  bundle. It is the phase's first measurement of the trained graph on physical hardware.
- The eligibility-versus-placement distinction preserved and now demonstrated rather than argued:
  239/239 ANE-eligible with a measured `{cpu: 239}` placement, on a device where the Neural Engine
  and GPU were both available and the compute-unit set was `.all`.
- Four prerequisites listed with real status, including the free Personal team `57YW6M29S7` signing
  GUI-only, so no unusable command line is offered for the device leg.
- Runbook in three steps with the exact fields to transcribe back, plus two operational details
  found by reading the bench source rather than assuming: `swift run` builds for the host and cannot
  target an iPad, and the bench's `.bench/` output path derives from `#filePath`, which does not
  exist in the iOS sandbox, so on device the numbers come from the Xcode console.

## Task Commits

1. **Task 1: Write 09-HUMAN-UAT.md, the runbook and the prerequisites** - `1a88d9e` (docs)
2. **Task 1 follow-up: point the runbook at the artifact the phase now ships** - `f617b68` (docs)
3. **Task 2 presented; plan summary recorded** - `033aba4` (docs)
4. **Task 2 resolved: record the iPad Air M2 capture, canonical M4 gate stays deferred** - `cb5f7cb` (docs)

## Files Created/Modified

- `.planning/phases/09-.../09-HUMAN-UAT.md` - the RD-06b gate: the never-auto-approved statement and
  its reason, the committed corroborating Mac number, the iPad Air M2 capture section, the
  eligibility-versus-placement section, four prerequisites, the three-step runbook, the two-row
  disposition table, and the honesty clause.
- `.planning/phases/09-.../09-perf-report-ipad-m2.json` - the raw Xcode Core ML Performance Report,
  committed unmodified so every figure is independently recomputable.
- `.planning/phases/09-.../deferred-items-09-11.md` - four out-of-scope discoveries, all in files
  owned by other plans.

## The checkpoint: presented, then resolved as deferred

**Task 2 is `type="checkpoint:human-verify"` with `gate="blocking"`, and the plan is
`autonomous: false`. Execution stopped and the gate was presented.**

`workflow.auto_advance` is `true` and the plan-level verification commands were green, but the gate
was not auto-approved. Green software verification is not what this gate measures. It measures what
a physical iPad Pro M4 does with the model. Auto-approving it would have produced a fabricated
iPad-M4 p99, which is the precise failure Phase 9 was opened to eliminate.

**Response received, recorded verbatim in substance:** the user ran a device capture, but on an
**iPad Air 11-inch (M2), NOT an iPad Pro M4**. The instruction was to record it as an M2
measurement, leave the canonical M4 row open and deferred, not let it close RD-06's canonical half,
and write no M4 number. The source artifact was named for copying into the phase directory as
`09-perf-report-ipad-m2.json`, mirroring the Phase-5 precedent.

That is what was done. The disposition table now carries two rows: the canonical iPad Pro M4 gate is
**DEFERRED** with its prerequisite, and the iPad Air M2 capture is **CAPTURED, corroborating**. Every
canonical M4 value still reads the literal string `not measured`.

### What the capture shows, all recomputed from the raw report

Method: Xcode Core ML Performance Report against `ndt1_real_vel_sweep_fp16.mlpackage`, the fp16
with-velocity model plan 09-08 recommends shipping. Its 2,708,540 byte size matches the fp16 package
in the committed palettization table exactly. Phase 5 used the same method on the same device, so
the two captures are directly comparable.

| Quantity | Value |
|---|---|
| Device / OS | iPad Air 11-inch (M2) / iPadOS 18.7.8 |
| Compute units | enum 2 (`.all`); neuralEngine, gpu and cpu all listed available |
| Schedulable ops | 239 |
| ANE eligibility | 239 / 239 |
| Preferred-device tally | {cpu: 239}, zero ANE, zero GPU |
| n | 120 predict samples (loadCount 3, experimentIterations 3, predictionCount 40) |
| min / p50 / p90 / p99 / max | 0.1881 / 0.2240 / 0.2710 / 0.5790 / 4.9390 ms |

Percentiles are nearest-rank, the convention `CortexDecoderBench` uses, so they line up with the Mac
figures. Nearest-rank and linear interpolation differ here (p99 0.5790 against 0.5729), which is why
the method is stated rather than assumed.

**The most valuable result is not the latency.** Recomputing the op-type histogram across the
Phase-5 and Phase-9 committed reports reproduces plan 09-08's correction exactly: `ios18.batch_norm`
0 to 12, `ios18.add` 24 to 25, every other op type identical, total 226 to 239. Plan 09-08 derived
that on the Mac after finding that `compile_model` nests its output via `shutil.move` and every ANE
scan since 2026-06-21 had been reading a stale compile. The Xcode Performance Report never touches
that code path, and this ran on different silicon with a different tool. Same answer.

The scale trap is also now reproduced on trained weights on real hardware: `{cpu: 239}` with the ANE
available and the compute-unit set at `.all`. Phase 5 saw `{cpu: 226}` on an untrained model. The
p99 sits inside the 2 ms decoder budget with about 3.5x headroom regardless of placement.

### Caveats recorded rather than smoothed over

- M2 is not M4: different silicon, different Core ML scheduler generation. Nothing here settles what
  an M4 would do.
- iPadOS 18.7.8 is not the iPadOS 26 baseline. It matches Phase 5's capture OS, which is what makes
  the M2-to-M2 comparison clean, but it is not the target OS.
- The report ran under `.all` (enum 2); the committed Mac number was measured under
  `.cpuAndNeuralEngine` (enum 3, the DEC-07 production set). The two configurations are not
  identical. Phase 5 had the same mismatch.
- The 4.9390 ms max is the first of the 120 samples, a cold-start outlier. It is reported because it
  happened and is never presented as the p99.
- The committed M5 Pro number was not relabeled or touched.

## Decisions Made

- `requirements-completed` is left empty, and the coordinator confirmed this judgment stands. RD-06's
  corroborating half was closed by plan 09-08; its canonical half is the deferred gate. Marking RD-06
  complete would assert a device measurement nobody took.
- The raw report is committed whole rather than reduced to a table, following the Phase-5 precedent,
  so a reviewer can recompute every figure. The identifier consequence is flagged in
  `deferred-items-09-11.md`.
- The artifact is pure ASCII with sentence-case headings, unlike the Phase-5 and Phase-8 precedents
  it mirrors structurally. The project's writing convention was applied over the older formatting.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] The runbook named an artifact the phase had just stopped shipping**

- **Found during:** Task 1, after the artifact was first committed at `1a88d9e`.
- **Issue:** The plan's runbook points `CORTEX_DECODER_MODEL_URL` at `ndt1_real_vel_4bit.mlpackage`.
  While this plan was executing, the concurrent 09-08 palettization follow-up committed `a222bca`,
  which settles the deployment artifact on **fp16** (4-bit per-tensor collapses held-out velocity R2
  to -1.786971; per-channel recovers it only to +0.191784) and adds a third latency candidate at p99
  0.165042 ms. A canonical capture measuring a package the project had decided not to ship would be
  a misleading instruction.
- **Fix:** Named all three committed corroborating figures, recorded the fp16 recommendation, and
  pointed the device leg at the shipping package while keeping the 4-bit path documented, since the
  committed `latency` entry was measured on it. No number was changed.
- **Files modified:** `09-HUMAN-UAT.md`
- **Verification:** the plan's Task-1 automated verify re-ran green; every numeric latency token in
  the file was enumerated and matched against committed values.
- **Committed in:** `f617b68`

**2. [Rule 2 - Missing Critical] The runbook forbade transcribing identifiers that the committed evidence format carries**

- **Found during:** Task 2 resolution, when committing the raw report.
- **Issue:** The runbook said not to transcribe a serial number or UDID, and threat T-09-11-05's
  `accept` rationale rested on that. But the Phase-5 precedent commits the raw Xcode report whole,
  and that report carries `deviceID`, `serialNumber` and the device display name. Committing this
  capture the same way would have silently contradicted the file's own rule and falsified the threat
  rationale.
- **Fix:** Reconciled the rule to what the repository actually does: identifiers stay out of the
  transcribed prose, the raw report is committed whole for recomputability, and the note records
  that the same three values for the same device are already committed from Phase 5, so this adds no
  identifier the repository did not already hold. Logged item 3 in `deferred-items-09-11.md`: if the
  repo is ever published, both reports must be scrubbed together or neither.
- **Files modified:** `09-HUMAN-UAT.md`, `deferred-items-09-11.md`
- **Verification:** confirmed by reading the Phase-5 committed report, which carries the identical
  `deviceID` `[redacted-device-id]` and `serialNumber`.
- **Committed in:** `cb5f7cb`

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical).
**Impact on plan:** contained to this plan's own files. No scope creep; files owned by other plans
were read but never written.

## Issues encountered

- **One coordinator-supplied value could not be verified and was dropped.** The message reported the
  hardware string `iPad14,8`. That string appears nowhere in the report (`grep -c` returns 0); the
  report identifies the device only as `iPad Air 11-inch (M2)`. Only what the artifact says was
  recorded. Every other supplied value was confirmed exactly: 239 ops, `{cpu: 239}`, 239/239
  eligible, n=120, the five latency percentiles, the perfRunConfig triple, batchNorm 12, add 25, and
  the 2,708,540 byte model size.
- **The source path in the message did not resolve.** It used a straight apostrophe; the actual
  bundle name uses U+2019. Located by `find` and copied; the committed file's sha256 matches the
  source byte for byte.
- A concurrent agent held uncommitted changes to `09-decoder-metrics.json` for part of this run and
  committed them at `a222bca` before any commit here. Files were staged individually and the donny
  `commit` wrapper was avoided in favor of plain git, because a state-sync step that reverts
  uncommitted `.planning` edits is a documented hazard in this repo and would have destroyed the
  other agent's in-flight work. Every commit here was verified to contain only its intended files.
- The plan's `<verification>` block ran clean: `decoder-policy.sh` and its `--self-test` both exit 0
  with all four negative controls biting, `latency.status` is still `corroborating` on
  `Apple M5 Pro (arm64)`, and the Decoder quick suite passes 208 tests in 5.23 s.
- Four out-of-scope discoveries were logged to `deferred-items-09-11.md` rather than acted on. The
  two that matter: `09-coreml-evidence.md` and `09-decoder-metrics.json` should gain the M2 row, and
  both are owned by plan 09-08.

## User setup required

None from this plan. The remaining prerequisite is hardware: a provisioned iPad Pro M4 on iPadOS 26.

## Next phase readiness

- RD-06 is closed on its corroborating half, now with two independent device measurements, and open
  on its canonical half. Phase 9 can complete on the corroborating tier, which is what D-17 permits,
  provided the canonical gate stays recorded as deferred.
- The M2 capture retroactively strengthens plan 09-08's op-count correction, which was previously
  supported only by Mac-side scans through the code path that had been returning stale reads.
- The open question this plan does not touch, and which belongs to Phase 10, is the deployment
  artifact: shipping fp16 gives up the 3.4x size reduction, and the untested candidates are
  refitting the readout on the palettized encoder's output and excluding the encoder from
  palettization.
- If an iPad Pro M4 is ever provisioned, the runbook in `09-HUMAN-UAT.md` flips the canonical row
  with no code change.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: information-disclosure | `.planning/phases/09-.../09-perf-report-ipad-m2.json` | T-09-11-05 dispositioned identifier leakage as `accept`, on the stated rationale that "no serial number, UDID or account identifier is requested by the runbook". That rationale describes the transcribed prose, which is still clean. It does not describe the raw Xcode report, which is committed whole per the Phase-5 precedent and carries `deviceID`, `serialNumber` and the device display name. The disposition outcome is unchanged (the identical values for the same device were already committed in Phase 5, so nothing new is exposed), but the rationale as written is narrower than the artifact. Recorded rather than quietly relied on. Remediation, if the repository is published, is item 3 of `deferred-items-09-11.md`: scrub both reports together or neither. |

No new network endpoints, auth paths or trust-boundary schema changes were introduced. This plan
created documentation and one raw measurement artifact.

## Self-Check: PASSED

- All three files exist at their specified paths: FOUND (`09-HUMAN-UAT.md` 386 lines,
  `09-perf-report-ipad-m2.json` 1,049,291 bytes, `deferred-items-09-11.md` 50 lines). All ASCII
  except the raw JSON report, which is committed byte-identical to the tool's output.
- Commits `1a88d9e`, `f617b68`, `033aba4`, `cb5f7cb` all exist; each was verified to contain only
  its intended files.
- Plan Task-1 automated verify: PASSED (all required tokens present; committed `p99_ms` 0.141083
  transcribed verbatim; zero matches for either of the two retired v1 glass-to-glass tokens the plan
  forbids).
- Plan Task-2 automated verify: PASSED (`09-HUMAN-UAT.md` contains both `DEFERRED` and `CAPTURED`; a
  disposition is recorded).
- Evidence integrity: the committed report's sha256 equals the source bundle's,
  `b3d85f26758346be4e15f43793a7e872d2fdce026ceecaca648fddf4535a9f8b`.
- No fabricated measurement: every latency-shaped number in `09-HUMAN-UAT.md` was enumerated and each
  maps either to a committed Mac value (0.110458, 0.130666, 0.130708, 0.131291, 0.141083, 0.141959,
  0.165042, 0.355584 ms), to a value recomputed from the committed M2 report (0.1881, 0.2240, 0.2710,
  0.5790, 4.9390 ms), or to the 2 ms budget. **No iPad-M4 value exists anywhere in the repository.**
- Canonical row integrity: all six canonical M4 fields still read the literal string `not measured`.
- Gate state: canonical M4 DEFERRED with its prerequisite; M2 capture CAPTURED as corroborating; not
  auto-approved.

*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Plan: 09-11 - the RD-06b canonical device gate*
*Completed: 2026-09-02*
