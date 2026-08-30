# Phase 9: Real-Data Ingest & NDT1 Retrain (Zenodo 3854034) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `09-CONTEXT.md`; this log preserves the alternatives considered.

**Date:** 2026-08-30
**Phase:** 09-real-data-ingest-ndt1-retrain-zenodo-3854034
**Mode:** discuss (advisor mode off, no USER-PROFILE.md)
**Areas discussed:** Velocity head on real kinematics, Multi-session training strategy, Real-data
gating in CI, Honest-number bar and the 0.3804 sweep, plus a follow-on round on lag, resampling,
training budget and checkpoint targeting.

---

## Assumptions round (pre-discussion)

Five areas surfaced for correction before any gray areas were presented: technical approach,
implementation order, scope boundaries, risk areas, dependencies.

**User response:** "Good." No corrections. Assumptions validated as stated.

Notable assumptions carried into the discussion:
- `download_indy.py` is complete; only the negative control is missing.
- `load_session` has never been run against a real `.mat` and is the highest-probability failure.
- Real co-bps will likely land well below the synthetic 0.3804.
- The Decoder Python suite has never run in CI (verified: no `uv`, `pytest`, or `ndt1` in `ci.yml`).
- The velocity head is currently ridge-fit on `rng.standard_normal` labels, flagged Unclear.

## Gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Velocity head on real kinematics | Real behavior arrays vs reconstruction-only | yes |
| Multi-session training strategy | Pooling, splits, LOSO | yes |
| Real-data gating in CI | Python suite, provenance gate, fixture | yes |
| Honest-number bar + 0.3804 sweep | Pass bar, NLB framing, citation scope | yes |

**User's choice:** all four.

---

## Velocity head on real kinematics

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, fit on real kinematics | Read behavior arrays, ridge-fit on real labels; makes the shipped .mlpackage real end to end and unblocks RD-07 | yes |
| No, reconstruction-only; defer to Phase 10 | Real encoder, fabricated readout, labeled as such | |
| Yes, and ship both checkpoints separately | Reconstruction checkpoint for co-bps, velocity checkpoint for RD-06 | |

| Option | Description | Selected |
|--------|-------------|----------|
| finger_pos, first two axes | NLB'21 mc_rtt convention; indy_20160630_01 is the mc_rtt session | yes |
| cursor_pos | On-screen cursor; a gained derivative, not the benchmark variable | |
| Both, with finger_pos canonical | Cross-check in evidence | |

| Option | Description | Selected |
|--------|-------------|----------|
| Keep closed-form ridge | Swap labels only; no training loop, ANE eligibility preserved | yes |
| Jointly fine-tune encoder + head | Better R2, risks the 226/226 result and changes the architecture story | |
| Ridge now, fine-tune ablation as evidence | Documents the choice at extra cost | |

| Option | Description | Selected |
|--------|-------------|----------|
| Held-out R2 vs mean-velocity null, per-session and pooled | Mirrors the co-bps-vs-null discipline | yes |
| Held-out R2 and correlation only | Common iBCI convention, no null baseline | |
| You decide | The planner picks at plan time | |

**Notes:** the existing `velocity_r2.json` R2 of 0.9998 was identified during scouting as a
self-consistency artifact (`test_convert_velocity_output.py:55` generates labels from the same
rates it then regresses). Replacing it became the motivating case for this whole area.

---

## Multi-session training strategy

| Option | Description | Selected |
|--------|-------------|----------|
| One pooled model, per-session + LOSO eval | Single shipped checkpoint; satisfies RD-03 and RD-04 | yes |
| Per-session models AND a pooled model, ablated | Measures what pooling costs; ~2x budget | |
| Per-session models only | Faithful to NDT1's single-session design, no model to ship | |

| Option | Description | Selected |
|--------|-------------|----------|
| Full 4-fold rotation, zero-shot | Four numbers plus mean and spread | yes |
| Single fold on the mc_rtt session | Quarter the compute, single sample | |
| 4-fold plus a few-shot adaptation number | Adds the realistic calibration story | |

| Option | Description | Selected |
|--------|-------------|----------|
| Raw counts; document per-session channel yield | Preserves the Poisson/co-bps metric definitions | yes |
| Raw counts, no yield reporting | Leaves heterogeneity undocumented | |
| Per-session rate normalization | Breaks the count-based metric and NLB comparability | |

| Option | Description | Selected |
|--------|-------------|----------|
| Proceed with passers; substitute only below 3 survivors | Documents exclusions, resists dataset reshaping | yes |
| Always substitute to keep n=4 | Keeps the manifest literal, risks silent drift | |
| Block the phase until four are confirmed | Turns a data finding into a blocker | |

**Notes:** the NDT2 tension was raised explicitly before the questions. Pooling across April-to-June
2016 sessions assumes stable channel identity; that is what session-conditioning relaxes and NDT2 is
Out of Scope. Captured as D-15 (state the assumption in evidence, treat a low pooled number as
expected) rather than resolved by architecture change.

---

## Real-data gating in CI

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, blocking, quick suite only | uv sync + pytest -m "not slow"; closes zero-coverage hole | yes |
| Yes, but non-blocking | Surfaces regressions nobody reads | |
| No, keep CI Swift-only | Structural shell gate only; loader stays unguarded | |

| Option | Description | Selected |
|--------|-------------|----------|
| One decoder-policy.sh --self-test, three assertions | Zero PENDING, provenance declared, checksums agree | yes |
| Manifest check only | Nothing ties a number to its bytes | |
| Python guard only, mirroring check_refit_uplift.py | Skips the shell-gate self-test discipline | |

| Option | Description | Selected |
|--------|-------------|----------|
| Commit a tiny synthetic v7.3-structured .mat fixture | Makes cell-array deref CI-testable, no licensing question | yes |
| Commit a slice of a real session | Strongest, but redistributes dataset bytes | |
| No fixture; slow tests cover it | Loader regressions ship silently | |

| Option | Description | Selected |
|--------|-------------|----------|
| Committed evidence.md + metrics JSON, human-run; CI never trains | The Phase 2 D-18 / Phase 6 D-10 tier split | yes |
| CI downloads and re-runs training | 1.5 GB through a bot-gated endpoint per run | |
| Short real-data smoke when a cached dataset is present | A gate that usually skips proves nothing | |

---

## Honest-number bar and the 0.3804 sweep

| Option | Description | Selected |
|--------|-------------|----------|
| Beat the train-split mean-rate null; margin re-derived from the real run | The Phase-4 procedure; honors D-12 no-gaming | yes |
| Null-beat plus a shuffled-spikes negative control | Stronger science, one extra run per fold | |
| Pre-register a numeric bar before training | Cleanest epistemics, invites tuning pressure | |

| Option | Description | Selected |
|--------|-------------|----------|
| Cite NLB as context, state plainly the protocols differ | Applies the D-13 category-error lesson prospectively | yes |
| Implement the NLB held-out-neuron protocol | Directly comparable, real scope expansion | |
| No NLB reference at all | Zero risk, leaves the best anchor unused | |

| Option | Description | Selected |
|--------|-------------|----------|
| Decoder-owned surfaces now; repo-wide sweep stays Phase 10 | PROJECT/ROADMAP/REQUIREMENTS plus superseded banners | yes |
| Do the full repo-wide sweep now | Pulls RD-09 forward; ReFIT numbers not yet re-derivable | |
| Touch nothing outside Decoder/ | Leaves 0.3804 unlabeled for another phase | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, a low honest number is a finding, not a failure | Deliverable is real data seen and numbers labeled | yes |
| Complete, and immediately open a decoder-improvement phase | Commits sprint time before knowing the gap | |
| Treat a materially worse number as a blocker | Would block on the expected outcome | |

---

## Follow-on round: lag, resampling, budget, checkpoint targeting

The user chose "Explore more gray areas" after the first four areas.

| Option | Description | Selected |
|--------|-------------|----------|
| Sweep lag on the TRAIN split, lock one value, report the sweep | 0 to 160 ms whole-bin offsets; leak-free selection | yes |
| Fixed 100ms lag from the literature | No tuning, no sensitivity information | |
| No lag, concurrent bin only | Conservative, known to understate the decoder | |

| Option | Description | Selected |
|--------|-------------|----------|
| Differentiate at 250Hz, then mean-aggregate into 20ms bins | Native-rate derivative, no filter parameters | yes |
| Bin positions first, then difference across bins | Coarser, noisier derivative | |
| Savitzky-Golay smoothed derivative, then bin | Better R2, parameters need justifying | |

| Option | Description | Selected |
|--------|-------------|----------|
| Keep the Phase-4 config as baseline; document any change | Directly comparable, no new judgment calls | yes |
| Train to plateau with a documented maximum | Needs an operational definition of plateau | |
| Early stopping on a third validation split | Cleanest, adds a split and moving parts | |

| Option | Description | Selected |
|--------|-------------|----------|
| Palettization on both models; ANE + p99 on the velocity model only | Keeps Phase-4 comparability AND characterizes what ships | yes |
| Velocity model only for both | One path, breaks comparability with 3.471x / delta 0.009114 | |
| Reconstruction model only for both | Leaves the shipped artifact uncharacterized | |

**Notes:** lag framing was clarified before the question. The model already sees a 32-bin (640 ms)
causal window and reads from `rates[..., -1:]`; the lag decides which kinematic sample that last bin
is regressed against, since M1 activity leads movement.

---

## Implementer's Discretion

Recorded in `09-CONTEXT.md`: `decoder-policy.sh` token lists and self-test construction, the metrics
JSON schema and naming, uv cache-key construction, the fixture's dimensions and generator location,
ridge lambda selection, LOSO fold budget, channel-yield table formatting, where the lag sweep runs,
and plan/wave decomposition.

## Deferred Ideas

NLB held-out-neuron protocol; joint encoder+head fine-tuning; NDT2 session-conditioning; early
stopping on a third split; Savitzky-Golay derivative; committing a real session slice as a fixture;
a decoder-improvement phase; RD-07 through RD-10 (Phase 10 by roadmap). Full rationale in
`09-CONTEXT.md`.

## Scope creep redirected

None. The discussion stayed inside RD-01..RD-06 throughout. Two candidate expansions (the NLB
held-out-neuron protocol, joint fine-tuning) were surfaced as options, declined, and recorded as
deferred rather than dropped.
