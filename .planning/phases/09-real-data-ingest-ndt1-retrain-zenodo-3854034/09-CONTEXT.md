# Phase 9: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034) - Context

**Gathered:** 2026-08-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The four curated O'Doherty/Makin Indy M1-only sessions physically exist under `Decoder/data/`,
are SHA-256-pinned in the committed manifest, and every decoder number the repo publishes is
re-derived on real primate M1 spikes instead of the synthetic Poisson fallback, up to and
including the `.mlpackage` that ships. Requirements RD-01 through RD-06. The work lives inside
the `Decoder/` uv subsystem plus the CI wiring that gates it.

Explicitly NOT this phase (Phase 10, RD-07 through RD-10): ReFIT-Kalman re-fit and the raw-vs-ReFIT
BPS ablation on real data, the end-to-end real-session closed loop and its software-timed
glass-to-glass re-derivation, the repo-wide synthetic-number sweep, and the `readme-policy.sh`
rewrite retiring the photodiode claim.

</domain>

<decisions>
## Implementation Decisions

### Real-data ingest and integrity (RD-01, RD-02)

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

### Velocity readout on real kinematics

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

### Multi-session training and generalization (RD-03, RD-04)

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

### CoreML re-derivation (RD-05, RD-06)

- **D-16:** The 4-bit palettization delta is re-measured on BOTH models. Poisson-NLL delta on the
  reconstruction model, for direct comparability to `04-palettization-evidence.md` (3.471x size,
  delta 0.009114). R2 delta on the with-velocity model, because that is the artifact that ships.
- **D-17:** ANE eligibility (226/226 ops, zero CPU-only) and decoder p99 are measured on the
  with-velocity model, the one `NeuralDecoder` actually loads. The device disposition carries
  forward unchanged from DEC-08 / DEC-11 and the D-11/D-12/D-08 line across Phases 5 to 8:
  M5 Pro corroborating, iPad Pro M4 canonical capture optional and never auto-approved. Real
  weights do not change the architecture or the 1.29M param count, so a material p99 shift would
  itself be a finding.

### CI gating and provenance enforcement

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

### Evidence framing and honest-number handling

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

### Folded Todos

None. `todo match-phase 9` returned zero matches.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

ROADMAP.md carries no `Canonical refs:` line for this phase; the list below was accumulated from
REQUIREMENTS.md, PROJECT.md, and the codebase scout during this discussion.

### Phase requirements and scope
- `.planning/ROADMAP.md` (Phase 9 section) - goal statement, RD-01..RD-06, the five success criteria
- `.planning/REQUIREMENTS.md` - the RD block (RD-01..RD-10) and the retired LAT block
- `.planning/PROJECT.md` - core-value re-point of 2026-08-28, Key Decisions table

### Dataset format and ingest pitfalls
- `.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-RESEARCH.md` - the `.mat` field
  list (`cursor_pos` k x 2 mm, `finger_pos` k x 3 or k x 6 cm, `target_pos` k x 2 mm, `t` k x 1 s,
  behavior at 250 Hz; `chan_names`, `wf`), Pitfall #3 (v7.3 needs h5py, not `scipy.io.loadmat`),
  Pitfall #10 (chronological split), Pitfall #11 (channel-width divergence), and the CI disposition
  note near line 114
- `Decoder/manifests/indy_sessions.json` - the four sessions, `"PENDING"` checksums, M1-only note
- `Decoder/README.md` - the uv subsystem runbook

### Evidence artifacts being superseded or mirrored
- `.planning/phases/04-.../04-training-evidence.md` - the artifact template to mirror AND the
  synthetic disclosure being replaced ("No real `.mat` was present under `Decoder/data/`", co-bps 0.3804)
- `.planning/phases/04-.../04-palettization-evidence.md` - the 3.471x / Poisson-NLL delta 0.009114
  baseline that RD-05 re-derives
- `.planning/phases/05-.../05-velocity-head-evidence.md` - carries the R2 0.9998 that D-10 replaces
- `.planning/phases/05-.../05-ane-eligibility-evidence.md` - the 226/226 zero-CPU-only result RD-06 re-verifies
- `.planning/phases/05-.../05-latency-evidence.md` - the p99 baseline and its device-annotation discipline
- `.planning/phases/05-.../05-HUMAN-UAT.md` - the never-auto-approve device-gate precedent

### Threat model
- `.planning/phases/04-.../04-SECURITY.md` - T-04-02-01 (download integrity), T-04-02-02 (`wf`
  memory DoS), T-04-02-03 (channel width), T-04-04-01 (checkpoint pickle), T-04-04-03 (seed determinism)

### Gate idioms to mirror
- `Tools/scripts/validate-privacy-manifest.sh` - the `--self-test` negative-control pattern
- `Tools/scripts/readme-policy.sh` - required/forbidden token gate with self-test
- `Tools/scripts/bps-policy.sh` - the same, plus a committed-number cross-check
- `Tools/scripts/check_refit_uplift.py` - bare-`python3` CI guard reading a committed JSON
- `.github/workflows/ci.yml` - where the new Decoder job (D-18) and gate step (D-19) land

### Phase 10 consumers of this phase's output
- `.planning/phases/07-refit-kalman-closed-loop-recalibration/07-RESEARCH.md` section 3.2 - the Q/R
  fitting recipe that needs real `z_decoded` vs `v_true` residuals
- `Decoder/scripts/fit_kalman_gain.py` - the held-out-Indy branch that has never fired and which
  D-05 finally makes reachable

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable assets
- `Decoder/scripts/download_indy.py`: complete. Fills `"PENDING"` on first fetch, verifies on
  re-run, refuses the bot-gated `/api/` endpoint, streams in 1 MiB chunks. Needs only the RD-01
  negative control.
- `Decoder/src/ndt1/data.py`: a real h5py v7.3 loader with the 96-channel gate, cell-array
  dereference, `chronological_split`, and `IndySpikeDataset`. Written against the documented format
  but never run against a real file. D-05 extends it to read `finger_pos`.
- `Decoder/src/ndt1/train.py`, `loss.py`, `metrics.py`: `train_ndt1`, `masked_poisson_nll`,
  `random_mask`, `co_bps`, `mean_firing_rate`. Unchanged by this phase.
- `Decoder/src/ndt1/velocity_head.py`: `ridge_fit`, `load_ridge`, and the rank-2 to rank-4
  `load_state_dict` pre-hook. Only the labels change (D-09).
- `Decoder/src/ndt1/palettize.py`, `convert.py`, `compute_plan.py`: the RD-05 and RD-06 paths,
  unchanged.
- `Decoder/tests/test_heldout_cobps.py`: `_load_binned()` already prefers a real `.mat` when one is
  present and falls back to synthetic otherwise. Extend it to the multi-session case rather than
  rewriting it.
- `Tools/scripts/check_refit_uplift.py` and the five `*-policy.sh` gates: the exact idioms D-19 mirrors.

### Established patterns
- Evidence discipline: every published number is a committed `*-evidence.md` carrying machine,
  pinned wheel versions, seed, a verbatim re-run runbook, and a device/method label.
- Tier split (Phase 2 D-18, Phase 6 D-10): CI gates correctness and structure; measured numbers are
  committed evidence, never CI-blocking.
- Gate self-tests: every `*-policy.sh` proves it bites via a negative control before it is trusted.
- Artifact policy: `Decoder/data/`, `Decoder/checkpoints/`, `*.pt` and `*.mlpackage` are gitignored.
  The Swift side resolves models via `CORTEX_MODEL_URL` / `CORTEX_DECODER_MODEL_URL` and skips
  cleanly when absent. This phase does not change that policy.
- No bare or blind `except` anywhere in the Decoder Python (enforced by the ruff BLE gate).
- `coremltools` is pinned at 9.0; `uv sync --project Decoder --extra dev` is required before any
  pytest run or a bare `uv run pytest` fails with a misleading `No module named numpy`.

### Integration points
- `.github/workflows/ci.yml`: a new blocking Decoder job (D-18) plus the `decoder-policy.sh` step (D-19).
- `Decoder/manifests/indy_sessions.json`: four `"PENDING"` checksums get filled by the first
  verified fetch (RD-01).
- `Decoder/src/ndt1/data.py`: its module docstring currently states behavior arrays are
  intentionally not used. D-05 amends that contract deliberately; the docstring must be updated in
  the same change so the comment does not go stale.
- `Packages/CortexDecoder` (`NeuralDecoder`, `CortexDecoderBench`): consume the regenerated velocity
  `.mlpackage` for RD-06's p99 re-verification.
- `Decoder/scripts/fit_kalman_gain.py`: its data-present branch activates in Phase 10 on this
  phase's artifacts.

</code_context>

<specifics>
## Specific Ideas

- The `velocity_r2.json` R2 of 0.9998 is a self-consistency artifact, not a decode result:
  `test_convert_velocity_output.py:55` generates labels as `last_bin @ w_true + 0.01 * noise` with
  `w_true = rng.standard_normal((96, 2)) * 0.05`, then regresses those same rates onto them.
  Replacing it with a real held-out R2 is the point of D-10.
- `indy_20160630_01` is the NLB'21 mc_rtt benchmark session. That is what makes the D-23 framing
  worth getting right rather than skipping.
- Phase 6 D-07 chose the dark Neuralink theme partly to give the photodiode a clean rising edge.
  That rationale is retired with the photodiode path; the theme itself stays.
- The v1 re-point rationale, quoted for downstream agents: the repo's largest credibility hole was
  that every decoder number was produced on a synthetic Poisson fallback. Closing that is the whole
  point of this phase, which is why D-25 treats a low honest number as success and a fabricated
  good one as failure.

</specifics>

<deferred>
## Deferred Ideas

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

### Reviewed Todos (not folded)

None. `todo match-phase 9` returned zero matches.

</deferred>

---

<post_research_corrections>
## Post-research corrections (added 2026-08-30, after 09-RESEARCH.md)

The decisions above are preserved verbatim as the historical record of the discussion. Research
falsified four factual premises inside them. The DECISIONS still stand; their RATIONALES and one
literal spec are corrected here. Where this block and the text above disagree, **this block wins.**

Source: `09-RESEARCH.md` (commit `d33128b`), all four verified by direct measurement of the real
dataset, not by documentation.

### C-01 supersedes D-03's contingency framing - substitution is CERTAIN, and the set is chosen

`indy_20160407_02` and `indy_20160411_01` are 192-channel M1+S1 recordings (`chan_names` run
`M1 001` .. `S1 096`). The loader is correct to reject them. Only 2 of 4 manifested sessions survive,
which is fewer than three, so D-03's substitution branch fires as written.

**The four sessions for this phase are (user decision, 2026-08-30, Option B):**

| Session id | Size | `finger_pos` cols | 20 ms bins |
|---|---|---|---|
| `indy_20160624_03` | 144.0 MB | 6 | 24,999 |
| `indy_20160627_01` | 1135.1 MB | 6 | 168,147 |
| `indy_20160630_01` | 382.2 MB | 6 | 73,161 |
| `indy_20160915_01` | 106.6 MB | **3** | 19,052 |

Total 1.77 GB, 285,359 bins, span 2016-06-24 to 2016-09-15 (83 days). Chosen over a tight 9-day June
cluster (which would make the LOSO claim weak) and over a cheaper 4-session set (which would drop the
168k-bin `indy_20160627_01`). Both `finger_pos` widths are present, so the k x 3 / k x 6 branch is
exercised rather than assumed.

The manifest's dropped-session note must record WHY the two were dropped (192-channel M1+S1), per D-03.

### C-02 corrects D-06's axis spec - the planar pair is rows 1-2, NOT rows 0-1

`finger_pos` is ordered `(z, -x, -y[, azimuth, elevation, roll])` in cm. D-06's "first two axes (x, y)"
would select depth and negated-x. Verified empirically: `corr(cursor_pos[0], finger_pos[1]) = -1.0000`,
while `corr(cursor_pos[0], finger_pos[0]) = +0.285` on an axis whose standard deviation is 0.24 cm.

**Use `finger_pos[1:3]`.** Note the axes are negated; handle the sign explicitly rather than inheriting
it silently. This is a correctness fix, not a change of decision - D-06 wanted the planar kinematics,
and rows 1-2 are the planar kinematics. Taking rows 0-1 raises no exception; it would just quietly
halve R2. Pinned by the RD-02c fixture test.

### C-03 voids the session-identity rationale in D-06 and D-23

The NLB'21 `mc_rtt` session is `indy_20170202_02` (per DANDI 000129 asset metadata). It is not
`indy_20160630_01` and is not in Zenodo record 3854034 at all.

D-06's label-source decision still stands on its own merits: `nlb_tools` does use `finger_vel` for
`mc_rtt`, so `finger_pos` remains the right source. D-23's "cite as context, never as comparison"
framing becomes MORE correct once the session-identity claim is dropped. Drop the claim from the
plans, the evidence artifact, and `Decoder/manifests/indy_sessions.json`'s `note` field (a
decoder-owned surface, in scope under D-24) - do not leave `decoder-policy.sh` enforcing a manifest
that asserts something false. The same false claim in this file's `<specifics>` section is superseded
by this block.

### C-04 corrects D-15's span

D-15 says "sessions spanning April to June 2016". Under the chosen set the span is **2016-06-24 to
2016-09-15**. The substance of D-15 is unchanged and still stands: pooling raw 96-channel spikes
across sessions assumes stable channel-to-neuron identity across electrode drift; that assumption is
what NDT2's session conditioning would relax; a pooled number below the per-session numbers is an
expected and reportable outcome, not a defect.

### C-05 new: a live silent-corruption defect in `ndt1.data.load_session`

Not a correction to a decision - a defect found in the code this phase touches. MATLAB writes empty
cells as *truthy* HDF5 references to a `(2,) uint64` dataset carrying a `MATLAB_empty` attribute, so
`data.py`'s `if not ref: continue` guard never fires. On `indy_20160630_01` it injects 498 spurious
timestamps (values 0.0 and 1.0) across 92 of 96 channels. They are discarded today only by luck: that
session's behavior clock starts at t = 148.984 s, so they fall outside `[t_start, t_end)`. A session
whose clock starts near zero would silently corrupt every firing rate.

Correct discriminator: `if "MATLAB_empty" in f[ref].attrs`. The channel-axis transpose heuristic, by
contrast, was verified correct. Pinned by the RD-02a fixture test, whose `t` vector must start at 0.0
so the negative control can actually bite.

### C-06 factual corrections to sizes and scope

- Manifest total is **2.599 GB** as currently committed, not the roadmap's "~1.5 GB". The corrected
  Option B set is 1.77 GB.
- `weight_threshold=2048` means the shipped velocity head is **never palettized**. D-16's two-model
  delta measurement must account for this rather than assume the head is quantized.
- Measured training cost on this Mac's CPU: ~11-15 min pooled, ~45-60 min for the LOSO rotation.
  `load_session` parses a real 382 MB session in 0.2 s.

</post_research_corrections>

---

*Phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034*
*Context gathered: 2026-08-30*
