# Phase 10 D-16 demo capture: the real-data closed loop running on the M5 Pro

**Status:** CAPTURED, 2026-09-06.
**Device:** Apple M5 Pro MacBook Pro, built-in Liquid Retina XDR ProMotion panel, macOS 26.5 (25F71).
**Label:** `corroborating`. This is a Mac capture. The canonical iPad-Pro-M4 120 Hz real-data webgrid
demonstration is **gate 6 in `10-HUMAN-UAT.md` and remains DEFERRED** (prerequisite: the iPad Pro M4 is
not provisioned). Nothing in this file is an iPad-M4 number.
**Toolchain:** Xcode 26.3 (17C529), Apple Swift 6.2.4, XcodeGen-generated `Cortex.xcodeproj`.
**Session:** `indy_20160630_01`.
**Disclosure, verbatim:** `open-loop replay of a recorded session; the subject was not in the loop`

This capture is the D-16 illustration of the numbers in `10-replay-evidence.md` and
`10-refit-real-evidence.md`. It is **not** their evidentiary basis. See
[What evidences RD-08](#what-evidences-rd-08).

One thing here is load-bearing rather than illustrative. `10-replay.json` records
`cadence_provenance` = "MODELLED 120 Hz present boundary arithmetic, not a CAMetalDisplayLink reading;
the measured display cadence is the Plan 10-10 GUI capture and the deferred iPad-M4 gate". This capture
is therefore the phase's only **measured** display cadence, and observation (a) below is that
measurement.

## The recording

| Field | Value |
|---|---|
| Filename | `Screen Recording 2026-09-06 at 11.48.31 PM.mov` |
| Location | `~/Documents/Screenshots/`, outside the repository, deliberately NOT committed |
| Bytes | 48,598,291 |
| sha256 | `bbe654cdc8d77b343cf3fda8145bd3ec455b612f8aa1aff4519efe7f115f48fd` |
| Duration | 61.38 s |
| Container | QuickTime `.mov`, H.264, 3024x1964, 120 fps, 3521 frames |
| Captured by | the user, `Cmd+Shift+5` full-screen recording |

The filename contains U+202F NARROW NO-BREAK SPACE before `PM`, which macOS writes into screenshot and
recording names. A path retyped with an ordinary space fails to open. Glob it (`*11.48.31*.mov`) rather
than transcribing it.

**Why the file is not committed.** It is a 48.6 MB binary, and Plan 10-17 pushes this repository for the
first time. It is pinned here by sha256 instead, which is what makes the observations below checkable
without carrying the bytes. No still frame is added to the README either; see
[What was checked before nothing was committed](#what-was-checked-before-nothing-was-committed).

## Runbook

Copy-pasteable, from a clean checkout. The `CODE_SIGN_ENTITLEMENTS=` override is not optional: without
it the app does not build at all on a free Personal team. See
[What the capture build is not](#what-the-capture-build-is-not).

```bash
xcodegen generate
git checkout -- Apps/CortexMac/Info.plist Apps/CortexiOS/Info.plist   # XcodeGen strips the SYS-05 keys

xcodebuild -project Cortex.xcodeproj -scheme CortexMac -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS=Tools/capture/CortexMac.capture.entitlements \
  -allowProvisioningUpdates build
# ** BUILD SUCCEEDED **

APP=$(find ~/Library/Developer/Xcode/DerivedData/Cortex-*/Build/Products/Debug \
        -maxdepth 1 -name 'CortexMac.app' | head -1)

CORTEX_REPLAY_EXPORT="$PWD/Decoder/exports/indy_20160630_01.replay.json" \
CORTEX_MODEL_URL="$PWD/Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage" \
MTL_HUD_ENABLED=1 \
"$APP/Contents/MacOS/CortexMac"
```

Both `CORTEX_` variables are required together. With a recorded export and no model the loop would decode
synthetically over real spikes and still look real on screen, which is the Pattern-2 trap in capture form;
`ClosedLoopDriver.init` therefore treats the pair as all-or-nothing and says so in the on-screen label.

Provenance of the replayed data:

| Field | Value |
|---|---|
| `session_id` | `indy_20160630_01` |
| `export_sidecar_sha256` | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` |
| Model | `Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage` (the Phase-9 retrained NDT1) |
| Normalisation | the pre-registered `cursor_bbox_square`, `10-PREREGISTRATION.md` section 3 as amended |

## The six named acceptance observations

Every value below was read out of the recording named above, at stated timestamps, after the fact. None
was reported from memory and none was taken from a re-run. The extraction method is in
[How these were measured](#how-these-were-measured).

### (a) Frame cadence

The Metal HUD's FPS reading, sampled at seven points:

| t (s) | FPS | GPU | Frame Interval |
|---|---|---|---|
| 5 | 115.20 | 0.47 ms | 8.68 ms |
| 15 | 119.01 | 0.42 ms | 8.40 ms |
| 25 | **120.00** | 0.41 ms | **8.33 ms** |
| 35 | **120.00** | 0.42 ms | **8.33 ms** |
| 45 | **120.00** | 0.40 ms | **8.33 ms** |
| 55 | **120.00** | 0.41 ms | **8.33 ms** |
| 60 | 113.84 | 0.42 ms | 8.78 ms |

**120.00 FPS sustained from t = 25 s to t = 55 s**, a 30 s window, with the HUD's frame-interval graph
flat and empty of spikes across all four of those samples. The two readings below 118 are the endpoints:
t = 5 s is app startup (the HUD's graph shows four spikes there) and t = 60 s is the recording being
stopped (three spikes). Both are reported rather than trimmed.

HUD-reported drawable per pane: 1511x1476. Compositing state: `Composited`. Game Mode: `Off`.

### (b) HUD frame time

`Frame Interval` 8.33 ms at every 120.00 FPS sample, which is 1000/120 to the HUD's two decimals.
`GPU` between 0.40 ms and 0.47 ms across all seven samples.

**This GPU figure is not comparable to Phase 6's and must not be read as a regression.**
`06-render-evidence.md` reports p50 0.0798 ms / p99 0.1618 ms over n = 10,000 frames, but that is an
offscreen `commandBuffer.gpuEndTime - gpuStartTime` histogram of a single encode at a 2752x2064 extent
with nothing else running. The HUD figure here is a live, composited reading taken while the window
holds **two** independent render surfaces, each with its own `CAMetalDisplayLink` and its own encode, and
while a 50 Hz CoreML decode timer runs on the main actor. Different instrument, different workload. The
SC#2 bound of 0.4 ms is defined on the Phase-6 measurement, which passed at 0.1618 ms p99; this reading
neither satisfies nor violates it.

### (c) Source label

`spike source: real: indy_20160630_01`

Verified constant at nine sample points spread over the recording (t = 1, 8, 16, 24, 32, 40, 48, 56, 61 s).
It never read `synthetic` and never carried a fallback reason. The label is produced by
`ClosedLoopDriver.init` in `Apps/CortexMac/ContentView.swift` from `export.sidecar.sessionId`, so it names
the export that was actually loaded rather than a constant; `grep -rn 'sourceLabel' Apps/CortexMac/`.

The instrumentation strip also carried, at those same nine points, the SYS-03/04 round-trip line
(`cycle=... seed=... in=item:N/9 out=item:N ptr=(x,y,0) t=...ns`, advancing throughout) and the
software-timed glass-to-glass line reading 5.08, 8.26, 6.52, 6.58, 7.39, 7.22, 7.27, 7.11 and 8.56 ms,
each suffixed `(M5-Pro corroborating)`, above the verbatim D-07 methodology label.

### (d) Cursor motion

Both cursors are driven and neither is frozen. Neither is the Phase-6 Lissajous oscillator: that producer
is not constructed anywhere in `ContentView.swift`, and the two arms diverge on identical decoded input,
which a shared closed-form oscillator could not do.

Two arms render side by side on the same session and the same decoded spikes, which is the point:
`kalman_only` on the left is what the decode does, `refit` on the right is what target knowledge does
(`10-PREREGISTRATION.md` section 7).

Measured over the recording, in grid cells (one cell = 49.2 px at the captured resolution):

| | `kalman_only` (target-blind) | `refit` (target-determined) |
|---|---|---|
| Cursor located in | 301 of 307 frames | 307 of 307 frames |
| Positional extent, 1 Hz sample | 10.6 x 14.8 cells | 2.1 x 2.2 cells |
| Step speed, 10 Hz sample, median | 0.80 cells/s | 1.30 cells/s |
| Step speed, p90 | 1.83 cells/s | 2.24 cells/s |
| cos(step, direction to drawn target), mean | **-0.011** | **+0.066** |
| same, median | +0.014 | +0.200 |

The cosine row is the one that matters, because it tests whether each arm's caption describes what the
recording shows. `kalman_only`'s alignment with the direction to the target is indistinguishable from
zero, which is what a target-blind arm must look like. `refit`'s is positive. The effect is weak per
0.1 s step rather than near +1 because `IntentRotation` rewrites the Kalman filter's **measurement**,
not its output, so the filter's own dynamics dominate over a tenth of a second, and because the rotation
passes the measurement through unchanged inside the acquisition radius. The direction of the difference
is the pre-registered one; its magnitude is small and is reported as small.

The two arms also fail differently, visibly. `kalman_only` drifts to the pane's right edge by t = 25 s,
clamps there, then rides the top edge from t = 45 s onward, tracking left along it at roughly
1.8 cells/s. `refit` stays inside a 2-cell box up and right of centre for the whole minute. Neither
converges on a target.

### (e) Webgrid hit

**No webgrid hit occurred during the recording, on either arm.** Stated without qualification.

Closest approach to the drawn target, measured over all 307 frames of a 5 Hz sweep of the full 61.38 s,
against the pre-registered acquisition radius of 0.50 cells:

| Arm | Closest approach | When | In acquisition radii |
|---|---|---|---|
| `kalman_only` (target-blind) | 2.36 cells | t = 9.2 s | 4.7 |
| `refit` (target-determined) | 0.71 cells | t = 21.2 s | 1.4 |

**The GUI does not score hits, and this is not a re-measurement of the published counts.**
`ClosedLoopPipeline.tick()`, which is what the demo calls, computes an instantaneous `onTarget` boolean
and nothing else. The dwell-to-select rule that produced the published numbers lives in `runToHit` /
`runArm` (dwell 0.30 s, timeout 5.0 s, per-trial reset), which the GUI never calls. The on-screen loop is
a continuous free-run with no trial structure, so a viewer should not expect to watch 70 of 1025
accumulate. Read the recording as an illustration of how the loop moves, and the headless artifacts as
the count.

A zero here is also the expected shape rather than a surprise. `refit` scores 70 of 1025, which is 6.8%
of trials; the two arms attributable to the decode score 0 of 1025. `10-PREREGISTRATION.md` section 15
named row B the expected outcome, in writing, before any number existed. The five-factor account of why
the decoded arms miss is `10-replay-evidence.md` section 5, "The D-11 decomposition, five factors", and
its per-factor object in `10-replay.json`'s `decomposition`. No acquisition parameter was relaxed to
manufacture a hit for the recording: radius, dwell and timeout are the section-3 values, and
`git diff` shows no change to any of them anywhere in the phase.

### (f) Duration

61.38 s wall clock (3521 frames at 120 fps), against the 20 s minimum the plan asked for.

## How these were measured

The observations above are properties of the artifact pinned by sha256 at the top of this file, derived
by decoding it rather than by re-running the app, so they can be re-derived from the same bytes.

- **HUD readings (a, b).** Single-frame seeks, cropped to the HUD box and upscaled with nearest-neighbour
  so the glyphs stay legible: `ffmpeg -ss T -i CAPTURE -frames:v 1 -vf
  "crop=300:180:1190:150,scale=1200:-1:flags=neighbor"`.
- **Source label and instrumentation strip (c).** The same seek, cropped to the menu-bar band
  (`crop=3024:120:0:0`) and the overlay band (`crop=3024:230:0:1610`), stacked across nine timestamps.
- **Cursor and target positions (d, e).** Each pane's rectangle was found once from the faint grid rules
  (mean luminance in 14..90) and clamped to the HUD-reported 1476-pixel drawable height, giving
  1512x1476 per pane and a 1476-pixel letterboxed square, hence 49.2 px per cell. Per frame, the target
  square is the centroid of pixels matching the kernel's `kTargetColor` (`r > 140`, `g < 90`, `b < 100`,
  `r - g > 70`, `r - b > 60`) and the cursor is the centroid of near-white pixels (`r, g, b > 200`). The
  Metal HUD overlays the top of the left pane and was blanked before the cursor search so its glyphs
  could not pose as a cursor.
- **Closest approach (e).** A single streaming decode of the whole file at 5 Hz and half resolution,
  `-vf "fps=5,crop=3024:1476:0:120,scale=1512:738"`, so the minimum is taken over 307 samples rather
  than a handful of seeks.

Two limits worth stating. The 1 Hz and 5 Hz sweeps under-sample a 120 Hz surface, so a closer approach
between samples is possible; the reported minima are upper bounds on the true closest approach, which
only makes the "no hit" conclusion safer, not weaker. And the six frames where `kalman_only`'s cursor was
not located are frames where it sat under the Metal HUD band, not frames where it vanished.

## What the capture build is not

**The recorded build omits `com.apple.developer.hid.virtual.device`, for signing only.**

A free Personal team cannot provision the HID Virtual Device capability, and that entitlement is declared
in all three signed targets, so `xcodebuild` failed before the app ever launched:

```
Cannot create a Mac App Development provisioning profile for "com.donovansantine.cortex.mac".
Personal development teams, including "Donovan Santine", do not support the HID Virtual Device
capability. (in target 'CortexMac')
```

The fix is a build-time override and never a file edit: `Tools/capture/CortexMac.capture.entitlements`
is the committed `Apps/CortexMac/Cortex.entitlements` minus exactly that one key, passed on the command
line via `CODE_SIGN_ENTITLEMENTS=`. `com.apple.security.application-groups` is kept, because the shm IPC
ring depends on it, and so is `keychain-access-groups`; the free team provisions both.

What this does and does not change:

- **The committed entitlements files and `project.yml` are unchanged and still declare the key.**
  `git diff --stat` over `Apps/CortexMac/Cortex.entitlements`, `Apps/CortexiOS/Cortex.entitlements`,
  `Apps/CortexDaemon/Cortex.entitlements` and `project.yml` is empty.
- **`hid-surface-policy.sh` still asserts the key in all three.** The script and its `--self-test` both
  exit 0 after this capture, unchanged. Editing the committed files to make the demo build would have
  disarmed that gate and contradicted ADR-0002's HID story, and XcodeGen regenerates the entitlements
  from `project.yml` anyway, so a hand edit would have been silently reverted.
- **Nothing that runs is affected.** The live `IOHIDUserDevice` path is `#if CORTEX_HID_LIVE`-gated and
  inert under free-team signing whether or not the entitlement is present, so the recording shows the
  same runtime behaviour the shipping configuration would.
- **This is not the shipping configuration.** `Tools/capture/README.md` says so at the point of use.

Verified on the built app that was launched for this capture:

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

`hid.virtual.device` is absent; `application-groups` is present; the team is the free Personal team
`57YW6M29S7`. Only the `TeamIdentifier` line of `codesign -dvv` is transcribed here: its `Authority`
line carries the signing certificate's email address, which does not belong in a repository that
Plan 10-17 pushes.

## What evidences RD-08

RD-08's evidence does not depend on this recording. Every row but the last is headless and committed, so
a failed or skipped capture would have left the requirement's basis untouched.

| Evidence | Artifact | What it establishes | Needs a GUI? |
|---|---|---|---|
| The webgrid hit count on real spikes, four arms | `10-refit-real.json`: `raw` 0, `kalman_only` 0, `refit` 70, `refit_reversed_target` 2, of 1025 | The RD-08 hit criterion itself | No |
| The recorded-cursor replay reference it is scored against | `10-ceiling.json`, 147 of 1025 at radius 2.8613660406415042 mm and dwell 0.3 s, committed in `a72344b` before any decoded number existed | That the count is interpretable | No |
| The full D-05 chain, decode through cursor integration to HID pointer-report encode | Seam B in `10-replay.json`: 73,128 decodes succeeded, 73,128 pointer reports encoded, 0 frames dropped, `model_backed` and `spike_buffer_backed` true, plus the `--tamper` control that failed closed on a flipped AES-GCM tag byte | That the loop closes end to end | No |
| Seam A software-timed p99 on the real-data path, every tick model-backed | Seam A in `10-replay.json`: p50 4,753,046 ns, p99 8,831,017 ns over n = 2286, debug, with `ticks_model_backed` 2294 of `ticks_total` 2294 | The re-derived latency RD-08 asks for | No |
| Decoder throughput on the real Phase-9 model | `CortexDecoderBench`, n = 10,000, p50 132,291 ns, p99 376,417 ns, device CPU, Mac-corroborating | That the shipped model runs on real input | No |
| The recorded demo | this capture | A human-legible ILLUSTRATION of the above | Yes |

## What was checked before nothing was committed

The recording is a full-screen capture, so it was swept for the three categories the threat model names
(T-10-10-05) before any decision about committing it. Nine sample points across the recording
(t = 1, 8, 16, 24, 32, 40, 48, 56, 61 s), covering the menu-bar band and the instrumentation overlay:

- **Email address:** none. The menu bar carries the app name, the standard menus, system status icons and
  the clock.
- **Signing identity:** none. `57YW6M29S7` does not appear on screen, and neither does the certificate
  email that `codesign -dvv` prints.
- **Filesystem path:** none. The window title is `Cortex`; the overlay prints a session id, tick
  counters and a latency figure, no paths.

Not one of those three categories, but a reason the file stays out of the repository regardless: a
full-screen capture includes the macOS Dock, with the user's installed applications and their unread
badge counts. **No still frame from this recording is added to the README**, and the `.mov` is not
committed. Should a README still be wanted later, crop it to the two webgrid panes before it goes near
`readme-policy.sh`.

## SC#2 disposition

Recorded 2026-09-06, from the user's answer at Plan 10-10 Task 3b. The rule applied is
`10-PREREGISTRATION.md` section 15's three-row table, committed in Wave 0 before any hit count existed.
This section selects a row from that table; it does not write a new rule.

**Measured inputs.**

| Arm | Rotation target source | Hits of 1025 | 1st-percentile distance to target |
|---|---|---|---|
| `raw` | none | **0** | 16.5820 mm |
| `kalman_only` | none | **0** | 16.6158 mm |
| `refit` | `true_track` | 70 | 0.8299 mm |
| `refit_reversed_target` | `reversed_track` | 2 | 3.9085 mm |

Recorded-cursor replay reference: **147 of 1025**. Acquisition radius 2.8613660406415042 mm, dwell 0.3 s,
both the pre-registered values.

**The row the rule selects: B. Disposition: `not_met`.**

Two of the table's columns point at different rows on this data, and `10-replay.json`'s
`sc2_adjudication` object records the conflict in full rather than resolving it silently:

- The table's **literal** first column reads "hits >= 1 on the `refit` arm", and `refit` scored 70. That
  is row A.
- But section 7, pre-registered before any number existed, fixes that `IntentRotation` replaces the
  decoded direction with the direction to the known target and keeps only the decoded speed. The `refit`
  and `refit_reversed_target` arms' heading is therefore **target-determined by construction** and their
  counts are not attributable to the decode. On the two arms that never see a target, the outcome is
  0 of 1025 against a replay reference of 147, which is row B's shape.
- Row C is ruled out: the replay reference is 147, not 0, so the geometry does admit hits for the
  recorded trajectory.

Publishing `refit`'s 70 as SC#2 met would present target knowledge as a decoding result. That is the
specific failure this milestone exists to eliminate, and it is why the row is B.

**The user's answer.** "Not met, on attributable arms." Row B confirmed; the zero is published, with the
distance proxy as the primary observable and the five-factor D-11 decomposition beside it. No acquisition
parameter was relaxed. `sc2_disposition` = `not_met` and `sc2_rule` = `B` are written into
`10-replay.json`.

**Section 15 amendment note.** Row B as written requires "hits == 0 on all four arms". Two arms are
non-zero (`refit` 70, `refit_reversed_target` 2), so row B's literal text does not match this outcome
either; the row was selected on section 7's attributability rule, which is the reading section 18 makes
governing. The literal wording is recorded here as not matching rather than quietly reinterpreted.

**Open for the user, not edited by an agent.** `ROADMAP.md:204` still describes "the 3-way ablation"
while D-04 locks a fourth arm. Amending a success criterion, or the wording around one, is the user's
call. It is flagged here, as `10-PREREGISTRATION.md` section 15 requires, and not edited.

## What this capture does not establish

- It is **not** the canonical iPad-Pro-M4 real-data webgrid demonstration. That is gate 6 in
  `10-HUMAN-UAT.md`, DEFERRED, prerequisite "iPad Pro M4 not provisioned".
- It is **not** a photodiode measurement. The glass-to-glass figures on screen are software-timed and
  carry the verbatim D-07 label, "software-timed pipeline latency — excludes the compositor's 1-3 frames
  of scanout, which is exactly the delta the v1 photodiode rig (Phases 9-10) quantifies". (Amendment, Plan 10-11, commit 78756ee: `GlassToGlassTimer.methodologyLabel` was subsequently changed to "software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout; measuring that delta needs a photodiode rig, which is retired to Future work (LAT-01..LAT-08) and was never built".) The retired
  24.7 ms spec target is not claimed as achieved here or anywhere else in this phase.
- It is **not** a closed-loop result. `open-loop replay of a recorded session; the subject was not in the
  loop`: the animal's spikes were recorded in 2016 and cannot respond to what the decoder does with them.
- It is **not** a hit count. The GUI runs no dwell-to-select scoring; see observation (e).
