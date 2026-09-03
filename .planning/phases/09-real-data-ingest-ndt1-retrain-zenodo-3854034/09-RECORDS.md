---
status: fail
agent: donny-tools verify gate
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
slug: real-data-ingest-ndt1-retrain-zenodo-3854034
verbs_run: 13
errors: 3
warnings: 3
not_yet: 0
not_applicable: 1
passed: 6
created: 2026-09-03
---

# Phase 09 - Record Gate

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
| phase-completeness | phase | 1 | warning | Summaries without plans: 09-06b, 09-06c, 09-06d |
| plan-graph | phase | 1 | pass | 11 plan(s), acyclic, every dependency in an earlier wave |
| phase-verified | phase | 1 | error | VERIFICATION.md status is "PARTIAL"; the engine matches the literal lowercase "passed" |
| threats-clear | phase | 1 | pass | threat register present, zero open |
| ui-reviewed | phase | 1 | not_applicable | no UI-REVIEW.md; not a UI phase |
| schema-drift | phase | 1 | pass | no schema drift |
| milestone-coverage | phase | 1 | error | 4 of 10 requirement(s) not satisfied |
| plan-structure | per-plan | 11 | pass | 09-01-PLAN.md: 3 task(s), no structural errors |
| references | per-plan | 11 | warning | 09-01-PLAN.md: 23 of 34 reference(s) did not resolve |
| artifacts | per-plan | 11 | pass | 09-01-PLAN.md: 3 artifact(s) verified |
| key-links | per-plan | 11 | warning | 09-04-PLAN.md: 2 of 3 key link(s) verified |
| verify-summary | per-summary | 14 | error | 09-02-SUMMARY.md: requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair) (plus 2 known-artifact finding(s): files_created, self_check) |
| commits | phase | 1 | pass | 20 commit hash(es) resolved |

## Findings

| Verb | Target | Severity | Finding |
|------|--------|----------|---------|
| phase-completeness |  | warning | Summaries without plans: 09-06b, 09-06c, 09-06d |
| phase-verified |  | error | VERIFICATION.md status is "PARTIAL"; the engine matches the literal lowercase "passed" |
| milestone-coverage |  | error | LAT-01: unsatisfied; LAT-02: unsatisfied; LAT-03: unsatisfied; LAT-04: unsatisfied; RD-01: partial (not listed in any SUMMARY's requirements-completed); RD-02: partial (not listed in any SUMMARY's ... |
| references | 09-01-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -c '"id"' Decoder/manifests/indy_sessions.json; grep -F 'indy_20160915_01' Decoder/manifests/indy_sessi... |
| references | 09-02-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; Decoder/**/*.mat; git check-ignore -v Decoder/tests/fixtures/tiny_v73.mat; grep -F '!Decoder/tests/fixtures/... |
| references | 09-03-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; nlb_tools/make_tensors.py; grep -E 'def planar_velocity_250hz\|def bin_velocity\|def apply_lag' Decoder/src/nd... |
| references | 09-04-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -E 'def firing_rate_stats\|def band_violations' Decoder/src/ndt1/qc.py; grep -F 'PLAUSIBLE_BAND' Decoder... |
| key-links | 09-04-PLAN.md | warning | Decoder/src/ndt1/sessions.py -> Decoder/src/ndt1/data.py: Pattern "except ValueError" not found in source or target |
| references | 09-05-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; Decoder/data/<id>.mat; Decoder/**/*.mat; /private/tmp/agent-501/-Users-d0nmega-Developer-Cortex/c7b2dc68-43... |
| key-links | 09-05-PLAN.md | warning | .planning/phases/09-.../09-ingest-evidence.md -> Decoder/manifests/indy_sessions.json: Source file not found |
| references | 09-06-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; uv run --project Decoder python Decoder/scripts/report_sessions.py; grep -nE 'except\s*:\|except Exception' D... |
| key-links | 09-06-PLAN.md | warning | .planning/phases/09-.../09-decoder-metrics.json -> Decoder/manifests/indy_sessions.json: Source file not found |
| references | 09-07-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; nlb_tools/make_tensors.py; .planning/phases/09-.../09-decoder-metrics.json; test -f Decoder/checkpoints/ndt1... |
| references | 09-08-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; grep -E 'def load_real_weights_if_present\|def checkpoint_sha256' Decoder/src/ndt1/real_checkpoint.py; grep -... |
| key-links | 09-08-PLAN.md | warning | .planning/phases/09-.../09-coreml-evidence.md -> Packages/CortexDecoder/.bench/latency_histogram.json: Source file not found |
| references | 09-09-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; ./Tools/scripts/X-policy.sh; python3 Tools/scripts/check_decoder_provenance.py Decoder/manifests/indy_sessio... |
| references | 09-10-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; .planning/phases/05-.../05-velocity-head-evidence.md; .planning/phases/07-*/07-bps-evidence.md; .planning/ph... |
| key-links | 09-10-PLAN.md | warning | .planning/phases/04-.../04-training-evidence.md -> .planning/phases/09-.../09-training-evidence.md: Source file not found |
| references | 09-11-PLAN.md | warning | $HOME/.agent/donny/workflows/execute-plan.md; $HOME/.agent/donny/templates/summary.md; Decoder/checkpoints/ndt1_real_vel_4bit.mlpackage; test -f .planning/phases/09-real-data-ingest-ndt1-retrain-... |
| key-links | 09-11-PLAN.md | warning | .planning/phases/09-.../09-HUMAN-UAT.md -> .planning/phases/09-.../09-coreml-evidence.md: Source file not found; .planning/phases/09-.../09-HUMAN-UAT.md -> Packages/CortexDecoder/Sources/CortexDeco... |
| verify-summary | 09-01-SUMMARY.md | warning | Missing files: ls Decoder/data/*.mat; Self-check section indicates failure |
| verify-summary | 09-02-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Missing files: Decoder/**/*.mat; Self-check section indicates failure |
| verify-summary | 09-03-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Self-check section indicates failure |
| verify-summary | 09-04-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Missing files: Decoder/data/indy_00000000_00.mat, ndt1/qc.py |
| verify-summary | 09-05-SUMMARY.md | warning | Missing files: git diff --stat Decoder/manifests/indy_sessions.json, uv run --project Decoder python Decoder/scripts/download_indy.py; Referenced commit hashes not found in git history; Self-check ... |
| verify-summary | 09-06-SUMMARY.md | error | requirements-completed missing from SUMMARY frontmatter (or shadowed by a body --- pair); Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 09-06b-SUMMARY.md | error | requirements-completed is empty; Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 09-06c-SUMMARY.md | error | requirements-completed is empty; Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 09-06d-SUMMARY.md | error | requirements-completed is empty; Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 09-07-SUMMARY.md | warning | Referenced commit hashes not found in git history |
| verify-summary | 09-08-SUMMARY.md | warning | Referenced commit hashes not found in git history; Self-check section indicates failure |
| verify-summary | 09-09-SUMMARY.md | warning | Referenced commit hashes not found in git history |
| verify-summary | 09-10-SUMMARY.md | warning | Referenced commit hashes not found in git history |
| verify-summary | 09-11-SUMMARY.md | error | requirements-completed is empty; Missing files: .planning/phases/09-.../09-HUMAN-UAT.md, .planning/phases/09-.../09-perf-report-ipad-m2.json; Referenced commit hashes not found in git history |

## Record Gate Audit Trail

| Run Date | Verbs | Errors | Warnings | Not yet | N/A | Verdict | Run By |
|----------|-------|--------|----------|---------|-----|---------|--------|
| 2026-09-03 | 13 | 3 | 3 | 1 | 1 | fail | donny-tools verify gate |
| 2026-09-03 | 13 | 3 | 3 | 1 | 1 | fail | donny-tools verify gate |
| 2026-09-03 | 13 | 3 | 3 | 0 | 1 | fail | donny-tools verify gate |
