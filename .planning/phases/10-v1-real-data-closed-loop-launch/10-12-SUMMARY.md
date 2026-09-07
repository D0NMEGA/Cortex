---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: "12"
subsystem: docs
tags: [readme, credibility, bps, banners, evidence, agents-md, project-md]

requires:
  - phase: 10-v1-real-data-closed-loop-launch/10-10
    provides: sc2_disposition not_met in 10-replay.json; 4-arm ablation numbers committed
  - phase: 10-v1-real-data-closed-loop-launch/10-11
    provides: 08-bps-evidence.md amendment block (key rename + nonComparabilityDisclosure)

provides:
  - README.md rewritten as v1 credibility artifact with decode-attributable 0 BPS headline
  - AGENTS.md ## Project section updated (photodiode core value retired)
  - PROJECT.md Key Decisions updated with Phase-10 outcomes (D-14, D-17, SC#2 not_met)
  - Phase-10 superseded banners on five evidence files (04-training, 04-palettization, 05-placement, 07-bps, 08-bps)
  - All 6 policy gates green: readme-policy, bps-policy, render-policy, hid-surface-policy, decoder-policy, refit-real-policy

affects:
  - 10-13: readme-policy.sh rewrite -- reads the current README and the CI-STATUS-CLAIM comment
  - 10-14: honesty-sweep.sh -- PERF-02 REQUIREMENTS.md wording flagged here for its path
  - 10-17: first push -- reads the CI-STATUS-CLAIM HTML comment and the CI-never-executed disclosure

tech-stack:
  added: []
  patterns:
    - "Evidence-banner discipline: superseded artifacts get forward-pointing banners; measured numbers never edited"
    - "D-14 provenance triple: session id + checkpoint sha256 prefix + open-loop-replay disclosure label in every claim"
    - "Headline BPS = decode-attributable arm only (raw/kalman_only); target-determined arms labeled and never promoted to headline"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-12-SUMMARY.md
  modified:
    - README.md
    - AGENTS.md
    - .planning/PROJECT.md
    - .planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md
    - .planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-palettization-evidence.md
    - .planning/phases/05-ndt1-coreml-deployment-with-ane-residency-verified/05-placement-evidence.md
    - .planning/phases/07-refit-kalman-closed-loop-recalibration/07-bps-evidence.md
    - .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-bps-evidence.md

key-decisions:
  - "Hand-edited AGENTS.md (not regenerated): only Core Value line changed; Conventions section byte-identical"
  - "ROADMAP.md edits skipped: orchestrator owns that file; post-commit hook reverts uncommitted .planning edits"
  - "PERF-02 REQUIREMENTS.md wording (verified vs retrieved) is out of scope here; flagged for Plan 10-14"

requirements-completed: [RD-09, RD-10]

duration: ~35 min
completed: 2026-09-07
---

# Phase 10 Plan 12: README Republish and v1 Credibility Labels Summary

**README rewritten as v1 credibility artifact with decode-attributable 0.000000 BPS headline, D-14 provenance triple, and Seam B in_process qualifier; AGENTS.md and PROJECT.md updated for real-data core value; five historical evidence files receive Phase-10 superseded banners.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-09-07
- **Tasks:** 3 / 3
- **Files modified:** 8 (README, AGENTS.md, PROJECT.md, 5 evidence files)

## Accomplishments

- README is now the v1 credibility artifact: headline BPS = 0.000000 (raw/kalman_only, decode-attributable, N=900 and N=64); 0.487984/70 hits labeled "target-determined by construction" with explicit "must never appear as one"; 24.7 ms moved to Future-work section with "retired spec target, never measured"; 239/239 ANE-eligible; Seam A 8831017 ns and Seam B 136167 ns (in_process qualifier); all 6 HUMAN-UAT gates in honest-gates table; CI-STATUS-CLAIM comment for Plan 10-17; nonComparabilityDisclosure verbatim; all 6 policy gates exit 0 including self-tests.
- AGENTS.md Core Value updated to the real-data statement (hand-edit; Conventions section byte-identical per git diff).
- PROJECT.md Key Decisions extended with D-14 provenance triple, D-17 8.5 retention rationale, SC#2 not_met disposition, and Phase-10 outcome numbers linked to their committed artifacts.
- Five evidence files carry forward-pointing banners to Phase-10 artifacts; no measured number was edited.

## Task Commits

1. **Task 1: Rewrite README as v1 credibility artifact** - `f447234` (docs)
2. **Task 2: Update AGENTS.md and PROJECT.md** - `c3fb403` (docs)
3. **Task 3: Five superseded banners** - `f6c82b3` (docs)

## Test Suite Results (verbatim)

**Decoder (Python, `not slow` marker):**
```
288 passed, 1 skipped, 10 deselected in 3.87s
SKIPPED [1] Decoder/tests/test_data.py:157: no loadable real .mat present (dataset is gitignored)
```
The skip is expected (dataset is gitignored; download_indy.py materializes it). 288 + 1 skip = 289 total non-deselected tests. Gate passed.

**CortexDemo:**
```
Test run with 44 tests in 5 suites passed after 0.044 seconds.
```

**CortexReFIT:**
```
Test run with 32 tests in 5 suites passed after 0.001 seconds.
```

**CortexRender:**
```
Test run with 19 tests in 4 suites passed after 0.014 seconds.
```

## Policy Gate Results (verbatim)

```
readme-policy      gate=0 self-test=0
bps-policy         gate=0 self-test=0
render-policy      gate=0 self-test=0
hid-surface-policy gate=0 self-test=0
decoder-policy     gate=0 self-test=0
refit-real-policy  gate=0 self-test=0
```

All six gates and all six self-tests exit 0. No new policy regressions.

## Entitlements / project.yml Guard

`git diff --stat -- Apps/CortexMac/Cortex.entitlements Apps/CortexiOS/Cortex.entitlements Apps/CortexDaemon/Cortex.entitlements project.yml` returned empty. No entitlement or project spec files were touched.

## Deviations from Plan

### Blocked task component (user override)

**1. [User override] ROADMAP.md edits skipped**
- **Found during:** Task 2
- **Issue:** Plan 10-12 Task 2c calls for three edits to `.planning/ROADMAP.md` (Phase-10 progress row, LAT-0N confirmation, v1 outcome in Milestones block). The user's explicit pre-execution directive states: "Do NOT edit `.planning/ROADMAP.md` or `.planning/STATE.md` -- the orchestrator writes those, and a post-commit hook reverts uncommitted `.planning` edits."
- **Decision:** Skipped entirely. The plan's acceptance criteria for ROADMAP.md will be met by the orchestrator's state-advance step.
- **Impact:** The seven ROADMAP.md acceptance checks in Task 2's `<verify>` block were not run. Plans 10-13 through 10-17 should be aware that the ROADMAP updates for Phase-10 completion land via the state-advance path, not via this plan.

### Auto-corrected wrong path (Rule 3)

**2. [Rule 3 - Blocking] Wrong Phase 5 directory name in plan**
- **Found during:** Task 3 (superseded banners)
- **Issue:** The plan references `.planning/phases/05-ndt1-coreml-deployment-ane-eligible-sub-2ms-verified/05-placement-evidence.md` but the actual directory is `05-ndt1-coreml-deployment-with-ane-residency-verified/`.
- **Fix:** Used the correct path. No file was created at the wrong path.
- **Files modified:** `05-ndt1-coreml-deployment-with-ane-residency-verified/05-placement-evidence.md`
- **Committed in:** `f6c82b3` (Task 3 commit)

### AGENTS.md management choice

**3. [Rule 2 - deliberate] Hand-edited AGENTS.md rather than regenerating**
- The `## Project` section is auto-managed tooling output (GSD markers present). The plan says to decide and state the choice. Decision: hand-edit, because regeneration would pull in unrelated churn from all sections. `git diff AGENTS.md` confirms only the Core Value line changed; the Conventions section (`## Conventions` through `<!-- GSD:conventions-end -->`) is byte-identical.

## PERF-02 Handling

`.planning/REQUIREMENTS.md` line 125 reads:
```
- [ ] **PERF-02**: Document path toward Neuralink P1 verified peak (8.5 BPS) -- what gaps remain
```

The word "verified" carries authority the 8.5 figure does not have (per Plan 10-11 threat T-10-11-09 and D-17's "not independently sourceable" qualifier). However, `REQUIREMENTS.md` is not in Plan 10-12's `<files>` list (which covers `AGENTS.md, .planning/PROJECT.md, .planning/ROADMAP.md`), and 10-11's acceptance grep also missed it (its path list covered `docs/ .planning/PROJECT.md .planning/ROADMAP.md Packages/CortexReFIT/Sources/` not `REQUIREMENTS.md`). This is an out-of-scope discovery.

**Decision:** Not fixed here. Flagged for Plan 10-14, whose `honesty-sweep.sh` already reads `.planning/REQUIREMENTS.md` for the LAT-0N preservation check and is the right place to catch and fix this wording.

See `.planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md` (appended below).

## Notes for Plans 10-13 Through 10-17

- **10-13** (readme-policy.sh rewrite): The current README satisfies the existing policy gate; the `<!-- CI-STATUS-CLAIM -->` HTML comment at README line 37 is the hook for 10-17. The README already uses "retrieved" language for 8.5 and "over 10 BPS" for the current Neuralink public statement.
- **10-14** (honesty-sweep.sh): `REQUIREMENTS.md` line 125 uses "verified peak" for 8.5 -- fix to "retrieved / not independently sourceable" consistent with D-17 and README wording.
- **10-17** (first push): CI-STATUS-CLAIM comment is present in README.md at the architectural commitments section intro paragraph. The current disclosure reads "As of 2026-09-07 the workflow has not yet executed on a hosted runner. That is verified against GitHub, not inferred: `gh api repos/D0NMEGA/Cortex/actions/runs` returns `total_count: 0`..." After the first successful push and runner execution, update this sentence and remove the HTML comment.

## Known Stubs

None. All numbers are transcribed from committed artifacts (`10-refit-real.json`, `10-replay.json`, `10-ceiling.json`, `09-decoder-metrics.json`). No placeholder values flow to any claim.

## Threat Flags

None. All changes are documentation-only. No new network endpoints, auth paths, file access patterns, or schema changes were introduced.

## Self-Check: PASSED

Verified:
- `README.md` exists at worktree root -- FOUND
- `AGENTS.md` contains `RETIRED SPEC TARGET` -- FOUND (1 match)
- `AGENTS.md` Conventions section byte-identical to pre-edit -- CONFIRMED (git diff shows only Core Value line changed)
- `05-placement-evidence.md` at correct path `05-ndt1-coreml-deployment-with-ane-residency-verified/` -- FOUND
- `07-bps-evidence.md` contains new banner -- FOUND
- `08-bps-evidence.md` contains new banner above amendment block -- FOUND
- Commits `f447234`, `c3fb403`, `f6c82b3` -- all present in `git log`
- All 6 policy gates exit 0
- All 4 test suites: 288+1skip/44/32/19 all passed
- Entitlements and project.yml untouched
