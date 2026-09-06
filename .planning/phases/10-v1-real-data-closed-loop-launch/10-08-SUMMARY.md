---
status: PARTIAL
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 08
subsystem: evidence
tags: [rd-08, seam-a, seam-b, glass-to-glass, latency, webgrid, d-09, d-11, sc2, ipc, amplitude-shrinkage]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: "Plan 10-04's CortexDemoBench --real (Seam A) and CortexCore.ReplayExport; Plan 10-06's CortexSeamBSmoke (Seam B chain); Plan 10-07's four-arm ablation 10-refit-real.json; Plan 10-01's 10-ceiling.json recorded-cursor replay reference; 10-PREREGISTRATION sections 1, 3a, 7, 9, 10, 11, 12, 13, 14, 15, 16, 18"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: "the shipped ndt1_real_vel_sweep_fp16.mlpackage and the per-session held-out velocity R2"
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: "the Phase-8 synthetic glass-to-glass p99 (8318256 ns) and the measurement geometry Seam A holds fixed"
provides:
  - "10-replay.json - the two-seam latency, the closed-loop hit and proxy numbers, and the five-factor D-11 decomposition, all provenance-bound"
  - "10-replay-evidence.md - the narrated RD-08 result with both boundaries defined and separated"
  - "CortexSeamBSmoke chain-latency instrumentation (p50/p99/max per completed window) and velocity_amplitude_shrinkage measurement"
  - "The measured answer to RD-08's latency half: Seam A p99 8831017 ns on the real-data path, model-backed on every tick"
  - "The full section-15 adjudication of SC#2, published as sc2_adjudication, with the enum left for the user"
affects: [10-09, 10-10, 10-11, 10-12, 10-14, rd-08, rd-09, sc2-adjudication]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A latency number is published as a distribution over repeated runs, never as one invocation, with the summary convention stated in the artifact"
    - "A measurement instrument is added to an existing binary without touching the frame format, the crypto or the counters, and says so in its own doc comment"
    - "Two seams that span different boundaries carry distinct boundary strings and the historical figure is physically absent from the wider seam's section"
    - "A statistic that is not stable across runs is labeled unstable in the artifact rather than published as if it were"
    - "When two pre-registered sections select different outcomes, the conflict is published in full and the enum is left to the checkpoint the contract reserves for the user"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-replay.json
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-replay-evidence.md
  modified:
    - Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift

key-decisions:
  - "Seam A's headline is the DEBUG build, because 08-03-SUMMARY.md records the Phase-8 command with no -c release and SwiftPM defaults to debug. Both configurations were run five times each and both are reported, since the summary never uses the word debug"
  - "The recorded-cursor replay reference is emitted as replay_reference_hits / replay_reference_ref, per 10-PREREGISTRATION section 11, NOT as the plan's ceiling_hits / ceiling_ref, which section 11 states in writing are not emitted"
  - "sc2_disposition and sc2_rule are ABSENT. Section 15's first column selects row A on the refit arm's 70 hits while section 7 makes only the target-blind arms attributable and those are 0 of 1025, which is row B's shape. Section 15 rule 2 forbids an agent from amending a success criterion, so the full adjudication is published as sc2_adjudication and Plan 10-10 Task 3b writes the enum"
  - "Seam B's latency is measured and published WITH its number, not omitted, because the in-process lock-step run puts both clock reads on one mach_absolute_time timebase in one thread. The cost of in_process is stated as a floor rather than an estimate"
  - "Seam B ran over the FULL export at --frames 73159 rather than the plan's 4096, so the amplitude measurement covers the same replay as the ablation. 73159 and not 73160 because seq maps to bin as seq % binCount with seq starting at 1"
  - "velocity_amplitude_shrinkage is a RATIO OF SUMMARIES (mean of decoded over mean of true, p95 over p95), not a summary of per-window quotients, because that quotient diverges at every reach reversal"
  - "hits_by_arm and distance_to_target_mm.by_arm were added so the target-blind zero is not hidden behind the refit arm's target-determined 70"

patterns-established:
  - "Every narrated number is matched back to a committed artifact by script before the commit, not proofread"
  - "An acceptance check written at line granularity on a hard-wrapped document is re-expressed at sentence granularity rather than satisfied by rewrapping the prose"

requirements-completed: [RD-08]

# Metrics
metrics:
  duration: ~75 min
  completed: 2026-09-05
  tasks: 2
  commits: 3
  files-changed: 3
  lines-added: 989
---

# Phase 10 Plan 08: RD-08's two measurement seams and the webgrid hit result Summary

**The software-timed glass-to-glass p99 on the real-data path is 8831017 ns at the unchanged Phase-8 boundary with NDT1 in the loop on all 2294 ticks, the wider daemon-to-decode chain runs at a 0.136 ms median across 73,128 windows in one process, and the arms attributable to the decode scored 0 webgrid hits of 1,025 against a recorded-cursor replay reference of 147 whose closest approach was 5.8 acquisition radii away.**

## Performance

- **Duration:** about 75 min
- **Tasks:** 2
- **Files:** 2 created, 1 modified
- **Commits:** 3

## Task commits

| # | Task | Commit | Type |
|---|---|---|---|
| 1 | Seam B chain-latency and amplitude instrumentation | `a8e9452` | feat |
| 1 | Both seams measured, `10-replay.json` assembled | `4c4f420` | feat |
| 2 | `10-replay-evidence.md`, the narrated result | `4d1f8eb` | docs |

## Task 1: both seams, measured

`rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench` ran
before any measurement, as RESEARCH's runtime-state inventory requires. None existed in this fresh
worktree; the command ran anyway, so no stale methodology label could be transcribed.

### Seam A: p50/p99/max/count and the build configuration

Five runs per configuration, `n` = 2,286 measured ticks, **2294 of 2294 ticks model-backed** in every
run. The bench's `allTicksModelBacked` precondition was never lowered and never fired.

| Configuration | p50 (median of 5) | p99 (median of 5) | max (largest observed) | p99 spread |
|---|---|---|---|---|
| **debug (the headline)** | 4753046 ns | **8831017 ns** | 9175382 ns | 0.25 percent |
| release | 4302424 ns | 8386219 ns | 8598101 ns | 0.39 percent |
| Phase 8 (synthetic) | about 4.2 ms | 8318256 ns | not published | one run only |

Per-run p99, debug: 8831017, 8845550, 8824918, 8823556, 8831823. Release: 8380106, 8370943, 8403407,
8400671, 8386219. A single invocation is not publishable and none is published: p50 and p99 are the
median across five runs, `max_ns` is the largest single sample observed across all five, and the
convention is written into the artifact as `distribution_convention`.

**Build configuration, recorded as the plan requires.** `08-03-SUMMARY.md` records the Phase-8 command
twice, both times as `swift run --package-path Packages/CortexDemo CortexDemoBench --full`, with no
`-c release`. SwiftPM's default is debug, so the Phase-8 figure is a debug-build number. The summary
never uses the word "debug", so under the plan's own rule for an unrecorded configuration **both were
run and both are reported**, and the debug column is the headline because that is what makes the
comparison to `8318256 ns` like-for-like. The difference is about 5 percent at p99, which is the size
of the error a silent configuration mismatch would have introduced.

Exit code 0 on every run. `grep -c '"passed"'` and `grep -c '"budget_ns"'` on `10-replay.json` both
return **0** (D-09).

### Seam B: counters, latency and the tamper control

Run over the FULL export at `--frames 73159`, five times.

| Counter | Value |
|---|---|
| `frames_accepted` | 73,159 |
| `frames_dropped` | 0 |
| `windows_completed` / `windows_filled` | 73,128 / 73,128 |
| `decodes_succeeded` | 73,128 (`model_backed` true) |
| `cursor_updates` / `pointer_reports_encoded` | 73,128 / 73,128 |
| `doorbell_wakes` | 73,159 |

Latency per completed window: **p50 136167 ns (0.136 ms)**, p99 160958 ns, max 13380292 ns, `n` =
73,128.

Per-run p50: 136583, 136167, 136292, 136167, 135833 (0.55 percent spread). Per-run p99: 172125,
159916, 245584, 160958, 154958 (**58 percent** spread). Per-run max: 964542, 990375, 13380292,
8598625, 3030959 (**14x**). Only p50 is a stable statistic here and the artifact says so in
`distribution_note`: `max_ns` is one sample out of 365,640 and is an OS-scheduling outlier bound, not
a chain property.

**The tamper control, executed. Exit code 1.** Transcript:

```
CortexSeamBSmoke: AES-GCM open FAILED CLOSED at seq 256 - authenticationFailure
  frames produced up to and including the tampered one = 256
  frames the accumulator ACCEPTED                       = 255
  windows_completed                                     = 224
  The tampered frame was never decrypted, never decoded, and never entered a decode window.
```

Payload integrity held: the newest bin of the first completed window matched the export bin the
producer read for the seq that closed it, to Float16 precision on all 96 channels.

### The hits and the reference

| Arm | Rotation target | Hits / 1,025 | p1 distance (mm) |
|---|---|---|---|
| `raw` | none | **0** | 16.582 |
| `kalman_only` | none | **0** | 16.616 |
| `refit` | true track | 70 | 0.830 |
| `refit_reversed_target` | reversed track | 2 | 3.908 |
| recorded-cursor replay reference | the animal's own cursor | **147** | |

Acquisition radius 2.8613660406415042 mm, dwell 0.30 s, timeout 5.0 s. All transcribed from
`10-refit-real.json` and `10-ceiling.json`; nothing was re-measured with different settings, and the
transcription was verified field by field by script.

## Task 2: the narration

486 lines, nine sections. **90 of 90 narrated values were matched back to a committed artifact
programmatically** before the commit, including every per-run latency value on both seams and all
twenty distance percentiles across the four arms. **35 acceptance checks pass**, including the two
that are easiest to get wrong: `8318256` appears in the Seam A section and nowhere in the Seam B
section, and every sentence in the document that mentions a photodiode carries a negation or
staleness marker. `grep -icE 'maximum any decoder|perfect decoder|theoretical maximum'` returns 0.
ASCII only, no em dashes, no smart quotes, no emoji.

## The SC#2 adjudication, and why the enum is absent

Section 15's table was applied explicitly to the measured numbers, and the result is a genuine
conflict between two pre-registered sections that only materialises on this data.

- **Row C is closed.** The recorded-cursor replay reference is 147, which is `>= 1`, so the
  cannot-discriminate escape is ruled out at this geometry, exactly as `10-ceiling-evidence.md` fixed
  before the measurement.
- **On section 15's literal first column, which names the `refit` arm: row A**, `hits >= 1`, because
  that arm scored 70 of 1,025.
- **On the arms section 7 pre-registers as the only ones attributable to the decode: row B's shape**,
  `hits == 0` with the reference `>= 1`, because `raw` and `kalman_only` both scored 0 of 1,025.
- Row B as literally written also requires zero on all four arms, which does not hold either.

The determination recorded for confirmation: **on the arms whose result is attributable to the neural
decode the outcome is not met.** The `refit` arm's 70 hits are target-determined by construction
(`IntentRotation.rotate` returns `(speed / dist) * d`, replacing the decoded direction with the
direction to the known target), so publishing them as SC#2 met would present target knowledge as a
decoding result.

`sc2_disposition` and `sc2_rule` are **absent** from `10-replay.json`. Three things point the same
way: this plan's own task text says to leave them absent, section 15 rule 2 says no agent amends a
success criterion, and Plan 10-10 Task 3b is a blocking `checkpoint:decision` whose text says "Do NOT
choose a row on the user's behalf." The full adjudication is published under `sc2_adjudication` and in
section 4 of the evidence so the user's decision at that checkpoint is a confirmation of measured
facts rather than an open question.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 - Missing critical] The plan's key names contradict the governing pre-registration**

- **Found during:** Task 1, assembling the artifact.
- **Issue:** the plan directs `ceiling_hits` and `ceiling_ref`. `10-PREREGISTRATION` section 11 states
  in writing that for `10-replay.json` "The names `ceiling_hits` and `ceiling_ref` are **not**
  emitted, because the ceiling framing was rejected (section 16)", and pins
  `replay_reference_hits` / `replay_reference_ref` instead. Section 18 makes the pre-registration
  govern where it and a plan disagree.
- **Fix:** the pre-registered names are emitted and the rejected ones are absent. The plan's
  verification script was adapted to the pre-registered names and re-run; the value binding it exists
  to enforce (equality with `10-ceiling.json`'s `canonical_hits` = 147) is asserted unchanged.
- **Note for 10-09:** its plan line 177 also names `ceiling_hits` and `ceiling_ref`. Its schema test
  must bind to `replay_reference_hits` and `replay_reference_ref`, which is what 10-07's summary
  already handed off.
- **Committed in:** `4c4f420`

**2. [Rule 2 - Missing critical] Seam B reported counters but no latency, and no amplitude ratio existed**

- **Found during:** Task 1, reading `CortexSeamBSmoke`.
- **Issue:** Plan 10-06 built the chain but reports counters only, and 10-PREREGISTRATION section 14
  requires a measured decoded-to-true velocity magnitude ratio that no artifact carried. 10-07
  explicitly deferred it here.
- **Fix:** both added to `CortexSeamBSmoke` as measurement instruments: two clock reads per iteration
  and one export read per completed window, after the latency clock stops. No frame byte, no crypto
  step and no counter changed; `git diff --stat` is 141 insertions, 0 deletions. Percentiles reuse
  `LatencyHistogram`, the same nearest-rank helper Seam A reaches through
  `GlassToGlassTimer.histogram`, so the two seams differ by boundary and not by method. A
  `precondition` ties the latency sample count to `windows_completed` so a silently short distribution
  cannot be published.
- **Verification:** the clean-clone CI path still exits 0 with the amplitude block omitted (no model
  configured, `n` = 0); 44 CortexDemo tests and 26 CortexIPC tests pass; `swiftformat --lint` clean.
- **Committed in:** `a8e9452`

**3. [Rule 1 - Bug] The cross-process clock concern the plan raised does not arise**

- **Found during:** Task 1.
- **Issue:** the plan anticipates cross-process instrumentation and permits reporting Seam B with no
  latency figure if a cross-process clock comparison proves unreliable. Plan 10-06's Rule-3 deviation
  had already made the chain single-process lock-step, so both clock reads are on one
  `mach_absolute_time` timebase in one thread and the arithmetic is sound.
- **Fix:** the number is published, and the limitation is stated in the direction that actually
  applies: no cross-process wakeup, context switch or scheduling delay is included, so 0.136 ms is a
  **floor** on what the chain would cost across a real process boundary, never an estimate of it.
  `latency_caveat` and `process_boundary_note` carry that in the artifact.
- **Committed in:** `a8e9452`, `4c4f420`

**4. [Rule 2 - Missing critical] The plan's 4096-frame Seam B run would not have covered the replay**

- **Found during:** Task 1.
- **Issue:** `--frames 4096` completes 4,065 windows, about 82 seconds of a 1,463-second session. An
  amplitude ratio measured over the first 6 percent of the replay is not "over the same replay", which
  is what the plan and section 14 ask for.
- **Fix:** `--frames 73159`, which completes 73,128 windows over the whole export. Not 73,160:
  `CortexSeamBSmoke` maps seq to bin as `seq % binCount` with seq starting at 1, so frame 73,160 would
  wrap back to bin 0. That leaves 73,128 windows against the ablation's 73,129 decoded ticks, because
  the window ending at bin 31 needs bin 0 and bin 0 is never sent. Recorded in the artifact as
  `frames_note`.
- **Committed in:** `4c4f420`

**5. [Rule 2 - Missing critical] The refit arm's hits and distances alone would have hidden the finding**

- **Found during:** Task 1.
- **Issue:** the plan directs transcribing `hits` and `distance_to_target_mm` from the `refit` arm
  only. Those numbers are target-determined by construction (section 7), so an artifact carrying only
  them would present target knowledge as the closed-loop result and would hide the 0 of 1,025 on the
  attributable arms, which is the actual RD-08 finding.
- **Fix:** the plan's transcription is honoured exactly (`hits` = 70, the five percentiles are the
  refit arm's, byte-equal and script-verified), and `hits_by_arm` plus
  `distance_to_target_mm.by_arm` carry all four arms beside them, each with the section-7 caveat. The
  evidence's single hit table leads with the two target-blind zero rows.
- **Committed in:** `4c4f420`

**6. [Rule 3 - Blocking, environment only] Gitignored directories absent from the worktree**

`Decoder/exports`, `Decoder/data` and `Decoder/checkpoints` do not exist in a fresh worktree. All
three were created as real directories holding symlinks to the canonical checkout, never as bare
symlinks, which is the trap Plans 10-02 and 10-04 both recorded. `git status --short` is clean and
`git check-ignore -v` confirms `.gitignore:99` covers `Decoder/exports/` and `.gitignore:27` covers
`Packages/CortexDemo/.bench/`. Nothing from any of them is committed.

**Total: 6 auto-fixed (4 missing-critical, 1 bug, 1 blocking-environment). No Rule 4 escalation, no
fix-limit escalation, no auth gate, no checkpoint reached.**

### Deliberately not done

- **`sc2_disposition` and `sc2_rule` were not written.** See the adjudication section above. This is
  the one place where the orchestrator's brief ("SC#2 is adjudicated HERE... record `not_met`
  plainly") and this plan's own text ("leave them ABSENT here") point in different directions, and it
  was resolved deliberately rather than by omission. The adjudication itself IS performed and
  published in full, in both the JSON and the prose, with the row named and the recommended
  determination stated as `not_met` on the attributable arms. What is withheld is only the enum
  write, because the antecedent of the orchestrator's instruction ("if that is what you measure") is
  true on the target-blind arms and false on the arm section 15's first column literally names, and
  choosing between those two readings is a judgement about what SC#2 means. Section 15 rule 2 and
  Plan 10-10 Task 3b both reserve that judgement for the user at a blocking checkpoint. Writing
  `met` would over-claim; writing `not_met` would have an agent resolve a conflict between two
  pre-registered sections on the user's behalf. Publishing the conflict is the honest third option.
- **`GlassToGlassTimer.methodologyLabel` was not edited.** It is the four-way coupled edit Plan 10-11
  owns. The label the bench emits today was transcribed into `10-replay.json` byte-exact and the
  evidence records that it is stale, because Phases 9 and 10 no longer build a photodiode rig.
- **No number was tuned toward a magnitude, and no acquisition parameter was relaxed.** Radius, dwell
  and timeout are the pre-registered values throughout.
- **The retired 24.7 ms claim is not presented as achieved anywhere.** Both published latencies are
  labeled software-timed, on an `Apple M5 Pro`, with status `corroborating`.
- **STATE.md and ROADMAP.md were not updated**, per the objective. The orchestrator owns those writes.

## Notes for later plans

- **10-09 (the schema gate):** bind to `replay_reference_hits` and `replay_reference_ref`, not
  `ceiling_hits` / `ceiling_ref` (deviation 1). **And note the ordering hazard:** 10-09's
  `test_sc2_disposition_present_but_unasserted` asserts `sc2_disposition` is PRESENT, but Plan 10-10
  Task 3b writes it, and both plans are wave 6. If 10-09 runs first its test will fail on a key that
  does not exist yet. Either order 10-09 after 10-10 Task 3, or have the test skip cleanly while the
  key is absent and assert membership once it appears. `10-replay.json` also carries two keys beyond
  section 11's list, `hits_by_arm` and `sc2_adjudication`; bind to "0 missing" plus an allow-list, as
  10-07 already advised for its own artifact.
- **10-10 Task 3b:** every number the checkpoint needs is pre-filled in `10-replay.json`'s
  `sc2_adjudication` and in section 4 of the evidence: all four arms' counts, the reference, the
  radius and dwell, both candidate rows with their conditions, and why row C is closed. Present it as
  a determination to confirm.
- **10-11 (RD-09):** the stale methodology label is quoted in section 6 of the evidence with an
  explicit note that the ASCII rendering there is a transliteration and that
  `10-replay.json`'s `seams[A].methodology` holds the byte-exact string with its U+2014 em dash.
- **10-12 (the README headline):** Seam A's `8831017 ns` is the real-data software-timed p99 and it
  sits beside `8318256 ns`. Seam B's `136167 ns` must NOT appear beside either. The webgrid headline
  attributable to the decode is 0 of 1,025.
- **Anyone re-running this:** use the runbook in section 7 of the evidence. `-c release` is not
  optional for Seam B (73,128 decodes), and the Seam A debug run is deliberate.

## Known Stubs

None. Both artifacts are measured data. Every counter reported was produced by code that ran, every
latency percentile comes from samples the instrument collected, and the amplitude ratio was computed
from the run rather than asserted. The zeros in the hit table are measured results, not stubs: `raw`
and `kalman_only` scored 0 hits and that is the finding.

One value is a floor rather than a measurement of the thing it names, and it is labeled as such in
three places (`process_boundary`, `process_boundary_note`, `latency_caveat`): Seam B's latency does
not cross a process boundary, so it does not include cross-process wakeup cost.

## Threat Flags

None. This plan added no network endpoint, no auth path and no schema change at a trust boundary. The
one code change reads two clock values and one already-mapped export record per completed window and
writes them into an artifact.

The plan's own STRIDE register is fully mitigated by executed controls:

| Threat | Mitigation, executed |
|---|---|
| T-10-08-01 a Seam B number presented as the re-derived Phase-8 number | each seam carries `seam` and a distinct `boundary`; the evidence states the non-comparability in bold; `8318256` verified present in the Seam A section and absent from the Seam B section by script |
| T-10-08-02 synthetic numbers published as real after a silent fallback | `ticks_model_backed == ticks_total == 2294` on every Seam A run, asserted by the bench's own `precondition` and re-asserted by the verification script |
| T-10-08-03 a hit count published without its reference | `replay_reference_hits` asserted byte-equal to `10-ceiling.json`'s `canonical_hits`; the evidence names commits `864259b`, `69ccd6f` and `2436188` in order |
| T-10-08-04 acquisition parameters quietly relaxed | radius, dwell and timeout read from the pre-registered sidecar and the committed ablation; `not relaxed` present in the evidence; the ablation and this artifact share one replay |
| T-10-08-05 a debug number compared against a release one | the Phase-8 configuration was read from `08-03-SUMMARY.md`, found to be debug by default, and BOTH configurations were run five times each and reported |
| T-10-08-06 an unreliable cross-process latency published as sound | the run is single-process on one timebase, so the arithmetic is sound; the limitation that actually applies (no cross-process wakeup) is stated as a floor in `latency_caveat` |
| T-10-08-07 a stale `.bench` artifact transcribed | all three `.bench` directories deleted before the first measurement, and the deletion is recorded in the artifact's `env` and in the runbook |

## Verification

Every command run in this worktree on **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Xcode 26.3 (17C529),
Swift 6.2.4.

| Command | Result |
|---|---|
| `rm -rf Packages/{CortexReFIT,CortexDemo,CortexDecoder}/.bench` | done before the first measurement; none existed |
| `swift build -c release ... CortexDemoBench` | **exit 0** |
| `CortexDemoBench --real`, 5x debug + 5x release | **exit 0** each; 2294/2294 model-backed each |
| `swift build -c release ... CortexSeamBSmoke` | **exit 0** |
| `CortexSeamBSmoke --frames 73159`, 5x | **exit 0** each; 73128 windows, 73128 decodes, 0 dropped |
| `CortexSeamBSmoke --tamper` | **exit 1**, transcript above |
| `CortexSeamBSmoke` clean-clone, no env | **exit 0**, `data_source synthetic_fixture`, amplitude block omitted |
| Plan's Task 1 verification script (key names adapted) | `OK two seams, model-backed on every tick, replay reference bound, five factors, sc2 deferred` |
| Plan's Task 2 verification command, verbatim | `decomposition complete`, **exit 0** |
| 35 Task-2 acceptance checks | **0 failures** |
| 90-value spot-check of prose against the committed artifacts | **90 of 90 matched** |
| `grep -c '"passed"'` / `'"budget_ns"'` on `10-replay.json` | **0 / 0** |
| `grep -icE 'maximum any decoder\|perfect decoder\|theoretical maximum'` on the evidence | **0** |
| `wc -l` on the evidence | **486** (>= 170) |
| ASCII-only / no em dash / no smart quote / no emoji | **clean** |
| `swift test --package-path Packages/CortexDemo` | **44 tests in 5 suites passed** |
| `swift test --package-path Packages/CortexIPC` | **26 tests in 5 suites passed** |
| `CortexDemoBench --smoke` (Phase-8 path intact) | **exit 0**, p99 8313651 ns, `PASS (PERF-04)` |
| `swiftformat --lint` on the modified file | **clean** |
| `./Tools/scripts/hotpath-policy.sh` and `--self-test` | **exit 0 / exit 0** |
| `./Tools/scripts/render-policy.sh` | **exit 0** |
| `./Tools/scripts/decoder-policy.sh` | **exit 0** |
| `./Tools/scripts/bps-policy.sh` and `--self-test` | **exit 0 / exit 0** (10-05's repair holds) |
| `./Tools/scripts/readme-policy.sh` | **exit 0** (untouched; Plan 10-12 owns the README) |
| `git status --short` | clean; nothing from `Decoder/` or `.bench/` |

### What was NOT run, and why

- **`honesty-sweep.sh`.** It does not exist yet; Plan 10-14 creates it.
- **The Decoder pytest set and `uv sync --extra dev`.** No Python ran in either measurement loop. The
  Python provenance quoted in the evidence is read from the artifacts the Python stages emitted.
- **Any iPad-M4 or device measurement.** Every number is an M5 Pro number labeled `corroborating`.
- **The repo-wide `swiftformat --strict` sweep.** D-18 work in a later plan. The one file this plan
  modified is lint-clean.

## Why status is PARTIAL, not PASS

Every task executed, every task is committed, every verification command is green and no criterion was
skipped. PARTIAL reflects three flagged items, all documented above rather than papered over:

1. **`sc2_disposition` and `sc2_rule` are not written.** RD-08's hit half is therefore adjudicated but
   not dispositioned, and the phase carries an open blocking checkpoint at Plan 10-10 Task 3b.
2. **Seam B does not cross a process boundary**, inherited from Plan 10-06, so its latency is a floor
   and three IPC legs remain uncovered by it.
3. **An ordering hazard is handed to 10-09**, whose schema test asserts the presence of a key that
   10-10 Task 3 writes, with both plans in wave 6.

## Self-Check: PASSED

Files claimed as created, both confirmed present on disk:

```
FOUND: .planning/phases/10-v1-real-data-closed-loop-launch/10-replay.json (362 lines)
FOUND: .planning/phases/10-v1-real-data-closed-loop-launch/10-replay-evidence.md (486 lines)
```

File claimed as modified, confirmed changed in `a8e9452` (141 insertions, 0 deletions):

```
FOUND: Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift (774 lines)
```

Commits claimed, all resolving as commit objects on top of the expected base
`e1fda58f546b56ff1602ec0775a4450d0536f799`: `a8e9452`, `4c4f420`, `4d1f8eb`.
`git merge-base HEAD e1fda58` returns `e1fda58f546b56ff1602ec0775a4450d0536f799`.

The load-bearing claims were executed, not asserted. Seam A ran ten times across two configurations
and reported 2294 of 2294 ticks model-backed on every one. Seam B ran five times over the full export
and the amplitude ratios were byte-identical across all five, which is the stronger determinism claim.
The tamper control was executed and its exit code captured as 1. `10-replay.json` was assembled by a
script that reads every value from a committed artifact and asserts the manifest, sidecar and ablation
digests agree before writing. Ninety narrated numbers were matched back to those artifacts by script.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
