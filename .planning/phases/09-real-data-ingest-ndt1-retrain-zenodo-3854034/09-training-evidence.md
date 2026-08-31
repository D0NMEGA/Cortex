# Phase 9 RD-03 / RD-04 evidence: NDT1 trained on real primate M1 spikes

**Date:** 2026-08-31
**Result:** pooled held-out **co-bps = 1.9116 bits/spike** against the train-split per-channel
mean-firing-rate null, measured on **real O'Doherty/Makin Indy M1 spikes (Zenodo record 3854034)**,
four sessions, CPU only.

This supersedes the co-bps of **0.3804** in `04-training-evidence.md`, which was measured on a
**synthetic Poisson fallback** because no real `.mat` was present under `Decoder/data/` when Phase 4
ran. Every decoder number this repository published before today came from that fallback. This
artifact is the first one that did not.

**Read the two disclosures in "What this number is NOT" before quoting 1.9116 anywhere.** The scored
positions are visible to the encoder, and the protocol is not NLB'21's. Both are measured and stated
below rather than left for a reader to discover.

**This is not a hardware-gated claim.** It is CPU-only decoder R&D that reproduces on any Mac CPU
with the pinned wheels. There is no Neural Engine, Core ML, palettization or latency number in this
file; those are Plans 09-07 and 09-08.

## At a glance

| Quantity | Value | Null |
|---|---|---|
| Pooled held-out co-bps | **1.9116** bits/spike | pooled train-split mean rate (the D-22 gate) |
| Pooled held-out co-bps | **1.8834** bits/spike | test mean (NLB convention, drift-robust) |
| Per-session held-out range | 1.6500 to 1.9540 bits/spike | test mean |
| Leave-one-session-out, 3 of 4 folds | 1.5110 mean, 1.2991 to 1.9137 | test mean |
| Leave-one-session-out, 4th fold | diverged to a non-finite loss in epoch 12 | not applicable |
| Re-derived assertion margin | 0.25 bits/spike | 13.1% of the observation (D-22) |
| Superseded synthetic value | 0.3804 bits/spike | `04-training-evidence.md` |

Every value in that table was produced on this machine's CPU from the four manifest-pinned real
sessions. None is estimated, extrapolated, or carried over from another document.

## Environment

| Field | Value |
|-------|-------|
| Machine | Apple M5 Pro, 18 cores, 24 GB. `Darwin 25.5.0` (`xnu-12377.121.6~2/RELEASE_ARM64_T6050`), `arm64` |
| OS | macOS 26.5 (build 25F71) |
| Compute | CPU only, `device="cpu"`. No ANE, no GPU, no `computeUnits` targeting |
| Interpreter | CPython 3.12.13 (uv-managed) |
| torch | 2.12.1 (CPU) |
| numpy | 2.4.6 |
| h5py | 3.16.0 |
| coremltools | 9.0 (installed, unused in this plan) |
| Determinism | `seed = 0` for the global RNG, model init, the training mask generator and every evaluation mask |

The machine identity above is `uname -a` / `sw_vers` / `sysctl machdep.cpu.brand_string` on the host
that produced every number in this file. The M5 Pro is a corroborating development machine, not the
project's canonical iPad Pro M4 capture device; that distinction does not matter here because
nothing in this file is a hardware-gated performance claim.

## Data

Four 96-channel M1-only Indy sessions, materialized under the gitignored `Decoder/data/` and pinned
by SHA-256 in `Decoder/manifests/indy_sessions.json` (Plan 09-05, `09-ingest-evidence.md`). Total
1,767,820,363 bytes, 285,359 bins at 20 ms, calendar span **2016-06-24 to 2016-09-15** (83 days).

Produced by `uv run --project Decoder python Decoder/scripts/report_sessions.py`, verbatim:

| session_id | sha256[:12] | bins | duration_s | mean_rate_hz | median_rate_hz | max_rate_hz | dead_ch | sub_1hz_ch | live_ch | max_count_per_bin | zero_fraction | finger_pos_cols | band |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| indy_20160624_03 | 65937e0cea18 | 24999 | 500.0 | 15.69 | 11.83 | 59.48 | 4 | 4 | 92 | 5 | 0.7533 | 6 | ok |
| indy_20160627_01 | b1a2404f2510 | 168147 | 3362.9 | 19.12 | 15.00 | 53.78 | 4 | 6 | 91 | 5 | 0.7141 | 6 | ok |
| indy_20160630_01 | 2ca8f6b7fcfc | 73161 | 1463.2 | 14.84 | 6.63 | 51.65 | 6 | 9 | 89 | 5 | 0.7870 | 6 | ok |
| indy_20160915_01 | 76175e5bf851 | 19052 | 381.0 | 12.09 | 9.95 | 32.45 | 8 | 8 | 88 | 3 | 0.7992 | 3 | ok |

Full committed SHA-256 pins, copied from the manifest by `train_real.py` at run time and written
into `09-decoder-metrics.json` (never recomputed there, so the published number cites the committed
pin):

| session_id | sha256 |
|---|---|
| indy_20160624_03 | `65937e0cea184b3307a19f84b4d9b44530c95e756e6b42bfad6cc8d55c3bf93f` |
| indy_20160627_01 | `b1a2404f2510475f244077bfc30efbd80148e784ea9263b88f348a8bb15c71e8` |
| indy_20160630_01 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| indy_20160915_01 | `76175e5bf851c123af29178fa7c483588e911a000615438bff97d6f2f2591408` |

Zero sessions were excluded: all four `.mat` files loaded and passed the 96-channel width gate and
the `ndt1.qc` plausibility band. `finger_pos` is six rows wide on three sessions and **three** on
`indy_20160915_01`, so both branches of the loader's `(3, k)` / `(6, k)` handling are exercised by
real data rather than assumed.

### Out-of-window spikes (09-RESEARCH P10)

`bin_spikes` drops every timestamp outside `[t_start, t_end)`, where the window is the behavior
clock's first and last sample. That is correct behavior, and the counts belong in the record rather
than being invisible. `report_sessions.py` re-parses each session to count them and cross-checks the
in-window total against the binned matrix's own sum; all four agree exactly.

| session_id | t_start_s | t_end_s | dropped before | dropped after | in window | matches binned total |
|---|---|---|---|---|---|---|
| indy_20160624_03 | 680.000 | 1179.996 | 5116 | 4229 | 721606 | yes |
| indy_20160627_01 | 105.936 | 3468.880 | 8476 | 4090 | 5852908 | yes |
| indy_20160630_01 | 148.984 | 1612.216 | 6076 | 3300 | 1932293 | yes |
| indy_20160915_01 | 282.956 | 664.000 | 5183 | 3487 | 405497 | yes |

The `indy_20160630_01` row (6076 before, 3300 after) reproduces 09-RESEARCH's independently measured
counts exactly, which is the cross-check that the report's re-parse walks the cell array the same way
`ndt1.data.load_session` does.

### Raw counts, no normalization (D-04)

These are raw spike counts. There is no per-session rate normalization, because the Poisson NLL
objective and co-bps are both defined on actual counts: normalizing would break the metric and its
comparability to Phase 4 and to NLB'21. Session heterogeneity is surfaced instead, as the channel
yield columns above (4 to 8 dead channels per session, 88 to 92 live of 96).

### Unit aggregation: u1 through u5 are SUMMED

Each session's `spikes` cell array is 5 unit rows by 96 channels. `load_session` sums all five into
one multiunit train per channel. This is the correct reconstruction of the total threshold-crossing
count, because Zenodo documents u1 as a **residual**: it "contains the threshold crossings which
remained after the spikes on that channel were sorted into other units". u1 alone is therefore not
the full threshold-crossing train.

Measured share of timestamps in unit row u1, per session (`h5py` walk over the same references the
loader dereferences):

| session_id | u1 | u2 | u3 | u4 | u5 |
|---|---|---|---|---|---|
| indy_20160624_03 | 55.0% | 12.0% | 18.5% | 10.1% | 4.4% |
| indy_20160627_01 | 56.3% | 11.0% | 15.8% | 10.8% | 6.0% |
| indy_20160630_01 | 57.9% | 8.0% | 15.7% | 12.9% | 5.5% |
| indy_20160915_01 | 41.3% | 32.7% | 18.5% | 5.7% | 1.8% |

Choosing u1-only would cut every firing rate roughly in half and therefore move co-bps. 09-RESEARCH
measured that directly on `indy_20160630_01`: 13.82 Hz mean per channel for u1..u5 against 8.00 Hz
for u1 alone (57.9%, matching the timestamp share above) and 5.82 Hz for u2..u5. The aggregation is
u1..u5 and is not a free parameter.

## Methodology

### Split discipline (D-12)

Each session is split independently into a chronological head and tail, `test_frac = 0.2`, and only
then pooled. There is no shuffle split and no pooling before splitting, so no future bin and no
cross-session bin can leak into training (04-RESEARCH pitfall #10). `ndt1.sessions.pooled_splits`
is the single implementation of this.

| session_id | train bins | train windows | test bins | test windows |
|---|---|---|---|---|
| indy_20160624_03 | 19999 | 624 | 5000 | 156 |
| indy_20160627_01 | 134518 | 4203 | 33629 | 1050 |
| indy_20160630_01 | 58529 | 1829 | 14632 | 457 |
| indy_20160915_01 | 15242 | 476 | 3810 | 119 |
| **pooled** | **228288** | **7132** | **57071** | **1782** |

Windows are cut PER SESSION and then concatenated, never cut across a concatenation of sessions. A
32-bin window straddling the boundary between two recordings three days apart would be a fabricated
neural sequence; there are 7132 windows and this discipline costs 2 of them.

**The pool is dominated by one session.** `indy_20160627_01` alone is 168,147 of 285,359 bins, 59%
of the data and 59% of the training windows. Every pooled number below is therefore weighted toward
that session, and the LOSO fold that holds it out trains on only 41% of the corpus. That is stated
here rather than hidden inside a mean.

### Objective

BERT-style masked-modeling Poisson reconstruction, unchanged from Phase 4: a random 25% of
`(bin, channel)` positions is selected, the model emits log-rates, and the Poisson NLL is summed over
the selected positions only (`ndt1.loss.masked_poisson_nll`, `log_input = True`). There is no
velocity or kinematics head in this artifact; the readout is Plan 09-07.

See "What this number is NOT" for the measured consequence of the fact that the selected positions
are not hidden from the encoder input.

### Config, Phase-4 verbatim (D-14)

| Parameter | Value |
|---|---|
| epochs | 12 |
| lr | 2e-3 |
| optimizer | AdamW, weight_decay 0.01 |
| batch_size | 16 |
| seq_len | 32 bins (640 ms) |
| mask_ratio | 0.25 |
| test_frac | 0.2 |
| bin_ms | 20.0 |
| seed | 0 |
| device | cpu |
| log_input | true |
| params | 1,292,544 |

These are byte-for-byte the constants Phase 4 used to produce the synthetic 0.3804, so the real
number is directly comparable to the synthetic one it replaces. D-14 permits RAISING the epoch
budget if the curve has clearly not converged and forbids lowering it; the curve below converges, so
the budget was left at 12. Nothing was tuned.

### The two nulls, and why both are reported (P8, T-09-06-04)

co-bps scores the model against a constant per-channel rate predictor, so the choice of constant
moves the number. Three constants are reported:

- **`train_null`** is the per-channel mean of the POOLED TRAIN split. This is the D-22 gate. It is
  leakage-free (fit only on data the model trained on) but it cannot adapt to within-session drift
  or to cross-session heterogeneity. Measured drift on `indy_20160630_01` is 8.1% BELOW the train
  head's mean rate in the test tail, which is the direction that makes this null worse and therefore
  INFLATES co-bps.
- **`test_mean_null`** is the per-channel mean of the evaluation spikes themselves, which is the
  NLB'21 convention. A null fit on the evaluation data is strictly stronger, so this is the
  drift-robust floor.
- **`session_train_null`** is the per-channel mean of that session's OWN train half, reported for
  the per-session held-out evaluation. It sits between the other two and separates within-session
  drift from cross-session heterogeneity, which the pooled `train_null` otherwise conflates. It is
  not required by the plan; it is reported because without it the gap between the other two has two
  possible explanations and no way to tell them apart.

All three are computed on one shared, `seed = 0` mask and one shared forward pass, so they differ
only in the baseline.

## Result

### Pooled held-out co-bps (RD-03)

| Null | Pooled held-out co-bps (bits/spike) |
|---|---|
| `train_null`, the pooled train-split per-channel mean (the D-22 gate) | **1.9116** |
| `test_mean_null`, the test-set per-channel mean (NLB convention) | **1.8834** |

Scored on 1,782 held-out windows (57,071 bins, 19.0 minutes of recording) drawn from the four
sessions' chronological tails, on one seeded mask at `mask_ratio = 0.25`. Apple M5 Pro, CPU only,
`seed = 0`. Full precision: 1.9115827904116325 and 1.8834470653325304.

### Per-session held-out co-bps (RD-04a)

| session_id | test windows | `train_null` | `session_train_null` | `test_mean_null` |
|---|---|---|---|---|
| indy_20160624_03 | 156 | 2.0294 | 1.8283 | 1.8129 |
| indy_20160627_01 | 1050 | 1.7577 | 1.7241 | 1.6725 |
| indy_20160630_01 | 457 | 2.2242 | 1.6610 | 1.6500 |
| indy_20160915_01 | 119 | 2.3927 | 1.9618 | 1.9540 |
| **pooled** | **1782** | **1.9116** | not applicable | **1.8834** |

Four things this table says, none of which is visible from the pooled number alone:

1. **Every session beats every null.** The lowest value anywhere in the table is 1.6500.
2. **The pooled value sits inside the per-session range**, between the lowest (1.7577 on
   `indy_20160627_01`) and the highest (2.3927 on `indy_20160915_01`) under the gate null. D-15
   predicted a pooled value at or below the per-session values; it lands in the middle, closest to
   `indy_20160627_01` because that session supplies 59% of the held-out windows.
3. **The inflation in `train_null` is cross-session heterogeneity, not within-session drift.**
   The `train_null` to `session_train_null` gap runs to 0.5632 bits/spike (`indy_20160630_01`) and
   0.4310 (`indy_20160915_01`), while the `session_train_null` to `test_mean_null` gap never exceeds
   0.0516. In other words the pooled mean rate is a poor constant predictor for a session whose
   rates differ from the pool average, and that handicap, not the measured 8.1% within-session rate
   drift, is what separates the gate null from the drift-robust floor. `indy_20160627_01` has the
   smallest gap (0.0336) precisely because the pooled mean is essentially its own mean.
   The third null exists to make that distinction; without it the two explanations are
   indistinguishable.
4. **The drift-robust floor is 1.8834 pooled.** Quoting only the gate value would be quoting the
   more flattering of two numbers that were both measured.

### Training loss curve (masked-position Poisson NLL, mean per epoch)

```
epoch  loss     |bar (scaled 0.20-0.45)
  1    0.4309   |#######################################     (start)
  2    0.3311   |######################
  3    0.2924   |################
  4    0.2717   |############
  5    0.2612   |##########
  6    0.2569   |##########
  7    0.2518   |#########
  8    0.2478   |########
  9    0.2451   |########
 10    0.2435   |#######
 11    0.2453   |########
 12    0.2439   |#######                                     (end)
```

0.4309 to 0.2439, a 43% reduction over 12 epochs and 5,352 optimizer steps, in 836 s of CPU. The
decrease is not strictly monotone: epochs 10 to 12 oscillate inside a band of 0.0018 (0.2435, 0.2453,
0.2439). That flattening is the signal D-14 asks for. The curve has converged, so the "raise the
budget" branch does not fire and the budget stayed at the Phase-4 12 epochs. Lowering it was never an
option D-14 permits.

### Re-derived assertion margin (D-22)

`CO_BPS_MARGIN` is now **0.25**, replacing the Phase-4 **0.05**.

The value was derived by code from the measurement, not typed by a human who had seen the number:
`train_real.py --derive-margin` reads the observed pooled `train_null` out of the committed metrics
JSON and multiplies it by the fraction Phase 4 used (`0.05 / 0.3804 = 13.1441%`), then rounds to two
significant figures. `1.9115827904 * 0.131441 = 0.2513`, so 0.25. The rationale string it generates
is committed at `co_bps.margin_rationale` in `09-decoder-metrics.json` and mirrored into the
constant's comment in `Decoder/tests/test_heldout_cobps.py`.

Phase 4's 0.05 was calibrated against a purpose-built learnable synthetic sinusoid and does not
transfer to real primate M1 spikes. It is superseded, not merely re-tuned.

Three quick tests (`Decoder/tests/test_cobps_margin.py`) hold this in place: the constant is not the
Phase-4 value, the JSON carries both the margin and its rationale, and the two agree. The training
pass deliberately writes `co_bps.margin = null` on every run, so a re-run without a re-derivation
fails those tests loudly rather than leaving a stale assertion guarding a number that no longer
exists.

The committed slow gate was then executed against the re-derived margin, on real data:

```
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
1 passed, 150 deselected in 1201.01s (0:20:01)
```

It recorded `held_out_co_bps = 2.3993` with
`source = "real sessions [indy_20160624_03, indy_20160627_01, indy_20160630_01, indy_20160915_01]"`,
so the synthetic fallback branch is no longer taken. That test uses a naive concatenation split
rather than the D-12 per-session split, so its number is a gate result and not the headline; what it
establishes is that the committed assertion passes on real spikes with 9.6x headroom over the
re-derived margin.

### Input-visibility diagnostic

The encoder is fed the unmasked counts, so it can read the observed value at every position it is
scored on (see "What this number is NOT"). `train_real.py --diagnostic` loads the committed
checkpoint and re-scores it twice on the same seeded mask: once as the training pass did, and once
with the scored positions zeroed in the encoder input.

| Eval set | visible, `train_null` | hidden, `train_null` | visible, `test_mean_null` | hidden, `test_mean_null` |
|---|---|---|---|---|
| indy_20160624_03 | 2.0294 | -5.4325 | 1.8129 | -5.6490 |
| indy_20160627_01 | 1.7577 | -5.4726 | 1.6725 | -5.5578 |
| indy_20160630_01 | 2.2242 | -5.7812 | 1.6500 | -6.3555 |
| indy_20160915_01 | 2.3927 | -5.1564 | 1.9540 | -5.5951 |
| pooled | 1.9116 | -5.5266 | 1.8834 | -5.5548 |

Two conclusions, and one non-conclusion.

- **The `visible_*` column reproduces the committed values to full double precision** on an
  independently constructed mask and a checkpoint reloaded from disk, which is the evaluation-path
  determinism check.
- **The prediction at a scored position is dominated by the observed value at that position.**
  Removing it costs about 7.4 bits/spike, taking the model from far above the constant-rate null to
  far below it. So 1.9116 measures self-reconstruction plus context, not context alone.
- **The -5.53 is NOT "the honest number with masking done right".** The checkpoint was never trained
  with zeroed inputs, so zeroing is far out of distribution and this figure understates a properly
  masked model by an unknown amount. The context-only quantity was not measured by this plan and
  cannot be without retraining under a corrected objective. That is deferred item 1 in
  `deferred-items-09-06.md`, not a number this artifact claims.

### Reproducibility (T-09-06-01)

The pipeline was executed end to end twice, about an hour apart, from the same seed. Every committed
number reproduced **bit for bit**, compared programmatically rather than by eye:

| Quantity | Run 1 versus run 3 |
|---|---|
| pooled `train_null` and `test_mean_null` | identical (1.9115827904116325, 1.8834470653325304) |
| all 12 per-epoch losses | identical |
| all per-session co-bps under all three nulls | identical |
| all three finite LOSO folds | identical to 16 significant figures |
| the diverged LOSO fold | diverged in both, in the same epoch |
| pooled checkpoint SHA-256 | identical: `0e5c174dd1d3112ca1d7fbfb9da8d14962b3a2f66ac9bffb8c2c789b87c72841` |

A third execution was interrupted by the harness during its final fold; before it stopped it had
reproduced the pooled result, the pooled checkpoint's SHA-256 and three of the four folds, which is
consistent with the other two. The committed JSON is run 3, which completed.

An identical checkpoint hash is the strongest form of this claim available: it means the optimizer
visited the same states in the same order, not merely that two summary statistics agreed. Scope of
the claim: this machine, these pinned wheel versions, CPU. Cross-platform determinism was not tested.

## Multi-session generalization (RD-04)

### The four-fold rotation (D-13)

Each fold retrains from scratch on three sessions' train halves with the identical config, then
evaluates on the held-out session's FULL binned matrix. The full matrix, not just its test tail,
because a held-out session had zero exposure, so every one of its bins is legitimately held out.
Each session is held out exactly once.

| Fold (held out) | trained on | train windows | eval windows | `train_null` | `test_mean_null` | final loss |
|---|---|---|---|---|---|---|
| indy_20160624_03 | 0627, 0630, 0915 | 6508 | 781 | diverged | diverged | non-finite (epoch 12) |
| indy_20160627_01 | 0624, 0630, 0915 | 2929 | 5254 | 1.7687 | 1.2991 | 0.2213 |
| indy_20160630_01 | 0624, 0627, 0915 | 5303 | 2286 | 2.4966 | 1.3203 | 0.2649 |
| indy_20160915_01 | 0624, 0627, 0630 | 6656 | 595 | 2.4162 | 1.9137 | 0.2445 |

Summary over the three folds that produced a value:

| Null | mean | std | min | max | folds | finite | diverged |
|---|---|---|---|---|---|---|---|
| `train_null` | 2.2271 | 0.3991 | 1.7687 | 2.4966 | 4 | 3 | 1 |
| `test_mean_null` | 1.5110 | 0.3489 | 1.2991 | 1.9137 | 4 | 3 | 1 |

**The meaningful cross-comparison is under `test_mean_null`, not `train_null`.** A LOSO fold's
`train_null` is the mean of three sessions the evaluated session is not among, so it is an even worse
constant predictor than the pooled null is, and it inflates the fold's co-bps for a reason that has
nothing to do with generalization. Comparing 2.2271 (LOSO) with 2.1010 (the in-pool per-session mean)
under that null would suggest the model generalizes BETTER to unseen sessions, which is an artifact.

Under the drift-robust null the comparison is honest and the answer is the expected one:

| Evaluation | mean `test_mean_null` co-bps |
|---|---|
| in-pool, per-session held-out tails | 1.7723 |
| leave-one-session-out, three finite folds | 1.5110 |

**Generalization to a session the model has never seen costs about 0.26 bits/spike, a 15% drop.**
The model does transfer: every finite fold stays far above its null, with the weakest at 1.2991.
Nothing here was reshaped or re-run to reach that; it is what the rotation produced.

### The fold that diverged

The fold holding out `indy_20160624_03` trains normally for eleven epochs and then loses the twelfth:

```
per-epoch loss: 0.4157 0.3305 0.2942 0.2748 0.2631 0.2573 0.2529 0.2485 0.2467 0.2455 0.2437 nan
```

The likely mechanism is an overflow in the `log_input=True` Poisson NLL, whose model term is
`exp(rate) - target * rate`: once a predicted log-rate spikes, `exp` overflows and the gradients
become non-finite. AdamW at `lr = 2e-3` with no gradient clipping has nothing to arrest it. The
divergence is deterministic and reproduced identically in every execution.

It is reported rather than repaired, for two reasons. The remedies (gradient-norm clipping, or a
lower learning rate) are changes to `ndt1/train.py` or to the D-14-locked config. And an 11-epoch
budget would have produced a finite number for this fold, but choosing 11 BECAUSE it avoids the
divergence would be tuning toward a result, which D-22 and D-25 forbid. The fold contributes nothing
to the summary and its loss curve is committed in `09-decoder-metrics.json` so the epoch is
auditable. See `deferred-items-09-06.md` item 2.

The honest reading is that the Phase-4-verbatim config sits closer to the numerical stability edge on
real spikes than the pooled loss curve alone suggests, and that one quarter of the rotation was lost
to it.

### The cross-session assumption, stated as a prior (D-15, corrected by C-04)

Pooling raw 96-channel spike counts across sessions spanning **2016-06-24 to 2016-09-15**, a span of
83 days, assumes stable channel-to-neuron identity across electrode drift. Utah-array unit identity
is not stable across days: extracellular waveforms change within a single day and performance
instability is attributed to electrode drift plus neuroplasticity. Channel 37 in June and channel 37
in September are the same electrode, not reliably the same neuron.

That assumption is exactly what session-conditioned modeling relaxes. **NDT2** conditions on session
identity so that a per-session embedding absorbs the drift instead of the shared weights having to
average over it. NDT2 is explicitly out of scope for v0 and v1 of this project, which is why the
assumption is stated here rather than engineered away.

This paragraph is a statement of prior expectation, written before the numbers were known and not
retrofitted to them:

- A pooled number BELOW the per-session numbers is an expected and reportable outcome, not a defect.
  (Observed: the pooled value landed inside the per-session range, not below it.)
- A LOSO number near zero or negative is a legitimate result meaning channel identity did not
  transfer. (Observed: it did transfer, at a cost of about 15% under the drift-robust null.)

Neither outcome would have changed what was reported. What was measured is what appears above.

## What this number is NOT (D-23)

### The scored positions are visible to the encoder

`ndt1.train.train_ndt1` calls `model(targets)` on the UNMASKED counts and uses the mask only to
select which positions the Poisson NLL is summed over. `NDT1ANE.forward` performs no input masking
either; it stores `mask_ratio` for the trainer and never applies it. So the encoder sees the observed
count at every position, including the positions it is scored on. This is a reconstruction score over
a random subset of positions, not BERT-style masked prediction where the target is hidden from the
input.

This is Phase-4 behavior. It was left unchanged because D-14 requires the config verbatim for
comparability, and changing the objective is an architectural decision outside this plan's scope. It
is recorded here as a disclosure, and the size of the effect is measured rather than asserted (see
the input-visibility diagnostic in the results above). It is the single largest reason this number
sits far above the NLB'21 baselines in the table below, and it is logged for a future plan in
`deferred-items-09-06.md`.

### The protocol is not NLB'21's

NLB'21's `mc_rtt` task is cited here for scale only. Its protocol differs from this one on every
axis that matters:

| Axis | NLB'21 mc_rtt co-bps | This repo's `ndt1.metrics.co_bps` |
|---|---|---|
| Session | `indy_20170202_02` | `indy_2016*` M1-only sessions |
| Units | 130 sorted single units, 98 held-in / 32 held-out | 96 channels of summed threshold crossings |
| Bin | 5 ms | 20 ms |
| Segments | 600 ms trials, overlap allowed | 32-bin (640 ms) non-overlapping windows |
| What is held out | neurons (co-smoothing) | a random 25% of (bin, channel) positions |
| Is the held-out value visible to the model | no | **yes**, see above |
| Scored over | held-out neurons, all timepoints | selected positions across all channels |
| Null rate source | mean of the evaluation spikes | mean of the train split (both reported here) |

The bits arithmetic is the same in both: `(NLL_null - NLL_model) / (masked spike count * ln 2)` under
a Poisson likelihood. So the units are the same and the protocols are not.

Published NLB'21 `mc_rtt` baselines, for scale and never as a leaderboard comparison: Smoothing
0.147, GPFA 0.155, SLDS 0.165, NDT 0.160, AutoLFADS 0.192 bits/spike. A number an order of magnitude
above those does not mean this decoder outperforms them; it means the task it was scored on is
easier, for the reasons tabulated above.

**Correction, stated plainly (C-03).** NLB'21's `mc_rtt` task uses `indy_20170202_02`, recorded
2017-02-02, per DANDI dandiset 000129 asset metadata. That session is not in Zenodo record 3854034
at all. This repository previously asserted that `indy_20160630_01` was the session behind that
benchmark; that claim was false and is retracted here. None of the four sessions used in this
artifact appears in NLB'21.

## Supersedes

This number replaces the **synthetic** co-bps **0.3804** from
`.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md` wherever
that value is cited as the decoder's held-out reconstruction quality.

Per D-24, `04-training-evidence.md` is NOT retroactively edited: a historical evidence artifact
records what that phase actually measured, and rewriting it would destroy the record rather than
correct it. It gains a superseded banner pointing here in Plan 09-10.

`Decoder/tests/test_heldout_cobps.py` also changes meaning as of this plan: with `Decoder/data/`
materialized, its `_load_binned()` now takes the real-session branch instead of the synthetic Poisson
fallback, so the slow gate it enforces is a real-data gate. Its `CO_BPS_MARGIN` was re-derived from
the real observation (see the Result section).

## Gaps and what would close them (D-25)

A low honest number completes this phase; so does a high one that is honestly qualified. These are
the gaps in what was measured, recorded as backlog and not as scheduled scope.

1. **The objective does not hide what it scores.** The single most valuable follow-up is to mask the
   encoder input at the selected positions, which is what NDT actually does, and re-measure. That
   changes `ndt1/train.py` and breaks comparability with Phase 4, so it is a deliberate future
   decision rather than a fix to slip into this plan.
2. **One LOSO fold diverged numerically** under the Phase-4-verbatim config. Gradient-norm clipping
   or a lower learning rate would very likely fix it, and both are config changes D-14 does not
   authorize here.
3. **Four sessions, one dominant.** 59% of the corpus is one recording. More sessions of comparable
   length would make both the pooled number and the rotation more even.
4. **No session conditioning.** See the D-15 statement in the generalization section.
5. **No velocity readout in this artifact.** The kinematic decode number is Plan 09-07; this file is
   reconstruction only.
6. **Determinism is verified for this machine and these wheel versions**, not across platforms. The
   config and the pinned versions are committed so a divergence elsewhere is diagnosable.

## Reproduce

Every number in this file comes from the commands below, in this order, on the machine described in
the Environment table. Nothing here runs in CI (D-21): the Decoder quick suite is the CI gate, and it
never trains and never downloads the dataset.

```sh
# 1. Materialize the pinned venv (CPython 3.12 + torch 2.12.1 + coremltools 9.0).
uv sync --project Decoder --extra dev

# 2. Materialize and verify the 1.77 GB dataset (gitignored; see 09-ingest-evidence.md).
uv run --project Decoder python Decoder/scripts/download_indy.py

# 3. The per-session ingest report (the Data tables above).
uv run --project Decoder python Decoder/scripts/report_sessions.py

# 4. Wiring check, about one minute, on the two smallest sessions. Never a committed number.
uv run --project Decoder python Decoder/scripts/train_real.py --smoke

# 5. The real run: pooled training, per-session held-out co-bps, the four-fold LOSO rotation.
#    Roughly 60 minutes of CPU. Writes 09-decoder-metrics.json with co_bps.margin left null.
uv run --project Decoder python Decoder/scripts/train_real.py

# 6. Measure the input-visibility effect on the committed checkpoint (about one minute).
uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic

# 7. Derive the D-22 assertion margin FROM the observed value and write it back with its rationale.
#    This runs only after the number exists; the margin never precedes the measurement.
uv run --project Decoder python Decoder/scripts/train_real.py --derive-margin

# 8. The quick gate (no dataset needed) and the slow real-data gate (about 20 minutes).
uv run --project Decoder pytest Decoder/tests -m "not slow" -q
uv run --project Decoder pytest Decoder/tests -m slow -k test_heldout_cobps -q
uv run --project Decoder ruff check Decoder
```

Model weights are gitignored by the Plan 04-01 artifact policy. The committed evidence is this file
plus `09-decoder-metrics.json`; the weights are reproduced from `seed = 0` by step 5.
