# Plan 10-17 Task 3: the CI run for the audited push

The push authorized at Task 2, the workflow run it produced, and the reconciliation of the README's
CI-status sentence to that run's real result.

**Run on:** Apple M5 Pro, macOS 26.5, 2026-09-08T03:06Z UTC.
**Tools:** git 2.50.1 (Apple Git-155), gh 2.94.0.
**Working tree:** `/Users/d0nmega/Developer/Cortex`, branch `main`.

## What this artifact is, and the framing it corrects

Plan 10-17 was written 2026-09-05 and calls this artifact "the first hosted-runner execution in the
project's history". **That framing is stale and is not used here.** It was true when Plan 10-12 wrote
it and true when 10-17 was planned. It was overtaken on 2026-09-07 by a user-directed scrub-and-push
session outside this plan, which pushed the repository's history for the first time and triggered
the project's first 24 workflow runs. The pre-push audit (`10-prepush-audit.md`) established that
against hosted state before anything else happened here.

So the honest statement of what this plan contributed is three things, none of which is "CI ran for
the first time":

1. An audited push. `10-prepush-audit.md` applied the README gate's four forbidden patterns plus
   three token shapes and an absolute-home-path scan to all 556 tracked files and to all 525 commits
   then in the history, before the bytes moved. 21 PASS, 5 FLAGGED, every FLAGGED row
   dispositioned by the user at Task 2 before the push ran.
2. The first COMMITTED evidence record of the project's CI execution history. Twenty-four runs had
   happened and nothing in `.planning/` recorded them; the numbers below are that record.
3. A README sentence that cites a specific run rather than asserting a state.

## The push

```
$ git push -u origin main
To https://github.com/D0NMEGA/Cortex.git
   cd87d6f..710e729  main -> main
branch 'main' set up to track 'origin/main'.
exit=0

$ git rev-parse HEAD
710e7296fa082d547309abe213716413eb1d3be8
```

A **fast-forward of six commits**, not a first push. `origin/main` was `cd87d6ff` beforehand. The
six: `d400947` (render channel tests), `9861c28` (audit validation), `96168ba` (the pre-push audit),
`1539592` (the audit's self-scan), `6330329` (phase-10 tracking correction), and this plan's own
`710e729` (the Task-2 decision record), which is the pushed head.

```
$ gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'
25          # 24 before the push
$ git log origin/main..HEAD
            # empty: nothing local is unpushed
```

### Repository visibility: unchanged, and no command was issued

- **BEFORE (2026-09-08, pre-push):** `gh repo view D0NMEGA/Cortex --json isPrivate,visibility` -> `{"isPrivate":true,"visibility":"PRIVATE"}`.
- **AFTER (2026-09-08, post-push, same command):** `{"isPrivate":true,"visibility":"PRIVATE"}`.

**No `gh repo edit` was run at any point in this plan.** The user chose `private-push`, under which
"unchanged" means no visibility command is issued at all, not that one was issued and returned the
same value. The only visibility-related commands in this plan are the two read-only `gh repo view`
calls above. The repository is private; the push changed what CI had executed against, not who can
read the repository.

## The run

| field | value |
|---|---|
| run id | 34182390856 |
| url | https://github.com/D0NMEGA/Cortex/actions/runs/34182390856 |
| head sha | `710e7296fa082d547309abe213716413eb1d3be8` |
| event | `push` to `main` |
| created | 2026-09-08T03:06:58Z |
| updated | 2026-09-08T03:15:06Z |
| wall duration | 8m08s |
| **conclusion** | **success** |

```
$ gh run watch 34182390856 --exit-status
...
watch_exit=0
```

Both jobs green. Per-job wall time: `build-and-lint` 7m58s (2026-09-08T03:07:07Z to 03:15:05Z) on
image `macos-26-arm64`; `decoder-python` 47s (03:07:07Z to 03:07:54Z) on `macos-15`. The two jobs run
in parallel by design, so the run's 8m08s is the longer of the two plus queueing.

## Per-step results

Every step of both jobs, with its own conclusion. The `Post ...` entries are the actions' own
cache-save and cleanup steps; they are included rather than trimmed, because a failed cache save is
a real failure that a trimmed table would hide.

### `build-and-lint`

| # | step | conclusion | duration |
|---|---|---|---|
| 1 | Set up job | success | 2s |
| 2 | Checkout | success | 2s |
| 3 | Select Xcode 26.3 | success | 0s |
| 4 | Print versions | success | 5s |
| 5 | Verify Xcode is 26.x (Critical Finding | success | 0s |
| 6 | Install tooling | success | 35s |
| 7 | Lint toolchain version pin + self-test (D-18) | success | 2s |
| 8 | Cache Rust toolchain + cargo target (Phase 3) | success | 16s |
| 9 | Install Rust toolchain + cbindgen (Phase 3, THREAD-06) | success | 0s |
| 10 | Cache SwiftPM | success | 4s |
| 11 | Cache DerivedData | success | 7s |
| 12 | No-CocoaPods structural check (FOUND-04) | success | 0s |
| 13 | Build CortexRingFFI xcframework (Phase 3, D-R1) | success | 16s |
| 14 | Generate Xcode project from project.yml | success | 0s |
| 15 | Resolve SwiftPM (FOUND-04 clean-clone proof) | success | 15s |
| 16 | Per-package SwiftPM build smoke | success | 79s |
| 17 | Run CortexCore unit tests (Swift Testing) | success | 11s |
| 18 | Run CortexIPC tests (Transport + Session + Harness — correctness only, IPC-01..06) | success | 20s |
| 19 | Rust ring unit + 1M-frame stress (SC#3b/SC#3c) | success | 7s |
| 20 | Rust ring loom permutation (SC#3a) | success | 4s |
| 21 | cbindgen header drift (SC#4 defense, D-13) | success | 1s |
| 22 | Swift integration over the Rust C ABI (SC#4) | success | 7s |
| 23 | SwiftFormat (lint) | success | 1s |
| 24 | SwiftLint (strict) | success | 2s |
| 25 | Validate PrivacyInfo manifests (FOUND-03) | success | 0s |
| 26 | Hot-path policy (D-15, no-op in Phase 1) | success | 0s |
| 27 | Render policy gate (D-10 tier 1, RENDER-01/04/06/07/08) | success | 2s |
| 28 | Run CortexBCIHID tests (SYS-01/05 + SYS-03/04 round trip) | success | 6s |
| 29 | HID surface policy gate (SYS-01/05/06, D-06) | success | 2s |
| 30 | Notarization pipeline gate (DIST-01, D-06) | success | 0s |
| 31 | Match/TestFlight pipeline gate (DIST-02/03, D-06) | success | 2s |
| 32 | README credibility + no-leak gate (DIST-04, D-06, RD-10) | success | 2s |
| 33 | Repo-wide honesty sweep + self-test (RD-09/RD-10) | success | 11s |
| 34 | Info.plist required keys + self-test (SYS-01/05) | success | 0s |
| 35 | Verify iOS 120Hz plist key (RENDER-03, SC#3) | success | 1s |
| 36 | No SCM_RIGHTS / cmsg structural check (SC#2 — FD passing MUST be mach_msg, not socket control messages) | success | 0s |
| 37 | No _ANEClient private API (DEC-12 negative control) | success | 14s |
| 38 | Run CortexDecoder tests (DEC-07/09/10 Swift-side, correctness only) | success | 10s |
| 39 | Run CortexReFIT tests (REFIT-01/02/03 — constants + filter + S&M-2004 throughput) | success | 11s |
| 40 | Run CortexRender tests (RENDER-01/02/03 — integrator, velocity ring, webgrid params) | success | 15s |
| 41 | ReFIT BPS uplift + determinism guard (REFIT-03, D-10) | success | 4s |
| 42 | Webgrid BPS structural + determinism gate (PERF-01, D-06/D-13) | success | 5s |
| 43 | Run CortexDemo tests (SYS-06/PERF-04) | success | 20s |
| 44 | Seam B chain smoke on the synthetic fixture (RD-08) | success | 3s |
| 45 | Software-timed glass-to-glass bench smoke (PERF-04, M5 corroborating) | success | 4s |
| 46 | Build CortexMac scheme (unsigned smoke) | success | 44s |
| 47 | Build CortexiOS scheme (unsigned smoke, simulator) | success | 16s |
| 48 | Build CortexDaemon scheme (verify SPM library reachability per Critical Finding | success | 7s |
| 49 | Verify PrivacyInfo.xcprivacy is included in built .app bundles (Pitfall | success | 1s |
| 50 | Verify no app-sandbox in Mac entitlements (Critical Finding | success | 0s |
| 51 | Verify CortexDaemon bundle artifact exists | success | 0s |
| 52 | Fastlane lanes parse (ruby -c, blocking; DIST-02/03) | success | 0s |
| 53 | Bundler smoke (fastlane gem resolution readiness; non-blocking, no live lane) | success | 45s |
| 103 | Post Cache DerivedData | success | 6s |
| 104 | Post Cache SwiftPM | success | 6s |
| 105 | Post Cache Rust toolchain + cargo target (Phase 3) | success | 0s |
| 106 | Post Checkout | success | 0s |
| 107 | Complete job | success | 3s |

### `decoder-python`

| # | step | conclusion | duration |
|---|---|---|---|
| 1 | Set up job | success | 2s |
| 2 | Checkout | success | 3s |
| 3 | Set up uv (Decoder Python subsystem) | success | 1s |
| 4 | Sync Decoder env (the dev extra is REQUIRED -- see AGENTS.md) | success | 5s |
| 5 | Print Decoder toolchain versions | success | 14s |
| 6 | Ruff (no bare/blind except -- the BLE gate) | success | 0s |
| 7 | Decoder quick suite (no dataset, no training, no measured-number assertions) | success | 14s |
| 8 | Prove the quick suite needs no dataset or export artifacts | success | 1s |
| 9 | Decoder provenance policy gate + self-test (D-19) | success | 0s |
| 10 | Real-data provenance gate + self-test (D-09/D-21) | success | 2s |
| 19 | Post Set up uv (Decoder Python subsystem) | success | 0s |
| 20 | Post Checkout | success | 1s |
| 21 | Complete job | success | 1s |

## SwiftFormat and SwiftLint: local versus the runner

D-18 is about exactly these two gates, so they get their own comparison. Both are `brew install`ed
on the runner, which is unpinned, so `Tools/toolchain-versions.env` plus `toolchain-policy.sh` are
what make a local result and a runner result comparable at all.

| | pinned in `Tools/toolchain-versions.env` | runner reported | local (M5 Pro) reported |
|---|---|---|---|
| SwiftFormat | `0.63.0` | `0.63.0` | `0.63.0` |
| SwiftLint | `0.65.1` | `0.65.1` | `0.65.1` |

Runner, `Install tooling` step, verbatim:

```
swiftformat: 0.63.0  (pinned: 0.63.0)
swiftlint:   0.65.1      (pinned: 0.65.1)
```

Runner, `Lint toolchain version pin + self-test (D-18)` step, verbatim:

```
scanning toolchain pin: Tools/toolchain-versions.env
scanning workflow:      .github/workflows/ci.yml
  ok  [pin-present] SWIFTFORMAT_VERSION=0.63.0  (Tools/toolchain-versions.env)
  ok  [pin-present] SWIFTLINT_VERSION=0.65.1  (Tools/toolchain-versions.env)
  ok  [swiftformat] installed 0.63.0 == pinned 0.63.0
  ok  [swiftlint] installed 0.65.1 == pinned 0.65.1
```

### The verdicts

| gate | local, immediately before the push | runner, run 34182390856 |
|---|---|---|
| `swiftformat --lint .` | `0/121 files require formatting, 19 files skipped.` exit 0 | `0/121 files require formatting, 17 files skipped.` exit 0 |
| `swiftlint --strict` | `Found 0 violations, 0 serious in 119 files.` exit 0 | `Found 0 violations, 0 serious in 119 files.` exit 0 |

SwiftLint matches exactly: same file count, same violation count, same verdict.

SwiftFormat matches on everything that decides the gate (121 files scanned, 0 requiring formatting)
and differs by 2 in the SKIPPED count, which counts files inside the `--exclude` paths rather than
files scanned. Those paths are generated build output (`.build` directories, `DerivedData`,
`vendor`, the generated `Cortex.xcodeproj`), so which of them exist at lint time differs between a
long-lived working tree and a fresh checkout partway through a job. **I did not attribute the 2-file
delta to specific files**: the excluded set is untracked generated output, an exact attribution would
require reproducing the runner's filesystem at 03:11:00Z, and the delta cannot move the verdict,
since a skipped file is by definition one the gate did not judge. It is recorded rather than rounded
away because "0/121, 19 skipped" and "0/121, 17 skipped" are not the same string, and the point of
this comparison is that a local pass is evidence rather than proof.

That was Plan 10-16's own statement of its limit, and it held: the local pass predicted the runner
pass on both gates. The prediction being correct does not retroactively make the local run a proof.

## Triage

**No triage attempts were needed. Zero of the three permitted attempts were used.** No step in
either job failed, so there was nothing to classify as an environment difference or as a real
defect, nothing to fix, nothing to re-push, and nothing to add to the Deferred Items table in
`.planning/STATE.md`.

Recorded explicitly rather than omitted: an absent triage section could equally mean "no failures"
or "failures not looked at", and those are different claims.

## The execution history this run joins

Twenty-four runs preceded it. All of them are from 2026-09-07, none from the ten phases before that.

```
$ gh api 'repos/D0NMEGA/Cortex/actions/runs?per_page=100' --jq '.workflow_runs[] | .conclusion' \
    | sort | uniq -c        # the 24 BEFORE this push
   6 cancelled
   6 failure
  12 success
```

**The first run in the project's history failed.** `34154026468`, 2026-09-07T19:02:29Z, on
`879fbe14`, which was commit 497 of the 529 now on `main`. Both its jobs failed.

The six oldest runs all failed, and none of the failures was a runner quirk. Each was a defect that
had shipped green locally through the phases that introduced it, because CI had never executed:

| run | sha | failing step |
|---|---|---|
| 34154026468 | `879fbe14` | `Lint toolchain version pin + self-test (D-18)` (build-and-lint) and `Ruff (no bare/blind except -- the BLE gate)` (decoder-python) |
| 34154374914 | `c75a401e` | `Resolve SwiftPM (FOUND-04 clean-clone proof)` |
| 34154714318 | `68a87fe5` | `Run CortexIPC tests (Transport + Session + Harness)` |
| 34155202143 | `1613e326` | `No _ANEClient private API (DEC-12 negative control)` |
| 34156111224 | `3d0a87c8` | `Build CortexMac scheme (unsigned smoke)` |
| 34156685759 | `b3aca9e2` | `Build CortexiOS scheme (unsigned smoke, simulator)` |

Three of those are documented in the tree they broke, and the documentation is worth quoting because
it is where the honest version of "CI is green" lives:

- The toolchain pin failed because Homebrew shipped SwiftFormat 0.63.0 and SwiftLint 0.65.1 while
  the pin named 0.61.1 and 0.63.3. That is exactly the drift the gate exists to catch, and it caught
  it on its first real execution. `Tools/toolchain-versions.env` records the re-measure-then-pin fix.
- `Resolve SwiftPM` ran `swift package resolve` from the repo root, where there is no
  `Package.swift`. As `ci.yml` now says in the step's own comment, it "could never have passed: it
  fails ... on any machine, including locally. It went unnoticed from Phase 1 to 2026-09-07 because
  CI had never executed."
- The `_ANEClient` negative control had been broken since Phase 8's `9b3013c`, when
  `readme-policy.sh` began naming the symbol as a rejected alternative and thereby matching the
  control's own grep. `ci.yml`: "Two phases shipped over a broken negative control because CI had
  never executed."

The six `cancelled` entries are the workflow's own `cancel-in-progress` concurrency group
superseding a run when the next push arrived, not failures. The seven runs before this one are
consecutive successes; `34173147693` on `cd87d6ff` concluded `success` at 2026-09-08T00:23:20Z, and
that was the state `origin/main` was in when this plan's push landed.

## What this establishes, and what it does not

**Establishes.**

- The twelve policy gates and their `--self-test` negative controls execute on hosted runners and
  pass on the current head of `main`, at a specific citable run.
- The SwiftFormat and SwiftLint remediation of Plans 10-15 and 10-16 holds on a machine that is not
  the machine it was measured on, under the same pinned versions, which is what the pin was added
  for.
- The Decoder Python tier runs its quick suite, its two provenance gates and their self-tests with
  an empty `Decoder/data/` and an empty `Decoder/exports/`, proving the D-21 tier split is real
  rather than declared.
- The full 25-run execution history, failures included, is now committed rather than living only in
  the Actions tab.

**Does not establish.**

- **No device measurement.** The gates in `10-HUMAN-UAT.md` remain deferred. Nothing here touches
  the iPad-M4 ANE placement capture, the on-device p99, or any latency figure. A green run on a
  hosted macOS runner is not a measurement on an M4.
- **No real-data result.** The D-21 tier split deliberately keeps CI off the CC-BY Indy dataset, so
  every dataset-gated number in this repo remains human-run runbook evidence produced from the
  committed checksum manifest. CI proves those artifacts are structurally well-formed and carry
  provenance; it does not reproduce them.
- **No performance claim.** Every timing gate in the workflow is a correctness or smoke check by
  design. The renderer's GPU budget, the IPC round trip and the decoder p99 are all measured
  elsewhere, on named hardware, and CI asserts none of their values.
- **Not a proof that the gates are correct**, only that they run and that their negative controls
  still bite. A gate can be green and still be asserting the wrong thing; that is what the
  `--self-test` corpora and the review passes are for.
- **Nothing about visibility.** The repository is private and stayed private. Nobody outside the
  account can verify the run cited in the README today.

## Local gate roll-call after the README edit

```
$ ./Tools/scripts/readme-policy.sh                 -> exit 0
$ ./Tools/scripts/readme-policy.sh --self-test     -> exit 0
$ ./Tools/scripts/honesty-sweep.sh                 -> exit 0
$ ./Tools/scripts/honesty-sweep.sh --self-test     -> exit 0
$ ./Tools/scripts/toolchain-policy.sh              -> exit 0
$ ./Tools/scripts/toolchain-policy.sh --self-test  -> exit 0
```

## The README reconciliation

Plan 10-17 Task 3d assumed a `CI-STATUS-CLAIM` HTML comment was already in the README, marking a
sentence that said the workflow had not yet executed, so that the task would be an edit. It was not
there. `f447234` (Plan 10-12) added it; `30217d4` ("docs: rewrite README as current state") removed
it along with the sentence it marked, so `grep -cF 'CI-STATUS-CLAIM' README.md` returned 0. The hook
was therefore **re-added**, not edited, in the `## Verification` section above the twelve-gates
paragraph, with a sentence that cites run 34182390856 by id and URL and states the failure history
rather than only the green result.

`grep -cF 'CI-STATUS-CLAIM' README.md` now returns 1. `grep -cF 'total_count: 0' README.md` returns
0; that pre-push wording was already gone before this plan.

The sentence near the rejected-alternatives table ("Other rejected options, each with a CI gate
preventing regression: the Apple-private `_ANEClient` API ...") was checked and **left unchanged**.
It is a present-tense claim that those gates exist and hold, which run 34182390856 backs: steps 37,
12 and 30 are the three gates it names and all three are green. It makes no claim about execution
history, so it needs no run citation. Note for a future reader that the `_ANEClient` gate was in fact
broken from Phase 8 until 2026-09-07; that history is above and in `ci.yml`'s own step comment, not
in the README sentence, which describes the current state.

## Self-scan

This file quotes `/Users/d0nmega/Developer/Cortex` once in its run header, matching the FLAG-04
pattern the user dispositioned as accept-as-is at Task 2. It introduces no PEM header, no
`MATCH_PASSWORD` assignment, no email address, no ASC issuer UUID and no cloud-token shape. It names
no path that is not already in `origin/main`.
