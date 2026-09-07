---
status: PARTIAL
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 15
subsystem: infra
tags: [swiftformat, swiftlint, ci, github-actions, toolchain-pinning, lint, provenance]

# Dependency graph
requires:
  - phase: 01-foundation-2026-toolchain
    provides: ".swiftformat / .swiftlint.yml / ci.yml -- the lint configs and the two unpinned brew-installed tools this plan pins and first actually runs"
  - phase: 10-14
    provides: "honesty-sweep.sh, the same-physical-line labeling gate that a reformat could have split"
provides:
  - "Tools/toolchain-versions.env -- the committed SwiftFormat/SwiftLint version pin"
  - "Tools/scripts/toolchain-policy.sh -- the version-drift gate, 4 assertions, 5 negative controls"
  - "10-lint-baseline.md -- the measured pre-remediation counts, committed before any reformatting"
  - "swiftformat --lint . exits 0 across the repo (was 79/113 files)"
  - "the residual swiftlint --strict roster 10-16 has to clear, classified into three actionable groups"
affects: [10-16, 10-17, any-future-lint-or-ci-work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lint toolchain pinned in a committed env file and asserted at run time by a gate with negative controls"
    - "Measure-then-remediate: the baseline is committed in an earlier commit than the change it baselines"
key-files:
  created:
    - Tools/toolchain-versions.env
    - Tools/scripts/toolchain-policy.sh
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-lint-baseline.md
  modified:
    - .github/workflows/ci.yml
    - .swiftformat
    - .swiftlint.yml
    - "73 .swift files under Apps/, Packages/, Tools/spikes/"

key-decisions:
  - "--header strip replaced by --header ignore: the sweep would have DELETED 315 lines of provenance headers across 19 files. Removes 315 violations without fixing anything; explicitly not counted as remediated."
  - "SwiftLint .build exclusion changed from a four-package enumeration to the glob Packages/*/.build: four later-added packages were being linted inside their vendored dependency checkouts."
  - "noForceUnwrapInTests disabled: it rewrites as! into try #require(... as?), which does not compile for CoreFoundation types and contradicts .swiftlint.yml's own 'as! allowed in tests only' policy."
  - "swiftTestingTestCaseNames left ENABLED, and the resulting SwiftFormat-vs-SwiftLint conflict reported rather than resolved: choosing which of the two CI gates yields is 10-16's call, not this plan's."

patterns-established:
  - "Version-pin gate: a committed pin file read (not sourced) by a policy script that fails naming both the installed and the pinned version plus the remedy"
  - "Artifact checksum manifest taken before and after a mechanical sweep to prove no emitted byte moved"

requirements-completed: [RD-09]

# Metrics
duration: 1h 5m
completed: 2026-09-07
---

# Phase 10 Plan 15: Pin the lint toolchain, measure the baseline, clear SwiftFormat Summary

**SwiftFormat now exits 0 across all 113 files under a committed 0.61.1/0.63.3 version pin with a drift gate, with every emitted artifact proven byte-identical; the sweep also exposed that `--header strip` would have deleted 315 lines of provenance and that SwiftFormat and SwiftLint are mutually unsatisfiable as configured.**

## Performance

- **Duration:** 1h 5m
- **Tasks:** 3 of 3
- **Files modified:** 78 (73 `.swift` + `ci.yml` + `.swiftformat` + `.swiftlint.yml` + 2 created in `Tools/`)
- **Commits:** 5

## Headline numbers

| | before | after |
|---|---|---|
| `swiftformat --lint .` | 79/113 files, 1,869 violations, **exit 1** | **0/113 files, exit 0** |
| `swiftlint --strict` | 514 violations, exit 2 | **546 violations, exit 2** (10-16's scope) |
| Package test suites | 8/8 green | **8/8 green, 186 tests** |
| Policy gates + self-tests | 10 + 10 | **11 + 11, all exit 0** |
| Committed JSON + evidence artifacts | 37 | **37, all sha256-identical** |

## Task commits

1. **Task 1: pin the lint toolchain and gate the pin** - `2f80b2e` (chore)
2. **Task 2: measure and commit the true pre-remediation baseline** - `bcab25b` (docs)
3. *(pre-sweep config correction)* - `72661b5` (fix)
4. *(pre-sweep config correction)* - `6e5db71` (fix)
5. **Task 3: run the SwiftFormat sweep** - `7af0cad` (style)

## Verification, verbatim

### Violation counts, per tool

```
PRE-SWEEP  (commit 2f80b2e, clean tree, no .build anywhere)
  swiftformat --lint .   79/113 files require formatting, 16 files skipped.   exit 1
                         1869 reported violations
                         (with --header ignore: 73/113, 1551 violations)
  swiftlint --quiet      514                                                  exit 2
                         301 error / 213 warning

POST-SWEEP (commit 7af0cad)
  swiftformat --lint .   0/113 files require formatting, 16 files skipped.    exit 0
  swiftlint --strict     546                                                  exit 2
                         376 error / 170 warning
```

The plan's interface block predicted 71/101 files and 526 SwiftLint violations. Measured 79/113 and
514. Reported as measured; see "Where the measurements disagree with the plan" below.

### Artifact checksum manifest

Method: `git ls-files -z | grep -zE '\.(json)$|-evidence\.md$' | xargs -0 shasum -a 256 | sort -k2`,
captured before Task 1 and again after the sweep commit. 37 tracked artifacts.

```
=== FINAL manifest diff vs pre-sweep (expected: empty) ===
EMPTY - all 37 artifacts byte-identical
```

The six artifacts named in the constraint, at their final (== original) digests:

```
57a8d54f...  .planning/phases/07-.../refit_bps.json
5a4f2d39...  .planning/phases/08-.../webgrid_bps.json
829b1bf4...  .planning/phases/09-.../09-decoder-metrics.json
4cef1c8c...  .planning/phases/10-.../10-ceiling.json
9a4948b3...  .planning/phases/10-.../10-refit-real.json
8d6a08b9...  .planning/phases/10-.../10-replay.json
```

Independently corroborated by two live regeneration checks, not just by the manifest:
`refit_bps.json` regenerated from a cleared `.bench` diffs empty against the committed Phase-7 copy,
and `bps-policy.sh` ran `CortexReFITBench --smoke` twice and confirmed `webgrid_bps.json` byte-identical
across runs and equal to the committed Phase-8 copy.

### All eleven gates, with and without `--self-test`

```
readme-policy            gate=0      readme-policy  self-test=0
bps-policy               gate=0      bps-policy     self-test=0
render-policy            gate=0      render-policy  self-test=0
hid-surface-policy       gate=0      hid-surface    self-test=0
decoder-policy           gate=0      decoder-policy self-test=0
refit-real-policy        gate=0      refit-real     self-test=0
honesty-sweep            gate=0      honesty-sweep  self-test=0
hotpath-policy           gate=0      hotpath-policy self-test=0
notarize-policy          gate=0      notarize-policy self-test=0
match-policy             gate=0      match-policy   self-test=0
toolchain-policy         gate=0      toolchain-policy self-test=0
validate-privacy-manifest.sh                        exit=0
```

`honesty-sweep.sh` was run immediately after the SwiftFormat pass and before committing, per the
same-physical-line hazard. It reports `ok [label] every superseded token in the swept tree carries a
label on its own line`. The sweep did wrap four long comment lines into nine (including lines
carrying `8.5` and `4.16`), and the gate still passes -- the labels stayed on their numbers' lines.
`README.md` line 134 was not touched; the sweep modified no non-`.swift` file.

### Decoder Python suite

```
$ uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q
288 passed, 1 skipped, 10 deselected, 1 warning in 22.28s
```

Matches the expected 288/1/10 exactly. The skip is the gitignored dataset (`no loadable real .mat present`).

### Swift package suites

```
CortexDemo   exit=0  Test run with 44 tests in 5 suites passed     (expected 44)
CortexReFIT  exit=0  Test run with 32 tests in 5 suites passed     (expected 32)
CortexRender exit=0  Test run with 19 tests in 4 suites passed     (expected 19)
```

Full battery, all eight packages, 186 tests: CortexCore 15, CortexIPC 26, CortexRing 7,
CortexDecoder 19, CortexRender 19, CortexReFIT 32, CortexBCIHID 24, CortexDemo 44.

### Task 1 manual bite check

`SWIFTLINT_VERSION=0.0.0` in a temp copy, `TOOLCHAIN_PIN_FILE` repointed at it:

```
ERROR [swiftlint] version drift: installed 0.63.3, pinned 0.0.0 (SWIFTLINT_VERSION in .../bite.env).
       ... REMEDY, in ONE commit: re-run the sweep under 0.63.3, update
       .../10-lint-baseline.md with the new counts, THEN set SWIFTLINT_VERSION=0.63.3 here.
exit=1
```

Names both versions and the remedy. `--self-test` prints five `PASS [` lines (plan required four).

### Task 3a header-survival check

Run on temp copies before the repo-wide pass, as required. `KalmanFilter.swift` (the plan's named
sample): 29-line diff, header **intact**, changes limited to semicolon splitting, brace wrapping and
one modifier reorder (`public nonisolated final` -> `public final nonisolated`). But the sample was
not representative and the STOP condition fired on other files -- see Deviation 1.

### Task 3e generated-file check

`Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` was **not touched by the sweep**
(`git diff --stat` empty), and is independently confirmed in scope and clean:
`swiftformat --lint <file>` -> `0/1 files require formatting`. So the emitter still produces
swiftformat-clean output and the do-not-hand-edit contract holds. `KalmanConstantsTests` passed as
part of CortexReFIT's 32.

**Not performed as literally specified:** the plan's `fit_kalman_gain.py --data-dir Decoder/data
--session indy_20160630_01` re-run. `Decoder/data/` is gitignored and absent in this fresh worktree,
and `download_indy.py` has no per-session flag -- it fetches every session in the manifest, 1.77 GB.
The question 3e exists to answer ("did the sweep change the generated file, and must the emitter be
updated?") is answered definitively by the zero diff. I did not download 1.77 GB to re-derive a file
the formatter provably never touched, and I am not claiming a run I did not do.

## Deviations from plan

### 1. [Rule 3 - Blocking] `--header strip` would have destroyed 315 lines of provenance

- **Found during:** Task 3a (and pre-empted into Task 2, so the baseline records it)
- **Issue:** `fileHeader` is 315 of the 1,869 reported violations across 19 files, and every one is a
  line SwiftFormat would **delete**. Verified on temp copies: `Apps/CortexRenderBench/FrameSoak.swift`
  lost its entire 31-line block (the "what mode (a) measures vs what it does NOT" honesty framing and
  the D-05 determinism argument); `CursorIntegrator.swift` lost 27 lines (the D-04 velocity-seam
  rationale); `Apps/CortexiOS/App.swift` lost both its lines. The plan's named sample
  (`KalmanFilter.swift`) survives because SwiftFormat only treats a leading comment as a strippable
  *header* when a blank line separates it from the first declaration -- so the sample was
  unrepresentative, which is exactly why the plan required the check.
- **Fix:** `.swiftformat` `--header strip` -> `--header ignore`, the remedy the plan names for this
  branch. Verified: all three sampled headers survive verbatim, every other rule still applies.
- **Files modified:** `.swiftformat`
- **Verification:** re-ran the temp-copy format with the new config; headers byte-identical
- **Committed in:** `72661b5`

**Called out because it cuts against this plan's own headline:** this removes 315 violations without
fixing anything. Post-correction the pre-sweep baseline is 73/113 files and 1,551 violations. Those
315 are **not** counted as remediated anywhere. The alternative was deleting 315 lines of provenance
from a repo whose whole discipline is that published numbers carry their origin.

### 2. [Rule 1 - Bug] SwiftLint was linting inside vendored dependency checkouts

- **Found during:** Task 2 (investigating why two directories in the plan's table measured 0)
- **Issue:** `.swiftlint.yml` excluded `.build` for only the four packages that existed in Phase 1.
  `CortexReFIT`, `CortexRing`, `CortexDemo` and `CortexBCIHID` were added later and never added, and
  SwiftLint descends into hidden directories -- so once a `swift test` created those `.build` dirs,
  SwiftLint reported violations in third-party dependency source. `ci.yml` runs the package test
  suites **before** `swiftlint --strict`, so on a runner this always fires.
- **Fix:** the four-entry enumeration replaced by the glob `Packages/*/.build`, which cannot go stale.
- **Verification:** probe file (2 violations) placed in each unexcluded `.build`. Old config: **522
  total, 8 inside `.build`**. New config: **514 total, 0 inside `.build`**. Control: the same probe in
  the already-excluded `CortexCore/.build` scored 0 both ways. Re-confirmed after the real test
  battery created all eight `.build` dirs: 0 violations inside `.build`.
- **Files modified:** `.swiftlint.yml`
- **Committed in:** `72661b5`

`.swiftformat` deliberately did **not** get the equivalent change: measured as a no-op, because
SwiftFormat never descends into hidden directories (same 113 files with and without the probes, and
it never names the probe file). The change was made, measured, and reverted rather than committed as
a cosmetic diff.

### 3. [Rule 1 - Bug] `noForceUnwrapInTests` emitted code that does not compile

- **Found during:** Task 3d (`swift test --package-path Packages/CortexIPC` failed)
- **Issue:** the rule rewrites `as!` into `try #require(... as?)`. That is a semantic change, not
  formatting, and for CoreFoundation types the result is a build error, not a warning:
  `conditional downcast to CoreFoundation type 'CFBoolean' will always succeed`. It broke
  `KeychainTests.swift` at two sites. It also contradicts this repo's stated policy --
  `.swiftlint.yml` pins `force_unwrapping` at error severity with the note "`try!` and `as!` allowed
  in tests only", so `as!` in a test is deliberate and permitted here.
- **Fix:** `--disable noForceUnwrapInTests` in `.swiftformat`; the two sites restored to their
  original `as!`. A cascading `redundantThrows` (the `throws` became redundant again once the `try`
  was gone) was resolved by re-running the formatter to convergence.
- **Verification:** `swift test --package-path Packages/CortexIPC` -> 26 tests, 5 suites, exit 0;
  `swiftformat --lint .` -> 0/113, exit 0
- **Committed in:** `6e5db71` (config) and `7af0cad` (the two restored lines, per plan Task 3f)

### 4. [Rule 3 - Blocking] CortexRing's Rust xcframework was absent

- **Found during:** Task 3d
- **Issue:** `swift test --package-path Packages/CortexRing` failed with `local binary target
  'CortexRingFFI' ... does not contain a binary artifact`. The xcframework is gitignored and absent in
  a fresh worktree. Pre-existing environment requirement, not sweep damage.
- **Fix:** ran `./Tools/scripts/build-rust.sh` (exit 0, three slices assembled)
- **Verification:** `swift test --package-path Packages/CortexRing` -> 7 tests, exit 0
- **Committed in:** n/a (gitignored build output; no source change)

### 5. Scope: one file outside the plan's stated `Apps/` + `Packages/`

The plan's acceptance criterion says the sweep commit should show only `.swift` files under `Apps/`
and `Packages/`. It contains 73 `.swift` files, of which 72 are under those two roots and one is
`Tools/spikes/keychain-access-group-spike/main.swift` -- a Swift file inside `.swiftformat`'s
configured scope. Excluding it would have left `swiftformat --lint .` non-zero, which is the plan's
primary success criterion. Reported rather than silently reconciled.

**Total deviations:** 5 (2 bugs, 2 blocking, 1 scope note). **Impact:** deviations 1-3 were each
necessary to avoid shipping something worse than the problem being fixed -- destroyed provenance,
a linter policing third-party code, and a formatter emitting code that does not build. No gate was
weakened, excluded or disabled: `Tools/scripts/*-policy.sh` and `honesty-sweep.sh` are untouched and
all eleven gates plus self-tests pass.

## Where the measurements disagree with the plan

Reported as measured, not reconciled.

| | plan / D-18 | measured |
|---|---|---|
| SwiftLint total | "around 535" / 526 | **514** clean tree, **522** with `.build` present |
| Phase-7 (`CortexReFIT`) subset | 67 | **135** -- roughly double |
| SwiftFormat | 71 of 101 files | **79 of 113** as committed, **73 of 113** post-`--header ignore` |
| `force_unwrapping` | 24 | **8** |
| `Packages/CortexRing` | 30 | **0** |
| `Packages/CortexBCIHID` | 30 | **0** |
| `CortexReplayBench/main.swift` `identifier_name` (per the handoff note) | 8 | **43** (35 of them snake_case JSON keys) |

The two 30s and part of the `CortexReFIT` gap are consistent with the plan's numbers having been
taken on a machine where `.build` directories existed, since those are exactly the packages that were
unexcluded (Deviation 2). Stated as a reading of the evidence, not an established fact.

## Handoff to 10-16: the residual `swiftlint --strict` roster

`swiftlint --strict` exits **2** with **546** violations (376 error, 170 warning). Measured at
`7af0cad` under SwiftLint 0.63.3, on a tree with all eight `.build` directories present and 0
violations inside them.

By rule:

| count | rule | count | rule |
|---|---|---|---|
| 498 | `identifier_name` | 3 | `cyclomatic_complexity` |
| 11 | `opening_brace` | 2 | `function_parameter_count` |
| 8 | `force_unwrapping` | 1 | `type_name` |
| 6 | `file_length` | 1 | `static_over_final_class` |
| 5 | `large_tuple` | 1 | `implicit_optional_initialization` |
| 4 | `function_body_length` | 1 | `empty_count` |
| 4 | `force_cast` | 1 | `blanket_disable_command` |

By directory: `CortexReFIT` 143, `CortexDemo` 136, `CortexIPC` 75, `CortexRender` 63,
`CortexRenderBench` 32, `CortexDaemon` 29, `CortexDecoder` 29, `CortexCore` 19, `CortexBCIHID` 15,
`CortexiOS` 4, `CortexMac` 1.

`identifier_name`'s 498 are three different problems and must not be treated as one:

**Group A -- 75 backticked `@Test` names. THIS IS A TOOL CONFLICT, NOT A BACKLOG.**
SwiftFormat's `swiftTestingTestCaseNames` rewrote `@Test("1: sample() = present(ns) - ...")` plus a
camelCase function into `@Test` plus a backticked descriptive function name. SwiftLint then rejects
those identifiers ("should start with a lowercase character"). There were **0** such violations
before the sweep and **75** after, all `Function name` violations, all at error severity.

As configured, **the repo cannot satisfy `swiftformat --lint .` and `swiftlint --strict`
simultaneously.** Renaming them re-triggers SwiftFormat; leaving them fails SwiftLint. One of the two
configs must yield, and choosing which is a repo-wide decision I deliberately did not make here --
my instruction is to report a genuine gate-vs-formatter conflict, not to resolve it by disarming
either side. The options, with their costs:
1. `--disable swiftTestingTestCaseNames` in `.swiftformat`. Clears all 75, and reverts ~358 of the
   sweep's changes. Rejects the Swift Testing idiom SwiftFormat 0.61 considers canonical.
2. Exclude test targets from `identifier_name` in `.swiftlint.yml`. Clears the 75 and probably part
   of Group C, but weakens the rule across all test code.
3. Raise `identifier_name`'s allowed character set / max length for test targets only.

**Group B -- 97 snake_case identifiers that ARE the serialized JSON schema.** These are `Encodable`
stored properties; Swift's synthesized `CodingKeys` makes the property name the JSON key verbatim.
Renaming any of them changes the bytes of a committed artifact under a byte-identity check. Located:

| count | file |
|---|---|
| 35 | `Packages/CortexDemo/Sources/CortexReplayBench/main.swift` |
| 24 | `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift` |
| 17 | `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` |
| 14 | `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` |
| 4  | `Packages/CortexDecoder/Sources/CortexDecoder/LatencyHistogram.swift` |
| 2  | `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` |
| 1  | `Packages/CortexReFIT/Sources/CortexReFIT/IntentRotation.swift` |

The handoff note said `CortexReplayBench/main.swift` carries 8; it carries **43** total, of which 35
are this group. Either a scoped config exception or explicit `CodingKeys` (which would preserve the
wire names while renaming the Swift properties) works. **Re-run the checksum manifest afterwards** --
the method in this summary is reusable verbatim.

**Group C -- 326 short mathematical names** (`dt`, `vx`, `vy`, `k0`..`k5`, `a0`..`a5`, `h0`, `h1`),
concentrated in the Kalman/SIMD code where they mirror the published state-space notation. Renaming
is safe for the artifacts but loses that correspondence. Per-site judgement.

Also for 10-16: the 8 `force_unwrapping` are at **error** severity and six are in production IPC code
(`ShmRing.swift` x2, `FDChannel.swift`, `SessionKeychain.swift` x2, plus the two app `ContentView`s and
one test).

## Issues encountered

- **The plan's 3a sample was unrepresentative**, which nearly let a 315-line provenance deletion
  through. Resolved by checking files that were actually in the `fileHeader` violation list rather
  than only the one the plan named. The general lesson: sample the population the rule flags, not a
  file chosen for other reasons.
- **`exit=$?` after a pipe reports the pipe's last command.** An early `swift test ... | tail` read as
  exit 0 while the build was actually failing. All exit codes in this summary were re-taken by
  redirecting to a file and reading `$?` directly.
- **`swiftlint <path>` does not narrow scope** when the config sets `included:` -- it lints the
  configured set once per path argument. An early "1028 violations in two packages" reading was my own
  artifact (2 x 514), not a finding. Corrected before it reached any committed number.

## Cosmetic regression, reported not chased

`sortImports` moved the leading comment block *below* the imports in **29 files** where no blank line
separated the comment from the first import (SwiftFormat treats such a comment as attached to the
import it precedes, and carries it along when sorting). No comment content was lost -- verified line
by line across the whole diff: 200 comment lines removed, 205 added, with the 4 "lost" long lines
accounted for as 9 wrapped ones and zero unique text missing. The file header simply no longer leads
the file in those 29. Not fixed: the repair would touch 29 more files and would also convert those
comments into SwiftFormat-recognised *headers*, which is precisely the category `--header strip`
deletes -- so it would trade a cosmetic issue for a latent provenance risk.

## Next plan readiness

Ready for **10-16**. `swiftformat --lint .` is green and pinned; the roster above is the exact
remaining surface, classified and located.

**One thing 10-16 must decide before it starts:** Group A is a genuine SwiftFormat-vs-SwiftLint
deadlock, not a list of fixes. It cannot be worked down violation by violation -- one of the two
configs has to yield, and that decision may warrant surfacing to the user, since it changes what CI
enforces for every future test file.

**Constraint that carries forward:** no emitted byte may move. The manifest method in "Verification"
reproduces in one command and returned empty for this plan; 10-16's renames are far more likely to
disturb it than a formatter was.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-07*

## Self-Check: PASSED

All four created/modified key artifacts exist on disk; `toolchain-policy.sh` is executable. All five
commits are present in history (`2f80b2e`, `bcab25b`, `72661b5`, `6e5db71`, `7af0cad`), each
reachable and parented on `87e3028`. The baseline commit `bcab25b` precedes the sweep commit
`7af0cad`, satisfying the plan's ordering requirement that the baseline predate the change.
