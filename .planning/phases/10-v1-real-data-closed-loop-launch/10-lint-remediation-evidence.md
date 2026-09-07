# Phase 10 Plan 16 - lint remediation evidence

`swiftlint --strict` cleared from 471 violations to 0 across `Apps/` and `Packages/`, with every
emitted JSON byte and every serialized key unchanged.

**Machine.** Apple M5 Pro, macOS 26.5, Xcode 26.3 (Swift 6.2.4).
**Toolchain, pinned by `Tools/toolchain-versions.env` and gated by `Tools/scripts/toolchain-policy.sh`:**
SwiftLint 0.63.3, SwiftFormat 0.61.1. Both confirmed with `swiftlint version` / `swiftformat --version`
before the sweep. The baseline in `10-lint-baseline.md` was taken under these same two versions.
**Date.** 2026-09-07. **Base commit.** `c3d406a`.

---

## 1. Before and after

### 1.1 The starting roster is 471, not the baseline's 526

`10-lint-baseline.md` recorded **526** violations. That number was taken before Plan 10-15's
SwiftFormat sweep and before the orchestrator's post-merge fix. Two things moved it:

- 10-15's `swiftformat .` pass cleared the whole mechanical tier at the source: `sorted_imports` 48,
  `duplicate_imports` 24, `trailing_newline` 12, `trailing_whitespace` 8,
  `non_optional_string_data_conversion` 8, `convenience_type` 8, `void_return` 8,
  `redundant_type_annotation` 4 all went to zero without a SwiftLint fix.
- The same sweep MANUFACTURED 75 `identifier_name` violations by deleting `@Test("description")`
  display strings into backticked function names. Disabling `swiftTestingTestCaseNames` in
  `.swiftformat` removed them again, taking the roster from 546 to 471.

Re-measured on `c3d406a` at the start of this plan: **471**. That is the honest starting point and
every "before" figure below is against it.

### 1.2 By rule

| rule | 10-lint-baseline (526) | 10-16 start (471) | after | how |
|---|---|---|---|---|
| `identifier_name` | 350 | 423 | **0** | 97 by `CodingKeys` + renames; 326 by the min-length config |
| `sorted_imports` | 48 | 0 | 0 | cleared by 10-15's formatter sweep |
| `force_unwrapping` | 24 | 8 | **0** | 8 individual source fixes |
| `duplicate_imports` | 24 | 0 | 0 | cleared by 10-15 |
| `trailing_newline` | 12 | 0 | 0 | cleared by 10-15 |
| `file_length` | 9 | 6 | **0** | 3 by comment-line counting, 3 by paired disables |
| `void_return` | 8 | 0 | 0 | cleared by 10-15 |
| `trailing_whitespace` | 8 | 0 | 0 | cleared by 10-15 |
| `non_optional_string_data_conversion` | 8 | 0 | 0 | cleared by 10-15 |
| `convenience_type` | 8 | 0 | 0 | cleared by 10-15 |
| `large_tuple` | 5 | 5 | **0** | 3 named structs |
| `redundant_type_annotation` | 4 | 0 | 0 | cleared by 10-15 |
| `force_cast` | 4 | 4 | **0** | 2 source fixes, 2 scoped disables |
| `opening_brace` | 3 | 11 | **0** | config reconciliation with SwiftFormat |
| `function_parameter_count` | 2 | 2 | **0** | 1 real fix, 1 scoped disable |
| `function_body_length` | 2 | 4 | **0** | 4 scoped disables |
| `cyclomatic_complexity` | 2 | 3 | **0** | 3 scoped disables |
| `type_name` | 1 | 1 | **0** | one named exception |
| `static_over_final_class` | 1 | 1 | **0** | source fix |
| `implicit_optional_initialization` | 1 | 1 | **0** | autocorrect |
| `empty_count` | 1 | 1 | **0** | added `LatencyHistogram.isEmpty` |
| `blanket_disable_command` | 1 | 1 | **0** | excluded the generated directory |
| **total** | **526** | **471** | **0** | |

Two rules fired transiently on this plan's own edits and were cleared in the same task:
`nesting` (1, from a `CodingKeys` nested two levels deep) and `orphaned_doc_comment` (2, from a
comment placed between a `///` block and its declaration).

### 1.3 By top-level directory

| directory | 10-16 start | after |
|---|---|---|
| `Packages/CortexReFIT` | 131 | 0 |
| `Packages/CortexDemo` | 104 | 0 |
| `Packages/CortexIPC` | 74 | 0 |
| `Packages/CortexRender` | 62 | 0 |
| `Apps/CortexRenderBench` | 32 | 0 |
| `Packages/CortexDecoder` | 29 | 0 |
| `Apps/CortexDaemon` | 29 | 0 |
| `Packages/CortexCore` | 5 | 0 |
| `Apps/CortexiOS` | 4 | 0 |
| `Apps/CortexMac` | 1 | 0 |

---

## 2. The CodingKeys decision

### 2.1 What the class actually was

The plan expected `identifier_name` to be dominated by snake_case `Codable` field names. Measured, it
splits two ways, and the split matters because the two halves have different correct answers:

| sub-class | count | what it is |
|---|---|---|
| character-set (`should only contain alphanumeric`) | **97** | snake_case JSON wire keys |
| min-length (`should be between 3 and 40 characters`) | **326** | 1- and 2-character notation |

Only the 97 are the trap the plan described. They were cleared the expensive way. The 326 are a
different problem and are treated separately in section 3.

### 2.2 Why not the one-line config fix

Clearing the 97 by adding this rule's symbol-allowlist option would have satisfied the gate in one
line while defeating its purpose (threat T-10-16-03), and it would have thrown away a property that
was available for free: `CodingKeys` lets the Swift names AND the wire format both be right at the
same time. `grep -cE 'allowed_symbols' .swiftlint.yml` returns **0**; the config comment describes
the option rather than spelling it, precisely so that acceptance grep stays a true signal instead of
tripping on a comment.

### 2.3 What was done

Ten `Codable` / `Encodable` shapes got camelCase properties plus an explicit `CodingKeys` enum
mapping each property back to its exact pre-existing snake_case key:

| file | types | keys preserved |
|---|---|---|
| `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` | `RefitBPS`, `WebgridBPSReport` | 14 |
| `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` | `RealSeamReport`, `GlassToGlassReport` | 13 |
| `Packages/CortexDemo/Sources/CortexReplayBench/main.swift` | `ArmReport`, `DeltaTriple`, `Deltas`, `References`, `SupersededSynthetic`, `RefitRealReport` | 32 |
| `Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift` | `SeamBReport` | 24 |
| `Packages/CortexDecoder/Sources/CortexDecoder/LatencyHistogram.swift` | `Summary` | 4 |

Each `CodingKeys` carries a doc comment naming the gate that byte-diffs the artifact, so the next
reader does not "simplify" it away.

Renames were applied to **code positions only**. String literals and comments keep their snake_case
spelling, which is correct: the wire format did not change, so a key quoted in a disclosure string or
a doc comment is still accurate. Two follow-on passes were needed because of that split - string
INTERPOLATIONS (`\(payload.n_targets)`) are code inside a string literal and had to be renamed
separately (37 occurrences across three files), and the compiler found every one of them.

Three snake_case identifiers were **not** `Codable` fields and were renamed outright:

- `CursorVelocity.ts_ns` -> `tsNs`, 28 code sites. It is held in a typed
  `UnsafeMutableBufferPointer<CursorVelocity>`, so no memory layout depends on the name, and the
  FlatBuffers accessor is already spelled `tsNs`, so this removed a split spelling.
- `IntentRotation`'s internal parameter `r_acq` -> `rAcq`. The external argument label
  `acquisitionRadius` is unchanged, so no call site moved. Prose keeps `r_acq`, the literature symbol.
- The two `CortexRing` sites `frame.pointee.ts_ns` and `frame.ts_ns` were deliberately **excluded**:
  that is the C FFI struct member from the Rust header and must keep its C spelling. Verified present
  and unchanged after the rename pass.

### 2.4 The proof the bytes did not move

A checksum manifest over the committed files proves only that checked-in bytes were not edited. It
does NOT prove the emitted wire format is unchanged, because those files are checked in, not
regenerated. So every artifact was regenerated from the remediated code and diffed.

**(a) The three artifacts a generator emits directly: byte-identical.**

```
find Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench -type f -delete
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke                    # rc=0
diff Packages/CortexReFIT/.bench/refit_bps.json \
     .planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json             # EMPTY
diff Packages/CortexReFIT/.bench/webgrid_bps.json \
     .planning/phases/08-apple-bci-hid-integration-distribution-v0-ship/webgrid_bps.json   # EMPTY

uv run --project Decoder python Decoder/scripts/webgrid_ceiling.py \
  --session indy_20160630_01 --out <scratch>/10-ceiling-REPRO.json                         # rc=0
diff <scratch>/10-ceiling-REPRO.json \
     .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json                   # EMPTY
```

`refit_bps.json`, `webgrid_bps.json` and `10-ceiling.json` all reproduce **byte-for-byte**.
`10-ceiling.json` comes from a Python script and is outside the Swift changes, but it was
regenerated rather than assumed.

**(b) `10-replay.json` and `10-refit-real.json` are MERGED artifacts, so the honest check is a
base-commit control.** Neither is a direct generator emission: `10-refit-real.json` carries
`ceiling_ref`, `phase9_bounds` and two extra `env` entries that no version of `CortexReplayBench`
emits, and `10-replay.json`'s 22 top-level keys merge a Seam A and a Seam B run. Diffing a merged
artifact against one generator's output measures the merge, not the rename. The control that isolates
the rename is to run the SAME generator on the SAME inputs at the base commit and at HEAD and diff
the two outputs; `c3d406a` was extracted with `git archive` into a scratch tree for this.

```
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
swift run -c release --package-path Packages/CortexDemo CortexReplayBench --out <out>

CORTEX_REPLAY_EXPORT=... CORTEX_MODEL_URL=... \
swift run -c release --package-path Packages/CortexDemo CortexSeamBSmoke --frames 73159 --out <out>
```

| generator | comparison | result |
|---|---|---|
| `CortexReplayBench` (feeds `10-refit-real.json`) | BASE output vs HEAD output | **EMPTY diff** |
| `CortexReplayBench` | HEAD output vs committed artifact | 0 lines only in HEAD, 0 changed lines, 17 lines only in the committed file - the pre-existing merge additions |
| `CortexSeamBSmoke --frames 73159` (feeds `10-replay.json`) | BASE output vs HEAD output | 31/31 keys identical, 28/31 values identical; the 3 that differ are wall-clock timings - see below |
| `CortexDemoBench --real` (`RealSeamReport`) | emitted key set | 17/17 snake_case, no camelCase leak |
| `CortexDemoBench --smoke` (`GlassToGlassReport`) | emitted key set | 9/9 snake_case, no camelCase leak |
| `CortexSeamBSmoke` (`SeamBReport`) | emitted key set | 31/31 snake_case, no camelCase leak |

**The three Seam B differences are measurement noise, proven rather than asserted.** The same HEAD
binary was run a second time on identical inputs. It differs from its own first run on exactly the
same three keys, by the same magnitude:

```
key            BASE     HEAD run1    HEAD run2   |base-h1|      |h1-h2|
max_ns      5901791       4101917      2271792     1799874      1830125
p50_ns       133459        132041       130792        1418         1249
p99_ns       173584        181125       174667        7541         6458
```

`|BASE-HEAD|` is the same order as `|HEAD-HEAD|` on one unchanged binary, so the base-vs-head
difference is wall-clock variance in a latency histogram, not an effect of the rename. Across all
three runs the key SET is identical (31 keys), 28 of 31 values are byte-identical, and no key
anywhere contains an uppercase character.

**(c) Neither committed artifact was edited.** All 37 files in the checksum manifest of section 5 are
unchanged, including all five artifacts above.

A regression test was added because none of the above runs in CI on every push:
`LatencyHistogramTests.emittedKeysAreSnakeCase`. The pre-existing round-trip test could NOT catch a
dropped `CodingKeys` - encoder and decoder would simply agree on camelCase and the round-trip would
still pass. The new case reads the emitted bytes and fails if a wire key moved.

### 2.5 One real regression, caught by a gate and fixed

`honesty-sweep.sh` failed after the rename commit:

```
ERROR [label] a superseded number appears WITHOUT a labeling token on its own line.
  Packages/CortexDemo/Sources/CortexReplayBench/main.swift:713: [1.953]   phase8SyntheticRefitBpsN900: 1.953047883714651,
```

The identifier `phase8_synthetic_refit_bps_n900` contained the lowercase substring `synthetic`, which
is one of the sweep's label tokens, and it was carrying the label for a line stating the superseded
1.953 figure. CamelCasing it to `Synthetic` silently delabeled that line. Fixed by fixing the CLAIM,
not by widening the label list (which the script explicitly forbids): the line now carries a comment
stating the number is a synthetic Phase-8 seed-locked replay figure and superseded. `honesty-sweep.sh`
and `--self-test` both exit 0.

This is worth recording as a general hazard: **a rename can remove a label a gate depends on.** The
gate caught it. Nothing else would have.

---

## 3. Every `.swiftlint.yml` change, with what drove it

Five entries. **No numeric threshold was lowered anywhere.** `file_length` is still 400,
`function_body_length` 50, `cyclomatic_complexity` 10, `function_parameter_count` 5, `identifier_name`
`max_length` 40/60.

| entry | kind | what drove it |
|---|---|---|
| `excluded: Packages/*/Sources/*/generated` | path exclusion | `CortexIPCSession/generated/sample_generated.swift`, flatc output whose header says "do not modify". Its `swiftlint:disable all` was the repo's only `blanket_disable_command`, and it cannot be narrowed at the source because `flatc` rewrites the file. |
| `opening_brace: ignore_multiline_function_signatures` + `ignore_multiline_statement_conditions` | rule reconciliation | 11 sites, all SwiftFormat's `wrapMultilineStatementBraces`. See 3.1. |
| `type_name: excluded: [iOSDisplayLinkAdapter]` | named exception | `iOS` is Apple's spelling; the rule wanted `IOSDisplayLinkAdapter`. One named type; any other lowercase-initial type still fails. |
| `identifier_name: min_length: {warning: 1, error: 0}` | rule relaxation | 326 violations of mathematical and systems notation. See 3.2 - this is the one genuine weakening in the plan. |
| `nesting: ignore_coding_keys: true` | false-positive opt-out | `LatencyHistogram.Summary.CodingKeys`, two levels deep because the language requires `CodingKeys` inside the type it describes. Introduced by this plan's own work. |
| `file_length: ignore_comment_only_lines: true` | counting change | Thresholds unchanged; documentation stops counting toward "this file does too much". See 3.3. |

### 3.1 The SwiftFormat / SwiftLint brace conflict, measured not assumed

SwiftFormat's `wrapMultilineStatementBraces` puts the opening brace on its own line when a signature
or condition is wrapped; SwiftLint's `opening_brace` wants it on the declaration line. Rather than
assume, the conflict was reproduced: `Apps/CortexDaemon/Producer.swift:75` was hand-edited into
SwiftLint's preferred form and `swiftformat` was re-run on it. The brace was put straight back on its
own line. The two tools are mutually unsatisfiable at all 11 sites, so hand-editing them would leave
the files in a state neither tool accepts.

SwiftLint ships both flags for exactly this coexistence, so the linter yields on the wrapped case
only. `func abc(){`, `if x{`, and a stray brace after a single-line declaration are all still caught.
Eight sites were wrapped signatures, three were wrapped conditions; all eleven are named in the config
comment.

### 3.2 The min-length relaxation, and what it costs

This is the one place where a rule got weaker, so it is stated plainly rather than buried.

**Population.** 326 violations: 189 at error severity (1-character names), 139 at warning (2-character).
They are notation, not lazy naming - the ReFIT filter's `x z a h k p q r s A H K a0..a5 h0 h1 k0..k5
hx`, kinematics `dt dx dy vx vy x0 t0 t1`, POSIX and Mach `fd rc cb kq kh ns ts`, and loop indices
`i j k n m`. `KalmanFilter.swift`'s own file header documents the per-tick ordering as
`x- = A . x` and `x = x- + K . (z_rot - H . x-)`; renaming those symbols breaks the correspondence
between the code, that comment, and the ReFIT literature the constants were solved against.

**Why not rename.** ~326 sites across ~50 files, reaching into the hot path (`ShmRing.swift`,
`Doorbell.swift`) and into the three bench mains whose JSON output is byte-diffed - the
unreviewable-diff failure mode this plan's own threat register names as T-10-16-06.

**Why this is a different judgement from the 97.** For the wire keys, `CodingKeys` kept both
properties: camelCase Swift and snake_case JSON. There is no equivalent here. Renaming `x` to
`stateVector` trades one property (linter satisfaction) for another (correspondence with the
equations). When both options lose something, the config change loses less.

**What it costs, stated:** SwiftLint no longer flags a genuinely lazy short name. Some already exist
in the test files - `fa`, `fb`, `o1`, `o2`, `s1`, `s2`, `pb`, `pf`, `va`, `vb`. Code review is now the
only check on those. Length was never a good proxy for clarity in this codebase, but this is a real
reduction in coverage and a reviewer should weigh it rather than take it as free.

**What was NOT touched:** the character-set arm and `validates_start_with_lowercase` stay at their
defaults. The character-set arm is the one that polices the snake_case wire keys, and the 97 were
cleared with `CodingKeys` specifically so it could stay armed against them.

### 3.3 file_length counts code, not documentation

The thresholds did not move. `ignore_comment_only_lines` stops a file's doc comments from counting
toward a rule about a file doing too much. It matters here because this repo documents heavily:

| file | total | comment-only | code | outcome |
|---|---|---|---|---|
| `CortexDemo/ClosedLoopPipeline.swift` | 499 | 212 | 287 | under 400, no suppression |
| `CortexCore/ReplayExport.swift` | 408 | 123 | 285 | under 400, no suppression |
| `CortexDemoBench/main.swift` | 494 | 108 | 386 | under 400, no suppression |
| `CortexReFITBench/main.swift` | 684 | 192 | 430 | paired disable |
| `CortexSeamBSmoke/main.swift` | 812 | 158 | 587 | paired disable |
| `CortexReplayBench/main.swift` | 834 | 134 | 617 | paired disable |

The three still over on code alone got a paired `disable`/`enable` in the file rather than a threshold
bump, so the other ~110 files keep the 400 limit. All three are top-level `main.swift` files: Swift
only permits top-level statements in a file with that name, so the run sequence cannot move to a
sibling. Two of the three emit artifacts that are byte-diffed against committed files, and splitting
those for a length rule is exactly the trade this plan was instructed not to make.

---

## 4. Every suppression in the tree

### 4.1 Added by this plan (9)

| file:line | rule | reason |
|---|---|---|
| `CortexIPC/Tests/.../KeychainTests.swift:97` | `force_cast` | `as?` on a CoreFoundation type is a COMPILE ERROR ("conditional downcast to CoreFoundation type 'CFBoolean' will always succeed"), verified by substituting `as?` and building. `.swiftlint.yml`'s own policy line permits `as!` in tests. The `CFGetTypeID` assertion one line above fails loudly on a wrong type first. |
| `CortexIPC/Tests/.../KeychainTests.swift:104` | `force_cast` | Same CoreFoundation constraint for `CFString`. |
| `CortexReplayBench/main.swift:6` + `:851` | `file_length` (paired) | 617 code lines; top-level `main.swift`; emits the committed `10-refit-real.json`. |
| `CortexSeamBSmoke/main.swift:4` + `:818` | `file_length` (paired) | 587 code lines; same reasoning. |
| `CortexReFITBench/main.swift:5` + `:697` | `file_length` (paired) | 430 code lines; the `--smoke` output is byte-diffed by `ci.yml` and `bps-policy.sh`. |
| `CortexRenderBench/main.swift:49` | `cyclomatic_complexity` | `parseArgs`: one `while` over argv, one `switch` case per flag. The complexity is the flag count; extraction moves branches without removing any. |
| `CortexRenderBench/FrameSoak.swift:74` | `function_body_length` | `FrameSoak.run`, 63 lines: a sequential bench driver (acquire device, build encoder and target, timed loop, reduce). |
| `CortexDecoderBench/main.swift:236` | `function_body_length`, `cyclomatic_complexity` | `runBench`, 86 lines / complexity 14: same driver shape; the branches are the failure guards this bench must not skip. |
| `CortexReplayBench/main.swift:319` | `function_body_length` | `runArm`, 69 lines: deliberately ONE function so all four ablation arms provably run identical code, in a byte-diffed file. |
| `CortexCore/ReplayExport.swift:224` | `function_body_length`, `cyclomatic_complexity` | `init(sidecarURL:)`, 68 lines / complexity 15: the eleven fail-closed validation steps enumerated in its own doc comment, on untrusted input. Every branch is one of those checks. |
| `CortexReFITBench/main.swift:253` | `function_parameter_count` | `simulateReach`, 6 parameters: which arm, which reach, its index, the seed, and two pieces of loop-carried state. No natural grouping, in a byte-diffed file. |

The two function-level directives on `ReplayExport.init` and `simulateReach` are trailing
`disable:this` on the declaration line rather than `disable:next` above it. A comment line between a
`///` doc block and its declaration orphans the doc comment, which `orphaned_doc_comment` correctly
flagged on the first attempt.

### 4.2 Pre-existing, not added here (6)

Confirmed present at `c3d406a`: three `empty_count` `disable:next` in
`CortexDemoTests/RollingSpikeWindowTests.swift`, one `large_tuple` `disable:this` in
`CortexSeamBSmoke/main.swift:275`, one paired `large_tuple` disable/enable in
`CortexBCIHID/BCIHIDReports.swift:56`-`:124`, and the `swiftlint:disable all` in the flatc-generated
`sample_generated.swift`.

### 4.3 A note on the plan's blanket-disable grep

The plan's acceptance criterion is:

```
grep -rn 'swiftlint:disable' Apps/ Packages/ | grep -v ':this\|:next\|swiftlint:enable'
```

It returns 5 lines, and **none of them is a blanket disable**. The grep is line-scoped and cannot see
that a `disable` has a matching `enable` further down the file. The five are: the four paired
`file_length` / `large_tuple` disables (each with its `enable` line, which the grep also cannot
associate), and the generated file, which is now excluded from linting entirely. The paired form is
one of the three scoped forms the plan itself names, and `blanket_disable_command` - the rule that
actually detects the failure this grep approximates - reports **0**.

---

## 5. Emitted-artifact byte identity

The constraint that outranks a clean lint run: no emitted number and no serialized key may change.

**Method.** A SHA-256 manifest over every committed `*.json` and every `*-evidence.md`, captured
before any edit and re-run after the final commit:

```
git ls-files '*.json' '*-evidence.md' > artifact-list.txt      # 37 files
xargs shasum -a 256 < artifact-list.txt | sort -k2 > manifest-before.txt
# ... all remediation work ...
xargs shasum -a 256 < artifact-list.txt | sort -k2 > manifest-after.txt
diff -u manifest-before.txt manifest-after.txt
```

**Result: empty.** All 37 artifacts byte-identical. The manifest was re-run after each of the four
task commits and was clean every time. It covers `refit_bps.json`, `webgrid_bps.json`,
`10-replay.json`, `10-refit-real.json`, `10-ceiling.json`, `09-decoder-metrics.json`,
`gpu_time_hist.json`, `soak_log.json`, the two `perf-report-ipad-m2.json`, `runtime_plan_ipad.json`,
`09-budget-probe.json`, the Decoder manifests and fixtures, and all 20 `*-evidence.md` files.

This artifact is the 38th; it did not exist when the manifest was captured.

---

## 6. Force unwrap and force cast disposition

All twelve sites, individually. `force_unwrapping` is ERROR severity by deliberate project policy
("Force unwrap is BANNED"), so none was silenced wholesale, and **no site was replaced by
`?? someDefault`** - substituting a value converts a loud crash into a quiet wrong number, which in
this repo means a wrong published number (T-10-16-02).

| file:line | was | now | could behaviour differ? |
|---|---|---|---|
| `CortexIPC/ShmRing.swift:153` | `base = mapped!` after an `if mapped == MAP_FAILED \|\| mapped == nil` | `guard let mapped = mmap(...), mapped != MAP_FAILED else { ... throw .map(e) }` | No. Same two conditions, same `close(fd)`, same throw. |
| `CortexIPC/ShmRing.swift:176` | same | same fold, `throw .map(errno)` | No. |
| `CortexIPC/FDChannel.swift:63` | `namePtr.baseAddress!` | `guard let nameBase = ... else { preconditionFailure(...) }` | No. A sentinel return was deliberately rejected: a negative value surfaces as `.recv(code)` and would be indistinguishable from a genuine recv failure. |
| `CortexIPC/SessionKeychain.swift:91` | `kCFBooleanTrue!` | `cfTrue`, a `CFBoolean`-typed computed property | No. Identical trap semantics on a CF singleton that is never nil; the unwrap happens once, in a documented place. Computed rather than stored because `CFBoolean` is not `Sendable` and a `static let` is a Swift 6 global-state error - this avoids needing a `nonisolated(unsafe)` escape hatch. |
| `CortexIPC/SessionKeychain.swift:121` | `kCFBooleanTrue!` | `Self.cfTrue` | No. |
| `Apps/CortexiOS/ContentView.swift:31` | `VelocityRing(capacity: 4096)!` | closure with `guard let ... else { preconditionFailure(...) }` | No. `init?` only returns nil for zero or non-power-of-two capacity; 4096 is neither, so the trap is unreachable and now says why. |
| `Apps/CortexMac/ContentView.swift:110` | same | same | No. |
| `CortexRender/WebgridView.swift:35` | `layer as! CAMetalLayer` | `guard let metal = layer as? CAMetalLayer else { preconditionFailure(...) }` | No. `layerClass` returns `CAMetalLayer.self`. |
| `CortexRender/WebgridView.swift:119` | same | same, citing `makeBackingLayer` | No. |
| `CortexIPC/Tests/.../RingTests.swift:168` | `ring.ack(seq: seen!)` | `try ring.ack(seq: #require(seen, "..."))` | Only on failure: a nil now fails the test with a message instead of crashing the runner. Strictly better. |
| `CortexIPC/Tests/.../KeychainTests.swift:92` | `dp as! CFBoolean` | unchanged, scoped `disable:next force_cast` | No change. `as?` does not compile (measured). |
| `CortexIPC/Tests/.../KeychainTests.swift:96` | `accessible as! CFString` | unchanged, scoped `disable:next force_cast` | No change. Same constraint. |

No site in this table has a behaviour-could-differ answer other than "no" or "strictly better", so no
per-site paragraph is owed.

One related source change: `LatencyHistogram.isEmpty` was added. SwiftLint's `empty_count` autocorrect
rewrote a call site to `hist.isEmpty`, which did **not compile** - the type only had `count`. The
member was added rather than the autocorrect reverted, because a `count`-exposing type offering
`isEmpty` is the idiomatic reason the rule exists.

---

## 7. Full verification transcript

All run after the final commit, on the machine and toolchain named at the top.

```
swiftlint --strict                       rc=0   Found 0 violations, 0 serious in 111 files
swiftformat --lint .                     rc=0   0/113 files require formatting, 17 files skipped
```

Package suites:

```
CortexCore     rc=0   Test run with 15 tests in 1 suite passed
CortexIPC      rc=0   Test run with 26 tests in 5 suites passed
CortexRing     rc=0   Test run with  7 tests in 0 suites passed
CortexDecoder  rc=0   Test run with 20 tests in 4 suites passed   (19 before; +1 wire-key guard)
CortexRender   rc=0   Test run with 19 tests in 4 suites passed
CortexReFIT    rc=0   Test run with 32 tests in 5 suites passed
CortexBCIHID   rc=0   Test run with 24 tests in 4 suites passed
CortexDemo     rc=0   Test run with 44 tests in 5 suites passed
```

Byte identity:

```
find Packages/CortexReFIT/.bench -type f -delete
swift run --package-path Packages/CortexReFIT CortexReFITBench --smoke    rc=0
diff .bench/refit_bps.json   <committed Phase-7>                          EMPTY
diff .bench/webgrid_bps.json <committed Phase-8>                          EMPTY
python3 Tools/scripts/check_refit_uplift.py <committed Phase-7>           rc=0
swift run --package-path Packages/CortexDemo CortexDemoBench --smoke      rc=0, 9/9 keys snake_case
swift run --package-path Packages/CortexDemo CortexSeamBSmoke             rc=0, 31/31 keys snake_case
swift run -c release ... CortexReplayBench (real session + real model)    diff vs base-commit output EMPTY
```

All eleven policy gates, plain and `--self-test`:

```
hotpath-policy.sh              rc=0    --self-test rc=0
render-policy.sh               rc=0    --self-test rc=0
hid-surface-policy.sh          rc=0    --self-test rc=0
notarize-policy.sh             rc=0    --self-test rc=0
match-policy.sh                rc=0    --self-test rc=0
bps-policy.sh                  rc=0    --self-test rc=0
readme-policy.sh               rc=0    --self-test rc=0
decoder-policy.sh              rc=0    --self-test rc=0
refit-real-policy.sh           rc=0    --self-test rc=0
honesty-sweep.sh               rc=0    --self-test rc=0
toolchain-policy.sh            rc=0    --self-test rc=0
validate-privacy-manifest.sh Apps/CortexMac/PrivacyInfo.xcprivacy Apps/CortexiOS/PrivacyInfo.xcprivacy   rc=0
```

Python and Xcode:

```
uv sync --project Decoder --extra dev                                     rc=0
uv run --project Decoder pytest Decoder/tests -m "not slow" -q            289 passed, 10 deselected
xcodegen generate                                                         rc=0
xcodebuild build -scheme CortexMac       -configuration Debug             ** BUILD SUCCEEDED **
xcodebuild build -scheme CortexRenderBench -configuration Debug           ** BUILD SUCCEEDED **
```

`pytest` reports 288 passed / 1 skipped in a bare worktree, where the skip is
`test_data.py:157 no loadable real .mat present (dataset is gitignored)`. Symlinking
`Decoder/data` from the canonical checkout, as the Plan 10-07 runbook does, gives the
289 passed / 10 deselected above. The symlink was removed afterwards; `git status` is clean.

**The Float16 daemon defect did not reproduce.** `STATE.md`'s Deferred Items row "xcodebuild of the
CortexDaemon Xcode target fails on 'Float16' is unavailable in macOS" (deferred 2026-06-20) does not
occur under Xcode 26.3: `CortexMac`, which builds `CortexDaemon` as a peer target, reaches
BUILD SUCCEEDED. This matches Plan 10-06's independent finding.

**`CortexiOS` could not be built here.** `xcodebuild -showdestinations -scheme CortexiOS` lists no
simulator destination: "iOS 26.2 is not installed. Please download and install the platform from
Xcode > Settings > Components." The three iOS-only constructs this plan edited were therefore
verified by typechecking them verbatim against the iPhoneSimulator26.2 SDK instead:

```
xcrun swiftc -typecheck -sdk <iPhoneSimulator26.2.sdk> -target arm64-apple-ios26.0-simulator \
  -swift-version 6 iosprobe.swift          rc=0
```

covering `override public static var layerClass`, the `metalLayer` guard, and the `VelocityRing`
precondition closure. That is strong evidence, not a build.

---

## 8. What this does not establish

**The gate has still never run on a hosted runner.** Everything above was measured on one machine
(Apple M5 Pro, macOS 26.5, Xcode 26.3) at one pair of tool versions. The Plan 10-15 pin plus
`toolchain-policy.sh` make that result reproducible *at those versions*, and CI installs SwiftFormat
and SwiftLint via `brew install`, which is unpinned unless the gate catches the drift. Plan 10-17
pushes and reports the first real result. A local `swiftlint --strict` on one machine is strong
evidence that the gate will pass; it is not proof.

**`CortexiOS` is unbuilt.** See section 7. The iOS platform is not installed on this machine, so the
iOS app target has not been compiled by anything, here or in CI history.

**Two `10-refit-real.json` blocks are not reproducible from `CortexReplayBench`.** Discovered while
building the base-commit control in 2.4(b) and recorded in `deferred-items.md`. The committed
artifact contains `ceiling_ref`, `phase9_bounds`, and two `env` entries (`ticks_model_backed`,
`ticks_total`) that **no version of the bench emits** - not this one and not `c3d406a`'s. The diff is
17 added lines, zero modified and zero removed, so nothing this plan did caused it and no number in
the artifact is contradicted. But the artifact is a superset of what its generator produces, which
means "regenerate and diff" is not currently a complete reproducibility check for it. That predates
this plan and is out of its scope.

**Lint cleanliness is not correctness.** A repo that passes `swiftlint --strict` has satisfied a style
gate. The behaviour evidence is the eight package suites, the eleven policy gates, and the byte
identity checks above, not the lint result.

---

## 9. An operator error during verification, and how it was caught and undone

Recorded because it touched data outside this worktree.

While preparing the base-commit control for section 2.4(b), the scratch tree's `Decoder/exports` was
already a symlink to the canonical checkout's `Decoder/exports`. Running

```
ln -sfn <canonical>/Decoder/exports/indy_20160630_01.replay.json  <scratch>/Decoder/exports/indy_20160630_01.replay.json
```

resolved the destination path THROUGH that directory symlink, so `-f` deleted the real file in the
canonical checkout and replaced it with a symlink to itself. The same happened to
`indy_20160630_01.replay.bin`. Both are gitignored, so neither git nor the checksum manifest would
have reported it; the base-commit run failing with `could not open ... notFound` is what surfaced it.

Scope was exactly those two files. `Decoder/checkpoints/` and `Decoder/data/` were untouched -
`ln -sf` cannot overwrite a real directory, and the `.mlpackage` bundles and the four `.mat` files
are directories and large regular files respectively, all verified present and unchanged afterwards.

Restored by regenerating from the pinned dataset, which is deterministic:

```
uv run --project Decoder python Decoder/scripts/export_replay.py --session indy_20160630_01
```

Restoration verified against checksums recorded in a committed artifact, not by inspection:

| quantity | restored file | recorded in committed `10-refit-real.json` | match |
|---|---|---|---|
| sidecar SHA-256 | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` | `export_sidecar_sha256` identical | yes |
| source `.mat` SHA-256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` | `source_sha256` identical | yes |
| binary SHA-256 | `5107b00911de761a60fe9ecc83dfef9b195d387ba42467586ef899755e57c48f` | matches the sidecar's own `binary_sha256` | yes |

The restored export is provably bit-identical to the one that produced every committed Phase-10
artifact, so no data was lost and no number is affected. The base-commit control was then re-run
successfully and its result is what section 2.4(b) reports.

**Lesson worth carrying:** `ln -sfn dest/file` where `dest` is itself a symlink to a directory writes
into the symlink's TARGET. When staging gitignored inputs into a scratch tree, create real
directories and symlink the files into them, which is exactly what the Plan 10-07 and 10-11 runbooks
already say ("real directories holding symlinks, never bare symlinks"). This plan followed that in
its own worktree and did not in the scratch control tree.
