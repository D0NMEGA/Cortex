---
status: PARTIAL
agent: donny-phase-researcher
phase: 10
confidence: HIGH
---

# Phase 10: v1 Real-Data Closed Loop & Launch - Research

**Researched:** 2026-09-05
**Domain:** real-session BCI replay through an existing Swift closed loop, ReFIT re-fit on real
residuals, repo-wide honesty sweep, and a rewritten build-failing README gate
**Confidence:** HIGH (most findings verified directly against this repo, the materialized dataset,
and two primary sources; the residual uncertainty is listed in Open Questions)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Real-session replay contract (RD-07, RD-08)**

- **D-01:** ReFIT's intent rotation points at the session's real `target_pos`, the target the
  animal was actually reaching for. `ndt1.data.load_session` starts reading a third behavior
  array, extending the Phase-9 D-05 contract (`spikes`, `t`, `finger_pos`) to include
  `target_pos`. `cursor_pos` and the large `wf` array stay unread (threat T-04-02-02). Rotating
  a genuinely-decoded velocity toward a target the subject never saw would fabricate intent,
  which is the exact class of over-claim this phase exists to eliminate.
- **D-02:** The 30x30 webgrid on the real-data path is a re-grid of the real workspace: the
  session's `finger_pos` workspace maps onto the grid and the real `target_pos` track is snapped
  to cells. A hit then means the real decoded velocity carried the cursor to where the animal was
  reaching, so RD-08's webgrid-hit criterion stays meaningful. The existing seed-locked synthetic
  target sequence is preserved byte-identical as the Phase-7/8 regression fixture, so
  `bps-policy.sh` and `check_refit_uplift.py` keep guarding exactly what they guard today.
- **D-03:** The loop is disclosed as software-path-closed and subject-open-loop. "Closed loop"
  refers to the software path being closed end to end (decode -> filter -> integrate -> render ->
  HID), never to the subject being in the loop: a recorded session's spikes cannot respond to a
  cursor we drive. The disclosure is carried in the evidence artifacts, the README, and the
  committed metrics JSON, not left to prose in one place.
- **D-04:** The ablation gains a fourth arm: the rotation re-run against a shuffled or
  time-reversed target track. If uplift survives a target the neural data has no relationship to,
  the uplift is the rotation exploiting target knowledge rather than decoding, and that is the
  finding. This is the attribution control, mirroring Phase 9's checkpoints-hidden control that
  made the 226-to-239 op delta attributable to the weights.

**Spike path into Swift (RD-08)**

- **D-05:** The real spike stream goes through the full chain. `CortexDaemon` reads the exported
  real bins instead of generating synthetic spikes; IPC, decoder, ReFIT, renderer and HID are
  unchanged. This is the only version where the re-derived glass-to-glass p99 is like-for-like
  with the Phase-8 number, which included the IPC leg.
- **D-06:** The Python side exports one artifact carrying the 20 ms binned counts (96 channels),
  the paired true velocity, and the target track, as a compact binary with a JSON sidecar
  recording session id, source sha256, bin count, the locked lag, and the workspace-to-grid
  mapping. Swift reads it with no parsing risk, and the sidecar is what the provenance gate binds
  to. Binning stays in `ndt1` where it is already tested; a second binner in Swift would be a
  silent drift hole.
- **D-07:** The export is gitignored and materialized by a committed script from the SHA-256-
  pinned `.mat` files, exactly like `Decoder/data/`. Keeps the Phase-9 D-21 tier split intact
  (CI never trains and never touches the dataset) and raises no CC-BY redistribution question.
  CI therefore cannot run the real path, which the tier split already accepts.
- **D-08:** The replayed session is `indy_20160630_01`, the NLB'21 mc_rtt benchmark session
  already named in Phase 9's D-06 as the reason `finger_pos` is the label source. Chosen in
  advance so the session was not selected on its own outcome, and so the number stays legible
  against published work. Per-session held-out velocity R2 ranged +0.1446 to +0.5069; picking the
  strongest session would have been selection on the result.

**Ablation and reporting bar (RD-07)**

- **D-09:** The Phase-7 `refit_bps.json` and `check_refit_uplift.py`'s `refit_bps >= raw_bps`
  invariant stay byte-identical and synthetic-scoped, continuing to catch a filter-code
  regression. Real-data numbers land in a separate artifact whose gate asserts provenance and
  schema only, never the direction of the result. This is the structural form of D-25: a negative
  finding must be publishable without turning the build red, because a red build is pressure to
  tune (Phase 8 D-12).
- **D-10:** Both rate metrics are reported. Fitts throughput carries the arm-to-arm comparison
  against Phase 7's 0.374 vs 0.161; Webgrid BPS carries the comparison against Phase 8's 1.953
  and the 4.16 and 8.5 references RD-07 names. The Phase-7/8 D-13 and Phase-9 D-23 disclosure is
  restated plainly: Fitts throughput is not the Webgrid bitrate and the two are not comparable.
- **D-11:** A zero-hit outcome is published as the result, not worked around. Report no hits and
  BPS 0, then decompose why: decode R2, the absence of closed-loop error correction in an
  open-loop replay, the workspace-to-grid scale, and the dwell and timeout settings. A hit-
  independent proxy (cursor-to-target distance over time) is reported alongside, so RD-08 has a
  defined observable when the hit count is zero. Acquisition parameters are not relaxed until
  hits appear.
- **D-12:** Whatever the real-data rate number turns out to be becomes the README headline, with
  1.953 retained beside it and explicitly labeled the synthetic seed-locked replay it always was.
  Preserving the before-and-after is what makes the project's honesty discipline legible.

**README republish and gate rewrite (RD-09, RD-10)**

- **D-13:** `readme-policy.sh`'s handling of `24.7` becomes context-sensitive rather than a flat
  required or forbidden token. The figure may appear only under a Future work or retired heading
  and adjacent to a target marker; any occurrence framed as measured, achieved, or instrumented
  fails the build. The `--self-test` proves both directions bite: a retired-context occurrence
  passes, an achieved-context occurrence fails. This lets the README state the spec target it is
  retiring instead of going silent about it.
- **D-14:** The required-disclosure set gains a real-data provenance triple: the replayed session
  id, the real checkpoint sha256, and the open-loop-replay disclosure phrase. The README cannot
  state a real-data result without naming the bytes it came from and the limitation it carries.
  Mirrors what `decoder-policy.sh` already enforces on the metrics JSON. `photodiode` and `24.7`
  leave the required set; every other current required token stays. Every added or changed check
  gets a negative control in the same commit, keeping the existing nine-control discipline.
- **D-15:** v1 is declarable with the device gates still deferred. The iPad Pro M4 canonical
  captures, the live TestFlight gate, and the on-device HID registration gate are listed in the
  README's honest-gates table as v1's stated boundary, never as done, exactly as v0 shipped. The
  Mac real-data replay is a runbook evidence artifact on hardware that exists; only the iPad-M4
  rows stay device-gated and never auto-approved (D-17 carried forward).
- **D-16:** A recorded demo capture of the real-data loop on the M5 Pro is in scope as RD-08's
  evidence that a webgrid hit was demonstrated. Opening the first pull request is out of scope:
  it arms SwiftLint `--strict` for the first time in the project's history (around 535 repo-root
  violations today) and that is separate work, not a credibility-phase concern.

### Implementer's Discretion

Sensible defaults; planner and executor choose within the constraints above without re-asking:

- The export binary layout, dtype, and sidecar schema, within D-06's provenance requirement.
- Where the export script lives and how the daemon selects the export path (env var vs argv),
  and what the daemon does on a clean clone when the export is absent (skip cleanly, per the
  existing bench idiom).
- Whether the replay is paced against a wall clock or advanced deterministically, provided the
  simulation path stays reproducible (Phase 7/8 D-13).
- Whether the daemon still applies AES-GCM on the real-data path (default: yes, unchanged).
- The exact regular expressions implementing D-13's context-sensitive check and the wording of
  the D-14 disclosure phrases.
- The real-data evidence artifact set: how many files, their names, and the split between
  markdown evidence and committed JSON.
- The ADR number and scope for the photodiode retirement (ADR-0003 by sequence).
- Plan and wave decomposition across RD-07..RD-10.
- Whether the shuffled-target control uses shuffling, time reversal, or both.

### Deferred Ideas (OUT OF SCOPE)

- NDT2-style session conditioning to repair Phase 9's negative leave-one-session-out transfer.
  Out of scope for v0 and v1; the pooled-across-sessions assumption and its consequences are
  already documented in Phase 9's D-15.
- A live-human two-stage ReFIT retrain on real electrode data. Out of scope per Phase 8 D-12 and
  restated in the README's honest-gates table.
- The photodiode rig and the 10,000-trial campaign (LAT-01..LAT-08). Already preserved verbatim in
  ROADMAP "Future work"; this phase records why they were retired, it does not schedule them.
- A repo-wide SwiftLint `--strict` sweep and the first pull request. The strict gate has never
  executed because every phase went direct to main; it arms on the first PR at roughly 535
  repo-root violations. Its own piece of work, ahead of any ship step (D-16).
- Closing the deferred iPad Pro M4 device gates: the Phase-8 canonical latency, live TestFlight
  and on-device HID registration gates, plus Phase 9's canonical decoder p99. Disclosed as v1's
  boundary rather than closed (D-15).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research support |
|----|-------------|-----------------|
| RD-07 | ReFIT-Kalman gains re-fit on real data; raw-vs-ReFIT BPS ablation re-run on real Indy sessions with the honest remaining gap to 4.16 / 8.5 BPS stated | Sections "Correction 1" (the re-fit is unimplemented, not a re-run), "Correction 5" (4.16 is a 9x9 number, not 6x6), "Standard stack" (existing `fit_kalman_gain.py` + `ndt1.kalman_gain` API), "Architecture pattern 3" (four-arm ablation with gain and smoothing held fixed), "Pitfall 6" (the `--smoke` byte-identity constraint on the bench) |
| RD-08 | Closed loop replays a real session end-to-end at 120Hz with a webgrid hit; software-timed glass-to-glass p99 re-derived on the real-data path | "Correction 2" (there is no IPC leg in the demo today, and the Phase-8 p99 was never model-backed), "Correction 4" (the webgrid hit is geometry-limited: a perfect decoder hits 43/1025), "Architecture pattern 1" (the export contract), "Architecture pattern 2" (the source-swap seam and the seqLen trap) |
| RD-09 | Repo-wide sweep: no synthetic-derived number is presented as a real-data result; README, ADRs and every `*-evidence.md` carry the re-derived number or an explicit synthetic label | "Runtime state inventory" (the complete token-to-file map), "Correction 3" (CI has never executed, so "enforced in CI" is itself an unearned claim), "Correction 5" and "Correction 6" (two primary-source mislabels), "Pitfall 5" (the methodology label is a four-way coupled edit) |
| RD-10 | `readme-policy.sh` rewritten (required set drops `photodiode`/`24.7`, gains real-data provenance + a forbidden-token check on the retired figure), `--self-test` updated in lockstep; photodiode retired in an ADR with LAT-01..08 preserved | "Code examples" (tested helper and regex shapes for D-13 and D-14, with the measured baseline), "Architecture pattern 4" (the negative-control discipline), "Validation architecture" (SC#4 assertions) |
</phase_requirements>

## Summary

The phase as described in CONTEXT.md rests on four premises about the codebase that are false, and
two claims the repo publishes that primary sources contradict. All six were verified this session
against the repo, the materialized dataset, and the papers. None of them invalidate a locked
decision; each changes what the work under that decision actually costs, or what the honest number
is. They are listed as Corrections 1 to 6 below and each maps to a concrete planning consequence.

The single largest planning risk is not the decoder. It is geometry. Replaying the animal's own
recorded cursor through the repo's existing dwell-to-select model, at the 30x30 half-cell
acquisition radius over the session's 105 mm target field, registers a webgrid hit on 43 of 1,025
trials (4.2 percent). That is the ceiling a perfect decoder achieves. RD-08 asks for "a 30x30
webgrid hit demonstrated" and D-11 forbids relaxing acquisition parameters until hits appear, so
without a pre-registered ceiling measurement the phase is set up to produce a zero that says
nothing about the decoder. The fix costs one script and is fully within D-11's letter: measure the
true-cursor ceiling first, publish it as the control, and report the decoded result as a fraction
of an achievable maximum rather than against an implicit 100 percent.

The second-largest risk is scope. D-05 says "IPC, decoder, ReFIT, renderer and HID are unchanged",
but `Packages/CortexDemo` has no dependency on `CortexIPC`, no app-side ring consumer exists, and
`CortexDemoBench` never passed a model URL to the pipeline, so the Phase-8 8.3 ms p99 was measured
on a synthetic decode with an arithmetically modelled present timestamp and no IPC leg at all.
Routing real bins through the daemon is new integration work, and the resulting p99 will not be
like-for-like with Phase 8 unless the like-for-like seam is measured separately.

**Primary recommendation:** decompose RD-08 into two measured seams. Seam A is the Phase-8 seam
with exactly one variable changed (real bins and the real CoreML model in place of the synthetic
source and the synthetic decode fallback), giving a p99 strictly comparable to 8.3 ms. Seam B is
the wider daemon plus IPC plus consumer chain D-05 mandates, reported as a new and explicitly wider
measurement. Pre-register the true-cursor webgrid ceiling before any decoded number is scored, and
report every rate number against it. Implement the residual path in `fit_kalman_gain.py` rather
than assuming it exists.

## Project constraints (from AGENTS.md)

Directives extracted from `/Users/d0nmega/Developer/Cortex/AGENTS.md`, treated with the same
authority as locked decisions. [VERIFIED: read this session]

| Directive | Consequence for this phase |
|-----------|---------------------------|
| Apple Silicon M4-class only, Xcode 26 / Swift 6.2 / macOS 26 baseline | The real-data replay runs on the M5 Pro; no x86 fallback path to plan for |
| Decoder inference under 2 ms p99, renderer GPU under 0.4 ms, IPC round trip sub-microsecond | The re-derived p99 must stay inside these; Phase 9 measured 0.141 ms decoder p99 (CPU-placed, corroborating) and Phase 2 measured 208 ns IPC p99, so the real path has headroom |
| Hot path is the audio-callback regime: no `dispatch_async`, no Obj-C runtime, no locks, no ARC retain/release | Any real-bin reader that lands on the daemon producer path or the filter path must stay Foundation-free; `hotpath-policy.sh` enforces it. File I/O for the export belongs at startup, not per tick |
| App Store path: no `_ANEClient`, no deprecated entitlements, privacy manifest required | Unchanged by this phase; the `_ANEClient` negative control at `ci.yml:337` stays |
| `Decoder/` requires `uv sync --project Decoder --extra dev` before any `uv run --project Decoder pytest`, else a misleading `No module named numpy` | Every Python command in every plan must carry the sync first |
| `coremltools` pinned at 9.0 | No re-conversion in this phase, but any script importing it inherits the pin |
| Dataset lives in gitignored `Decoder/data/`, materialized from the committed checksum manifest | D-07's export follows the same pattern; `.gitignore:90` already covers `Decoder/data/` |
| Evidence discipline: every published number is a committed `*-evidence.md` with machine, pinned wheel versions, seed, and a reproducible runbook, labeled with the device and method that produced it | The RD-07 and RD-08 artifacts must carry this structure; the pattern is `09-velocity-evidence.md` |
| A number measured on synthetic data is labeled synthetic; a Mac number is not presented as an iPad-M4 number | This is the whole of RD-09, and `test_metrics_schema.py::test_latency_is_device_labeled_and_corroborating` already enforces it structurally for the decoder metrics |

Project skills: none. `.agent/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`
and `.codex/skills/` are all absent. [VERIFIED: filesystem check]

## Verified corrections to CONTEXT.md premises

These six items each contradict something the phase currently assumes. Every one was checked
directly. None asks the planner to revisit a locked decision; each changes the work that decision
implies.

### Correction 1: `fit_kalman_gain.py --data-dir` never fits from data. It is a stub that always falls back.

CONTEXT.md "Reusable Assets" says the script "already implements the RD-07 re-fit" and that "the
re-fit is a re-run plus a residual source, not new machinery." The source says otherwise.
[VERIFIED: `Decoder/scripts/fit_kalman_gain.py:154-189`]

```python
def fit_noise(data_dir: Path, seed: int) -> NoiseFit:
    if not data_dir.exists():
        ...
        return default_noise(seed)

    # Data dir exists but the residual extraction (decoded velocity vs true Indy velocity) is a
    # Plan-03 hook (it needs the behavior arrays data.py does not yet surface). Until then we do NOT
    # fabricate a residual: fall back to the documented default and say so plainly.
    print(...)
    return default_noise(seed)
```

Both branches return `default_noise`. There is no code path that computes `cov(z_decoded - v_true)`
or an empirical jerk distribution. The committed `KalmanConstants.swift` header records
`noise source = default   seed = 0` with `sigma_jerk^2=1.0, R=diag(0.25)`.
[VERIFIED: `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift:7-10`]

Planning consequence: RD-07's re-fit is an implementation task, not a re-run task. What it needs is
already available: `ndt1.kalman_gain.steady_state_gain(q_obs, r)` solves the gain and asserts Schur
stability, `white_noise_jerk_q(sigma_jerk_sq)` builds Q from a scalar, and the residual itself is
`decoded_velocity - true_binned_velocity` on the held-out split, which `fit_velocity_real.py`
already produces end to end (it builds the stride-1 window stack, runs the encoder, applies the
ridge readout, and scores against `bin_velocity` output). The honest R is the 2x2 covariance of the
held-out residual of that same pipeline. Budget one plan for it, and expect the units question in
Open Question 3.

### Correction 2: there is no IPC leg in the demo pipeline, and the Phase-8 p99 never ran the model.

D-05 states the re-derived p99 will be "like-for-like with the Phase-8 number, which included the
IPC leg." Three separate checks contradict this.

`Packages/CortexDemo/Package.swift` declares dependencies on CortexDecoder, CortexReFIT,
CortexRender, CortexBCIHID and CortexCore. `CortexIPC` is not among them.
[VERIFIED: `Packages/CortexDemo/Package.swift:37-43`]

Neither `Apps/CortexMac` nor `Apps/CortexiOS` references `CortexIPC`, `HarnessConsumer` or
`ShmRing`. Only the `CortexDaemon` target depends on the IPC products.
[VERIFIED: grep across `Apps/`, and `project.yml:169-177`]

`CortexDemoBench` constructs the pipeline with no model URL, so `isModelBacked` is false for the
whole run and every tick used `ClosedLoopPipeline.syntheticDecodedVelocity`. The present timestamp
is not read from a display link; it is computed as the next 120 Hz boundary after the measured
pipeline cost. [VERIFIED: `Packages/CortexDemo/Sources/CortexDemoBench/main.swift:90` and `:109-116`]

```swift
let pipeline = ClosedLoopPipeline(seed: seed)          // no modelURL argument
...
let framesElapsed = pipelineDoneNs / framePeriodNs
let presentNs = (framesElapsed + 1) * framePeriodNs    // modelled, not measured
```

Planning consequence: the honest reading of "re-derived on the real-data path" needs two numbers.
Seam A holds the Phase-8 measurement geometry fixed (same bench, same modelled present, same
pipeline stages) and changes exactly one thing, the spike source and the decode, so the delta is
attributable. Seam B is the D-05 chain (daemon reads the export, encrypts, writes the ring, an
app-side consumer decrypts and accumulates the window), which is genuinely new wiring and which
measures a strictly wider seam. Reporting Seam B alone against 8.3 ms would be a comparison across
two different measurement boundaries, which is the same class of defect RD-09 exists to remove.

### Correction 3: no CI workflow in this repository has ever executed.

`gh api repos/D0NMEGA/Cortex/actions/runs --jq '.total_count'` returns `0`, and `origin/main` is
not a known revision locally, so `main` has never been pushed. [VERIFIED: `gh api` and `git log`
this session]. `ci.yml` triggers on `push` to `main` as well as `pull_request`, so the trigger is
not the reason. The repo has simply never left the machine.

The v1.0 milestone audit already records a weaker form of this ("SC#1 (CI green on macos-15) gate
is real but never fired"). [VERIFIED: `.planning/v1.0-MILESTONE-AUDIT.md`]

The README currently states, of the architectural commitments, "These are enforced as CI structural
gates so a future commit cannot silently regress them" (line 32-33) and, of the rejected
alternatives, "Each is enforced somewhere in CI" (line 46). Under this phase's own standard, those
are forward-looking claims presented in the present tense. The accurate statement is that the gates
are wired into `ci.yml` and each is proven to bite by a locally-run `--self-test`, and that the
workflow has not yet run on a hosted runner.

Planning consequence, three parts. First, RD-09's sweep should include this claim, not only the
numeric ones; it is the claim a reviewer verifies by clicking the Actions tab. Second, SC#4's
verification evidence must be a locally-captured `--self-test` transcript, not "CI is green".
Third, the D-16 boundary is slightly wider than stated: `swiftlint --strict` arms on the first
push, not only on the first pull request, so any step that pushes `main` triggers it.

### Correction 4: the 30x30 webgrid hit is geometry-limited. A perfect decoder hits 4.2 percent of trials.

Measured on `indy_20160630_01` by replaying the animal's own `cursor_pos` against its own
`target_pos` through the repo's dwell-to-select rule (continuous dwell inside the acquisition
radius), at 250 Hz over all 1,025 target-constant segments. [VERIFIED: computed this session from
the materialized `.mat`]

| Acquisition radius | Dwell 0.30 s | Dwell 0.10 s |
|---|---|---|
| 1.75 mm (30x30 half-cell over the 105 mm target field) | **43 / 1025 (4.2%)** | 153 / 1025 (14.9%) |
| 2.32 mm (30x30 half-cell over the 139 mm cursor-y span) | 83 / 1025 (8.1%) | 242 / 1025 (23.6%) |
| 2.86 mm (30x30 half-cell over the 172 mm cursor-x span) | 147 / 1025 (14.3%) | 334 / 1025 (32.6%) |
| 3.50 mm (a full 30x30 cell over the target field) | 249 / 1025 (24.3%) | 449 / 1025 (43.8%) |
| 7.50 mm (half the real 15 mm target pitch) | 951 / 1025 (92.8%) | 1007 / 1025 (98.2%) |
| 15.00 mm (the real target pitch) | 1023 / 1025 (99.8%) | 1025 / 1025 (100%) |

Read the 7.50 mm row as the task's own implied acceptance zone: the animal held a 300 ms dwell
inside 7.5 mm of the target on 92.8 percent of trials. The real task is effectively a 14x14 grid
over that field, not a 30x30 one.

Planning consequence: pre-register the ceiling. Compute it before any decoded number is scored,
commit it as part of the RD-08 artifact, and report the decoded hit count as a fraction of it. This
satisfies D-11 ("acquisition parameters are not relaxed until hits appear") without pretending the
denominator is 1,025, and it converts an otherwise uninterpretable zero into an interpretable one,
which is exactly what D-11's own "an uninterpretable zero is not [acceptable]" demands. The
alternative reading, that the grid should be chosen to match the task, is a live option worth
stating in the artifact but it is not what D-02 locks.

### Correction 5: the 4.16 BPS reference is a 9x9 dense-grid number, not a 6x6 number.

Verified against the full text of Pandarinath et al. 2017, eLife 18554. [VERIFIED:
elifesciences.org/articles/18554, retrieved 2026-09-05]

Verbatim from the paper: on the 6x6 grid, "average performance was 2.2 +/- 0.4 bits per second
(bps; mean +/- s.d.), 3.7 +/- 0.4 bps, and 1.4 +/- 0.1 bps" for T6, T5 and T7 respectively. The
4.16 figure appears only here: "Across two days of testing with T5 (Figure 3 figure supplement 2
and Video 10; 8 evaluation blocks), average performance was 4.16 +/- 0.39 bps", in a section that
opens "We performed additional grid measurements with T5 in which targets were arranged in a denser
grid (9 x 9)" and notes the result "was significantly greater than the 6 x 6 performance".

The repo labels it 6x6 in at least six places:
`README.md:123` ("BrainGate 6x6 (Pandarinath 2017) | 4.16"),
`Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift:42-45`
(`public static let brainGate6x6BPS = 4.16`, doc comment "BrainGate (Pandarinath 2017) 6x6 Webgrid
bitrate"), `Packages/CortexReFIT/Tests/CortexReFITTests/WebgridBPSTests.swift:98`,
`docs/cortex-spec.md:53`, `.planning/REQUIREMENTS.md:124` (PERF-01: "Match BrainGate Webgrid 6x6
BPS (4.16 BPS)"), and `docs/adr/0002-...md:81`. [VERIFIED: grep this session]

The README's stated rationale, "this `log2(N)` normalization is what makes a 30x30 result
comparable to BrainGate's 6x6" (line 110-111), is built on that mislabel.

Planning consequence: this is squarely inside RD-09 and it is a source-checkable error in a Swift
identifier, a unit test, a requirement statement and the README. The cheapest correct fix is to
rename the constant to name the condition it measured (for example `brainGateDenseGridBPS = 4.16`
with a doc comment recording "T5, 9x9 dense grid, 8 evaluation blocks") and add the 6x6 figure
(T5 3.7 +/- 0.4) beside it, so the comparison the README makes is stated against the condition that
produced it. `readme-policy.sh` requires no `4.16` token today, so the gate is not disturbed.

Corroborating detail worth carrying: the paper's own bitrate uses net correct selections, where
"each incorrect selection requires an additional correct selection to compensate (analogous to
having to select a keyboard's backspace key)". That is exactly the repo's `(Sc - Si)` and its
"N = 900 incl. the delete/cancel key" framing, so the formula itself is faithful.

### Correction 6: the 8.5 Neuralink reference is unsourceable as stated, and the repo already contradicts itself.

`docs/cortex-spec.md:54` and `:172` state "Neuralink P1 Noland Arbaugh peak | PRIME study, May 2024
| **8.5 BPS verified**". `docs/cortex-spec.md:313`, in the same file's own source list, states
"Neuralink: 'PRIME Study Progress Update - User Experience' - neuralink.com (Noland Arbaugh **8
BPS** verified)". The repo therefore cites the same source for two different numbers.
[VERIFIED: grep this session]

The current public page is more specific and does not support 8.5 either. As of 2026-09-05,
neuralink.com/webgrid states verbatim: "Our clinical trial participants have achieved over 10 BPS
controlling a computer with their brain", and describes the score as "derived from net correct
targets selected per minute (NTPM), grid size, and the number of click types". The page's default
grid is 35x35. [VERIFIED: neuralink.com/webgrid rendered and read this session; the page carries
exactly two BPS statements and 9.51 is not among them]

The 10-RESEARCH-INPUTS pass recorded 9.51 from this page. That figure is not present today. Either
the page changed, or the figure came from a secondary summary. Treat 9.51 as unverified and do not
cite it.

Planning consequence: `readme-policy.sh:148` requires the literal token `8.5`, and D-14 keeps every
other current required token, so `8.5` stays a required token unless the planner changes it. Three
dispositions, in preference order:

1. Keep `8.5` but date and source it explicitly everywhere, and state the current public figure
   beside it. Cheapest, gate untouched, and it makes the staleness the reader's information rather
   than a hidden defect. Requires resolving the internal 8-vs-8.5 contradiction in `cortex-spec.md`
   first, since a figure the repo cannot self-consistently source is not sourced.
2. Re-point to the current public statement ("over 10 BPS", neuralink.com/webgrid, accessed date).
   This changes `readme-policy.sh`'s required token, `WebgridBPS.referencePeakBPS`,
   `WebgridBPSTests.swift:97`, ADR-0002 and the spec, and it replaces a precise-looking number with
   an honest lower bound.
3. Report the gap to a range with both endpoints sourced.

Whichever is chosen, the phase must not leave an unsourced bare `8.5` standing, and the choice
belongs in the RD-09 sweep rather than with an executor.

One further note, relevant to PERF-03: Neuralink's own description includes "the number of click
types" as a scoring factor. The repo's harness is single-click-type and its disclosed formula omits
that term. With one click type the term contributes nothing, but the README should say the harness
is single-click-type rather than implying full formula parity.

## Ground truth from the dataset

All measured this session from the materialized, checksum-pinned `.mat` files under
`Decoder/data/`. These are the numbers the D-06 export contract and the D-02 re-grid depend on.

### `target_pos` is present in all four sessions and is a discrete target grid

[VERIFIED: h5py inspection this session]

| Session | `target_pos` shape (h5py) | Distinct x | Distinct y | Distinct (x,y) | Target changes | x range (mm) | y range (mm) |
|---|---|---|---|---|---|---|---|
| indy_20160624_03 | (2, 125000) | 7 | 8 | 50 | 348 | -60.0 to 60.0 | 0.0 to 130.0 |
| indy_20160627_01 | (2, 840737) | 7 | 7 | 49 | 2335 | -60.0 to 60.0 | 10.0 to 130.0 |
| **indy_20160630_01** (D-08) | (2, 365809) | 8 | 8 | **64** | **1025** | -52.5 to 52.5 | 7.5 to 112.5 |
| indy_20160915_01 | (2, 95262) | 8 | 8 | 64 | 296 | -52.5 to 52.5 | 7.5 to 112.5 |

`target_pos` is per-sample (one column per behavior sample, same width as `t`, `cursor_pos` and
`finger_pos`), holding a piecewise-constant step function. It is not a per-trial list. Trial
boundaries are recovered as the indices where it changes.

For `indy_20160630_01`: 15 mm target pitch on both axes, a 105.0 x 105.0 mm target field, 1,025
trials over 1,463.232 s, trial duration mean 1.428 s / median 1.300 s / p10 1.024 s / p90 1.898 s /
min 0.656 s / max 16.972 s. Behavior clock is 250 Hz (median `diff(t)` = 0.004 s), starting at
t = 148.984 s. `load_session` yields 73,161 twenty-millisecond bins for this session, and
`bin_velocity` produces the same 73,161 rows.

### The cursor frame is the finger frame times ten

[VERIFIED: least-squares fit this session]

```
cursor_x = 10.005060 * planar_x(cm) + 0.000528     R2 = 0.99996642
cursor_y = 10.004078 * planar_y(cm) + -0.023824    R2 = 0.99997487
```

where `planar_cm` is exactly what `load_session` returns (`(-finger[1:3, :]).T`). `cursor_pos` and
`target_pos` are in millimetres; `finger_pos` planar is in centimetres. The mapping is a pure unit
conversion with an offset under 0.03 mm and a residual under 0.004 percent. No calibration fit is
needed to put the decoded cm/s velocity into the target frame: multiply by 10.

This also means `cursor_pos` carries no information the export needs beyond `finger_pos`, so
D-01's decision to leave `cursor_pos` unread costs nothing. It is worth reading once, in the
export script's own verification step, to confirm the x10 relation holds on the session being
exported, then discarding it.

### Workspace spans and speed

[VERIFIED: computed this session, `indy_20160630_01`]

- Target field: 105.0 x 105.0 mm.
- Cursor excursion: 171.7 x 139.1 mm, i.e. the cursor leaves the target field on both axes.
- Binned speed magnitude (20 ms bins, cm/s): p50 1.822, p90 18.880, p99 36.846, max 64.425.
- Cursor-to-target distance (mm): p1 1.01, p5 2.31, p25 6.13, p50 12.88, p90 77.08. Fraction of
  samples within 3.5 mm: 10.28 percent; within 7.5 mm: 32.77 percent; within 15 mm: 53.92 percent.

Grid arithmetic for D-02:

| Normalisation span | 30x30 cell | Half-cell acquisition radius |
|---|---|---|
| 105.0 mm (target field) | 3.50 mm | 1.75 mm |
| 139.1 mm (cursor y span) | 4.64 mm | 2.32 mm |
| 171.7 mm (cursor x span) | 5.72 mm | 2.86 mm |

Normalising on the target field clips real cursor excursions, because `CursorIntegrator` clamps to
[0,1]. Normalising on the cursor span keeps every excursion but shrinks the target field to roughly
61 percent by 75 percent of the grid. Either is defensible; the choice must be recorded in the
sidecar (D-06 already requires the workspace-to-grid mapping) and disclosed in the evidence.

### The information-theoretic mismatch the planner must decide

`log2(900) = 9.81` bits per selection is the normalisation `WebgridBPS` applies. The real task
presented **64** distinct targets, worth `log2(64) = 6.0` bits. Snapping a 64-target track onto a
900-cell grid and then crediting 9.81 bits per hit awards 1.64x more information per selection than
the task contained. On a Bliss Chapman review this is the same defect class as a synthetic number
labeled real.

D-02 locks the 30x30 re-grid, and nothing here contradicts it. What the planner must add is the
reporting: publish the real-data BPS at both normalisations (N = 900 for continuity with 1.953, and
N = 64 for the task-faithful number) and state which one the headline uses. `WebgridBPS.bitsPerSecond(n:correct:incorrect:seconds:)`
already takes `n` as a parameter, so this costs one extra call, not a new metric.

## Standard stack

Nothing new needs installing. Every capability this phase requires already exists in the repo at a
pinned version. The table below is what to use, and where it already is.

### Core

| Component | Version / location | Purpose | Why this and not something else |
|---|---|---|---|
| `ndt1.kalman_gain` | `Decoder/src/ndt1/kalman_gain.py` (205 lines) | `full_transition()`, `full_measurement()`, `observable_gain(q_obs, r)`, `steady_state_gain(q_obs, r)` with a Schur-stability assertion and zeroed position rows | The observability resolution (07-RESEARCH 2.3) is already encoded here; re-deriving it would risk a non-stabilizing gain |
| `Decoder/scripts/fit_kalman_gain.py` | committed, emits `KalmanConstants.swift` | The code-gen path and the swiftformat-clean SIMD row renderer | The generated-file discipline (do-not-hand-edit header plus `KalmanConstantsTests`) only holds if the emitter stays the single writer |
| `ndt1.kinematics` | `Decoder/src/ndt1/kinematics.py` (332 lines) | `planar_velocity_250hz`, `bin_velocity` (bin edges identical to `bin_spikes` by construction), `apply_lag`, `heldout_r2`, `lag_sweep_r2` | `bin_velocity` recomputes `num_bins` with the same `floor((t_end-t_start)/bin_s)` arithmetic and reuses the high-edge clip, which is what makes the rates and velocity matrices row-aligned by construction rather than by convention |
| `ndt1.sessions` | `Decoder/src/ndt1/sessions.py` (209 lines) | `SessionLoad` frozen dataclass, `available_sessions`, `pooled_splits`, `loso_folds` | The export script should build on `available_sessions` so an unloadable session becomes a recorded `SessionExclusion` rather than a crash |
| `Decoder/scripts/fit_velocity_real.py` | committed (Plan 09-07) | The stride-1 BC1S window stack, encoder forward, ridge readout, held-out scoring at `SEQ_LEN = 32` | The residual for the R fit is the held-out output of exactly this pipeline; reimplementing the window stack is the fastest way to introduce an off-by-one against the committed R2 |
| `Packages/CortexReFIT` | `KalmanFilter`, `IntentRotation`, `WebgridAcquisition`, `WebgridBPS`, `FittsThroughput` | The filter, the magnitude-preserving rotation, dwell-to-select, the clamped bitrate, the S&M-2004 throughput | All five are unit-tested and gate-guarded; the fourth arm is a new `case` in the bench's `Arm` enum, not new math |
| `Packages/CortexDemo` | `ClosedLoopPipeline`, `SyntheticSpikeSource`, `GlassToGlassTimer` | The decode / filter / integrate / webgrid assembly and the software-timed sampler | The seam to swap is `ClosedLoopPipeline.spikeSource` plus the `numBins` it feeds into `SpikeInputBuffer` |
| `Tools/scripts/decoder-policy.sh` + `check_decoder_provenance.py` | committed (Plan 09-09) | The provenance-gate idiom: two grep legs plus a Python set-comparison leg, with a four-case `--self-test` | D-14's provenance triple and D-09's real-data gate are this pattern applied to two new files |
| `Decoder/tests/test_metrics_schema.py` | committed | Schema and provenance assertions plus a source self-check that forbids any measured-value-versus-bar assertion in the module | This is the executable form of D-09; copy the marker-split guard verbatim into the real-data schema test |

### Supporting

| Component | Location | When to use |
|---|---|---|
| `ndt1.qc.firing_rate_stats` / `band_violations` | `Decoder/src/ndt1/qc.py` | Sanity-check the exported bins before they leave Python; a silently misparsed export is the D-06 failure mode |
| `ndt1.real_checkpoint` | `Decoder/src/ndt1/real_checkpoint.py` | `REAL_ENCODER_CHECKPOINT`, `REAL_VELOCITY_CHECKPOINT`, `checkpoint_sha256(path)`, `SHA_PREFIX_LEN = 12`. This is where D-14's "real checkpoint sha256" comes from |
| `Decoder/scripts/download_indy.py` | committed | The template for D-07's export materializer: manifest-driven, magic-bytes then size then md5 then sha256, explicit exception types only |
| `Packages/CortexDecoder` `SpikeInputBuffer` | `ZeroCopyInput.swift` | The `(1, channels, 1, seqLen)` BC1S IOSurface input; `seqLen` must be 32 for the shipped model |
| `LatencyHistogram` | `Packages/CortexDecoder` | Device-annotated p50/p99/max; already carries the corroborating-versus-canonical annotation string |

**Installation:** none. `uv sync --project Decoder --extra dev` is the only environment step, and it
is mandatory before any `uv run --project Decoder pytest`. [VERIFIED: AGENTS.md and `ci.yml:579`]

### Version verification

| Package | Version | Source |
|---|---|---|
| coremltools | 9.0 | pinned in `Decoder/pyproject.toml`; recorded in every `env` block of `09-decoder-metrics.json` [VERIFIED] |
| torch | 2.12.1 | `09-decoder-metrics.json` `env` [VERIFIED] |
| numpy | 2.4.6 | same [VERIFIED] |
| h5py | 3.16.0 | same [VERIFIED] |
| python | 3.12.13 | same [VERIFIED] |
| scikit-learn | 1.9.0 | same [VERIFIED] |
| Swift toolchain | Xcode 26.3 / Swift 6.2.4 | `09-decoder-metrics.json` `latency.toolchain` [VERIFIED] |

No new dependency is warranted. The export format in D-06 is deliberately "a compact binary with a
JSON sidecar" precisely so that no serialization library is needed on either side.

### Alternatives considered

| Instead of | Could use | Tradeoff |
|---|---|---|
| Raw little-endian binary + JSON sidecar (D-06) | `.npy` read by a Swift npy parser | `.npy` has a text header that a Swift reader must parse; raw binary plus an explicit sidecar moves all the structure into JSON where a human and a gate can both read it. D-06 already picks this |
| Adding a fourth `Arm` case to `CortexReFITBench` | A separate real-data bench executable | A fourth case risks perturbing the `--smoke` bytes that `bps-policy.sh` and the `ci.yml:378-388` byte-identity check depend on. A separate executable, or a flag-gated separate JSON, is safer. See Pitfall 6 |
| Swift-side re-binning of spikes | Keep binning in `ndt1` (D-06) | D-06 already locks this, and the reason is measurable: `bin_velocity` and `bin_spikes` share bin-edge arithmetic by construction. A second binner is a silent drift hole |

## Architecture patterns

### Pattern 1: the D-06 export, and the two aggregation rules it needs

The export carries four aligned arrays for `indy_20160630_01`, all on the same 20 ms bin edges,
plus a JSON sidecar.

| Array | Shape | Dtype | Producer |
|---|---|---|---|
| binned spike counts | (73161, 96) | float32 (or float16 for wire parity) | `ndt1.data.bin_spikes` via `load_session` |
| true velocity | (73161, 2) | float64 | `bin_velocity(planar_velocity_250hz(planar_cm, t), t, ...)` |
| target track | (73161, 2) | float64 | new, see the aggregation rule below |
| bin start times | (73161,) | float64 | `t_start + i * 0.020` |

Aggregation rules differ by array and this is the one place a naive implementation goes wrong:

- Velocity is **mean-aggregated** per bin. `bin_velocity` already does this and raises if any bin
  is empty rather than emitting a NaN.
- The target track must **not** be mean-aggregated. `target_pos` is a step function on a 15 mm
  discrete grid; averaging across a bin that spans a target change produces an off-grid target that
  the animal never saw, which is precisely the fabrication D-01 forbids. Use the **last sample in
  the bin** (matching `apply_lag`'s window-ending-at-bin-i convention) or the per-bin mode. Assert
  after aggregation that every emitted target value is a member of the session's 64 observed
  (x, y) pairs; that assertion is cheap and it is the export's own negative control.

Sidecar fields, satisfying D-06 and feeding D-14:

```json
{
  "schema_version": 1,
  "session_id": "indy_20160630_01",
  "source_sha256": "<the manifest's committed digest for that .mat>",
  "manifest_path": "Decoder/manifests/indy_sessions.json",
  "bin_ms": 20.0,
  "n_bins": 73161,
  "n_channels": 96,
  "lag_bins": 1,
  "lag_ms": 20.0,
  "behavior_hz": 250.0,
  "units": {"spikes": "counts/bin", "velocity": "cm/s", "target": "mm"},
  "frame_scale_mm_per_cm": 10.0,
  "workspace": {
    "normalisation": "target_field | cursor_span",
    "x_min_mm": -52.5, "x_max_mm": 52.5,
    "y_min_mm": 7.5,  "y_max_mm": 112.5,
    "grid_rows": 30, "grid_cols": 30,
    "cell_mm": 3.5, "acquisition_radius_mm": 1.75
  },
  "target_grid": {"distinct_targets": 64, "pitch_mm": 15.0, "log2_n_task": 6.0},
  "trials": 1025,
  "encoder_checkpoint_sha256": "f95b257bf2479b49102a2d8afee3c46d9008c51ba754d42a60a26762b7d3af8e",
  "velocity_checkpoint_sha256": "9d542cb51d4af4811f324fbc6bda0b503da7b15aafc98b5e1340e1a7f49cce65",
  "env": {"python": "...", "numpy": "...", "h5py": "..."},
  "disclosure": "open-loop replay of a recorded session; the subject was not in the loop"
}
```

The checkpoint digests are already committed in `09-decoder-metrics.json` and reachable from
`ndt1.real_checkpoint.checkpoint_sha256`. [VERIFIED]

### Pattern 2: the source-swap seam in `ClosedLoopPipeline`, and the seqLen trap

`ClosedLoopPipeline` holds `public let spikeSource: SyntheticSpikeSource` and builds
`SpikeInputBuffer(device:, seqLen: spikeSource.numBins, channels: spikeSource.channels)`.
`SyntheticSpikeSource`'s default is `numBins: 8`. The shipped real-data model's input is
`spikes` with shape `(1, 96, 1, 32)` and output `var_745` `(1, 2, 1, 1)`.
[VERIFIED: `coremltools` spec read of `ndt1_real_vel_sweep_fp16.mlpackage` and
`ndt1_real_vel_4bit_per_grouped_channel_1.mlpackage` this session; `SEQ_LEN = 32` in
`fit_velocity_real.py:144`]

The failure is silent. `decodeWithModel` wraps both the buffer write and `decoder.decode(buffer)`
in `try?` and returns nil on any error, and `decode(window:tick:cursor:)` then falls through to
`syntheticDecodedVelocity`. A shape mismatch therefore produces a running loop whose
`decodedByModel` is false and whose numbers are synthetic. That is a "decoder genuinely in loop"
claim silently becoming false.

Two structural requirements follow:

1. The real path must construct the pipeline with `numBins == 32`, and the buffer's `seqLen` must
   be derived from the model, not from the source's default.
2. The RD-08 run must **assert** `decodedByModel == true` on every tick and fail loudly otherwise.
   A single boolean, counted and committed in the evidence JSON (`ticks_model_backed` versus
   `ticks_total`), turns a silent fallback into a visible one. This is the cheapest and highest-value
   assertion in the whole phase.

The seam itself: introduce a small protocol (`numBins`, `channels`, `window(_:) -> [Float16]`),
conform both `SyntheticSpikeSource` and a new `RecordedSpikeSource`, and inject. Note that
`ClosedLoopPipeline` carries a grep gate (T-08-03-01) asserting the Phase-6 oscillator producer's
type name appears nowhere in that file; a new type name must not collide with it.

### Pattern 3: the four-arm ablation, with gain and smoothing held fixed

The existing three arms in `CortexReFITBench` differ only in the filter stage, on an identical
replay:

| Arm | Filter | Gain and smoothing |
|---|---|---|
| `raw` | none, decoded velocity straight to the integrator | unity gain, no smoothing |
| `kalman_only` | `filter.step(measurement:target: nil, acquisitionRadius:)` | Kalman gain K, Kalman smoothing |
| `refit` | `filter.step(measurement:target:acquisitionRadius:)` | **same** K, **same** smoothing, plus rotation |

`IntentRotation.rotate` preserves the decoded speed exactly (`speed = |z|; z_rot = speed * d/|d|`)
and only changes direction. [VERIFIED: `IntentRotation.swift:45-66`]

This matters for Finding 2 of the research inputs (Willett et al. 2017, IEEE TBME 65(9):2066-2078,
DOI 10.1109/TBME.2017.2783358), which warns that "simple differences in gain and smoothing
properties have a large effect on online performance and can confound decoder comparisons"
[CITED: 10-RESEARCH-INPUTS.md Finding 2, sourced from PubMed]. The consequence is precise:

- `refit` minus `kalman_only` isolates the rotation with gain and smoothing **held fixed**. This is
  the attributable number.
- `refit` minus `raw` conflates the rotation with the Kalman's gain and smoothing. This is the
  headline comparison the repo currently makes.

The Phase-8 synthetic numbers already show the two differ in sign: Webgrid BPS raw 1.292,
kalman_only 1.183, refit 1.953. Kalman smoothing alone made things worse; all of the uplift is the
rotation. Say that explicitly in the real-data artifact, because it is the direct answer to the
Willett confound and it costs nothing to report.

Add, per arm, two measured quantities so the confound is reported rather than assumed away:

- realized gain: `mean(|v_out|) / mean(|v_in|)` over the arm's ticks;
- realized smoothing: lag-1 autocorrelation of the output velocity, or the mean absolute
  tick-to-tick change in heading.

D-04's fourth arm (`refit_shuffled_target`) must shuffle **only the rotation's target**, keeping the
scoring target true. If both are shuffled the control is vacuous, because the cursor would be
rotated toward the same target it is scored against. State this in the plan; it is the single
detail that decides whether the control tests what D-04 says it tests. Time reversal is the
stronger of the two options offered by discretion, because it preserves the target track's
autocorrelation and spatial distribution while destroying its temporal relationship to the spikes.

### Pattern 4: the negative-control gate discipline

Every build-failing gate in this repo ships with a `--self-test` that proves each check bites, and
the self-test changes in the same commit as the check. `readme-policy.sh` currently has nine
controls plus a clean-baseline case, and all ten pass today (`./Tools/scripts/readme-policy.sh`
exit 0, `--self-test` exit 0). [VERIFIED: run this session]

The `decoder-policy.sh` pattern is the one D-09 and D-14 should copy: two cheap grep legs plus one
Python leg for anything that is a set comparison rather than a token presence, and a self-test that
mutates exactly one thing per case so a passing case proves one assertion and nothing else.

### Anti-patterns to avoid

- Do not add assertions on the direction or magnitude of a real-data result to any CI gate. D-09
  requires provenance and schema only. `test_metrics_schema.py::test_no_number_is_a_measured_threshold_assertion`
  is the executable form of that rule and it self-scans the module for `co_bps.*>`, `r2.*>` and
  `p99.*<` patterns. Copy the guard-split-marker mechanism into the real-data schema test.
- Do not change `refit_bps.json` or `webgrid_bps.json`'s `--smoke` output. See Pitfall 6.
- Do not mean-aggregate `target_pos`. See Pattern 1.
- Do not let a shape mismatch decide silently which decode path ran. See Pattern 2.
- Do not report a Seam B (daemon plus IPC) latency against the Phase-8 8.3 ms. See Correction 2.

## Don't hand-roll

| Problem | Do not build | Use instead | Why |
|---|---|---|---|
| Binning real spikes for the export | A Swift or fresh Python binner | `ndt1.data.bin_spikes` via `load_session` | D-06 locks it, and `bin_velocity` is aligned to `bin_spikes` by shared arithmetic, not by convention. A second binner silently desynchronises rates from labels |
| Deriving velocity from `finger_pos` | A Savitzky-Golay or any filtered derivative | `ndt1.kinematics.planar_velocity_250hz` | The module documents why there is no smoothing filter: window length and polynomial order would each need justifying and can smooth away real fast dynamics |
| Solving the steady-state Kalman gain | A fresh DARE solve | `ndt1.kalman_gain.steady_state_gain` | It asserts Schur stability and zeroes the unobservable position rows; a hand-rolled solve can silently return a non-stabilizing gain |
| Writing `KalmanConstants.swift` | Hand-editing the literals | Re-run `fit_kalman_gain.py` | The file carries a do-not-hand-edit header backed by `KalmanConstantsTests`; the SIMD row renderer also emits swiftformat-clean output by construction |
| Cursor clamping and NaN rejection | A new clamp in the replay harness | `CursorIntegrator.integrate(latest:dt:)` | It is the single [0,1] clamp and non-finite-reject seam (Phase-6 T-06-02-01) and both the pipeline and the bench already route through it |
| The bitrate formula | A local `log2` expression | `WebgridBPS.bitsPerSecond(n:correct:incorrect:seconds:)` | The mandatory `Swift.max(0,` clamp lives there and `bps-policy.sh` greps for it in that file specifically |
| Dwell-to-select hit detection | A distance threshold in the replay loop | `WebgridAcquisition.runTrial(positions:target:)` | The continuous-dwell semantics (the counter resets on any excursion) and the timeout-endpoint behavior are already unit-tested |
| Checkpoint digests | Recomputing sha256 ad hoc | `ndt1.real_checkpoint.checkpoint_sha256` plus the digests already in `09-decoder-metrics.json` | Keeps D-14's provenance triple pointing at the same bytes the decoder gate already validates |
| Manifest-driven materialization for the export | A fresh downloader | Copy `download_indy.py`'s structure | Magic bytes, then size, then md5, then sha256, with explicit exception types only, is the pattern the ruff BLE gate and threat T-09-01-01 both require |

**Key insight:** almost every "new" capability this phase needs already exists in a tested,
gate-guarded form. The genuinely new code is small and specific: the `target_pos` read, the export
writer and reader, the residual extraction for R, the recorded spike source, the app-side IPC
consumer, the fourth ablation arm, and the two gate rewrites. Everything else is wiring.

## Common pitfalls

### Pitfall 1: assuming the Kalman re-fit is a re-run

Covered as Correction 1. Warning sign: a plan task worded "re-run `fit_kalman_gain.py --data-dir`"
with no task that computes a residual. Detection: after the run, `KalmanConstants.swift`'s header
still says `noise source = default`. Make that header string the acceptance criterion: the re-fit
succeeded only if it says `indy-heldout`.

### Pitfall 2: the silent synthetic fallback

Covered as Pattern 2. Warning sign: the real-data run completes suspiciously fast and produces
numbers close to the synthetic ones. Detection: `ClosedLoopPipeline.isModelBacked` and a per-tick
`decodedByModel` count committed in the evidence.

### Pitfall 3: a geometrically-forced zero

Covered as Correction 4. Warning sign: zero hits reported with no ceiling measurement beside them.
Detection: the pre-registered true-cursor ceiling, computed and committed before the decoded run.

### Pitfall 4: mean-aggregating the target track

Covered as Pattern 1. Warning sign: exported target values that are not among the session's 64
observed pairs. Detection: the membership assertion in the export script.

### Pitfall 5: the methodology label is a four-way coupled edit

`GlassToGlassTimer.methodologyLabel` is the literal string
`"software-timed pipeline latency - excludes the compositor's 1-3 frames of scanout, which is
exactly the delta the v1 photodiode rig (Phases 9-10) quantifies"`. Four things depend on it:

1. `GlassToGlassTimerTests.swift:44-55` asserts the label verbatim, and separately asserts it
   `.contains("photodiode")`.
2. `README.md:81` quotes it inside the latency table.
3. `readme-policy.sh:136` requires the substring `software-timed pipeline latency` in the README,
   which is a prefix of that same label.
4. `Packages/CortexDemoBench/main.swift` prints it, and `glass_to_glass.json` carries it.

[VERIFIED: all four read this session]

RD-09 must change this label, because it names "the v1 photodiode rig (Phases 9-10)" and those
phases no longer build a photodiode rig. The four edits must land in one commit, and
`readme-policy.sh`'s `software-timed pipeline latency` requirement must survive (D-14 keeps every
other current required token), so the label's prefix must not change. Recommended: keep the prefix
byte-identical and replace only the trailing clause, so requirement 3 and the README quote both
continue to hold.

### Pitfall 6: perturbing the `--smoke` bytes

Two CI legs depend on the bench's synthetic output being stable:

- `ci.yml:378-388` re-runs `CortexReFITBench --smoke` and diffs `.bench/refit_bps.json` against the
  committed Phase-7 artifact **byte-for-byte**.
- `bps-policy.sh` runs `--smoke` twice and diffs `.bench/webgrid_bps.json` byte-for-byte, and
  requires the literal formula string and `"n_targets": 900` in it.

[VERIFIED: `ci.yml` and `bps-policy.sh` read this session]

Adding a field to `RefitBPS` or `WebgridBPSReport`, or adding an arm that changes the `reaches`
sequence, breaks these. D-09 already says the Phase-7 artifact stays byte-identical; the concrete
implication is that the fourth arm and every real-data output must go to a **new** JSON behind a
**new** flag, leaving the `--smoke` code path and its two payload structs untouched.

### Pitfall 7: `CORTEX_REFIT_REPLAY_URL` is a decoy that mislabels its own output

`CortexReFITBench` accepts `CORTEX_REFIT_REPLAY_URL`, and when the path exists it sets
`source = "indy-replay (\(replayURL.lastPathComponent)) + seed-locked synthetic perturbation"` and
then runs the synthetic reaches anyway. The comment says so: "the data format loader is
intentionally minimal here ... For now, treat a present path as 'run the deterministic model
anyway'". [VERIFIED: `CortexReFITBench/main.swift:466-474`]

The output therefore names a real session while every number in it is synthetic. That is the exact
defect RD-09 exists to remove, sitting inside the harness RD-07 is supposed to use. Either implement
the loader or delete the env hook; leaving it as-is while the phase publishes real-data claims is
the worst of the three options.

### Pitfall 8: `SessionLoad` is a frozen dataclass

Adding a `target_mm` field to `ndt1.sessions.SessionLoad` changes a frozen dataclass's constructor.
Every construction site must be updated in the same commit. There is exactly one production site
(`available_sessions`) plus whatever the tests build. Give the field a default of `None` only if the
export path checks for it explicitly; a silently-`None` target array is a fabrication risk.

### Pitfall 9: the IPC frame is one bin, not one window

`SampleCodec.encode(tsNs:seq:channels:)` takes `[Float16]` of exactly `channelCount` (96) elements,
so each IPC frame carries **one 20 ms bin across 96 channels**, not a 32-bin window.
[VERIFIED: `SampleCodec.swift:113-116`, `Producer.patternF16` returns
`[Float16](repeating: v, count: channelCount)`]

The D-05 chain therefore needs a consumer-side rolling 32-bin accumulator between the ring and
`SpikeInputBuffer`. That component does not exist. Budget it.

### Pitfall 10: `readme-policy.sh` uses `grep -nF` for tokens

The required-present checks are fixed-string (`-F`) precisely so that metacharacters in a token
such as `max(0` stay literal. Any context-sensitive check D-13 adds needs `grep -nE` and therefore
needs its pattern's metacharacters escaped. The runner is `macos-15` with BSD grep 2.6.0-FreeBSD,
which does honour `\b` in ERE (probed this session), but the safest patterns avoid it.

## Code examples

All snippets below were tested against real inputs this session unless noted.

### D-13: a context-sensitive `24.7` check, in the existing helper style

The requirement has two directions: a retired-context occurrence passes, an achieved-context
occurrence fails. A single line-scoped pairing rule covers both with no false positives, and needs
one new helper.

```bash
# ── require_marker_on_matching_lines: every line matching NEEDLE must ALSO match MARKER.
# ($1=path $2=needle(fixed) $3=marker(fixed) $4=label). A line carrying the needle without the
# marker is the failure; the offending lines are printed so the author sees exactly what to fix.
require_marker_on_matching_lines() {
  local path="$1" needle="$2" marker="$3" label="$4" offenders
  if [[ ! -f "$path" ]]; then
    echo "ERROR [context] $label: file not found: $path" >&2
    return 1
  fi
  offenders="$(grep -nF -- "$needle" "$path" | grep -vF -- "$marker" || true)"
  if [[ -z "$offenders" ]]; then
    echo "  ok  [context] $label  ($path)"
    return 0
  fi
  echo "ERROR [context] $label: '$needle' appears without '$marker' on:" >&2
  printf '%s\n' "$offenders" >&2
  return 1
}
```

Wired in `scan()`:

```bash
  # RETIRED-CONTEXT-ONLY — the photodiode spec target may be NAMED but never CLAIMED (D-13, RD-10).
  require_marker_on_matching_lines "$README_FILE" "24.7" "retired spec target" \
    "retired: 24.7 may appear only as a retired spec target (D-13)" || rc=1
  # Belt and braces: an explicit achievement phrasing next to the number fails even with the marker.
  forbid_regex_in_file "$README_FILE" \
    '24\.7[^|]{0,80}(we measured|was measured|is measured|achieved|verified at)' \
    "no achieved-framing on the retired 24.7 figure (D-13)" || rc=1
```

Tested behaviour (six synthetic lines, `/usr/bin/grep` on this machine):

| Line | Pairing rule | Verdict |
|---|---|---|
| `Glass-to-glass latency 24.7 +/- 1.3 ms -- RETIRED SPEC TARGET, never measured (Future work).` | marker present | pass |
| `The 24.7 ms figure is a RETIRED SPEC TARGET; no photodiode rig was ever built.` | marker present | pass |
| `Glass-to-glass latency 24.7 +/- 1.3 ms (p50, sigma=0.8 ms, n=10k, photodiode-instrumented)` | marker absent | fail |
| `We measured 24.7 ms glass-to-glass on the iPad Pro M4.` | marker absent | fail |
| `Cortex achieves 24.7 ms end to end.` | marker absent | fail |
| `\| latency \| 24.7 ms \| measured \|` | marker absent | fail |

Note on the second rule: a verb-proximity regex alone produces a false positive on the legitimate
phrase "never measured" and misses inflections such as "achieves". The pairing rule is the
load-bearing one; keep the verb rule narrow and closed-set, and do not attempt negation handling in
a regex.

Baseline today: `README.md` carries `24.7` on exactly three lines (18, 91, 150), and all three lack
any retirement marker, so the new rule bites on the current file until the README is rewritten.
[VERIFIED: grep this session]

Self-test additions required by D-13 (both directions, per the existing `assert_exit` idiom):

```bash
  # 1f. A RETIRED-context 24.7 must PASS (the gate must not simply ban the number).
  r="$(mktemp)"; write_clean_readme "$r"
  printf 'Future work: the 24.7 ms figure is a retired spec target, never measured.\n' >> "$r"
  assert_exit 0 "retired-context 24.7 passes" "$r"; rm -f "$r"

  # 1g. An ACHIEVED-context 24.7 must FAIL.
  r="$(mktemp)"; write_clean_readme "$r"
  printf 'We measured 24.7 ms glass-to-glass on the iPad Pro M4.\n' >> "$r"
  assert_exit 1 "achieved-context 24.7 bites" "$r"; rm -f "$r"
```

`write_clean_readme` must be updated in the same commit: it currently emits
`"...next to the v1 target 24.7 ms."` with no marker, which the new rule fails. Add the marker
there, drop the `photodiode` line, and add the D-14 triple.

### D-14: the real-data provenance triple

Three fixed-string requirements, using the existing helper unchanged:

```bash
  # REQUIRED-PRESENT — the real-data provenance triple (D-14, RD-10). A real-data result may not be
  # stated without naming the session it came from, the checkpoint bytes, and its limitation.
  require_fixed_in_file "$README_FILE" "indy_20160630_01" \
    "provenance: replayed session id (D-14)" || rc=1
  require_fixed_in_file "$README_FILE" "9d542cb51d4a" \
    "provenance: real velocity-checkpoint sha256 prefix (D-14)" || rc=1
  require_fixed_in_file "$README_FILE" "open-loop replay" \
    "provenance: open-loop-replay disclosure (D-03/D-14)" || rc=1
```

The 12-hex prefix matches `ndt1.real_checkpoint.SHA_PREFIX_LEN = 12` and the form already used in
`09-decoder-metrics.json` (`"real-data checkpoint ndt1_real_with_velocity.pt sha256=9d542cb51d4a"`),
so the README and the metrics JSON name the same bytes in the same shorthand. [VERIFIED]

Each of the three needs a strip-negative-control in the same commit, taking the nine existing
controls to fourteen (nine existing, two for D-13, three for D-14), plus the clean baseline.

### The removals D-14 mandates

```bash
  # REMOVE: require_fixed_in_file "$README_FILE" "24.7"        (replaced by the context rule above)
  # REMOVE: require_fixed_in_file "$README_FILE" "photodiode"  (retired to Future work, ADR-0003)
  # REMOVE self-test cases 1a (strip photodiode) and 1c (strip 24.7).
```

Everything else in the required set stays: `MLX`, `_ANEClient`, `CocoaPods`, `altool`,
`software-timed pipeline latency`, the free/Personal-team alternative, `ANE-eligible`, `synthetic`,
`entitlement`, `max(0`, `8.5` (subject to the Correction 6 decision), and all four forbidden-absent
regexes.

### The true-cursor ceiling control (pre-register, run before scoring anything)

```python
# Ceiling: replay the animal's OWN recorded cursor through the repo's dwell-to-select rule.
# This is the maximum any decoder can score on this session at this geometry. Pre-registered.
import h5py, numpy as np

with h5py.File("Decoder/data/indy_20160630_01.mat", "r") as f:
    tp = np.asarray(f["target_pos"][()], dtype=np.float64)   # (2, N) mm
    cp = np.asarray(f["cursor_pos"][()], dtype=np.float64)   # (2, N) mm
d = np.linalg.norm(cp - tp, axis=0)
changed = np.any(np.diff(tp, axis=1) != 0.0, axis=0)
bounds = np.r_[0, np.flatnonzero(changed) + 1, tp.shape[1]]

def ceiling(radius_mm: float, dwell_s: float, fs: float = 250.0) -> int:
    need = int(round(dwell_s * fs))
    hits = 0
    for a, b in zip(bounds[:-1], bounds[1:]):
        inside = d[a:b] < radius_mm
        best = run = 0
        for v in inside:
            run = run + 1 if v else 0
            best = max(best, run)
        if best >= need:
            hits += 1
    return hits

# Measured 2026-09-05: ceiling(1.75, 0.30) == 43 out of 1025 trials (4.2%).
```

`cursor_pos` is read here and only here, in the control script, not in `load_session`. D-01 leaves
it unread in the loader and that stays true.

### Asserting the model actually ran

```swift
// RD-08: the real-data run must PROVE NDT1 was in the loop. `decodeWithModel` swallows every
// failure into the synthetic fallback, so a shape mismatch would otherwise pass unnoticed.
var modelBackedTicks = 0
for _ in 0 ..< tickCount {
  let state = pipeline.tick()
  if state.decodedByModel { modelBackedTicks += 1 }
}
precondition(
  modelBackedTicks == tickCount,
  "RD-08: \(tickCount - modelBackedTicks) of \(tickCount) ticks fell back to the synthetic decode. "
    + "The real-data claim requires NDT1 on every tick (check SpikeInputBuffer seqLen == 32)."
)
```

## State of the art

| Old claim in this repo | Current state | Source | Impact |
|---|---|---|---|
| "BrainGate 6x6 (Pandarinath 2017) 4.16 BPS" | 4.16 +/- 0.39 bps is T5 on a **9x9 dense** grid; the 6x6 numbers are T6 2.2 +/- 0.4, T5 3.7 +/- 0.4, T7 1.4 +/- 0.1 | eLife 18554 full text [VERIFIED 2026-09-05] | Mislabel in a Swift constant, a unit test, PERF-01's wording, the spec, ADR-0002 and the README |
| "Neuralink P1 verified peak 8.5 BPS (PRIME study blog, May 2024)" | neuralink.com/webgrid today states "Our clinical trial participants have achieved over 10 BPS". The repo's own source list says 8 BPS, not 8.5 | neuralink.com/webgrid [VERIFIED 2026-09-05]; `docs/cortex-spec.md:313` | Required token in `readme-policy.sh`; see Correction 6 for the three dispositions |
| "Glass-to-glass 24.7 +/- 1.3 ms, photodiode-instrumented" as the defining v1 claim | Retired to Future work 2026-08-28; it was always a spec target | ROADMAP "Future work" and this phase's SC#4 | The whole of RD-10 |
| "226/226 ops ANE-eligible" | 239/239 eligible, 0 CPU-only, re-measured on the trained real-data graph in Phase 9 | `09-decoder-metrics.json` `ane.n_schedulable` [VERIFIED] | Stale in `README.md:37` and `README.md:147`; RD-09 sweep target |
| co-bps 0.3804 on synthetic Poisson | 0.4096 on real spikes against the train-split per-channel mean-rate null | `09-training-evidence.md` [VERIFIED] | README carries no co-bps number at all today; the real-data story must be added, not just corrected |
| ReFIT uplift established (0.374 vs 0.161 Fitts, 1.953 vs 1.292 Webgrid) | Synthetic seed-locked replay only. Willett et al. 2017 reports that intention-estimation methods yield nearly equivalent decoders once gain and smoothing are accounted for | 10-RESEARCH-INPUTS Finding 2 [CITED: DOI 10.1109/TBME.2017.2783358] | Near-zero real-data uplift is the published expectation, not a defect; report `refit - kalman_only` as the attributable delta |
| "These are enforced as CI structural gates" | Zero GitHub Actions runs have ever occurred; the repo has never been pushed | `gh api .../actions/runs` total_count 0 [VERIFIED] | RD-09 sweep target; SC#4 evidence must be a local transcript |

**Deprecated or outdated in-repo:**

- `CORTEX_REFIT_REPLAY_URL` in `CortexReFITBench`: accepted, mislabels the output, changes nothing.
- `fit_kalman_gain.py`'s "Plan-03 hook" comment: `data.py` now surfaces the behavior arrays it says
  are missing, so the comment is stale even before the residual path is written.

## Runtime state inventory

RD-09 is a repo-wide token sweep, which is rename-class work. The categories below answer "after
every prose file is updated, what still carries the old claim?"

| Category | Items found | Action required |
|---|---|---|
| Stored data | None. No database, no vector store, no service holds any of these tokens. `Decoder/data/` holds only the four checksum-pinned `.mat` files, which are inputs and are never edited. [VERIFIED: filesystem] | none |
| Live service config | None. No n8n, Datadog, Tailscale or Cloudflare surface exists for this project. The only external service is GitHub Actions, which has **never run** (0 workflow runs), so no dashboard, badge or cached run carries a stale claim. [VERIFIED: `gh api`] | none, but see Correction 3: the README's "enforced in CI" claim itself needs correcting |
| OS-registered state | None. No launchd plist, no Task Scheduler entry, no pm2 process. `SMAppService` registration is scaffolded but inert under free signing. [VERIFIED: grep and Phase-8 records] | none |
| Secrets and env vars | `CORTEX_MODEL_URL` (model path, unchanged), `CORTEX_REFIT_REPLAY_URL` (see Pitfall 7), `CORTEX_REFIT_DEBUG`. None encodes a retired claim. A new env var for the export path is implementer's discretion under D-07. [VERIFIED: grep] | none for the sweep; one new var to add |
| Build artifacts | Gitignored and stale: `Packages/CortexReFIT/.bench/`, `Packages/CortexDemo/.bench/`, `Packages/CortexDecoder/.bench/` hold bench JSON that embeds the old `metric`/`caveat`/`methodology` strings; `Decoder/checkpoints/*.mlpackage` and `*.mlmodelc` are the Phase-9 outputs. None is committed, so none needs editing, but a stale `.bench/glass_to_glass.json` on the executor's machine will carry the old methodology label and could be transcribed into evidence by mistake. [VERIFIED: `.gitignore:15-27`, filesystem] | delete the `.bench/` directories before the RD-08 evidence run |

Committed files carrying each retired or stale token, as the sweep's work list. Phase artifacts
under `.planning/phases/0*` are historical evidence and per project convention are never
retroactively edited; they receive superseded banners instead.

| Token | Committed files outside `.planning/phases/` |
|---|---|
| `photodiode` | `README.md`, `AGENTS.md`, `docs/cortex-spec.md`, `docs/adr/0001-...md`, `docs/adr/0002-...md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/v1.0-MILESTONE-AUDIT.md`, `.github/workflows/ci.yml`, `Tools/scripts/readme-policy.sh`, `Packages/CortexDemo/Package.swift`, `Packages/CortexDemo/Sources/CortexDemo/GlassToGlassTimer.swift`, `Packages/CortexDemo/Sources/CortexDemoBench/main.swift`, `Packages/CortexDemo/Tests/CortexDemoTests/GlassToGlassTimerTests.swift` |
| `24.7` | the same set minus the three CortexDemo sources, plus nothing new |
| `8.5` | `README.md`, `docs/cortex-spec.md`, `docs/adr/0002-...md`, `.planning/{PROJECT,REQUIREMENTS,ROADMAP}.md`, `.github/workflows/ci.yml`, `Tools/scripts/readme-policy.sh`, `Tools/scripts/check_refit_uplift.py`, `Packages/CortexReFIT/Sources/CortexReFIT/WebgridBPS.swift`, `.../FittsThroughput.swift`, `.../CortexReFITBench/main.swift`, `.../Tests/CortexReFITTests/WebgridBPSTests.swift`, `.../FittsThroughputTests.swift`. Also a false positive in `Decoder/manifests/indy_sessions.json` (a substring of a checksum or size), which must not be edited |
| `4.16` | as for `8.5`, plus `Decoder/tests/test_cobps_margin.py` |
| `226` | `README.md` (lines 37 and 147), `.planning/{PROJECT,REQUIREMENTS,ROADMAP,STATE}.md`, `Decoder/scripts/fit_velocity_real.py`, `Decoder/scripts/rederive_coreml.py`, `Decoder/tests/test_ane_compute_plan.py`, `Tools/scripts/readme-policy.sh` (inside the self-test's synthetic README). In the three Decoder files the 226 is a **deliberately preserved Phase-5 baseline string**, not a live claim; do not sweep those |
| `1.953`, `0.374`, `0.161` | `README.md`, `docs/adr/0002-...md`, `.planning/{PROJECT,ROADMAP,STATE,REQUIREMENTS}.md`, `Tools/scripts/bps-policy.sh` (1.953 only). These stay, relabeled as the synthetic seed-locked numbers they are (D-12) |

`AGENTS.md`'s `## Project` section carries the photodiode core-value statement verbatim and is not
in CONTEXT.md's canonical-refs list. It is auto-managed tooling output, so decide explicitly whether
to edit it or regenerate it, but do not leave it stating a retired claim.

## Environment availability

| Dependency | Required by | Available | Version | Fallback |
|---|---|---|---|---|
| Indy `.mat` sessions | RD-07, RD-08 export | yes | 4 files, 1,767,820,363 B total, checksum-pinned | none needed |
| Real checkpoints | the export sidecar and the model-backed decode | yes | `ndt1_real_pooled.pt`, `ndt1_real_with_velocity.pt` | none needed |
| Shipped `.mlpackage` (real, with velocity) | RD-08 model-backed decode | yes | `ndt1_real_vel_sweep_fp16.mlpackage`, input `(1,96,1,32)`, output `(1,2,1,1)` | ship fp16 per Phase-9 RD-05; the 4-bit variants destroy the velocity decode |
| `uv` + Decoder env | every Python step | yes | `uv sync --project Decoder --extra dev` required first | none |
| `coremltools` | only if re-converting | yes | 9.0, pinned | not needed this phase |
| Xcode 26.3 / Swift 6.2.4 | all Swift work | yes | recorded in `09-decoder-metrics.json` | none |
| Apple M5 Pro host | the RD-08 replay and demo capture | yes | corroborating device label | none |
| iPad Pro M4 | canonical device gates | **no** | not provisioned | D-15 discloses these as v1's boundary; never auto-approve |
| GitHub Actions runner | any "CI green" claim | **never used** | 0 runs | SC#4 evidence is a local `--self-test` transcript |
| Photodiode rig (BPW34, OPA381, Saleae) | LAT-01..08 | **no** | not purchased | retired to Future work; ADR-0003 records the reason |
| SwiftLint / SwiftFormat | the strict gate | installed locally | the `--strict` gate has never executed | out of scope per D-16 |

**Missing dependencies with no fallback:** none blocks this phase. The iPad Pro M4 and the
photodiode rig are both explicitly disclosed boundaries (D-15) rather than blockers.

## Validation Architecture

### Test framework

| Property | Value |
|---|---|
| Swift framework | Swift Testing (`import Testing`, `@Test`/`#expect`), per-package `swift test` |
| Python framework | pytest 8.x, config in `Decoder/pyproject.toml` (`testpaths = ["tests"]`, marker `slow`) |
| Env bootstrap (REQUIRED first) | `uv sync --project Decoder --extra dev` |
| Quick Python run | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` (~15-30 s, no dataset) |
| Full Python run | `uv run --project Decoder pytest Decoder/tests -q` |
| Quick Swift run | `swift test --package-path Packages/CortexReFIT` and `swift test --package-path Packages/CortexDemo` |
| Gate scripts | `Tools/scripts/{readme,bps,decoder}-policy.sh`, each with `--self-test`; `Tools/scripts/check_refit_uplift.py` |
| CI jobs | `build-and-lint` (macos-15) and `decoder-python` (macos-15), both blocking, both triggered on push and pull_request to `main` |

**Tier split (Phase 9 D-21, carried forward unchanged and reinforced by D-07).** CI gates
correctness, structure and provenance. CI never trains, never downloads the dataset, never reads
the D-06 export, and never asserts a measured number against a bar. Every automated command below
runs green on a checkout with an empty `Decoder/data/` and no export present. `ci.yml` already
proves this actively with the "Prove the quick suite needs no dataset" step.

**Standing caveat, new this phase.** The CI workflow has never executed (Correction 3). Every
"CI-blocking" row below describes where the assertion is wired, not a run that has happened. Phase
evidence must record locally-captured transcripts.

### Phase success criteria to assertion map

| SC | Behavior that must be true | Tier | Automated assertion the planner turns into a task | Negative control that proves it bites |
|---|---|---|---|---|
| **SC#1a** | Kalman gains were fit from real residuals, not defaults | CI-blocking (structural) | New test asserting `KalmanConstants.swift`'s provenance header contains `noise source = indy-heldout` and does **not** contain `noise source = default`; extend `KalmanConstantsTests` | Point `fit_kalman_gain.py` at an absent `--data-dir`, regenerate, confirm the test fails |
| **SC#1b** | The re-fit gain is Schur-stable and keeps zero position rows | CI-blocking | Existing `KalmanConstantsTests` structural invariants, unchanged; `steady_state_gain` already raises on a non-stabilizing solve | Existing Phase-7 control retained |
| **SC#1c** | The four-arm ablation ran on real spikes and its numbers are traceable | CI-blocking (schema only) | New `Tools/scripts/refit-real-policy.sh` plus a Python set-comparison leg, mirroring `decoder-policy.sh`: assert the real-data artifact declares `data_source: "real"`, a `session_id`, a 64-hex `source_sha256` agreeing with `indy_sessions.json`, four named arms, and the open-loop disclosure string. **Assert nothing about the sign or magnitude of any delta (D-09)** | `--self-test`: (0) clean stand-in pair passes; (1) strip `data_source` -> exit 1; (2) perturb one checksum, still 64 hex -> exit 1; (3) drop the fourth arm -> exit 1; (4) strip the disclosure -> exit 1 |
| **SC#1d** | Gain and smoothing are reported per arm (Willett confound) | CI-blocking (schema) | The real-data schema test asserts each of the four arms carries `realized_gain` and a smoothing statistic | Remove one arm's `realized_gain`; the schema test must fail |
| **SC#1e** | The synthetic Phase-7 invariant still guards the filter code | CI-blocking | Unchanged: `ci.yml` byte-diff of `refit_bps.json` after `CortexReFITBench --smoke`, plus `python3 Tools/scripts/check_refit_uplift.py` | Existing Phase-7 control retained; the new work must not perturb the bytes (Pitfall 6) |
| **SC#1f** | The honest gap to 4.16 and 8.5 is stated with each reference's condition | CI-blocking (token) | `readme-policy.sh` keeps requiring `8.5`; add a required token naming the 4.16 condition once Correction 5 is resolved | Strip the token; the self-test must fail |
| **SC#1g** | The measured real-data ablation numbers | **evidence, human-run** | `swift run --package-path Packages/CortexReFIT <real-arm flag> <export path>` with the export materialized; numbers transcribed into `10-refit-real-evidence.md` and the metrics JSON | n/a (measurement) |
| **SC#2a** | NDT1 was genuinely in the loop on every real-data tick | CI-blocking (structural) + evidence | Structural: a `CortexDemo` test asserting the pipeline derives `SpikeInputBuffer.seqLen` from the model input rather than from the source's default. Evidence: `ticks_model_backed == ticks_total` recorded in the RD-08 JSON | Construct a pipeline with `numBins == 8` against a 32-bin model and assert the run reports fallback ticks rather than passing silently |
| **SC#2b** | A 30x30 webgrid hit is demonstrated on the real-data path | **evidence, human-run** | The replay run's hit count, reported **alongside the pre-registered true-cursor ceiling** (43/1025 at r = 1.75 mm, dwell 0.30 s) | The ceiling script itself is the control: it must be committed and its number published before the decoded run is scored |
| **SC#2c** | The hit-independent proxy exists so a zero is interpretable (D-11) | CI-blocking (schema) | The RD-08 schema test asserts the artifact carries a cursor-to-target distance series or its summary percentiles | Remove the key; the schema test must fail |
| **SC#2d** | Seam A p99 is like-for-like with Phase 8 | **evidence, human-run** | `swift run --package-path Packages/CortexDemo CortexDemoBench --full` with the real export and the real model wired, same modelled-present arithmetic; report beside 8.3 ms | n/a (measurement); the like-for-like claim is validated by the seam being unchanged, which is a code-review assertion |
| **SC#2e** | Seam B (daemon -> IPC -> consumer -> decode) runs end to end | CI-blocking (smoke) + evidence | A headless smoke that runs the daemon producer and the new consumer over a short export slice and asserts every frame decrypts, decodes and lands in the rolling window in order. Skips cleanly with exit 0 when the export is absent, per the existing bench idiom | Corrupt one frame's tag and assert the consumer fails closed (the Phase-2 AES-GCM tamper test pattern) |
| **SC#2f** | The Seam B latency is not presented as the Phase-8 number | CI-blocking (schema) | The RD-08 artifact carries two separately named seams with a `seam` field on each, and the schema test asserts both are present and distinctly labeled | Collapse the two into one; the schema test must fail |
| **SC#3a** | No committed file presents a synthetic-derived number as a real-data result | CI-blocking (token sweep) | A new `Tools/scripts/honesty-sweep.sh`: for each of `1.953`, `0.374`, `0.161`, `226`, assert every occurrence outside `.planning/phases/` sits on a line that also carries a labeling token (`synthetic`, `superseded`, `Phase-5 baseline`) | `--self-test`: a stand-in file with a bare `1.953` and no label -> exit 1; the same line with `synthetic` -> exit 0 |
| **SC#3b** | Every `*-evidence.md` carries the re-derived number or a superseded banner | CI-blocking | Extend the sweep: every `*-evidence.md` under `.planning/phases/0[4-8]` that names a superseded number must contain a `Superseded` marker | Remove a banner from a stand-in copy; the gate must fail |
| **SC#3c** | The methodology label no longer names a photodiode rig as a scheduled phase | CI-blocking | `GlassToGlassTimerTests` updated in lockstep with the label, asserting the new string verbatim and asserting the prefix `software-timed pipeline latency` is unchanged | Revert the label; the verbatim test must fail |
| **SC#4a** | `readme-policy.sh` no longer requires `photodiode` or `24.7` | CI-blocking | `grep -c 'require_fixed_in_file .*"photodiode"' Tools/scripts/readme-policy.sh` is 0, likewise for the flat `"24.7"` requirement | A stand-in README with neither token must now pass (this is itself the control) |
| **SC#4b** | A retired-context `24.7` passes and an achieved-context `24.7` fails | CI-blocking | `./Tools/scripts/readme-policy.sh --self-test` cases 1f and 1g above | Both directions are the control; the self-test fails if either stops biting |
| **SC#4c** | The provenance triple is required | CI-blocking | Three `require_fixed_in_file` calls plus three strip controls | Strip each of the three in turn from the clean synthetic README; each must exit 1 |
| **SC#4d** | Every pre-existing control still bites | CI-blocking | `./Tools/scripts/readme-policy.sh && ./Tools/scripts/readme-policy.sh --self-test` both exit 0, with the control count risen from 9 to at least 14 | The self-test prints one PASS line per control; count them in the evidence transcript |
| **SC#5a** | LAT-01..LAT-08 are preserved verbatim | CI-blocking | A sweep assertion that all eight `LAT-0N` identifiers appear in `.planning/ROADMAP.md` and `.planning/REQUIREMENTS.md` with their original text | Delete one; the gate must fail |
| **SC#5b** | ADR-0003 exists, follows the format, and is indexed | CI-blocking | Assert `docs/adr/0003-*.md` exists, contains the four required headings (`## Context`, `## Decision`, `## Consequences`, `## Alternatives considered`), a `**Status:**` line, and is linked from `docs/adr/README.md` | Remove the index link; the gate must fail |
| **SC#5c** | The honest-gates table reflects the new boundary | CI-blocking (token) | `readme-policy.sh` keeps requiring `ANE-eligible`, `synthetic`, `entitlement` and the free-team phrase, and gains the D-14 triple; the table rows are prose the tokens pin | Existing strip controls plus the three new ones |

### What CANNOT be automated in CI, and why

CI never touches the dataset (D-07, D-21), so every row below is human-run runbook evidence, not a
gate. This is the tier split working as designed, not a coverage gap.

| Behavior | SC | Why it cannot be a CI gate | Runbook |
|---|---|---|---|
| The Kalman R fit from real residuals | SC#1 | Needs the 1.77 GB dataset and an encoder forward pass | `uv sync --project Decoder --extra dev`; materialize the data; run the fit; commit the regenerated `KalmanConstants.swift` and the residual statistics into `10-refit-real-evidence.md` |
| Every real-data ablation number | SC#1 | Needs the export; and D-09 forbids asserting the direction of the result anywhere | Run the four arms, transcribe into the evidence artifact and the metrics JSON |
| The true-cursor ceiling | SC#2 | Reads `Decoder/data/*.mat` directly | Run the committed ceiling script, commit its output **before** the decoded run |
| The webgrid hit demonstration and the recorded capture (D-16) | SC#2 | Needs a GUI session on the M5 Pro and a free-team GUI signing path | Run CortexMac from Xcode with `MTL_HUD_ENABLED=1`, capture the recording, store it as RD-08 evidence |
| Seam A and Seam B p99 | SC#2 | Latency values are never asserted against a bar in CI (the Phase-8 smoke asserts only that the bench runs) | `CortexDemoBench --full` with the export and model wired; device-annotate as corroborating |
| iPad Pro M4 canonical captures | SC#5 | Hardware absent | `10-HUMAN-UAT.md`, never auto-approved, all value fields `not measured` (the `09-HUMAN-UAT.md` template) |
| "CI is green" | all | The workflow has never run (Correction 3) | Capture local transcripts of every gate and its `--self-test`; state in the README that the workflow has not yet executed on a runner |

### Sampling rate

- **Per task commit:** `uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q`, plus `swift test --package-path Packages/CortexReFIT` when Swift changed.
- **Per wave merge:** the quick Python suite, `swift test` on CortexReFIT / CortexDemo / CortexDecoder, and every policy gate with its `--self-test`: `./Tools/scripts/readme-policy.sh && ./Tools/scripts/readme-policy.sh --self-test && ./Tools/scripts/bps-policy.sh && ./Tools/scripts/bps-policy.sh --self-test && ./Tools/scripts/decoder-policy.sh && ./Tools/scripts/decoder-policy.sh --self-test`.
- **Phase gate:** all of the above green, the byte-identity check on `refit_bps.json` still passing, every evidence artifact committed with its runbook and device label, ADR-0003 written and indexed, then `/donny-verify-work`.
- **Max feedback latency:** ~30 s for the Python quick suite; ~2-4 minutes for the Swift packages plus gates.

### Wave 0 gaps

Test infrastructure exists on both sides. The gaps are fixtures, gates and one missing seam.

- [ ] `Tools/scripts/refit-real-policy.sh` plus its `--self-test`, structurally copied from `decoder-policy.sh`, with a bare-`python3` set-comparison helper. Covers SC#1c, SC#1d.
- [ ] `Tools/scripts/honesty-sweep.sh` plus its `--self-test`. Covers SC#3a, SC#3b, SC#5a, SC#5b.
- [ ] `Decoder/tests/test_real_replay_schema.py`, copying `test_metrics_schema.py`'s guard-split-marker self-check verbatim so the new module also cannot grow a measured-value assertion. Covers SC#1d, SC#2c, SC#2f.
- [ ] A committed **synthetic** export fixture (a few hundred bins, correct dtypes and sidecar) so the Swift reader and the schema test are exercisable on a clean clone with no dataset. This is the D-20 `tiny_v73.mat` pattern applied to the export. Without it, every export-touching test is dataset-gated and CI covers none of it.
- [ ] The rolling 32-bin window accumulator between the IPC consumer and `SpikeInputBuffer` (Pitfall 9), with its own unit test.
- [ ] `readme-policy.sh`'s new `require_marker_on_matching_lines` helper plus five new self-test cases, and an updated `write_clean_readme`.
- [ ] Three new CI steps in `ci.yml`: the real-data provenance gate, the honesty sweep, and the Seam B smoke. Each with its `--self-test` alongside, matching the existing seven policy-gate steps.
- [ ] `10-HUMAN-UAT.md` from the `09-HUMAN-UAT.md` template, for the iPad-M4 rows carried forward.

## Security domain

`security_enforcement` is not set to false in `.planning/config.json`, so this section applies.
The phase adds one new file-reading path and one new IPC producer path.

### Applicable ASVS categories

| ASVS category | Applies | Standard control in this repo |
|---|---|---|
| V2 Authentication | no | single-user, on-device, no accounts |
| V3 Session management | no | no sessions |
| V4 Access control | no | no multi-user surface |
| V5 Input validation | **yes** | The export reader is a new parser of an attacker-influenceable-in-principle file. Validate the sidecar's declared shapes against the binary's actual byte length before any read, reject a mismatch, and never trust `n_bins` to size an allocation without bounding it. This is the `SampleCodec` discipline (explicit `badChannelCount` / `malformedBuffer` errors) applied to a new format |
| V6 Cryptography | **yes** | Unchanged: AES-GCM via CryptoKit with HKDF per-direction subkeys and a deterministic 96-bit sequence nonce. D-11 (discretion) keeps AES-GCM on the real-data path. Do not add a "skip encryption for the replay" option; a second code path is how a fail-open appears |
| V12 File and resource | **yes** | The export is gitignored and materialized by script (D-07). The reader must not follow symlinks out of the expected directory and must fail closed when the file is absent rather than substituting synthetic data silently |
| V14 Configuration | **yes** | A new env var selecting the export path is a config surface; treat an absent or empty value as "skip cleanly", never as "fall back to synthetic and report it as real" |

### Known threat patterns for this stack

| Pattern | STRIDE | Mitigation |
|---|---|---|
| A malformed or truncated export sizes an allocation from an untrusted header | Denial of service | Bound `n_bins * n_channels * itemsize` against the file's actual size before allocating; raise on mismatch |
| The replay silently falls back to synthetic data and the number is published as real | Repudiation / Information disclosure (of a false claim) | The `decodedByModel` tick count assertion (Pattern 2) and the `data_source` provenance leg in the new gate |
| The export's sidecar names a session whose bytes were never verified | Tampering | The sidecar's `source_sha256` must agree with `indy_sessions.json`, checked by the Python set-comparison leg, exactly as `check_decoder_provenance.py` does for the metrics |
| A gate is weakened without its self-test changing | Tampering | Every added check ships its negative control in the same commit; the self-test's PASS-line count is recorded in the evidence transcript |
| The dataset or the export leaks into git | Information disclosure (CC-BY redistribution) | `.gitignore` covers `Decoder/data/`; add the export path. `ci.yml`'s "Prove the quick suite needs no dataset" step should be extended to assert the export directory is empty on a CI checkout |
| Reading `wf` or `cursor_pos` into memory | Denial of service | T-04-02-02 already forbids `wf`; D-01 keeps `cursor_pos` out of `load_session`. The ceiling script reads `cursor_pos` once, outside the loader, and is not on any hot path |

## Assumptions log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | The export can reuse the shipped fp16 `.mlpackage` unchanged; no re-conversion is needed | Standard stack, Environment availability | If the real replay needs a different `seq_len` or a different palettization, a conversion step appears that this phase did not budget. Mitigated by the verified `(1,96,1,32)` input shape |
| A2 | The residual for the R fit should be computed on the held-out split at the locked lag of 1 bin and lambda 0.1 | Correction 1, Open Question 3 | A residual computed in-sample or at a different lag gives a different R and therefore a different gain. Pre-register the choice before running |
| A3 | Adding a `target_mm` field to `SessionLoad` has exactly one production construction site | Pitfall 8 | A missed site is a `TypeError` at import, which is loud rather than silent, so the risk is schedule not correctness |
| A4 | Time reversal is a stronger D-04 control than shuffling because it preserves the target track's autocorrelation | Architecture pattern 3 | If reviewers prefer shuffling, running both is cheap; discretion already allows either or both |
| A5 | The `8.5` false positive in `Decoder/manifests/indy_sessions.json` is a checksum or size substring, not a claim | Runtime state inventory | If it were a claim it would need sweeping; a one-line grep at plan time settles it |
| A6 | Deleting the local `.bench/` directories before the evidence run is sufficient to avoid transcribing a stale methodology label | Runtime state inventory | A stale value transcribed into evidence would be an honesty defect; the mitigation is cheap and the artifacts are gitignored |

## Open questions

1. **Which disposition for the `8.5` reference (Correction 6)?**
   - What we know: `readme-policy.sh:148` requires the literal `8.5`; D-14 keeps every other current
     required token; the repo's own source list says 8, not 8.5; neuralink.com/webgrid today says
     "over 10 BPS"; the 9.51 figure from the research inputs is not on the page now.
   - What is unclear: whether the project wants to keep a precise-looking number that it cannot
     source, or replace it with a sourced but vaguer one.
   - Recommendation: disposition 1 (keep `8.5`, date and source it, state the current public
     figure beside it) as the default, because it keeps the gate untouched and makes the staleness
     visible. Resolve the internal 8-versus-8.5 contradiction in `docs/cortex-spec.md` either way.

2. **Does the real-data headline BPS use N = 900 or N = 64?**
   - What we know: the task presented 64 distinct targets (6.0 bits); `WebgridBPS` normalises by
     `log2(900) = 9.81` bits; `bitsPerSecond` already takes `n` as a parameter.
   - What is unclear: whether D-02's locked 30x30 re-grid also fixes the normalisation, or only the
     geometry.
   - Recommendation: report both, headline the N = 900 number for continuity with 1.953 (D-12 makes
     the before-and-after load-bearing), and state the N = 64 number immediately beside it as the
     task-faithful figure. Costs one extra call.

3. **What exactly is the R residual, in what units?**
   - What we know: the decoded velocity is cm/s from the readout, the cursor and target frame is mm,
     the conversion is a verified x10, and the Kalman operates in grid-units per second in
     `[0,1]` space in the Swift harness. The committed default `R = diag(0.25)` was described as
     "(grid-units/s)^2".
   - What is unclear: whether the fit should produce R in grid-units (requiring the workspace
     normalisation to be applied to the residual first) or in cm/s with the normalisation applied
     later. The two differ by the square of the normalisation constant, which is large.
   - Recommendation: fit R in the same units the filter runs in, that is normalise the residual to
     grid-units per second using the D-06 workspace mapping before taking the covariance, and record
     the normalisation constant in the generated file's provenance header so the number is
     reproducible. Pre-register this before the run.

4. **Does the phase push `main`?**
   - What we know: the repo has never been pushed, `swiftlint --strict` sits at roughly 535
     repo-root violations, and D-16 puts the SwiftLint sweep and the first pull request out of scope.
   - What is unclear: whether "v1 launch" implies making the repository visible, which requires a
     push, which arms the strict gate.
   - Recommendation: treat v1 as declarable without a push, disclose in the README that the workflow
     has not executed, and leave the push with the deferred SwiftLint sweep.

5. **Where does the shuffled-target arm's target come from?**
   - What we know: D-04 leaves shuffle-versus-reversal to discretion; the scoring target must stay
     true or the control is vacuous.
   - What is unclear: whether the shuffled arm should be scored on hits at all, or only on the
     rotation's effect on trajectory.
   - Recommendation: score it identically to the other three arms against the true target, so the
     four numbers are directly comparable, and report the rotation-target source as a field on each
     arm in the artifact.

6. **Which offline-versus-closed-loop citations survive verification?**
   - What we know: 10-RESEARCH-INPUTS Finding 4 lists four candidate sources and explicitly marks
     them unverified against their primary text.
   - What is unclear: their exact claims. This researcher verified eLife 18554 and neuralink.com
     but did not open the four Finding-4 candidates.
   - Recommendation: the D-11 decomposition does not need them. The Willett 2017 result (verified
     in the inputs pass via PubMed) already supplies the honest framing for a near-zero uplift.
     Cite a Finding-4 source only after opening its primary text.

## Sources

### Primary (HIGH confidence)

- This repository, read directly on 2026-09-05: `Tools/scripts/readme-policy.sh`,
  `Tools/scripts/decoder-policy.sh`, `Tools/scripts/bps-policy.sh`,
  `Tools/scripts/check_refit_uplift.py`, `Tools/scripts/check_decoder_provenance.py`,
  `Decoder/scripts/fit_kalman_gain.py`, `Decoder/src/ndt1/{data,kinematics,sessions,kalman_gain}.py`,
  `Decoder/tests/test_metrics_schema.py`, `Packages/CortexDemo/**`, `Packages/CortexReFIT/**`,
  `Packages/CortexDecoder/Sources/CortexDecoder/{NeuralDecoder,ZeroCopyInput}.swift`,
  `Apps/CortexDaemon/Producer.swift`, `.github/workflows/ci.yml`, `README.md`, `project.yml`,
  `docs/cortex-spec.md`, `docs/adr/README.md`, `.planning/**`
- `Decoder/data/indy_*.mat`, inspected with h5py and analysed with numpy on 2026-09-05 (the target
  grid, the trial segmentation, the frame relation, the speed distribution, and the true-cursor
  ceiling table)
- `Decoder/checkpoints/ndt1_real_vel_*.mlpackage`, input and output shapes read via coremltools 9.0
- Pandarinath et al. 2017, "High performance communication by people with paralysis using an
  intracortical brain-computer interface", eLife 18554, https://elifesciences.org/articles/18554,
  full text retrieved 2026-09-05 (the 4.16 / 9x9 correction and the 6x6 per-participant figures)
- Neuralink, "Play Webgrid", https://neuralink.com/webgrid/, retrieved 2026-09-05 (the "over 10 BPS"
  statement, the NTPM / grid size / click types scoring description, the 35x35 default grid)
- `gh api repos/D0NMEGA/Cortex/actions/runs` on 2026-09-05, total_count 0

### Secondary (MEDIUM confidence)

- `.planning/phases/10-v1-real-data-closed-loop-launch/10-RESEARCH-INPUTS.md`, the main-thread pass.
  Finding 2 (Willett et al. 2017, DOI 10.1109/TBME.2017.2783358, PMID 29989927) is carried forward
  as cited; its abstract-level claims were not independently re-fetched this session.
- `.planning/phases/09-*/09-{training,velocity,coreml,ingest}-evidence.md` and
  `09-decoder-metrics.json`, treated as this project's own committed measurements.

### Tertiary (LOW confidence, flagged)

- The 9.51 BPS figure attributed to neuralink.com/webgrid in 10-RESEARCH-INPUTS Finding 1. Not
  present on the page as of 2026-09-05. Do not cite.
- The four offline-versus-closed-loop candidate sources in 10-RESEARCH-INPUTS Finding 4. Not opened
  this session; explicitly marked unverified there and still unverified here.

## Metadata

**Confidence breakdown:**

- Repo-internal facts (gate structure, seams, dependencies, shapes, CI state): HIGH. Every claim was
  read from the file or produced by running the command, and the commands are reproduced inline.
- Dataset facts (target grid, trial counts, frame relation, speed, ceiling): HIGH. Computed this
  session from the checksum-pinned files with the repo's own loader where one exists.
- External benchmark corrections: HIGH. Both were read from the primary source, and the eLife
  passages are quoted verbatim.
- The Willett 2017 confound framing: MEDIUM. Carried from the inputs pass at abstract level, not
  re-fetched. It does not gate any decision; it shapes what the ablation must report.
- Unit and normalisation questions for the R fit: MEDIUM. The mechanism is clear, the convention is
  a choice the planner must pre-register (Open Question 3).

**Research date:** 2026-09-05
**Valid until:** 2026-10-05 for the repo-internal findings (they change only when the repo does);
the neuralink.com figure should be re-checked at the moment it is cited, since the page changed
between the inputs pass and this one.
