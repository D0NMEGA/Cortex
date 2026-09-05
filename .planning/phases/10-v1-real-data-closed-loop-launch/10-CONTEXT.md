# Phase 10: v1 Real-Data Closed Loop & Launch - Context

**Gathered:** 2026-09-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Requirements RD-07 through RD-10, the v1 milestone. ReFIT-Kalman gains are re-fit on real Indy
data and the ablation is re-run on real spikes with the honest gap to 4.16 and 8.5 BPS stated;
the pipeline replays a real recorded session end to end through daemon -> IPC -> decoder ->
ReFIT-Kalman -> 120Hz renderer -> BCI HID, with the software-timed glass-to-glass p99 re-derived
on that path; a repo-wide sweep leaves no synthetic-derived number presented as a real-data
result; `readme-policy.sh` is rewritten (not deleted) and the photodiode claim is retired to
Future work in an ADR with LAT-01..LAT-08 preserved verbatim.

Explicitly NOT this phase: NDT2 session-conditioning to repair Phase 9's negative leave-one-
session-out transfer, a live-human two-stage ReFIT retrain, the photodiode rig itself, any new
decoder training, and closing the deferred iPad Pro M4 device gates.

**Amended 2026-09-05 (D-18):** the repo-wide SwiftLint `--strict` sweep and the first push/PR were
originally listed here as out of scope. They are now **in scope**.

</domain>

<decisions>
## Implementation Decisions

### Real-session replay contract (RD-07, RD-08)

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

### Spike path into Swift (RD-08)

- **D-05:** The real spike stream goes through the full chain. `CortexDaemon` reads the exported
  real bins instead of generating synthetic spikes; IPC, decoder, ReFIT, renderer and HID are
  unchanged. ~~This is the only version where the re-derived glass-to-glass p99 is like-for-like
  with the Phase-8 number, which included the IPC leg.~~
  **FACTUALLY WRONG - struck 2026-09-05, verified twice (10-RESEARCH.md Correction 2, confirmed
  independently by an external Codex audit).** The Phase-8 number did **not** include an IPC leg
  and did **not** run the model: `Packages/CortexDemo/Package.swift` has no `CortexIPC` dependency,
  no app-side ring consumer exists, and `CortexDemoBench/main.swift:90` builds
  `ClosedLoopPipeline(seed:)` with no model URL against an arithmetically modelled present
  timestamp (`:112-115`). There is therefore **no** single version that is like-for-like with
  Phase 8. Plan against the Seam A / Seam B split instead: Seam A reproduces the Phase-8 geometry
  with one variable changed, Seam B is the full D-05 chain, and the two are separately labeled and
  never presented as the same measurement.
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

### Ablation and reporting bar (RD-07)

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

### README republish and gate rewrite (RD-09, RD-10)

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
  evidence that a webgrid hit was demonstrated. ~~Opening the first pull request is out of scope:
  it arms SwiftLint `--strict` for the first time in the project's history (around 535 repo-root
  violations today) and that is separate work, not a credibility-phase concern.~~
  **SUPERSEDED 2026-09-05 by D-18** on the pull-request half; the demo-capture half stands.

### Decisions added 2026-09-05 (post-research, user-resolved)

Added after `10-RESEARCH.md` surfaced six verified corrections to this file's premises. These two
were escalated to the user because each changes the deliverable rather than its implementation.

- **D-17:** The `8.5` Neuralink P1 reference is **kept**, but dated and sourced everywhere it
  appears, with the current public wording ("over 10 BPS", neuralink.com/webgrid, verified live
  2026-09-05) stated beside it. `readme-policy.sh`'s required `8.5` token is therefore unchanged.
  `docs/cortex-spec.md`'s internal contradiction must be resolved in the same sweep: `:54` and
  `:172` say 8.5 verified while `:313` says 8 verified, from the same cited source. Research
  Correction 6 established that 8.5 is not sourceable to a Neuralink primary as a "verified peak",
  and that the 9.51 figure carried by the research-inputs pass is **not** on the page and must not
  be adopted. Rejected: re-pointing to the sourced May-2024 figure of 8, and publishing a dated
  range - both were offered; the project chose to keep continuity and make the staleness visible.

- **D-18:** **Phase 10 pushes `main`.** This reverses D-16's deferral of the first pull request.
  The repo has never been pushed - `gh api .../actions/runs` returns `total_count: 0` and
  `origin/main` is not a known revision - so "v1 launch" currently means nothing is public and no
  gate has ever executed on a runner. Pushing arms SwiftLint `--strict` for the first time at
  roughly 535 repo-root violations, including 67 in Phase-7 code that is currently labeled green.
  **That sweep is therefore in scope for this phase**, not deferred. The user was shown this cost
  explicitly and chose it over both the no-push option and the push-with-lint-soft-failed option.
  Consequence for planning: the phase gains a lint-remediation workstream and a push/PR step, and
  the "CI has never run" disclosure (Research Correction 3) may become obsolete during the phase -
  the README wording must be written to match whichever state is true at the end.

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

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

ROADMAP.md carries no `Canonical refs:` line for this phase. The list below was accumulated from
REQUIREMENTS.md, PROJECT.md, the Phase 9 handoff, and the codebase scout during this discussion.

### Phase requirements and scope
- `.planning/ROADMAP.md` (Phase 10 section) - goal statement, RD-07..RD-10, the five success
  criteria; and the "Future work (retired from v1)" section holding LAT-01..LAT-08 verbatim plus
  the standing honesty constraint that 24.7 ms was always a spec target, never a measurement
- `.planning/REQUIREMENTS.md` - RD-07..RD-10, the retired LAT block, PERF-01..PERF-04
- `.planning/PROJECT.md` - the 2026-08-28 core-value re-point and the Key Decisions table

### Phase 9 inputs (the real-data foundation this phase consumes)
- `.planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-CONTEXT.md` - D-01..D-25,
  especially D-05 (the `finger_pos` loader contract this phase extends), D-17 (device
  discipline), D-21 (the CI tier split), D-24 (citation-sweep scope, which explicitly left README
  and ADR-0002 for RD-09), D-25 (a low honest number completes the phase)
- `.planning/phases/09-.../09-VERIFICATION.md` - 5/5 criteria verified, status PARTIAL /
  human_needed, and the deferred canonical iPad-M4 gate this phase inherits as a disclosed boundary
- `.planning/phases/09-.../09-training-evidence.md` - co-bps 0.4096, and the leave-one-session-out
  result showing the encoder does not transfer to an unseen session
- `.planning/phases/09-.../09-velocity-evidence.md` - pooled held-out R2 0.4238, locked lag 1 bin
  (20 ms), locked ridge lambda 0.1; the velocity readout the closed loop actually drives
- `.planning/phases/09-.../09-coreml-evidence.md` - 239/239 ANE-eligible, 0 CPU-only; the ship-fp16
  recommendation and the 4-bit velocity-decode collapse
- `.planning/phases/09-.../09-decoder-metrics.json` - the provenance-bearing metrics schema the
  real-data artifact should mirror, including the `superseded_*` block convention
- `.planning/phases/09-.../09-HUMAN-UAT.md` - the never-auto-approve device-gate template
- `.planning/phases/09-.../09-ingest-evidence.md` - the four pinned sessions and their checksums

### ReFIT re-fit and the closed loop (RD-07, RD-08)
- `.planning/phases/07-refit-kalman-closed-loop-recalibration/07-RESEARCH.md` - the observability
  resolution (section 2.3), the Q/R fitting recipe (section 3.2), the three-arm ablation design
  (section 4.1), and the dwell, timeout and acquisition-radius defaults (section 4.4)
- `.planning/phases/07-.../07-CONTEXT.md`, `07-bps-evidence.md`, `refit_bps.json` - the ablation
  contract and the synthetic baseline being superseded
- `Decoder/scripts/fit_kalman_gain.py` - emits the Swift constants. **Its `--data-dir`
  real-residual path is a no-op** (both `fit_noise` branches return `default_noise`); implementing
  it is RD-07 work, not a re-run. See the struck Reusable-Assets entry below.
- `Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift` - the generated target; the
  header forbids hand-editing the literals and `KalmanConstantsTests` enforces it
- `Packages/CortexReFIT/Sources/CortexReFITBench/main.swift` - the deterministic three-arm ablation
  harness and the SC#3 filter-step latency mode
- `Packages/CortexReFIT/Sources/CortexReFIT/` - `KalmanFilter.swift`, `IntentRotation.swift`,
  `WebgridBPS.swift`, `FittsThroughput.swift`, `WebgridAcquisition.swift`
- `Packages/CortexDemo/Sources/CortexDemo/ClosedLoopPipeline.swift` - the assembly whose
  `SyntheticSpikeSource` stage the real export replaces
- `Packages/CortexDemo/Sources/CortexDemo/GlassToGlassTimer.swift` - the software-timed measurement
  using `targetPresentationTimestamp`, and the verbatim D-07 honesty label
- `Packages/CortexDemo/Sources/CortexDemoBench/main.swift` - the headless latency bench whose number
  RD-08 re-derives
- `Apps/CortexDaemon/` - the producer re-pointed at the export (D-05)
- `Decoder/src/ndt1/data.py` - the loader contract D-01 extends; the documented "only `spikes`,
  `t`, `finger_pos`, `chan_names` are read" note is what changes
- `Decoder/src/ndt1/kinematics.py`, `Decoder/src/ndt1/sessions.py` - velocity derivation, lag
  application, and the session/split layer the export reuses

### Gates to rewrite or preserve (RD-09, RD-10)
- `Tools/scripts/readme-policy.sh` - the RD-10 rewrite target: the required-present set
  (`MLX`, `_ANEClient`, `CocoaPods`, `altool`, `software-timed pipeline latency`, `24.7`,
  `ANE-eligible`, `photodiode`, `synthetic`, `entitlement`, `max(0`, `8.5`), the forbidden-absent
  set (PEM header, `MATCH_PASSWORD =`, email, issuer UUID), and the `--self-test` whose nine
  negative controls all currently bite
- `Tools/scripts/bps-policy.sh` - preserve: the clamp, `log2`, formula pin, `n_targets` 900, and
  the run-twice determinism leg on the synthetic fixture
- `Tools/scripts/check_refit_uplift.py` - preserve, synthetic-scoped (D-09)
- `Tools/scripts/decoder-policy.sh` and `Tools/scripts/check_decoder_provenance.py` - the
  provenance-gate idiom the real-data gate mirrors
- `Tools/scripts/validate-privacy-manifest.sh` - the original negative-control idiom every gate
  in this repo follows
- `.github/workflows/ci.yml` - where the gates are wired; the README gate step is near line 286
  and the BPS gate near line 394; the `decoder-python` job is the Phase-9 addition

### README and ADRs (RD-09, RD-10)
- `README.md` - the sweep target. Sections that carry synthetic or photodiode numbers: "Core
  value" (lines 14-27), "Latency claim - software-timed v0, photodiode v1" (lines 65-97),
  "Webgrid information-rate BPS" (lines 99-134), and the "Honest gates" table (lines 136-152)
- `docs/adr/0001-foundation-and-2026-toolchain.md` - the ADR format precedent (Context, Decision,
  Consequences, Alternatives considered; sequential numbering)
- `docs/adr/0002-v0-ship-and-bci-hid-integration.md` - carries ReFIT-side numbers that RD-09
  sweeps; Phase 9's D-24 explicitly deferred it to this phase
- `docs/adr/README.md` - the ADR index the retirement ADR is added to
- `docs/cortex-spec.md` - section 10 (Sprint Timeline) the roadmap derives from, and the source of
  the canonical 24.7 ms target line

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- ~~`Decoder/scripts/fit_kalman_gain.py`: already implements the RD-07 re-fit ... so the re-fit is
  a re-run plus a residual source, not new machinery.~~
  **FACTUALLY WRONG - struck 2026-09-05, verified twice (Correction 1, confirmed by the Codex
  audit).** Both branches of its `fit_noise` return `default_noise(seed)` (`:177`, `:189`). The
  advertised `--data-dir` real-residual path is a **no-op**: the script cannot fit from data today
  and never has. Its header claim and the `KalmanConstants.swift` "fell back to defaults" note
  together create a false impression that only the data was missing. **RD-07's re-fit is new
  implementation work, not a re-run.** Acceptance: the regenerated header reads
  `noise source = indy-heldout`, never `default`.
- `Packages/CortexReFITBench`: the three-arm ablation already isolates the filter stage on an
  identical replay. Adding D-04's shuffled-target arm is a fourth condition through the same
  harness, not a new harness. **Caveat added 2026-09-05:** the harness makes incorrect selections
  structurally zero (`CortexReFITBench/main.swift:283-285`), so its BPS is not measuring the same
  quantity as a human point-and-click bitrate. See the comparability defects in `10-REVIEWS.md`.
- `Packages/CortexDemo/ClosedLoopPipeline`: already has a decoder-backed path gated on
  `CORTEX_MODEL_URL` with a deterministic synthetic fallback. The real path swaps the source
  stage; the decode, filter, integrate and webgrid stages are untouched.
- `Tools/scripts/decoder-policy.sh` plus `check_decoder_provenance.py`: a working example of a
  gate that ties a published number back to the bytes it came from, with a four-case self-test.
  D-14's provenance triple is the same pattern applied to the README.
- `Decoder/src/ndt1/kinematics.py`: `planar_velocity_250hz`, `bin_velocity`, `apply_lag`,
  `heldout_r2` already produce exactly the paired velocity the D-06 export needs.

### Established Patterns
- Every build-failing gate ships a `--self-test` that proves each check bites. A gate whose
  required set changes without its self-test changing in the same commit is silently disarmed.
- Measured numbers live in committed `*-evidence.md` plus a metrics JSON, produced by a human-run
  runbook with pinned versions and a seed. CI gates structure and correctness only.
- Device annotation is load-bearing: Mac numbers are labeled corroborating, iPad-M4 numbers are
  canonical, and `test_metrics_schema.py` structurally forbids a non-iPad device being labeled
  anything but corroborating.
- Generated files (`KalmanConstants.swift`) carry a do-not-hand-edit header backed by a test.
- Historical evidence artifacts get a superseded banner pointing forward; what they measured is
  never retroactively edited.

### Integration Points
- `Apps/CortexDaemon` producer stage -> the exported real bins (D-05), leaving the encrypt, ring
  and doorbell path unchanged.
- `ndt1.data.load_session` -> a third behavior array, `target_pos` (D-01), which then flows into
  the D-06 export.
- `readme-policy.sh` required and forbidden sets -> the CI step near `ci.yml` line 286.
- The real-data ablation artifact -> a new provenance gate alongside `decoder-policy.sh`, leaving
  `bps-policy.sh` and `check_refit_uplift.py` pointed at the untouched synthetic fixtures.

</code_context>

<specifics>
## Specific Ideas

- The roadmap's own framing is the standard for RD-07: "If ReFIT's uplift does not survive contact
  with real spikes, that is the finding and it gets published as such."
- D-04's shuffled-target arm is deliberately modeled on Phase 9's attribution control, where
  hiding the real checkpoints and re-running the same code reproduced the Phase-4/5 baselines
  exactly, proving the delta was attributable to the weights rather than to tooling drift.
- The v1 artifact is for review by Bliss Chapman and Nir Even-Chen. A reviewer who sees a rotation
  uplift on an open-loop recording will ask what the rotation knew about the target; D-04 answers
  that before it is asked.
- Zero hits is an acceptable published outcome (D-11), but an uninterpretable zero is not. The
  decomposition is what turns a bad number into a finding.

</specifics>

<deferred>
## Deferred Ideas

- NDT2-style session conditioning to repair Phase 9's negative leave-one-session-out transfer.
  Out of scope for v0 and v1; the pooled-across-sessions assumption and its consequences are
  already documented in Phase 9's D-15.
- A live-human two-stage ReFIT retrain on real electrode data. Out of scope per Phase 8 D-12 and
  restated in the README's honest-gates table.
- The photodiode rig and the 10,000-trial campaign (LAT-01..LAT-08). Already preserved verbatim in
  ROADMAP "Future work"; this phase records why they were retired, it does not schedule them.
- ~~A repo-wide SwiftLint `--strict` sweep and the first pull request.~~ **NO LONGER DEFERRED -
  pulled into scope 2026-09-05 by D-18.** The strict gate has never executed because every phase
  went direct to main; it arms on the first push/PR at roughly 535 repo-root violations.
- Closing the deferred iPad Pro M4 device gates: the Phase-8 canonical latency, live TestFlight
  and on-device HID registration gates, plus Phase 9's canonical decoder p99. Disclosed as v1's
  boundary rather than closed (D-15).

### Reviewed Todos (not folded)

None. `todo match-phase 10` returned zero matches.

</deferred>

---

*Phase: 10-v1-real-data-closed-loop-launch*
*Context gathered: 2026-09-05*
