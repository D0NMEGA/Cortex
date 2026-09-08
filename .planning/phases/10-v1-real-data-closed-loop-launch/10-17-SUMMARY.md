---
status: PARTIAL
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 17
subsystem: infra
tags: [ci, github-actions, git, secret-scanning, swiftlint, swiftformat, evidence]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: "Plans 10-15 and 10-16 cleared swiftformat --lint and swiftlint --strict locally under the pins in Tools/toolchain-versions.env; Plan 10-13 rewrote readme-policy.sh; Plan 10-12 wrote the CI-status claim this plan reconciles"
provides:
  - "An audited push: every tracked file and every historical object scanned for credentials and licence-encumbered payloads before the bytes moved"
  - "The user's recorded answer on two separate questions, push and visibility, with a disposition for each of the five FLAGGED audit rows"
  - "The first committed evidence record of the project's CI execution history, 26 runs including the 6 that failed"
  - "A README CI-status sentence that cites run 34182390856 by id and URL instead of asserting a state"
affects: [phase-10 validation, phase-10 completion, any future claim about what CI has proven]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A CI claim in prose names the run id, the URL and the commit, never 'the current head'"
    - "A local gate result is compared to the runner result under a version pin, and a delta is recorded rather than rounded away"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-first-ci-run-evidence.md
  modified:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-prepush-audit.md
    - README.md

key-decisions:
  - "private-push: push, leave visibility unchanged. No gh repo edit was run at all."
  - "All five FLAGGED audit rows accepted as-is, none fixed, each with a recorded reason"
  - "The plan's 'first hosted-runner execution in the project's history' framing was dropped as stale; CI first ran 2026-09-07, outside this plan"
  - "The README claim is pinned to commit 710e729 rather than to the head of main, so it survives the branch advancing"

patterns-established:
  - "Two irreversibilities are two decisions: a push and a visibility change are never settled by one answer"
  - "A record of a CI run cannot contain the result of the run its own commit triggers; state where the follow-on run is recorded instead of pretending the regress does not exist"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: [RD-09]

# Metrics
duration: 98min
completed: 2026-09-08
---

# Phase 10 Plan 17: push, first CI evidence, README reconciliation Summary

**`main` pushed to a private origin after a 26-check pre-push audit; CI run 34182390856 green across both jobs on commit `710e729`; the README's CI claim rewritten to cite that run and the six failures that preceded it.**

## Performance

- **Duration:** 98 min (Task 1 audit 2026-09-08T01:51:47Z through final push 2026-09-08T03:29Z)
- **Started:** 2026-09-08T01:51:47Z
- **Completed:** 2026-09-08T03:29:23Z
- **Tasks:** 3 of 3
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- Audited 556 tracked files and 525 commits against the README gate's four forbidden patterns, three
  cloud-token shapes and an absolute-home-path scan added beyond the plan, before anything left the
  machine. 21 PASS, 5 FLAGGED, no credential and no dataset byte anywhere.
- Recorded the user's answer as two separate answers. `private-push` was chosen; **`gh repo edit`
  was never run**, and `gh repo view --json isPrivate` returns `true` both before and after.
- Pushed six commits as a fast-forward `cd87d6f..710e729`, then two more, with `git log
  origin/main..HEAD` empty at the end.
- Watched run **34182390856** to completion: `success`, 8m08s, `build-and-lint` green across 58
  steps on `macos-26-arm64`, `decoder-python` green across 13 steps on `macos-15`. Zero of the three
  permitted triage attempts were used because no step failed.
- Watched the follow-on run **34183202020** for commit `7089692` to completion: `success`, 7m21s,
  both jobs green, no failing step.
- Wrote the first committed record of the project's CI history, including that the first run ever
  executed **failed** and that the six oldest runs all failed on real defects that ten phases of
  green local builds had never surfaced.

## Task Commits

1. **Task 1: the pre-push audit** - `96168ba`, `1539592` (docs) [executed by the prior agent]
2. **Task 2: authorize the push and set visibility** - `710e729` (docs)
3. **Task 3: push, watch the run, reconcile the README** - `ac7a3a5`, `7089692` (docs)

## Files Created/Modified

- `.planning/phases/10-v1-real-data-closed-loop-launch/10-first-ci-run-evidence.md` (created, 376
  lines) - the pushed sha, run id, URL, conclusion and duration; a per-step table for all 58 and 13
  steps of both jobs; the local-versus-runner comparison for `swiftformat --lint .` and `swiftlint
  --strict` against the pins; the triage section recording that none was needed; the 24-run history
  that preceded the push; and an explicit account of what a green run does and does not establish.
- `.planning/phases/10-v1-real-data-closed-loop-launch/10-prepush-audit.md` (modified) - the
  Decision section: date, `private-push` verbatim, visibility before and after on two separate
  lines, one disposition per FLAGGED row, and a self-scan of the section's own added matches.
- `README.md` (modified) - the `CI-STATUS-CLAIM` hook re-added in `## Verification` with a sentence
  citing run 34182390856 and stating the failure history.

## Decisions Made

- **`private-push`.** The user was shown the verdict table and all five FLAGGED rows and chose to
  push while leaving visibility untouched. Under that option no visibility command is issued at all,
  which is stronger than issuing one that happens to be a no-op, and the audit says so explicitly.
- **All five flags accepted, none fixed.** FLAG-01 the PEM placeholder, FLAG-02 the 13 email-shaped
  strings, FLAG-03 the `@utexas` domain inside a grep pattern, FLAG-04 the 68 home paths under
  `.planning/`, FLAG-05 the pre-existing history rewrite. Each has a recorded reason; none was
  silently kept.
- **The plan's stale framing was dropped rather than repeated.** Plan 10-17 says this artifact is
  "the first hosted-runner execution in the project's history". It is not. The evidence artifact
  says what actually happened and names this plan's three real contributions instead.
- **The README claim names a commit, not the head.** A head-relative sentence stops being true the
  moment this plan's own documentation commits land, which they did, twice.

## Deviations from Plan

### 1. [Rule 3 - Blocking] The plan's Task-3 premise was stale in five ways

- **Found during:** Task 3, and already documented by Task 1's audit.
- **Issue:** Task 3 assumes `total_count: 0`, a repository that has never been pushed, a first push
  rather than a fast-forward, and an existing `CI-STATUS-CLAIM` sentence to edit. All four were
  false. `origin/main` was `cd87d6ff`, 24 runs had executed, and `grep -cF 'CI-STATUS-CLAIM'
  README.md` returned 0 because `30217d4` had removed the hook along with the sentence it marked.
- **Fix:** Executed against live state as the orchestrator directed. The hook was **re-added**, not
  edited. The evidence artifact opens by naming the stale framing and correcting it rather than
  quietly writing around it.
- **Files modified:** `README.md`, `10-first-ci-run-evidence.md`
- **Verification:** `grep -cF 'CI-STATUS-CLAIM' README.md` returns 1; `readme-policy.sh` and its
  self-test exit 0.
- **Committed in:** `ac7a3a5`, `7089692`

### 2. [Rule 1 - Bug] The README's CI sentence was tied to a moving head

- **Found during:** Task 3, immediately after committing `ac7a3a5`.
- **Issue:** The sentence read "the run covering the current head of `main`", which `ac7a3a5` itself
  falsified: that commit advanced the head past `710e729`, so the cited run no longer covered it.
  Shipping it would have made the README wrong within one commit of being written.
- **Fix:** Pinned the sentence to commit `710e729`. Added a "Follow-on runs" section to the evidence
  artifact stating where each subsequent run is recorded and why the regress terminates by
  construction.
- **Files modified:** `README.md`, `10-first-ci-run-evidence.md`
- **Verification:** `readme-policy.sh`, its self-test, and `honesty-sweep.sh` all exit 0.
- **Committed in:** `7089692`

**Total deviations:** 2 auto-fixed (1 Rule 3, 1 Rule 1).
**Impact on plan:** Both were required for the plan's own output to be true. No scope creep: nothing
outside `README.md` and the two phase artifacts was touched.

## Acceptance criteria not met, and why

Reported here rather than folded into the accomplishments, because a criterion recorded as met when
it is not is exactly the defect this milestone exists to remove.

### The plan's PEM-header criterion is not met as literally written

Task 1's acceptance criterion says "No tracked file contains a PEM private-key header", and the
plan's own automated verify line is
`test -z "$(git ls-files -z | xargs -0 grep -lE -- '-----BEGIN[ A-Z]*PRIVATE KEY-----' 2>/dev/null)"`.
That command **exits 1** today, and did before this plan started. Three tracked files match:

- `fastlane/asc_api_key.json.example` - the template Plan 08-04 committed on purpose, whose payload
  is the literal string `REPLACE_WITH_P8_CONTENTS` and whose real counterpart is gitignored
- `.planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/08-04-PLAN.md` - the plan that
  specified that template
- `10-prepush-audit.md` - the audit, which quotes the finding

The criterion is recorded as **MIS-SPECIFIED**: it cannot pass against a deliberately committed
placeholder template, and it was unsatisfiable from the day `b624c2f` landed in June. The user was
shown this as FLAG-01 and chose to accept the classification (placeholder, not key material) rather
than reword the `.example`. **No private key material is present**, but the criterion as written is
not met and this summary does not claim otherwise.

### The plan's "No history rewrite occurred" success criterion cannot be asserted as a blanket statement

A full-history rewrite of all 525 commits happened on **2026-09-07**, user-directed, before this plan
ran and outside its scope, and it was already pushed. The evidence is direct: author and committer
are uniform across every commit, and the agent-instructions file reads as having been named
`AGENTS.md` since 2026-04-28 with no prior name anywhere in history.

What **is** true, and is the narrower claim this summary makes: **this plan performed no rewrite.**
`git reflog --date=iso` shows only `commit:` entries after the audit baseline, no rebase, no amend,
no `filter-repo` and no force push. The user confirmed at Task 2 that the criterion is read as "THIS
PLAN performs no rewrite" and that the standing prohibition stands in full.

## Issues Encountered

- **The plan's premise had been overtaken by a session outside it.** Handled by executing against
  live state and recording the delta in both artifacts rather than by re-planning. Resolved.
- **The CI-run regress.** Committing a record of a run triggers a run that the record cannot
  contain. Terminated deliberately: run 34182390856 is recorded in the evidence artifact, run
  34183202020 is recorded here, and the run triggered by this summary's own commit is reported by
  the executor to the orchestrator. Each is stated to cover only its own commit.
- **A 2-file delta in SwiftFormat's skipped count**, 19 locally against 17 on the runner, on an
  otherwise identical verdict (0 of 121 files requiring formatting on both). Recorded, not rounded
  away, and deliberately **not** attributed to specific files: the excluded set is untracked
  generated build output, and an exact attribution would need the runner's filesystem reproduced at
  03:11:00Z. It cannot move the verdict, since a skipped file is one the gate did not judge.

## User Setup Required

None. The push and the run needed no new credential, no new service and no configuration. `gh` was
already authenticated.

## Next Phase Readiness

**Ready.** `main` is on `origin`, nothing local is unpushed, the working tree is clean, and both the
twelve `build-and-lint` policy gates and the `decoder-python` tier execute green on hosted runners
at a citable run id.

**Open, and not closed by this plan:**

- The device gates in `10-HUMAN-UAT.md` remain deferred. A green hosted-runner run is not an
  iPad-M4 measurement, and nothing here touches ANE placement, on-device p99 or any latency figure.
- Dataset-gated evidence remains human-run runbook evidence. The D-21 tier split keeps CI off the
  CC-BY Indy dataset by design, so CI proves those artifacts are well-formed and carry provenance,
  never that it reproduced them.
- The repository is **private**. Nobody outside the account can verify the run the README now cites.
  Making it public is a decision the user has not made and this plan did not touch.
- Phase tracking is left to the orchestrator by instruction. `RD-09` is still unchecked in
  `.planning/REQUIREMENTS.md` with a `TBD` traceability row, and `.planning/STATE.md` and
  `.planning/ROADMAP.md` were not edited by this plan.

## Threat Flags

None. This plan introduced no network endpoint, no auth path, no file-access pattern and no schema
change. The one boundary it crossed, the local machine to GitHub, is `T-10-17-01` through
`T-10-17-09` in the plan's own register, and each disposition was executed: the audit ran before the
push, the checkpoint blocked until every FLAGGED row had an answer, `gh repo edit` was never run,
the README sentence was written after the run and matches its conclusion, and the reflog shows no
rewrite.

## Self-Check: PASSED

Files claimed created or modified, verified present:

- FOUND: `.planning/phases/10-v1-real-data-closed-loop-launch/10-first-ci-run-evidence.md` (376 lines)
- FOUND: `.planning/phases/10-v1-real-data-closed-loop-launch/10-prepush-audit.md` (574 lines)
- FOUND: `README.md` (288 lines)

Commits claimed, verified in `git log`:

- FOUND: `96168ba` docs(10-17): audit what is already on GitHub, and what the next push adds
- FOUND: `1539592` docs(10-17): record that the audit commit changed the payload it describes
- FOUND: `710e729` docs(10-17): record the private-push decision and all five flag dispositions
- FOUND: `ac7a3a5` docs(10-17): record the CI run for the audited push and cite it in the README
- FOUND: `7089692` docs(10-17): pin the README's CI claim to a commit, not the head

External facts, verified against GitHub rather than asserted:

- FOUND: run `34182390856`, conclusion `success`, commit `710e7296`
- FOUND: run `34183202020`, conclusion `success`, commit `7089692`
- FOUND: `gh repo view D0NMEGA/Cortex --json isPrivate` returns `true` after the push
- FOUND: `git log origin/main..HEAD` empty, `git status --short` empty
- FOUND: `readme-policy.sh`, `honesty-sweep.sh`, `toolchain-policy.sh` and all three `--self-test`
  runs exit 0

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-08*
