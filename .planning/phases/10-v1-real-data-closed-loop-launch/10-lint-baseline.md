# Phase 10 RD-09 evidence: the measured pre-remediation lint baseline

**Date:** 2026-09-07
**Result:** MEASURED. `swiftformat --lint .` reports **79 of 113 files require formatting** (1,869
reported violations, 16 files skipped) under the config as committed. `swiftlint --quiet` reports
**514 violations** on a clean tree. Both were taken under the versions now pinned in
`Tools/toolchain-versions.env`, at commit `2f80b2e`, before a single line was reformatted.

This artifact contains no decoder metric, no latency, and no BPS figure. Every number in it is a
count of lint findings produced by a named tool at a named version against a named commit, so no
device annotation applies.

---

## Why this exists

`10-CONTEXT.md` D-18 put the repo-wide SwiftLint `--strict` sweep and the first push in scope on an
**estimate**: "roughly 535 repo-root violations, including 67 in Phase-7 code that is currently
labeled green". An estimate cannot be the starting point of a remediation whose success claim is
"the gate now passes", because there is nothing to check the claim against. This artifact replaces
the estimate with a measurement.

It is committed **before** the formatter runs. The git order is the audit trail: this file's commit
precedes the sweep commit, so the baseline provably predates the change it is a baseline for
(threat T-10-15-06).

---

## Provenance

| Field | Value |
|-------|-------|
| **Machine** | Apple M5 Pro (`arm64`), macOS **26.5** |
| **SwiftFormat** | **0.61.1** (`swiftformat --version`) |
| **SwiftLint** | **0.63.3** (`swiftlint version`) |
| **Pin file** | `Tools/toolchain-versions.env`, asserted by `Tools/scripts/toolchain-policy.sh` |
| **Commit at measurement** | `2f80b2e889b8d6f82b20f4269d75a67e63cfc0e7` (`2f80b2e`) |
| **Working tree** | Clean except the two config edits described under "Config corrections" below |
| **`.build` present?** | **No.** No SwiftPM build directory existed anywhere under `Packages/` at measurement time. This is load-bearing; see "The `.build` scope bug". |
| **Determinism** | Both tools are deterministic over fixed input. Runs were repeated and produced identical counts. |

Both versions match `Tools/toolchain-versions.env` exactly, which is what makes these counts
reproducible rather than date-dependent. `brew install swiftformat swiftlint` is unpinned; a count
measured under one version and gated under another is not a baseline.

### Commands

```
swiftformat --version
swiftlint version
swiftformat --lint . 2>&1 | tail -3
swiftformat --lint . 2>&1 | sed -nE 's/.*error: \(([a-zA-Z]+)\).*/\1/p' | sort | uniq -c | sort -rn
swiftformat --lint . 2>&1 | grep -oE '^/[^:]+' | sed "s|$PWD/||" | sort -u | wc -l
swiftlint --quiet 2>/dev/null | wc -l
swiftlint --quiet 2>/dev/null | sed -E 's/.*\((.*)\)$/\1/' | sort | uniq -c | sort -rn
swiftlint --quiet 2>/dev/null | sed -E "s|^$PWD/||; s|/[^/]*\.swift.*$||" | cut -d/ -f1-2 | sort | uniq -c | sort -rn
```

Each tool was invoked **once** and its raw output captured to a file; the histogram pipelines above
were then run against that capture rather than re-invoking the tool three times. The pipelines are
byte-for-byte the ones listed, and both tools are deterministic, so the counts are identical to
running each line standalone. The per-directory rollups were computed in Python over the same
capture because the `sed`/`cut` pipeline collapses paths of differing depth inconsistently.

---

## The state of CI

**This gate has never executed.** Not once, in ten phases.

```
$ gh api repos/D0NMEGA/Cortex/actions/runs
{"total_count":0,"workflow_runs":[]}
```

That is `total_count: 0` -- zero workflow runs, ever. The repository has never been pushed. `origin/main` is not a known revision. Every prior phase's
"CI green" therefore recorded that the *wiring was present and locally exercised*, not that a run
had happened on a runner. `.github/workflows/ci.yml` triggers on both `push` and `pull_request`, so
the gate arms **on the first push (Plan 10-17)**, not only on the first pull request. There is no
opportunity to discover the true cost later and no partial-credit path: the first push either
passes 100% of `swiftformat --lint .` and `swiftlint --strict` or it fails visibly.

---

## SwiftFormat baseline

Measured against `.swiftformat` **as committed at `2f80b2e`** (i.e. including `--header strip`):

```
79/113 files require formatting, 16 files skipped.
```

1,869 reported violations. Rule histogram, highest first:

| count | rule | count | rule | count | rule |
|---|---|---|---|---|---|
| 483 | `indent` | 21 | `wrapFunctionBodies` | 5 | `redundantThrows` |
| 358 | `swiftTestingTestCaseNames` | 20 | `blankLinesBetweenImports` | 4 | `blankLinesBetweenScopes` |
| 315 | `fileHeader` | 18 | `redundantReturn` | 3 | `hoistTry` |
| 123 | `sortImports` | 17 | `semicolons` | 3 | `andOperator` |
| 84 | `consecutiveSpaces` | 15 | `conditionalAssignment` | 2 | `redundantVariable` |
| 81 | `docComments` | 15 | `blankLinesAtStartOfScope` | 2 | `redundantSendable` |
| 46 | `wrap` | 13 | `numberFormatting` | 2 | `noForceUnwrapInTests` |
| 42 | `wrapLoopBodies` | 11 | `wrapMultilineStatementBraces` | 1 | `preferKeyPath` |
| 38 | `wrapPropertyBodies` | 11 | `unusedArguments` | 1 | `preferCountWhere` |
| 31 | `redundantSelf` | 9 | `modifierOrder` | 1 | `hoistPatternLet` |
| 27 | `spaceAroundOperators` | 9 | `braces` | 1 | `elseOnSameLine` |
| 25 | `trailingCommas` | 5 | `wrapSingleLineComments` | | |
| 22 | `blankLineAfterImports` | 5 | `redundantType` | | |

Files requiring formatting, by directory (after the `--header ignore` correction below, 73 files):

| files | directory | files | directory |
|---|---|---|---|
| 18 | `Packages/CortexIPC` | 4 | `Apps/CortexDaemon` |
| 11 | `Packages/CortexRender` | 3 | `Apps/CortexRenderBench` |
| 10 | `Packages/CortexReFIT` | 3 | `Packages/CortexCore` |
| 9 | `Packages/CortexDecoder` | 2 | `Apps/CortexiOS` |
| 5 | `Packages/CortexBCIHID` | 2 | `Apps/CortexMac` |
| 5 | `Packages/CortexDemo` | 1 | `Tools/spikes` |

---

## The `--header strip` finding (threat T-10-15-05): the config destroys provenance

The plan's Task 3a required confirming, on a temp copy and **before** the repo-wide pass, that
`--header strip` leaves top-of-file provenance headers intact. It does not. The check was run and
**the STOP condition fired.**

`fileHeader` is 315 of the 1,869 reported violations, spread over 19 files. Every one of those 315
lines is a line SwiftFormat would **delete**. `--header strip` is not a quality check; it is a
mandate to remove the header comment block.

Verified empirically on temp copies (repo untouched), config copied alongside:

| file | header lines | outcome under `--header strip` |
|---|---|---|
| `Apps/CortexRenderBench/FrameSoak.swift` | 31 | **destroyed** -- the entire "what mode (a) measures vs what it does NOT" honesty framing, the D-05 determinism argument, and the on-panel-vs-offscreen distinction |
| `Apps/CortexRenderBench/GPUTimeHistogram.swift` | 30 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/CursorIntegrator.swift` | 27 | **destroyed** -- the D-04 "seam stays velocity-typed" rationale |
| `Packages/CortexRender/Sources/CortexRender/VelocityRing.swift` | 26 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift` | 25 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/LissajousProducer.swift` | 23 | destroyed |
| `Tools/spikes/keychain-access-group-spike/main.swift` | 21 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` | 20 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/WebgridView.swift` | 17 | destroyed |
| `Apps/CortexDaemon/main.swift` | 17 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/TargetChannel.swift` | 14 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/WebgridParams.swift` | 13 | destroyed |
| `Packages/CortexReFIT/Sources/CortexReFIT/CortexReFIT.swift` | 13 | destroyed |
| `Packages/CortexRender/Tests/CortexRenderTests/CursorIntegratorTests.swift` | 10 | destroyed |
| `Packages/CortexRender/Tests/CortexRenderTests/VelocityRingTests.swift` | 8 | destroyed |
| `Apps/CortexMac/App.swift` | 8 | destroyed |
| `Packages/CortexRender/Sources/CortexRender/CortexRender.swift` | 5 | destroyed |
| `Packages/CortexCore/Sources/CortexCore/AppGroup.swift` | 4 | destroyed |
| `Apps/CortexiOS/App.swift` | 3 | destroyed |
| **total** | **315** | |

`Packages/CortexReFIT/Sources/CortexReFIT/KalmanFilter.swift`, the file the plan named as the
sample, is **not** in this list and its 8-line provenance header survives untouched -- the plan's
empirical note about it was correct, but it was not representative. SwiftFormat's `fileHeader` rule
only treats a top-of-file comment as a *header* when a blank line separates it from the first
declaration or import. `KalmanFilter.swift` has no such blank line, so its comment is read as
attached documentation; the 19 files above do, so theirs are read as strippable headers. The
distinction is invisible from the config and is exactly why the plan required a sample check.

The plan's instruction for this branch is explicit: "If a header IS stripped, STOP: `--header strip`
would be destroying provenance comments, and the correct response is to change the config (or add
`--header ignore`) deliberately, not to accept the loss."

**Correction applied:** `.swiftformat` `--header strip` -> `--header ignore`. Verified on the same
temp copies: all three sampled headers survive verbatim and every other rule still applies.

**Stated plainly, because it cuts against the remediation's own headline:** this correction removes
315 violations from the SwiftFormat count without fixing anything. Post-correction the baseline is
**73 of 113 files, 1,551 violations**. Those 315 are **not** counted as remediated anywhere in this
phase. The alternative was deleting 315 lines of provenance from a repository whose entire
discipline is that every published number carries the record of where it came from, and no third
option preserves the headers while satisfying `fileHeader` short of replacing 19 bespoke provenance
blocks with one boilerplate stamp.

---

## SwiftLint baseline

```
$ swiftlint --quiet | wc -l
514
```

Exit code 2 (SwiftLint's error-severity code). Severity split: **301 error, 213 warning**. The four
lines on stderr are pre-existing configuration warnings (`unused_declaration` and `unused_import`
each listed in both `opt_in_rules` and `analyzer_rules`), not violations.

By rule:

| count | rule | count | rule |
|---|---|---|---|
| 423 | `identifier_name` | 3 | `cyclomatic_complexity` |
| 48 | `sorted_imports` | 2 | `opening_brace` |
| 8 | `force_unwrapping` | 2 | `function_parameter_count` |
| 6 | `file_length` | 1 | `type_name` |
| 5 | `large_tuple` | 1 | `static_over_final_class` |
| 4 | `redundant_type_annotation` | 1 | `implicit_optional_initialization` |
| 4 | `function_body_length` | 1 | `empty_count` |
| 4 | `force_cast` | 1 | `blanket_disable_command` |

By top-level directory:

| count | directory | count | directory |
|---|---|---|---|
| 135 | `Packages/CortexReFIT` | 28 | `Packages/CortexDecoder` |
| 104 | `Packages/CortexDemo` | 6 | `Apps/CortexiOS` |
| 92 | `Packages/CortexIPC` | 6 | `Packages/CortexCore` |
| 71 | `Packages/CortexRender` | 2 | `Apps/CortexMac` |
| 37 | `Apps/CortexDaemon` | 0 | `Packages/CortexRing` |
| 33 | `Apps/CortexRenderBench` | 0 | `Packages/CortexBCIHID` |

### The two facts that shape the remediation

**1. `identifier_name` is 423 of 514 (82%), and it is two different problems.**

| sub-class | count | what it is |
|---|---|---|
| "should only contain alphanumeric" | **97** | snake_case identifiers |
| "should be between 3 and 40 characters" | **326** | names shorter than 3 characters |
| other | 0 | |

The 97 snake_case violations are concentrated in seven files, four of which are bench executables
whose job is to emit JSON:

| count | file |
|---|---|
| 35 | `Packages/CortexDemo/Sources/CortexReplayBench/main.swift` |
| 24 | `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift` |
| 17 | `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` |
| 14 | `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` |
| 4 | `Packages/CortexDecoder/Sources/CortexDecoder/LatencyHistogram.swift` |
| 2 | `Packages/CortexRender/Sources/CortexRender/CursorVelocity.swift` |
| 1 | `Packages/CortexReFIT/Sources/CortexReFIT/IntentRotation.swift` |

**These are not style violations. They are the serialized schema.** Names such as `schema_version`,
`data_source`, `source_sha256`, `bps_n900`, `refit_minus_kalman_only` and `superseded_synthetic` are
`Encodable` stored properties, and Swift's synthesized `CodingKeys` makes the property name the JSON
key verbatim. Renaming any of them changes the bytes of `10-replay.json`, `10-refit-real.json`,
`webgrid_bps.json` or `refit_bps.json`, each of which is under a byte-identity check. Plan 10-16
must clear them **without** a byte-diff in any emitted artifact -- either a scoped config exception
or explicit `CodingKeys` that preserve the wire names while renaming the Swift properties.

The 326 short-name violations are the opposite kind of work: `dt`, `vx`, `vy`, `k0`..`k5`,
`a0`..`a5`, `h0`, `h1` in the Kalman and SIMD math, where the two-character names mirror the
published state-space notation. 286 of the 423 are at **error** severity (SwiftLint's
`identifier_name` escalates names of two characters or fewer), so `--strict` is not what makes them
fatal; they are already fatal.

**2. `force_unwrapping` is configured at ERROR severity**, with the comment "Force unwrap is BANNED
-- try! and as! allowed in tests only". Those 8 are not style and cannot be waived by a formatter:

```
Apps/CortexiOS/ContentView.swift:31:42
Apps/CortexMac/ContentView.swift:106:42
Packages/CortexIPC/Tests/CortexIPCTransportTests/RingTests.swift:162:25
Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift:151:23
Packages/CortexIPC/Sources/CortexIPCTransport/ShmRing.swift:174:23
Packages/CortexIPC/Sources/CortexIPCTransport/FDChannel.swift:61:86
Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift:91:66
Packages/CortexIPC/Sources/CortexIPCSession/SessionKeychain.swift:121:53
```

Six of the eight are in production IPC code on the hot path.

### The Phase-7 subset

```
$ swiftlint --quiet | grep -c 'Packages/CortexReFIT'
135
```

D-18 specifically names Phase-7 code as "currently labeled green". It carries **135** violations,
129 of them `identifier_name` -- overwhelmingly the `k0`..`k5` / `a0`..`a5` / `h0` / `h1` gain-matrix
scalars that `KalmanFilter.swift` unpacks from `KalmanConstants.swift`. The Phase-7 "green" label was
accurate for what it claimed (its tests and its policy gates pass); it never included a lint run,
because no lint run has ever happened.

---

## The `.build` scope bug (found while measuring)

`.swiftlint.yml` excluded `.build` for exactly four packages -- `CortexCore`, `CortexIPC`,
`CortexRender`, `CortexDecoder` -- the four that existed when the list was written in Phase 1.
`CortexReFIT`, `CortexRing`, `CortexDemo` and `CortexBCIHID` were added in later phases and were
never added to the list. SwiftLint descends into hidden directories, so once a `swift test` has
created those `.build` directories, SwiftLint lints **vendored dependency checkouts and generated
sources** as if they were this repository's code.

This matters here because `ci.yml` runs `swift test --package-path Packages/CortexRing` and the
other package suites **before** the `swiftlint --strict` step, so on a runner the `.build`
directories always exist by the time the gate runs. It also matters for Plan 10-16, whose entire job
is to drive this count to zero: a roster that shifts depending on whether a build has happened is
not a roster.

Proven with a probe file (`let q = 1` / `let zz = 2`, 2 violations) placed inside the `.build` of
each of the four unexcluded packages:

| config | total | of which inside `.build` |
|---|---|---|
| as committed at `2f80b2e` | **522** | **8** |
| with `Packages/*/.build` | **514** | **0** |

Control: the same probe inside `Packages/CortexCore/.build`, which *was* excluded, produced 0 in
both runs. The probes were deleted after measurement.

**Correction applied:** the four-entry enumeration in `.swiftlint.yml` is replaced by the glob
`Packages/*/.build`, which cannot go stale as packages are added.

`.swiftformat` needed no equivalent change and did not get one. Measured: SwiftFormat reports the
same 113 files with and without the probes present and never names the probe file, because it does
not descend into hidden directories at all. Its enumerated `.build` excludes are inert. Changing
them was tried, measured as a no-op, and reverted rather than committed as a cosmetic diff.

---

## Comparison to the estimate

D-18 put this work in scope on a figure of **around 535** violations, "including 67 in Phase-7 code".

| | estimate | measured |
|---|---|---|
| SwiftLint total | around 535 | **514** (clean tree) / **522** (with `.build` present, pre-fix) |
| Phase-7 (`CortexReFIT`) subset | 67 | **135** |
| SwiftFormat files | 71 of 101 | **79 of 113** (as committed) / **73 of 113** (post `--header ignore`) |

The SwiftLint total is within 4% of the estimate. The Phase-7 subset is **roughly double** what D-18
stated. The SwiftFormat file count is higher than the plan's interface block because Plans 10-01
through 10-14 added Swift files after that table was written; the plan anticipated this and
instructed re-measurement rather than reuse.

Two per-directory rows in the plan's interface table -- `Packages/CortexRing 30` and
`Packages/CortexBCIHID 30` -- measure **0** here. Both are packages whose `.build` was unexcluded,
and both were measured on a machine that had run their test suites. The most likely reading is that
those 60 were violations in build products rather than in either package's source; both packages'
tracked sources are clean. This is stated as a reading of the evidence, not as an established fact
about how the earlier measurement was taken.

---

## Remediation plan

Split across two plans because the two halves are different kinds of work.

**Plan 10-15 (this plan): SwiftFormat.** Mechanical and auto-fixable in a single `swiftformat .`
pass. Correctness is established negatively -- by running all eight package test suites, both bench
byte-identity checks and all eleven policy gates afterwards and showing nothing moved.

**Plan 10-16: SwiftLint.** Not mechanical. 97 of the 423 `identifier_name` violations are serialized
JSON keys under byte-identity checks and must be cleared without changing an emitted byte; 326 are
short mathematical names where the rename either loses the correspondence to the published notation
or is genuinely an improvement, decided per site; and the 8 `force_unwrapping` violations are real
code changes at error severity in production IPC. Grouped by rule class, verified per file.

---

## Config corrections committed alongside this baseline

Both predate the sweep and are committed separately from it, so the sweep commit contains only
`.swift` files.

| file | change | why |
|---|---|---|
| `.swiftformat` | `--header strip` -> `--header ignore` | Stops the formatter deleting 315 lines of provenance across 19 files (T-10-15-05). Reduces the SwiftFormat count by 315 without remediating anything; recorded as such above. |
| `.swiftlint.yml` | four `.build` entries -> `Packages/*/.build` | Stops SwiftLint reporting violations inside vendored dependency checkouts once a build has run. Proven to bite (522 -> 514 with probes present). |

Neither correction weakens a policy gate. `Tools/scripts/*-policy.sh` and `honesty-sweep.sh` are
untouched by both, and all eleven gates plus their self-tests are re-run after the sweep.
