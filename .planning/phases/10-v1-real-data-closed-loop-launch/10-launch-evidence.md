# Plan 10-17 launch evidence: first push and first CI runs

**Machine:** Apple M5 Pro, macOS 26.5 (25F71), Xcode 26.3 (17C529), Swift 6.2.4
**Runner:** `macos-15`, Xcode pinned 26.3 via `setup-xcode@v1`
**Date:** 2026-09-07
**Repo:** `https://github.com/D0NMEGA/Cortex`, **private** (`gh repo view` reports
`private=true visibility=PRIVATE`)

This file records what happened, not what was expected. Plan 10-17's own objective says the outcome
is not knowable in advance because a hosted runner differs from the sweep machine. It differed.

## 1. What was published

The push was preceded by a history rewrite the user requested (see section 2) and two prerequisite
fixes they authorised:

| prerequisite | commit | what |
|---|---|---|
| Info.plist keys | `3510952` (pre-rewrite) | `xcodegen generate` was stripping `NSAccessibilityUsageDescription` and `CortexBCIHIDProtocolVersion` from both tracked plists. Fixed at the generator input (`project.yml`) and gated by the new `Tools/scripts/infoplist-policy.sh`, 7 controls. |
| personal addresses | `4ae39a4` (pre-rewrite) | 11 occurrences of two personal Apple ID addresses across 8 files replaced with `<apple-id redacted>`, including three verbatim `codesign -dvv` transcripts. Ordinary commit, not a history rewrite. |

Pre-push audit, run on the rewritten tree:

    dataset / export / checkpoint tracked : 0
    key / pem / p12 / mobileprovision     : 0
    personal emails in tracked content    : 0
    agent worktree paths tracked          : 0
    largest tracked file                  : 1.0 MB  09-perf-report-ipad-m2.json

## 2. The history rewrite

`git filter-repo` over all 496 commits, at the user's instruction, to remove every reference to the
authoring harness. Verified on the rewritten history rather than the working tree:

| requirement | result |
|---|---|
| no commit message mentions the harness | 0 matches; 28 `Co-Authored-By` trailers stripped |
| single author identity | `D0NMEGA <D0NMEGA@users.noreply.github.com>`, author and committer, every commit |
| no harness instruction file in any commit | 0; the root instruction file is `AGENTS.md` across all history |
| no harness reference in file content | 0 files (was 337 matches across 130 files) |

Two strings were **not** blanket-renamed, because they were functional rather than prose: the
`.gitignore` entry and `honesty-sweep.sh`'s `find` prune, both of which guard against staging or
scanning live worktrees of other branches. Renaming them would have silently disarmed both. They now
match by shape (`.*/worktrees/`, `-name 'worktrees'`) and were verified against the real condition: a
worktree carrying an unlabeled superseded number is planted, and the sweep still exits 0.

**Provenance cost, paid not deferred.** The rewrite orphaned 286 commit-SHA citations across
`.planning/`. Remapped from `.git/filter-repo/commit-map`: 885 occurrences across 96 files, 280 of
286 now resolve against `HEAD`, none dangling. Only 7-to-12-character abbreviations were eligible, so
3105 longer hex strings (`source_sha256`, `export_sidecar_sha256`, checksum manifests) are
byte-identical. All 38 committed JSON and `*-evidence.md` artifacts came through the rewrite with
unchanged blob hashes.

**Restore point:** a `git bundle` of the pre-rewrite `main`, held OUTSIDE this repo under the local
harness backups directory (`cortex-prescrub-20260907/cortex-main-f69da34-prescrub.bundle`).
`git bundle verify` OK; it contains `main` at `f69da34` with the original instruction file and
authorship.
No ref in the working repo points at the pre-rewrite history: `filter-repo` rewrites tags too, so the
backup tag created beforehand was itself rewritten and was never a valid restore point. The bundle is
the only one.

## 3. The runs

`gh api repos/D0NMEGA/Cortex/actions/runs` returned `total_count: 0` immediately before the push.

| run | id | result | failing step | cause |
|---|---|---|---|---|
| 1 | 34154026468 | failure | `decoder-python` step 6 (Ruff) and `build-and-lint` step 7 (toolchain pin) | see 3.1, 3.2 |
| 2 | 34154374914 | failure | `build-and-lint` step 15 (Resolve SwiftPM) | see 3.3 |
| 3 | 34154714318 | failure | `build-and-lint` step 18 (CortexIPC tests) | see 3.4 |
| 4 | (pending) | | | |

### 3.1 Ruff E501, self-inflicted

`E501 Line too long (103 > 100)` at `Decoder/scripts/fit_kalman_gain.py:790`. The section-2 reference
scrub replaced a 19-character phrase with a 24-character one inside an emitted Swift doc comment,
taking the line from 98 to 103. `pytest` was re-run after the scrub; `ruff check` was not, and that
gap is why it reached a runner. Reflowed by moving one word to the next line, applied identically to
the generator and to the generated `KalmanConstants.swift` so the two still agree.

### 3.2 Toolchain pin drift, the gate working

    ERROR [swiftformat] version drift: installed 0.63.0, pinned 0.61.1
    ERROR [swiftlint]   version drift: installed 0.65.1, pinned 0.63.3

CI installs both tools with an unpinned `brew install`, so the runner had newer versions than the
sweep machine. This is precisely the condition `toolchain-policy.sh` exists to catch: a remediation
measured under one version and gated by another is not a remediation.

Resolved in the order the gate's own error message prescribes, re-measure first and pin second:

| tool | runner version | re-measured result |
|---|---|---|
| swiftlint | 0.65.1 | `--strict` 0 violations, unchanged from 0.63.3 |
| swiftformat | 0.63.0 | `--lint` 70 sites in 20 files, all from one new default rule, `wrapIfStatementBodies` |

`wrapIfStatementBodies` was **applied, not disabled**. It is cosmetic, changes no semantics, and the
alternative was a third documented `--disable` in `.swiftformat` with no substantive objection behind
it. The two existing disables were each for a real reason (a semantic rewrite that broke compilation;
a rule that deleted 179 `@Test("...")` display names). This one had none. Result: +122/-45 lines
across 20 files, no committed JSON or `*-evidence.md` changed, all gates and tests green after.

### 3.3 The clean-clone proof had never worked

    error: Could not find Package.swift in this directory or any of its parent directories.

The FOUND-04 step ran `swift package resolve` from the repo root. There is no `Package.swift` there;
the eight packages live under `Packages/*/`. The command fails on any machine, including locally, so
**the step could not have passed since it was written in Phase 1**. It shipped through eight phases
because CI had never executed. This is the single clearest vindication of Plan 10-17 existing at all:
the value of the first run was not a green badge, it was discovering that a proof step was inert.

Fixed to loop `Packages/*/` with `--package-path`. Verified by running the new step body verbatim:
all eight packages resolve, exit 0.

**Pre-flight for the same class of defect**, done once rather than one runner round-trip at a time:
every `Tools/scripts` path referenced anywhere in `ci.yml` exists; no `swift` or `cargo` invocation is
missing its path argument (the two `cargo` calls correctly use `--manifest-path`); and all 15 scripted
`run:` blocks execute cleanly locally as whole blocks.

### 3.4 The runner could not run a macOS 26 binary

    error: Exited with unexpected signal code 5
    Fatal error: Failed to open test bundle ... dlopen(...):
      Library not loaded: /usr/lib/swift/libswift_DarwinFoundation1.dylib

Not a code defect and not a flake. The runner image is `macos-15-arm64`; all eight `Package.swift`
files declare `platforms: [.macOS(.v26), .iOS(.v26)]`, which is the project's stated constraint. A
binary built against the Xcode 26.3 SDK for a macOS 26 deployment target COMPILES on macos-15 and
then fails at load time, because macOS 15 does not ship the macOS 26 Swift runtime. Nineteen steps
passed before it, so the failure surfaced only once CI got far enough to execute a test bundle.

`ci.yml:5` claimed macos-15 was "the only runner with Xcode 26.x pre-installed". That was true when
Phase 1 wrote it and is no longer: `macos-26-arm64` shipped 2026-08-31
(`actions/runner-images` tag `macos-26-arm64/20260831.0337`). `build-and-lint` moved to `macos-26`.
`decoder-python` stays on `macos-15` deliberately -- it is pure Python, it passes there, and moving
it is outside this fix.

The same 26 CortexIPC tests pass on the sweep machine, which runs macOS 26.5. All eight packages do:

    CortexBCIHID 24   CortexDecoder 20   CortexDemo 44   CortexIPC 26
    CortexReFIT  32   CortexRender  19   CortexRing     7   CortexCore (no test target)

So the runner was never testing what the project targets. Three of the four failures so far were
pre-existing repo defects that only a real runner could expose, which is the argument for this plan
existing.

## 4. Local state at the time of the last push

    12 policy gates + 12 --self-tests   all exit 0
    swiftlint --strict                  0 violations   (0.65.1)
    swiftformat --lint .                exit 0         (0.63.0)
    ruff check Decoder                  exit 0
    pytest -m "not slow"                289 passed, 10 deselected
    swift test CortexDemo/ReFIT/Render  44 / 32 / 19 passed
    harness references in tracked files 0

## 5. Honest limitations

- `CortexiOS` had never been compiled anywhere before these runs. The iOS 26.2 platform is not
  installed on the sweep machine, so CI is the first environment to build it.
- The runner is `macos-15` on Apple silicon; every number in this repo labelled M5 Pro remains a
  sweep-machine number and is not restated as a runner number.
- A green CI run proves the gates execute and pass on a clean checkout. It proves nothing about the
  iPad-M4 hardware measurements, which remain deferred and are labelled as such wherever they appear.
