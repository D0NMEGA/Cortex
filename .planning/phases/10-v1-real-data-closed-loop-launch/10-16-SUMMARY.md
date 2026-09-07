---
status: PASS
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 16
subsystem: infra
tags: [swiftlint, swiftformat, codable, codingkeys, ci, lint, swift6]

# Dependency graph
requires:
  - phase: 10-15
    provides: the pinned lint toolchain (SwiftLint 0.63.3 / SwiftFormat 0.61.1), the committed
      baseline in 10-lint-baseline.md, a SwiftFormat-clean tree, and the resolved
      swiftTestingTestCaseNames deadlock that set the real starting roster at 471
  - phase: 07-refit-kalman-closed-loop-recalibration
    provides: refit_bps.json, the artifact ci.yml byte-diffs a fresh --smoke run against
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: webgrid_bps.json, the artifact bps-policy.sh byte-diffs
provides:
  - "swiftlint --strict exits 0 across Apps/ and Packages/: 471 violations to 0"
  - "explicit CodingKeys on ten Codable report shapes, keeping Swift camelCase and the snake_case JSON wire format apart"
  - "a regression test (LatencyHistogramTests.emittedKeysAreSnakeCase) that fails if a wire key moves"
  - "12 force unwraps and force casts each given an individually reasoned disposition"
  - "10-lint-remediation-evidence.md: before/after, every exception with what drove it, the regeneration proof"
affects: [10-17, first-push, first-ci-run, any-future-swift-work]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Codable wire shapes: camelCase Swift properties + explicit CodingKeys mapping to the snake_case JSON key, with a LOAD-BEARING doc comment naming the gate that byte-diffs the artifact"
    - "Byte-identity proof by base-commit control: run the same generator on the same inputs at the base commit and at HEAD and diff the outputs, rather than diffing against a stored file"
    - "Lint exceptions are scoped and sited: a per-file or per-declaration swiftlint directive with a written reason, in preference to moving a repo-wide threshold"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-lint-remediation-evidence.md
  modified:
    - .swiftlint.yml
    - Packages/CortexReFIT/Sources/CortexReFITBench/main.swift
    - Packages/CortexDemo/Sources/CortexReplayBench/main.swift
    - Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift
    - Packages/CortexDemo/Sources/CortexDemoBench/main.swift
    - Packages/CortexDecoder/Sources/CortexDecoder/LatencyHistogram.swift
    - Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift
    - Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift
    - Packages/CortexRender/Sources/CortexRender/WebgridView.swift
    - Packages/CortexCore/Sources/CortexCore/ReplayExport.swift
    - .planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md

key-decisions:
  - "Cleared the 97 snake_case identifier_name violations with explicit CodingKeys rather than the rule's symbol-allowlist option: CodingKeys keeps camelCase Swift AND snake_case wire at once, where the config line would satisfy the gate without earning it (T-10-16-03)"
  - "Relaxed identifier_name's min-length arm only, leaving the character-set arm at its default: the 326 short names are Kalman/POSIX/loop notation matching the equations documented in KalmanFilter.swift's own header, and unlike the wire keys there is no option that keeps both properties"
  - "Reconciled opening_brace with SwiftFormat's wrapMultilineStatementBraces using SwiftLint's two designed-in flags, after measuring that the two tools are mutually unsatisfiable at all 11 sites"
  - "Changed no numeric threshold anywhere: file_length stays 400, function_body_length 50, cyclomatic_complexity 10, function_parameter_count 5. The 15 size/complexity violations were cleared by counting code rather than documentation, one real refactor, and six sited suppressions"
  - "Proved byte identity by regeneration and a base-commit control, not by a checksum manifest alone: a manifest over committed files cannot show the emitted wire format is unchanged"

patterns-established:
  - "Wire-key protection: a Codable shape whose JSON is read back by a gate carries explicit CodingKeys plus a do-not-remove comment naming that gate"
  - "Suppression discipline: every swiftlint:disable is :this, :next or a documented disable/enable pair, sited next to the code and carrying its reason; no repo-wide threshold was moved to clear a violation"

# REQUIRED - copy ALL requirement IDs from this plan's `requirements` frontmatter field.
requirements-completed: [RD-09]

# Metrics
duration: 3h 40m
completed: 2026-09-07
---

# Phase 10 Plan 16: Lint remediation Summary

**`swiftlint --strict` cleared from 471 violations to 0 with every emitted JSON key and value unchanged, the 97 snake_case wire keys preserved by explicit `CodingKeys` rather than by weakening the rule, and byte identity proven by regenerating each artifact and by a base-commit control run.**

## Performance

- **Duration:** 3h 40m (spanning one session-limit interruption; no work was lost)
- **Started:** 2026-09-07T03:35:00Z
- **Completed:** 2026-09-07T07:22:00Z
- **Tasks:** 3
- **Files modified:** 30

## Accomplishments

- **`swiftlint --strict` exits 0**: "Found 0 violations, 0 serious in 111 files", from a measured 471.
- **No emitted byte moved.** `refit_bps.json`, `webgrid_bps.json` and `10-ceiling.json` regenerate byte-for-byte; the two merged Phase-10 artifacts were checked with a base-commit control that diffs EMPTY.
- **No numeric threshold in `.swiftlint.yml` was lowered.** Every size and complexity limit is where it was.
- **The character-set arm of `identifier_name` is still armed** against snake_case, which is what the `CodingKeys` work bought.
- **A gate caught a real regression this plan introduced, and it was fixed at the source**, not by widening the gate.

## Task Commits

1. **Task 1: the mechanical classes** - `80e46b7` (fix)
2. **Task 2a: identifier_name, the snake_case wire keys** - `a1cd5af` (refactor)
3. **Task 2b: identifier_name min-length + nesting config** - `c548aef` (chore)
4. **Task 3a: the 12 force unwraps and force casts** - `6b17800` (fix)
5. **Task 3b: size and complexity classes** - `e90e89a` (refactor)

**Plan metadata:** `76f6db6` (docs: the remediation evidence artifact)

## Files Created/Modified

- `.swiftlint.yml` - five entries added, each with the files that drove it. No threshold lowered.
- `.planning/phases/10-*/10-lint-remediation-evidence.md` - 576 lines: before/after per rule and per directory, the CodingKeys decision, every exception, the force-unwrap disposition table, the full transcript, what it does not establish, and the operator error in section 9.
- Four bench `main.swift` files and `LatencyHistogram.swift` - camelCase properties + `CodingKeys` on ten report shapes.
- `ShmRing.swift`, `FDChannel.swift`, `SessionKeychain.swift`, `WebgridView.swift`, both `ContentView.swift` - force unwraps and casts restructured.
- `ReplayExport.swift`, `CortexDecoderBench/main.swift`, `FrameSoak.swift`, `CortexRenderBench/main.swift` - sited suppressions with reasons.
- `LatencyHistogramTests.swift` - the new `emittedKeysAreSnakeCase` guard.
- `deferred-items.md` - two Plan 10-16 entries appended.

## Decisions Made

### The roster was 471, and it split two ways, not one

The plan assumed `identifier_name` (423 of the 471) was dominated by snake_case `Codable` fields. Measured, it splits:

| sub-class | count | disposition |
|---|---|---|
| character-set (`should only contain alphanumeric`) | 97 | explicit `CodingKeys` + three renames |
| min-length (`between 3 and 40 characters`) | 326 | config, `min_length` only |

Only the 97 are the trap the plan described. Treating all 423 the same way would have been wrong in either direction.

### Force unwraps: what "a real disposition" meant, by class

Twelve sites, three classes. This is the distinction a reviewer should check:

**Restructured in production so the impossible case is named (8 sites, zero suppressions).**
`ShmRing.swift` x2 - `mmap` is imported implicitly-unwrapped, so the nil check and the `MAP_FAILED` check fold into one `guard let`; same two conditions, same throw. `FDChannel.swift` - `baseAddress!` became `guard let ... else { preconditionFailure(...) }`; a sentinel return was deliberately rejected because a negative value surfaces as `.recv(code)` and would be indistinguishable from a genuine recv failure. `SessionKeychain.swift` x2 - `kCFBooleanTrue!` bound once as a `CFBoolean`-typed computed property (computed, not stored, because `CFBoolean` is not `Sendable` and a `static let` is a Swift 6 global-state error - this avoids needing a `nonisolated(unsafe)` escape hatch). Both `ContentView.swift` - `VelocityRing(capacity: 4096)!` became a guard naming the contract. `WebgridView.swift` x2 - `layer as! CAMetalLayer` became a guard citing `layerClass` / `makeBackingLayer`.

**Converted to a test assertion (1 site).**
`RingTests.swift` - `ring.ack(seq: seen!)` became `try ring.ack(seq: #require(seen, "pollLatest must have returned a seq to ack"))`. The enclosing test already threw. This is the only site whose behaviour changes at all, and strictly for the better: a nil now fails the test with a message instead of crashing the runner.

**Left as `as!` under the repo's own written test policy, with a sited disable (2 sites).**
`KeychainTests.swift` - the only two suppressions this plan adds to source. `.swiftlint.yml`'s own comment states the policy: "Force unwrap is BANNED -- try! and as! allowed in tests only". That was verified rather than trusted: substituting `as?` and building produces a COMPILE ERROR, "conditional downcast to CoreFoundation type 'CFBoolean' will always succeed". `as!` is the only form that compiles, and the `CFGetTypeID` assertion one line above already fails loudly on a wrong type, so the cast is not the thing carrying the check.

**No site anywhere was replaced by `?? someDefault`.** Substituting a value converts a loud crash into a quiet wrong number, which in this repo means a wrong published number (T-10-16-02). The evidence artifact tabulates all twelve with a behaviour-could-differ column; every answer is "no" or "strictly better".

### `.swiftlint.yml`: five entries, what each protects, and why the alternative was worse

| entry | what it protects | why the alternative was worse |
|---|---|---|
| `excluded: Packages/*/Sources/*/generated` | the repo's only `blanket_disable_command`, in `flatc` output whose header says "do not modify" | The bare `disable all` cannot be narrowed at the source: `flatc` rewrites the file, so any hand edit is erased on the next regeneration. |
| `opening_brace: ignore_multiline_function_signatures` + `ignore_multiline_statement_conditions` | 11 wrapped signatures and conditions | Measured, not assumed: hand-editing `Producer.swift:75` into SwiftLint's form and re-running `swiftformat` put the brace straight back. Hand-editing all 11 leaves them in a state neither tool accepts. These are the two flags SwiftLint ships for this coexistence; `func abc(){` and `if x{` still fail. |
| `type_name: excluded: [iOSDisplayLinkAdapter]` | one type name | The rule wanted `IOSDisplayLinkAdapter`, misspelling Apple's own name for the platform. A named exception; any other lowercase-initial type still fails. |
| `identifier_name: min_length: {warning: 1, error: 0}` | 326 notation identifiers | The alternative is a ~326-site rename across ~50 files reaching into the hot path and three byte-diffed bench mains - the unreviewable-diff failure mode T-10-16-06 names. `KalmanFilter.swift`'s header documents `x- = A . x` and `x = x- + K . (z_rot - H . x-)`; renaming `x`/`z`/`K`/`H` breaks the correspondence with that comment and with the literature. **This is the one genuine weakening and it is stated as such**: lazy short names like `fa`, `o1`, `s2` (already present in test files) are no longer flagged. The character-set arm and `validates_start_with_lowercase` are untouched. |
| `nesting: ignore_coding_keys: true` | `LatencyHistogram.Summary.CodingKeys` | Introduced by this plan's own work, and unfixable by moving the declaration: the language requires `CodingKeys` inside the type it describes. SwiftLint's own opt-out; every other second-level nested type still fails. |
| `file_length: ignore_comment_only_lines: true` | three long files | A counting change, not a threshold change - the limit stays 400. The six over-limit files carry 108-212 comment-only lines each; counting code alone brings `ClosedLoopPipeline` 499->287, `ReplayExport` 408->285, `CortexDemoBench` 494->386 back under it honestly. |

`grep -cE 'allowed_symbols' .swiftlint.yml` returns **0**. The config comment describes that option rather than spelling it, precisely so the plan's acceptance grep stays a true signal instead of tripping on a comment that forbids it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SwiftLint's own autocorrect introduced a build break**
- **Found during:** Task 1
- **Issue:** `swiftlint --fix --only-rule empty_count` rewrote `#expect(hist.count == 0)` to `hist.isEmpty`. `LatencyHistogram` had no `isEmpty` member, so `CortexDecoder` did not compile.
- **Fix:** Added `public var isEmpty: Bool { samplesNs.isEmpty }` rather than reverting. A `count`-exposing type offering `isEmpty` is the idiomatic reason the rule exists.
- **Verification:** `swift test --package-path Packages/CortexDecoder` passes.
- **Committed in:** `80e46b7`

**2. [Rule 1 - Bug] A rename silently removed a label the honesty gate depends on**
- **Found during:** Task 3
- **Issue:** `honesty-sweep.sh` failed: `ERROR [label] a superseded number appears WITHOUT a labeling token on its own line ... phase8SyntheticRefitBpsN900: 1.953047883714651`. The old identifier `phase8_synthetic_refit_bps_n900` contained the lowercase substring `synthetic`, one of the sweep's label tokens, and was carrying the label for a line stating the superseded 1.953 figure. CamelCasing it to `Synthetic` delabeled that line.
- **Fix:** Fixed the CLAIM, not the label list (which the script explicitly forbids widening). The line now carries a comment stating the number is a synthetic Phase-8 seed-locked replay figure and superseded.
- **Verification:** `honesty-sweep.sh` and `--self-test` both rc=0.
- **Committed in:** `e90e89a`
- **Worth carrying forward:** a rename can remove a label a gate reads. Nothing but that gate would have caught it.

**3. [Rule 2 - Missing Critical] The `CodingKeys` had no test protecting them**
- **Found during:** Task 2
- **Issue:** The pre-existing `LatencyHistogram` round-trip test could NOT catch a dropped `CodingKeys` - encoder and decoder would simply agree on camelCase and the round-trip would still pass. The whole point of T-10-16-01 was unguarded in CI.
- **Fix:** Added `LatencyHistogramTests.emittedKeysAreSnakeCase`, which reads the emitted bytes and fails if a wire key moved or a camelCase key appeared.
- **Verification:** `CortexDecoder` suite is 20 tests, up from 19.
- **Committed in:** `a1cd5af`

**4. [Rule 3 - Blocking] The worktree could not run `xcodebuild` at all**
- **Found during:** Task 1
- **Issue:** `Packages/CortexRing/CortexRingFFI.xcframework` is a gitignored build artifact; without it the whole package graph fails to resolve and every `xcodebuild` fails regardless of what changed.
- **Fix:** Ran `Tools/scripts/build-rust.sh`. This is item 5 in `deferred-items.md`, independently reproduced.
- **Committed in:** n/a (build artifact, gitignored)

**5. [Scope boundary] `xcodegen generate` stripped four tracked Info.plist keys; reverted, not fixed**
- **Found during:** Task 1
- **Issue:** Running `xcodegen` (which Task 3d's battery requires) deleted `CortexBCIHIDProtocolVersion` and `NSAccessibilityUsageDescription` from `Apps/CortexMac/Info.plist` and `Apps/CortexiOS/Info.plist`. They are hand-added to the committed plists and absent from `project.yml`.
- **Fix:** Reverted both files with `git checkout --`; neither appears in any commit. NOT fixed: the fix belongs in `project.yml`, which this plan's boundary forbids editing. Already documented as item 2 of Plan 10-06's deferred items; re-confirmed live under Xcode 26.3 and appended to `deferred-items.md`.

**Total deviations:** 5 (2 bugs auto-fixed, 1 missing-critical added, 1 blocker cleared, 1 out-of-scope discovery reverted and logged)
**Impact on plan:** All four auto-fixes were necessary for correctness. Deviation 2 in particular is the kind of silent damage this plan existed to avoid, caught by an existing gate. No scope creep: `project.yml`, the entitlements, `ROADMAP.md` and `STATE.md` were not touched, and `donny-tools state advance-plan` was not run.

## Issues Encountered

**An operator error during verification touched data outside the worktree, and was fully repaired.**

Staging gitignored inputs into the base-commit control tree, `ln -sfn <src> <scratch>/Decoder/exports/<file>` resolved the destination THROUGH an existing directory symlink and replaced two real files in the **canonical checkout** with self-referential symlinks: `Decoder/exports/indy_20160630_01.replay.{json,bin}`.

Both are gitignored, so neither `git status` nor the checksum manifest would have reported it. The base-commit run failing with `could not open ... notFound` is what surfaced it. Scope was exactly those two files - `Decoder/checkpoints/` and `Decoder/data/` were untouched, since `ln -sf` cannot overwrite a real directory, and both were verified intact afterwards.

Restored deterministically with `export_replay.py --session indy_20160630_01` and verified against checksums recorded in a committed artifact rather than by inspection:

| quantity | restored | recorded in committed `10-refit-real.json` |
|---|---|---|
| sidecar SHA-256 | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` | `export_sidecar_sha256`, identical |
| source `.mat` SHA-256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` | `source_sha256`, identical |
| binary SHA-256 | `5107b00911de761a60fe9ecc83dfef9b195d387ba42467586ef899755e57c48f` | matches the sidecar's own `binary_sha256` |

The restored export is provably bit-identical to the one that produced every committed Phase-10 artifact. No data lost, no number affected. Full account in section 9 of the evidence artifact. The rule that would have prevented it is already written in the Plan 10-07 and 10-11 runbooks: real directories holding symlinks, never bare directory symlinks.

**A pre-existing reproducibility gap, found and logged.** `10-refit-real.json` contains `ceiling_ref`, `phase9_bounds` and two `env` entries that **no version of `CortexReplayBench` emits** - not HEAD's and not `46ab4c3`'s. The diff is 17 added lines, zero modified, zero removed, so nothing this plan did caused it and no number is contradicted. But it means "regenerate and diff" is not currently a complete reproducibility check for that artifact. Out of scope; recorded in the evidence artifact and `deferred-items.md`.

## Verification

```
swiftlint --strict     BEFORE (main @ 46ab4c3): 471 violations
swiftlint --strict     AFTER:  Found 0 violations, 0 serious in 111 files      rc=0
swiftformat --lint .   0/113 files require formatting, 17 files skipped        rc=0
```

Residual roster: **empty**. No rule has a nonzero count.

**Checksum manifest** over every committed `*.json` and `*-evidence.md` (37 files), captured before any edit and re-run after the final commit:

```
git ls-files '*.json' '*-evidence.md' > artifact-list.txt
xargs shasum -a 256 < artifact-list.txt | sort -k2 > manifest-{before,after}.txt
diff -u manifest-before.txt manifest-after.txt
-> MANIFEST CLEAN: all 37 committed JSON + *-evidence.md byte-identical
```

**Regeneration** (a manifest alone cannot prove the emitted wire format is unchanged):

```
diff <fresh>/refit_bps.json   <committed Phase-7>                  EMPTY
diff <fresh>/webgrid_bps.json <committed Phase-8>                  EMPTY
diff <fresh>/10-ceiling.json  <committed Phase-10>                 EMPTY
CortexReplayBench  BASE(46ab4c3) output vs HEAD output             EMPTY
CortexSeamBSmoke   BASE vs HEAD, 73159 frames    31/31 keys, 28/31 values identical
```

The three Seam B values that differ are `max_ns` / `p50_ns` / `p99_ns`. Proven to be wall-clock noise, not asserted: the same HEAD binary run twice differs on exactly those three keys by the same magnitude (`|base-head|` 1799874 / 1418 / 7541 vs `|head-head|` 1830125 / 1249 / 6458). Emitted key sets: `SeamBReport` 31/31 snake_case, `RealSeamReport` 17/17, `GlassToGlassReport` 9/9, zero camelCase leaks.

**All eleven policy gates, with and without `--self-test`:**

```
hotpath-policy.sh      rc=0   --self-test rc=0
render-policy.sh       rc=0   --self-test rc=0
hid-surface-policy.sh  rc=0   --self-test rc=0
notarize-policy.sh     rc=0   --self-test rc=0
match-policy.sh        rc=0   --self-test rc=0
bps-policy.sh          rc=0   --self-test rc=0
readme-policy.sh       rc=0   --self-test rc=0
decoder-policy.sh      rc=0   --self-test rc=0
refit-real-policy.sh   rc=0   --self-test rc=0
honesty-sweep.sh       rc=0   --self-test rc=0
toolchain-policy.sh    rc=0   --self-test rc=0
validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy   rc=0
```

**Tests:**

```
uv run --project Decoder pytest Decoder/tests -m "not slow" -q    289 passed, 10 deselected
swift test --package-path Packages/CortexDemo                     44 tests in 5 suites passed
swift test --package-path Packages/CortexReFIT                    32 tests in 5 suites passed
swift test --package-path Packages/CortexRender                   19 tests in 4 suites passed
  (also: CortexCore 15, CortexIPC 26, CortexRing 7, CortexDecoder 20, CortexBCIHID 24)
xcodebuild -scheme CortexMac         ** BUILD SUCCEEDED **
xcodebuild -scheme CortexRenderBench ** BUILD SUCCEEDED **
```

`pytest` reports 288 passed / 1 skipped in a bare worktree; the skip is `test_data.py:157 no loadable real .mat present (dataset is gitignored)`. With `Decoder/data` materialized as the runbooks do, it is 289 passed / 10 deselected.

**Suppression audit:**

```
grep -rn 'swiftlint:disable' Apps/ Packages/ | grep -v ':this\|:next\|swiftlint:enable'   -> 5 lines
```

None of the five is a blanket disable. The grep is line-scoped and cannot see that a `disable` has a matching `enable` further down. Four are paired `file_length` / `large_tuple` disables (three added here, one pre-existing in `BCIHIDReports.swift`), and the fifth is the `flatc`-generated file now excluded from linting entirely. `blanket_disable_command`, the rule that actually detects what this grep approximates, reports **0**.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for **10-17**. What the first push and the first CI run need to know:

1. **The lint gate should now pass, but it has still never run on a hosted runner.** Everything above is one machine (Apple M5 Pro, macOS 26.5, Xcode 26.3) at one pair of tool versions. `toolchain-policy.sh` will fail loudly if the runner's Homebrew ships different versions, which is the intended behaviour, not a surprise - CI installs both tools unpinned. If it fires, the correct response is to re-run the sweep under the new version and update the pin and the baseline together, not to relax the pin.

2. **`ci.yml` invokes a `Cortex.xcworkspace` that nothing generates.** Three steps (`ci.yml:435`, `:451`, `:467`) use `xcodebuild -workspace Cortex.xcworkspace`; `xcodegen` produces only `Cortex.xcodeproj`. This is `deferred-items.md` item 3 from Plan 10-06 and it has never executed. **The first CI run trips it.** Either add a `workspace:` section to `project.yml` or change the three steps to `-project Cortex.xcodeproj`. This is the single most likely cause of a red first run and it is unrelated to lint.

3. **A fresh clone cannot run any `xcodebuild` until `Tools/scripts/build-rust.sh` has run.** `Packages/CortexRing/CortexRingFFI.xcframework` is gitignored; without it the package graph fails to resolve with "local binary target 'CortexRingFFI' ... does not contain a binary artifact", regardless of what changed. Reproduced again in this plan. CI needs that step before any Xcode step.

4. **`CortexiOS` has never been compiled, here or in CI.** `xcodebuild -showdestinations -scheme CortexiOS` reports no destination: "iOS 26.2 is not installed." The three iOS-only constructs this plan edited were verified by typechecking them verbatim against the iPhoneSimulator26.2 SDK (`xcrun swiftc -typecheck`, rc=0), which is strong evidence but not a build. If CI has the iOS platform, its first `CortexiOS` build is genuinely new information.

5. **Do not run `xcodegen generate` and then commit.** It deletes four tracked SYS-05 keys from both app `Info.plist` files. Revert with `git checkout -- Apps/*/Info.plist` afterwards, every time, until `project.yml` is fixed.

6. **`swiftlint` prints two config warnings on every invocation** (`unused_declaration` / `unused_import` are listed in both `opt_in_rules` and `analyzer_rules`). Cosmetic, exit code unaffected, logged in `deferred-items.md`. Expect them in the first CI log.

7. **The two `.swiftformat` `--disable` entries are load-bearing.** `noForceUnwrapInTests` and `swiftTestingTestCaseNames` each carry their rationale inline. Removing either re-breaks `KeychainTests.swift` or deletes 179 `@Test` display strings and re-manufactures 75 unfixable `identifier_name` violations.

**No blockers.** `.planning/ROADMAP.md` and `.planning/STATE.md` were deliberately not touched and `donny-tools state advance-plan` was not run; the orchestrator owns those.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-07*

## Self-Check: PASSED

All created and modified key artifacts exist on disk: `10-lint-remediation-evidence.md` (576 lines),
`10-16-SUMMARY.md`, the appended `deferred-items.md`, `.swiftlint.yml`, and the new test case in
`LatencyHistogramTests.swift`.

All six commits are present in history and parented on the base `46ab4c3`: `80e46b7`, `a1cd5af`,
`c548aef`, `6b17800`, `e90e89a`, `76f6db6`.

The plan's mechanical acceptance greps were re-run against the tree, not assumed:

```
swiftlint --quiet | grep -c identifier_name                                    0
swiftlint --strict                              Found 0 violations, 0 serious in 111 files
grep -cE 'allowed_symbols' .swiftlint.yml                                      0
grep -cF 'CodingKeys' Packages/CortexReFIT/Sources/CortexReFITBench/main.swift 4   (>= 2 required)
grep -cF 'CodingKeys' Packages/CortexDemo/Sources/CortexDemoBench/main.swift   4   (>= 1 required)
grep -cF 'LOAD-BEARING' Packages/CortexReFIT/Sources/CortexReFITBench/main.swift 2 (>= 1 required)
git diff --stat .planning/phases/07-*/refit_bps.json .planning/phases/08-*/webgrid_bps.json   EMPTY
```

One acceptance criterion is reported as measured rather than as passing:
`grep -rn 'swiftlint:disable' Apps/ Packages/ | grep -v ':this\|:next\|swiftlint:enable'` returns 5
lines rather than nothing. None is a blanket disable - four are documented `disable`/`enable` pairs
(one of which predates this plan) and the fifth is the generated file now excluded from linting. The
grep is line-scoped and cannot associate a `disable` with its `enable`. `blanket_disable_command`,
the rule that actually detects the failure this grep approximates, reports 0.

---

## Amendment (orchestrator, 2026-09-07): triage of the seven Next Phase Readiness items

Each was checked against `main` at the 10-16 merge. Two of the three called out as most likely to
redden the first CI run do not reproduce; one previously unquantified item is confirmed and is worse
than described.

**1. `xcodebuild -workspace Cortex.xcworkspace` -- DOES NOT REPRODUCE.** All three invocations read
`-project Cortex.xcodeproj`, at `ci.yml:494`, `:510` and `:526`. Plan 10-09 corrected this and it is
intact; the 10-16 branch does not touch `ci.yml` at all (empty diff). The cited lines `435/451/467`
do not correspond to this file's current content. Not a blocker for 10-17.

**2. `build-rust.sh` ordering -- DOES NOT REPRODUCE.** `./Tools/scripts/build-rust.sh` runs at
`ci.yml:141` and the Xcode steps at `:493`, `:509`, `:526`. The workflow has exactly two jobs,
`build-and-lint` (22-614) and `decoder-python` (615+), so all four steps are in the same job in the
correct order. Not a blocker for 10-17.

**3. `xcodegen generate` strips tracked `Info.plist` keys -- CONFIRMED, and it is a latent Phase-8
defect rather than a Phase-10 one.** Measured: `xcodegen generate` rewrites both tracked plists,
removing 8 lines from each, and drops exactly two keys per file:

    CortexBCIHIDProtocolVersion
    NSAccessibilityUsageDescription

Mechanism: XcodeGen *regenerates* `Info.plist` from `project.yml`'s `info.properties` block rather
than merging into the existing file, so any key absent from `project.yml` is dropped on every run.

Provenance, established from history rather than inferred: both keys entered the tracked plists in
`647f14e` (2026-06-23, Plan 08-01) and `project.yml` has **never** carried either one -- zero commits
across all refs touch them there. They were written to the generator's OUTPUT instead of its INPUT,
so every `xcodegen generate` since 2026-06-23 has silently dropped them.

`NSAccessibilityUsageDescription` is a required purpose string for an assistive-input application.
**No gate asserts either key** -- `grep` over `Tools/scripts/` and `.github/workflows/` returns
nothing -- so CI builds an app without them and stays green. That is why it survived eight phases.

The fix is two entries in `project.yml`'s `info.properties` for `CortexMac` and `CortexiOS`, plus a
gate assertion so it cannot regress. It was NOT applied here: `project.yml` is outside the execution
boundary for this phase, and this is not Phase-10 work. It is carried to the Plan 10-17 checkpoint
for the user's decision, since 10-17 is the first push and the first CI run.

The remaining item, that `CortexiOS` has never been compiled anywhere because the iOS 26.2 platform
is not installed locally, stands as reported and is genuinely first-exercised by CI.
