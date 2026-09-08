---
status: human_needed
agent: donny-verifier
phase: 10-v1-real-data-closed-loop-launch
verified: 2026-09-08T04:35:36Z
verdict: human_needed
score: 5/5 must-haves verified (SC#2 met as a measurement obligation with a pre-registered negative outcome)
re_verification: false
gaps: []
disclosed_deviations:
  - criterion: "SC#2 / RD-08 - 30x30 webgrid hit demonstrated"
    disposition: not_met
    adjudicated_by: "Plan 10-10 Task 3b blocking checkpoint:decision; user answered 'Not met, on attributable arms'"
    evidence: "10-replay.json sc2_disposition=not_met, sc2_rule=B; raw 0/1025 and kalman_only 0/1025 against a recorded-cursor replay reference of 147"
    why_not_a_gap: "10-PREREGISTRATION section 15 committed row B and its action in Wave 0 before any hit count existed, and rule 1 forbids relaxing radius/dwell/timeout to convert a zero into a hit. There is no remediation to plan; publishing the negative result IS the pre-registered action."
  - criterion: "Plan 10-17 Task 1 - 'No tracked file contains a PEM private-key header'"
    disposition: mis_specified
    evidence: "10-17-SUMMARY.md:155-172 records it as MIS-SPECIFIED and does not claim it passed. It fails only against fastlane/asc_api_key.json.example whose payload is the literal REPLACE_WITH_P8_CONTENTS. No key material exists."
    why_not_a_gap: "User-reviewed and accepted. The repo reports it as not met rather than claiming a pass."
  - criterion: "Plan 10-17 - 'no history rewrite occurred'"
    disposition: cannot_be_asserted
    evidence: "10-17-SUMMARY.md:174-176. A user-directed full-history rewrite of 525 commits happened 2026-09-07, before and outside this plan. The plan asserts only the narrower true claim that it performed none."
    why_not_a_gap: "Correctly narrowed rather than falsely asserted."
human_verification:
  - test: "Gate 1 - canonical iPad Pro M4 software-timed glass-to-glass latency (PERF-04, D-08)"
    expected: "A p50/p99 captured on a provisioned iPad Pro M4, replacing the corroborating M5 Pro number as canonical"
    why_human: "Requires physical iPad Pro M4 hardware that is not provisioned. Never-auto-approve gate; DEFERRED 2026-09-06."
  - test: "Gate 2 - live TestFlight submission (DIST-01 / DIST-02 / DIST-03)"
    expected: "An accepted TestFlight build"
    why_human: "Requires an Apple Developer Program membership that is not enrolled. DEFERRED 2026-09-06."
  - test: "Gate 3 - on-device HID registration as a Switch Control provider (SYS-01 / SYS-02, D-06)"
    expected: "The BCI HID device appears to Switch Control on a real device"
    why_human: "com.apple.developer.hid.virtual.device is Apple-managed and request-gated, and has not been granted. DEFERRED 2026-09-06."
  - test: "Gate 4 - canonical iPad Pro M4 p99 for the real-data decoder (RD-06b, D-17)"
    expected: "Decoder p99 under 2 ms measured on iPad Pro M4 with real weights"
    why_human: "Requires physical iPad Pro M4 hardware. DEFERRED 2026-09-06."
  - test: "Gate 5 - canonical iPad Pro M4 Seam A glass-to-glass p99 on the real-data path (RD-08)"
    expected: "Seam A p99 re-captured on iPad Pro M4, replacing the 8.831 ms M5 Pro corroborating figure as canonical"
    why_human: "Requires physical iPad Pro M4 hardware. DEFERRED 2026-09-06."
  - test: "Gate 6 - canonical iPad Pro M4 120 Hz real-data webgrid demonstration (RD-08)"
    expected: "Sustained 120 Hz real-data replay observed on iPad Pro M4"
    why_human: "Requires physical iPad Pro M4 hardware. DEFERRED 2026-09-06."
  - test: "D-16 demo capture review"
    expected: "The 3521-frame, 120 fps recording sustains 120.00 FPS from t=25s to t=55s on real spikes, as 10-demo-capture-evidence.md reports"
    why_human: "The recording is deliberately not committed. It exists at ~/Documents/Screenshots/Screen Recording 2026-09-06 at 11.48.31 PM.mov (48,598,291 B, verified present), but a repo reviewer cannot check the visual claims from the checkout alone."
---

# Phase 10: v1 Real-Data Closed Loop & Launch Verification Report

**Phase Goal:** The full pipeline runs on a real recorded session - real M1 spikes replayed through daemon -> IPC -> decoder -> ReFIT-Kalman -> 120Hz renderer -> BCI HID - and the repo republishes itself honestly: every synthetic-derived number is re-derived or labeled, the photodiode claim is retired to Future work with its reason recorded, and a CI gate makes the retired claim structurally impossible to resurrect as an achieved result.

**Verified:** 2026-09-08T04:35:36Z
**Status:** human_needed  **Verdict:** human_needed
**Re-verification:** No - initial verification

## Goal Achievement

### Observable Truths

| # | Truth (ROADMAP Success Criterion) | Status | Evidence |
|---|---|---|---|
| 1 | ReFIT-Kalman gains re-fit on real data; the ablation re-run on real Indy sessions with the honest gap to 4.16 / 8.5 BPS stated | VERIFIED | `KalmanConstants.swift:9` header reads `noise source = indy-heldout`, pinned by `KalmanConstantsTests.swift:132-133` which also asserts `!contains("noise source = default")`. Four-arm ablation on `indy_20160630_01` in `10-refit-real.json` (`data_source = real`, 73,129 model-backed ticks, 0 decode fallbacks). Honest gap in `10-refit-real-evidence.md:145-181`: attributable arms are 0.000000 BPS, so the gap is the full 4.16 and 8.5, and the `refit` arm's gap is explicitly refused as a decoding gap. ROADMAP's own escape clause ("if ReFIT's uplift does not survive contact with real spikes, that is the finding") is exercised, not evaded. |
| 2 | Closed loop replays a real session end to end at 120 Hz with a 30x30 webgrid hit demonstrated, and the software-timed glass-to-glass p99 re-derived **on the real-data path** | VERIFIED as a measurement obligation, with a pre-registered negative outcome on the hit | **p99 half: MET.** Seam A (`CortexDemoBench --real`) re-derives the Phase-8 geometry with the spike source swapped to `RecordedSpikeSource` over the real export and the decode swapped to the shipped fp16 `.mlpackage`: p99 **8.831 ms** debug / 8.386 ms release, n=2,286, 5 runs, vs the synthetic Phase-8 8.318 ms (`10-replay-evidence.md:60-80`). Labeled `Apple M5 Pro`, status `corroborating`; no synthetic-path number stands in for it. **120 Hz half: MET** - `10-demo-capture-evidence.md` records 120.00 FPS sustained over a 30 s window on the real-data GUI build. **Hit half: NOT MET and published as such** - `sc2_disposition = not_met`, `sc2_rule = B` in `10-replay.json`, on raw 0/1025 and kalman_only 0/1025 against a recorded-cursor replay reference of 147. See Disclosed deviations. |
| 3 | Repo-wide sweep leaves no synthetic-derived number presented as a real-data result | VERIFIED | `honesty-sweep.sh` exits 0 on 7 checks (label / banner / preserve / adr / grounds / supersede / authority) and its `--self-test` exits 0 on 11 negative controls, including control 10 ("the same unlabeled strings bite in a NON-excluded file") which proves the path exclusions are not holes. Independent grep for `0.3804`, `1.953`, `3.471`, `226/226`, `0.374` outside `.planning/` finds every occurrence carrying an inline synthetic label or under a superseded banner (`docs/adr/0002-*.md:8-9`). README's first table leads with the negative results (0 of 1,025 decode-only acquisitions, LOSO -0.3498, linear baseline beating NDT1). |
| 4 | `readme-policy.sh` rewritten, not deleted: required set drops `photodiode`/`24.7`, gains real-data provenance and a forbidden-token check, `--self-test` updated in lockstep | VERIFIED | 522-line script. `photodiode`/`24.7` are no longer in the required-present set; the figure is handled by three independently-controlled context rules (`readme-policy.sh:295-300`): retired-A marker-on-every-matching-line, retired-B whole-line achievement-framing forbid, retired-C under-a-Future-work-heading. Gained the D-14 provenance triple (`:313-319`). `./Tools/scripts/readme-policy.sh` exits 0 across 21 checks; `--self-test` exits 0 across 12 controls plus an 8-case adversarial corpus scored in both directions. |
| 5 | Photodiode path documented as Future work with LAT-01..LAT-08 preserved verbatim, an ADR records why, README honest-gates table reflects the new boundary | VERIFIED | `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` (Accepted, 2026-09-05) gives exactly the two required reasons: hardware-gated (BOM + unprovisioned iPad Pro M4, with the four prior deferrals cited) and not the largest credibility hole (every decoder number was synthetic Poisson). Indexed at `docs/adr/README.md:11`. All eight `LAT-0[1-8]` present in `REQUIREMENTS.md` as unchecked, preserved items plus the ROADMAP "Future work (retired from v1)" section; `honesty-sweep.sh` gate `[preserve]` enforces this in both files. README honest-gates table row: "Physical glass-to-glass latency \| Not measured. No photodiode rig was built." |

**Score:** 5/5 truths verified. SC#2 carries a pre-registered, user-adjudicated negative outcome on its hit clause.

### Disclosed deviations

These are correctly-reported non-achievements, not gaps. In each case the repo states the failure rather than claiming a pass, which is the phase goal working as designed.

| # | Criterion | Disposition | Where it is disclosed |
|---|---|---|---|
| 1 | SC#2 / RD-08 "30x30 webgrid hit demonstrated" | `not_met`, rule B | `10-replay.json` keys `sc2_disposition` / `sc2_rule`, written only by the Plan 10-10 Task 3b blocking checkpoint after the user answered "Not met, on attributable arms". The full adjudication object `sc2_adjudication` is committed and names the conflict between section 15's literal first column (row A on the refit arm's 70 hits) and section 7's attributability rule (row B on raw/kalman_only 0/1025), and refuses to let an agent amend a success criterion. Section 15 rule 1 forbade relaxing radius (2.8614 mm), dwell (0.30 s) or timeout (5.0 s) to convert a zero into a hit, and the committed values match the pre-registered ones. |
| 2 | Plan 10-17 Task 1 "No tracked file contains a PEM private-key header" | MIS-SPECIFIED, not met as written | `10-17-SUMMARY.md:150-172` under the heading "Acceptance criteria not met, and why". Fails only against `fastlane/asc_api_key.json.example`, a deliberately committed template whose payload is `REPLACE_WITH_P8_CONTENTS`. No key material. The summary explicitly says "not met and this summary does not claim otherwise". |
| 3 | Plan 10-17 "No history rewrite occurred" | Cannot be asserted as a blanket statement | `10-17-SUMMARY.md:174-176`. The user-directed 525-commit rewrite of 2026-09-07 predates and is outside this plan; the plan asserts only that it performed none. |

I checked specifically for the inverse failure - the repo claiming these criteria PASSED - and found none. Plan 10-17's own frontmatter is `status: PARTIAL`, which is the honest value.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` | Real-data re-fit gain, provenance header | VERIFIED | `noise source = indy-heldout   seed = 0`; two gains, shipping K plus the frozen `phase7BaselineK` for D-09 byte-identity |
| `Decoder/scripts/fit_kalman_gain.py` | Residual path implemented (both branches previously returned `default_noise`) | VERIFIED | Present; its output is the header above, armed by a test |
| `Packages/CortexCore/Sources/CortexCore/ReplayExport.swift` | D-06 export reader | VERIFIED, WIRED | Imported by `CortexDaemon/Producer.swift`, `CortexMac/ReplayDriver.swift`, all three benches, and `ReplayExportTests.swift` |
| `Packages/CortexDemo/Sources/CortexDemo/RecordedSpikeSource.swift` + `SpikeWindowSource.swift` | Seam A real spike source behind a seam | VERIFIED, WIRED | `SpikeWindowSource` is implemented by both `RecordedSpikeSource` and `SyntheticSpikeSource`; consumed by `ReplayPipeline` and all three bench mains |
| `Packages/CortexDemo/Sources/CortexDemo/RollingSpikeWindow.swift` | Seam B window | VERIFIED, WIRED | Used by `CortexDaemon/Producer.swift` and `CortexSeamBSmoke` |
| `Packages/CortexDemo/Sources/CortexDemo/ArmStatistics.swift` | Four-arm Willett statistics | VERIFIED, WIRED | Consumed by `CortexReplayBench/main.swift`; tested by `ArmStatisticsTests.swift` |
| `Packages/CortexDemo/Sources/{CortexReplayBench,CortexSeamBSmoke}` | The two measurement benches | VERIFIED | Both exist as products alongside `CortexDemoBench` |
| `Tools/scripts/readme-policy.sh` | Rewritten (SC#4) | VERIFIED | 522 lines; runs clean, `--self-test` clean |
| `Tools/scripts/honesty-sweep.sh` | RD-09 structural gate | VERIFIED | Runs clean, `--self-test` clean on 11 controls |
| `Tools/scripts/refit-real-policy.sh` + `check_real_replay_provenance.py` | RD-07/RD-08 provenance gate | VERIFIED | Runs clean; asserts the four pre-registered arms, two distinctly-labeled seams, the open-loop disclosure, and checksum agreement with the manifest |
| `Decoder/tests/test_real_replay_schema.py` | Schema test | VERIFIED | 27 tests pass in 0.24 s alongside `test_cobps_margin.py` |
| `docs/adr/0003-photodiode-retirement-and-real-data-v1.md` | Retirement ADR | VERIFIED, LINKED | Indexed; both rationale literals gate-checked by `honesty-sweep.sh` |
| `.planning/phases/10-*/10-{refit-real,replay,ceiling}.json` + matching `*-evidence.md` | Pinned artifacts | VERIFIED | Committed with machine, OS, toolchain, seed, sha256s and a runbook |
| `10-HUMAN-UAT.md` | Six never-auto-approve device gates | VERIFIED | 6 deferred, 0 auto-approved, each with a named missing prerequisite and a date |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| Real `.mat` session | Swift replay | D-06 export + sidecar sha256 | WIRED | `refit-real-policy.sh` verifies `source_sha256` and `export_sidecar_sha256` agree with `Decoder/manifests/indy_sessions.json` byte-for-byte |
| `RecordedSpikeSource` | CoreML decode | `ReplayPipeline`, model-backed tick counting | WIRED | `ticks_model_backed = 73129` equals `ticks_total = 73129`; the bench `precondition`-aborts before computing any statistic if a single window falls back to the synthetic decode |
| Decoder | ReFIT-Kalman | `KalmanFilter.step` + `IntentRotation` with the real-data gain | WIRED | Four arms differ only in the filter stage over one shared decoded velocity array |
| Daemon | IPC (Seam B) | `ShmRing` + Doorbell + AES-GCM + FlatBuffers | WIRED, with a disclosed boundary | `CortexSeamBSmoke` exercises the codec path with an AES-GCM tamper control; `10-replay-evidence.md:405` discloses that Seam B does not cross a process boundary, so the Mach rendezvous, `FDChannel` fileport handoff and `SessionKeyChannel` remain untested by it |
| Renderer | 120 Hz | `CAMetalDisplayLink` in the GUI build; modelled boundary arithmetic in the headless bench | WIRED, with the distinction stated | `cadence_provenance` in `10-replay.json` says the bench cadence is MODELLED, not a display-link reading; the measured cadence is the GUI capture |
| Latency claim | Honesty label | `GlassToGlassTimer.methodologyLabel` | WIRED and REPAIRED | The label now reads "software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built". `10-replay-evidence.md` flagged this string as stale at measurement time; Plan 10-11's coupled edit fixed it, and `GlassToGlassTimerTests.swift:44-46` pins it verbatim |
| README claims | CI reality | Pinned run id, not "the head" | WIRED | README cites run 34182390856 on commit `710e729` by id and URL. Verified live: that run and run 34183802014 on `7b47d67` both concluded `success` |

### Data-Flow Trace (Level 4)

| Artifact | Data variable | Source | Produces real data | Status |
|---|---|---|---|---|
| `10-refit-real.json` | `arms[].bps_n64/n900`, `hits` | `CortexReplayBench` over the D-06 export through `ndt1_real_vel_sweep_fp16.mlpackage` | Yes - `data_source = real`, 73,129 model-backed ticks, 0 fallbacks | FLOWING |
| `10-replay.json` | `seams[].p50/p99` | `CortexDemoBench --real` (Seam A) and `CortexSeamBSmoke` (Seam B), 5 runs each | Yes - real 20 ms bins, checksum-pinned | FLOWING |
| README "What works" table | every cell | Transcribed from `09-decoder-metrics.json`, `10-refit-real.json`, `10-replay.json` | Yes, and the negative cells match the artifacts exactly (0 of 1,025; -0.3498; 0.1446; 8.831 ms) | FLOWING |
| `KalmanConstants.swift` | `K` | `fit_kalman_gain.py` residual path on Indy held-out noise | Yes - header would read `default` if the residual path had not run; a test forbids that string | FLOWING |
| `10-demo-capture-evidence.md` | FPS / frame-interval rows | The user's `Cmd+Shift+5` recording, read back at stated timestamps | Yes, but the source file is outside the repo | FLOWING (source not committed - see human verification) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| README policy gate holds on the real README | `./Tools/scripts/readme-policy.sh` | 21 checks ok, exit 0 | PASS |
| Every README gate still bites | `./Tools/scripts/readme-policy.sh --self-test` | 12 controls + 8 adversarial cases, all pinned verdicts, exit 0 | PASS |
| RD-09 sweep holds repo-wide | `./Tools/scripts/honesty-sweep.sh` | 7 checks ok, exit 0 | PASS |
| Sweep exclusions are not holes | `./Tools/scripts/honesty-sweep.sh --self-test` | 11 controls incl. "moving an excluded string into scanned position bites", exit 0 | PASS |
| RD-07/08 artifact provenance | `./Tools/scripts/refit-real-policy.sh` | all three artifacts agree with the manifest, exit 0 | PASS |
| Real-replay schema + co-bps margin | `uv run --project Decoder pytest Decoder/tests/test_real_replay_schema.py Decoder/tests/test_cobps_margin.py -q` | 27 passed in 0.24s | PASS |
| Lint gate armed (D-18) | `swiftlint --strict --quiet` | exit 0, zero violations | PASS |
| Format gate armed (D-18) | `swiftformat --lint .` | 0/121 files require formatting, exit 0 | PASS |
| CI actually green on the pushed head | `gh run list` | run 34183802014 on `7b47d67` concluded `success`; run 34182390856 on `710e729` (the README-cited run) `success` | PASS |
| Working tree / push state | `git status --porcelain`, `git rev-parse origin/main` | clean; `origin/main` = `7b47d67`, HEAD = `8b0e7a4` (one docs-only tracking-fix commit ahead, not yet pushed and therefore not yet CI-covered) | PASS |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|---|---|---|---|
| RD-07 | ReFIT-Kalman gains re-fit on real data; raw-vs-ReFIT BPS ablation re-run on real Indy sessions with the honest remaining gap to 4.16 / 8.5 stated | SATISFIED | `KalmanConstants.swift:9` `noise source = indy-heldout` with `KalmanConstantsTests.swift:132-133` forbidding `default`; `10-refit-real.json` (four arms, `data_source = real`, per-arm realized gain and smoothing); `10-refit-real-evidence.md:145-181` states the gap as the full 4.16 / 8.5 on the attributable arms and refuses the refit arm's gap as a decoding gap; enforced by `refit-real-policy.sh` in CI (`ci.yml:747-748`). The uplift did not survive contact with real spikes and that finding is published, which is what the criterion asked for. |
| RD-08 | Closed loop replays a real session end-to-end at 120 Hz with a webgrid hit; software-timed glass-to-glass p99 re-derived on the real-data path | SATISFIED WITH A DISCLOSED DEVIATION | p99 re-derived on the real-data path: Seam A 8.831 ms p99 (debug) / 8.386 ms (release), n=2,286, 5 runs, real spikes + fp16 `.mlpackage`, M5 Pro `corroborating` (`10-replay.json`, `10-replay-evidence.md:60-80`). 120 Hz replay observed: 120.00 FPS sustained 30 s (`10-demo-capture-evidence.md`). Webgrid hit: `sc2_disposition = not_met`, `sc2_rule = B`, user-adjudicated. The pre-registration committed this row before the measurement, so the requirement's reporting obligation is discharged; the capability is absent and is published as absent. Canonical iPad-M4 captures remain deferred (Gates 5 and 6). |
| RD-09 | Repo-wide sweep - no synthetic-derived number presented as a real-data result; README, ADRs and every `*-evidence.md` carry the re-derived number or an explicit synthetic label | SATISFIED | **This is the finding the orchestrator needs: RD-09 is satisfied despite its unchecked box at `.planning/REQUIREMENTS.md:103` and its `TBD` traceability row at line 243.** Evidence: `Tools/scripts/honesty-sweep.sh` exits 0 on all 7 checks and its `--self-test` exits 0 on 11 negative controls, including control 10 which proves the path exclusions are not holes and control 11 which proves collision forms are not holes; wired blocking in `ci.yml:360-361`. Independent grep confirms every occurrence of `0.3804`, `1.953`, `3.471`, `226/226`, `0.374` outside `.planning/` is labeled synthetic inline or sits under a superseded banner (`docs/adr/0002-*.md:8-9`). README leads with the negative real-data results and states "a number measured on a Mac is never presented as an iPad number" (`README.md:246-247`), a rule the artifacts follow (`device.status = corroborating` on every Phase-10 number). The stale `GlassToGlassTimer.methodologyLabel` that `10-replay-evidence.md` flagged has been repaired and is pinned verbatim by a test. Supporting plans: 10-11, 10-12, 10-14, 10-15, 10-16. |
| RD-10 | `readme-policy.sh` rewritten (required set drops `photodiode`/`24.7`, gains real-data provenance + a forbidden-token check on the retired figure), `--self-test` updated in lockstep; photodiode retired in an ADR with LAT-01..08 preserved | SATISFIED | `readme-policy.sh` rewritten to 522 lines: the two tokens left the required set (`:27-28`) and were replaced by three independently-controlled context rules (`:295-300`), plus the D-14 provenance triple (`:313-319`). Both `./Tools/scripts/readme-policy.sh` and `--self-test` exit 0, the latter proving all 12 controls and all 8 adversarial 24.7 sentences yield their pinned verdict in both directions. `docs/adr/0003-*.md` records the retirement with both required reasons and is indexed. All eight LAT ids survive in `REQUIREMENTS.md` and the ROADMAP Future-work section, gate-enforced by `honesty-sweep.sh [preserve]`. Wired blocking in `ci.yml:334-335`. |

No orphaned requirements: `REQUIREMENTS.md` maps exactly RD-07..RD-10 to Phase 10, and all four are claimed by plans in the phase.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `Packages/CortexDemo/Sources/**`, `CortexCore/ReplayExport.swift`, `CortexDaemon/Producer.swift`, `CortexMac/ReplayDriver.swift` | - | TODO / FIXME / XXX / HACK / PLACEHOLDER / "not yet implemented" | none found | Clean |
| `.planning/phases/10-*/10-replay.json` | top level | `hits = 70` sits at the top level without an inline qualifier | Info | The same object carries `sc2_disposition = not_met`, the `hits_by_arm.note` naming the refit arm as target-determined by construction, and the full `sc2_adjudication`. The README renders both rows separately ("0 of 1,025" decode-only and "70 of 1,025, which is not a decoding result"). Not misleading in context; noted only because a naive consumer reading the top-level key alone would get the wrong impression. |
| `10-replay-evidence.md` | 404-410 | Says `GlassToGlassTimer.methodologyLabel` is stale | Info (resolved) | Accurate at the time of writing (Plan 10-08); repaired by Plan 10-11. The current label is honest. A future reader of the evidence file may be briefly confused by the stale-at-time-of-writing note. |

No blockers. No warnings.

### Human Verification Required

Seven items. Six are the never-auto-approve device gates in `10-HUMAN-UAT.md`, all DEFERRED 2026-09-06 with a named missing prerequisite and zero auto-approvals. Per standing project policy (`D-15`: v1 is declarable with these deferred, carried forward as disclosed limitations) these are deferrals, not gaps.

#### 1. Canonical iPad Pro M4 software-timed glass-to-glass latency (PERF-04, D-08)
**Test:** Capture Seam A p50/p99 on a provisioned iPad Pro M4.
**Expected:** A canonical iPad-M4 number replacing the corroborating M5 Pro figure.
**Why human:** The hardware is not provisioned. Auto-approving would fabricate a load-bearing credibility number.

#### 2. Live TestFlight submission (DIST-01 / DIST-02 / DIST-03)
**Test:** Submit and land a TestFlight build.
**Expected:** An accepted build.
**Why human:** No Apple Developer Program membership is enrolled.

#### 3. On-device HID registration as a Switch Control provider (SYS-01 / SYS-02, D-06)
**Test:** Register the BCI HID device and confirm Switch Control sees it.
**Expected:** The device appears as an input provider.
**Why human:** `com.apple.developer.hid.virtual.device` is Apple-managed, request-gated, and not granted.

#### 4. Canonical iPad Pro M4 p99 for the real-data decoder (RD-06b, D-17)
**Test:** Measure decoder p99 with the real fp16 weights on iPad Pro M4.
**Expected:** p99 under the 2 ms bar with real weights on the canonical device.
**Why human:** The hardware is not provisioned.

#### 5. Canonical iPad Pro M4 Seam A p99 on the real-data path (RD-08)
**Test:** Re-run Seam A on iPad Pro M4.
**Expected:** A canonical replacement for the 8.831 ms corroborating figure.
**Why human:** The hardware is not provisioned.

#### 6. Canonical iPad Pro M4 120 Hz real-data webgrid demonstration (RD-08)
**Test:** Observe the real-data replay at 120 Hz on iPad Pro M4.
**Expected:** Sustained 120 Hz on the canonical device.
**Why human:** The hardware is not provisioned.

#### 7. D-16 demo capture review
**Test:** Play `~/Documents/Screenshots/Screen Recording 2026-09-06 at 11.48.31 PM.mov` and confirm 120.00 FPS sustained from t=25s to t=55s with the HUD frame interval at 8.33 ms.
**Expected:** The six named acceptance observations in `10-demo-capture-evidence.md` reproduce.
**Why human:** The recording is deliberately not committed. I confirmed the file exists (48,598,291 B, 2026-09-06 23:49) but a repo reviewer cannot verify its visual content from the checkout.

### Gaps Summary

**No gaps.** Every one of the five ROADMAP Success Criteria is discharged, and the two clauses that did not land as originally worded are disclosed as non-achievements rather than claimed as passes - which is precisely what this phase's goal demanded.

The phase goal has three parts and all three hold:

**The pipeline runs on a real recorded session.** 73,129 model-backed ticks from `indy_20160630_01`, 0 decode fallbacks, through a real-data-re-fit Kalman gain, with a `precondition` abort that makes a synthetic number under a real-data label structurally impossible. The one boundary that is narrower than the goal sentence is disclosed rather than papered over: Seam B exercises the AES-GCM/FlatBuffers/ShmRing codec but does not cross a process boundary, so the Mach rendezvous and fileport handoff are untested by it, and `10-replay-evidence.md:405` says so.

**The repo republishes itself honestly.** README leads with what does not work. `honesty-sweep.sh` makes the sweep structural rather than a one-time edit, and its self-test proves the exclusions and collision forms are not holes. RD-09 is satisfied in the codebase even though its checkbox and traceability row are still unmarked - that is bookkeeping, not a missing deliverable.

**The retired claim cannot be resurrected as an achieved result.** `readme-policy.sh` no longer requires `photodiode`/`24.7`; it now permits them only as a retired spec target, under three independently-controlled rules that each bite alone, verified against an 8-case adversarial corpus scored in both directions, wired blocking into CI on a run that has actually executed and passed.

The single substantive scientific finding is negative and is published as such: the decoder cannot acquire targets at the pre-registered geometry (0 of 1,025 on both target-blind arms), the ReFIT uplift does not survive contact with real spikes, the encoder loses to a linear ridge baseline, and it does not transfer across sessions. The pre-registration committed the action for that outcome in Wave 0, before any number existed, and rule 1 forbade relaxing radius, dwell or timeout to convert a zero into a hit. The committed values match the pre-registered ones. That is the phase working correctly, not failing.

Status is `human_needed` rather than `passed` solely because seven items require physical hardware or human review and none may be auto-approved.

---

_Verified: 2026-09-08T04:35:36Z_
_Verifier: donny-verifier_
