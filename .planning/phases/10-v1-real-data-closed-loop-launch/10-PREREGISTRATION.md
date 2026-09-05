---
phase: 10
status: registered
registered: 2026-09-05
amended: 2026-09-05 (section 3a supersedes one line of section 3; no published number changed)
supersedes: none
rule: "No section below may be edited after a number it governs has been measured. A convention chosen after seeing the result is not a convention."
---

# Phase 10 pre-registration: the measurement contract

This document fixes every measurement convention Phase 10 uses, in writing, before any number
exists to be influenced by it. Every later plan in this phase cites this file.

**The rule, restated so it cannot be missed:** no section below may be edited after a number it
governs has been measured. A convention chosen after seeing the result is not a convention. If a
convention turns out to be wrong, the correct move is a new dated section that supersedes the old
one and states what changed and why, leaving the original text intact, exactly as this repo already
treats superseded evidence artifacts.

Registered 2026-09-05, before Plan 10-03 produced any decoded number and before
`Decoder/scripts/fit_kalman_gain.py` was run against real residuals.

## 1. The replayed session

`indy_20160630_01`, sha256 `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8`,
pinned in `Decoder/manifests/indy_sessions.json`. This is the NLB'21 mc_rtt benchmark session, and
CONTEXT D-08 chose it in advance, before any Phase 10 outcome was known, so that the session could
not be selected on its own result.

State the cost of that plainly. Its Phase-9 per-session held-out velocity R2 was **+0.1446**, the
**weakest of the four** sessions. The range across the four was +0.1446 to +0.5069 with a pooled
+0.4238 (`09-decoder-metrics.json`, `velocity.per_session`, null = that session's own train-split
mean velocity per axis). A better-looking session was available and was not taken.

An independent pre-execution re-measurement on 2026-09-05, on a chronological tail split of this
one session (73,161 bins by 96 channels, split at bin 58,529, 14,601 held-out rows, scored against
the train-split mean null using this repo's own `fit_velocity_real._build_design` and
`kinematics.heldout_r2`), gives vx = 0.0671, vy = 0.2653, **pooled = 0.1523**.

`0.1446` and `0.1523` are **not the same number and are not reconciled**. The first is the Phase-9
per-session figure from `09-decoder-metrics.json` `velocity.per_session`, produced by the pooled
Phase-9 split. The second is an independent re-measurement on the chronological tail split
described above. Both are recorded, both are labeled with the method that produced them, and
neither is adjusted toward the other. If an executor's own run produces a third value, that is
recorded too, with its method. A number is not reconciled by tuning.

## 2. Decoder configuration, locked

Locked from Phase 9. Nothing in this list is re-tuned, retrained, re-swept or re-converted in
Phase 10.

| Item | Value |
|---|---|
| Encoder checkpoint | `Decoder/checkpoints/ndt1_real_pooled.pt`, sha256 prefix `f95b257bf247` |
| Velocity checkpoint | `Decoder/checkpoints/ndt1_real_with_velocity.pt`, sha256 prefix `9d542cb51d4a` |
| Shipped CoreML model | `Decoder/checkpoints/ndt1_real_vel_sweep_fp16.mlpackage` |
| Model input | `spikes`, shape `(1, 96, 1, 32)` |
| Model output | shape `(1, 2, 1, 1)` |
| Precision | fp16 ships. Phase-9 RD-05 measured that 4-bit destroys the velocity decode (R2 +0.4239 to -1.7870) |
| `SEQ_LEN` | 32 |
| Lag | 1 bin = 20 ms |
| Ridge lambda | 0.1 |
| Bin width | 20 ms |

No retraining, no re-conversion, and no lag or lambda re-sweep happens in Phase 10.

## 3. The workspace-to-grid mapping

Pre-registered. **The first line of this block was amended on 2026-09-05; read section 3a before
using this section.** The grid box is a square, axis-aligned, derived from the session's own cursor
track:

```
cursor_mm      = the session's recorded cursor_pos track, transposed to (n_samples, 2)
                 (already in millimetres; NOT derived from planar_cm)
bbox           = axis-aligned bounding box of cursor_mm over the whole session
side_mm        = max(bbox.width, bbox.height)
centre_mm      = bbox centre
box            = the side_mm x side_mm square centred on centre_mm
grid           = 30 x 30 over box, so cell_mm = side_mm / 30
acq_radius_mm  = cell_mm / 2      (the repo's 0.5/30 grid-unit radius, expressed in mm)
normalisation  = "cursor_bbox_square"
```

The normalisation is named `cursor_bbox_square` and that name is written into every artifact that
depends on it.

Rationale, stated here rather than inferred later. `CursorIntegrator` clamps to `[0,1]`.
Normalising on the 105 mm target field would **clip** real cursor excursions, because the cursor
leaves the target field on both axes (171.7 mm by 139.1 mm of excursion against a 105.0 mm by
105.0 mm target field), and a clipped trajectory is fabricated cursor behavior. A square box keeps
the grid isotropic in grid units, so the scalar `acquisitionRadius` means the same distance on both
axes.

Expected values for `indy_20160630_01`: `side_mm` about 171.7, `cell_mm` about 5.72,
`acq_radius_mm` about 2.86. These are **expected, not asserted**. The script computes them and the
emitted JSON records what it computed. A containment assertion is explicit: every cursor sample
must fall inside the box, and the script raises if any does not.

## 3a. Amendment, 2026-09-05: the box is the recorded `cursor_pos` track

A dated amendment to section 3, made after Plans 10-01, 10-02 and 10-03 had run. It is recorded in
full rather than applied silently, because a pre-registration that can be rewritten without a trace
is not a pre-registration.

**What the original text said.** The first line of section 3's block read, verbatim:

```
cursor_mm      = 10.0 * planar_cm            (the verified x10 frame relation)
```

`planar_cm` is `(-finger[1:3, :]).T` (`Decoder/src/ndt1/data.py:401`), the FINGER track. The literal
text therefore derived the box from the finger track scaled by ten.

**What it says now.** `cursor_mm` is the session's own recorded `cursor_pos` array, read from the
`.mat` and already in millimetres. Nothing else in section 3 changes: the box is still square, still
axis-aligned, still the larger of the two bounding-box spans, still centred on the bounding-box
centre, still 30 x 30 with `acq_radius_mm = cell_mm / 2`, and still named `cursor_bbox_square`.

**Why.** The two are different boxes, and the original text was internally inconsistent with the
rest of its own section. Measured on `indy_20160630_01`, over all 365,809 behaviour samples:

| Box | `side_mm` | `cell_mm` | `acq_radius_mm` |
|---|---|---|---|
| Recorded `cursor_pos` (this amendment) | 171.68196243849025 | 5.7227320812830085 | 2.8613660406415042 |
| `10.0 * planar_cm` (the superseded literal text) | 171.0725351294064 | 5.7024178376468795 | 2.8512089188234397 |

The decisive fact is containment, which section 3 already required in writing: "every cursor sample
must fall inside the box, and the script raises if any does not." **13 of the 365,809 recorded
cursor samples fall outside the finger-derived box; 0 fall outside the recorded-cursor box.** The
finger-derived square is 171.07 mm on a side while the recorded cursor spans 171.68 mm on the same
axis, so no centring of a 171.07 mm square can contain the recorded track. The finger box fails the
pre-registered containment assertion by construction, not by a floating-point ulp. The converse was
measured and holds cleanly: **0 of 365,809 finger-track samples fall outside the recorded-cursor
box.** The recorded-cursor box is the only one of the two that contains both tracks, and containment
is exactly what the assertion exists to protect, since a sample outside the box is a clipped
excursion and a clipped trajectory is fabricated cursor behavior.

Two further consistency points, both already visible in the original text. Section 3's own expected
values ("`side_mm` about 171.7") are the recorded-cursor numbers, not the finger numbers. So is its
reported excursion, "171.7 mm by 139.1 mm": the recorded cursor spans 171.68 by 139.13, the finger
track 171.07 by 138.85.

**Who decided.** The user, explicitly, on 2026-09-05, after Plan 10-02's own cross-artifact
discrepancy note surfaced the disagreement. No agent chose this.

**What changed as a result, and what did not.** No already-published number changed. Plan 10-01's
`10-ceiling.json` and `10-ceiling-evidence.md` were computed on the recorded `cursor_pos` box and
already carry `side_mm` 171.68196243849025 and 147 of 1,025 trials at radius 2.8613660406415042.
They are correct as published, and they are not reissued. What moved is the two artifacts that had
implemented the superseded literal text: the Plan 10-02 replay export sidecar and the Plan 10-03
Kalman R fit, whose `k = 10.0 / side_mm` shifts by 0.35 percent and therefore moves `R` by
0.71 percent. Both were regenerated on the corrected box, and the measured direction is recorded in
`10-03a-RECONCILIATION-SUMMARY.md`. The amendment moves two artifacts ONTO a number that was
committed before either of them ran. It does not move any number toward a more flattering result.

**The x10 frame relation is not repealed, only demoted.** `cursor_pos = 10.0 * planar_cm` remains a
verified property of this session and is still checked on every export by
`Decoder/scripts/export_replay.py::verify_frame_relation`, which aborts if it stops holding. It is
still what puts a decoded cm/s velocity into the millimetre frame, and it is still the 10.0 in
`grid_units_per_cm = 10.0 / side_mm` (section 4's `k`). It is **not** what defines the box. The two
uses are not interchangeable: a unit conversion tolerates a fitted slope of 10.005 harmlessly, while
a bounding box built through that same 0.05 percent scale error stops containing the track it exists
to bound.

**Relation to this document's own no-edit rule.** The rule in the frontmatter stands. This is the
remedy that rule itself prescribes, "a new dated section that supersedes the old one and states what
changed and why, leaving the original text intact", applied in this repo's established form: the
superseded line is quoted verbatim above, section 3 carries a pointer to this amendment, and the
reference number the convention was registered to protect is unchanged.

## 4. Open Question 3, the R residual units

Pre-registered, before the fit runs.

R is fit **in the units the filter runs in: grid-units per second.** The two candidate conventions
(cm/s and grid-units/s) differ by a factor of `k^2`, which is large. This one is chosen because the
committed default `R = diag(0.25)` in `KalmanConstants.swift` was already documented as
`(grid-units/s)^2`, so fitting in grid-units/s keeps the fitted value on the same scale as the
default it replaces.

The procedure, in order:

1. Compute the held-out residual `resid_cm_s = v_decoded_cm_s - v_true_cm_s` on the chronological
   tail split, at lag 1 bin and lambda 0.1, using the same window stack `fit_velocity_real.py`
   builds. Import it; do not reimplement it.
2. Convert to grid units: `k = 10.0 / side_mm` grid-units per centimetre (10.0 mm/cm divided by the
   box side in mm). `resid_grid_s = k * resid_cm_s`.
3. `R = cov(resid_grid_s)` as a 2x2, then take `R = diag(R[0,0], R[1,1])`. The filter's measurement
   model is per-axis. Record the off-diagonal in the evidence, but do not use it.
4. Record `k` and `side_mm` in the generated `KalmanConstants.swift` provenance header, so the
   number is reproducible from the file alone.

Acceptance: the regenerated header reads `noise source = indy-heldout`, never `default`.

## 5. Q

Pre-registered. Q stays the white-noise-jerk form `white_noise_jerk_q(sigma_jerk_sq)`.
`sigma_jerk_sq` is fit as the variance of the second difference of the true binned velocity, in
grid-units/s^3, on the **same** held-out split, using the same `k`.

If that fit produces a non-Schur gain, `steady_state_gain` raises. The fallback is **not** to
silently revert to the default: the raise is recorded in the evidence and reported.

## 6. Open Question 2, the N normalisation

Pre-registered: report **both**, with these exact labels.

`WebgridBPS.bitsPerSecond(n:correct:incorrect:seconds:)` is called twice per arm:

- `n = 900`, `log2(900) = 9.8138`, the 30x30 re-grid. JSON key `bps_n900`.
- `n = 64`, `log2(64) = 6.0`, the number of distinct targets the animal actually saw. JSON key
  `bps_n64`.

The N = 900 number stays the **headline, for continuity with Phase 8's 1.953**, and the N = 64
number is stated immediately beside it, in the same table row, everywhere the headline appears.

**Label discipline, pre-registered.** The N = 900 figure is a **counterfactual grid score**: what
the recorded session's selections would be worth on a 900-cell grid. It is not the information rate
of the task that was recorded, because the task presented 64 targets. Every place the headline
appears it carries this label, in these words or a byte-identical variant:

```
counterfactual 30x30 grid score; the recorded task presented 64 targets (6.0 bits), whose rate is N=64
```

The N = 64 figure is the one labeled `the recorded task's information rate`. Both JSON keys carry a
sibling `*_label` string holding the same text, so the label cannot be dropped by a prose edit.

Reason: snapping a 64-target track onto a 900-cell grid and crediting 9.81 bits per hit awards
1.64x more information per selection than the task contained. Presenting that as the task's rate
would be the same defect class as a synthetic number labeled real.

## 7. Open Question 5 and D-04, the fourth arm

Pre-registered. Arm name `refit_reversed_target`.

The rotation's target track is the session's real `target_pos` track **reversed in time**
(`track[::-1]`), and nothing else changes. The **scoring** target stays the **true** target for all
four arms, so all four BPS and throughput numbers are directly comparable.

State the trap explicitly: if both the rotation target and the scoring target were reversed, the
control would be vacuous, because the cursor would be rotated toward the same target it is scored
against.

Time reversal is chosen over shuffling because it preserves the track's autocorrelation and spatial
distribution while destroying its temporal relationship to the spikes.

Each arm carries a `rotation_target_source` field with one of three values: `none`, `true_track`,
`reversed_track`.

| Arm | `rotation_target_source` |
|---|---|
| `raw` | `none` |
| `kalman_only` | `none` |
| `refit` | `true_track` |
| `refit_reversed_target` | `reversed_track` |

**What this control can and cannot establish.** Pre-registered before the number exists. Read both
directions and do not later state only the flattering one.

- If uplift **survives** the reversed target, the uplift is the rotation exploiting target knowledge
  rather than the decode, and that is the finding (CONTEXT D-04).
- If uplift **disappears** under the reversed target, that does **not** convert the `refit` arm into
  an independent neural-decoding result. `IntentRotation.rotate` (`IntentRotation.swift:75-85`)
  returns `(speed / dist) * d`: it replaces the decoded direction with the direction to the known
  target and keeps only the decoded speed. The `refit` arm's cursor heading is target-determined by
  construction in both arms; only the target differs. So the correct reading of a failing reversed
  arm is narrow: the rotation needs the correct target to help. It says nothing about how much
  intent the decode itself carried. The `raw` and `kalman_only` arms, which never see a target, are
  the only arms whose rate is attributable to the decode.

That paragraph is written verbatim into `10-refit-real-evidence.md` (Plan 10-07) and into the
README's BPS section (Plan 10-12), so the limit is published beside the number rather than left to
a reader to derive.

## 8. The Willett confound: per-arm gain and smoothing

Pre-registered. Willett et al. 2017, IEEE TBME 65(9):2066-2078, DOI `10.1109/TBME.2017.2783358`,
warns that gain and smoothing differences can confound decoder comparisons. That warning is what
this section acts on.

**Scope limit, pre-registered.** The paper compares decoder **calibration** methods: how the
intention used to **fit** a decoder is estimated. This repo's `IntentRotation` is a **runtime**
transform applied to an already-fit decoder's output. Willett 2017 therefore supports exactly one
claim here: gain and smoothing can produce an apparent uplift with no intent information involved,
so they must be measured per arm. It does not predict that this repo's runtime target-directed
rotation should show a small benefit, and no artifact in this phase may cite it for that. The
required wording is: gain and smoothing are reported per arm so that any uplift is attributable
rather than assumed.

Every arm therefore reports:

- `realized_gain` = `mean(|v_out|) / mean(|v_in|)` over the arm's ticks
- `realized_smoothing` = lag-1 autocorrelation of the output velocity magnitude

and the artifact reports **both** deltas:

- `refit - kalman_only`, the rotation with gain and smoothing held fixed. **This is the
  attributable number.**
- `refit - raw`, the headline comparison, which conflates the rotation with the Kalman's gain and
  smoothing.

Do not cite any of the four unverified offline-versus-closed-loop candidates from
`10-RESEARCH-INPUTS` Finding 4. Willett 2017 is the one verified citation and it is sufficient.

## 9. RD-08's two seams

Pre-registered.

**Seam A** is the Phase-8 measurement geometry with exactly one variable changed. Same
`CortexDemoBench`, same modelled 120 Hz present arithmetic, same `GlassToGlassTimer.sample`. What
changes: the spike source becomes the real export and the decode becomes the real `.mlpackage`.
This p99 is comparable to the Phase-8 8.3 ms and is reported beside it.

**Seam B** is the D-05 chain: daemon reads the export, AES-GCM seal, shm ring, consumer decrypt,
rolling 32-bin window, `SpikeInputBuffer`, decode. This is a strictly **wider** measurement
boundary and is reported as a new number, never against 8.3 ms.

Stated verbatim, because CONTEXT D-05 is factually wrong on this point: the Phase-8 8.3 ms did
**not** include an IPC leg (`Packages/CortexDemo/Package.swift` declares no `CortexIPC` dependency)
and was **not** model-backed (`CortexDemoBench:90` builds `ClosedLoopPipeline(seed:)` with no model
URL). CONTEXT D-05's claim that the re-derived number would be "like-for-like with the Phase-8
number, which included the IPC leg" is therefore wrong, and the Seam A / Seam B split is the
repair.

**Pre-registered, and non-negotiable (D-09).** Neither seam's latency may be routed through the
Phase-8 PERF-04 verdict. `CortexDemoBench/main.swift:144` computes `let passed = histogram.p99 <
budgetNs` and `:188-197` exits non-zero when it is false, and `ci.yml:428-429` invokes that binary.
That synthetic 25 ms gate is correct and stays exactly as it is on the `--smoke` and `--full`
paths: it guards a deterministic software pipeline against regression. Inheriting it onto a
real-data measurement would let a real-data result redden the build, which is the "a red build is
pressure to tune" failure D-09 forbids. Therefore, in writing, before either number exists:

- the real-data path emits no `passed` field and no `budget_ns` comparison, and exits 0 whatever the
  p99 is;
- `10-replay.json` carries no `passed` key for either seam;
- the 25 ms budget is quoted in the evidence only as the PERF-04 target the **synthetic** path is
  gated against, never as a bar either seam was judged by.

The `10-RESEARCH` claim at `:1119` that the Phase-8 smoke "asserts only that the bench runs" is
false and must not be relied on. The assertion above is the corrected fact.

## 10. The model-in-loop assertion

Pre-registered. `ClosedLoopPipeline.decodeWithModel` wraps everything in `try?` and falls through to
`syntheticDecodedVelocity` on any error, including a shape mismatch. `SyntheticSpikeSource`'s
default `numBins` is 8; the shipped model wants 32.

Therefore every real-data run counts `decodedByModel` per tick and commits `ticks_model_backed` and
`ticks_total` in its JSON, and the run **fails loudly** (a `precondition`) if they differ. No
real-data number is published from a run where they differ.

## 11. Artifact schemas

The exact top-level key list for each committed artifact, so the schema tests and the provenance
gate can be written against it without guessing.

`10-ceiling.json`:

```
schema_version, data_source, session_id, source_sha256, manifest_path, workspace,
canonical_radius_mm, canonical_dwell_s, canonical_hits, trials, table, env, disclosure
```

`10-refit-real.json`:

```
schema_version, data_source, session_id, source_sha256, manifest_path, export_sidecar_sha256,
encoder_checkpoint_sha256, velocity_checkpoint_sha256, arms, deltas, references, device, env,
disclosure, superseded_synthetic
```

`arms` holds four entries, each with: `name`, `rotation_target_source`, `correct`, `incorrect`,
`seconds`, `bps_n900`, `bps_n64`, `fitts_tp`, `realized_gain`, `realized_smoothing`.

`10-replay.json`:

```
schema_version, data_source, session_id, source_sha256, export_sidecar_sha256, seams,
frame_period_ns, cadence_provenance, ticks_model_backed, ticks_total, hits, trials,
replay_reference_hits, replay_reference_ref, distance_to_target_mm, decomposition,
sc2_disposition, sc2_rule, env, disclosure
```

`seams` holds two entries, each with: `seam` (`A` or `B`), `p50_ns`, `p99_ns`, `max_ns`, `count`,
`device`, `status`, `methodology`, `boundary`, `data_source`. Neither entry carries `passed` and
neither carries `budget_ns`, per section 9.

`distance_to_target_mm` holds the percentiles `p1`, `p5`, `p25`, `p50`, `p90` of cursor-to-target
distance in millimetres.

**Naming choice, fixed here and not changed later.** The recorded-cursor replay reference is named
`replay_reference_hits` and `replay_reference_ref` in `10-replay.json`. The names `ceiling_hits` and
`ceiling_ref` are **not** emitted, because the ceiling framing was rejected (section 16). The gate
and the schema test name `replay_reference_hits` and `replay_reference_ref`. The word "ceiling"
survives only in the file and identifier names that already exist (`webgrid_ceiling.py`,
`10-ceiling.json`, `10-ceiling-evidence.md`), never in a published sentence describing the number.

## 12. Disclosure strings

Pre-registered, verbatim, byte-identical everywhere they appear.

- Open-loop disclosure: `open-loop replay of a recorded session; the subject was not in the loop`
- README-required token subset of it: `open-loop replay`
- Session token: `indy_20160630_01`
- Checkpoint token: `9d542cb51d4a`
- Device label for every Mac number: `Apple M5 Pro`, with `status` = `corroborating`

**BPS non-comparability disclosure, the canonical short form.** Required by `honesty-sweep.sh`
(Plan 10-14) in both the README and `docs/cortex-spec.md`, as a single unwrapped line so byte
identity is checkable:

```
this repo's Webgrid BPS is not like-for-like with either reference: the formula differs (log2(N) here versus log2(N-1) in eLife 18554), the grid differs (T5 dense 9x9, not 6x6), the harness makes incorrect selections structurally zero so Si is always 0, and Neuralink's current published score adds a click-types term this single-click-type harness omits
```

The long form, carrying the `CortexReFITBench/main.swift:283-285` citation for the structurally
zero Si, goes in `10-refit-real-evidence.md` and in `WebgridBPS.swift`'s doc comment (Plan 10-11).

This is a **disclosure obligation, not a formula change**. Editing `bps-policy.sh`'s pinned formula
would break the Phase-7 byte-identity fixture that D-09 exists to protect.

## 13. D-09, restated as a build rule

No gate, test or CI step added by this phase may assert the sign or magnitude of any real-data
result. Gates assert provenance, schema and structure only.

The Phase-7 `refit_bps.json` byte-identity invariant and `check_refit_uplift.py`'s
`refit_bps >= raw_bps` stay untouched and synthetic-scoped.

A negative or zero finding must be publishable without turning the build red, because a red build is
pressure to tune.

## 14. D-11, restated, and the proxy promoted

Pre-registered. If the decoded hit count is zero, that is the published result. It is reported
against the pre-registered recorded-cursor replay reference at section 3's radius and dwell 0.30 s.
Acquisition parameters are **not** relaxed until hits appear.

**The hit-independent cursor-to-target distance proxy is RD-08's PRIMARY reported observable, not a
fallback.** It is pre-registered here because the pre-execution measurement in section 1 makes a
floored hit count likely. A count that is zero carries no information and cannot distinguish a
decoder that drove the cursor most of the way from one that did nothing, while the
distance-over-time distribution degrades gracefully and discriminates both. Every artifact and every
table that reports the hit count reports the proxy percentiles (p1, p5, p25, p50, p90 of
cursor-to-target distance in mm) beside it, in the same row or the adjacent one. The hit count is
still reported, first and unhidden. It simply is not the only observable RD-08 rests on.

**The decomposition has five factors, not four.** The keys are fixed here so the schema test and the
evidence agree:

| Key | What it records |
|---|---|
| `velocity_amplitude_shrinkage` | The ridge/MSE shrinkage-toward-the-mean effect. Report the ratio of decoded to true velocity magnitude (mean and p95). State in one sentence that a systematically under-scaled velocity travels too short a distance to enter the acceptance radius within the dwell window. **First** among the mechanical explanations, because it is the one that most directly produces a zero |
| `decode_r2` | The session's held-out velocity R2, with both the Phase-9 per-session figure (+0.1446) and the executor's own measurement, each labeled with its method |
| `open_loop_no_error_correction` | A recorded session's spikes cannot respond to a cursor we drive |
| `workspace_to_grid_scale` | The `cursor_bbox_square` box, `cell_mm`, `acq_radius_mm` |
| `dwell_and_timeout` | 0.30 s dwell, 5.0 s timeout, continuous-dwell semantics, stated as not relaxed |

The mechanism named by `velocity_amplitude_shrinkage` was observed in the pre-execution
measurement: the decoder tracks reach timing well (decoded peaks align with true peaks) but
systematically under-scales amplitude, with true velocity peaks reaching plus or minus 20 to 30
cm/s while decoded output rarely leaves plus or minus 10. That is ordinary ridge/MSE shrinkage
toward the mean, not a defect, and it is decisive for hit counts.

## 15. The RD-08 hit criterion

Pre-registered contract, fixed before any hit count exists.

There is a real conflict in this phase's own inputs and it is resolved here, not after the number is
seen. RD-08 and ROADMAP SC#2 require "a 30x30 webgrid hit demonstrated". D-11 accepts zero hits as a
publishable result. Nothing previously defined how a zero relates to the requirement, which would
have left the project free to redefine success after seeing the number, the exact move this
milestone exists to eliminate.

**Row B is the EXPECTED outcome, on measured evidence, and saying so in advance is the point.** The
pre-execution measurement in section 1 gives this session a pooled held-out R2 of about 0.15,
against a recorded-cursor replay reference of 4.2 percent at the 30x30 half-cell radius over the
105 mm target field, with a decoder that systematically under-scales velocity amplitude. Zero hits
is the most probable result. Writing that here, before the run, is what makes the eventual number a
finding rather than a disappointment that invites re-litigating the rule.

The disposition is chosen from this table, and the table is committed before the measurement.
Whichever row the outcome lands in, that row's disposition is what happens.

| Outcome on the `refit` arm at the pre-registered radius and dwell | SC#2 disposition (`sc2_disposition`) | What the phase does |
|---|---|---|
| **A.** `hits >= 1` | `met` | Publish the count against the replay reference. Plan 10-10 Task 2 captures the demonstration on the M5 Pro |
| **B.** `hits == 0` on all four arms and the recorded-cursor replay reference is `>= 1` (**the expected row**) | `not_met` | Publish the zero, with the distance proxy as the primary observable and the five-factor D-11 decomposition beside it. Do not relax radius, dwell or timeout. Record SC#2 as NOT MET and route the amend-or-defer choice to the user at Plan 10-10 Task 3, which is a blocking checkpoint |
| **C.** `hits == 0` and the recorded-cursor replay reference is also `0` | `unachievable_at_this_geometry` | The geometry admits no hit for the recorded trajectory either, so the criterion cannot discriminate. That is itself the finding. Publish it and route the same user choice |

Four rules bind every row:

0. **The session is not switched.** `indy_20160630_01` is locked by D-08 and stays locked even
   though the pre-execution measurement shows it near the bottom of the per-session range. Choosing
   a stronger session after seeing that is selection on the outcome, which is the thing D-08 exists
   to prevent. The weakness is disclosed, not corrected.
1. **No parameter relaxation.** Radius, dwell and timeout are the pre-registered values in every
   row. A row-B or row-C outcome is never converted into a row-A outcome by widening the acceptance
   zone.
2. **No agent amends a success criterion.** In rows B and C the phase records SC#2 as NOT MET and
   presents the amend-or-defer decision to the user. An executor that quietly restates SC#2 as
   satisfied has committed the defect this phase exists to remove.
3. **The disposition is written into `10-replay.json` as `sc2_disposition`**, with the value `met`,
   `not_met` or `unachievable_at_this_geometry`, plus `sc2_rule` naming the row (`A`, `B` or `C`).
   Plan 10-09's schema test asserts the key is present and its value is one of the three. It asserts
   nothing about which, because that would be an assertion on the direction of a real-data result
   (D-09).

Noted for the record, not an action for this phase's executors: `ROADMAP.md:204` still describes
"the 3-way ablation" while D-04 locks a fourth arm. Amending a success criterion is the user's call.
It is flagged, not edited.

## 16. What the recorded-cursor replay reference is, and is not

Pre-registered, so that the framing cannot drift once the decoded number exists.

The reference number is the hit rate obtained by replaying the animal's **own** recorded cursor
trajectory through this repo's dwell-to-select rule at one radius and one dwell. RESEARCH
Correction 4 measured 43 of 1,025 trials (4.2 percent) at the 1.75 mm radius over the 105 mm target
field, and an external reviewer independently reproduced the arithmetic on 2026-09-05.

It is a property of **one recorded trajectory under one acceptance rule**. It is not a bound on what
a decoder can achieve. A decoder producing different trajectories, with straighter approaches or
longer holds inside the radius, can exceed it. Its value is as a pre-registered reference point that
makes a decoded count interpretable.

Every published sentence uses the **recorded-cursor replay** wording. The word "ceiling" survives
only in file and identifier names that already exist. The framing that this reference is what any
decoder could at best achieve is rejected and must not appear in any Phase 10 artifact.

## 17. Reference figures and their sourcing

Pre-registered so no artifact adopts an unsourced number.

| Figure | Status |
|---|---|
| 4.16 BPS | Pandarinath et al. 2017, eLife 18554. Measured with **T5 on a 9x9 dense grid**, 8 evaluation blocks, not the 6x6 grid. The 6x6 figures in the same paper are T6 2.2, T5 3.7, T7 1.4 |
| 8.5 BPS | Kept per D-17, but dated and sourced everywhere it appears, with the current public wording ("over 10 BPS", neuralink.com/webgrid, verified live 2026-09-05) stated beside it. `readme-policy.sh`'s required `8.5` token is unchanged. `docs/cortex-spec.md`'s internal 8-versus-8.5 contradiction (`:54`, `:172` versus `:313`) is resolved in the same sweep |
| The figure the research-inputs pass attributed to neuralink.com/webgrid | **Unverified and not adopted.** It is not on the page as of 2026-09-05. It appears nowhere in this phase's artifacts |
| 24.7 ms | A spec target, never a measurement. May appear only under a Future work or retired heading, adjacent to a target marker (D-13) |

## 18. Provenance and precedence

- This document is committed before Plan 10-02's ceiling run and before every decoded number in the
  phase. The git order is the audit trail.
- Where this document and `10-CONTEXT.md` disagree, this document governs, and the disagreement is
  stated here rather than resolved silently. Sections 9 and 16 are the two places that happens.
- Where this document and `10-RESEARCH.md` disagree, this document governs. Section 9 is the one
  place that happens.
- Nothing here may be edited after a number it governs has been measured. One amendment has been
  made under that rule's own remedy clause: section 3a, dated 2026-09-05, which supersedes a single
  line of section 3 and leaves the superseded text quoted verbatim. It changed no published number.
  It is the only amendment; anything else claiming to amend this document is not authorized by it.
