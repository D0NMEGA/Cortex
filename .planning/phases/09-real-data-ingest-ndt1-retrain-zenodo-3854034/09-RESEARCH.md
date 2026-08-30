---
status: PARTIAL
agent: donny-phase-researcher
phase: 9
confidence: HIGH
---

# Phase 9: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034) - Research

**Researched:** 2026-08-30
**Domain:** MATLAB v7.3 / HDF5 neural-data ingest, masked-modeling retrain on real macaque M1 spikes, CoreML re-derivation, CI provenance gating
**Confidence:** HIGH (the dataset findings are empirical, produced by downloading and parsing the actual files in this session)

> **Why status is PARTIAL, not PASS.** The research is complete and self-sufficient, but it
> falsifies three factual premises that CONTEXT.md and the committed manifest rest on. Two of the
> four manifested sessions are 192-channel M1+S1 files that the loader is designed to reject, the
> NLB'21 `mc_rtt` session is not `indy_20160630_01` and is not in this Zenodo record at all, and
> `finger_pos`'s "first two axes" are not (x, y). None of these invalidate a locked *decision*, but
> the planner must resolve the session set (Open Question 1) before decomposing waves.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Real-data ingest and integrity (RD-01, RD-02)**

- **D-01:** `scripts/download_indy.py` is used as-is for the fetch. It already fills a `"PENDING"`
  checksum on first fetch and raises `ValueError` on mismatch. What RD-01 adds is the negative
  control: deliberately corrupt a fetched `.mat` and prove the integrity gate bites, in the
  `validate-privacy-manifest.sh --self-test` idiom the project has used since Phase 1.
- **D-02:** RD-02's "documented plausible band" is a pinned pytest regression test over 20 ms binned
  per-channel firing rates. A silently misparsed session fails the suite rather than training quietly.
- **D-03:** Session contingency. A session failing the 96-channel gate or the plausibility band is
  excluded and the exclusion is documented; the loader raising `ValueError` on a 192-channel M1+S1
  file is correct behavior, not a bug to route around. Substitute another Indy M1-only session from
  the same Zenodo record ONLY if fewer than three sessions survive, updating the manifest and
  re-pinning checksums. Never reshape the dataset until the numbers improve.
- **D-04:** Raw spike counts, no per-session rate normalization. The Poisson NLL objective and the
  co-bps metric are both defined on actual counts, so normalizing would break the metric and its
  comparability to Phase 4 and to NLB'21. Session heterogeneity is instead surfaced: the evidence
  artifact reports per-session channel yield including dead and silent channels.

**Velocity readout on real kinematics**

- **D-05:** The real-data checkpoint includes a velocity readout fit on the real behavior arrays.
  `data.py`'s documented contract is amended accordingly: it now reads `finger_pos` alongside
  `spikes` and `t`. The large `wf` waveform array remains untouched (threat T-04-02-02).
  Without this, the shipped `.mlpackage` would carry a real encoder and a fabricated readout, and
  Phase 10's RD-07 could not fit `R` from real `z_decoded` vs `v_true` residuals.
- **D-06:** Label source is `finger_pos`, first two axes (x, y). This is the NLB'21 mc_rtt convention,
  and `indy_20160630_01` is the mc_rtt benchmark session, so the number stays legible against
  published work. `cursor_pos` is a gained derivative of the same signal and is not the benchmark
  variable.
- **D-07:** Velocity derivation is a finite difference at the native 250 Hz behavior rate, then a
  mean aggregate of the samples falling in each 20 ms bin. No smoothing filter: a Savitzky-Golay
  derivative would introduce window and order parameters that need justifying and can smooth away
  genuine fast dynamics.
- **D-08:** Neural-to-kinematic lag is swept over whole-bin offsets from 0 to 160 ms using the TRAIN
  split only. One value is locked and the full sweep is published in the evidence artifact.
  Selection never touches the held-out tail, so there is no leak, and the sweep documents how
  sensitive R2 is to the choice rather than leaving it assumed.
- **D-09:** The fit stays closed-form ridge, `W = (XtX + lambda*I)^-1 XtY`, through the existing
  `ridge_fit` / `load_ridge` path and its rank-2 to rank-4 pre-hook. Only the labels change. No
  training loop, no new op types, so the 226/226 ANE-eligibility result is not put at risk and the
  DEC-10 contract holds.
- **D-10:** The committed velocity number is held-out R2 against a constant mean-velocity null,
  reported per axis, per session, and pooled. This replaces `velocity_r2.json`'s 0.9998, which
  regressed rates onto labels generated from those same rates and is a self-consistency check
  rather than a decode result. Mirrors the existing co-bps-vs-null discipline.

**Multi-session training and generalization (RD-03, RD-04)**

- **D-11:** One pooled checkpoint trained on all four sessions' train splits. Evaluation on each
  session's own held-out tail supplies RD-04's per-session co-bps. One model ships.
- **D-12:** Split discipline is a per-session chronological tail (`test_frac = 0.2`). No pooled
  shuffle, no cross-session leakage. Preserves Pitfall #10 from 04-RESEARCH.
- **D-13:** RD-04's leave-one-session-out number is a full four-fold zero-shot rotation: train on
  three sessions, evaluate co-bps on the fourth with no exposure to it, rotate through all four.
  Report four numbers plus mean and spread. This is what "generalizes across four sessions"
  actually requires.
- **D-14:** Training budget starts from the Phase-4 config verbatim (12 epochs, lr 2e-3, batch 16,
  seq_len 32, seed 0) so the run is directly comparable. Any change is documented with rationale.
  The loss curve is committed; if it has clearly not converged at 25-30x the synthetic bin count,
  the budget is raised and that is stated in the evidence.
- **D-15:** The cross-session assumption is stated explicitly in the evidence artifact: pooling raw
  96-channel spikes across sessions spanning April to June 2016 assumes stable channel-to-neuron
  identity across electrode drift. That assumption is exactly what NDT2's session-conditioning
  relaxes, and NDT2 is Out of Scope for v0/v1. A pooled number below the per-session numbers is
  therefore an expected and reportable outcome, not a defect.

**CoreML re-derivation (RD-05, RD-06)**

- **D-16:** The 4-bit palettization delta is re-measured on BOTH models. Poisson-NLL delta on the
  reconstruction model, for direct comparability to `04-palettization-evidence.md` (3.471x size,
  delta 0.009114). R2 delta on the with-velocity model, because that is the artifact that ships.
- **D-17:** ANE eligibility (226/226 ops, zero CPU-only) and decoder p99 are measured on the
  with-velocity model, the one `NeuralDecoder` actually loads. The device disposition carries
  forward unchanged from DEC-08 / DEC-11 and the D-11/D-12/D-08 line across Phases 5 to 8:
  M5 Pro corroborating, iPad Pro M4 canonical capture optional and never auto-approved. Real
  weights do not change the architecture or the 1.29M param count, so a material p99 shift would
  itself be a finding.

**CI gating and provenance enforcement**

- **D-18:** The Decoder Python quick suite starts running in CI as a blocking gate:
  `uv sync --project Decoder --extra dev` then `pytest -m "not slow"`. Those tests need no dataset
  (they synthesize or skip cleanly). This closes a real hole: 3,582 lines of Python currently have
  zero CI coverage (`ci.yml` contains no `uv`, no `pytest`, no `ndt1`). The uv install is
  cache-keyed like the existing DerivedData and SwiftPM caches.
- **D-19:** One `Tools/scripts/decoder-policy.sh` with a `--self-test` negative control asserts
  three things: (a) zero `"PENDING"` sha256 entries in `indy_sessions.json`; (b) the committed
  metrics JSON declares its `data_source` plus the session ids and checksums it was produced from;
  (c) those checksums agree with the manifest. Each assertion is proven to bite. This is what
  structurally ties a published number back to the bytes it came from.
- **D-20:** A tiny synthetic MATLAB v7.3-structured `.mat` fixture is committed so CI can exercise
  the cell-array dereference and channel-axis transpose path without the gitignored 1.5 GB dataset.
  Fabricated values in a real HDF5 structure (`spikes` as an n_channels x n_units object-reference
  array with zero-filled empty cells, a `t` vector, `finger_pos`). No dataset redistribution, no
  licensing question, and it targets the highest-probability failure identified in this phase.
- **D-21:** Measured numbers live in a committed `09-training-evidence.md` plus a metrics JSON,
  produced by a human-run runbook. CI never trains and never downloads the dataset. This is the
  Phase 2 D-18 / Phase 6 D-10 tier split applied unchanged: CI gates correctness and structure,
  hardware and human runs gate the measured numbers.

**Evidence framing and honest-number handling**

- **D-22:** RD-03's pass bar is beating the train-split per-channel mean-firing-rate null. The test
  assertion margin is re-derived from the observed real value AFTER measuring and its rationale is
  documented, exactly as Phase 4 set 0.05 against an observed 0.38. `CO_BPS_MARGIN = 0.05` was
  calibrated to a purpose-built learnable sinusoid and does not transfer. No tuning toward a bar
  (Phase 8 D-12).
- **D-23:** NLB'21 mc_rtt is cited as context, with the protocol difference stated plainly: our
  masked-reconstruction co-bps over all channels is NOT NLB's held-out-neuron co-smoothing co-bps,
  and the two are not directly comparable. This applies the Phase-7/8 D-13 lesson prospectively
  (the Fitts throughput is not the Webgrid bitrate).
- **D-24:** Citation updates are scoped to decoder-owned surfaces this phase: `PROJECT.md`, the
  ROADMAP Phase-4 bullet, and REQUIREMENTS RD-03. `04-training-evidence.md` and
  `05-velocity-head-evidence.md` get a clearly marked superseded banner pointing at the Phase-9
  artifacts, WITHOUT altering what those phases actually measured (a historical evidence artifact
  is not retroactively edited). README, ADR-0002 and `bps-policy.sh` carry ReFIT-side numbers and
  stay for RD-09 in Phase 10.
- **D-25:** A low honest number completes the phase. The deliverable is that the decoder has
  actually seen real primate M1 spikes and that every number is re-derived and labeled, not that
  the number is good. Gaps are documented with what would close them (more sessions,
  session-conditioning, longer budget) and parked in the backlog rather than expanded into scope.

### Implementer's Discretion

Sensible defaults; planner and executor choose within the constraints above without re-asking:

- Exact `decoder-policy.sh` token lists and self-test construction (mirror the existing gate idioms).
- The metrics JSON schema, file naming, and where it lives under the phase directory.
- The uv cache key construction in `ci.yml`.
- The synthetic `.mat` fixture's dimensions and the location of its generator script.
- Ridge `lambda` selection for the velocity head.
- Whether the LOSO folds reuse the pooled hyperparameters or a reduced budget.
- Per-session channel-yield table formatting in the evidence artifact.
- Where the lag sweep runs (script vs test) and how the swept values are recorded.
- Plan and wave decomposition across RD-01..RD-06.

### Deferred Ideas (OUT OF SCOPE)

- **NLB'21 held-out-neuron protocol** for a directly leaderboard-comparable co-bps. Considered and
  deferred: it would expand RD-03 into adopting NLB's split and co-smoothing protocol. D-23 cites
  the benchmark as context instead.
- **Joint encoder + head fine-tuning** on real velocity. Considered and deferred in favor of the
  closed-form ridge (D-09). A candidate for v2 if the linear readout plateaus.
- **Session-conditioned modeling (NDT2)** to absorb cross-session channel drift. Explicitly Out of
  Scope for v0/v1 per PROJECT.md. Named here because D-15's stated assumption is precisely what it
  would relax.
- **Early stopping on a third validation split.** Methodologically cleaner, deferred in favor of the
  Phase-4-comparable fixed config (D-14).
- **Savitzky-Golay smoothed derivative** for velocity. Rejected for D-07 on unjustified parameters.
- **Committing a real session slice as a CI fixture.** Rejected in favor of the synthetic-structure
  fixture (D-20). Revisit only if the structural fixture proves insufficient.
- **A decoder-improvement phase** if the real numbers come in materially low. Per D-25 this is
  backlog, not a scheduled phase, until the size of the gap is known.
- **RD-07 through RD-10** (ReFIT re-fit and real-data BPS ablation, real-session closed loop and
  glass-to-glass re-derivation, repo-wide synthetic-number sweep, `readme-policy.sh` rewrite plus
  the photodiode-retirement ADR). Phase 10 by roadmap.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research support |
|----|-------------|-----------------|
| RD-01 | Four manifested Indy M1-only sessions downloaded and SHA-256-pinned, zero `"PENDING"`, integrity negative control proven | Section 2 (verified download URL, real byte sizes, Zenodo-published md5 for cross-check, one session already fetched with its SHA-256 recorded). Pitfall P2 (content-type blindness). Open Question 1 (two of the four are not M1-only). |
| RD-02 | `load_session` ingests each real v7.3 HDF5 session, 96-channel gate passes, cell-array deref correct, rates in a test-pinned plausible band | Section 3 (real HDF5 structure, confirmed transpose direction, the `MATLAB_empty` deref defect with an exact reproduction). Section 5 (measured firing-rate distribution, the band to pin, and why a per-channel band fails on dead channels). |
| RD-03 | NDT1 retrained on real multi-session spikes; held-out chronological-tail co-bps committed, beating the mean-rate null | Section 7 (co-bps arithmetic verified against `nlb_tools`, including the null-model difference). Section 9 (measured training throughput, 11-15 min pooled on CPU). Section 6 (why our co-bps is not NLB's). |
| RD-04 | Per-session held-out co-bps plus a leave-one-session-out number | Section 8 (cross-session drift, measured within-session drift of -8.1%, what a normal LOSO degradation looks like). Section 9 (LOSO cost, ~45-60 min). |
| RD-05 | 4-bit palettization delta re-measured on the real-data checkpoint | Section 10 (coremltools 9.0 defaults verified from the installed wheel, `weight_threshold=2048` means the velocity head is not palettized, why the size ratio should reproduce and the loss delta should not). |
| RD-06 | Real-data checkpoint re-converted; 226/226 ANE eligibility and <2 ms p99 re-verified | Section 10 (op eligibility is a graph property, invariant to weights; the concrete risks are the torch 2.12.1 / coremltools 9.0 untested pairing and k-means nondeterminism). |
</phase_requirements>

---

## Summary

The four-session manifest this phase is built on is factually wrong, and that is the single most
important thing the planner needs to know. I downloaded `indy_20160630_01.mat` (382 MB) and parsed
the HDF5 headers of eleven more sessions over HTTP range requests. Two of the four manifested
sessions, `indy_20160407_02` and `indy_20160411_01`, are 192-channel M1+S1 recordings whose
`chan_names` run `M1 001` through `S1 096`. The loader is *supposed* to reject them, and it does, so
under D-03 only two sessions survive, which is fewer than three, which means D-03's substitution
branch is not a contingency but the certain path. There is a clean temporal boundary in the record:
every Indy session in April 2016 is 192-channel, and every session from June 2016 onward that I
probed is 96-channel M1-only. Nine confirmed M1-only substitutes exist.

The second finding is a live data-corruption defect in `ndt1.data.load_session`. Empty cells in the
`spikes` cell array are not null HDF5 references; MATLAB writes them as valid, truthy references to
a `(2,) uint64` dataset carrying a `MATLAB_empty` attribute, whose payload is the array dimensions.
The `if not ref: continue` guard therefore never fires, and in `indy_20160630_01` the loader injects
498 spurious timestamps with values 0.0 and 1.0 across 92 of 96 channels. Today they are silently
discarded only because that session's behavior clock starts at t = 148.984 s, so they fall outside
`[t_start, t_end)`. The correct discriminator is the `MATLAB_empty` attribute, and D-20's fixture is
exactly the right place to pin it. The channel-axis transpose heuristic, by contrast, is correct:
h5py sees `spikes` as `(n_units, n_channels)` and the existing `n_dim1 == 96` test flips it properly.

The third finding contradicts two rationales, not decisions. `finger_pos` is `(z, -x, -y)` in cm, so
its "first two axes" are depth and negated-x, not (x, y). I verified this empirically: correlation
between `cursor_pos[0]` and `finger_pos[1]` is exactly -1.0000, while correlation with
`finger_pos[0]` is +0.285 and that axis has a standard deviation of 0.24 cm. The planar pair is rows
1 and 2. Separately, the NLB'21 `mc_rtt` session is `indy_20170202_02` (2017-02-02, per the DANDI
000129 asset metadata), which is not `indy_20160630_01` and is not in Zenodo record 3854034 at all.
D-06's label-source choice still stands on its own merits, because `nlb_tools` does use `finger_vel`
for `mc_rtt`, but the session-identity argument in D-06 and D-23 must be dropped.

**Primary recommendation:** Wave 1 replaces the two 192-channel entries in `indy_sessions.json` with
confirmed M1-only sessions (default: `indy_20160624_03` and `indy_20160915_01`, giving 1.77 GB and a
June-to-September span), fixes the `MATLAB_empty` dereference behind D-20's committed fixture, and
pins `finger_pos[1:3]` as the planar label pair. Everything downstream is then mechanical: measured
training cost is 11-15 minutes pooled and 45-60 minutes for the LOSO rotation on this Mac's CPU, and
`load_session` already parses a real 382 MB session correctly in 0.2 s.

---

## What changed versus 04-RESEARCH.md

04-RESEARCH was written against a file it had never seen. Everything below is now empirical.

| 04-RESEARCH claim | Status after this pass | Detail |
|---|---|---|
| `.mat` is MATLAB v7.3 = HDF5, needs `h5py` not `scipy.io.loadmat` (Pitfall #3) | **CONFIRMED** | File magic is `MATLAB 7.3 MAT-f`; root has a `#refs#` group and `MATLAB_class` attributes. [VERIFIED: local parse] |
| `spikes` is an `n x u` cell array of spike-timestamp vectors | **CONFIRMED, with the axis pinned** | h5py sees `(u, n)` = `(5, 96)`, transposed from MATLAB's `(96, 5)`. The loader's existing transpose heuristic handles it. [VERIFIED: local parse] |
| Chronological tail split, no shuffle (Pitfall #10) | **CONFIRMED and reinforced** | Measured within-session drift between the train head and test tail is -8.1% mean rate on `indy_20160630_01`. A shuffle split would hide exactly this. [VERIFIED: local parse] |
| Channel-width divergence is a risk (Pitfall #11) | **SHARPENED from risk to certainty** | 2 of the 4 manifested sessions are 192-channel. This is no longer a hypothetical. [VERIFIED: local parse + remote header probe] |
| "in most sessions M1 recordings were made alone (96 channels)" | **TRUE OF THE RECORD, FALSE OF THE MANIFEST** | 9 of 12 probed sessions are M1-only, but the manifest happened to pick 2 that are not. [VERIFIED] |
| `u1` is the unsorted/hash unit | **CONFIRMED and refined** | Zenodo: u1 holds "the threshold crossings which **remained** after the spikes on that channel were sorted into other units". So u1 alone is a *residual*, not the full threshold-crossing train. Summing u1..u5 (what the loader does) is the correct reconstruction of total threshold crossings. [CITED: zenodo.org/records/3854034] |
| Session subset is "sizeable", train on a few | **QUANTIFIED** | The four manifested files are 2.599 GB, not the roadmap's "~1.5 GB". Whole record is 24.01 GB across 48 files. [VERIFIED: Zenodo API] |
| `wf` is the bulk of file size, do not touch it (T-04-02-02) | **CONFIRMED** | `wf` is a `(5, 96)` cell array of waveform snippets, same shape as `spikes`; the loader never opens it. [VERIFIED: local parse] |
| `indy_20160630_01` is the NLB mc_rtt session (manifest note, CONTEXT `<specifics>`) | **FALSIFIED** | mc_rtt is `indy_20170202_02`. Not in this Zenodo record. [VERIFIED: DANDI 000129 asset metadata] |
| `finger_pos` is `k x 3` or `k x 6` in cm | **CONFIRMED, and the axis order pinned** | Order is `(z, -x, -y[, azimuth, elevation, roll])`. Both widths occur inside the candidate session pool. [CITED: Zenodo] + [VERIFIED: local parse] |
| (not covered) | **NEW: empty-cell dereference defect** | See Section 3. The single highest-probability silent failure in this phase. |

---

## Dataset ground truth

Primary sources: <https://zenodo.org/records/3854034> (record page, CC-BY-4.0, published 2020-05-26,
DOI 10.5281/zenodo.3854034) and the Zenodo REST record `https://zenodo.org/api/records/3854034`.
Everything marked [VERIFIED: local parse] was produced in this session by opening the real file with
h5py 3.16.0 under the project's own `uv` environment.

### Record shape

- 48 files, 24.01 GB total: 37 Indy sessions, 10 Loco sessions, and `refh_results.csv`.
  [VERIFIED: Zenodo API]
- License CC-BY-4.0. Redistribution of a slice would be permissible with attribution, but D-20's
  synthetic-structure fixture avoids the question entirely and is the better call.
  [CITED: zenodo.org/api/records/3854034 `metadata.license.id = "cc-by-4.0"`]

### Per-session `.mat` fields, as h5py actually sees them

Measured on `indy_20160630_01.mat`. Note every array is transposed relative to the MATLAB
documentation, because MATLAB is column-major and HDF5 is row-major.

| Field | MATLAB doc shape | h5py shape here | dtype | Notes |
|---|---|---|---|---|
| `spikes` | `n x u` cell | `(5, 96)` object | HDF5 object refs | `MATLAB_class = b'cell'`. Rows are units, columns are channels. |
| `wf` | `n x u` cell | `(5, 96)` object | refs | Waveform snippets, uV. Never opened by the loader (T-04-02-02). |
| `chan_names` | `n x 1` cell | `(1, 96)` object | refs to uint16 char | Values `'M1 001'` .. `'M1 096'`. The authoritative array-identity field. |
| `t` | `k x 1` | `(1, 365809)` | float64 | Seconds. `t[0] = 148.984`, `t[-1] = 1612.216`, median dt = 0.004 s (250.0 Hz). |
| `cursor_pos` | `k x 2` | `(2, 365809)` | float64 | mm. |
| `finger_pos` | `k x 3` or `k x 6` | `(6, 365809)` | float64 | cm, order `(z, -x, -y, azimuth, elevation, roll)`. |
| `target_pos` | `k x 2` | `(2, 365809)` | float64 | mm. |
| `#refs#` | (internal) | group | - | Where MATLAB parks the cell contents. Do not enumerate it directly. |

[VERIFIED: local parse of `indy_20160630_01.mat`]

### The four manifested sessions, ground truth

| Session id | Bytes | Zenodo md5 | h5py `spikes` | `chan_names` | `finger_pos` cols | Duration | 20 ms bins | Verdict |
|---|---|---|---|---|---|---|---|---|
| `indy_20160407_02` | 418,087,697 | `63ab3e2e55652fb5709eb024642111cf` | `(3, 192)` | `M1 001` .. `S1 096` | 3 | 818 s | 40,889 | **FAILS 96-ch gate** |
| `indy_20160411_01` | 663,268,786 | `cee905e1021535626a442748e5612643` | `(3, 192)` | `M1 001` .. `S1 096` | 6 | 953 s | 47,660 | **FAILS 96-ch gate** |
| `indy_20160627_01` | 1,135,050,817 | `de58797d649bdf2bec589c074ee991d2` | `(5, 96)` | `M1 001` .. `M1 096` | 6 | 3,363 s | 168,147 | PASSES |
| `indy_20160630_01` | 382,243,800 | `197413a5339630ea926cbd22b8b43338` | `(5, 96)` | `M1 001` .. `M1 096` | 6 | 1,463 s | 73,161 | PASSES |

Manifest total as committed: **2,598,651,100 bytes = 2.599 GB**, not the roadmap's "~1.5 GB".
[VERIFIED: Zenodo API `files[].size` / `files[].checksum`; shapes via remote HDF5 header reads over
HTTP Range]

### Confirmed 96-channel M1-only substitution candidates

Every one of these was header-probed remotely (12-15 MB of range reads each, not a full download).

| Session id | Size | h5py `spikes` | `finger_pos` cols | Duration | 20 ms bins |
|---|---|---|---|---|---|
| `indy_20160622_01` | 909.0 MB | `(5, 96)` | 6 | 2,450 s | 122,483 |
| `indy_20160624_03` | 144.0 MB | `(5, 96)` | 6 | 500 s | 24,999 |
| `indy_20160627_01` | 1135.1 MB | `(5, 96)` | 6 | 3,363 s | 168,147 |
| `indy_20160630_01` | 382.2 MB | `(5, 96)` | 6 | 1,463 s | 73,161 |
| `indy_20160915_01` | 106.6 MB | `(5, 96)` | **3** | 381 s | 19,052 |
| `indy_20160921_01` | 109.2 MB | `(5, 96)` | **3** | 360 s | 18,007 |
| `indy_20160927_04` | 120.3 MB | `(5, 96)` | **3** | 389 s | 19,468 |
| `indy_20160930_02` | 117.9 MB | `(5, 96)` | **3** | 461 s | 23,039 |
| `indy_20161005_06` | 84.0 MB | `(5, 96)` | **3** | 374 s | 18,700 |

Confirmed 192-channel M1+S1 (do not use): `indy_20160407_02`, `indy_20160411_01`,
`indy_20160411_02`, `indy_20160418_01`, `indy_20160419_01`, `indy_20160420_01`, `indy_20160426_01`.
Every probed April-2016 Indy session is 192-channel; every probed session from 2016-06-22 onward is
96-channel M1-only. `indy_20160426_01` is 192-channel with 5 unit-rows, so unit count is **not** a
usable discriminator; only `chan_names` / the channel axis is. [VERIFIED: remote HDF5 header probe]

### Already fetched, do not re-download

`indy_20160630_01.mat` is sitting at
`/private/tmp/agent-501/-Users-d0nmega-Developer-Cortex/c7b2dc68-4396-41f8-aeda-22443c34a3f2/scratchpad/indy_20160630_01.mat`
with:

- md5 `197413a5339630ea926cbd22b8b43338` (matches Zenodo's published checksum)
- **sha256 `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8`**

The executor can move it into `Decoder/data/` and paste that sha256 straight into the manifest, or
re-fetch and let `download_indy.py` compute it. Either way the value above is a cross-check that the
fetch was not silently corrupted. [VERIFIED: `shasum -a 256` / `md5 -q` in this session]

---

## Topic findings

### 1. Zenodo 3854034 structure, unit convention, and which sessions are M1-only

Covered exhaustively in "Dataset ground truth" above. Two points deserve isolating.

**The unsorted-unit convention.** Zenodo states: "First unit (u1) is the 'unsorted' unit, meaning it
contains the threshold crossings which remained after the spikes on that channel were sorted into
other units." [CITED: <https://zenodo.org/records/3854034>] This is a *residual*, so the total
threshold-crossing count for a channel is the sum over u1..u5, which is what `load_session` already
does. The three aggregation choices give materially different rates on `indy_20160630_01`:

| Aggregation | Mean rate/ch | Median | Max | Dead channels | Mean count / 20 ms bin |
|---|---|---|---|---|---|
| all units u1..u5 (what the loader does) | 13.82 Hz | 6.67 Hz | 51.89 Hz | 6 / 96 | 0.2765 |
| u1 only (residual hash) | 8.00 Hz | 4.31 Hz | 38.90 Hz | 6 / 96 | 0.1600 |
| u2..u5 only (sorted) | 5.82 Hz | 1.97 Hz | 31.54 Hz | 14 / 96 | 0.1165 |

Summing all units is correct and should be stated explicitly in the evidence artifact, because
choosing u1-only would cut every firing rate roughly in half and therefore move co-bps. Do not
change it. [VERIFIED: local parse]

**Sessions with `finger_pos` width 3 versus 6.** Both occur within the M1-only pool. The loader must
handle `(3, k)` and `(6, k)`. Slicing rows 1:3 works for both.

### 2. h5py MATLAB v7.3 dereference correctness

**The transpose direction is settled.** h5py reports `spikes.shape == (5, 96)`, i.e.
`(n_units, n_channels)`. MATLAB's documented `n x u` becomes `u x n` under HDF5 row-major storage.
The existing heuristic in `data.py`:

```python
if n_dim1 == CORTEX_CHANNEL_COUNT and n_dim0 != CORTEX_CHANNEL_COUNT:
    ref_array = ref_array.T
```

fires correctly on `(5, 96)` and correctly leaves an already-`(96, 5)` array alone. It is safe for
any session where exactly one axis is 96, which holds for every M1-only session (unit counts are 3
or 5). [VERIFIED: local parse]

**The symptom of a silently transposed load**, which D-20's fixture must reproduce: on a
192-channel file h5py gives `(3, 192)`; neither axis is 96, no transpose occurs, `num_channels`
becomes **3**, and the loader raises `ValueError: session ... yielded 3 channels, expected 96`. The
guard fires, so there is no silent corruption, but the message reports the *unit* count and gives
the operator no way to tell this is an M1+S1 file. The fix is to derive the width from
`chan_names.shape[1]` (authoritative, 96 or 192) and name the array set in the error.
[VERIFIED: remote probe of `indy_20160407_02`]

**The real defect: empty cells are truthy.** MATLAB does not write null references for empty cells.
It writes a reference to a real dataset carrying `MATLAB_empty`:

```
truthy=True shape=(2,) dtype=uint64 attrs=('H5PATH','MATLAB_class','MATLAB_empty')
```

`bool(ref)` is `True`, so `if not ref: continue` never fires; `f[ref][()]` returns `array([0, 0])`
or `array([0, 1])` (the MATLAB dimensions), `.ravel()` gives size 2, and the loader appends two
timestamps. On `indy_20160630_01`: 249 empty cells out of 480, injecting **498 spurious timestamps
with values 0.0 and 1.0 across 92 of 96 channels**. They are discarded today only because
`t_start = t[0] = 148.984 s`, so they fail `bin_spikes`'s `(t >= t_start)` filter. Any session whose
behavior clock starts below 1.0 s, or any refactor that sets `t_start = 0.0` or
`t_start = min(spike_time)`, converts this into a large artificial burst in bin 0.

The correct guard is the attribute, not the reference:

```python
dataset = f[ref]
if "MATLAB_empty" in dataset.attrs:
    continue
```

Corroborating documentation for the general mechanism: MathWorks notes that HDF5 in R2014b and
earlier could not create a zero-sized dataspace, so "H5 files created in those versions contain a
single 0, even when the variable is empty. If the size attribute of a variable is 0, you should
discard its value." [CITED: <https://monkeylogic.nimh.nih.gov/docs_HDF5Implementation.html>] The
`MATLAB_empty` attribute is the modern encoding of the same idea and is what this file uses.
[VERIFIED: local parse]

**One more small correctness note.** `bin_spikes` computes
`num_bins = floor((t_end - t_start) / bin_s)` and then clips out-of-range indices with
`np.clip(bin_idx, 0, num_bins - 1)`. On `indy_20160630_01` that folds the final 0.012 s of spikes
into the last bin. Negligible in magnitude but it is an assertion the fixture can pin. Separately,
6,076 spikes precede `t[0]` and 3,300 follow `t[-1]` (spike and behavior clocks do not coincide);
dropping them is correct because there are no labels outside the behavior window, and it is worth a
line in the evidence artifact. [VERIFIED: local parse]

### 3. Plausible firing-rate band for RD-02's regression test

**Do not pin a per-channel band.** Six of 96 channels on `indy_20160630_01` are completely silent
(zero spikes in 1,463 s) and nine are under 1 Hz. Any assertion of the form "every channel is
between X and Y Hz" fails on a correctly-parsed session. This is the trap D-02 is most likely to
walk into.

**Measured ground truth** on `indy_20160630_01`, all units, 20 ms bins, via the repo's own
`load_session`:

| Statistic | Value |
|---|---|
| per-channel mean rate | 13.76 Hz |
| per-channel median rate | 6.63 Hz |
| min / max | 0.000 / 51.65 Hz |
| p5 / p25 / p75 / p95 | 0.00 / 3.48 / 21.29 / 44.29 Hz |
| dead channels (0 Hz) | 6 / 96 |
| channels < 1 Hz | 9 / 96 |
| mean count per 20 ms bin (population) | 0.2751 |
| max count in any (bin, channel) | 5 |
| fraction of zero (bin, channel) entries | 0.787 |

[VERIFIED: local run of `ndt1.data.load_session`]

**Band I would defend**, as population statistics with an explicit dead-channel allowance:

| Assertion | Recommended bound | Why |
|---|---|---|
| population mean rate over live channels | `1.0 Hz <= mean <= 60.0 Hz` | Observed 13.76. Wide enough for session variation, tight enough that a factor-of-2 unit-aggregation error or a transposed load falls outside. |
| median per-channel rate | `0.5 Hz <= median <= 40.0 Hz` | Observed 6.63. Median is robust to the dead-channel tail. |
| max per-channel rate | `<= 200 Hz` | Observed 51.65. A hard physiological ceiling; 200 Hz sustained on a threshold-crossing channel means the parse is wrong. |
| live channels (rate > 0.1 Hz) | `>= 60 / 96` | Observed 87/96. Catches a deref that empties most channels. |
| max count in one 20 ms bin | `<= 20` | Observed 5. At 20 ms a count above 20 implies 1000 Hz. |
| fraction of zero entries | `0.3 <= frac <= 0.95` | Observed 0.787. Catches both an all-zero parse and a count-explosion. |

**Literature framing.** This dataset is threshold-crossing multiunit, not sorted single units. The
field-standard detection convention is a single negative threshold at -4.5x the RMS of the spike
band per electrode, and threshold crossings "typically reflect individual spikes from a small
handful of neurons," which is why per-channel rates run well above sorted single-unit rates.
[CITED: <https://arxiv.org/pdf/1610.05872> (Sussillo et al., "Making brain-machine interfaces robust
to future neural variability"); <https://www.biorxiv.org/content/10.1101/2019.12.13.862532v3.full>]
I did **not** find a single paper stating a canonical numeric Hz band for macaque M1 threshold
crossings that I would quote as authoritative, so the band above is derived from the measured
distribution on this dataset with generous margin, and that derivation should be stated in the test
docstring rather than dressed up as a literature constant. [ASSUMED: the bounds' width; the observed
values are VERIFIED]

### 4. NLB'21 mc_rtt protocol versus this repo's co-bps

This is where D-23's framing paragraph must be precise, and where CONTEXT.md is currently wrong.

**The mc_rtt session is `indy_20170202_02`, recorded 2017-02-02.** DANDI dandiset 000129's
`sub-Indy_desc-train_behavior+ecephys.nwb` asset carries
`wasGeneratedBy: {name: "20170202_02", startDate: "2017-02-02", description: "Data from monkey Indy
performing self-paced random target reaching task ..."}`.
[VERIFIED: <https://api.dandiarchive.org/api/assets/2ae6bf3c-788b-4ece-8c01-4b4a5680b25b/info/>]
That session id does not appear in Zenodo 3854034; the record's latest Indy session is
`indy_20170131_02`. [VERIFIED: Zenodo API file listing] So the manifest note and CONTEXT
`<specifics>` claim that `indy_20160630_01` is the mc_rtt session is false and must be corrected in
this phase (it is a decoder-owned surface under D-24).

**What NLB co-bps actually is**, from `nlb_tools` source:

- Trials are "continuous 600 ms snippets of the recording", submitted in 5 ms bins.
  [CITED: <https://ar5iv.labs.arxiv.org/html/2109.04463>]
- Neurons are **sorted units** split into 98 held-in and 32 held-out. Models see held-in spikes and
  must predict held-out neurons' rates. [CITED: same]
- `bits_per_spike(rates, spikes) = (nll_null - nll_model) / sum(spikes) / log(2)` where `nll_null`
  uses `np.nanmean(spikes, axis=all-but-last)`, i.e. the **per-neuron mean of the evaluation spikes
  themselves**. [VERIFIED: <https://raw.githubusercontent.com/neurallatents/nlb_tools/main/nlb_tools/evaluation.py>]
- Published mc_rtt baselines: Smoothing 0.147, GPFA 0.155, SLDS 0.165, NDT 0.160, AutoLFADS 0.192.
  [CITED: <https://ar5iv.labs.arxiv.org/html/2109.04463>]

**How ours differs**, point by point, for the D-23 paragraph:

| Axis | NLB'21 mc_rtt co-bps | This repo's `ndt1.metrics.co_bps` |
|---|---|---|
| Session | `indy_20170202_02` | `indy_2016*` M1-only sessions |
| Units | 130 sorted single units (98 held-in / 32 held-out) | 96 channels of summed threshold crossings |
| Bin | 5 ms | 20 ms |
| Segments | 600 ms trials, overlap allowed | 32-bin (640 ms) non-overlapping windows |
| What is held out | **neurons** (co-smoothing) | **random 25% of (bin, channel) positions** (masked reconstruction) |
| Scored over | held-out neurons, all timepoints | masked positions across all channels |
| Null rate source | mean of the **evaluation** spikes | mean of the **train** split |

The bits arithmetic itself matches: both are `(NLL_null - NLL_model) / (total masked spikes * ln 2)`
with a Poisson likelihood, and the `gammaln(n+1)` term nlb_tools includes cancels in the difference
exactly as PyTorch's `full=False` omission does. So the *units* are the same and the *protocols* are
not. The honest sentence is: "the same bits-per-spike arithmetic applied to a different held-out
construction on a different session at a different bin width; the NLB numbers are context for what
scale of value is meaningful, not a leaderboard comparison."

**One asymmetry worth disclosing.** Our null is fit on the train split; NLB's is fit on the eval
data. A null fit on the eval data is a *stronger* null, so a train-split null can inflate co-bps
whenever the test tail's mean rate differs from the train head's. On `indy_20160630_01` the test
tail's mean rate is **8.1% below** the train head's, which is exactly the direction that inflates.
Our choice is leakage-free and is the right gate under D-22; recommend also reporting the
NLB-convention (test-mean null) value in the metrics JSON as a drift-robust floor. That is inside
Implementer's Discretion (metrics JSON schema) and does not touch D-22's locked pass bar.
[VERIFIED: local parse + nlb_tools source]

### 5. Neural-to-kinematic lag

There is a directly citable, primary-source value for **this exact dataset family**:
`nlb_tools/make_tensors.py` sets `'lag': 140` for `mc_rtt`, meaning behavior is taken 140 ms after
the neural window. Sibling datasets use `mc_maze` 100 ms, `mc_maze_{large,medium,small}` 120 ms, and
`area2_bump` -20 ms (somatosensory, so neural activity *lags* movement, which is a nice internal
consistency check that the sign convention is what it looks like).
[VERIFIED: <https://raw.githubusercontent.com/neurallatents/nlb_tools/main/nlb_tools/make_tensors.py>]

Independent literature support: cross-correlation between the M1 activity envelope and hand velocity
peaks at -180 ms and -120 ms in two macaques, with neural activity leading.
[CITED: <https://www.pnas.org/doi/10.1073/pnas.2212227120>]

**Implication for D-08.** The 0-160 ms sweep in whole 20 ms bins is 0-8 bins and brackets NLB's
140 ms at bin 7. That is a defensible range. If the sweep selects something far from 5-8 bins
(100-160 ms), treat it as a signal that the label alignment or the sign is wrong rather than as a
discovery, and say so in the evidence. Note also the sweep interacts with the readout geometry:
`VelocityHead.forward` reads `rates[..., -1:]`, the last bin of the window, so "lag k" means pairing
the window ending at bin `i` with the velocity at bin `i + k`.

### 6. Multi-session pooling without session conditioning

There is no published number for "expected pooled-versus-per-session co-bps degradation on Indy",
and I will not invent one. What is defensible:

- Utah-array unit identity is not stable across days. "Action potentials identified by their
  extracellular waveforms may change within a single day, although some identified units can be
  identified consistently for weeks and even months," and performance instability is attributed to
  electrode drift plus neuroplasticity, producing feature inconsistency across days.
  [CITED: <https://pubmed.ncbi.nlm.nih.gov/29553484/> (Downey et al., "Intracortical recording
  stability in human brain-computer interface users")]
- Across the BrainGate/BrainGate2 corpus (2,319 sessions, 20 arrays, up to 7.6 years), arrays
  recorded spiking waveforms on 35.6% of electrodes with only a 7% decline over enrollment, so
  gross array failure is slow; the instability that matters here is per-channel tuning, not yield
  collapse. [CITED: <https://www.medrxiv.org/content/10.1101/2025.07.02.25330310v1>]
- A useful magnitude anchor from a model class that *does* pool: on 30 Indy sessions with 10 ms
  bins and 96-channel unsorted multiunit activity, single-session finger-velocity R2 is 0.633-0.717
  across GRU / Transformer / RWKV / Mamba, while multi-session training *raises* it to 0.720-0.838.
  [CITED: <https://arxiv.org/html/2406.06626v1>] That is behavior decoding, not reconstruction
  co-bps, and those models have far more capacity, but it does establish that pooling Indy sessions
  is not automatically destructive.

**What this means for D-15.** The reportable expectation is: pooled co-bps between the best and
worst per-session numbers, and LOSO co-bps below every in-pool number. A LOSO number that is near
zero or negative is a legitimate, publishable result meaning "channel identity did not transfer",
not a bug. Do not raise the training budget or reshape the pool chasing it (D-25, D-03).

**A concrete refinement.** If Open Question 1 is resolved toward the tight June-cluster option, the
sessions span nine days rather than three months and D-15's sentence must be rewritten, because a
nine-day span is a much weaker drift test and the LOSO number becomes correspondingly less
impressive as a generalization claim. If it is resolved toward a June-to-September span, D-15 stands
as written with "April to June 2016" corrected to the actual dates.

### 7. Ridge lambda and the held-out R2 formulation

**Lambda without a validation split.** D-09 keeps the closed-form ridge and D-14 forbids adding a
third split, so grid-searching lambda on held-out data would leak. Three defensible options, in
order of preference:

1. **Generalized cross-validation (GCV) on the train split.** Closed-form, no extra split, no
   leakage. For a fixed SVD of the centered design matrix, GCV over a log-spaced lambda grid costs
   one SVD plus O(grid) scalar work. This is what `sklearn.linear_model.RidgeCV(gcv_mode=...)` does
   and it is the standard answer to "select lambda with no validation set."
2. **K-fold CV over contiguous blocks of the train split only.** Contiguous, not shuffled, so it
   respects the temporal structure. More code, same guarantee.
3. **Fix lambda and report sensitivity.** Sweep lambda over a log grid on the train split, lock one
   value, publish the whole curve in the evidence exactly as D-08 does for lag. Simplest and most
   consistent with the phase's existing idiom.

Recommend option 3 for symmetry with D-08's lag sweep, with option 1 as the tie-breaker if the curve
is flat. Note the design matrix is 96 columns against tens of thousands of rows, so it is heavily
overdetermined and the result will be insensitive to lambda over orders of magnitude; the current
default `lam = 1.0` is very likely fine and the sweep will document that. [ASSUMED: insensitivity;
cheap to verify during execution]

**Held-out R2 versus a constant-mean null (D-10).** The correct formulation, per axis:

```
R2_axis = 1 - SS_res / SS_tot
SS_res  = sum_t (v_true[t, axis] - v_pred[t, axis])^2         over TEST bins
SS_tot  = sum_t (v_true[t, axis] - mean_TRAIN(v_true[:, axis]))^2
```

Two details that decide whether the number is honest:

- The null mean must come from the **train** split, mirroring `co_bps`'s train-split mean-rate null.
  Using the test set's own mean makes `SS_tot` the test variance and silently converts this into the
  textbook R2, which is a *different* (and easier) claim.
- Report per axis and pooled separately. The pooled figure should be
  `1 - sum_axes SS_res / sum_axes SS_tot`, not the mean of the two per-axis R2 values, because the
  two axes have different variance (on `indy_20160630_01`, `finger_pos` row 1 std 3.26 cm, row 2 std
  3.28 cm, so they are comparable here, but that is not guaranteed across sessions).

**Expectation setting, which matters for D-25.** The readout is a rank-2 linear map from 96
context-smoothed rate values at a single bin. Published R2 on this dataset in the 0.63-0.84 range
comes from GRU/Transformer/RWKV/Mamba sequence models with nonlinear readouts at 10 ms bins
[CITED: <https://arxiv.org/html/2406.06626v1>], and classic Wiener-filter decoders use many lagged
bins. A single-bin linear ridge on top of a masked-reconstruction encoder should be expected to land
well below that. A held-out R2 in the 0.1-0.4 range would be an unremarkable outcome for this
architecture and should be reported as-is, not treated as a defect. [ASSUMED: the specific 0.1-0.4
range; the reasoning is sound but I have no measurement of this exact configuration]

### 8. Verified `finger_pos` axis convention

Zenodo describes `finger_pos` as fingertip position in cm as `(z, -x, -y)` (or with three more
orientation columns), and `cursor_pos` as an affine transform of it with matrix
`[0, 0; -10, 0; 0, -10]`. [CITED: <https://zenodo.org/records/3854034>] Measured on
`indy_20160630_01`:

| Quantity | Value |
|---|---|
| `corr(cursor_pos[0], finger_pos[0])` | +0.2852 |
| `corr(cursor_pos[0], finger_pos[1])` | **-1.0000** |
| `corr(cursor_pos[1], finger_pos[2])` | **-1.0000** |
| `max abs(cursor_pos[0] - (-10 * finger_pos[1]))` | 2.09 mm |
| `max abs(cursor_pos[1] - (-10 * finger_pos[2]))` | 1.65 mm |
| `std(finger_pos[0])` (the z / depth axis) | 0.242 cm |
| `std(finger_pos[1])`, `std(finger_pos[2])` | 3.257, 3.279 cm |

[VERIFIED: local parse]

So the planar workspace pair is **h5py rows 1 and 2**, which correspond to MATLAB columns 2 and 3.
Taking "the first two axes" literally selects `(z, -x)`, mixing a near-static 0.24 cm depth channel
into the label. Ridge would fit it without crashing and the resulting R2 would be roughly halved,
with the vy axis effectively unlearnable. This is a silent-failure path with no exception.

Recommended handling: use `finger_pos[1:3]`, negate to recover true `(x, y)` in cm, take the finite
difference at 250 Hz, and aggregate into 20 ms bins per D-07. The negation is cosmetic for ridge (W
absorbs the sign) but matters for interpretability, for the sign of the shipped cursor velocity, and
for Phase 10's `R` fit from `z_decoded` versus `v_true` residuals, so do it once at the source and
document it. Alternatively, `cursor_pos` differs from `-10 * finger_pos[1:3]` by at most 2.1 mm and
is already in the cursor plane, but D-06 locks `finger_pos` as the source and `nlb_tools` does use
`finger_vel` for mc_rtt, so the locked choice is right; only the column indexing needs correcting.
[VERIFIED: <https://raw.githubusercontent.com/neurallatents/nlb_tools/main/nlb_tools/make_tensors.py>
line 45, `'behavior_field': 'finger_vel'`]

### 9. Measured training cost (sizes the runbook)

Measured on this machine, CPU, using the repo's real `NDT1ANE` (1,292,544 params), `random_mask`,
`masked_poisson_nll` and `AdamW(lr=2e-3, wd=0.01)` at batch 16, seq_len 32:

**148.9 ms per training step.**

| Pool | Train windows | Steps @ 12 epochs | Pooled run | LOSO 4 folds |
|---|---|---|---|---|
| `indy_20160630_01` alone | 1,829 | 1,380 | 3.4 min | 13.7 min |
| 2 currently-surviving (0627 + 0630) | 6,032 | 4,524 | 11.2 min | 44.9 min |
| 4 sessions, ~330k bins | 8,250 | 6,192 | 15.4 min | 61.5 min |

[VERIFIED: local timing]

The full evidence run, pooled plus LOSO plus the lag sweep plus the ridge fit, is roughly 1.5 hours
of CPU. That is comfortably a human-run runbook (D-21) and there is no reason to reach for MPS.

Two related facts for D-14: `load_session` parses the real 382 MB file in **0.2 s** and produces a
28 MB `(73161, 96)` float32 matrix, so I/O is not a constraint. And the real pool is **60-70x** the
synthetic 4,000 bins, not the "25-30x" D-14 estimates, which makes 12 epochs correspondingly more
gradient steps (4,524 versus 84) and makes the "clearly has not converged" branch of D-14 less
likely to fire.

### 10. CoreML 9.0 palettization and ANE re-measurement

**Nothing in the coremltools 9.0 release notes changes palettization semantics.** The 9.0 release
(2025-11-10) adds Python 3.13 support, int8 model I/O, model state read/write, iOS26/macOS26
deployment targets, an `AllowLowPrecisionAccumulationOnGPU` hint, PyTorch 2.7 support, extra
auto-added model metadata, and an `im2col` optimization. No palettization changes are listed.
[CITED: <https://api.github.com/repos/apple/coremltools/releases> tag 9.0]

**Defaults verified from the installed wheel** rather than the docs:

```
OpPalettizerConfig(mode='kmeans', nbits=None, lut_function=None,
                   granularity=PER_TENSOR, group_size=32, channel_axis=None,
                   cluster_dim=1, enable_per_channel_scale=False,
                   num_kmeans_workers=1, weight_threshold=2048)
```

[VERIFIED: `inspect.signature` under `uv run --project Decoder`, coremltools 9.0]

Three consequences the executor should know before measuring:

- `weight_threshold = 2048` skips any weight tensor with fewer than 2,048 elements. The velocity
  readout is `2 x 96 = 192` elements, so **the shipped model's velocity head is never palettized**.
  D-16's "R2 delta on the with-velocity model" is therefore entirely attributable to encoder
  palettization propagating through an unquantized head. Say so in the evidence.
- The **size ratio should reproduce 04-palettization-evidence.md's 3.471x almost exactly**, because
  the architecture, parameter count, and which tensors clear the threshold are all unchanged. A
  materially different ratio means the conversion config drifted, and is itself the finding.
- The **loss delta will not reproduce** 0.009114, because k-means centroids are fit to the actual
  weights and the real-data weights differ. That is expected, not a regression.

**ANE eligibility is a graph property.** `MLComputePlan.get_compute_device_usage_for_mlprogram_operation`
walks the compiled program's ops [CITED: <https://apple.github.io/coremltools/docs-guides/> /
Context7 `/apple/coremltools` `coremltools.models.md`]. Op count and op types are determined by the
module structure and the trace, not by weight values, so **226/226 with zero CPU-only should
reproduce exactly**. Any deviation means the traced graph changed, which is a real finding under
D-17 and should stop the phase rather than be papered over.

**The concrete version risk** is not palettization, it is the trace: the environment pairs
**torch 2.12.1 with coremltools 9.0, which warns "Torch version 2.12.1 has not been tested with
coremltools. You may run into unexpected errors. Torch 2.7.0 is the most recent version that has
been tested."** [VERIFIED: emitted on every `import coremltools` in this repo] Phase 5 shipped
through this same pairing, so the expectation is that it keeps working, but if `ct.convert` regresses
the cause is this, not the real data. Do not "fix" it by bumping coremltools mid-phase; the pin at
9.0 is a project convention.

**Determinism note for RD-05.** k-means palettization is stochastic in general. To keep the
committed delta reproducible, fix the seed if the API exposes one and otherwise record that the
delta is measured once and re-running may shift the last digits. `num_kmeans_workers=1` (the default)
at least removes multi-process nondeterminism.

### 11. CI mechanics for D-18 and D-19

**uv on GitHub Actions.** `astral-sh/setup-uv` handles cache save and restore itself; do not hand-roll
an `actions/cache` step for it the way the repo does for SwiftPM and DerivedData.

```yaml
- name: Set up uv (Decoder Python subsystem)
  uses: astral-sh/setup-uv@v8
  with:
    enable-cache: true
    cache-dependency-glob: |
      Decoder/uv.lock
      Decoder/pyproject.toml
    cache-suffix: decoder-py312
    prune-cache: true
```

- `enable-cache` defaults to `auto`, which enables caching on GitHub-hosted runners except for
  `release`, tag pushes, `pull_request_target` and `workflow_run`. Set it explicitly to `true` for
  this repo's `push` + `pull_request` triggers.
- The default `cache-dependency-glob` already covers `pyproject.toml` and lock files, but scoping it
  to `Decoder/` keeps the cache from invalidating on unrelated repo churn.
- Default cache dir on macOS is `/tmp/setup-uv-cache`; the action will not override an existing
  `UV_CACHE_DIR` or a `cache-dir` set in config.
- `prune-cache: true` strips pre-built wheels before save, which matters because `torch` and
  `coremltools` are large.

[CITED: <https://github.com/astral-sh/setup-uv/blob/main/docs/caching.md>]

**The blocking job.** The quick suite needs no dataset and no Xcode. Two shapes are viable:

- A step inside the existing `build-and-lint` job, matching how every `*-policy.sh` gate is wired
  today (lines 203-409 of `ci.yml`). Simplest, and keeps one job.
- A separate `decoder-python` job on `macos-15`. Runs in parallel with the 30-minute Xcode build, so
  it fails fast on Python regressions, at the cost of a second runner.

Recommend the separate job: the existing job is already near its 30-minute timeout with Rust
toolchain installation, SwiftPM, DerivedData and seven policy gates, and the Python suite has no
dependency on any of it.

```yaml
  decoder-python:
    runs-on: macos-15
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v8
        with: { enable-cache: true, cache-dependency-glob: "Decoder/uv.lock", prune-cache: true }
      - name: Sync Decoder env (dev extra is REQUIRED - see AGENTS.md)
        run: uv sync --project Decoder --extra dev
      - name: Decoder quick suite (no dataset, no training)
        run: uv run --project Decoder pytest Decoder/tests -m "not slow" -q
      - name: Decoder provenance policy gate (D-19)
        run: |
          ./Tools/scripts/decoder-policy.sh
          ./Tools/scripts/decoder-policy.sh --self-test
```

**The `decoder-policy.sh` idiom.** `bps-policy.sh` is the closest template and should be copied
structurally: environment-variable scope overrides (`BPS_SWIFT_FILE` / `BPS_JSON_FILE` become
`DECODER_MANIFEST_FILE` / `DECODER_METRICS_FILE`), a `require_fixed_in_file` / `require_re_in_file`
pair, a `scan()` that returns nonzero if any assertion fails, a `SELF` variable so `--self-test` can
re-invoke the script against synthetic stand-ins, and an `assert_exit` helper that writes a clean
tree (must exit 0), then mutates exactly one thing per case (must exit 1). D-19's three assertions
map onto three negative-control cases: reintroduce a `"PENDING"` sha256, strip the `data_source` key
from the metrics JSON, and perturb one checksum so the manifest and metrics disagree.

One caveat specific to D-19(c): the cross-check between the metrics JSON's recorded checksums and the
manifest is a JSON comparison, not a grep. `bps-policy.sh` shells out to nothing; `check_refit_uplift.py`
is the precedent for "bare `python3` CI guard reading a committed JSON" and the runner has `python3`
with no extra tooling (ci.yml line 372). Use that split: bash for the token greps and self-test
scaffolding, a small bare-`python3` helper for the checksum set comparison.

### 12. Fallout in existing tests when real data lands

`Decoder/tests/test_heldout_cobps.py::_load_binned` iterates `sorted(_DATA_DIR.glob("*.mat"))` and
calls `load_session(mat)` **without catching `ValueError`**. The moment a 192-channel session sits in
`Decoder/data/`, `indy_20160407_02.mat` sorts first and the slow test **errors** instead of falling
back. `Decoder/tests/test_data.py::test_load_session_real_mat` uses `next(_DATA_DIR.glob("*.mat"))`
and has the same problem. Both need to become multi-session aware and to skip-or-exclude sessions
that fail the width gate, which is also what CONTEXT's `<code_context>` asks for ("extend it to the
multi-session case rather than rewriting it"). [VERIFIED: source read]

---

## Ranked pitfalls

Ranked by probability x cost. Each has a mitigation an executor can act on directly.

### P1. Two manifested sessions are 192-channel M1+S1 (probability: certain; cost: high)

`indy_20160407_02` and `indy_20160411_01` both have `chan_names` running `M1 001` to `S1 096`. The
loader will reject them. Only two of four sessions survive, so D-03's "fewer than three survive"
substitution branch fires on day one.

**Mitigation:** resolve Open Question 1 in Wave 1, before any download. Replace both entries with
confirmed M1-only sessions from the table in "Dataset ground truth", re-pin checksums, and record the
exclusion rationale in the manifest note as D-03 requires. Do not attempt to slice the first 96
channels out of a 192-channel file: the M1 subset of an M1+S1 session is a different array
configuration and mixing it into the pool is exactly the "reshape the dataset" move D-03 forbids.

### P2. `download_indy.py` cannot tell a file from an error page (probability: low; cost: high)

The script writes whatever bytes the URL returns, hashes them, and fills `"PENDING"` with that hash.
There is no content-type check, no size check, and no magic-byte check. A Zenodo maintenance page, a
rate-limit HTML body, or a truncated transfer would be recorded as the canonical checksum of a
session, and every downstream number would be pinned to garbage. I verified the URL works today
(`content-type: application/octet-stream`, `content-length: 382243800`, first bytes
`MATLAB 7.3 MAT-f`) but that is a point-in-time observation.

**Mitigation:** three cheap assertions in `_process_session`, all of which also become the RD-01
negative controls: (a) the first 16 bytes start with `MATLAB 7.3 MAT-f`; (b) the byte size equals a
new `size_bytes` field in the manifest (values in the ground-truth table); (c) the Zenodo-published
md5 (also in the ground-truth table) matches. (c) is a genuinely independent cross-check because it
comes from the publisher rather than from our own first fetch.

### P3. `MATLAB_empty` cells dereferenced as spikes (probability: certain; cost: medium today, high after any refactor)

The `if not ref: continue` guard never fires. 498 spurious timestamps at t = 0.0 and 1.0 across 92
channels on `indy_20160630_01`. Currently masked by `t_start = 148.984 s`.

**Mitigation:** switch the guard to `if "MATLAB_empty" in f[ref].attrs: continue`, and make D-20's
fixture carry both empty-cell payloads (`[0, 0]` and `[0, 1]`) plus a `t` vector starting at 0.0 so
the negative control provably bites. Assert in the fixture test that the binned matrix has exactly
zero counts attributable to the empty cells.

### P4. `finger_pos` "first two axes" selects (z, -x) (probability: high if taken literally; cost: high)

D-06's wording, read literally, picks the depth axis. No exception is raised; R2 quietly degrades.

**Mitigation:** pin `finger_pos[1:3]` (h5py rows 1 and 2) with a fixture assertion, and add a
one-line sanity check in the loader or the evidence script: `abs(corr(cursor_pos[0], -10*finger_pos[1]))
> 0.99`. If a session ever fails that, the axis convention changed and the run should stop.

### P5. Existing tests crash rather than skip on a rejected session (probability: certain once data lands; cost: medium)

`_load_binned` and `test_load_session_real_mat` both grab the alphabetically-first `.mat` and do not
handle `ValueError`.

**Mitigation:** make both iterate every `.mat`, catch the width `ValueError` explicitly (never a bare
`except`, per the ruff BLE gate), collect the sessions that load, and skip only if none do. This is
required for D-11's pooled multi-session training anyway.

### P6. Per-channel firing-rate band fails on dead channels (probability: high; cost: medium)

Six of 96 channels are silent. A naive `assert (rates > 0.5).all()` fails on correct data, which then
gets "fixed" by loosening the band until it stops asserting anything useful.

**Mitigation:** assert population statistics plus a dead-channel allowance, per the table in
Section 3. Pin the band from the *measured* values with margin, and put the derivation in the test
docstring so a future reader knows it is empirical rather than a literature constant.

### P7. Cross-session pooling degrades and gets mistaken for a bug (probability: moderate; cost: medium)

A LOSO co-bps near zero is a legitimate outcome of pooling raw channel indices across sessions.

**Mitigation:** write D-15's assumption paragraph into `09-training-evidence.md` **before** the run,
not after, so the framing is not retrofitted to whatever number appears. Include the per-session
channel-yield table (D-04) so a reader can see the drift directly.

### P8. Train-split null inflates co-bps under drift (probability: moderate; cost: medium)

Measured within-session drift on `indy_20160630_01` is -8.1% in mean rate from train head to test
tail, the direction that makes the train-split-mean null worse and co-bps larger.

**Mitigation:** report both nulls in the metrics JSON. The train-split null remains the D-22 gate;
the test-mean (NLB-convention) null is disclosed alongside as the drift-robust floor.

### P9. torch 2.12.1 is outside coremltools 9.0's tested range (probability: low; cost: high if it fires)

Every `import coremltools` warns. Phase 5 shipped through the same pairing.

**Mitigation:** run the conversion smoke early in the phase, before the long training run, so a
conversion regression is discovered while it is still cheap. If it fires, the fix is a torch pin, not
a coremltools bump (9.0 is a project convention).

### P10. Edge-bin clipping and out-of-window spikes (probability: certain; cost: low)

`np.clip` folds the trailing 0.012 s into the last bin; 6,076 spikes precede `t[0]` and 3,300 follow
`t[-1]` and are dropped.

**Mitigation:** both behaviors are correct. Assert them in the fixture so they are intentional, and
put the dropped-spike count in the evidence artifact's per-session table.

### P11. Downloading 2.6 GB (or 1.8 GB) repeatedly (probability: moderate; cost: low)

Re-running the download after a manifest edit re-verifies rather than re-fetches only when the file
is already at `Decoder/data/<id>.mat`.

**Mitigation:** `indy_20160630_01.mat` is already fetched, verified against Zenodo's md5, and its
sha256 is recorded in this document. Move it rather than re-fetching. Note that `_process_session`
skips the download when `dest.exists()`, so a partially-written file from an interrupted transfer
will be checksummed as-is and either poison a `"PENDING"` entry or fail verification; the size check
from P2 fixes that too.

---

## Project constraints (from AGENTS.md)

| Directive | Where it binds this phase |
|---|---|
| `Decoder/` requires the `dev` extra: `uv sync --project Decoder --extra dev` before any pytest run, or a bare `uv run pytest` fails with a misleading `No module named numpy` | Every runbook command, and the D-18 CI job's first step |
| `coremltools` pinned at 9.0 | RD-05 / RD-06. Do not bump to resolve the torch-version warning |
| Training/eval dataset lives in gitignored `Decoder/data/`, materialized from the committed checksum manifest, never committed | RD-01. Also why D-20's fixture is synthetic |
| Evidence discipline: any published number is a committed `*-evidence.md` with machine, pinned wheel versions, seed, and a reproducible runbook, labeled with device and method | D-21, `09-training-evidence.md` |
| A number measured on synthetic data is labeled synthetic; a Mac number is not presented as an iPad-M4 number | D-17, D-24 |
| No bare or blind `except` anywhere in Decoder Python (ruff BLE gate) | The `MATLAB_empty` fix, the multi-session test fallback in P5 |
| Workflow enforcement: start work through a donny command before Edit/Write | Execution, not research |
| Immutability, files under 800 lines, minimal diffs, no drive-by reformatting | `data.py` amendments should be surgical: the empty-cell guard, the `finger_pos` read, and the docstring correction D-05 mandates |

---

## Validation Architecture

### Test framework

| Property | Value |
|----------|-------|
| Framework | `pytest` 8.x (declared in `Decoder/pyproject.toml` `[project.optional-dependencies].dev`) |
| Config file | `Decoder/pyproject.toml` (`[tool.pytest.ini_options]`, `testpaths = ["tests"]`, marker `slow`) |
| Env bootstrap (REQUIRED first) | `uv sync --project Decoder --extra dev` |
| Quick run command | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` |
| Full suite command | `uv run --project Decoder pytest Decoder/tests -q` |
| Estimated runtime | quick ~15-30 s (structural, fixture, manifest, metric asserts; no dataset, no training); full ~minutes plus the excluded human-run evidence runs |
| Gate scripts | `Tools/scripts/decoder-policy.sh` (new, D-19) plus its `--self-test`, mirroring `bps-policy.sh` |

**Tier split (Phase 2 D-18 / Phase 6 D-10 / this phase's D-21, unchanged).** CI gates correctness
and structure and NEVER trains, NEVER downloads the dataset, and NEVER asserts a measured number.
Measured numbers are committed evidence produced by a human-run runbook. Every automated command
below runs green on a checkout with an empty `Decoder/data/`.

### Phase requirements to test map

| Req | Behavior proved | Tier | Automated command / artifact | Negative control that proves it bites |
|---|---|---|---|---|
| RD-01a | Manifest has zero `"PENDING"` sha256 entries | CI-blocking | `./Tools/scripts/decoder-policy.sh` | `--self-test` writes a stand-in manifest with one `"PENDING"` and asserts exit 1 |
| RD-01b | Every manifest session declares `id`, `url`, `sha256`, `size_bytes`, `md5`, direct (non-`/api/`) URL | CI-blocking | `pytest -k test_manifest` (extend existing `test_manifest.py`) | add a stand-in session with an `/api/` URL and a missing `size_bytes`; both must fail |
| RD-01c | Integrity gate raises on a corrupted `.mat` | CI-blocking | `pytest -k test_download_integrity_gate` (new): write a temp manifest + a temp file whose bytes do not match a committed sha256, assert `_process_session` raises `ValueError` | flip the assertion to a matching checksum; the test must then pass, proving it discriminates rather than always raising |
| RD-01d | Downloader rejects a non-MATLAB payload (P2) | CI-blocking | same test module: feed a file whose first bytes are `<!DOCTYPE html>` and assert `ValueError` | feed real `MATLAB 7.3 MAT-f` magic bytes; must not raise |
| RD-02a | Cell-array dereference skips `MATLAB_empty` cells | CI-blocking | `pytest -k test_fixture_empty_cells` against the D-20 committed fixture | fixture generator variant that omits the `MATLAB_empty` attribute must make the count assertion fail |
| RD-02b | Channel axis transpose is correct; a 192-channel structure raises with an informative message | CI-blocking | `pytest -k test_fixture_channel_axis` | fixture written as `(96, u)` and as `(u, 192)`; the first must load, the second must raise naming 192 |
| RD-02c | `finger_pos` planar pair is rows 1-2, not 0-1 (P4) | CI-blocking | `pytest -k test_fixture_finger_pos_axes`: fixture with a near-constant row 0 and two varying rows; assert the extracted labels are rows 1-2 | make the extractor take rows 0-1; the near-constant-axis assertion must fail |
| RD-02d | 20 ms binned per-channel rates fall in the pinned plausible band | CI-blocking (fixture) + evidence (real) | `pytest -k test_firing_rate_band` runs the band function against the fixture; the real-session numbers go in `09-training-evidence.md` | fixture variant with 10x inflated timestamps density must fall outside the band |
| RD-02e | All selected real sessions load end to end | evidence | `uv run --project Decoder python Decoder/scripts/report_sessions.py` (new, Implementer's Discretion) emitting the per-session channel-yield table | a session that fails the width gate must appear in the excluded list with its measured width |
| RD-03a | Held-out chronological-tail co-bps on real spikes beats the train-split mean-rate null | evidence (human-run) | `uv run --project Decoder pytest -m slow -k test_heldout_cobps -q` with real `.mat` present; number transcribed into `09-training-evidence.md` + metrics JSON | the same test with a shuffled (non-chronological) split must produce a materially different number; record it as the leak-detection control |
| RD-03b | The committed margin is re-derived from the observed value, not inherited | CI-blocking | `pytest -k test_cobps_margin_documented`: assert `CO_BPS_MARGIN` differs from the Phase-4 synthetic 0.05 constant and that the metrics JSON records both the observed value and the margin rationale string | set the margin back to 0.05 with no rationale key; must fail |
| RD-03c | Published number is traceable to the bytes it came from | CI-blocking | `./Tools/scripts/decoder-policy.sh` assertions (b) and (c) | `--self-test` strips `data_source` from a stand-in metrics JSON (exit 1) and perturbs one checksum so manifest and metrics disagree (exit 1) |
| RD-04a | Per-session held-out co-bps reported for every pooled session | evidence | metrics JSON has one entry per session id; `pytest -k test_metrics_schema` asserts the key set matches the manifest's session ids | drop one session from the metrics JSON; the schema test must fail |
| RD-04b | Full four-fold LOSO rotation reported with mean and spread | evidence | metrics JSON `loso` array of length == number of sessions; schema test asserts the length and that each fold's `held_out_session` is unique | a 3-fold array must fail the length assertion |
| RD-05a | Palettized package exists and is smaller; ratio recorded | evidence + CI structure | existing `pytest -m slow -k test_palettized_package`; ratio into the metrics JSON | n/a (existing Phase-4 control retained) |
| RD-05b | Palettization delta measured on BOTH models (Poisson-NLL on reconstruction, R2 on with-velocity) | evidence | metrics JSON carries `palettization.nll_delta` and `palettization.r2_delta`, each with the model it was measured on | schema test fails if either key or its `model` label is absent |
| RD-06a | 226/226 ops ANE-eligible, zero CPU-only, on the with-velocity real-data model | evidence (M5 Pro corroborating; iPad-M4 optional, never auto-approved) | existing `pytest -m slow -k test_ane_compute_plan`; result into `09-ane-eligibility-evidence.md` | existing Phase-5 control retained: a deliberately CPU-only op must make the count assertion fail |
| RD-06b | Decoder p99 under 2 ms with real weights | evidence (device-labeled) | `CortexDecoderBench` on the regenerated `.mlpackage`; number into the evidence artifact with its device label | n/a (measurement, device-gated per D-17) |
| RD-06c | Python quick suite runs as a blocking CI gate | CI-blocking | the `decoder-python` job in `ci.yml` | introduce a deliberately failing quick test on a scratch branch and confirm the job goes red before merging the real change |

### Sampling rate

- **Per task commit:** `uv sync --project Decoder --extra dev && uv run --project Decoder pytest Decoder/tests -m "not slow" -q`
- **Per wave merge:** `uv run --project Decoder pytest Decoder/tests -q` plus
  `./Tools/scripts/decoder-policy.sh && ./Tools/scripts/decoder-policy.sh --self-test`
- **Phase gate:** full suite green, `09-training-evidence.md` + metrics JSON committed, ANE and
  palettization evidence re-derived, then `/donny-verify-work`
- **Max feedback latency:** ~30 s for the quick suite

### Wave 0 gaps

Test infrastructure exists (pytest 8, 21 test modules, `slow` marker, `conftest.py`). The gaps are
fixtures and gate scaffolding, not framework installation.

- [ ] `Decoder/tests/fixtures/tiny_v73.mat` plus its generator script (D-20). Must contain: `spikes`
      as an object-reference array with both `MATLAB_empty` payload shapes (`[0,0]` and `[0,1]`), a
      `t` vector **starting at 0.0** so the P3 negative control can bite, and a `finger_pos` with a
      near-constant row 0 and two varying rows so the P4 control can bite. Generate with `h5py`
      writing `MATLAB_class` / `MATLAB_empty` attributes and a `#refs#` group. Covers RD-02a/b/c/d.
- [ ] `Tools/scripts/decoder-policy.sh` + `--self-test`, structurally copied from `bps-policy.sh`,
      with a small bare-`python3` helper for the checksum set comparison (the
      `check_refit_uplift.py` precedent). Covers RD-01a, RD-03c.
- [ ] `decoder-python` job in `.github/workflows/ci.yml` with `astral-sh/setup-uv@v8`. Covers RD-06c.
- [ ] Multi-session fallback in `test_heldout_cobps.py::_load_binned` and
      `test_data.py::test_load_session_real_mat` (P5). Blocks every real-data test the moment data
      lands.
- [ ] Metrics JSON schema plus `test_metrics_schema.py`. Covers RD-04a/b, RD-05b, RD-03b.
- [ ] Manifest correction to a genuine M1-only session set, with `size_bytes` and `md5` fields
      added (P1, P2, RD-01b). This is Wave 0 because everything downstream depends on it.

### Manual-only verifications

| Behavior | Requirement | Why manual | Instructions |
|---|---|---|---|
| Real-data pooled + LOSO training run | RD-03, RD-04 | ~1.5 h CPU; produces the committed numbers, never a CI gate (D-21) | `uv sync --project Decoder --extra dev`; `uv run --project Decoder python Decoder/scripts/download_indy.py`; `uv run --project Decoder pytest -m slow -q`; transcribe into `09-training-evidence.md` + metrics JSON |
| Lag sweep (0-160 ms) on the TRAIN split | RD-03 (D-08) | Sweep over 9 offsets; the full curve is published, not just the argmax | script or slow test, Implementer's Discretion; record every swept value |
| Integrity negative control on a real fetched file | RD-01 | Requires the 1.8-2.6 GB dataset present | copy a fetched `.mat`, flip one byte, re-run `download_indy.py`, capture the `ValueError` transcript in the evidence artifact |
| Decoder p99 with real weights on device | RD-06 | Hardware-gated; M5 Pro corroborating, iPad-M4 canonical **never auto-approved** (D-17, and the standing device-checkpoint rule) | `CortexDecoderBench` against the regenerated `.mlpackage`; label the device explicitly |

---

## Environment availability

| Dependency | Required by | Available | Version | Fallback |
|---|---|---|---|---|
| `uv` + `Decoder` venv | everything | yes | CPython 3.12, resolved | - |
| `h5py` | RD-02 | yes | 3.16.0 | - |
| `numpy` | all | yes | 2.4.6 | - |
| `torch` | RD-03, RD-04 | yes | 2.12.1 (CPU) | - |
| `coremltools` | RD-05, RD-06 | yes | 9.0 (pinned) | - |
| `pytest` | all | yes | 8.x via `--extra dev` | - |
| Zenodo record 3854034 reachable | RD-01 | yes, verified 2026-08-30 | `content-type: application/octet-stream`, correct `content-length`, `MATLAB 7.3 MAT-f` magic | none; a Zenodo outage blocks RD-01 |
| Disk for the dataset | RD-01 | must be checked | 1.77 GB (recommended set) to 2.60 GB (as-manifested) | pick the smaller session set |
| `python3` on the CI runner (for the D-19 checksum helper) | RD-01, RD-03 | yes, preinstalled on `macos-15` | per `ci.yml` line 372 precedent | - |
| iPad Pro M4 | RD-06 canonical p99 | **no** | - | M5 Pro corroborating, canonical deferred to HUMAN-UAT, never auto-approved (D-17) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** iPad Pro M4 (documented deferral, unchanged from Phases 5-8).

---

## Security domain

`security_enforcement` is absent from `.planning/config.json`, so it is treated as enabled.

### Applicable ASVS categories

| ASVS category | Applies | Standard control |
|---|---|---|
| V2 Authentication | no | No auth surface; offline dataset ingest and local training |
| V3 Session management | no | No sessions |
| V4 Access control | no | Single-user, on-device, no multi-tenancy |
| V5 Input validation | **yes** | Every field read out of an untrusted `.mat` is validated before use: channel width against `CORTEX_CHANNEL_COUNT`, `t` non-empty and monotone, `finger_pos` row count in {3, 6}, spike-timestamp dtype float64. Explicit `ValueError` on violation, never a bare `except` |
| V6 Cryptography | **yes** | SHA-256 via `hashlib` (stdlib) for manifest pinning; the Zenodo-published md5 is a **transport cross-check only**, never a security control (md5 is broken for collision resistance). Do not present md5 as an integrity guarantee in the evidence artifact |
| V12 File and resource | **yes** | Streamed 1 MiB reads in `download_indy.py` and `_sha256_of`; the `wf` array is never opened (T-04-02-02); path handling stays under `Decoder/data/` |
| V14 Configuration | **yes** | `Decoder/data/`, `checkpoints/`, `*.pt`, `*.mlpackage` remain gitignored; the phase does not change the artifact policy |

### Threat patterns carried forward and extended

| Pattern | STRIDE | Mitigation | Status this phase |
|---|---|---|---|
| T-04-02-01 download integrity (MITM / corrupted mirror) | Tampering | Committed SHA-256, verified on every re-run, `ValueError` on mismatch | **Strengthened**: add size and magic-byte checks (P2). The current script would checksum an HTML error page as canonical |
| T-04-02-02 `wf` memory DoS | DoS | `load_session` never opens `wf` | Unchanged. D-05 adds `finger_pos` (2.9-17.6 MB) which is bounded and safe |
| T-04-02-03 channel width divergence | Tampering / integrity | 96-channel gate raising `ValueError` | **Fires for real this phase** (P1). Improve the message to report the true width from `chan_names` |
| T-04-04-01 checkpoint pickle | RCE | Checkpoints are `state_dict` only, produced locally, gitignored | Unchanged |
| T-04-04-03 seed determinism | Repudiation | `seed = 0` throughout; evidence records it | **Extend** to the k-means palettization step (Section 10), which is the one remaining nondeterministic stage |
| **New:** published number decoupled from the bytes that produced it | Repudiation | `decoder-policy.sh` assertions (b) and (c) tie the metrics JSON to the manifest checksums | New this phase (D-19) |
| **New:** untrusted HDF5 object-reference traversal | Tampering | Only `spikes`, `t`, `finger_pos`, `chan_names` are read; `#refs#` is never enumerated directly; every dereferenced payload is shape- and dtype-checked before use | New this phase (the `MATLAB_empty` defect is the concrete instance) |

---

## Assumptions log

| # | Claim | Section | Risk if wrong |
|---|---|---|---|
| A1 | The recommended firing-rate band widths (mean 1-60 Hz, median 0.5-40 Hz, >= 60/96 live channels) generalize to the other selected sessions | 3 | A correctly-parsed session fails RD-02's gate and gets wrongly excluded under D-03. Cheap to falsify: run the band function on every session before pinning the constants |
| A2 | A single-bin linear ridge readout will land in roughly R2 0.1-0.4 on real data | 7 | If it lands far lower, D-25's "low honest number completes the phase" is doing more work than expected; if far higher, double-check for label leakage through the lag alignment |
| A3 | Ridge lambda is insensitive over orders of magnitude given 96 columns against tens of thousands of rows | 7 | Only affects which lambda-selection option is worth the code. The D-08-style published sweep makes this self-correcting |
| A4 | k-means palettization is nondeterministic enough to move the committed delta between runs | 10 | If it is in fact deterministic, the "measured once" caveat is unnecessary but harmless. Verify by running `palettize_weights` twice and diffing |
| A5 | Sessions I probed remotely but did not fully download parse cleanly end to end (I read headers, not the full `spikes` payload) | Dataset ground truth | A substitute session could still fail on a payload-level anomaly. D-03's exclusion path covers it, but budget for one more substitution |
| A6 | `indy_20170202_02` genuinely is not in Zenodo 3854034 under any alternate name | 4 | Only affects the D-23 framing sentence. The record's 37 Indy filenames are enumerated and none is `20170202`, so this is close to VERIFIED; I could not check other Zenodo records because their API returned 403 during this session |

---

## Open questions

### OQ1. Which four sessions? (blocks Wave 1; planner must decide)

Two of the four manifested sessions fail the 96-channel gate, so under D-03 the substitution branch
fires. Three viable sets, all confirmed M1-only:

| Option | Sessions | Download | Total 20 ms bins | Calendar span | Trade-off |
|---|---|---|---|---|---|
| A: tight June cluster | 0622, 0624, 0627, 0630 | 2.57 GB | 388,790 | 9 days | Largest data volume; all `finger_pos` width 6. But a 9-day span makes the LOSO generalization claim weak and forces D-15's "April to June 2016" sentence to be rewritten downward |
| **B (recommended)** | 0624, 0627, 0630, 0915 | **1.77 GB** | 285,359 | **83 days** | Keeps both currently-surviving sessions, closest to the roadmap's "~1.5 GB", genuine multi-month LOSO span, and exercises both `finger_pos` widths (6 and 3) which is a correctness feature |
| C: cheapest, widest | 0630, 0915, 0921, 1005 | 0.68 GB | 128,920 | 97 days | Smallest download and widest span, but drops the 168k-bin `indy_20160627_01`, cutting the pooled training set by more than half |

**Recommended default: Option B.** It preserves the two sessions the manifest already gets right,
lands nearest the roadmap's stated size, gives D-15 a span worth making a claim about, and forces the
`finger_pos` k x 3 / k x 6 branch to be exercised rather than assumed. Whichever is chosen, the
manifest note must record why `indy_20160407_02` and `indy_20160411_01` were dropped (192-channel
M1+S1, `chan_names` `M1 001` .. `S1 096`) as D-03 requires.

### OQ2. Does D-15's assumption paragraph need rewriting?

D-15 says "sessions spanning April to June 2016". Under any option in OQ1 that is now wrong: the
April sessions are all 192-channel. Under Option B the span is 2016-06-24 to 2016-09-15.

**Recommended default:** rewrite the span to the actual dates of the chosen set and keep the
substance (raw channel pooling assumes stable channel-to-neuron identity; NDT2's session
conditioning is what relaxes it; a pooled number below the per-session numbers is expected). This is
a factual correction inside a locked decision's rationale, not a change of decision.

### OQ3. How should D-06's and D-23's factual errors be corrected?

Two claims in CONTEXT.md are false: `finger_pos`'s "first two axes (x, y)" (they are `(z, -x)`), and
"`indy_20160630_01` is the mc_rtt benchmark session" (it is `indy_20170202_02`, not in this record).
Neither invalidates the underlying decision: `finger_pos` remains the right label source because
`nlb_tools` uses `finger_vel` for `mc_rtt`, and D-23's "cite as context, not comparison" framing
becomes *more* correct once the session-identity claim is dropped.

**Recommended default:** the planner carries the corrections forward in the plans and the evidence
artifact, and fixes the same false claim in `Decoder/manifests/indy_sessions.json`'s `note` field
(a decoder-owned surface, in scope under D-24). Do not silently leave the manifest note asserting the
mc_rtt identity, because `decoder-policy.sh` will then be enforcing a manifest that contains a false
statement.

### OQ4. Where does the metrics JSON live, and does it carry both nulls?

Implementer's Discretion covers the schema and location. Two things worth deciding once:

**Recommended default:** `.planning/phases/09-.../09-decoder-metrics.json`, mirroring
`08-.../webgrid_bps.json`, so `decoder-policy.sh` can point at it the way `bps-policy.sh` points at
its artifact. Carry both the train-split null co-bps (the D-22 gate) and the test-mean null co-bps
(the NLB-convention drift-robust floor, Section 4), each explicitly labeled.

### OQ5. Separate CI job or a step in `build-and-lint`?

**Recommended default:** a separate `decoder-python` job (Section 11). `build-and-lint` is already at
a 30-minute timeout with the Rust toolchain, SwiftPM, DerivedData and seven policy gates, and the
Python suite shares none of that. The `decoder-policy.sh` gate step goes in the same new job so the
provenance check runs next to the tests it protects.

---

## Main-thread-gated research

**None.** Everything in this document came from HTTP sources, the Zenodo REST API, GitHub raw files,
the DANDI API, Context7, or direct local parsing of a downloaded dataset file under the project's own
`uv` environment. No source required a logged-in browser. The one HTTP failure encountered (Zenodo's
API returning 403 for a record *search* query, noted in A6) does not change any conclusion; the
record listing for 3854034 itself fetched cleanly and is the source for every file-level claim.

---

## Sources

### Primary, verified in this session by direct measurement

- Local parse of `indy_20160630_01.mat` (sha256 `2ca8f6b7...03ef6a8`, md5 matching Zenodo's published
  `197413a5339630ea926cbd22b8b43338`) with h5py 3.16.0: field shapes, `MATLAB_empty` cell
  representation, unit-aggregation firing rates, `finger_pos` axis correlations, `chan_names`.
- Remote HDF5 header probes over HTTP Range of 11 further Indy sessions: channel counts,
  `chan_names` prefixes, `finger_pos` widths, durations.
- End-to-end run of the repo's own `ndt1.data.load_session` on the real file (0.2 s, `(73161, 96)`).
- Training-step timing with the repo's own `NDT1ANE` / `masked_poisson_nll` / `AdamW` (148.9 ms/step).
- `inspect.signature(OpPalettizerConfig.__init__)` under the installed coremltools 9.0.

### Primary, cited

- Zenodo record 3854034, O'Doherty, Cardoso, Makin, Sabes 2020, "Nonhuman Primate Reaching with
  Multichannel Sensorimotor Cortex Electrophysiology", CC-BY-4.0 -
  <https://zenodo.org/records/3854034> and <https://zenodo.org/api/records/3854034> (file list,
  sizes, md5 checksums, field descriptions, unsorted-unit convention, 96 vs 192 channels)
- DANDI dandiset 000129 (NLB'21 MC_RTT), asset metadata identifying session `20170202_02` -
  <https://api.dandiarchive.org/api/assets/2ae6bf3c-788b-4ece-8c01-4b4a5680b25b/info/>
- `neurallatents/nlb_tools`, `nlb_tools/evaluation.py` (`bits_per_spike`, `neg_log_likelihood`, the
  eval-mean null) and `nlb_tools/make_tensors.py` (mc_rtt `behavior_field: finger_vel`, `lag: 140`,
  600 ms `align_range`) - <https://github.com/neurallatents/nlb_tools>
- Pei et al. 2021, "Neural Latents Benchmark '21", arXiv 2109.04463 (co-bps definition, mc_rtt
  98 held-in / 32 held-out sorted units, 5 ms bins, baseline co-bps 0.147-0.192) -
  <https://arxiv.org/abs/2109.04463>, full text via <https://ar5iv.labs.arxiv.org/html/2109.04463>
- coremltools 9.0 release notes - <https://api.github.com/repos/apple/coremltools/releases>
- coremltools palettization and `MLComputePlan` API, via Context7 `/apple/coremltools` -
  <https://apple.github.io/coremltools/docs-guides/source/opt-palettization-api.html>
- `astral-sh/setup-uv` caching documentation -
  <https://github.com/astral-sh/setup-uv/blob/main/docs/caching.md>

### Secondary, cited with attribution

- Makin, O'Doherty, Cardoso, Sabes 2018, "Superior arm-movement decoding from cortex with a new,
  unsupervised-learning algorithm", J Neural Eng - <https://iopscience.iop.org/article/10.1088/1741-2552/aa9e95>
  (the paper this dataset accompanies)
- "Benchmarking Neural Decoding Backbones towards Enhanced On-edge iBCI Applications", arXiv
  2406.06626 (30 Indy sessions from Zenodo 3854034, 10 ms bins, 96-channel unsorted multiunit,
  finger velocity, single-session R2 0.633-0.717, multi-session 0.720-0.838) -
  <https://arxiv.org/html/2406.06626v1>
- Sussillo et al., "Making brain-machine interfaces robust to future neural variability", arXiv
  1610.05872 (-4.5 x RMS threshold-crossing convention) - <https://arxiv.org/pdf/1610.05872>
- Downey et al. 2018, "Intracortical recording stability in human brain-computer interface users"
  (day-to-day waveform instability, electrode drift) - <https://pubmed.ncbi.nlm.nih.gov/29553484/>
- "Long-term performance of intracortical microelectrode arrays in 14 BrainGate clinical trial
  participants" (2,319 sessions, 35.6% of electrodes recording spiking waveforms, 7% decline) -
  <https://www.medrxiv.org/content/10.1101/2025.07.02.25330310v1>
- "Propagating spatiotemporal activity patterns across macaque motor cortex carry kinematic
  information", PNAS (M1 envelope leads hand velocity by 120-180 ms) -
  <https://www.pnas.org/doi/10.1073/pnas.2212227120>
- MonkeyLogic HDF5 implementation notes (MATLAB's inability to write zero-sized dataspaces in
  R2014b and earlier; "discard its value, 0, when you read the variable") -
  <https://monkeylogic.nimh.nih.gov/docs_HDF5Implementation.html>

### In-repo sources read

`.planning/phases/09-.../09-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`
(Phase 9 section), `.planning/config.json`,
`.planning/phases/04-.../04-RESEARCH.md`, `04-VALIDATION.md`, `04-training-evidence.md`,
`Decoder/scripts/download_indy.py`, `Decoder/src/ndt1/{data,velocity_head,metrics}.py`,
`Decoder/manifests/indy_sessions.json`, `Decoder/pyproject.toml`,
`Decoder/tests/{test_heldout_cobps,test_data,test_manifest}.py`,
`Tools/scripts/bps-policy.sh`, `.github/workflows/ci.yml`, `AGENTS.md`.

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|---|---|---|
| Dataset structure and session inventory | **HIGH** | Measured directly by downloading and parsing the real files; every shape, checksum and channel count is a local observation, not a document claim |
| The `MATLAB_empty` dereference defect | **HIGH** | Reproduced exactly, with the spurious-timestamp count and values enumerated |
| `finger_pos` axis convention | **HIGH** | Correlation of exactly -1.0000 against `cursor_pos`, plus the Zenodo affine matrix reproducing to 2.1 mm |
| NLB mc_rtt protocol and session identity | **HIGH** | `nlb_tools` source plus DANDI asset metadata, both primary |
| Neural-to-kinematic lag | **HIGH** | `nlb_tools` sets `lag: 140` for this exact dataset family; corroborated by PNAS cross-correlation |
| Training cost estimates | **HIGH** | Timed on this machine with the repo's own modules |
| coremltools 9.0 behavior | **MEDIUM-HIGH** | Defaults read from the installed wheel; release notes checked; but the real-weight conversion has not been run |
| Firing-rate band bounds | **MEDIUM** | Centre values measured; the width of the band is my judgment (A1) and should be re-checked against every selected session before pinning |
| Expected ridge R2 magnitude | **LOW** | Reasoned from architecture and published comparanda, not measured (A2). Flagged so D-25's framing does not depend on it |
| Cross-session degradation magnitude | **LOW** | No published number exists for this configuration. Deliberately not invented (Section 6) |

**Research date:** 2026-08-30
**Valid until:** 2026-09-29 for the tooling claims (coremltools, setup-uv, CI). The dataset findings
do not expire: Zenodo record 3854034 was published 2020-05-26 and its files are immutable.
