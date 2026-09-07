---
status: PARTIAL
agent: donny-executor
phase: 10-v1-real-data-closed-loop-launch
plan: 06
subsystem: swift
tags: [swift, ipc, aes-gcm, shm-ring, seam-b, rd-08, d-05, asvs-v5, asvs-v6, asvs-v14, ndt1, coreml]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: "Plan 10-04's CortexCore.ReplayExport + RecordedSpikeSource.modelSeqLen; Plan 10-02's D-06 export format and its committed tiny_replay fixture; 10-PREREGISTRATION section 9 (the Seam A / Seam B split); 10-RESEARCH Pitfall 9 and Correction 2"
  - phase: 02-ipc-shm-ring-aes-gcm-session
    provides: "ShmRing, Doorbell, SampleCodec, SessionCrypto, HarnessConsumer.packSlot, and the in-process lock-step gate idiom from HarnessE2ETests"
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: "CursorIntegrator, BCIInputPointerReport, ClosedLoopPipeline.modelURLFromEnvironment"
provides:
  - "CortexDemo.RollingSpikeWindow - one-bin-in, contiguous 32-bin-window-out, with gap and duplicate refusal and an oldest-first ordering contract on both window() and fill(_:)"
  - "Producer.binF16 / isReplayBacked / replaySessionId / configuredPayloadSourceDescription - the D-05 replay source on the daemon producer, throwing rather than falling back"
  - "CortexSeamBSmoke - the headless Seam B chain executable writing .bench/seam_b.json with data_source, process_boundary and no verdict key"
  - "The CI step 'Seam B chain smoke on the synthetic fixture (RD-08)', already wired; Plan 10-09 must NOT add a second one"
affects: [10-07, 10-08, 10-09, 10-10, 10-11, rd-08-replay, seam-b]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A payload SOURCE is injectable at one line while the transport, crypto and framing stay byte-identical, so a measurement changes one variable"
    - "A configured-but-unloadable input THROWS; it never degrades to the synthetic path under a real-data label"
    - "A gate resolves its input in ORDER with a committed fixture as the fallback, rather than skipping, so a CI step cannot pass vacuously"
    - "An artifact carries data_source and process_boundary as first-class fields, so a downstream reader cannot overstate what was measured"
    - "A negative control is EXECUTED and its transcript recorded, not merely written"

# Key files
key-files:
  created:
    - Packages/CortexDemo/Sources/CortexDemo/RollingSpikeWindow.swift
    - Packages/CortexDemo/Tests/CortexDemoTests/RollingSpikeWindowTests.swift
    - Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift
    - Packages/CortexDemo/Package.resolved
  modified:
    - Apps/CortexDaemon/Producer.swift
    - Apps/CortexDaemon/main.swift
    - Packages/CortexDemo/Package.swift
    - .github/workflows/ci.yml

# Decisions
decisions:
  - "Seam B runs in ONE process in producer/consumer lock-step over the real transport. The repo's own Phase-2 decision is that the always-on gate is in-process and the posix_spawn proof is XCTSkip-guarded, and the daemon's Mach rendezvous was re-measured failing today BEFORE any Phase-10 change. The JSON records process_boundary: in_process."
  - "SwiftPM derives a path dependency's identity from the DIRECTORY, so .product(package:) takes CortexIPC, not the manifest's CortexIPCPackage. The plan asserted the opposite; the resolution failure is the evidence."
  - "RollingSpikeWindow.fill(_:) is @MainActor while push and window() are nonisolated, because SpikeInputBuffer is MainActor-isolated and only the handoff crosses."
  - "A sequence gap RESETS the fill and RE-ANCHORS on the seq that arrived, so a second consecutive gap is still detected rather than absorbed as a fresh start."
  - "Packages/CortexDemo/Package.resolved is committed to pin the transitive flatbuffers revision the new CortexIPC edge introduces; it matches the tracked CortexIPC pin exactly."

# Metrics
metrics:
  duration: ~70 min
  completed: 2026-09-05
  tasks: 3
  commits: 3
  files-changed: 8
  lines-added: 1232
  tests-added: 11
---

# Phase 10 Plan 06: Seam B, the D-05 chain end to end

The daemon producer now emits real 20 ms bins from the D-06 export instead of the Phase-2 test
pattern, a rolling 32-bin accumulator turns one-bin IPC frames into contiguous oldest-first decode
windows, and a headless `CortexSeamBSmoke` drives the whole chain (seal, shm ring, doorbell, decrypt,
ordering, accumulation, `SpikeInputBuffer` fill, NDT1 decode, cursor integration, HID pointer-report
encode), fails closed on a tampered AES-GCM tag, and runs the same chain over the committed synthetic
fixture on a clean clone so the new CI step cannot pass vacuously.

## What was built

**Task 1, `RollingSpikeWindow` (commit `6100311`).** 10-RESEARCH Pitfall 9 is the reason it exists:
`SampleCodec.encode` takes exactly 96 `Float16` values, so one IPC frame carries one 20 ms bin, while
the shipped NDT1 input is `(1, 96, 1, 32)`. Nothing in the repo bridged that gap. The accumulator
refuses the two failures that would otherwise be silent. A time-reversed window is a well-formed
tensor the model accepts, so `window()` and `fill(_:)` both pin bin 0 as the OLDEST bin under named
tests with distinguishable bins. A window straddling a sequence gap is not 32 contiguous bins of the
recorded session, so a gap RESETS the fill rather than bridging it or inserting zeros. 11 tests,
dataset-free and model-free.

**Task 2, the D-05 replay producer (commit `cce92bd`).** `binF16(forSeq:)` returns the export bin at
`seq % binCount` when `CORTEX_REPLAY_EXPORT` names a D-06 export, else the unchanged `patternF16`.
`produce` changed by exactly one line. The crypto, framing, ring write, doorbell and ack-bounce are
untouched, and no path bypasses AES-GCM. A SET but unloadable export THROWS from `Producer.init`
rather than falling back, which is the D-05 form of the Pattern-2 trap Plan 10-04 removed from the
closed loop.

**Task 3, `CortexSeamBSmoke` plus its CI step (commit `807feb3`).** The Seam B executable, and the
one CI step that makes it a gate. It asserts structure only, emits no `passed` key and compares
nothing against any budget (D-09).

## Verification

Every command below was run in this worktree on 2026-09-05, on an Apple M5 Pro under Xcode 26.3
(Swift 6.2, macOS 26.5 build 25F71). Exit codes are as captured, not as expected.

| Check | Result |
|---|---|
| `swift test --package-path Packages/CortexDemo` | 44 tests in 5 suites passed (33 before this plan, +11) |
| Same, with `CORTEX_MODEL_URL` set to the shipped `.mlpackage` | 44 tests passed (the 10-05 repair at `95c73c7` held) |
| `swift test --package-path Packages/CortexIPC` | 26 tests in 5 suites passed, no Phase-2 regression |
| `git diff --stat Packages/CortexIPC/` | empty; the consumer extension lives in the smoke, not the shipped session library |
| `./Tools/scripts/hotpath-policy.sh` | exit 0 |
| `./Tools/scripts/hotpath-policy.sh --self-test` | exit 0, the gate bites on every forbidden token |
| `swift build --package-path Packages/CortexCore` | Build complete |
| `xcodegen generate` then `xcodebuild build -project Cortex.xcodeproj -scheme CortexDaemon -configuration Debug CODE_SIGNING_ALLOWED=NO` | `** BUILD SUCCEEDED **` |

### The Seam B runs, with their exit codes

**Clean clone, no export configured. This is the CI path.** Exit 0.

```
  source        = <repo>/Decoder/tests/fixtures/tiny_replay.json
  data_source   = synthetic_fixture   [no export was configured, so the COMMITTED SYNTHETIC
                                       FIXTURE is the source; this run measures the chain,
                                       never real data]
  session       = tiny_replay_synthetic
  bins          = 256, channels = 96
  frames        = 256 (requested 512, clamped to the source's n_bins)

  frames_accepted         = 256   frames_dropped = 0
  windows_completed       = 225   windows_filled = 225
  decodes_succeeded       = 0   (model_backed = false)
  cursor_updates          = 225
  pointer_reports_encoded = 225
  doorbell_wakes          = 256
  payload integrity       = the newest bin of the first window matches export bin 32 exactly
  AES-GCM                 = applied to every frame; there is no bypass path
```

The emitted artifact, `Packages/CortexDemo/.bench/seam_b.json` (`.bench/` is gitignored, so the
bytes are transcribed here rather than committed):

```json
{
  "aes_gcm" : "applied to every frame; no bypass path exists",
  "boundary" : "export bin -> AES-GCM seal -> shm ring -> doorbell -> decrypt -> ordering -> 32-bin accumulation -> SpikeInputBuffer fill -> NDT1 decode -> cursor integration -> HID pointer report encode",
  "cursor_updates" : 225,
  "data_source" : "synthetic_fixture",
  "decodes_succeeded" : 0,
  "device" : "Apple M5 Pro (arm64)",
  "disclosure" : "synthetic fixture - not real neural data; exists so the export format is covered on a clean clone",
  "doorbell_wakes" : 256,
  "env" : {
    "bin_ms" : "20.0",
    "channels" : "96",
    "frames_requested" : "512",
    "os" : "Version 26.5 (Build 25F71)",
    "ring_depth" : "1024",
    "ring_slot_stride" : "288",
    "seq_len" : "32",
    "source_path" : "tiny_replay.json",
    "source_reason" : "no export was configured, so the COMMITTED SYNTHETIC FIXTURE is the source; this run measures the chain, never real data",
    "swift_compiler" : ">=6.2"
  },
  "export_sidecar_sha256" : "6d3251a0dffa3cb23c8e726ddaeca7919b4ba40fe36e88addfcf3c94b9d91291",
  "frames_accepted" : 256,
  "frames_dropped" : 0,
  "model_backed" : false,
  "not_comparable_to" : "the Phase-8 glass-to-glass p99 and the Plan 10-04 Seam A p99. Seam B is a strictly WIDER boundary (10-PREREGISTRATION section 9), and the Phase-8 number had no IPC leg and was not model-backed (10-RESEARCH Correction 2).",
  "pointer_reports_encoded" : 225,
  "process_boundary" : "in_process",
  "schema_version" : 1,
  "seam" : "B",
  "session_id" : "tiny_replay_synthetic",
  "spike_buffer_backed" : true,
  "status" : "corroborating",
  "windows_completed" : 225,
  "windows_filled" : 225
}
```

The plan's non-vacuity probe:

```
$ python3 -c "import json;d=json.load(open('Packages/CortexDemo/.bench/seam_b.json'));..."
seam B non-vacuous: synthetic_fixture 225
```

**The anti-vacuity assertion is proven to bite.** `--frames 8` is below the 32-bin window, so the run
resolves a source and completes zero windows. Exit 133.

```
CortexSeamBSmoke/main.swift:436: Precondition failed: windows_completed is 0 after 8 accepted
frames: the chain was never exercised through a decode window. 32 contiguous bins are needed to
complete one, so --frames must be at least 32. A run that measures nothing must not report success.
```

**Real export, clean.** Exit 0. `frames_accepted 512, frames_dropped 0, windows_completed 481,
cursor_updates 481, pointer_reports_encoded 481, doorbell_wakes 512, data_source real,
session indy_20160630_01, 73160 bins`.

**Real export, model-backed** (`--model .../ndt1_real_vel_sweep_fp16.mlpackage --frames 128`). Exit 0.
`windows_completed 97, decodes_succeeded 97, model_backed true`. The shipped NDT1 model is genuinely
in the Seam B chain, and `decodes_succeeded == windows_completed` is asserted whenever a model is
supplied.

**The tamper control, executed (T-10-06-01).** One bit of the AES-GCM tag on frame 256 is flipped
before the slot is written; everything else is byte-identical, so only the authentication tag can
reject it. Exit 1.

```
CortexSeamBSmoke: AES-GCM open FAILED CLOSED at seq 256 - authenticationFailure
  frames produced up to and including the tampered one = 256
  frames the accumulator ACCEPTED                       = 255
  windows_completed                                     = 224
  The tampered frame was never decrypted, never decoded, and never entered a decode window.
```

The two `precondition`s behind those lines assert on the ACCUMULATOR's own counters rather than this
loop's, because `count` is a rolling fill that sits at 32 mid-stream either way and would prove
nothing. What proves the tampered frame never entered the chain is that the accumulator accepted
exactly one fewer frame than was produced, and that no window formed for it.

**The throw-on-bad-export control, executed (T-10-06-02).** `CORTEX_REPLAY_EXPORT` pointed at a
nonexistent path. The daemon exits 70 without producing a frame:

```
Cortex daemon (Phase 2). mode=produce. App Group: group.com.donovansantine.cortex.shared.
Cortex daemon (mode=produce) failed: notFound(path: "/tmp/definitely-not-an-export.json")
```

With the real export present the banner names what is actually being replayed, and with none set it
names the Phase-2 pattern:

```
Cortex daemon payload source: replay export, real bins (D-05): session=indy_20160630_01, bins=73160, channels=96
Cortex daemon payload source: Phase-2 synthetic pattern (CORTEX_REPLAY_EXPORT unset)
```

Both daemon runs then fail at `parentAwaitReply(268451844)`. That is PRE-EXISTING and unrelated: it
reproduces identically with and without an export configured, and it is the same two-process
rendezvous limitation Phase 2 already XCTSkip-guards. See the deviation below.

### Acceptance greps

`grep -F` on `Sources/CortexSeamBSmoke/main.swift`: `tiny_replay.json`, `synthetic_fixture`,
`CursorIntegrator`, `BCIInputPointerReport`, `RollingSpikeWindow`, `SpikeInputBuffer`, `seam_b.json`,
`"B"` and `decode(` all match. `grep -nE '(passed|verdict)\s*='` returns nothing (D-09). The Phase-8
literal `8.3 ms` appears on exactly two lines, both comments, one the verbatim section-9 quote that
itself says "never against 8.3 ms" and one an explicit non-comparability disclaimer.

`grep -F 'Seam B chain smoke on the synthetic fixture' .github/workflows/ci.yml` matches exactly once
and `git diff .github/workflows/ci.yml` shows only that one added step.

On `Apps/CortexDaemon/Producer.swift`: `CORTEX_REPLAY_EXPORT` and `sidecarURLFromEnvironment` match,
`public func binF16` matches, `public func patternF16` still matches, `isReplayBacked` matches,
`grep -cF 'patternF16(forSeq: seq)'` returns exactly 1 and it is inside `binF16`, and
`grep -nEi 'skip[_ ]?(encrypt|crypto)|plaintext|noCrypto|disableAes'` returns nothing.

## Deviations from Plan

### 1. [Rule 3 - Blocking] Seam B runs in one process, not two

**Found during:** Task 3, before writing a line of the smoke.

**Issue.** The plan specifies "posix_spawn THIS binary with a `consume` argument, producer half in
the parent, consumer half in the child", and also requires a CI step that runs the result. Those two
requirements are in conflict on this codebase. The repo's own Phase-2 decision, written in
`HarnessE2ETests`, is that `testInProcessRoundTrip` is "the ALWAYS-ON CI correctness gate (runs on
the macos-15/M1 runner with no spawn flakiness)" while `testTwoProcessSpawnRoundTrip` is
XCTSkip-guarded. Re-measured today on the developer machine, and BEFORE any Phase-10 change, the
daemon's rendezvous fails: the child returns `MACH_SEND_INVALID_DEST` (0x10000003) from
`Rendezvous.childAcquire` and the parent then times out in `parentAwaitReply`
(`MACH_RCV_TIMED_OUT`, 0x10004004). It fails identically with and without a replay export, so it is
not caused by Task 2. Building the new CI gate on that mechanism would produce a red or flaky step,
which is the opposite of what review D-7 asked the gate to be.

**Fix.** The chain runs in one process in producer/consumer lock-step over a real `shm_open`ed
`ShmRing`, a real `Doorbell` socketpair, real AES-GCM and the real FlatBuffers codec. Every stage
10-PREREGISTRATION section 9 names is exercised; section 9's definition of Seam B does not name a
process boundary. The one thing not crossed IS the process boundary, and the artifact says so in a
first-class `process_boundary: "in_process"` field so no downstream reader can overstate it. The file
header states the deviation, the evidence and the Phase-2 precedent in full.

**What this costs, stated plainly.** Seam B as measured does not prove the Mach rendezvous, the
`FDChannel` fileport handoff or the `SessionKeyChannel` key delivery. Those three legs remain covered
only by the XCTSkip-guarded Phase-2 test. Everything else in section 9's list is covered.

**Committed in:** `807feb3`

### 2. [Rule 3 - Blocking] The plan's SwiftPM package name is backwards

**Found during:** Task 3, at the first `swift build`.

**Issue.** The plan directs `.product(name:..., package: "CortexIPCPackage")`. That fails:
`unknown package 'CortexIPCPackage' in dependencies of target 'CortexSeamBSmoke'; valid packages are:
... 'CortexIPC'`. For a local path dependency SwiftPM derives the package IDENTITY from the
DIRECTORY, not from the manifest's `name:`.

**Fix.** Both `.package(path:)` and `.product(package:)` take `CortexIPC`. The note the plan asked
for is still present and still mentions `CortexIPCPackage`, but now states the measured fact rather
than the assumed one. This is the first SwiftPM consumer of that package, so nothing in the repo had
pinned the answer before.

**Committed in:** `807feb3`

### 3. [Rule 1 - Bug] The banner would have created a second, colliding Producer

**Found during:** Task 2b.

**Issue.** The plan's "add one line to the mode banner ... using `producer.isReplayBacked`" requires a
`Producer` instance, but `main.swift` has none at that point. Constructing one would open a SECOND
`ShmRing` under the same global `CORTEX_SHM_NAME` and write a second single-process Keychain entry,
both of which `Harness.runParent`'s own producer then contends for, and the probe's `deinit` calls
`SessionKeychain.delete()`.

**Fix.** `Producer.configuredPayloadSourceDescription()`, a static that resolves the same env seam
with no Keychain write, no shm region and no doorbell, and throws on a set-but-unloadable export
exactly as `init` does so the banner can never announce a source the producer would refuse. The
instance properties `isReplayBacked` and `replaySessionId` are still there and are what the smoke
records.

**Committed in:** `cce92bd`

### 4. [Rule 2 - Missing critical] The doorbell leg was counted, not assumed

**Found during:** Task 3.

**Issue.** The plan's counter list stops at the decode and its CI comment claims the doorbell is
exercised. `Producer.produce` rings the doorbell and never reads it, so a broken notification path
would be invisible, and at a large `--frames` the undrained socketpair could fill.

**Fix.** The smoke arms the doorbell and, per frame, drains it with `wait(timeoutNanos: 0)` and
asserts the woken seq equals the written seq, counting `doorbell_wakes`. A final precondition
requires `doorbell_wakes == frames`. Measured 256 of 256 on the fixture and 512 of 512 on the real
export.

**Committed in:** `807feb3`

### 5. [Rule 2 - Missing critical] `Int(seq)` could trap

**Found during:** Task 2a.

**Issue.** The plan writes `replay.window(endingAt: Int(seq) % replay.binCount, length: 1)`.
`Int(UInt64)` traps above `Int.max`.

**Fix.** The modulo is taken in `UInt64` first, so the `Int` conversion is of a value already less
than `binCount` and cannot trap. Same value for every reachable `seq`.

**Committed in:** `cce92bd`

### 6. [Rule 3 - Blocking] `fill(_:)` had to be `@MainActor`

**Found during:** Task 1, GREEN phase.

**Issue.** The plan pins `public func fill(_ buffer: SpikeInputBuffer) throws(ZeroCopyInputError)` on
a `nonisolated` class, but `SpikeInputBuffer` is MainActor-isolated (CortexDecoder carries
`.defaultIsolation(MainActor.self)`), so the call does not compile from a nonisolated context.

**Fix.** `fill(_:)` is `@MainActor`; `push` and `window()` stay nonisolated so a consumer thread can
accumulate off the main actor as `HarnessConsumer` does. Only the handoff crosses. The signature the
plan pinned is otherwise unchanged, and the two `fill` tests carry `@MainActor`.

**Committed in:** `6100311`

### 7. [Rule 3 - Blocking, environment only] Two artifacts symlinked into the worktree

`Decoder/exports`, `Decoder/data` and `Packages/CortexRing/CortexRingFFI.xcframework` are all
gitignored build artifacts absent from a fresh worktree. Without the xcframework the whole package
graph fails to resolve and no `xcodebuild` invocation runs at all. All three were symlinked from the
canonical checkout. Nothing from any of them is committed; `git status` shows them untracked and no
`git add .` was used anywhere in this plan.

### Not a deviation, but recorded: `xcodegen` damage was reverted

`xcodegen generate` STRIPS four hand-added SYS-05 keys from the tracked `Apps/CortexMac/Info.plist`
and `Apps/CortexiOS/Info.plist`. Both files were restored with `git checkout --` and nothing was
committed. Logged as item 2 in `deferred-items.md`.

## Notes for later plans

**Plan 10-09: the CI step is ALREADY WIRED.** `Seam B chain smoke on the synthetic fixture (RD-08)`
sits in `build-and-lint` immediately after the CortexDemo test step. Do not add a second one. Its
schema test can read `data_source`, `process_boundary`, `seam` and `boundary` from
`.bench/seam_b.json`; the file carries no `passed` key by construction.

**`.github/workflows/ci.yml` was also touched by Plan 10-07.** Per the parallel-execution brief, this
plan's edit is the single added step shown above and takes precedence on any conflict there.

**A real CI run will trip `ci.yml`'s missing `Cortex.xcworkspace`** (three `xcodebuild -workspace`
steps reference a workspace nothing generates). Logged as item 3 in `deferred-items.md`.

## Known Stubs

None. Every counter reported is produced by code that ran, every leg named in the `boundary` string
is executed, and the one thing not exercised (the process boundary) is a named JSON field rather than
an unstated gap.

## Threat Flags

None. This plan adds no new network endpoint, no new auth path and no schema change at a trust
boundary. It adds one new file-reading path on the daemon (`ReplayExport`, already validated by Plan
10-04's ten pre-allocation checks) and one new SwiftPM executable that reaches the existing transport.
The four threats the plan registered as `mitigate` are each closed by an EXECUTED control, transcripts
above: T-10-06-01 (tamper, exit 1), T-10-06-02 (throw on bad export, exit 70), T-10-06-03 (ordering
and gap, named tests), T-10-06-04 (no crypto-bypass token, grep returns nothing), T-10-06-08
(anti-vacuity, exit 133), T-10-06-09 (`data_source` in the artifact), T-10-06-06 (`git diff --stat
Packages/CortexIPC/` empty, hot-path policy and self-test both exit 0), T-10-06-07 (`seam: "B"` plus
a `not_comparable_to` string).

## Why status is PARTIAL, not PASS

Every task executed, every task is committed, and every verification command is green. PARTIAL
reflects two flagged gaps, both documented above rather than papered over:

1. Seam B does not cross a process boundary, so the Mach rendezvous, the `FDChannel` fileport handoff
   and the `SessionKeyChannel` key delivery are NOT covered by this measurement. That is a real
   narrowing of what the plan promised, even though it is the repo's own established idiom and the
   alternative was a red gate.
2. Six out-of-scope findings are logged to `deferred-items.md`, one of which (`ci.yml` naming a
   `Cortex.xcworkspace` that nothing generates) will fail the first real CI run for reasons unrelated
   to this plan.

## Self-Check: PASSED

Files claimed created, verified present on disk:

```
FOUND: Packages/CortexDemo/Sources/CortexDemo/RollingSpikeWindow.swift
FOUND: Packages/CortexDemo/Tests/CortexDemoTests/RollingSpikeWindowTests.swift
FOUND: Packages/CortexDemo/Sources/CortexSeamBSmoke/main.swift
FOUND: Packages/CortexDemo/Package.resolved
FOUND: Packages/CortexDemo/.bench/seam_b.json
```

Commits claimed, verified in `git log`:

```
FOUND: 6100311  feat(10-06): add RollingSpikeWindow, the one-bin-in 32-bin-window-out accumulator
FOUND: cce92bd  feat(10-06): point the daemon producer at the real export (D-05), AES-GCM unchanged
FOUND: 807feb3  feat(10-06): add CortexSeamBSmoke, the D-05 chain end to end, and wire its CI gate
```
