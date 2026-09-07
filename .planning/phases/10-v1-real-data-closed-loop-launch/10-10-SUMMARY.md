---
status: PASS
agent: main-thread (run inline at the user's request, not a donny-executor subagent)
phase: 10-v1-real-data-closed-loop-launch
plan: 10
subsystem: evidence
tags: [rd-08, rd-10, d-15, d-16, d-17, human-uat, device-gates, capture, entitlements, sc2, renderer, ablation]

# Dependency graph
requires:
  - phase: 10-v1-real-data-closed-loop-launch
    provides: "Plan 10-08's 10-replay.json / 10-replay-evidence.md and its sc2_adjudication object; Plan 10-07's four-arm 10-refit-real.json; Plan 10-01's 10-ceiling.json replay reference; Plan 10-04's injected SpikeWindowSource and ReplayExport; 10-PREREGISTRATION sections 3, 7, 12, 15, 16, 18"
  - phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
    provides: "09-HUMAN-UAT.md as the template and the never-auto-approve rule; the shipped ndt1_real_vel_sweep_fp16.mlpackage"
  - phase: 08-apple-bci-hid-integration-distribution-v0-ship
    provides: "the three Phase-8 device gates carried forward; the CortexMac GUI shell and its glass-to-glass instrumentation strip"
  - phase: 06-cametaldisplaylink-120hz-renderer-with-30-30-webgrid
    provides: "the WebgridView / display-link adapters / Webgrid.metal render path the capture exercises unchanged in structure"
provides:
  - "10-HUMAN-UAT.md - six never-auto-approved device gates, every value field 'not measured', all six DEFERRED by the user"
  - "Tools/capture/CortexMac.capture.entitlements + README.md - the signing-only override that makes CortexMac buildable under the free Personal team with every committed entitlements file byte-identical"
  - "10-demo-capture-evidence.md - the D-16 capture, device-labeled and provenance-bound, with all six named observations measured out of the recording"
  - "sc2_disposition = not_met and sc2_rule = B in 10-replay.json, the row section 15 selects, confirmed by the user"
  - "The phase's only MEASURED display cadence: 120.00 FPS / 8.33 ms sustained over 30 s, which 10-replay.json's cadence_provenance names as this capture"
  - "A live two-arm side-by-side demo (kalman_only vs refit) so the target-determined arm cannot be mistaken for a decoding result on screen"
affects: [10-09, 10-11, 10-12, 10-13, 10-14, 10-17, rd-08, rd-10, sc2]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A capability a free team cannot provision is dropped for signing only, via CODE_SIGN_ENTITLEMENTS on the build command, never by editing a committed entitlements file that a policy gate asserts"
    - "A recorded demo names its data source ON SCREEN, sourced from the loaded artifact's own session id, so a silent synthetic fallback cannot be recorded as real-data evidence"
    - "Both ablation arms render side by side with captions stating what each is and is not, because showing only the target-determined arm is how target knowledge gets mistaken for a decode"
    - "Observations of a capture are derived by decoding the pinned artifact, with the extraction commands recorded, rather than reported from memory"
    - "A demo that does not implement the scoring rule says so, so a viewer does not read its behaviour as a hit count"

key-files:
  created:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-HUMAN-UAT.md
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-demo-capture-evidence.md
    - Tools/capture/CortexMac.capture.entitlements
    - Tools/capture/README.md
    - Packages/CortexRender/Sources/CortexRender/TargetChannel.swift
  modified:
    - .planning/phases/10-v1-real-data-closed-loop-launch/10-replay.json
    - Apps/CortexMac/ContentView.swift
    - Packages/CortexDemo/Sources/CortexDemo/ClosedLoopPipeline.swift
    - Packages/CortexRender/Sources/CortexRender/Webgrid.metal
    - Packages/CortexRender/Sources/CortexRender/WebgridParams.swift
    - Packages/CortexRender/Sources/CortexRender/WebgridView.swift
    - Packages/CortexRender/Sources/CortexRender/MacDisplayLinkAdapter.swift
    - Packages/CortexRender/Sources/CortexRender/iOSDisplayLinkAdapter.swift

key-decisions:
  - "All six device gates DEFERRED on the user's own reply. No iPad-M4 number was written anywhere - not in 10-HUMAN-UAT.md, not in 10-replay-evidence.md, not in 10-replay.json, not in the README"
  - "sc2_disposition = not_met, sc2_rule = B, on the user's answer 'Not met, on attributable arms'. Row B was selected on section 7's attributability rule rather than section 15's literal first column, because refit's 70 hits are target-determined by construction and publishing them as SC#2 met would present target knowledge as a decoding result"
  - "Row B's literal text ('hits == 0 on all four arms') does NOT match this outcome either, since refit scored 70 and refit_reversed_target 2. The mismatch is recorded in the evidence as a mismatch rather than quietly reinterpreted"
  - "The 48.6 MB .mov is NOT committed. It is pinned by sha256 instead, because Plan 10-17 pushes this repository and the full-screen capture includes the macOS Dock. No README still frame was added either"
  - "The six named observations were measured out of the recording by decoding it, with the ffmpeg commands and the colour thresholds recorded, rather than eyeballed. The under-sampling limit of the 1 Hz and 5 Hz sweeps is stated"
  - "Only the TeamIdentifier line of codesign -dvv is transcribed. Its Authority line carries the signing certificate's email address, which does not belong in a repository about to be pushed"
  - "The GUI runs no dwell-to-select scoring. ClosedLoopPipeline.tick() computes an instantaneous onTarget and nothing else; runToHit / runArm are bench-only. The evidence says so explicitly so 'no hit in the recording' is not read as a re-measurement of the published counts"
  - "ROADMAP.md:204's stale '3-way ablation' wording was FLAGGED to the user and not edited, per section 15's own instruction"

patterns-established:
  - "A checkpoint's six named observations get values derived from the artifact, with the derivation method written beside them, so a reader can re-derive them from the same bytes"
  - "A live HUD reading is not compared to an offscreen histogram without saying why they are different instruments measuring different workloads"

requirements-completed: [RD-10]
requirements-advanced: [RD-08]

# Metrics
metrics:
  duration: ~5 h (spanning a usage-limit pause and five capture iterations)
  completed: 2026-09-06
  tasks: 3
  commits: 7
  files-changed: 13
---

# Phase 10 Plan 10: device gates, the M5 Pro demo capture, and the SC#2 disposition

**All six iPad-M4 / TestFlight / HID device gates are DEFERRED by the user with no number invented for any of them; the real-data loop was captured running at a measured, sustained 120.00 FPS / 8.33 ms on the M5 Pro against `indy_20160630_01`; no webgrid hit occurred in 61.38 s on either arm, with the target-blind arm's closest approach 4.7 acquisition radii away; and SC#2 is recorded `not_met` at row B on the user's confirmation.**

## Task 1: the six device gates

`10-HUMAN-UAT.md` was written from the `09-HUMAN-UAT.md` template with every value field reading
`not measured`, presented, and **all six recorded DEFERRED on the user's reply**:

| # | Gate | Prerequisite named | Corroborating stand-in |
|---|---|---|---|
| 1 | Phase-8 canonical iPad-Pro-M4 glass-to-glass latency | iPad Pro M4 not provisioned | Phase-8 Mac p99 8,318,256 ns |
| 2 | Phase-8 live TestFlight submission | Apple Developer Program not enrolled | none |
| 3 | On-device BCI HID registration as a Switch Control provider | the entitlement is Apple-managed and request-gated | the instrumented in-app round trip |
| 4 | Phase-9 canonical iPad-Pro-M4 decoder p99 | iPad Pro M4 not provisioned | iPad Air 11-inch M2, p99 0.5790 ms |
| 5 | Canonical iPad-Pro-M4 Seam A p99 on the real-data path | iPad Pro M4 not provisioned | Seam A M5 Pro p99 8,831,017 ns |
| 6 | Canonical iPad-Pro-M4 120 Hz real-data webgrid demonstration | iPad Pro M4 not provisioned | this plan's Task 2 capture |

`grep -cE 'LAT-0[1-8]'` returns 0: the retired photodiode requirements are Future work in the ROADMAP,
not deferred gates, and are not presented as any.

## Task 2: the capture

### The blocker, resolved as planned

`CortexMac` did not build. `com.apple.developer.hid.virtual.device` is declared in all three signed
targets and a free Personal team cannot provision it. `Tools/capture/CortexMac.capture.entitlements` is
the committed `Apps/CortexMac/Cortex.entitlements` minus exactly that key, passed on the command line:

```
xcodebuild -project Cortex.xcodeproj -scheme CortexMac -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements \
  -allowProvisioningUpdates build

** BUILD SUCCEEDED **
```

```
$ codesign -d --entitlements - --xml "$APP" | plutil -p -
{
  "com.apple.application-identifier" => "57YW6M29S7.com.donovansantine.cortex.mac"
  "com.apple.developer.team-identifier" => "57YW6M29S7"
  "com.apple.security.application-groups" => [ 0 => "group.com.donovansantine.cortex.shared" ]
  "com.apple.security.get-task-allow" => true
  "keychain-access-groups" => [ 0 => "57YW6M29S7.com.donovansantine.cortex.shared" ]
}
$ codesign -dvv "$APP" 2>&1 | grep TeamIdentifier
TeamIdentifier=57YW6M29S7
```

`hid.virtual.device` absent, `application-groups` present, free Personal team.
`git diff --stat` over the three committed entitlements files and `project.yml` is EMPTY;
`hid-surface-policy.sh` and `--self-test` both exit 0; `git status --short` over the two `Info.plist`
files is empty after the XcodeGen SYS-05 key-strip was reverted.

Only the `TeamIdentifier` line of `codesign -dvv` is transcribed anywhere. Its `Authority` line carries
the signing certificate's email address, and Plan 10-17 pushes this repository.

### Four defects found and fixed while getting to a usable recording

The capture went through five iterations. Each of the first four exposed a real defect, none of which
touched a published number:

1. **Unit mismatch, 17.168x too fast.** `CortexReplayBench` converts NDT1's cm/s to grid-units/s;
   `ClosedLoopPipeline.tick()` did not, so the GUI cursor ran at 46.94 cells/s against an expected 2.7.
   Fixed with `modelVelocityGridUnitsPerCm` (default 1.0, so synthetic callers are unchanged), applied
   to the model output only. **No published number affected**: the ablation came from the bench, which
   converts correctly.
2. **Stale ReFIT target.** `ClosedLoopPipeline.target` was set at init with no setter, so the ReFIT arm
   steered at the default centre cell (13,13) while the red square drew the real per-trial target. Fixed
   with `setTarget(_:)` plus a `rotationEnabled` flag.
3. **`drawableSize` never tracked bounds.** Both `WebgridMetalNSView` and `WebgridMetalUIView` carried a
   comment asserting the layer resizes with the view automatically, which `CAMetalLayer` does not do.
   Invisible while the grid was the whole window; the side-by-side layout made it visible as a drawable
   of 449x1793, correct in width but the full window height, so square cells rendered as tall
   rectangles. Fixed on both hosts.
4. **The demo showed one arm.** Showing only `refit` is exactly how a target-determined result gets read
   as a decoding result. The window now runs **both arms side by side** on the same session and the same
   decoded spikes, each captioned with what it is and is not and with its published hit count.

The renderer was also restyled to the Neuralink reference the user supplied: thin white rules at alpha
0.15 on near-black, a ring-plus-dot cursor, and a red target square, replacing 900 filled rounded cells
and a filled disc.

### The six named observations

Measured by decoding the recording, not reported from memory. Full method in the evidence file.

| # | Observation | Value |
|---|---|---|
| a | Frame cadence | **120.00 FPS sustained t = 25..55 s**; 115.20 at t = 5 (startup), 113.84 at t = 60 (recording stop) |
| b | HUD frame time | **Frame Interval 8.33 ms** at every 120.00 sample; GPU 0.40..0.47 ms |
| c | Source label | **`spike source: real: indy_20160630_01`**, constant at nine sample points; never `synthetic` |
| d | Cursor motion | Driven, not frozen, not Lissajous. cos(step, direction to target): `kalman_only` **-0.011**, `refit` **+0.066** |
| e | Webgrid hit | **None, on either arm.** Closest approach `kalman_only` 2.36 cells (4.7 radii), `refit` 0.71 cells (1.4 radii) |
| f | Duration | **61.38 s**, 3521 frames at 120 fps |

Observation (a) is load-bearing rather than illustrative: `10-replay.json`'s `cadence_provenance` names
this capture as the phase's measured display cadence, the modelled 120 Hz arithmetic in Seam A being
arithmetic rather than a `CAMetalDisplayLink` reading.

Observation (b) is explicitly **not** compared like-for-like to Phase 6's 0.1618 ms p99. That is an
offscreen single-encode histogram at 2752x2064; this is a live composited reading with two render
surfaces and a 50 Hz CoreML timer running. Different instrument, different workload; the evidence says so
rather than implying a regression.

Observation (e) carries the disclosure that **the GUI does not score hits at all**:
`ClosedLoopPipeline.tick()` computes an instantaneous `onTarget`, while the dwell-to-select rule that
produced the published counts lives in `runToHit` / `runArm` and is bench-only. A zero on screen is not a
re-measurement of 0-of-1025.

### The recording

`Screen Recording 2026-09-06 at 11.48.31 PM.mov`, 48,598,291 bytes, 61.38 s, sha256
`bbe654cdc8d77b343cf3fda8145bd3ec455b612f8aa1aff4519efe7f115f48fd`. Kept OUTSIDE the repository and
pinned by digest: it is a 48.6 MB binary, Plan 10-17 pushes the repo, and a full-screen capture includes
the macOS Dock. Swept at nine points for the three T-10-10-05 categories: no email address, no signing
identity, no filesystem path. No README still frame was added.

The filename contains U+202F NARROW NO-BREAK SPACE before `PM`. A path retyped with an ordinary space
fails to open with `No such file or directory`, which cost two tool calls to diagnose; glob it.

## Task 3: RD-08's evidence basis and the SC#2 disposition

**3a.** `10-demo-capture-evidence.md` records RD-08's evidence as five headless committed artifacts with
the recording listed last and labeled an illustration: the four-arm hit count (`10-refit-real.json`), the
recorded-cursor replay reference committed before it (`10-ceiling.json`, 147 of 1025), the full D-05
chain counters (Seam B: 73,128 decodes and pointer reports, 0 frames dropped, plus the `--tamper` control
that failed closed), Seam A's p99 on the real-data path (8,831,017 ns, model-backed on 2294 of 2294
ticks), and `CortexDecoderBench` on the shipped model. A capture failure would not have moved any of them.

**3b.** The measured inputs and the row:

| Arm | Rotation target source | Hits of 1025 | p1 distance |
|---|---|---|---|
| `raw` | none | **0** | 16.5820 mm |
| `kalman_only` | none | **0** | 16.6158 mm |
| `refit` | `true_track` | 70 | 0.8299 mm |
| `refit_reversed_target` | `reversed_track` | 2 | 3.9085 mm |

Replay reference 147 of 1025; radius 2.8613660406415042 mm; dwell 0.3 s. Both pre-registered values,
unchanged.

Section 15's literal first column selects row A on `refit`'s 70. Section 7, pre-registered before any
number existed, makes `refit`'s heading target-determined by construction and only `raw` / `kalman_only`
attributable to the decode; those are 0 of 1025 against a reference of 147, which is row B's shape. Row C
is ruled out because the reference is 147, not 0.

**The user answered "Not met, on attributable arms."** `sc2_disposition` = `not_met` and `sc2_rule` = `B`
are written into `10-replay.json` as a two-line diff. No acquisition parameter was relaxed. Row B's
literal text ("hits == 0 on all four arms") does not match this outcome either, and the evidence records
that mismatch rather than reinterpreting the row quietly.

`ROADMAP.md:204`'s stale "3-way ablation" wording is **flagged, not edited**.

## Verification

```
grep -c 'not measured' 10-HUMAN-UAT.md                      -> 33
grep -cE 'LAT-0[1-8]' 10-HUMAN-UAT.md                       -> 0
swift test --package-path Packages/CortexDemo               -> 44 tests, 5 suites, PASSED
./Tools/scripts/render-policy.sh    (+ --self-test)         -> 0, 0
./Tools/scripts/hid-surface-policy.sh (+ --self-test)       -> 0, 0
git diff --stat -- Apps/*/Cortex.entitlements project.yml   -> EMPTY
git status --short -- Apps/*/Info.plist                     -> empty
xcodebuild ... CODE_SIGN_ENTITLEMENTS=...capture...         -> ** BUILD SUCCEEDED **
Task 1 / 2 / 3 automated verifies                           -> all pass; sc2 not_met rule B
10-demo-capture-evidence.md                                 -> 373 lines (min 110)
```

## Deviations from the plan

- **Run inline on the main thread rather than as a `donny-executor` subagent**, at the user's explicit
  request, so the checkpoints were visible as they happened.
- **Four code defects were fixed that the plan did not anticipate**, all inside the diff the plan already
  authorised for Task 2c ("wire the GUI to the real source"). The unit mismatch and the stale target were
  blocking: without them the recording would have shown a cursor moving 17x too fast toward the wrong
  cell. `drawableSize` and the single-arm layout were exposed by the two-arm change.
- **The recording is referenced by digest rather than saved under the phase directory.** The plan allowed
  "or a path you name"; the reason for choosing outside-the-repo is recorded in the evidence.
- **Task 2's six observations were measured by the executor from the user's recording** rather than
  reported by the user in prose. The user supplied the capture; the values were derived from it, with the
  extraction commands recorded so they can be re-derived. No observation was asserted that the recording
  does not show.

## Open flags carried forward

- `ROADMAP.md:204` says "3-way ablation"; D-04 locks four arms. User's call.
- `ci.yml:445,461,477` reference `Cortex.xcworkspace`, which `xcodegen` does not produce. Assigned to
  Plan 10-09; must be fixed before Plan 10-17's first CI run.
- Seam B is `in_process` only; the two-process `posix_spawn` rendezvous fails with
  `MACH_SEND_INVALID_DEST` and did so before any Phase-10 change. Needs a disclosure line in Plan 10-12's
  README rewrite.
- The `refit` arm's on-screen directional bias is weak (+0.066 mean cosine per 0.1 s step). The direction
  is the pre-registered one and the magnitude is reported as small, but a viewer expecting the ReFIT arm
  to visibly fly at the target will not see that.
