# Cortex: a sequential architecture walkthrough

A stage-by-stage account of what the pipeline does, which alternative was rejected at each stage
and why, and what was actually measured. Every number here is transcribed from `README.md`, the
ADRs, or the milestone retrospective, all of which are CI-gated against the artifacts that produced
them.

Read the caveat in "The one claim never to make" before quoting anything from this document.

## The one claim never to make

The spec's original north star was "glass-to-glass latency 24.7 +/- 1.3 ms, photodiode
instrumented". **That number was never measured and must never be presented as a result.** The
photodiode rig (BPW34, OPA381 TIA, Saleae Logic Pro 8) was never built, and ADR-0003 retired the
whole path. Every latency figure in this project is software-timed with `mach_absolute_time` and
excludes the compositor's 1 to 3 frames of scanout.

The honest sentence is: "I have software-timed pipeline latency, p99 8.386 ms release. I do not
have glass-to-glass, because I never built the rig, and I will not quote a spec target as a
measurement."

## Stage 0: the decision that set the project's character

ADR-0003 (2026-09-05) retired the photodiode path and re-pointed v1 at real-neural-data decoding.
The reasoning is the most important thing in the repository:

Through Phase 8, every decoder number the project published had been produced on a **synthetic
Poisson fallback**, because no real `.mat` file was present under `Decoder/data/`. So co-bps
0.3804, the ReFIT 0.374-versus-0.161 ablation and the 1.953 Webgrid BPS were synthetic numbers
wearing real-sounding labels.

The decisive line: a photodiode measures the scanout delta of a pipeline, and says nothing about
whether the decoder in that pipeline has ever seen a spike from an animal. Buying a latency
instrument while every decoder number was synthetic would have been optimising the wrong claim.

The eight LAT requirements were moved to "Future work (retired from v1)" preserved verbatim, not
deleted, so a reader can confirm nothing was quietly dropped.

## Stage 1: data ingest

**What.** Four checksum-pinned sessions (1.77 GB) from the O'Doherty / Cardoso / Makin / Sabes
primate M1 dataset, Zenodo 3854034. The locked session is `indy_20160630_01`: 96 channels, 20 ms
bins, 73,160 bins. Self-paced reaches to a grid of 64 targets at 15 mm pitch.

**Why this dataset.** It is real awake-behaving non-human-primate M1 electrophysiology with
simultaneous hand kinematics, publicly checksummable, and large enough to support a held-out split
that is not a rounding error. The alternative, continuing on synthetic Poisson spikes, is what
ADR-0003 rejected.

**Rejected.** Synthetic Poisson generation. It produces numbers that cannot be falsified by
anything, which is the opposite of what the project is for.

## Stage 2: the decoder, and the baseline that beats it

**What.** NDT1 (Ye and Pandarinath 2021), 1,292,544 parameters, 6 layers, 1 to 2 attention heads,
128 hidden dimensions, 20 ms spike binning, 32-bin (640 ms) context window.

**The result that matters.** A causal ridge decoder on raw binned spike counts, fit and scored
through the identical split, the identical 20 ms lag, the identical 56,943 held-out rows and the
identical train-mean null, beats it:

| decoder | history | pooled held-out R2 |
|---|---|---|
| ridge on raw spikes | 20 ms | 0.1280 |
| ridge on raw spikes | 80 ms | 0.2795 |
| ridge on raw spikes | 320 ms | 0.4428 |
| ridge on raw spikes | 640 ms (the encoder's own window) | **0.4616** |
| NDT1 encoder + ridge readout | 640 ms | **0.4238** |

The baseline leads on every session individually, including the locked one (0.1832 against
0.1446). The baseline's ridge penalty is chosen by a weaker rule than the encoder's, so it is
untuned rather than flattered.

**What was done about it.** The shipped demo runs the decoder that wins. `CortexMac` drives replay
from the ridge filter by default, loaded from the weights the comparison was measured with;
`export_ridge_decoder.py` refuses to write the file unless the exported weights reproduce 0.4616
on the same 56,943 rows, and a Swift test asserts the on-device decode matches the Python fit on a
fixed probe window. It is 3,072 multiply-adds per axis and ships in the app bundle, so the demo
needs no checkpoint file. `CORTEX_DECODER=ndt1` selects the transformer with everything downstream
identical.

**The honest framing.** On this dataset, under this protocol, the transformer is not earning its
parameters. That is a finding about this setup, not a general claim about NDT1. A stronger result
would need better cross-session generalization, which is exactly where it currently fails.

**Generalization.** Leave-one-session-out co-bps against the unseen session's test mean is
**-0.3498**, below a mean-rate null. The co-bps figure masks random bin/channel entries; the Neural
Latents Benchmark withholds whole neurons, so this is **not** NLB-comparable and is not offered as
one.

## Stage 3: model deployment

**What.** CoreML, 4-bit palettized `.mlpackage`, fp16 velocity checkpoint `9d542cb51d4a`.

**Why CoreML over MLX.** MLX has unbounded p99 and no ANE residency. A decoder on a control path
needs a bounded tail, not a good average.

**Measured.** 239/239 operations **ANE-eligible** by `MLComputePlan`, reproduced independently on
an iPad Air M2. Inference p99 under 2 ms (approximately 0.5 ms on iPad-M2, 0.14 ms on M5 Pro).

**The gap, stated plainly.** Runtime placement measures **CPU** at the 1.29M-parameter scale.
Eligibility is not residency. The likely mechanism is that ANE dispatch overhead dominates at this
model size, so CoreML's scheduler picks CPU, but the crossover has not been measured and is not
claimed.

## Stage 4: filtering and the control law

**What.** ReFIT-Kalman filter, then open-loop velocity integration to cursor position.

**The naming discipline, part one.** The scoring arm that succeeds is labelled
**target-assisted**, not ReFIT, on purpose. ReFIT uses target-informed intention to retrain decoder
parameters; it does not supply target knowledge during online control. Calling the arm ReFIT would
borrow credibility from a method that is not what is running.

**The naming discipline, part two, and say this before anyone asks.** This is **not a Kalman
decoder in the Wu 2006 / Gilja 2012 sense**. In that architecture the state is kinematic and the
*observation is neural*: firing rates observe the kinematic state through a tuning model, and the
filter performs the decoding. Here the state is the 6-DOF kinematic vector `[px, py, vx, vy, ax,
ay]` and the measurement matrix is `H = [0 I 0]`, a **velocity-only observation of an
already-decoded `(vx, vy)`**. So this is a steady-state kinematic smoother sitting *downstream* of
the decoder, plus the Gilja intent-rotation step, not a neural-observation Kalman decoder.

The shorthand "ReFIT-Kalman" is how the repo names it and the intent-rotation genuinely is the
ReFIT idea, but a reviewer who knows the literature will assume the canonical decoder and should be
corrected immediately rather than allowed to infer it. The honest one-liner: "it is a post-decoder
kinematic Kalman smoother with ReFIT-style intent rotation; I never fit a neural-observation Kalman
decoder, and that comparison against the ridge baseline is a real gap."

**Why the observability caveat is not hand-waving.** The 6-DOF state is *not observable* from a
velocity-only measurement, because position is a pure integrator no measurement corrects. The
implementation solves the steady-state DARE on the observable `[vx, vy, ax, ay]` sub-block and
embeds the 4x2 result into a 6x2 gain with **zero rows for position**, which is the correct handling
rather than a convenient one, and the closed loop is Schur-stable at max|lambda| approximately 0.93.

## Stage 5: inter-process transport

**What.** `shm_open` shared memory ring with `kqueue` and `recvmsg` doorbell signalling.

**Rejected.** `Network.framework`, measured at 50 to 200 us of overhead. On a path whose entire
budget is a few milliseconds, a transport that can consume 200 us for a local handoff is
disqualifying.

**Measured.** Shared-memory round trip p99 **208 ns**, sigma 89.7 ns, n = 199,000 on M5 Pro.

**The gap.** The two-process rendezvous fails with `MACH_SEND_INVALID_DEST`. The published
daemon-to-decode chain (FlatBuffers encode, AES-GCM seal, ring write, doorbell, decrypt, 32-bin
accumulate, NDT1, cursor integrate, HID report) was therefore measured with producer and consumer
running lock-step **in one process** over the real ring, doorbell, crypto and codec, with no
cross-process wakeup included. p50 0.136 ms stable to 0.55% across 5 runs; p99 0.161 ms with a 58%
run-to-run swing. **This is a floor, not a cross-process estimate**, and the README says so.

## Stage 6: threading

**What.** `pthread` with `QOS_CLASS_USER_INTERACTIVE`. QoS is the worker's first action,
`import Darwin` only. No `dispatch_async`, no Objective-C runtime, no locks, no ARC retain/release
on the hot path. Enforced by a CI gate.

**Rejected.** Swift `Task` and structured concurrency. Cooperative scheduling cannot meet a 1 ms
deadline, because the runtime decides when a continuation resumes and nothing in the language
surfaces that as a deadline.

**The gap, and it is the sharpest one.** This is **structural, not a runtime measurement**. The hot
path is built and CI-gated but is **not on the replay demo's path**, which drives decoding from a
`@MainActor` timer by design (D-03), because v1 has no acquisition hardware to feed a real-time
thread. The milestone audit caught this as INT-01: a requirement set describing a hot path with no
production caller, undetected for seven phases.

## Stage 7: cryptography

**What.** AES-GCM via CryptoKit. HKDF-derived per-direction subkeys, deterministic 96-bit nonce,
fail-closed tamper tests.

**Rejected.** ChaCha20-Poly1305, which is the usual choice on platforms without AES acceleration
and the wrong one here: Apple Silicon implements `FEAT_AES`, so AES-GCM is faster.

**Kept off the measured hot path**, and stated as such rather than folded into a latency figure.

## Stage 8: rendering

**What.** `CAMetalDisplayLink`, beam-raced, 120 Hz ProMotion.

**Rejected.** `CADisplayLink`, which cannot bundle drawable acquisition, encode and present
tightly enough for beam racing.

**Measured.** GPU p99 **0.162 ms** against a 0.4 ms budget. 60-second soak, 243,724 frames, **0
dropped**.

## Stage 9: output

**What.** Apple's BCI HID protocol surface (May 2025), so the artifact is both a demo and a
deployable assistive input device.

**The gap.** Signing is a free Personal team, so the BCI HID entitlement is declared but **inert**.
The surface is implemented; the live half is request-gated and deferred with the blocker named.

## End-to-end metrics

**Intent to present**, `CortexDemoBench --real`, real spike source, shipped fp16 model, 2,294 of
2,294 ticks model-backed:

| | debug | release |
|---|---|---|
| p50 | 4.753 ms | 4.302 ms |
| p99 | **8.831 ms** | **8.386 ms** |
| n | 2,286 windows | 2,286 windows |

n is 2,286 because 73,160 bins at a 32-bin window yields that many whole windows. Present time is
modelled 120 Hz arithmetic, not a `CAMetalDisplayLink` reading. The two latency chains above are
**not comparable to each other**: one measures intent to present, the other a wider daemon chain.

**Task performance**, 1,025 trials, four arms:

| arm | acquisitions | Webgrid BPS | target information |
|---|---|---|---|
| raw (decode only) | **0 / 1,025** | 0 | none |
| kalman_only (decode + filter) | **0 / 1,025** | 0 | none |
| target-assisted | 70 / 1,025 | 0.487984 | true target every tick |
| target-assisted, reversed | 2 / 1,025 | 0.013635 | reversed target every tick |

**The decode-attributable result is 0 of 1,025.** The reversal control is the point: collapsing
70 to 2 by reversing the supplied target shows the 70 is explained by the target, not by decoded
intent.

BPS is **not** comparable to published BrainGate or Neuralink scores, for four separate reasons:
the bit convention differs (log2(N) here versus log2(N-1) in eLife 18554), the grid differs, this
harness makes incorrect selections structurally zero so every BPS here is an upper bound, and
Neuralink's published score adds a click-type term this single-click harness omits.

## Why the acquisition count is zero

Two causes. The repository measures the first directly, by replaying the animal's **own recorded
hand track** through the same acceptance rule, which isolates how much of the zero the geometry
alone explains:

| acquisition radius | dwell 0.30 s | dwell 0.10 s |
|---|---|---|
| 2.861 mm (the rule used above) | 147 / 1,025 (14.3%) | 334 / 1,025 (32.6%) |
| 7.50 mm | **951 / 1,025 (92.8%)** | 1,007 / 1,025 (98.2%) |
| 15.00 mm | 1,023 / 1,025 (99.8%) | 1,025 / 1,025 (100%) |

1. **The evaluator is mis-specified relative to the source task.** The 30x30 Webgrid geometry
   and its 2.861 mm radius are derived from the grid cell, not from the task, whose real target
   pitch is 15 mm. At that radius the recorded hand itself succeeds on 14.3% of trials; at half the
   real pitch it succeeds on 92.8%. **878 of the 1,025 trials are lost before decoding is
   involved.**
2. **The decoder does not put the cursor near the target**, and this term dominates. Held-out R2 is
   0.1446 on this session, integrated open-loop with no feedback path.

**The decomposition, and the part that matters.** Measured in `11-decode-gap-evidence.md`: for the
two target-blind arms, the cursor's **closest 1% of samples sit 16.58 mm from the target**. That is
**5.80x** the 2.861 mm acceptance radius, **2.21x** the task's own 7.50 mm half-pitch, and **1.11x**
even the 15.00 mm radius at which the recorded hand scores 1,023 of 1,025. Median distance is
97.98 mm in a workspace 171.68 mm on a side, 57% of the workspace width.

So the honest answer to "your evaluator is mis-specified, fix the geometry and re-score" is: it is
mis-specified, by roughly 2.6x in radius, **and correcting it fully would still not produce a hit.**
There is no radius at which the decoder scores and the task geometry still discriminates. The
geometry critique is correct and is not load-bearing. (Stated precisely: the zero at 2.861 mm is
measured; the claim at 7.50 and 15.00 mm is a strong bound from the distance percentiles, not a
deductive proof, because percentiles say nothing about whether inside-samples cluster into the 15
consecutive ticks the decoded arms' dwell needs. The full per-sample sweep is the obvious next task.
Note the two scorers run on different clocks: the recorded-hand ceiling is scored at 250 Hz where
0.30 s is 75 samples, while the decoded arms decode once per 20 ms bin where 0.30 s is 15 ticks.)

Note also that the 70-hit `refit` arm is **target-determined by construction** -- its rotation reads
the true target track -- and its reversed-target control collapses to 2. Neither is a decode result.

Fixing the geometry would not turn any of this into closed-loop evidence either. Recorded spikes
cannot react to a decoded cursor, so no replay of this dataset establishes online control at any
radius.

## What makes this architecture strong

Not the numbers. The numbers are mostly negative. What is defensible is the machinery that made
the negative numbers trustworthy:

**Pre-registration.** `10-PREREGISTRATION.md` committed the disposition and action for a zero-hit
outcome in Wave 0, before any hit count existed, and forbade relaxing radius, dwell or timeout.
When the zero arrived there was no argument to have. The retrospective calls this the single
highest-value process artifact in the milestone, and it cost one document.

**Negative controls on the gates themselves.** Every policy gate ships a `--self-test` proving the
gate bites. Twelve `*-policy.sh` CI gates, four carrying adversarial self-test corpora. "The gate
passed" means something only if the gate can fail.

**Correcting rather than shipping a flattering number.** A masked-objective defect had inflated
co-bps roughly tenfold. It was found, fixed, and the entire co-bps-versus-epoch curve was published
instead of a single figure. Same with a 226-versus-239 op tally read off a stale artifact.

**Deferring instead of approximating.** Eleven hardware- and account-gated measurements are
recorded as DEFERRED with the blocker named. None was fabricated, and the audit can say exactly
what was and was not measured.

**Every number labelled by the device and method that produced it.** Which is why this document can
state a p99 and also state that it excludes scanout.

## What I would do next, in order

1. **Fix the cross-process rendezvous.** `MACH_SEND_INVALID_DEST` is the one gap that converts a
   caveat into a number. Until it is fixed, the daemon-to-decode figure is a floor and the
   architecture's central IPC claim is unproven across the boundary it exists to cross.
2. **Measure the ANE crossover.** Sweep model scale and find where runtime placement moves from CPU
   to ANE. That turns "eligible but measures CPU" into a dispatch-overhead threshold, which is the
   number that actually informs how large a deployable decoder can be.
3. **Attack nonstationarity directly.** LOSO co-bps of -0.3498 is the real scientific gap, and it
   is the open problem the field names. Characterise what drifts between sessions (channel yield,
   firing-rate statistics, tuning rotation) before reaching for a bigger model.
4. **Put the hot path on the demo path.** INT-01 exists because the real-time thread has no
   production caller. Either feed it or stop claiming it as a runtime property.
5. **Glass-to-glass, if hardware appears.** The BOM is roughly $110 plus an analyzer. It is the
   only way the original claim becomes real.

## Anticipated questions

**"Your transformer loses to ridge. Why ship the transformer at all?"** I do not. The demo runs
ridge by default. The transformer is behind an environment variable with everything downstream
identical, so the comparison stays matched. The finding is that at 96 channels and this data
volume, a 1.3M-parameter attention model has no room to express an advantage over a 640 ms linear
readout.

**"Is 8.386 ms p99 real?"** It is real as software-timed intent to present, over 2,286 windows,
release build, with a real spike source and the shipped model. It excludes the compositor's 1 to 3
frames of scanout and it is not glass-to-glass. I never built the photodiode rig.

**"0 of 1,025 sounds like the pipeline does not work."** The pipeline works; the decoder is weak
and the evaluator is mis-specified. I can separate those, because I scored the animal's own hand
through the same rule and it hits 14.3% at that radius and 92.8% at half the task's real target
pitch.

**"Why is a replay interesting at all?"** It is not closed-loop and I do not claim it is. It is
interesting as an instrumented pipeline and as an honest negative result. Closed-loop needs a
subject in the loop, which no recorded dataset can provide.
