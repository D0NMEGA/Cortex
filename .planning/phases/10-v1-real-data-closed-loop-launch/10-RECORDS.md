---
status: fail
agent: donny-tools verify gate
phase: 10-v1-real-data-closed-loop-launch
slug: v1-real-data-closed-loop-launch
verbs_run: 13
errors: 3
warnings: 4
not_yet: 1
not_applicable: 1
passed: 4
created: 2026-09-08
---

# Phase 10 - Record Gate

NOTE ON FORMAT: this file intentionally contains no bare `---` horizontal rules in its body.
Only the two frontmatter fence lines above use `---`. The engine's frontmatter parser
(`bin/lib/frontmatter.cjs:16-17`) treats every `---`/`---` pair in a file as a candidate
frontmatter block and prefers the LAST one, so a decorative section rule would make the real
frontmatter above silently unreadable. This is the same defect class the record gate exists to
catch, and `templates/SECURITY.md` currently has it.

## Verdict

The verdict is re-derived from the Verb Results table below on every read, never trusted from
the frontmatter above (D-11, the A6 ENFORCING GATE pattern). `status` is `fail` if and only if
at least one Verb Results row has Severity `error`. A hand-edited, stale or truncated
frontmatter verdict is non-authoritative by construction; a disagreement is reported as
`consistent: false` and the table wins.

Severities: `pass` (clean), `warning` (recorded, does not fail), `error` (fails the gate),
`not_applicable` (the check does not apply to this phase), `not_yet` (the input artifact
legitimately does not exist at this point in the phase lifecycle). The absence of this file
entirely is a sixth state, `not_run`, and never reads as a pass (D-10, GATE-02).

## Verb Results

| Verb | Scope | Targets | Severity | Detail |
|------|-------|---------|----------|--------|
| phase-completeness | phase | 1 | warning | Summaries without plans: 10-03a-RECONCILIATION |
| plan-graph | phase | 1 | pass | 17 plan(s), acyclic, every dependency in an earlier wave |
| phase-verified | phase | 1 | error | VERIFICATION.md status is "human_needed"; the engine matches the literal lowercase "passed" |
| threats-clear | phase | 1 | not_yet | no SECURITY.md yet; /donny-audit-phase writes it after close |
| ui-reviewed | phase | 1 | not_applicable | no UI-REVIEW.md; not a UI phase |
| schema-drift | phase | 1 | pass | no schema drift |
| milestone-coverage | phase | 1 | error | 4 of 8 requirement(s) not satisfied |
| plan-structure | per-plan | 17 | pass | 10-01-PLAN.md: 3 task(s), no structural errors |
| references | per-plan | 17 | warning | 10-01-PLAN.md: 10 of 30 reference(s) did not resolve |
| artifacts | per-plan | 17 | warning | 10-05-PLAN.md: 3 of 4 artifact(s) verified |
| key-links | per-plan | 17 | warning | 10-04-PLAN.md: 2 of 3 key link(s) verified |
| verify-summary | per-summary | 18 | error | 10-03a-RECONCILIATION-SUMMARY.md: requirements-completed is empty (plus 2 known-artifact finding(s): commits_exist, self_check) |
| commits | phase | 1 | pass | 20 commit hash(es) resolved |

## Findings

| Verb | Target | Severity | Finding |
|------|--------|----------|---------|
| phase-completeness |  | warning | Summaries without plans: 10-03a-RECONCILIATION |
| phase-verified |  | error | VERIFICATION.md status is "human_needed"; the engine matches the literal lowercase "passed" |
| milestone-coverage |  | error | LAT-05: unsatisfied; LAT-06: unsatisfied; LAT-07: unsatisfied; LAT-08: unsatisfied; RD-07: partial (not listed in any SUMMARY's requirements-completed); RD-08: partial (not listed in any SUMMARY's ... |
| references | 10-01-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -c 'def test_' Decoder/tests/test_webgrid_ceiling.py; grep -c '@pytest.mark.slow' Decoder/tests/test_webg... |
| references | 10-02-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; !Decoder/tests/fixtures/tiny_v73.mat; grep -c 'def test_' Decoder/tests/test_target_track.py; grep -F 'def bin... |
| references | 10-03-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; swiftformat --lint Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift; grep -cF 'return default_no... |
| references | 10-04-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; Packages/CortexDemo/Sources/CortexDemo/ClosedLoopPipeline.swift; CortexDemoBench/main.swift; grep -c '@Test' P... |
| key-links | 10-04-PLAN.md | warning | Packages/CortexDemo/Sources/CortexDemo/ClosedLoopPipeline.swift -> Packages/CortexDecoder/Sources/CortexDecoder/ZeroCopyInput.swift: Source file not found |
| references | 10-05-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; .bench/webgrid_bps.json; .bench/refit_bps.json; CortexReFITBench/main.swift; diff Packages/CortexReFIT/.bench/... |
| artifacts | 10-05-PLAN.md | warning | Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift: Missing pattern: public init(gain: |
| references | 10-06-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -c '@Test' Packages/CortexDemo/Tests/CortexDemoTests/RollingSpikeWindowTests.swift; grep -F 'case gap(exp... |
| key-links | 10-06-PLAN.md | warning | Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift -> Packages/CortexDecoder/Sources/CortexDecoder/NeuralDecoder.swift: Invalid regex pattern: decode( |
| references | 10-07-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; .bench/glass_to_glass.json; shasum -a 256 Decoder/exports/indy_20160630_01.replay.json |
| references | 10-08-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; .bench/glass_to_glass_real.json; .bench/seam_b.json |
| key-links | 10-08-PLAN.md | warning | .planning/phases/10-v1-real-data-closed-loop-launch/10-replay.json -> .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json: Pattern "ceiling_ref" not found in source or target |
| references | 10-09-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; python3 Tools/scripts/check_refit_uplift.py; ./Tools/scripts/X-policy.sh; python3 Tools/scripts/check_real_rep... |
| references | 10-10-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; git checkout -- Apps/CortexMac/Info.plist Apps/CortexiOS/Info.plist; CORTEX_REPLAY_EXPORT=Decoder/exports/indy... |
| references | 10-11-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; Packages/CortexDemoBench/main.swift; .bench/webgrid_bps.json; .planning/phases/07-.../refit_bps.json; CortexDe... |
| references | 10-12-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -cF '226/226' README.md; grep -cF '239/239' README.md; grep -cF '0003-' .planning/ROADMAP.md; grep -cE '9... |
| key-links | 10-12-PLAN.md | warning | README.md -> .planning/phases/10-v1-real-data-closed-loop-launch/10-refit-real-evidence.md: Pattern "10-refit-real-evidence.md" not found in source or target |
| references | 10-13-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -cE 'require_fixed_in_file .*"photodiode"' Tools/scripts/readme-policy.sh; grep -cE 'require_fixed_in_fil... |
| references | 10-14-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; docs/adr/0003-*.md; Tools/scripts/*-policy.sh; $SWEEP_ADR_DIR/0003-*.md; $SWEEP_ADR_DIR/README.md; adr/0003-x.... |
| references | 10-15-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -cF 'toolchain-versions.env' .github/workflows/ci.yml; grep -cF 'toolchain-policy.sh' .github/workflows/c... |
| references | 10-16-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; .bench/refit_bps.json; .bench/webgrid_bps.json; diff Packages/CortexReFIT/.bench/refit_bps.json .planning/phas... |
| references | 10-17-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; origin  https://github.com/D0NMEGA/Cortex.git; Decoder/**/*.mat; Decoder/**/*.pt; git log origin/main..HEAD |
| verify-summary | 10-02-SUMMARY.md | warning | Self-check section indicates failure |
| verify-summary | 10-03-SUMMARY.md | warning | Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 10-03a-RECONCILIATION-SUMMARY.md | error | requirements-completed is empty; Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 10-04-SUMMARY.md | warning | Self-check section indicates failure |
| verify-summary | 10-05-SUMMARY.md | warning | Missing files: diff .bench/refit_bps.json .planning/phases/07-*/refit_bps.json; Self-check section indicates failure |
| verify-summary | 10-06-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Self-check section indicates failure |
| verify-summary | 10-07-SUMMARY.md | warning | Missing files: rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench; Self-check section indicates failure |
| verify-summary | 10-08-SUMMARY.md | warning | Missing files: rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench, rm -rf Packages/{CortexReFIT,CortexDemo,CortexDecoder}/.bench; Referenced commit hashes n... |
| verify-summary | 10-09-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair) |
| verify-summary | 10-10-SUMMARY.md | warning | Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 10-11-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Missing files: .bench/webgrid_bps.json |
| verify-summary | 10-12-SUMMARY.md | warning | Missing files: git diff --stat -- Apps/CortexMac/Cortex.entitlements Apps/CortexiOS/Cortex.entitlements Apps/CortexDaemon/Cortex.entitlements project.yml |
| verify-summary | 10-13-SUMMARY.md | warning | Self-check section indicates failure |
| verify-summary | 10-14-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Self-check section indicates failure |
| verify-summary | 10-15-SUMMARY.md | warning | Self-check section indicates failure |
| verify-summary | 10-16-SUMMARY.md | warning | Missing files: .planning/phases/10-*/10-lint-remediation-evidence.md, CortexDecoderBench/main.swift; Self-check section indicates failure |
| verify-summary | 10-17-SUMMARY.md | warning | Missing files: git log   origin/main..HEAD; Self-check section indicates failure |

## Record Gate Audit Trail

| Run Date | Verbs | Errors | Warnings | Not yet | N/A | Verdict | Run By |
|----------|-------|--------|----------|---------|-----|---------|--------|
| 2026-09-08 | 13 | 3 | 4 | 1 | 1 | fail | donny-tools verify gate |
