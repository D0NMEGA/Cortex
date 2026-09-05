---
status: PARTIAL
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 04
subsystem: swift
tags: [swift, replay-export, binary-format, asvs-v5, asvs-v12, seam-a, glass-to-glass, pattern-2, coreml, ndt1]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: Plan 10-02's D-06 export format, its committed tiny_replay fixture and the materialized indy_20160630_01 export; 10-PREREGISTRATION sections 2, 9 and 10; 10-03a's corrected workspace box
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: the shipped ndt1_real_vel_sweep_fp16.mlpackage with its (1, 96, 1, 32) spikes input
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: ClosedLoopPipeline, GlassToGlassTimer, CortexDemoBench and the Phase-8 measurement geometry
provides:
  - CortexCore.ReplayExport - the ONE Swift reader of the D-06 export, with ten validations before any allocation
  - SpikeWindowSource - the injected spike-window seam, with SyntheticSpikeSource and RecordedSpikeSource conforming
  - RecordedSpikeSource - real 20 ms bins at the model's 32-bin window length
  - ClosedLoopPipeline.modelBackedTicks / totalTicks / allTicksModelBacked / sourceSeqLen / lastDecodeFailure
  - CortexDemoBench --real - Seam A, writing .bench/glass_to_glass_real.json with no verdict and no budget key
affects: [10-05, 10-06, 10-08, 10-09, 10-10, 10-11, rd-08-replay, seam-a-latency]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One reader of a binary format in Swift, living in the package every consumer already depends on, so a second reader cannot drift"
    - "Every header field validated before Data(contentsOf:), with the byte-length check last and a one-byte truncation control committed"
    - "A fallback keeps its behaviour but loses its silence: the try? becomes do/catch that records the first reason, naming both shapes"
    - "A real-data measurement mode is ADDITIVE - separate flag, separate report struct, separate output file - so the synthetic gate it must not inherit is provably untouched"
    - "A modelled quantity ships with a verbatim provenance string naming what it is not"

key-files:
  created:
    - Packages/CortexCore/Sources/CortexCore/ReplayExport.swift
    - Packages/CortexCore/Tests/CortexCoreTests/ReplayExportTests.swift
    - Packages/CortexDemo/Sources/CortexDemo/SpikeWindowSource.swift
    - Packages/CortexDemo/Sources/CortexDemo/RecordedSpikeSource.swift
    - Packages/CortexDemo/Tests/CortexDemoTests/RecordedSpikeSourceTests.swift
  modified:
    - Packages/CortexDemo/Sources/CortexDemo/ClosedLoopPipeline.swift
    - Packages/CortexDemo/Sources/CortexDemo/SyntheticSpikeSource.swift
    - Packages/CortexDemo/Sources/CortexDemoBench/main.swift
    - Packages/CortexDemo/Tests/CortexDemoTests/ClosedLoopPipelineTests.swift
    - Packages/CortexDemo/Package.swift
    - .planning/phases/10-v1-real-data-closed-loop-launch/deferred-items.md

key-decisions:
  - "The T-08-03-01 forbidden token is LissajousProducer, and it is NOT enforced by render-policy.sh: it is a Phase-8 threat-model inspection assertion recorded in 08-SECURITY.md. The plan's read_first pointed at the wrong file; the token was found and checked anyway"
  - "ReplayExport is nonisolated + Sendable with only immutable stored properties, so both the MainActor bench and a nonisolated consumer can read it without an actor hop"
  - "All 13 workspace fields are decoded, not the 11 the plan listed: the sidecar also carries centre_x_mm and centre_y_mm"
  - "The --real path repeats the present arithmetic verbatim rather than factoring it out, because factoring it out would edit the Phase-8 code path and that is exactly what Seam A's comparability forbids"
  - "ClosedLoopPipeline's init records a model-load failure into lastDecodeFailure too, so the RD-08 assertion cannot report 'none recorded' for the commonest cause of a fallback run"
  - "ClosedLoopPipelineTests Test 2 was NOT repaired: the plan says in writing not to modify an existing case, and the failure is proven pre-existing"

patterns-established:
  - "A pre-existing test failure is proven by rebuilding the pre-change tree from git archive and reproducing it, not by arguing from the diff"
  - "A model-gated control skips cleanly with no model and, when one is present, drives the exact trap the plan exists to remove"

requirements-completed: [RD-08]

# Metrics
duration: 62min
completed: 2026-09-05
---

# Phase 10 Plan 04: The Swift replay reader, the injected spike seam and Seam A Summary

**Swift now has one validated reader of the D-06 export, the closed loop takes its spike source by injection and counts every model-backed tick, and `CortexDemoBench --real` replays 2,286 real 32-bin windows through the shipped NDT1 model inside the unmodified Phase-8 measurement geometry with 2294 of 2294 ticks model-backed and no pass/fail bar attached.**

## Performance

- **Duration:** 62 min
- **Tasks:** 3
- **Files:** 11 (5 created, 6 modified)
- **Commits:** 6 (2 TDD RED, 3 GREEN, 1 docs)

## Task commits

| # | Task | Commit | Type |
|---|---|---|---|
| 1 | ReplayExport contract test (RED) | `6f96ddd` | test |
| 1 | CortexCore.ReplayExport (GREEN) | `5bb164d` | feat |
| 2 | Seam and counter tests (RED) | `fe53217` | test |
| 2 | SpikeWindowSource, RecordedSpikeSource, the pipeline changes (GREEN) | `778776c` | feat |
| 3 | CortexDemoBench --real, Seam A | `5b251d5` | feat |
| 2 | The D-13 determinism contract on the seam | `f2bbac5` | docs |

## Task 1: one Swift reader of the D-06 export

`Packages/CortexCore/Sources/CortexCore/ReplayExport.swift` (408 lines) parses the sidecar into
`ReplaySidecar` (all 22 keys), `ReplayWorkspace` (all 13 fields) and `ReplayTargetGrid`, with explicit
`CodingKeys` rather than a key-decoding strategy so every mapped key is greppable from the file.

**The ordering proof the plan asked for, recorded explicitly.** `init(sidecarURL:)` runs ten checks
before any file bytes are loaded, and `Data(contentsOf:options: .mappedIfSafe)` is reached only on
step 11. The source carries a comment stating that, and the truncation control asserts the specific
case:

```
Test 2: a one-byte truncation throws .sizeMismatch (checked before any read)
  #expect(throws: ReplayExportError.sizeMismatch(declared: 256 * 424, actual: 108_543))
```

Six malformations are refused, each with a committed control: a schema bump, a wrong channel count, a
wrong record size, a `source_sha256` that is not 64 lowercase hex (including a 64-character UPPERCASE
one), a symlinked `binary_path` resolving outside the sidecar's directory, and a size mismatch. An
absent sidecar or binary throws `.notFound`, never an empty read.

`window(endingAt:length:)` returns bin-major `[Float16]`, matching `SyntheticSpikeSource.window`'s
layout so the two sources are interchangeable at the seam. `loadUnaligned` is used throughout, with
the reason in a comment: 424 is not a multiple of 8, so a record's `Float64` fields are unaligned for
odd bins, and an aligned `load` there is undefined behaviour.

The tests are deliberately a CROSS-LANGUAGE contract: the fixture is written by Python
(`make_tiny_replay.py` through `ndt1.replay_export.write_export`) and read by Swift, and the bin-major
assertion cross-checks three `(bin, channel)` cells against the raw bytes read independently at
`424 * bin + 4 * channel`, so it is a real check of the layout rather than a restatement of the
reader's own arithmetic. Every mutation control copies the fixture into a temporary directory; the
committed bytes are never touched.

## Task 2: the injected seam and the end of the silent fallback

**The T-08-03-01 forbidden token is `LissajousProducer`.** The plan's `read_first` said to find it in
`Tools/scripts/render-policy.sh`. It is not there: `render-policy.sh` forbids `CADisplayLink` (iOS
adapter), `storageModeManaged` and the timed-present variants, and carries no `ClosedLoopPipeline`
check at all. T-08-03-01 is a Phase-8 threat-model assertion recorded in `08-SECURITY.md:56` and
`08-VALIDATION.md:50`, verified by inspection. The token was found there and checked: it appears zero
times in `ClosedLoopPipeline.swift`, `SpikeWindowSource.swift` and `RecordedSpikeSource.swift`, and
`render-policy.sh` plus `--self-test` both exit 0.

Four surgical changes to `ClosedLoopPipeline`:

1. `spikeSource` becomes `any SpikeWindowSource`. A new designated init takes `source:`; the Phase-8
   `init(seed:start:target:modelURL:)` survives as a convenience that forwards, so
   `Apps/CortexMac/ContentView.swift:76`, `CortexDemoBench/main.swift:90` and all five existing test
   cases compile and behave unchanged.
2. `sourceSeqLen` exposes the buffer's window length. The `SpikeInputBuffer(device:, seqLen:
   spikeSource.numBins, channels: spikeSource.channels)` line is unchanged and now carries a comment
   naming the trap.
3. `modelBackedTicks`, `totalTicks` and `allTicksModelBacked`, incremented in the single place
   `decode(window:tick:cursor:)` resolves.
4. The two swallowing `try?` sites in `decodeWithModel` become `do`/`catch` recording the first
   failure into `lastDecodeFailure`.

**`try?` count in `ClosedLoopPipeline.swift`: 1, and it is inside a doc comment describing the removed
pattern.** No code `try?` remains anywhere in the file, which exceeds the acceptance criterion
(criterion: zero inside `decodeWithModel`; other uses elsewhere would have been acceptable and listed).
The two in `init` were converted as well, for the reason in Deviation 3 below.

The fallback BEHAVIOUR is unchanged: a failure still returns nil and the loop still runs on the
synthetic decode. What changed is that the reason is recoverable.

## Task 3: `CortexDemoBench --real` is Seam A by construction

`git diff --stat` on `main.swift`: **246 insertions, 2 deletions**. The two deleted lines are the
`import CortexCore` trailing comment and `if !isSmoke, !isFull {` becoming
`if !isSmoke, !isFull, !isReal {`. **No line inside the existing `--smoke` / `--full` tick loop, its
configuration, its report struct, its verdict or its JSON write was modified.** The `--real` block sits
between the shared configuration and the untouched synthetic block, reads `framePeriodNs` rather than
re-typing it, and `exit(0)`s so the synthetic path never runs in real mode.

**D-09 / review D-3, verified two ways.**

- Structurally: `grep -n 'passed'` on `main.swift` returns lines **55, 382, 388, 396, 432**. Line 55 is
  the shared usage string ("No flag was passed"), which is not a verdict; 382/388/396/432 are all
  inside the synthetic block, which begins at line 330. `grep -n 'budgetNs'` returns **96, 118, 388,
  395, 434, 439**: line 96 is the shared declaration (never read in `--real`), line 118 is the comment
  stating it is not compared, and the rest are in the synthetic block. The `if isReal` block spans
  lines 148 to 328 and contains no verdict and no comparison. `RealSeamReport` has no such fields, so
  their absence is a compile-time property, not a runtime one.
- Dynamically: the run below exits **0**, and
  `python3 -c "...assert 'passed' not in d and 'budget_ns' not in d..."` prints `no verdict keys`.

Both methods are recorded because the criterion allowed either.

**Frame cadence (review D-7, SC#2).** `frame_period_ns` is `8333333` in the emitted JSON,
`frames_modelled` is the number of distinct 120 Hz present boundaries the run crossed, and
`cadence_provenance` is the verbatim string forbidding it from being read as measured.

## The Seam A run

Recorded as an execution observation, **not** as a published number. Plan 10-08's evidence artifact is
where a Seam A figure gets published with a runbook; this is the first run of the code, reported here
so the next plan knows what it produces.

Machine: **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Swift 6.2.4, Xcode 26.3. Device label
`M5-Pro-software-timed-corroborating`. Seed `0xC0FFEE`. Software-timed, MODELLED 120 Hz cadence.

```
swift run --package-path Packages/CortexDemo CortexDemoBench --real \
  --export Decoder/exports/indy_20160630_01.replay.json \
  --model  Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage
```

| Field | Value |
|---|---|
| `session_id` | `indy_20160630_01` |
| `export_sidecar_sha256` | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` (matches 10-03a) |
| `ticks_model_backed` / `ticks_total` | **2294 / 2294** |
| `count` (measured ticks) | 2286 |
| `p50_ns` | 4747568 (4.748 ms) |
| `p99_ns` | 8835053 (8.835 ms) |
| `max_ns` | 9108011 (9.108 ms) |
| `frame_period_ns` | 8333333 |
| `frames_modelled` | 161 |
| `data_source` | `real` |
| exit code | **0** |

**NDT1 was genuinely in the loop on every tick, against real Indy M1 spike bins.** That is the first
time in this repository that the CoreML decoder has run over real recorded spikes inside the closed
loop.

**Three facts the evidence artifact must carry, learned from running it.**

1. **The p99 is not stable run to run.** Four runs of the same command gave p99 8911224, 9092833,
   8851681 and 8835053 ns - a spread of about 3 percent. The measurement includes real work on a live
   machine, so the arithmetic is deterministic but the pipeline cost is not. A published Seam A number
   needs a stated n and a stated run count, not a single invocation.
2. **`n` is 2286, not 10000.** The export holds 73,160 bins, so at the model's 32-bin window length it
   yields 2,286 whole windows and `min(10_000, windowCount)` binds on the export. Seam A cannot reach
   the 10k bar the Phase-8 full run used without replaying windows.
3. **`ticks_total` is 2294, including the 8 warmup ticks**, and the source clamps at its last whole
   window, so the final 8 ticks re-replay window 2285. That is stated in the JSON's `note` and printed.
   It does not affect the latency distribution but it should not surprise a reader of the JSON.

The Phase-8 synthetic reference `8318256 ns` is printed beside the new p99, with the statement that the
two are comparable because only the source and the decode changed, and that Seam B (Plan 10-06)
measures a strictly wider boundary and is comparable to neither.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 3 - Blocking] The T-08-03-01 token is not in `render-policy.sh`**

- **Found during:** Task 2, before naming any new type.
- **Issue:** the plan's `read_first` and `action` both say to read `Tools/scripts/render-policy.sh` for
  the forbidden token. That file contains no `ClosedLoopPipeline` check; the gate is a Phase-8
  threat-model inspection assertion.
- **Fix:** located the token in `08-SECURITY.md:56` and `08-VALIDATION.md:50` as `LissajousProducer`
  and checked all three new/modified pipeline files against it.
- **Verification:** zero occurrences in the three files; `render-policy.sh` and `--self-test` exit 0.
- **Committed in:** `778776c`

**2. [Rule 2 - Missing critical] `n_bins * 424` could overflow before the size check**

- **Found during:** Task 1.
- **Issue:** the plan's step 6 is `nBins > 0`. An `n_bins` near `Int.max` would wrap `n_bins * 424`
  into a small positive number that a truncated file would then "match", defeating the very check
  T-10-04-01 exists to make. The threat is sizing a mapping from an untrusted header, and a positivity
  test alone does not close it.
- **Fix:** a second guard, `nBins <= Int.max / recordBytes`, with its own `.malformedSidecar` reason.
- **Files:** `ReplayExport.swift`
- **Committed in:** `5bb164d`

**3. [Rule 2 - Missing critical] A model that never loads reported no reason at all**

- **Found during:** Task 2, while writing the `lastDecodeFailure` control.
- **Issue:** the plan scoped the `do`/`catch` to `decodeWithModel`. But when `NeuralDecoder` or
  `SpikeInputBuffer` fails to construct, `decoder` is nil and `decodeWithModel` is never called, so
  every tick falls back and the RD-08 precondition would print `First failure: none recorded` for the
  single commonest cause of a fallback run. The diagnostic the plan specifies would have been useless
  in the case it is most likely to fire.
- **Fix:** the two `try?` in `init` become one `do`/`catch` recording a `setupFailure` (naming the
  requested seqLen and channels) into `lastDecodeFailure`. The no-Metal-device branch records too.
  This also makes the plan's own required control - "test with a stub that forces the failure path so
  it runs on a clean clone with no model" - implementable: an unloadable model URL now produces a
  recorded reason with no `.mlpackage` present.
- **Files:** `ClosedLoopPipeline.swift`
- **Committed in:** `778776c`

**4. [Rule 2 - Missing critical] A short window would have trapped instead of falling back**

- **Found during:** Task 2.
- **Issue:** `decodeWithModel` indexes `window[bin * channels + channel]`. A source whose window is
  shorter than `numBins * channels` would trap mid-run rather than degrade.
- **Fix:** a length guard that records the mismatch and returns nil, so it is a legible fallback.
- **Files:** `ClosedLoopPipeline.swift`
- **Committed in:** `778776c`

**5. [Rule 2 - Missing critical] `CortexCore` was an undeclared transitive import in the test target**

- **Found during:** Task 2.
- **Issue:** `RecordedSpikeSourceTests` imports `CortexCore`, which the `CortexDemoTests` target
  reached only transitively through `CortexDemo`. It compiles under Swift 6.2.4 but is not a declared
  dependency.
- **Fix:** `.product(name: "CortexCore", package: "CortexCore")` added to the test target.
- **Files:** `Packages/CortexDemo/Package.swift`
- **Committed in:** `778776c`

**6. [Rule 2 - Missing critical] The T-10-04-03 mitigation had no executed control for the actual trap**

- **Found during:** Task 3 verification.
- **Issue:** the plan's tests cover the counters and the recorded reason, but nothing drove the real
  shape mismatch against the real model, which is the threat itself. RESEARCH calls this "the cheapest
  and highest-value assertion in the whole phase".
- **Fix:** `RecordedSpikeSourceTests` Test 9 builds two pipelines over the same fixture and the same
  model, differing only in window length: at 32 every tick is model-backed and `lastDecodeFailure` is
  nil; at 8 zero ticks are model-backed and the reason names `seqLen 8` and `numBins 8`. It skips
  cleanly with no `CORTEX_MODEL_URL`, and it passes with the shipped fp16 model wired.
- **Files:** `RecordedSpikeSourceTests.swift`
- **Committed in:** `5b251d5`

**7. [Rule 3 - Blocking] `--real` was unreachable through the no-flag guard**

- **Found during:** Task 3.
- **Issue:** `if !isSmoke, !isFull { print(usage); exit(0) }` fires before any new code, so `--real`
  alone would have printed usage and exited.
- **Fix:** `!isReal` added to that condition, plus a `--real` paragraph in the usage string. These are
  the only two pre-existing lines touched, and neither is in the measurement path.
- **Files:** `CortexDemoBench/main.swift`
- **Committed in:** `5b251d5`

**8. [Rule 3 - Blocking] A bare `Decoder/exports` symlink left the worktree dirty**

- **Found during:** setup.
- **Issue:** `.gitignore:99` is `Decoder/exports/` with a trailing slash, which matches only a real
  directory, so a symlink at that path showed as untracked - the identical trap Plan 10-02 recorded
  for `Decoder/data/`.
- **Fix:** `Decoder/exports/` is a real directory holding two symlinks to the canonical checkout.
  `git status --short` is clean and `git check-ignore -v Decoder/exports/x.bin` reports
  `.gitignore:99`. Nothing from `Decoder/exports/` or `.bench/` was committed.
- **Files:** none (ignored paths only)

**9. [Rule 1 - Bug] The sidecar has 13 workspace fields, not the 11 the plan listed**

- **Found during:** Task 1.
- **Issue:** the plan says "the 11 workspace fields"; the committed sidecars also carry `centre_x_mm`
  and `centre_y_mm`.
- **Fix:** all 13 are decoded.
- **Files:** `ReplayExport.swift`
- **Committed in:** `5bb164d`

**10. [Rule 2 - Missing critical] A zero-window export would have reported percentiles over no samples**

- **Found during:** Task 3.
- **Issue:** `min(10_000, windowCount)` is 0 for an export shorter than one window, and the run would
  have proceeded to a histogram over an empty array.
- **Fix:** a guard that names the bin count and refuses, rather than reporting.
- **Files:** `CortexDemoBench/main.swift`
- **Committed in:** `5b251d5`

**Total: 10 auto-fixed (6 missing-critical, 3 blocking, 1 bug). No Rule 4 escalation.**

### Formatting note

`swiftformat` was run on every touched file with `--disable swiftTestingTestCaseNames` on the test
files, because that rule fires identically on the pre-existing `ClosedLoopPipelineTests.swift` and
`GlassToGlassTimerTests.swift`; conforming only the new files would have made them inconsistent with
the suite around them. Every file this plan touched is otherwise `swiftformat --lint` clean. The
repo-wide lint sweep is D-18 work in a later plan. `swiftformat` also rewrote `min(10_000, ...)` to
`min(10000, ...)`, matching the file's existing `let tickCount = isSmoke ? 2000 : 10000`.

### Deliberately not done

- **`ClosedLoopPipelineTests` Test 2 was not repaired.** See "Findings for later plans" below and
  `deferred-items.md`.
- **`Tools/scripts/bps-policy.sh` and the `ci.yml:378-388` `refit_bps.json` byte-diff were left red.**
  Both are Plan 10-05's to repair. Measured: `bps-policy.sh` exits **1**, `bps-policy.sh --self-test`
  exits **0** (the gate itself is intact) - identical to what 10-03a recorded. No committed synthetic
  fixture was modified.
- **`GlassToGlassTimer.methodologyLabel` was not touched.** It is the four-way coupled edit Plan 10-11
  owns; `--real` reads it and writes it into the JSON unchanged.
- **STATE.md and ROADMAP.md were not updated**, per the task.

## Findings for later plans

**`ClosedLoopPipelineTests` Test 2 cannot pass against the shipped 32-bin model, and that is
pre-existing.** With `CORTEX_MODEL_URL` set to `ndt1_real_vel_sweep_fp16.mlpackage`, the Phase-8 case
`modelBackedDecodePathPresent` fails at `ClosedLoopPipelineTests.swift:71` with
`Expectation failed: anyModelTick`. It builds the pipeline with the default 8-bin `SyntheticSpikeSource`
and asserts NDT1 ran; the model's input is `(1, 96, 1, 32)`, so it structurally cannot.

This was **proven**, not argued: the pre-change tree at commit `5bb164d` was rebuilt with
`git archive` and produced the identical failure. The `try?` the old code used and the `do`/`catch`
the new code uses both return nil and both fall back, so the observable outcome is unchanged.

It is the trap itself, sitting inside the Phase-8 test that was written to catch it and has never been
run under the condition it was written for. The plan says in writing "Do not modify or delete any
existing case", so it was logged to `deferred-items.md` with the reproduction rather than repaired.
**Plans 10-06 and 10-09 will see a red CortexDemo suite from this one case the moment they run with a
model wired.** The repair is one line: construct that case's pipeline at
`RecordedSpikeSource.modelSeqLen`.

**Other handoffs.**

- **10-05:** `CortexCore.ReplayExport` is the reader to consume from `CortexReFITBench`; do not write a
  second one. `RecordedSpikeSource.target(forWindow:)` already gives the rotation target under the
  last-bin convention.
- **10-06 (Seam B):** the `--real` output file is `glass_to_glass_real.json` with `seam: "A"`. Seam B
  needs its own entry; the two go into `10-replay.json`'s `seams` array per section 11, and neither
  carries `passed` or `budget_ns`.
- **10-08 / 10-09:** the numbers above are an execution observation, not evidence. The three facts under
  "The Seam A run" (run-to-run spread, n = 2286, warmup in `ticks_total`) all need to appear in the
  evidence artifact. `export_sidecar_sha256` in the JSON is computed from the bytes actually read, so
  the provenance gate can bind to it.
- **Anyone re-running this:** `Decoder/exports/` must be a real directory holding symlinks, never a
  bare symlink, or `git status` goes dirty.

## Known Stubs

Three zero-valued fallbacks exist in `RecordedSpikeSource` and are listed here so a verifier does not
have to rediscover them. **None is reachable**, and each is unreachable by construction rather than by
convention:

| File | Line | Fallback | Why it cannot fire |
|---|---|---|---|
| `RecordedSpikeSource.swift` | 60 | `window(_:)` returns an all-zero window if `export.window` throws | The index is clamped to `[0, binCount - 1]` before the call, and `ReplayExport.init` refuses `n_bins <= 0`, so the only throwing case left is an export holding fewer than `numBins` bins. `windowCount` is then 0, and `--real` refuses to run at all (see Deviation 10) |
| `RecordedSpikeSource.swift` | 67 | `target(forWindow:)` returns `(0, 0)` | Same clamp, via `lastBin(forWindow:)` |
| `RecordedSpikeSource.swift` | 72 | `trueVelocity(forWindow:)` returns `(0, 0)` | Same clamp |

`RecordedSpikeSourceTests` Test 3 asserts the clamped window carries real bins rather than zeros, so
the unreachability is tested and not just asserted. No placeholder text, no hardcoded empty collection
and no unwired component was introduced by this plan.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new_config_surface | `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` | `--export <path>` and `--model <path>` are new argv-driven file-path inputs. The threat register names only the env-var surface (`CORTEX_REPLAY_EXPORT`, `CORTEX_MODEL_URL`). The trust level is identical (a local CLI invocation), the export path is fully validated by `ReplayExport` including the `.pathEscape` check, and the model path goes to the same `NeuralDecoder(modelURL:)` the pre-existing env var already reaches. Recorded for completeness rather than as an open risk; no register entry is proposed. |

Nothing else in this plan introduced a network endpoint, an auth path or a schema change at a trust
boundary.

## Verification

Every command run in this worktree on **Apple M5 Pro**, macOS 26.5 (25F71) arm64, Swift 6.2.4,
Xcode 26.3.

| Command | Result |
|---|---|
| `swift build --package-path Packages/CortexCore` | **Build complete**, 0 warnings |
| `swift test --package-path Packages/CortexCore` | **15 tests in 1 suite passed** (12 new + 3 pre-existing) |
| `swift build --package-path Packages/CortexDemo` | **Build complete**, 0 warnings |
| `swift test --package-path Packages/CortexDemo` | **21 tests in 3 suites passed** (9 pre-existing + 3 added to ClosedLoopPipelineTests + 9 RecordedSpikeSourceTests) |
| `CortexDemoBench` (no flag) | usage, **exit 0** |
| `CortexDemoBench --smoke` | p99 8334107 ns, `PASS (PERF-04)`, writes `.bench/glass_to_glass.json`, **exit 0** |
| `CortexDemoBench --real` with neither input | names BOTH missing inputs, **exit 0** |
| `CortexDemoBench --real` with export + model | 2294/2294 model-backed, writes `.bench/glass_to_glass_real.json`, **exit 0** |
| `python3` assert on `glass_to_glass_real.json` | prints `no verdict keys`; `frame_period_ns == 8333333` |
| `./Tools/scripts/render-policy.sh` | **exit 0** |
| `./Tools/scripts/render-policy.sh --self-test` | **exit 0** |
| `./Tools/scripts/hotpath-policy.sh` | **exit 0** |
| `./Tools/scripts/hotpath-policy.sh --self-test` | **exit 0** |
| `./Tools/scripts/decoder-policy.sh` | **exit 0** |
| `swiftformat --lint` on every touched file | clean (with the note above) |
| `git status --short` | clean; nothing from `Decoder/exports/` or `.bench/` |
| `Tools/scripts/bps-policy.sh` | **exit 1**, RED - pre-existing, Plan 10-05 owns it |
| `Tools/scripts/bps-policy.sh --self-test` | **exit 0**, the gate itself is intact |
| `swift test --package-path Packages/CortexDemo` with `CORTEX_MODEL_URL` set | **1 failure**, `ClosedLoopPipelineTests` Test 2 - proven pre-existing on `5bb164d`, deferred |

### Acceptance criteria greps

| Check | Result |
|---|---|
| `grep -c '@Test' ReplayExportTests.swift` | 12 (>= 9) |
| `grep -F 'public static let recordBytes = 424'` | 1 |
| `grep -F 'case sizeMismatch'` / `'case pathEscape'` | 1 / 1 |
| `grep -F 'resolvingSymlinksInPath'` / `'loadUnaligned'` | 3 / 3 |
| `grep -F 'CORTEX_REPLAY_EXPORT'` | 2 |
| `grep -cF 'CodingKeys'` | 3 (>= 2) |
| `grep -F 'tiny_replay.json'` in the tests | 8 |
| `grep -F 'public protocol SpikeWindowSource'` | 1 |
| `grep -F ': SpikeWindowSource'` in `SyntheticSpikeSource.swift` | 1 |
| `grep -F 'public static let modelSeqLen = 32'` | 1 |
| `grep -F 'any SpikeWindowSource'` in the pipeline | 2 |
| `grep -F 'seqLen: spikeSource.numBins'` | 1 |
| `grep -F 'allTicksModelBacked'` / `'lastDecodeFailure'` in the pipeline | 2 / 6 |
| `grep -cF 'try?'` in the pipeline | 1, in a doc comment; 0 in code |
| `grep -c '@Test' RecordedSpikeSourceTests.swift` | 9 (>= 6) |
| `grep -F 'RecordedSpikeSource'` in the bench | 3 |
| `grep -F 'glass_to_glass_real.json'` / `'glass_to_glass.json'` in the bench | 2 / 3 |
| `grep -F 'D-09: no pass/fail bar is applied to a real-data measurement'` | 1 |
| `grep -F 'frame_period_ns'` / `'cadence_provenance'` | 3 / 3 |
| `grep -F 'let framePeriodNs: UInt64 = 8_333_333'` | 1, unchanged |
| `grep -F '8318256'` | 1 |
| `grep -F 'let framesElapsed = pipelineDoneNs / framePeriodNs'` | 2 (the Phase-8 line unchanged, plus the verbatim Seam A copy) |
| `git diff --stat` on `main.swift` | 246 insertions, 2 deletions |

### Artifact minimums

| Artifact | Lines | Required |
|---|---|---|
| `ReplayExport.swift` | 408 | >= 180 |
| `ReplayExportTests.swift` | 320 | >= 90 |
| `SpikeWindowSource.swift` | 30 | >= 25 |
| `RecordedSpikeSource.swift` | 80 | >= 80 |

## Self-Check: PASSED

Files claimed as created, all confirmed present on disk:
`Packages/CortexCore/Sources/CortexCore/ReplayExport.swift`,
`Packages/CortexCore/Tests/CortexCoreTests/ReplayExportTests.swift`,
`Packages/CortexDemo/Sources/CortexDemo/SpikeWindowSource.swift`,
`Packages/CortexDemo/Sources/CortexDemo/RecordedSpikeSource.swift`,
`Packages/CortexDemo/Tests/CortexDemoTests/RecordedSpikeSourceTests.swift`.

Files claimed as modified, all confirmed changed in the commits below:
`ClosedLoopPipeline.swift`, `SyntheticSpikeSource.swift`, `CortexDemoBench/main.swift`,
`ClosedLoopPipelineTests.swift`, `Packages/CortexDemo/Package.swift`, `deferred-items.md`.

Commits claimed, all resolving as commit objects on top of the expected base
`657e6a7d9aa055085019044490da16e9984046ca`: `6f96ddd`, `5bb164d`, `fe53217`, `778776c`, `5b251d5`,
`f2bbac5`.

The two load-bearing claims were executed, not asserted: `--real` reported **2294 of 2294** ticks
model-backed against the real export and the shipped fp16 model and exited **0**, and the
`ClosedLoopPipelineTests` Test 2 failure was reproduced on a rebuilt pre-change tree at `5bb164d`
before being deferred.

*Phase: 10-v1-real-data-closed-loop-launch*
*Completed: 2026-09-05*
