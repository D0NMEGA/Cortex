# Phase 10 RD-08 evidence: two measurement seams on the real replay, and the webgrid hit result

**Date:** 2026-09-05 (Plan 10-08). Every number below is transcribed from `10-replay.json`, which was
assembled programmatically from the bench outputs and the committed upstream artifacts. Nothing here
was typed from memory.

**The one-line result.** On the real `indy_20160630_01` replay, with the shipped NDT1 model in the
loop on every published tick, the software-timed glass-to-glass p99 at the Phase-8 measurement
boundary is **8.831 ms** (Seam A, debug build, median of five runs, n = 2,286), the wider
daemon-to-decode chain runs at a **0.136 ms** median (Seam B, in-process, n = 73,128), and the arms
whose result is attributable to the neural decode scored **0 webgrid hits of 1,025 trials** against a
recorded-cursor replay reference of 147.

## Environment

| Field | Value |
|---|---|
| Machine | `Apple M5 Pro`, `arm64`, 24 GB |
| OS | macOS 26.5 (25F71) |
| Xcode | 26.3 (17C529) |
| Swift | 6.2.4 (`swiftlang-6.2.4.1.4 clang-1700.6.4.2`) |
| SwiftFormat | 0.61.1 |
| Device label | `Apple M5 Pro`, status **corroborating** on both seams |
| Session | `indy_20160630_01` |
| Source sha256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` (byte-equal to `Decoder/manifests/indy_sessions.json`) |
| Export sidecar sha256 | `a452ed69ef82d9c6f86d312e12defdadca843513a05092b0c1db1b9eb6dec4e3` |
| Model | `Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage`, velocity checkpoint `9d542cb51d4a` |
| Seed | `0xC0FFEE` (the `CortexDemoBench` pipeline seed; the replay itself is deterministic) |
| Stale bench state | `rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench` ran before the first measurement, so no earlier methodology label or number could be transcribed |

The M5 Pro is a corroborating development machine, not the project's canonical iPad Pro M4 capture
device. Both latency numbers below are Mac numbers and are labeled as such. Neither is presented as
an iPad-M4 number.

## 1. What RD-08 asked for, and why the answer is two numbers

RD-08 asks for two things: that the closed loop replays a real session end to end at 120 Hz with a
30x30 webgrid hit demonstrated, and that the software-timed glass-to-glass p99 is re-derived on the
real-data path, because the Phase-8 number was measured on the synthetic path.

CONTEXT D-05 said the re-derived number would be "like-for-like with the Phase-8 number, which
included the IPC leg." That sentence is factually wrong, and it was struck in CONTEXT on 2026-09-05.
`10-RESEARCH` Correction 2 records the three checks that contradict it, quoted here verbatim:

> `Packages/CortexDemo/Package.swift` declares dependencies on CortexDecoder, CortexReFIT,
> CortexRender, CortexBCIHID and CortexCore. `CortexIPC` is not among them.
> [VERIFIED: `Packages/CortexDemo/Package.swift:37-43`]
>
> Neither `Apps/CortexMac` nor `Apps/CortexiOS` references `CortexIPC`, `HarnessConsumer` or
> `ShmRing`. Only the `CortexDaemon` target depends on the IPC products.
> [VERIFIED: grep across `Apps/`, and `project.yml:169-177`]
>
> `CortexDemoBench` constructs the pipeline with no model URL, so `isModelBacked` is false for the
> whole run and every tick used `ClosedLoopPipeline.syntheticDecodedVelocity`. The present timestamp
> is not read from a display link; it is computed as the next 120 Hz boundary after the measured
> pipeline cost. [VERIFIED: `Packages/CortexDemo/Sources/CortexDemoBench/main.swift:90` and `:109-116`]

So there is no single re-derived number that is both like-for-like with Phase 8 and covers the D-05
chain, because the Phase-8 measurement did not contain the D-05 chain. `10-PREREGISTRATION` section 9
fixed the repair before either number existed: two separately named seams, each carrying its own
boundary string, and only one of them ever reported beside the Phase-8 figure.

## 2. Seam A: the Phase-8 geometry with one variable changed

Seam A is `CortexDemoBench --real`. Same 8-tick warmup, same `Time.machAbsoluteNanoseconds()` intent
clock, same modelled 120 Hz present arithmetic
(`framesElapsed = pipelineDoneNs / framePeriodNs; presentNs = (framesElapsed + 1) * framePeriodNs`),
same `GlassToGlassTimer.sample`, same `LatencyHistogram` nearest-rank percentiles. What changes is the
spike source, which becomes `RecordedSpikeSource` over the D-06 export, and the decode, which becomes
the shipped fp16 `.mlpackage`. Plan 10-04 built that path as a verbatim copy of the Phase-8 block
rather than a refactor of it, precisely so the comparison holds.

| Quantity | Phase 8 (synthetic) | Seam A (real), debug | Seam A (real), release |
|---|---|---|---|
| p50 | about 4.2 ms | **4753046 ns (4.753 ms)** | 4302424 ns (4.302 ms) |
| p99 | **8318256 ns (8.318 ms)** | **8831017 ns (8.831 ms)** | 8386219 ns (8.386 ms) |
| max | not published | 9175382 ns (9.175 ms) | 8598101 ns (8.598 ms) |
| n | 10,000 ticks | 2,286 ticks | 2,286 ticks |
| runs | 1 | 5 | 5 |
| spike source | `SyntheticSpikeSource`, seeded | real 20 ms bins from the export | real 20 ms bins from the export |
| decode | none: `isModelBacked` false, synthetic fallback on every tick | NDT1 fp16, **2294 of 2294 ticks model-backed** | NDT1 fp16, 2294 of 2294 model-backed |
| **the single changed variable** | | **the spike source and the decode; nothing else** | |

**The changed variable, stated as one row.** Between the Phase-8 column and the Seam A columns,
exactly one thing moved: a seeded synthetic spike source feeding no model became a recorded real spike
source feeding the shipped NDT1 model. The warmup, the clock, the present arithmetic, the sampling
function and the percentile math are the same code.

**Build configuration.** `08-03-SUMMARY.md` records the Phase-8 command twice, both times as
`swift run --package-path Packages/CortexDemo CortexDemoBench --full`, with no `-c release`. SwiftPM's
default configuration is debug, so the Phase-8 number is a debug-build number. The summary never uses
the word "debug", so under this plan's own rule for an unrecorded configuration both were run, five
times each, and both are reported above. The **debug** column is the headline because that is the
configuration that makes the comparison to `8318256 ns` like-for-like. Release is about 5 percent
faster at p99, which is the size of the effect a configuration mismatch would have introduced had it
gone unnoticed.

**A single invocation is not publishable.** The arithmetic is deterministic but the pipeline cost is
real work on a live machine, so the percentiles move between runs. All five runs of each configuration:

| Configuration | p99 per run (ns) | p99 spread | p50 per run (ns) |
|---|---|---|---|
| debug | 8831017, 8845550, 8824918, 8823556, 8831823 | 0.25 percent | 4753064, 4753046, 4699261, 4715805, 4759723 |
| release | 8380106, 8370943, 8403407, 8400671, 8386219 | 0.39 percent | 4231055, 4292569, 4307991, 4302424, 4325804 |

The headline p50 and p99 are the median across the five runs; `max_ns` is the largest single sample
observed across all five, which is why it is not the median of the per-run maxima. The convention is
recorded in the artifact as `distribution_convention` so it cannot be inferred wrongly later.

**Why the p99 sits where it does.** It is dominated by the 8.333 ms 120 Hz present-boundary snap, as
it was in Phase 8: a tick whose pipeline cost pushes it past a boundary waits for the next one. That
present time is **modelled arithmetic, not a `CAMetalDisplayLink` reading** (`cadence_provenance` in
the artifact says so in those words). The measured display cadence is the Plan 10-10 GUI capture and
the deferred iPad-M4 gate.

**Why n is 2,286 and not 10,000.** The export holds 73,160 bins, which at the model's 32-bin window
yields 2,286 whole windows, and the bench takes `min(10000, windowCount)`. Seam A cannot reach the
Phase-8 10k bar without replaying windows, and replaying windows to hit a round number would be
padding a distribution. `ticks_total` is 2,294 because the 8 warmup ticks are counted; the source
clamps at its last whole window, so those final ticks re-replay window 2,285. That does not enter the
latency distribution and it is stated in the artifact's `n_note`.

**Model in the loop, on every published tick.** `ticks_model_backed == ticks_total == 2294`. The bench
carries a `precondition` on that equality (10-PREREGISTRATION section 10) and it was neither lowered
nor bypassed. Device `Apple M5 Pro`, status **corroborating**.

**No verdict.** `grep -c '"passed"'` and `grep -c '"budget_ns"'` on `10-replay.json` both return 0.
The 25 ms PERF-04 budget gates the synthetic `--smoke` and `--full` paths only, and neither seam was
judged against it (D-09).

## 3. Seam B: a strictly wider boundary, and not comparable to Seam A

**Seam B is a wider measurement boundary. It is not comparable to Seam A and not comparable to the Phase-8 glass-to-glass p99.**
That is not a caveat added afterwards: `10-PREREGISTRATION` section 9 fixed it in writing before either
number existed, and the Phase-8 figure is deliberately absent from this entire section, so no reader
can lift a number from here and set it beside a narrower historical one.

Stage by stage, Seam B is: the daemon reads a 20 ms bin from the D-06 export, `SampleCodec` encodes it
as a FlatBuffers `Sample`, `SessionCrypto` AES-GCM seals it, the slot is written to a real
`shm_open`ed `ShmRing`, the `Doorbell` socketpair is rung and drained, the consumer polls the ring,
decrypts, decodes the `Sample`, checks ordering, pushes the bin into a rolling 32-bin accumulator,
fills a zero-copy `SpikeInputBuffer` when the window closes, decodes it with NDT1, integrates the
cursor and encodes a BCI HID pointer report.

Counters over the full export, `--frames 73159`:

| Counter | Value |
|---|---|
| `frames_accepted` | 73,159 |
| `frames_dropped` | 0 |
| `windows_completed` | 73,128 |
| `windows_filled` | 73,128 |
| `decodes_succeeded` | 73,128 (`model_backed` true) |
| `cursor_updates` | 73,128 |
| `pointer_reports_encoded` | 73,128 |
| `doorbell_wakes` | 73,159 |

`--frames 73159` rather than 73,160 because `CortexSeamBSmoke` maps seq to export bin as
`seq % binCount` with seq starting at 1, so frame 73,160 would wrap back to bin 0. The 73,128 windows
are therefore one fewer than the ablation's 73,129 decoded ticks: the window ending at bin 31 needs
bin 0, and bin 0 is never sent.

Latency, per completed window, five runs:

| Statistic | Median across runs | Per run (ns) | Spread |
|---|---|---|---|
| p50 | **136167 ns (0.136 ms)** | 136583, 136167, 136292, 136167, 135833 | 0.55 percent |
| p99 | 160958 ns (0.161 ms) | 172125, 159916, 245584, 160958, 154958 | 58 percent |
| max | 13380292 ns (13.380 ms) | 964542, 990375, 13380292, 8598625, 3030959 | 14x |

**Only p50 is a stable statistic here, and the artifact says so.** The p99 swings 58 percent between
runs and the max swings 14x. `max_ns` is one sample out of 365,640 across the five runs; it is an
outlier bound set by OS scheduling on a live machine, not a property of the chain. Publishing the max
as a chain characteristic would be reading a scheduling artifact as an engineering result.

**Two limits on what this latency figure means, both first-class fields in the artifact.**

The first is the process boundary. `process_boundary` is `in_process`. Plan 10-06 measured the
daemon's two-process rendezvous failing before any Phase-10 change (the child returns
`MACH_SEND_INVALID_DEST`, identically with and without a replay export configured, which is the same
limitation Phase 2 already `XCTSkip`-guards), so the chain runs producer and consumer in lock-step in
one process over the real transport, the real crypto and the real codec. **The Mach rendezvous, the
`FDChannel` fileport handoff and the `SessionKeyChannel` key delivery are therefore not covered by
this number.**

The second follows from the first. Because both halves run in one thread, both clock reads are
`Time.machAbsoluteNanoseconds()` on one `mach_absolute_time` timebase, so the arithmetic is sound and
no cross-timebase comparison is being smuggled in. But no cross-process wakeup, context switch or
scheduling delay is included either. **Read 0.136 ms as a floor on what this chain would cost across a
real process boundary, never as an estimate of it.** That is why the number is reported with its
boundary in the same object rather than as a bare figure.

**Payload integrity.** The newest bin of the first completed window matched, to Float16 precision on
all 96 channels, the export bin the producer read for the seq that closed it. That is what proves the
bytes the decoder saw are the bytes that left the producer, through the seal, the ring and the
accumulator, rather than a plausible-looking window assembled from the wrong bins.

**The tamper control, executed.** One bit of the AES-GCM tag on frame 256 was flipped; everything else
is byte-identical, so only the authentication tag can reject it. Transcript:

```
CortexSeamBSmoke: AES-GCM open FAILED CLOSED at seq 256 - authenticationFailure
  frames produced up to and including the tampered one = 256
  frames the accumulator ACCEPTED                       = 255
  windows_completed                                     = 224
  The tampered frame was never decrypted, never decoded, and never entered a decode window.
```

Exit code **1**. The load-bearing assertions are on the accumulator's own counters, not on the loop's:
what proves the tampered frame never entered the chain is that the accumulator accepted exactly one
fewer frame than was produced and that no window formed for it.

## 4. The webgrid hit result, with the distance proxy as the primary observable

The hit counts and the cursor-to-target distances below are transcribed from `10-refit-real.json`
(Plan 10-07). They are the same replay, the same export and the same geometry as the seams above; they
were not re-measured with different settings.

| Arm | Rotation target | Hits / 1,025 | Share of the 147 reference | p1 (mm) | p5 (mm) | p25 (mm) | p50 (mm) | p90 (mm) |
|---|---|---|---|---|---|---|---|---|
| `raw` | none | **0** | 0.000 | **16.582** | 35.977 | 69.657 | 97.980 | 144.384 |
| `kalman_only` | none | **0** | 0.000 | **16.616** | 35.723 | 69.382 | 97.794 | 144.211 |
| `refit` | true track | 70 | 0.476 | 0.830 | 1.780 | 3.473 | 24.111 | 72.736 |
| `refit_reversed_target` | reversed track | 2 | 0.014 | 3.908 | 14.475 | 35.161 | 53.579 | 90.149 |
| recorded-cursor replay reference | the animal's own cursor | **147** | 1.000 | | | | | |

Acquisition radius **2.8613660406415042 mm**, dwell **0.30 s**, timeout **5.0 s**, 1,025 trials.

**The proxy is RD-08's primary observable, not a fallback.** `10-PREREGISTRATION` section 14 promoted
it before any decoded number existed, because a hit count that floors at zero carries no information
and cannot distinguish a decoder that drove the cursor most of the way from one that did nothing,
while the distance distribution degrades gracefully and discriminates both. Here it does exactly that:
the target-blind arms' closest approach over the whole replay, at the 1st percentile of 73,129 ticks,
is 16.582 mm and 16.616 mm against a 2.8614 mm radius. That is **5.8 acquisition radii**. The zero is
not a near miss, and the proxy is what establishes that rather than leaving it to be assumed.

**Which arms mean what.** `10-PREREGISTRATION` section 7, pre-registered before any number existed,
states that `IntentRotation.rotate` returns `(speed / dist) * d`: it replaces the decoded direction
with the direction to the known target and keeps only the decoded speed. The `refit` and
`refit_reversed_target` arms' cursor heading is therefore target-determined by construction, and their
counts of 70 and 2 are not decoding results. `raw` and `kalman_only` never see a target and are the
only arms whose result is attributable to the decode. Both are 0 of 1,025.

**What the 147 is, and what it is not.** Replaying the animal's own recorded cursor track through this
repo's dwell-to-select rule at this radius and this dwell hits 147 of 1,025 trials, 14.3 percent. It
is a property of one recorded trajectory under one acceptance rule. It is **not** a bound on what a
decoder can score: a decoder producing different trajectories, with straighter approaches or longer
holds inside the radius, can exceed it. Its value is as a pre-registered reference point that makes a
decoded count interpretable, because without it a decoded zero says nothing about the decoder, since
the geometry alone already misses most trials.

It was committed before any decoded number existed, and the git order is the audit trail:
`10-PREREGISTRATION.md` landed in **`a72344b`**, `10-ceiling.json` and `10-ceiling-evidence.md` in
**`b3eeba2`**, and the ablation that produced every decoded count above in **`0b7ad67`**, 39 commits
later.

**Geometry context, from `10-RESEARCH` Correction 4 and reproduced exactly by Plan 10-01.** At dwell
0.30 s the recorded cursor scores 43 of 1,025 at a 1.75 mm radius, 147 of 1,025 at 2.86 mm, and 951 of
1,025 at 7.50 mm. The 7.50 mm row is the task's own implied acceptance zone, half the real 15.0 mm
target pitch, so on that reading the recorded task is effectively a **14x14 grid** over the field, not
a 30x30 one. D-02 locks the 30x30 re-grid; this artifact reports the consequence rather than changing
the decision.

**Zero was the expected outcome, and the rule for it was fixed first.** The pre-execution measurement
in `10-PREREGISTRATION` section 1 put this session's pooled held-out R2 near 0.15 with a decoder that
systematically under-scales velocity amplitude, and section 15 named row B, zero hits with disposition
`not_met`, as the expected row before the run. Writing that down in advance is what makes this a
finding rather than a disappointment that invites re-litigating the rule.

### Which row of section 15 this lands in

Section 15's table has three rows. Applying it to the measured numbers:

| Reading | Row | Condition | Holds? |
|---|---|---|---|
| The table's literal first column, which names the `refit` arm | **A** | `hits >= 1` | Yes: 70 of 1,025 |
| The arms section 7 makes attributable, `raw` and `kalman_only` | **B** | `hits == 0` with the reference `>= 1` | Yes in substance: 0 of 1,025 against 147 |
| | C | `hits == 0` and the reference is also 0 | No: the reference is 147, so row C is ruled out at this geometry |

Row C is closed. The two live readings disagree, and the disagreement is between two pre-registered
sections rather than between a rule and a preference: section 15's first column names the `refit` arm,
while section 7 states that the `refit` arm's heading is target-determined and that only the
target-blind arms are attributable to the decode. Row B as literally written also requires zero on all
four arms, which is not the case here.

The determination this artifact records, for confirmation rather than as a choice made on the user's
behalf: **on the arms whose result is attributable to the neural decode, the outcome is 0 of 1,025
against a reference of 147, which is row B's shape and disposition `not_met`.** The `refit` arm's 70
hits satisfy the table's literal first column, but publishing them as SC#2 met would present target
knowledge as a decoding result.

`sc2_disposition` and `sc2_rule` are deliberately **absent** from `10-replay.json`. Section 15 rule 2
says in writing that no agent amends a success criterion, and section 15 row B's own action column
routes the choice to **Plan 10-10 Task 3**, a blocking checkpoint that instructs its executor not to
choose a row on the user's behalf. The full adjudication above is recorded in the artifact under
`sc2_adjudication` so that the user's decision is a confirmation of measured facts rather than an open
question. Plan 10-10 Task 3 writes the two enum keys.

## 5. The D-11 decomposition, five factors

Each factor below is also written into `10-replay.json`'s `decomposition` object, so the JSON and this
prose agree by construction rather than by proofreading.

### 5.1 `velocity_amplitude_shrinkage`

Measured from the run itself, over the same replay, `n` = 73,128 completed windows, and
**byte-identical across five independent runs** because the decode is deterministic:

| Statistic | Decoded speed | True speed | Ratio |
|---|---|---|---|
| mean | 4.27580994115854 cm/s | 5.957895855050252 cm/s | **0.7176711451802436** |
| p95 | 8.928604125976562 cm/s | 25.706682164075655 cm/s | **0.34732619592792213** |

Both are ratios of summaries, not summaries of a per-window quotient. That convention is stated
because it matters: a per-window quotient diverges wherever the true speed passes through zero, which
it does at every reach reversal, so its mean would be dominated by near-zero denominators and would
measure nothing about amplitude. `realized_gain` in `10-refit-real.json` takes the ratio of means for
the same reason.

The decoder tracks reach timing well but systematically under-scales amplitude, which is ordinary
ridge/MSE shrinkage toward the mean rather than a defect, and it is the factor that most directly
produces a zero, because an under-scaled velocity does not carry the cursor into a 2.8614 mm
acquisition radius within a 0.30 s continuous dwell.

This measurement confirms the mechanism that `10-PREREGISTRATION` section 14 described before the run.
The pre-registration predicted "true velocity peaks reaching plus or minus 20 to 30 cm/s while decoded
output rarely leaves plus or minus 10." Measured: the true speed distribution reaches 25.71 cm/s at
p95, the decoded output reaches 8.93 cm/s. The prediction was recorded first and the measurement lands
inside it.

### 5.2 `decode_r2`

- **+0.14460174271291293**, the Phase-9 per-session figure, from `09-decoder-metrics.json`
  `velocity.per_session[indy_20160630_01].pooled`, produced by the pooled Phase-9 split, null = this
  session's own train-split mean velocity per axis, n = 14,600, vx 0.05855656761357275,
  vy 0.2588613876111545.
- **0.1523**, the independent pre-execution re-measurement of 2026-09-05 recorded in
  `10-PREREGISTRATION` section 1, on a chronological tail split of this one session (73,161 bins by 96
  channels, split at bin 58,529, 14,601 held-out rows) scored against the train-split mean null using
  this repo's own `fit_velocity_real._build_design` and `kinematics.heldout_r2`; vx 0.0671, vy 0.2653.

`0.1446` and `0.1523` are different measurements on different splits, not two attempts at one number.
Both are carried with the method that produced them and neither is adjusted toward the other.

This session is the weakest of the four by held-out velocity R2, against a per-session range of
+0.1446 to +0.5069. **The session was not switched.** D-08 chose it in advance, before any Phase-10
outcome was known, and section 15 rule 0 keeps it locked. Choosing a stronger session after learning
it was the weakest would be selection on the outcome, which is the thing D-08 exists to prevent. The
weakness is disclosed, not corrected.

### 5.3 `open_loop_no_error_correction`

The disclosure, verbatim and byte-identical everywhere it appears:

```
open-loop replay of a recorded session; the subject was not in the loop
```

D-03 in full: "closed loop" refers to the software path being closed end to end (decode, filter,
integrate, render, HID), never to the subject being in the loop. A recorded session's spikes cannot
respond to a cursor we drive, so the subject cannot correct an error the decoder makes, which
closed-loop control would allow. That asymmetry is the honest explanation for a low open-loop rate, and
it means no claim about closed-loop control follows from any number in this artifact.

### 5.4 `workspace_to_grid_scale`

From the export sidecar, normalisation `cursor_bbox_square`:

| Quantity | Value |
|---|---|
| `side_mm` | 171.68196243849025 |
| `cell_mm` | 5.7227320812830085 (`side_mm / 30`) |
| `acquisition_radius_mm` | 2.8613660406415042 (`cell_mm / 2`) |
| grid | 30 x 30 |

A half-cell radius means the decoded cursor must arrive within 2.8614 mm of the target centre and hold
there. The recorded task's own target pitch is 15.0 mm, implying a 7.50 mm acceptance zone, about 2.6
times this radius.

### 5.5 `dwell_and_timeout`

Dwell **0.30 s**, timeout **5.0 s**, continuous-dwell semantics: the counter resets on any excursion
outside the acquisition radius, so a hit requires 0.30 s held continuously inside 2.8614 mm within a
5.0 s trial.

**These were not relaxed.** Radius, dwell and timeout are the pre-registered values in every row of the
disposition table. D-11 and section 15 rule 1 bind all of them: acquisition parameters are **not
relaxed** until hits appear, and a zero is published as the result with this decomposition beside it
rather than converted into a hit by widening the acceptance zone.

## 6. What this does not establish

- **Nothing about closed-loop control.** The disclosure above is the governing statement: this is an
  open-loop replay of a recorded session and the subject was not in the loop.
- **One session.** `indy_20160630_01` only, and it is the weakest of the four by held-out velocity R2.
  Nothing here generalises to the other three sessions or to a different subject.
- **A Mac, not an iPad.** Both seams are `Apple M5 Pro` numbers with status `corroborating`. The
  canonical iPad-Pro-M4 capture is deferred and remains a never-auto-approved gate (Plan 10-10).
- **Software-timed, not photodiode-instrumented.** Both seams end at a software timestamp. Seam A's
  present time is modelled 120 Hz arithmetic, not a display-link reading, and it excludes the
  compositor's scanout. The retired 24.7 ms spec target is not claimed as achieved anywhere in this
  artifact, and no number here should be read as a glass-to-glass measurement in the
  photodiode-instrumented sense.
- **Seam B does not cross a process boundary**, so the Mach rendezvous, the `FDChannel` fileport
  handoff and the `SessionKeyChannel` key delivery are untested by it.
- **The methodology label this bench emits is stale.** `GlassToGlassTimer.methodologyLabel`
  (`GlassToGlassTimer.swift:37-39`) currently reads, transliterated to ASCII because the source string
  contains a U+2014 em dash:

  ```
  software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout, which is
  exactly the delta the v1 photodiode rig (Phases 9-10) quantifies
  ```

  The byte-exact string, em dash included, is carried in `10-replay.json` at `seams[A].methodology`.
  It is stale because Phases 9 and 10 no longer build a photodiode rig: the v1 milestone was
  re-pointed to real-data decoding on 2026-08-28 and the photodiode work moved to a Future work
  heading. The label was **not** edited here. It is a four-way coupled edit
  (`GlassToGlassTimerTests` asserts it verbatim, `README.md:81` quotes it, `readme-policy.sh:136`
  requires its prefix, `CortexDemoBench` prints it into the JSON) and RD-09, Plan 10-11, owns the
  correction. This section is the only place in this document where the word photodiode appears, and
  it appears only to record that the label is stale.

## 7. Runbook

Copy-pasteable from a clean checkout with the dataset, the export and the checkpoints materialized.
`Decoder/exports/`, `Decoder/data/` and `Decoder/checkpoints/` are gitignored; in a worktree they must
be real directories holding symlinks, never bare symlinks, or `git status` goes dirty.

```bash
# Stale bench state first, so no earlier methodology label or number can be transcribed.
rm -rf Packages/CortexReFIT/.bench Packages/CortexDemo/.bench Packages/CortexDecoder/.bench

# Seam A, the Phase-8 geometry. Run BOTH configurations five times each; debug is the
# configuration the Phase-8 number was measured in and is the like-for-like comparison.
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift run --package-path Packages/CortexDemo CortexDemoBench --real

CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift run -c release --package-path Packages/CortexDemo CortexDemoBench --real

# Seam B, the wider chain, over the full export. 73159 and not 73160: seq maps to bin as
# seq % binCount with seq starting at 1, so frame 73160 would wrap back to bin 0.
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
CORTEX_MODEL_URL=Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage \
  swift run -c release --package-path Packages/CortexDemo CortexSeamBSmoke --frames 73159

# The tamper control. Expected NON-ZERO exit: a clean exit here means the control did not bite.
CORTEX_REPLAY_EXPORT=Decoder/exports/indy_20160630_01.replay.json \
  swift run -c release --package-path Packages/CortexDemo CortexSeamBSmoke --tamper   # exit 1

# The Phase-8 synthetic path, unchanged and still gated against the 25 ms PERF-04 budget.
swift run --package-path Packages/CortexDemo CortexDemoBench --smoke                   # exit 0
```

`-c release` on the Seam B lines is not optional in practice: the chain makes 73,128 decodes and a
debug build is roughly two orders of magnitude slower over the `SpikeInputBuffer` writes, for an
identical result. The Seam A debug line is deliberate and is explained in section 2.

## 8. D-09 statement

No gate, test or CI step added or touched by this plan asserts the sign or magnitude of any number
above. `10-replay.json` carries no `passed` key and no `budget_ns` key for either seam, both verified
by grep returning 0. `CortexSeamBSmoke` emits no verdict field and exits 0 on a clean run whatever its
counters are; it fails only on a structural violation. The Phase-7 `refit_bps.json` byte-identity
invariant and `check_refit_uplift.py` stay untouched and synthetic-scoped. A negative or zero finding
is publishable here without turning the build red, because a red build is pressure to tune.

## 9. Artifact

`10-replay.json`. Eighteen of `10-PREREGISTRATION` section 11's twenty top-level keys, plus two named
additions, minus two deliberate absences:

- The two absences are `sc2_disposition` and `sc2_rule`, which Plan 10-10 Task 3 writes at a blocking
  checkpoint (section 4 above).
- The two additions are `hits_by_arm`, which carries all four arms' counts and distances so the zero on
  the attributable arms is not hidden behind the `refit` arm's 70, and `sc2_adjudication`, which
  records the row analysis in section 4 in machine-readable form.
- The recorded-cursor replay reference is emitted as `replay_reference_hits` and
  `replay_reference_ref`, which is what section 11 pins. Section 11 states in writing that
  `ceiling_hits` and `ceiling_ref` are **not** emitted, because the ceiling framing was rejected in
  section 16. The word survives only in the file and identifier names that already carried it
  (`webgrid_ceiling.py`, `10-ceiling.json`, `10-ceiling-evidence.md`), never in a published sentence
  describing the number.
