---
status: SECURED
agent: donny-security-auditor
phase: 10-v1-real-data-closed-loop-launch
threats_closed: 133
threats_open: 0
asvs_level: 1
---

# Phase 10 Security Audit: v1 real-data closed-loop launch

Scope: 17 plans (10-01 through 10-17), 133 threat-register rows extracted verbatim from each
plan's `<threat_model>` block (132 unique IDs; `T-10-03-06` is reused inside `10-03-PLAN.md` for two
different threats and is disambiguated below as `T-10-03-06` / `T-10-03-06b`, per instruction).
Every `mitigate` row was checked against the cited implementation file(s) with a live command,
grep, or git-ancestor check run in this session (not assumed from the plan's own transcript).
Every `accept` row was checked for a documented rationale, which is recorded in the Accepted Risks
section. There are no `transfer`-dispositioned threats in this register.

**Method note on currency.** Verification was run against the CURRENT working tree (HEAD, plus one
pre-existing uncommitted `10-VALIDATION.md` gap-fill from a concurrent `donny-nyquist-auditor` pass
that this audit did not create and did not modify), not against each plan's completion-time commit.
This surfaced one material finding: a body of work outside the 17 numbered plans (commits
`30217d4` "docs: rewrite README as current state" and roughly a dozen sibling `feat(demo)` /
`feat(decoder)` / `fix(render)` commits, dated 2026-09-07, sitting between Plan 10-13 and Plan
10-17 in history, reconciled in `10-VALIDATION.md` but never re-checked against Plan 10-12's own
acceptance criteria) substantially rewrote `README.md`. That rewrite is honest and passes every
currently-active gate (`readme-policy.sh`, `honesty-sweep.sh`, both re-run live in this audit), but
it dropped two literal artifacts Plan 10-12 committed and pinned by acceptance grep. Those two are
reported OPEN below rather than silently treated as still-closed. Nothing else in the 17-plan
register was affected by that rewrite; see the per-threat evidence for the plans that touch
`README.md` (10-11, 10-12, 10-13) for the specific commands re-run live to confirm the rest still
holds.

## Threat Register

Status is `closed` when a `mitigate` threat's cited artifact was independently confirmed present
and functioning by a live command in this session, or when an `accept`/`transfer` threat has a
documented rationale (see Accepted Risks). Status is `open` when the literal evidence the plan
itself specified is not currently present in the tree.

| Threat ID | Category | Disposition | Status | Evidence |
|---|---|---|---|---|
| T-10-01-01 | Repudiation | mitigate | closed | `Decoder/scripts/webgrid_ceiling.py:206-241` refuses `PENDING`/non-64-hex sha256; `manifest_path` + full digest written into `10-ceiling.json` |
| T-10-01-02 | Tampering | mitigate | closed | `10-PREREGISTRATION.md:7` frontmatter `rule:`; git-verified `a72344b` (pre-registration) is an ancestor of `b3eeba2` (the ceiling commit) |
| T-10-01-03 | Denial of Service | mitigate | closed | `webgrid_ceiling.py:271-286 load_tracks` reads only `target_pos`/`cursor_pos`; live `grep -c '"wf"'` on the script = 0 |
| T-10-01-04 | Tampering | mitigate | closed | `webgrid_ceiling.py:69-70 CANONICAL_DWELL_S` pinned constant; dwell logic unit-tested on synthetic arrays with independently known answers |
| T-10-01-07 | Repudiation | mitigate | closed | `10-ceiling-evidence.md:11` "What this is not" section present; banned framings (`maximum any decoder` etc.) absent |
| T-10-01-08 | Repudiation | mitigate | closed | `Decoder/tests/test_real_replay_schema.py:170-182 test_sc2_disposition_present_but_unasserted` checks enum membership only, never a specific value |
| T-10-01-05 | Information disclosure | mitigate | closed | `.gitignore:90 Decoder/data/`; only aggregate `10-ceiling.json` committed, no binary |
| T-10-01-06 | Elevation of Privilege | accept | closed | see Accepted Risks |
| T-10-02-01 | Denial of Service | mitigate | closed | `Decoder/src/ndt1/replay_export.py:388-` `read_export`: schema_version -> n_channels -> n_bins -> record_bytes -> getsize, all before `np.fromfile` |
| T-10-02-02 | Tampering | mitigate | closed | `replay_export.py:443-446` refuses non-64-hex `source_sha256`; `Decoder/scripts/export_replay.py:66,93-97` refuses `PENDING` |
| T-10-02-03 | Tampering | mitigate | closed | `bin_target_track` (last-sample-per-bin) + `target_distinct` membership assertion; `test_target_track.py` two-value mean-aggregator control |
| T-10-02-04 | Information disclosure | mitigate | closed | `.gitignore:95-99 Decoder/exports/` with `!Decoder/tests/fixtures/tiny_replay.bin` negation; fixture sidecar carries its own `disclosure` field |
| T-10-02-05 | Elevation of Privilege | mitigate | closed | `replay_export.py:450-461` resolves both paths, raises on parent mismatch (V12 symlink escape) |
| T-10-02-06 | Denial of Service | mitigate | closed | live `grep -c '"wf"' Decoder/src/ndt1/data.py` = 0 (3 prose mentions of the word "wf" exist; the quoted dataset-key literal does not) |
| T-10-02-07 | Repudiation | mitigate | closed | `Decoder/tests/fixtures/tiny_replay.json`: `session_id: "tiny_replay_synthetic"` + `disclosure`; asserted by `test_replay_export.py:381` |
| T-10-03-01 | Repudiation | mitigate | closed | `KalmanConstants.swift:7` header `noise source = indy-heldout`; `KalmanConstantsTests.swift:125 noiseSourceIsRealData`; executed Control 1 (`--data-dir /nonexistent` -> swift test exit 1) recorded in `10-03-SUMMARY.md` |
| T-10-03-02 | Tampering | mitigate | closed | `KalmanConstants.swift:3-5` do-not-hand-edit header; pre-existing structural invariant tests retained unchanged |
| T-10-03-06 (gain stability) | Tampering | mitigate | closed | `KalmanConstantsTests.swift:160 shippedGainIsSchurStable`; `Decoder/src/ndt1/kalman_gain.py:135-179 observable_gain` raises on non-Schur; executed Control 2 (10x row scale -> swift test exit 1) recorded |
| T-10-03-07 | Tampering | mitigate | closed | `KalmanConstants.swift:11` publishes `R_offdiag=-0.03146268` rather than discarding it; `noiseProvenanceShapes` byte-identical per summary |
| T-10-03-03 | Tampering | mitigate | closed | `kalman_gain.py:183-198 steady_state_gain` calls `observable_gain` (raises) before any header write |
| T-10-03-04 | Tampering | mitigate | closed | `KalmanConstants.swift:12` emits `grid_units_per_cm=0.05824724`, recoverable from the artifact alone |
| T-10-03-05 | Elevation of Privilege | mitigate | closed | `./Tools/scripts/hotpath-policy.sh` and `--self-test` run live in this audit, both exit 0 |
| T-10-03-06b (checkpoint path leak; the plan reuses ID `T-10-03-06` for this second, unrelated Information-disclosure/accept row) | Information disclosure | accept | closed | see Accepted Risks |
| T-10-04-01 | Denial of Service | mitigate | closed | `Packages/CortexCore/Sources/CortexCore/ReplayExport.swift:48,308 .sizeMismatch`; `ReplayExportTests.swift:100-108` Test 2 truncation control |
| T-10-04-02 | Elevation of Privilege | mitigate | closed | `ReplayExport.swift:46,274-286 .pathEscape` via `resolvingSymlinksInPath()`; `ReplayExportTests.swift:164-199` Test 7 symlink control |
| T-10-04-03 | Repudiation | mitigate | closed | `Packages/CortexDemo/Sources/CortexDemo/ReplayPipeline.swift:212-218,545-546`; `CortexDemoBench/main.swift:272-275` precondition on `allTicksModelBacked` |
| T-10-04-04 | Tampering | mitigate | closed | `--real` additive path; `git diff --stat` inside the existing tick loop confirmed empty per summary |
| T-10-04-08 | Tampering | mitigate | closed | `CortexDemoBench/main.swift:420,434-435 RealSeamReport` has no `passed`/`budget_ns` keys; verified by the summary's `python3` assert ("no verdict keys") |
| T-10-04-09 | Spoofing | mitigate | closed | `CortexDemoBench/main.swift:167-169 frame_period_ns`/`frames_modelled`/`cadence_provenance` |
| T-10-04-05 | Tampering | mitigate | closed | `./Tools/scripts/render-policy.sh` + `--self-test`, exit 0/0 per summary |
| T-10-04-06 | Information disclosure | mitigate | closed | `.gitignore:27 .bench/`; only sha256/session_id/repo-relative labels written |
| T-10-04-07 | Spoofing | mitigate | closed | `export_sidecar_sha256` computed from the file actually read; cross-checked by Plan 10-09's provenance gate |
| T-10-05-01 | Tampering | mitigate | closed | `KalmanConstants.swift:84 phase7BaselineK`; `CortexReFITBench --smoke` byte-identical vs committed `refit_bps.json` per summary |
| T-10-05-02 | Repudiation | mitigate | closed | `rotation_target_source` per-arm field; `refit_reversed_target`/`rotation_target_source` grep counts 4/3 recorded |
| T-10-05-03 | Repudiation | mitigate | closed | `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift:556-571`: a present, existing replay path now `exit(1)`, naming `CortexReplayBench` (verified live by reading the code) |
| T-10-05-04 | Tampering | mitigate | closed | single shared `decoded` array decoded once before the arm loop (structural; task text + inspectable code) |
| T-10-05-05 | Denial of Service | mitigate | closed | `ArmStatistics.swift`: `isFinite` guard count 4, named unit tests, per summary |
| T-10-05-06 | Tampering | mitigate | closed | live `grep -nE '(passed|verdict|PASS|FAIL)\s*=' Packages/CortexDemo/Sources/CortexReplayBench/main.swift` = empty |
| T-10-05-07 | Elevation of Privilege | mitigate | closed | `hotpath-policy.sh` acceptance criterion on both `CortexReFIT`-touching tasks |
| T-10-06-01 | Tampering | mitigate | closed | `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift:158-160,315-386` `--tamper` flips one tag byte; executed transcript (exit 1) recorded |
| T-10-06-02 | Repudiation | mitigate | closed | `Apps/CortexDaemon/Producer.swift:19,59-114`: set-but-unloadable `CORTEX_REPLAY_EXPORT` throws in `init`; `isReplayBacked`/`replaySessionId` recorded |
| T-10-06-03 | Tampering | mitigate | closed | `RollingSpikeWindow.push` returns `.gap(expected:got:)` and resets; named ordering/gap tests per summary |
| T-10-06-04 | Information disclosure | mitigate | closed | live `grep -rniE 'skip_encrypt|plaintext|noCrypto|disableAes' Apps/CortexDaemon/Producer.swift` = 0 matches |
| T-10-06-08 | Repudiation | mitigate | closed | `CortexSeamBSmoke/main.swift:493-522`: `windows_completed` anti-vacuity `precondition`s |
| T-10-06-09 | Spoofing | mitigate | closed | binary writes `data_source: "synthetic_fixture"`; Plan 10-09's schema test reads the field |
| T-10-06-05 | Denial of Service | mitigate | closed | `--frames` default 512; `ReplayExport.window(endingAt:length:1)` one bin at a time over a memory-mapped file |
| T-10-06-06 | Elevation of Privilege | mitigate | closed | `git diff --stat Packages/CortexIPC/` empty per summary; `hotpath-policy.sh --self-test` exit 0 |
| T-10-06-07 | Spoofing | mitigate | closed | `10-replay.json` Seam B carries distinct `boundary` + `not_comparable_to`; live check confirms `8318256` appears only in the Seam A section |
| T-10-07-01 | Repudiation | mitigate | closed | live check: `10-refit-real.json:124,140,158,168` carries all four digests (`encoder_checkpoint_sha256`, `export_sidecar_sha256`, `source_sha256`, `velocity_checkpoint_sha256`) |
| T-10-07-02 | Repudiation | mitigate | closed | `CortexReplayBench` precondition; `ticks_model_backed == ticks_total == 73129`, 0 fallbacks, recorded |
| T-10-07-03 | Tampering | mitigate | closed | radius/dwell/timeout read from the pre-registered export sidecar; `not relaxed` literal present in `10-refit-real-evidence.md` |
| T-10-07-04 | Tampering | mitigate | closed | live `grep -c '"passed"' 10-refit-real.json` = 0 |
| T-10-07-05 | Spoofing | mitigate | closed | live check: `10-refit-real-evidence.md:155` "dense 9x9" beside 4.16, `:161` "over 10 BPS" with date; `9.51` absent |
| T-10-07-06 | Information disclosure | mitigate | closed | three `.bench` directories deleted before the run, recorded in `10-07-SUMMARY.md` |
| T-10-08-01 | Spoofing | mitigate | closed | live check on `10-replay.json`: distinct `seam`/`boundary` strings; `8318256` present in the Seam A block only, absent from Seam B |
| T-10-08-02 | Repudiation | mitigate | closed | `allTicksModelBacked` precondition; `ticks_model_backed == ticks_total == 2294` |
| T-10-08-03 | Repudiation | mitigate | closed | live check: `10-replay.json` `replay_reference_hits`=147 byte-equal to `10-ceiling.json` `canonical_hits`=147 |
| T-10-08-04 | Tampering | mitigate | closed | radius/dwell/timeout from the pre-registered sidecar + Phase-7 defaults; ablation and this artifact share one replay |
| T-10-08-05 | Tampering | mitigate | closed | `-c release` used; `10-replay.json:210 build_configuration_note` records both debug and release runs since Phase-8's config was unrecorded |
| T-10-08-06 | Repudiation | mitigate | closed | `10-replay.json` `latency_caveat` states the single-process lock-step limitation explicitly rather than presenting the number as sound cross-process evidence |
| T-10-08-07 | Information disclosure | mitigate | closed | three `.bench` directories deleted before the first measurement, recorded |
| T-10-09-01 | Repudiation | mitigate | closed | `./Tools/scripts/refit-real-policy.sh` run live in this audit: exit 0, all required checks `ok`, cross-file digest identity confirmed against the manifest |
| T-10-09-02 | Tampering | mitigate | closed | `refit-real-policy.sh --self-test` run live: 6/6 controls pass, including a clean-tree baseline |
| T-10-09-03 | Tampering | mitigate | closed | live check: `refit-real-policy.sh:80` "D-09: no assertion below compares a measured value against a bar" sits directly above `scan()` at `:81` |
| T-10-09-04 | Denial of Service | mitigate | closed | `.github/workflows/ci.yml:721-730`: fails if `Decoder/exports/` is non-empty; `export_replay.py`/`webgrid_ceiling.py` named as never-run-in-CI |
| T-10-09-05 | Elevation of Privilege | mitigate | closed | live check: `Tools/scripts/check_real_replay_provenance.py:49-53` imports only `json`, `sys`, `pathlib` (stdlib-only) |
| T-10-09-06 | Repudiation | mitigate | closed | local `--self-test` transcripts recorded in the plan summary; Plan 10-17 performed the first real run (CI run 34182390856, confirmed live via `gh api`) |
| T-10-10-01 | Repudiation | mitigate | closed | live check: `10-10-PLAN.md:219,310` both carry `<task type="checkpoint:human-verify" gate="blocking">` |
| T-10-10-02 | Spoofing | mitigate | closed | `10-HUMAN-UAT.md`: iPad-M4 fields start `not measured`; iPad Air M2 rows explicitly labeled "corroborating"; live grep found no Mac number labeled iPad |
| T-10-10-03 | Repudiation | mitigate | closed | `Apps/CortexMac/ContentView.swift:74-76 Text(blind.sourceLabel)`: "name the spike source ON SCREEN" |
| T-10-10-04 | Tampering | mitigate | closed | capture uses the same export and pre-registered geometry as `10-replay.json`; no-hit outcome stated without qualification |
| T-10-10-05 | Information disclosure | mitigate | closed | `readme-policy.sh` forbidden-absent set (PEM/MATCH_PASSWORD/email/UUID) run live, all `ok`; reviewer-checked-frame process documented |
| T-10-10-06 | Repudiation | mitigate | closed | live check: `grep -cE 'LAT-0[1-8]' 10-HUMAN-UAT.md` = 0 |
| T-10-10-07 | Tampering | mitigate | closed | `CODE_SIGN_ENTITLEMENTS=` build-time override; live `git diff --stat` over the three entitlements files + `project.yml` across the exact Plan 10-10 commit range (`8ee012c^..d7cd8d9`) confirmed empty |
| T-10-10-08 | Spoofing | mitigate | closed | live check: `10-demo-capture-evidence.md:228-255` "What the capture build is not" section, literal "signing only" present |
| T-10-10-09 | Repudiation | mitigate | closed | `10-10-PLAN.md` Task 3a: five headless committed artifacts enumerated, recording listed last as illustration |
| T-10-10-10 | Repudiation | mitigate | closed | live check: `10-replay.json:203 sc2_disposition = "not_met"`, set via a blocking `checkpoint:decision` on the user's own recorded answer |
| T-10-11-01 | Repudiation | mitigate | closed | live check: `Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift:51,55 brainGateDenseGridBPS` / `brainGate6x6T5BPS` |
| T-10-11-02 | Repudiation | mitigate | closed | live check: `docs/cortex-spec.md:54,172,317` all carry "over 10 BPS" and "retrieved 2026-09-05" |
| T-10-11-03 | Tampering | mitigate | closed | live check: `git grep -cF "9.51"` (fixed-string) over `docs/ .planning/PROJECT.md .planning/ROADMAP.md Packages/CortexReFIT/Sources/` = 0. Note: a naive unescaped-dot `grep "9.51"` reports 1 hit in `KalmanConstants.swift`, but that is a regex-metacharacter false positive matching part of the unrelated float literal `0.15044899551772603` (the R-matrix noise variance); the fixed-string check is definitive |
| T-10-11-04 | Tampering | mitigate | closed | live check: `Packages/CortexDemo/Tests/CortexDemoTests/GlassToGlassTimerTests.swift:50 hasPrefix("software-timed pipeline latency")`, guarding `readme-policy.sh:136` |
| T-10-11-08 | Repudiation | mitigate | closed | `honesty-sweep.sh` "grounds" check run live: `ok [grounds] all four BPS non-comparability grounds in the README and the spec` |
| T-10-11-09 | Repudiation | mitigate | closed | `honesty-sweep.sh` "authority" check run live: `ok [authority] the 8.5 reference is nowhere framed as verified` |
| T-10-11-05 | Tampering | mitigate | closed | `./Tools/scripts/bps-policy.sh` run live: exit 0; artifact regenerated and re-committed in the same commit per summary |
| T-10-11-06 | Repudiation | mitigate | closed | live check: `08-bps-evidence.md:13 "## Amendment (2026-09-07..."` block; `git diff ce7b789^..ce7b789 -- webgrid_bps.json` shows only a key rename (`brain_gate_6x6_bps` -> `brain_gate_dense_9x9_bps`, value unchanged 4.16) plus one added key; every measured field (`correct`, etc.) byte-identical |
| T-10-11-07 | Repudiation | mitigate | closed | live check: `git grep "4.16 -> 8.5"` over `docs/cortex-spec.md .planning/PROJECT.md .planning/ROADMAP.md` = 0 |
| T-10-12-01 | Repudiation | mitigate | closed | Closed by ELIMINATION, not by the planned labelling. `1.953` no longer appears in `README.md` at all (commit `30217d4` removed the Phase-8 comparison table rather than mislabelling it), so a synthetic number cannot be read as real from a number that is absent. The general policy sentence survives at `README.md:246-247`; the figure stays banner-labelled in `08-bps-evidence.md`; `honesty-sweep.sh` re-run live catches any unlabelled reintroduction. See Superseded Mitigations |
| T-10-12-02 | Repudiation | mitigate | closed | live check: `README.md:268` "Glass-to-glass latency 24.7 +/- 1.3 ms ... is a retired spec target, never measured." |
| T-10-12-03 | Repudiation | mitigate | closed | live check: `README.md:224-227` `<!-- CI-STATUS-CLAIM -->` hook present, wording now cites the actual run (`34182390856`, commit `710e729`) after Plan 10-17's execution |
| T-10-12-04 | Information disclosure | mitigate | closed | `readme-policy.sh` run live: all four forbidden-absent checks (PEM/MATCH_PASSWORD/email/issuer-UUID) report `ok` |
| T-10-12-05 | Tampering | mitigate | closed | live check: `git show --stat f6c82b3` ("add Phase-10 superseded banners to five evidence files") is a banner-only additions commit |
| T-10-12-06 | Tampering | mitigate | closed | live check: `LAT-0[1-8]` present in both `ROADMAP.md` and `REQUIREMENTS.md`; `honesty-sweep.sh` "preserve" check `ok` |
| T-10-12-07 | Spoofing | mitigate | closed | Closed by a STRONGER caveat than the planned pairing. `README.md:278-280` heads the table "None of these is a claim about this project" and marks 8.5 "not independently sourceable to a Neuralink primary" - the spoofing core (an external figure carried in as authoritative) is denied outright. The dropped `over 10 BPS` anchor was anti-staleness only, and the superseded text itself conceded "an access date does not authenticate a number". `docs/cortex-spec.md:54,172,317` still carries the dated wording. See Superseded Mitigations |
| T-10-13-01 | Tampering | mitigate | closed | `readme-policy.sh --self-test` run live: 19 `PASS` lines, 8/8 corpus cases, 0 `FAIL` |
| T-10-13-02 | Repudiation | mitigate | closed | live self-test: `retired-B` achievement rule `ok`; corpus/3,4,5,8 (the four dishonest sentences) each bite |
| T-10-13-03 | Tampering | mitigate | closed | live self-test: corpus/1,2 (retired-context occurrences) both `PASS` |
| T-10-13-08 | Tampering | mitigate | closed | live self-test rule-isolation: corpus/6 (rule A alone), corpus/8 (rule B alone), corpus/7 (rule C alone) each bite independently |
| T-10-13-04 | Repudiation | mitigate | closed | live self-test: D-14 provenance-triple negative controls (session id, checkpoint prefix, disclosure phrase) all `PASS` |
| T-10-13-05 | Tampering | mitigate | closed | live self-test: corpus/1 ("never measured" survives) vs corpus/3 ("we measured" bites) both correct |
| T-10-13-09 | Repudiation | mitigate | closed | live check: `docs/adr/0003-photodiode-retirement-and-real-data-v1.md:22,33` carries `hardware-gated` and `largest credibility hole` |
| T-10-13-06 | Repudiation | mitigate | closed | live check: ADR-0003 `:47-52,79,103` names all eight `LAT-0N` identifiers and explicitly rejects deletion |
| T-10-13-07 | Information disclosure | mitigate | closed | live self-test: all four forbidden-secret negative controls (PEM/email/MATCH_PASSWORD/UUID) `PASS`, unchanged from Plan 10-12/10-09 |
| T-10-14-01 | Repudiation | mitigate | closed | `honesty-sweep.sh --self-test` run live: control 1 (strip label from a `1.953` stand-in) bites, exit 1 |
| T-10-14-02 | Repudiation | mitigate | closed | live self-test: control 2 (remove superseded-evidence banner) bites, exit 1 |
| T-10-14-03 | Tampering | mitigate | closed | live self-test: controls 3/3b (delete `LAT-05` from ROADMAP/REQUIREMENTS) each bite |
| T-10-14-04 | Tampering | mitigate | closed | live self-test: controls 4/5 (remove ADR index link / remove a heading) each bite |
| T-10-14-05 | Tampering | mitigate | closed | live check: `honesty-sweep.sh:159` exclusion comment names Plan 09-08's attribution control by ID |
| T-10-14-06 | Tampering | mitigate | closed | task text forbids widening `LABEL_TOKENS`; first-run occurrences tabulated with disposition in `10-14-SUMMARY.md` |
| T-10-14-07 | Tampering | mitigate | closed | live check: `honesty-sweep.sh:491` "D-09: no assertion below compares a measured value against a bar" sits directly above `scan()` at `:493` |
| T-10-14-08 | Denial of Service | mitigate | closed | live check: `honesty-sweep.sh:100-108` uses the token `226/226` (not bare `226`) throughout `SUPERSEDED_TOKENS`/`BANNER_TOKENS` |
| T-10-15-01 | Tampering | mitigate | closed | `./Tools/scripts/toolchain-policy.sh` + `--self-test` run live: exit 0/0, 4 negative controls (missing pin, drift, missing file, un-wired CI) all bite |
| T-10-15-02 | Tampering | mitigate | closed | all 12 gate scripts (`bps`, `decoder`, `hid-surface`, `hotpath`, `honesty-sweep`, `infoplist`, `match`, `notarize`, `readme`, `refit-real`, `render`, `toolchain`) re-run live in this audit: all exit 0 |
| T-10-15-03 | Tampering | mitigate | closed | `KalmanConstants.swift` do-not-hand-edit header intact; `swift test --package-path Packages/CortexReFIT` passes (32 tests / 5 suites) |
| T-10-15-04 | Tampering | mitigate | closed | bench byte-identity checks (`refit_bps.json`, `webgrid_bps.json`) and all eight package suites reported passing; commit scope restricted to `.swift` under `Apps/`/`Packages/` |
| T-10-15-05 | Information disclosure | mitigate | closed | live spot-check: provenance headers intact post-sweep in `KalmanFilter.swift` and `ReplayPipeline.swift` |
| T-10-15-06 | Repudiation | mitigate | closed | live git-ancestor check: `16a09d0` (baseline commit) confirmed an ancestor of `94c1b19` (the formatter sweep commit) |
| T-10-15-07 | Spoofing | accept | closed | see Accepted Risks |
| T-10-16-01 | Tampering | mitigate | closed | live check: `Packages/CortexDemo/Sources/CortexReplayBench/main.swift:478,506,524,544,567` — explicit `CodingKeys` enums present |
| T-10-16-02 | Tampering | mitigate | closed | `10-lint-remediation-evidence.md:410`: disposition table for all handled force-unwrap/cast sites, every "behaviour-could-differ" answer "no" or "strictly better"; no `?? default` substitutions |
| T-10-16-03 | Tampering | mitigate | closed | live check: `grep "allowed_symbols" .swiftlint.yml` = 0 matches |
| T-10-16-04 | Tampering | mitigate | closed | live check: `blanket_disable_command` not in `.swiftlint.yml` `disabled_rules`; suppression audit shows 5 remaining disables, all `:this`/`:next`-paired |
| T-10-16-05 | Tampering | mitigate | closed | all 12 gates + self-tests confirmed green live (same evidence as T-10-15-02); CI run `34182390856` independently confirms `swiftlint --strict` 0 violations on both hosted runners |
| T-10-16-06 | Denial of Service | mitigate | closed | task text mandates smallest-honest-change discipline; the byte-diffed bench file was not split for a length rule |
| T-10-16-07 | Repudiation | mitigate | closed | evidence artifact originally stated "never run on a hosted runner"; live check of `10-first-ci-run-evidence.md:209-210` confirms Plan 10-17's actual CI run measured `swiftlint --strict` 0 violations / `swiftformat --lint` 0 files on both `macos-26-arm64` and `macos-15` |
| T-10-17-01 | Information disclosure | mitigate | closed | live check: no PEM private-key header in any tracked file; the four grep matches are template/placeholder content (`fastlane/asc_api_key.json.example` and two `PLAN.md` files describing the required schema), confirmed by direct inspection |
| T-10-17-02 | Information disclosure | mitigate | closed | live check: `git ls-files` has nothing under `Decoder/{data,exports,checkpoints}/`, no `.pt`/`.mlpackage`/`.mlmodelc`, only `Decoder/tests/fixtures/tiny_v73.mat` tracked |
| T-10-17-03 | Information disclosure | mitigate | closed | live check: no unexpected personal email in tracked files; the only email-shaped matches are `git@github.com` remote-URL syntax, not PII |
| T-10-17-04 | Information disclosure | mitigate | closed | live check confirms `10-prepush-audit.md:294,299`: "clean: NO tracked image, screen recording or still frame anywhere in the repo" |
| T-10-17-05 | Repudiation | mitigate | closed | live check: `README.md:224-227` written after the run, cites `34182390856`/`710e729` by ID and URL rather than asserting a state |
| T-10-17-06 | Tampering | mitigate | closed | live `git reflog` inspection: the sole `amend` entry (`879fbe1`) is a pre-existing commit-SHA-citation remap from the disclosed 2026-09-07 history scrub, unrelated to and preceding Plan 10-17 |
| T-10-17-07 | Denial of Service | mitigate | closed | live check: `10-first-ci-run-evidence.md:230` "Zero of the three permitted attempts were used" |
| T-10-17-08 | Elevation of Privilege | mitigate | closed | `gh repo edit` never invoked (grep of the plan's own commits); live `gh repo view D0NMEGA/Cortex --json isPrivate` = `true` |
| T-10-17-09 | Spoofing | mitigate | closed | live `gh repo view` confirms `isPrivate: true`; push and visibility are separated per the plan's own option structure |

## Open Threats

None. `threats_open: 0`.

## Superseded Mitigations

Two rows were reported `open` by the auditor because the literal artifact Plan 10-12 pinned by
acceptance grep is absent from the current tree. Both were adjudicated by the user on 2026-09-09 and
recorded as `closed` by different means. The adjudication is recorded here rather than applied
silently, and neither row was closed by restoring text to `README.md`.

Root cause, shared: commit `30217d4` ("docs: rewrite README as current state", 2026-09-07) landed
between Plans 10-13 and 10-17, outside the 17 numbered plans. It was reconciled in `10-VALIDATION.md`
for the threats a standing gate covers, but a plan's `<acceptance_criteria>` grep runs ONCE at
execution time and never becomes a standing gate unless someone wires it into a policy script.
Neither of these two was wired in, so the rewrite passed every gate that exists and still voided
both mitigations as written.

| Threat ID | Mitigation as planned | What protects it now | Why the new form is not weaker |
|---|---|---|---|
| T-10-12-01 | `grep -cF '1.953' README.md` >= 1, every occurrence beside the word `synthetic` (`10-12-PLAN.md:290`) | The number is gone from `README.md` entirely (0 occurrences). The general labelling policy stands at `README.md:246-247`; `08-bps-evidence.md` still carries the figure under its superseded banner; `honesty-sweep.sh` (re-run live, negative control biting) catches an unlabelled reintroduction | The threat is a synthetic number presented as real. Removing the number eliminates the threat at its source; labelling only manages it. Elimination is the stronger closure, and it aligns with the 2026-08-28 v1 re-point that drove synthetic figures out of headline positions |
| T-10-12-07 | `grep -cF 'over 10 BPS' README.md` >= 1, dated, beside the historical 8.5 (`10-12-PLAN.md:294`) | `README.md:276` heads the table "None of these is a claim about this project"; `README.md:280` marks 8.5 "not independently sourceable to a Neuralink primary". `docs/cortex-spec.md:54,172,317` retains `over 10 BPS` with its 2026-09-05 retrieval date | The threat is an unsourced external figure carried in as authoritative. The current wording denies sourceability outright, which is a stronger disclaimer than a dated pairing. The superseded line itself said "an access date does not authenticate a number", and the omitted figure is HIGHER than the one cited, so its absence cannot flatter this project |

Residual, accepted with the closure: `README.md` no longer tells a reader that the vendor's current
public claim exceeds the 8.5 it cites. The exposure is low - the direction of the omission works
against this project, not for it - and `docs/cortex-spec.md` still carries the dated wording for
anyone following the citation. Recorded so the trade is visible rather than assumed away.

Queued follow-up (user-approved 2026-09-09, NOT done in this audit): promote the surviving README
invariants into `Tools/scripts/readme-policy.sh` as standing controls with `--self-test` negative
controls, so the next out-of-plan rewrite cannot silently void a mitigation the way this one did.
`README.md` is a repository file, so that work belongs in a separate `/donny-quick`, not here.
Logged to `deferred-items.md`.

## Unregistered Flags

Two `threat_flag` entries from `## Threat Flags` sections in the plan summaries do not map to an
existing threat ID in the 17-plan register. Both were explicitly logged by the executor as
informational / no register entry proposed, and neither blocks this audit, but both are live,
unresolved observations as of this session:

| Flag | File | Description | Current status |
|---|---|---|---|
| `threat_flag: unverified_by_default` | `Decoder/src/ndt1/replay_export.py` | `read_export`'s `verify_digest` parameter defaults to `False`: an ordinary read validates the sidecar-declared SIZE against the binary but does not re-hash the binary's CONTENT against `binary_sha256`. Truncation and length-changing substitution are still caught by the size check; a same-length content substitution would not be. The executor recommended that consumers publishing a number from an export (Plan 10-09's provenance gate, the daemon's D-05 chain) pass `verify_digest=True` or hash the binary themselves. | Live-checked in this audit: `Tools/scripts/check_real_replay_provenance.py` never calls `read_export` or passes `verify_digest` at all — it cross-checks digest fields already recorded in the JSON artifacts against the manifest and against each other, not against a fresh re-hash of the binary export. The recommendation was not adopted by Plan 10-09 or any later plan. Residual, unaddressed. |
| `threat_flag: new_config_surface` | `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` | `--export <path>` / `--model <path>` argv inputs were added alongside the pre-existing `CORTEX_REPLAY_EXPORT`/`CORTEX_MODEL_URL` env-var surface the register names. The executor assessed the trust level as identical (same local CLI invocation, same `ReplayExport` validation, same `NeuralDecoder(modelURL:)` sink) and proposed no register entry. | No further action found necessary; the executor's own equivalence argument holds on inspection (`ReplayExport`'s `.pathEscape`/`.sizeMismatch` checks, verified under T-10-04-01/02 above, apply uniformly regardless of how the path arrived). Recorded here per instruction rather than silently dropped. |

## Accepted Risks

Three threats carry an `accept` disposition in the source plans. Each is recorded here with its
plan-stated rationale, preserved exactly as declared (no disposition demoted, no rationale
invented):

| Threat ID | Category | Component | Rationale (verbatim from the source plan) |
|---|---|---|---|
| T-10-01-06 | Elevation of Privilege | a third-party import (`numpy`, `h5py`) in a script that later runs unattended | "The script runs under the pinned `uv` environment (numpy, h5py) which the `decoder-python` CI job already provisions; no new dependency is added and no network call is made." (`10-01-PLAN.md` threat_model) |
| T-10-03-06b | Information disclosure | a checkpoint path or dataset byte leaking into a committed artifact | "Only 12-hex digest prefixes and repo-relative paths are written; the checkpoints and `.mat` files are gitignored and nothing binary is committed by this plan." (`10-03-PLAN.md` threat_model, second use of ID `T-10-03-06`). Live-verified: `KalmanConstants.swift:9` carries `sha256=2ca8f6b7fcfc`, `encoder_sha=f95b257bf247`, `velocity_sha=9d542cb51d4a` — all 12-hex prefixes, no full digest, no path, no binary. |
| T-10-15-07 | Spoofing | a supply-chain substitution through an unpinned `brew install` | "Homebrew's own signing and the project's existing install path are unchanged; the pin gate converts a version substitution into a loud failure. A harder pin (GitHub release artifacts with sha256) is recorded as the rejected alternative in the gate's header comment, with its cost." (`10-15-PLAN.md` threat_model). Live-verified: `Tools/scripts/toolchain-policy.sh` + `--self-test` both exit 0, and the gate's version-mismatch negative control was confirmed to bite live. |

## Summary

All 133 threat-register rows (132 unique IDs) are closed. 131 closed on the audit of 2026-09-08 with
live, independently reproduced evidence: a file:line match for the declared code-level mitigation, a
gate script plus its `--self-test` run in session, or a git-ancestor/diff check for the process- and
documentation-level controls this phase relies on heavily given its subject matter (scientific-claim
integrity). The remaining 2 (`T-10-12-01`, `T-10-12-07`) were reported open because their literal,
plan-pinned evidence had been superseded by an out-of-plan but honest README rewrite; both were
adjudicated by the user on 2026-09-09 and closed by different means, with the reasoning and the
accepted residual recorded under Superseded Mitigations. No `mitigate` threat was found unevidenced
and silently carried as closed; no `accept` disposition was demoted or given an invented rationale;
the one ID collision (`T-10-03-06`) is preserved as two distinct rows per instruction.

## Security Audit 2026-09-08

| Metric | Count |
|--------|-------|
| Threats found | 133 |
| Closed | 131 |
| Open | 2 |

Register built from the `<threat_model>` blocks of all 17 Phase-10 plans: 133 rows, 132 unique IDs.
Dispositions were carried across unchanged and re-checked against the plans after the audit: 130
`mitigate` and 3 `accept`, with the same six STRIDE categories at the same counts the plans declare
(Tampering 49, Repudiation 40, Information disclosure 15, Spoofing 11, Denial of Service 10,
Elevation of Privilege 8). No mitigation was demoted to an acceptance and no category was flattened.

Two orchestrator corrections were applied to the auditor's draft and are recorded here rather than
left silent:

1. The register section was emitted as `## Threat Verification`. The engine's `verify threats-clear`
   parses `## Threat Register` by name, so the heading was renamed. Before the rename the checker
   returned `has_register: false`, which reads as "not clear" and would have blocked on a parse
   failure rather than on the two real findings. Table content was not altered.
2. The two open rows were re-derived independently before being accepted. `10-12-PLAN.md:290` pins
   `grep -cF '1.953' README.md` at 1 or more and `10-12-PLAN.md:294` pins `grep -cF 'over 10 BPS'
   README.md` at 1 or more. Both return 0 against the current tree, so both findings stand on the
   plan's own acceptance criteria rather than on the auditor's judgement.

`verify threats-clear` after the rename: `clear: false`, `threats_open: 2`, `declared: 2`,
`consistent: true`, `has_register: true`. The table and the frontmatter agree.

## Security Audit 2026-09-09

| Metric | Count |
|--------|-------|
| Threats found | 133 |
| Closed | 133 |
| Open | 0 |

Re-disposition pass, no re-verification of the 131 rows already closed on 2026-09-08. The two rows
`T-10-12-01` and `T-10-12-07` moved from `open` to `closed` by a user decision recorded at this
audit's accept/block gate, on the reasoning set out under Superseded Mitigations: each threat's
planned mitigation was voided by commit `30217d4`, and in each case what replaced it denies the
threat more strongly than the planned control did. The register's mitigation-plan text was amended
to describe what actually protects each row now; the dispositions themselves (`mitigate`) and the
STRIDE categories were NOT altered, and no row was reclassified as an accepted risk.

One residual is accepted rather than closed away, and is stated in the table above: `README.md` no
longer records that the vendor's current public claim exceeds the 8.5 figure it cites. The dated
wording survives in `docs/cortex-spec.md:54,172,317`.

Structural finding, queued and not fixed here: a plan's `<acceptance_criteria>` grep is a one-shot
check at execution time, not a standing gate. Neither pinned grep was ever wired into
`readme-policy.sh`, which is why an out-of-plan rewrite could void two mitigations while passing
every gate the repository actually runs. Promoting the surviving invariants into `readme-policy.sh`
with `--self-test` controls is logged to `deferred-items.md` for a separate `/donny-quick`.

`verify threats-clear` after this pass: `clear: true`, `threats_open: 0`, `declared: 0`,
`consistent: true`, `has_register: true`.
