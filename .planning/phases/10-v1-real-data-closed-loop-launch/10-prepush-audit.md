# Plan 10-17 Task 1: pre-push audit

The secret, history and payload audit that Task 2's checkpoint gates on. Every command below was
run and its real output recorded; nothing is summarised into the word "clean" without the evidence
beneath it.

**Run on:** Apple M5 Pro, macOS 26.5, 2026-09-08T01:51:47Z UTC.
**Tools:** git 2.50.1 (Apple Git-155), gh 2.94.0.
**Working tree:** `/Users/d0nmega/Developer/Cortex`, branch `main`.

## The audit is partly retrospective, and the plan's premise is stale

Plan 10-17 was written 2026-09-05. Its `<interfaces>` block asserts that the repository has never
been pushed, that `gh api .../actions/runs` returns `total_count: 0`, and that `gh repo view`
returns an empty `defaultBranchRef`. **All three were true when Plan 10-12 wrote them and were
overtaken by a user-directed scrub-and-push session on 2026-09-07, outside this plan.** The
corrections below are the live state, verified by the commands shown, and they govern.

| the plan says | live state, 2026-09-08 | evidence |
|---|---|---|
| never pushed | pushed; `origin/main` = `cd87d6ff` | `git rev-parse origin/main` |
| `total_count: 0` | **24** workflow runs | `gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'` -> `24` |
| empty `defaultBranchRef` | `{"name":"main"}` | `gh repo view --json defaultBranchRef` |
| `git branch -a` shows `main` only | `remotes/origin/main` exists | `git branch -a` |
| Matchfile uses a `file:///Users/donmega/...` git_url | swapped to an `https://` private-repo URL in Phase 8 (`b624c2f`) | `cat fastlane/Matchfile` |
| Appfile keeps every identity field commented out | `app_identifier` is uncommented; the three ENV-read fields are live | `cat fastlane/Appfile` |
| the README carries a `CI-STATUS-CLAIM` hook | the hook is **gone**, removed by `30217d4` | `grep -cF 'CI-STATUS-CLAIM' README.md` -> `0` |

So this audit is a live gate for **two unpushed commits** and a **retrospective disclosure review**
for the 523 commits already on GitHub. Every finding below is split accordingly, because for
already-pushed content a disposition can no longer prevent disclosure, only decide what to do next.

**The repository is PRIVATE.** `gh repo view D0NMEGA/Cortex --json isPrivate,visibility` returns
`{"isPrivate":true,"visibility":"PRIVATE"}`. Nothing here is world-readable today. That is the
second, still-unmade decision at Task 2.

### Repository visibility

- **BEFORE (verified 2026-09-08):** `isPrivate: true`, `visibility: PRIVATE`.
- **AFTER:** not yet determined - Task 2 has not been answered and no push or `gh repo edit` has run.

## What the push would actually add

```
$ git log origin/main..HEAD --stat
commit 9861c2850c67b3bf5a057e94abe52eba4ff65583
Author: D0NMEGA <D0NMEGA@users.noreply.github.com>
Date:   Mon Sep 7 20:37:50 2026 -0500

    docs(phase-10): audit validation

 .../10-VALIDATION.md    | 303 ++++++++++++++++-----
 .../deferred-items.md   |  38 +++
 2 files changed, 279 insertions(+), 62 deletions(-)

commit d400947f21a9c680ca0d3eab23cc6e046e3a4d34
Author: D0NMEGA <D0NMEGA@users.noreply.github.com>
Date:   Mon Sep 7 20:37:47 2026 -0500

    test(phase-10): cover the two render channels the demo work shipped untested
    [...body elided; 25 lines...]

 .../CortexRenderTests/SelectionChannelTests.swift  |  93 ++++++++++++
 .../CortexRenderTests/TargetChannelTests.swift     | 160 +++++++++++++++++++++
 2 files changed, 253 insertions(+)

$ git diff --name-only origin/main..HEAD
.planning/phases/10-v1-real-data-closed-loop-launch/10-VALIDATION.md
.planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md
Packages/CortexRender/Tests/CortexRenderTests/SelectionChannelTests.swift
Packages/CortexRender/Tests/CortexRenderTests/TargetChannelTests.swift
```

Four files, two commits, +532/-62 lines. All five 1a patterns were re-run against exactly those
four files and every one returned clean:

```
$ command grep -nE -- '-----BEGIN[ A-Z]*PRIVATE KEY-----' <the 4 files>   -> clean: no PEM header
$ command grep -nE -- 'MATCH_PASSWORD[[:space:]]*='       <the 4 files>   -> clean
$ command grep -nE -- '<email ERE>'                        <the 4 files>   -> clean
$ command grep -nEi -- '<ASC issuer UUID ERE>'             <the 4 files>   -> clean
$ command grep -nE -- 'AKIA…|ghp_…|sk-…|xox[baprs]-'       <the 4 files>   -> clean
$ git diff origin/main..HEAD | grep -E '^\+.*/Users/[A-Za-z0-9_.-]+'
  clean: the 2 unpushed commits ADD no absolute /Users/ path
```

**Every finding in this audit is therefore already in `origin/main`.** The incremental disclosure
risk of the push itself is zero on all six scanned patterns.

## 1a. Working-tree secret scan

Applied over every tracked file (`git ls-files -z | xargs -0 grep …`), 556 tracked files.

### 1a-1 PEM private-key header - 2 hits, both placeholders

```
.planning/phases/08-…/08-04-PLAN.md:148:  … "key": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----" …
fastlane/asc_api_key.json.example:5:    "key": "-----BEGIN PRIVATE KEY-----\nREPLACE_WITH_P8_CONTENTS\n-----END PRIVATE KEY-----",
```

The `.example` is the template Plan 08-04 created deliberately; its payload is the literal string
`REPLACE_WITH_P8_CONTENTS`, its `key_id` is `REPLACE_WITH_10CHAR_KEY_ID`, its `issuer_id` is
`REPLACE_WITH_ISSUER_UUID`, and `.gitignore` lines 46-49 keep the real `fastlane/asc_api_key.json`
and every `*.p8` untracked while negating the `.example` back in. Added `b624c2f` (2026-06-23);
present in `origin/main`. **No private key material is present.**

This nonetheless makes one of Task 1's acceptance criteria false as literally written - see
FLAG-01.

### 1a-2 inline MATCH_PASSWORD assignment - 21 hits, no passphrase

Every hit is either a policy-gate implementation, a negative-control injection, or prose describing
the gate. The only assignment-shaped literal in the repo is
`Tools/scripts/match-policy.sh:207: printf 'MATCH_PASSWORD = "supersecret"\n' >> "$m"`, which is the
self-test that proves `match-policy.sh` bites; `supersecret` is a fixture string. `fastlane/Fastfile`
and `fastlane/Matchfile` read the passphrase from `ENV[…]` only. **No real passphrase is present.**

### 1a-3 email addresses - 13 hits under the gate's ERE, zero personal addresses

`git ls-files -z | xargs -0 grep -nEo -- '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}'`,
tallied by matched string:

| matched string | count | what it is | already in `origin/main`? |
|---|---|---|---|
| `git@github.com` | 12 | the SSH remote **form**, quoted inside policy-gate code and prose that forbid it. Not an address. | yes, all 12 |
| `D0NMEGA@users.noreply.github.com` | 1 (`10-launch-evidence.md:38`) | GitHub's own noreply address; it is the author and committer identity on all 525 commits and is therefore visible in every commit's metadata regardless. | yes |

The 13 line-level hits under the gate's stricter `(edu|com|org|net)` ERE are the same strings and
are listed at file:line in FLAG-02. Targeted probes for the user's own address returned nothing:

```
$ git ls-files -z | xargs -0 grep -nEi -- 'santine@'        -> (no output)
$ git ls-files -z | xargs -0 grep -nEi -- 'donovan\.santine' -> (no output)
$ git ls-files -z | xargs -0 grep -nEi -- '@icloud\.com'     -> (no output)
$ git ls-files -z | xargs -0 grep -nEi -- '@gmail\.com'      -> (no output)
$ git ls-files -z | xargs -0 grep -nEi -- 'utexas'
  .planning/phases/08-…/08-06-PLAN.md:145: … grep -nE "…|@utexas\\.edu|…" README.md returns nothing.
```

The single `utexas` hit is a **regex literal inside a grep pattern**, not an address; it names the
domain but no local part. It is listed as FLAG-03 rather than dismissed, because deciding whether a
personal domain may appear is the user's call, not the executor's.

### 1a-4 ASC issuer UUID - 1 hit, synthetic

```
Tools/scripts/readme-policy.sh:433:  printf 'issuer "%s"\n' "11111111-2222-3333-4444-555555555555" >> "$r"
```

The self-test's negative control. Not an App Store Connect issuer id.

### 1a-5 common cloud/token shapes - clean

```
$ git ls-files -z | xargs -0 grep -nE -- 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32,}|xox[baprs]-'
clean: no common token shapes
```

### 1a-6 absolute home paths - 68 hits (added beyond the plan's five patterns)

The plan's five patterns do not cover local filesystem paths, and a `/Users/<name>/…` path is a
real disclosure the moment the repository is public: it names the machine's account and its
directory layout. Scanning for it is why this audit exists rather than the README gate alone.

```
$ git ls-files -z | xargs -0 grep -hoE -- '/Users/[A-Za-z0-9_.-]+' | sort | uniq -c | sort -rn
  46 /Users/donmega
  22 /Users/d0nmega
```

68 lines across 23 files, all under `.planning/`, all already in `origin/main`
(`git grep -cE '/Users/…' origin/main` -> 68 lines / 23 files). Representative hits:

```
.planning/phases/01-…/01-01-PLAN.md:331: <automated>cd /Users/donmega/Desktop/Cortex && swift build …
.planning/phases/01-…/01-04-PLAN.md:157: git_url("file:///Users/donmega/Library/Cortex-fastlane-certs")
.planning/phases/01-…/01-04-SUMMARY.md:88: `/Users/donmega/Desktop/Cortex/Gemfile` -- Bundler manifest …
.planning/STATE.md:99:                 Matchfile uses `git_url("file:///Users/donmega/Library/…")` …
```

They disclose two local account names and the former project location
(`/Users/donmega/Desktop/Cortex`). No credential is at those paths and the fastlane certs path is a
directory that Phase 1 explicitly never created. Raised as FLAG-04.

## 1b. History scan

The 5 local `worktree-agent-*` branches are all ancestors of `main`
(`git merge-base --is-ancestor` -> yes, 5/5), so `--all` and `main` describe the same object set and
the push payload is the whole history.

```
$ git log --all --oneline | wc -l        525      (origin/main holds 523)
$ git rev-list --objects --all | wc -l  4493
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u \
    | grep -Ei '\.(p8|p12|mobileprovision|cer|pem|key|env)$'
Tools/toolchain-versions.env
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u \
    | grep -Ei '\.(mat|pt|mlpackage|mlmodelc)$'
Decoder/tests/fixtures/tiny_v73.mat
```

Both hits are extension matches on benign files, and `--diff-filter=A` covers files added and later
deleted, so a leaked-then-removed credential would have surfaced here. Neither is one:

- `Tools/toolchain-versions.env` is the SwiftFormat/SwiftLint version pin
  (`SWIFTFORMAT_VERSION=0.63.0`, `SWIFTLINT_VERSION=0.65.1`) plus 25 lines of comment. Added
  `21e5179` (2026-09-07, Plan 10-15); present in `origin/main`. No secret.
- `Decoder/tests/fixtures/tiny_v73.mat` is the synthetic fixture, confirmed in 1c.

**No credential-extension file carrying credential material, and no dataset or model artifact, was
ever added in any of the 525 commits.**

### The 2026-09-07 history rewrite, recorded as a pre-existing fact

Plan 10-17's threat T-10-17-06 and its success criterion "No history rewrite occurred" cannot be
asserted as a blanket statement, because a rewrite did happen - on 2026-09-07, user-directed,
before this plan ran, and already pushed. The evidence is direct, not inferred:

```
$ git log --all --format='%an <%ae>' | sort | uniq -c
 525 D0NMEGA <D0NMEGA@users.noreply.github.com>
$ git log --all --format='%cn <%ce>' | sort | uniq -c
 525 D0NMEGA <D0NMEGA@users.noreply.github.com>
$ git log --diff-filter=A --format='%h %ad %s' --date=short -- AGENTS.md
4605b83 2026-04-28 chore: track project context files before Phase 1 execution
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u | grep -i 'CLAUDE'
clean: no CLAUDE.md path exists anywhere in the rewritten history
```

Author and committer are uniform across all 525 commits, and the agent-instructions file reads as
having been named `AGENTS.md` since 2026-04-28 with no prior name anywhere in history. That is the
signature of a retroactive rewrite, not of organic history.

**This plan performs no rewrite.** No rebase, amend, `filter-repo` or force push has been run or
will be, under any Task-2 option. The reflog baseline at audit time is:

```
$ git reflog --date=iso | head -3
9861c28 HEAD@{2026-09-07 20:37:50 -0500}: commit: docs(phase-10): audit validation
d400947 HEAD@{2026-09-07 20:37:47 -0500}: commit: test(phase-10): cover the two render channels …
cd87d6f HEAD@{2026-09-07 19:23:16 -0500}: commit: feat(demo): free-running cursor, a real click, …
```

Only `commit:` entries. Raised as FLAG-05, because the plan's acceptance criterion is unsatisfiable
as written and the user should see why rather than read a false "no rewrite occurred".

## 1c. Payload scan

```
$ git ls-files | grep -E '^Decoder/(data|exports|checkpoints)/'
clean: no dataset, export or checkpoint tracked
$ git ls-files | grep -E '\.(pt|mlpackage|mlmodelc)$'
clean: no model or dataset artifact tracked
$ git ls-files | grep -E '\.bench/'
clean: no bench output tracked
$ git ls-files | grep -E '\.mat$'
Decoder/tests/fixtures/tiny_v73.mat
$ git ls-files | grep -E 'tiny_replay\.(bin|json)$'
Decoder/tests/fixtures/tiny_replay.bin
Decoder/tests/fixtures/tiny_replay.json
$ du -sh .git
 15M	.git
$ git ls-files -z | xargs -0 du -ck | tail -1
12556	total          (12.3 MB of tracked working-tree bytes, 556 files)
```

Ten largest tracked files, KB: `09-perf-report-ipad-m2.json` 1028, `05-perf-report-ipad-m2.json`
984, `sc1-histogram.csv` 780, `tiny_v73.mat` 444, `tiny_replay.bin` 108, `09-decoder-metrics.json`
108, `01-RESEARCH.md` 104, `10-RESEARCH.md` 100, `Decoder/uv.lock` 92, `09-training-evidence.md` 92.
Nothing large, nothing binary beyond the two fixtures.

**The CC-BY Indy dataset is absent.** `Decoder/manifests/indy_sessions.json` and
`Decoder/scripts/download_indy.py` ship SHA-256 checksums and a downloader, never Zenodo bytes.
D-07 and the Phase-9 D-21 tier split are intact.

### The three fixtures, each confirmed synthetic from its own disclosure

- **`Decoder/tests/fixtures/tiny_replay.json`** carries the field verbatim:
  `"disclosure": "synthetic fixture - not real neural data; exists so the export format is covered
  on a clean clone"`, with `"session_id": "tiny_replay_synthetic"` and both checkpoint digests set
  to 64 zeros because no checkpoint produced it.
- **`Decoder/tests/fixtures/tiny_replay.bin`** is bound to that sidecar by
  `"binary_sha256": "69db628905ff5115…"`, and its generator `Decoder/scripts/make_tiny_replay.py`
  opens: *"THIS FIXTURE IS SYNTHETIC. Its counts are Poisson draws from a seeded generator, its
  velocity is a closed-form Lissajous curve … It is not real neural data and must never be
  presented as a real-data artifact."*
- **`Decoder/tests/fixtures/tiny_v73.mat`** - generator `Decoder/scripts/make_tiny_v73.py` opens:
  *"Writes a small HDF5 file that is structurally a MATLAB v7.3 `.mat` … but whose values are
  wholly fabricated. No Zenodo bytes are redistributed, so there is no licensing question."*
  Its sidecar `tiny_v73.truth.json` records `"seed": 0` and closed-form ground truth.

## 1d. The demo capture

Plan 10-10 committed **no** screen recording and no still frame, so there is no frame to review.
Recorded as a check that found nothing rather than a check invented to pass:

```
$ git ls-files | grep -iE '\.(mov|mp4|gif|png|jpg|jpeg|heic|webm|m4v)$'
clean: NO tracked image, screen recording or still frame anywhere in the repo
$ git log --all --diff-filter=A --name-only --pretty=format: | sort -u | grep -iE '\.(mov|mp4|gif|…)$'
clean: no media file was ever added in any commit
$ ls docs/media/
ls: docs/media/: No such file or directory
```

The capture tooling is tracked and its output is not: `Tools/capture/record-demo.sh`,
`Tools/capture/README.md`, `Tools/capture/CortexMac.capture.entitlements`, with
`Tools/capture/out/` gitignored. `record-demo.sh` contains no absolute path and no signing identity;
the capture entitlements file contains only the App Group id and the
`$(AppIdentifierPrefix)`-templated keychain group, both already public in `project.yml`.

One documentation drift found, not a leak: `.gitignore`'s comment says "the .gif is committed
deliberately under `docs/media/`", but `docs/media/` does not exist and no `.gif` is tracked. Logged
to `deferred-items.md` rather than fixed here, since it is out of this task's scope.

## 1e. Dry run

```
$ git remote -v
origin	https://github.com/D0NMEGA/Cortex.git (fetch)
origin	https://github.com/D0NMEGA/Cortex.git (push)

$ git status --short
 M .planning/STATE.md

$ git log --oneline -15
9861c28 docs(phase-10): audit validation
d400947 test(phase-10): cover the two render channels the demo work shipped untested
cd87d6f feat(demo): free-running cursor, a real click, and the task's own 8x8 board
8df050f fix(demo): make the cell the target, and stop calling a square a radius
9388476 fix(demo): one acquisition per trial, held green, in the region that is scored
037a252 feat(demo): score against the task's own tolerance, and show the hits
0463abf fix(render): draw the task's target lattice, not a 30x30 substrate
670de9f fix(demo): one cursor, one target, and a tally that says what happened
45b8261 fix(capture): follow the app's decoder default
6c1b28f feat(decoder): ship the linear decoder and make it the demo default
4a29c04 refactor: rename the replay path off the closed-loop claim
91117e3 fix(render): zero-order hold the velocity across the cadence gap
b738a78 feat(demo): show decode provenance on screen
32c4341 fix(capture): make record-demo.sh actually run end to end
0cb6318 feat(demo): re-anchor the cursor per trial, fix stale-build capture

$ git push --dry-run origin main
To https://github.com/D0NMEGA/Cortex.git
   cd87d6f..9861c28  main -> main
exit=0
```

A fast-forward update of two commits, not an initial push. The one dirty file,
`.planning/STATE.md`, is orchestrator-owned counter and timestamp metadata
(`completed_phases 9->10`, `completed_plans 56->73`, `percent 80->100`, two date strings) and is
deliberately left uncommitted by this task.

## CI has already run, 24 times

The state Plan 10-17 was written to create already exists. Recorded here so no later artifact can
call the next push "the first run in the project's history".

```
$ gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'
24
$ gh api '…/actions/runs?per_page=100' --jq '.workflow_runs[] | .conclusion' | sort | uniq -c
   6 cancelled
   6 failure
  12 success
```

The first run in the project's history was `34154026468` at 2026-09-07T19:02:29Z on `879fbe14`, and
it **failed**. The six oldest runs all failed; runs since 2026-09-07T20:29Z are green apart from
five `cancelled` entries produced by the workflow's own `cancel-in-progress` concurrency group. The
seven most recent runs are consecutive successes. The run covering `origin/main`'s current head:

```
$ gh api '…/actions/runs?head_sha=cd87d6ff…' --jq '…'
34173147693 completed success 2026-09-08T00:23:20Z
https://github.com/D0NMEGA/Cortex/actions/runs/34173147693
```

Consequence for Task 3: the README's `CI-STATUS-CLAIM` hook and the "has not yet executed" sentence
were both removed by `30217d4`, so Task 3d must **re-add** the hook plus a run-citing sentence, not
edit an existing one. `grep -cF 'CI-STATUS-CLAIM' README.md` and `grep -cF 'total_count: 0'
README.md` both return 0 today. The current `## Verification` section (README line 224) says
"Twelve policy gates run in CI" in the present tense and cites no run.

## Verdict table

| # | Check | Result | Verdict |
|---|---|---|---|
| 1a-1 | PEM private-key header, tracked files | 2 hits, both `REPLACE_…` placeholders; no key material | **FLAGGED** (FLAG-01) |
| 1a-2 | inline `MATCH_PASSWORD =`, tracked files | 21 hits, all gate code / controls / prose; passphrase is ENV-only | PASS |
| 1a-3 | email addresses, tracked files | 13 hits: 12x `git@github.com` form, 1x GitHub noreply. Zero personal addresses | **FLAGGED** (FLAG-02) |
| 1a-3b | personal-domain literal | 1 hit, `@utexas\.edu` inside a grep pattern; no local part | **FLAGGED** (FLAG-03) |
| 1a-4 | ASC issuer UUID | 1 hit, `11111111-2222-…` self-test control | PASS |
| 1a-5 | AWS / GitHub / OpenAI / Slack token shapes | no matches | PASS |
| 1a-6 | absolute `/Users/…` home paths | 68 lines, 23 files, 2 account names disclosed | **FLAGGED** (FLAG-04) |
| 1b-1 | commit and object counts | 525 commits (523 on `origin/main`), 4,493 objects | PASS |
| 1b-2 | credential-extension file ever added | 1 extension hit, `Tools/toolchain-versions.env`, a version pin | PASS |
| 1b-3 | dataset or model artifact ever added | 1 hit, `tiny_v73.mat`, confirmed synthetic | PASS |
| 1b-4 | history rewrite | one occurred 2026-09-07, before and outside this plan; this plan performs none | **FLAGGED** (FLAG-05) |
| 1c-1 | `Decoder/{data,exports,checkpoints}/` tracked | nothing tracked | PASS |
| 1c-2 | `.pt` / `.mlpackage` / `.mlmodelc` tracked | nothing tracked | PASS |
| 1c-3 | `.mat` tracked | exactly `Decoder/tests/fixtures/tiny_v73.mat` | PASS |
| 1c-4 | `tiny_replay` tracked | exactly `tiny_replay.bin` + `tiny_replay.json` | PASS |
| 1c-5 | three fixtures confirmed synthetic | each confirmed from its own disclosure field or generator docstring | PASS |
| 1c-6 | `.bench/` output tracked | nothing tracked | PASS |
| 1c-7 | CC-BY Indy dataset absent | checksums and downloader only, no Zenodo bytes | PASS |
| 1c-8 | repository size | `.git` 15 MB, 12.3 MB tracked across 556 files | PASS |
| 1d-1 | demo capture reviewed | no capture exists; none was ever committed | PASS (nothing to review) |
| 1d-2 | capture tooling leak surface | no path, no signing identity; only already-public group ids | PASS |
| 1e-1 | push target and payload | fast-forward `cd87d6f..9861c28`, exit 0 | PASS |
| 1e-2 | unpushed commits re-scanned | all six patterns clean on all 4 files | PASS |
| X-1 | repository visibility before | `isPrivate: true` | PASS (recorded) |
| X-2 | CI execution history | 24 runs: 12 success, 6 failure, 6 cancelled | PASS (recorded) |

**21 PASS, 5 FLAGGED. No secret, no credential, no dataset byte, no export byte and no checkpoint
is in the working tree, in the history, or in the two commits about to be pushed.**

## FLAGGED rows - what the user must decide at Task 2

Each row names the finding, whether it is already on GitHub, and the decision. None is a leak of
live credential material; all five are disclosure or accuracy calls that belong to the user.

**FLAG-01 - PEM header in a committed template.**
`fastlane/asc_api_key.json.example:5` and `.planning/phases/08-…/08-04-PLAN.md:148` both contain the
literal `-----BEGIN PRIVATE KEY-----`. The payload is `REPLACE_WITH_P8_CONTENTS`. **Already in
`origin/main`** since `b624c2f`, 2026-06-23. This makes Task 1's acceptance criterion "No tracked
file contains a PEM private-key header" false as literally written, and makes the plan's own
automated verify line `test -z "$(git ls-files … grep -lE '-----BEGIN…')"` exit non-zero.
*Decide:* accept the finding as a classified non-leak and treat the acceptance criterion as
mis-specified (recommended, and the reason the `.gitignore` negation exists), or reword the
`.example` so the literal header no longer appears.

**FLAG-02 - email-shaped strings.** 13 lines match the gate's email ERE:
`.planning/STATE.md:99`; `01-04-PLAN.md:208,237`; `01-04-SUMMARY.md:73,150`; `08-04-PLAN.md:136,179`;
`08-04-SUMMARY.md:114,116`; `10-17-PLAN.md:116`; `10-launch-evidence.md:38`;
`Tools/scripts/match-policy.sh:18,222`. Twelve are the string `git@github.com`, quoted by code and
prose that forbid the SSH remote form; one is `D0NMEGA@users.noreply.github.com`, the commit author
identity on all 525 commits. **All 13 are already in `origin/main`.** No personal address exists in
any tracked file. *Decide:* accept as non-PII (recommended - removing them would break the policy
gates that quote the forbidden form, and the noreply address is already in every commit's
metadata), or ask for specific lines to be reworded in a new commit.

**FLAG-03 - personal email domain named in a regex.**
`.planning/phases/08-…/08-06-PLAN.md:145` contains `@utexas\.edu` inside a documented grep pattern.
It is not an address and has no local part, but it does state the user's institutional domain.
**Already in `origin/main`.** *Decide:* keep (recommended - it is a historical record of what the
README gate was built to catch), or generalise it to `@example\.edu` in a new commit. Note that
because it is already pushed, either choice affects future readers only.

**FLAG-04 - two local account names and a former project path.** 68 lines across 23 `.planning/`
files contain `/Users/donmega` (46) or `/Users/d0nmega` (22), including
`/Users/donmega/Desktop/Cortex` and `/Users/donmega/Library/Cortex-fastlane-certs`. **All 68 are
already in `origin/main`;** the two unpushed commits add none. No credential sits at any of those
paths and the fastlane certs directory was never created. This is the highest-volume disclosure in
the audit and the one most affected by the visibility decision: private today, it is visible only
to the account owner; public, it names the machine's user account to every reader. *Decide:* accept
(these are development-log paths in planning artifacts, and scrubbing them would rewrite the
`.planning/` record the project's evidence discipline depends on), or scrub them in a NEW commit
before answering the visibility half of Task 2. A rewrite is not an option: 196 of 199 cited commit
SHAs across `.planning/` would break.

**FLAG-05 - the plan's "no history rewrite" criterion cannot be met as written.** A rewrite of all
525 commits happened on 2026-09-07, user-directed, before this plan and outside its scope, and is
already pushed. This audit records that honestly rather than asserting a blanket "no rewrite
occurred", which would be false. *Decide:* confirm that Task 3's acceptance criterion is read as
"this plan performs no rewrite" (recommended - it is what the criterion was written to protect),
and confirm the standing prohibition stands: no rebase, amend, `filter-repo` or force push under
any Task-2 option, including as a remedy for FLAG-04.

## Self-scan: this audit is now the third unpushed commit

Written after the audit was committed as `96168ba`, because committing it changed the payload the
sections above describe and leaving that unsaid would be the same defect this milestone exists to
remove. The push is now three commits, not two:

```
$ git push --dry-run origin main
   cd87d6f..96168ba  main -> main
$ git log origin/main..HEAD --oneline
96168ba docs(10-17): audit what is already on GitHub, and what the next push adds
9861c28 docs(phase-10): audit validation
d400947 test(phase-10): cover the two render channels the demo work shipped untested
```

By quoting its own findings verbatim, this file adds matches for three of the six scanned patterns:

| pattern | lines added by `96168ba` | what they are |
|---|---|---|
| PEM private-key header | 3 | quotations of `asc_api_key.json.example:5` and the FLAG-01 rows |
| email ERE | 9 (6x `D0NMEGA@users.noreply.github.com`, 3x `git@github.com`) | quotations in FLAG-02 and the rewrite-fingerprint block |
| absolute `/Users/` path | 13 (10x `/Users/donmega`, 3x `/Users/d0nmega`) | the FLAG-04 sample hits and this file's own run header |
| `MATCH_PASSWORD =` / ASC issuer UUID / token shapes | 0 | not quoted as literals |

```
$ git diff origin/main..HEAD | grep -E '^\+.*(AKIA…|ghp_…|sk-…|xox[baprs]-)'
clean: none
```

Every added match is a quotation of content already in `origin/main`. No new secret, path or
address enters the repository through this commit, and the incremental disclosure of the push
remains zero. It does mean FLAG-04's count rises from 68 to 81 lines once this file is pushed, and
that a scrub disposition on FLAG-04 would have to cover this artifact too.

## Status

Task 1 complete. **Nothing has been pushed. No `gh repo edit` has been run. Repository visibility
is unchanged at `isPrivate: true`.** Task 2's checkpoint is presented to the user with the five
FLAGGED rows above; the "Decision" section is appended to this file only after the user answers.
