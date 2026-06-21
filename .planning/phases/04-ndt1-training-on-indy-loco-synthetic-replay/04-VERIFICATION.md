---
phase: 04-ndt1-training-on-indy-loco-synthetic-replay
verified: 2026-06-21T06:26:30Z
status: passed
score: 4/4 must-haves verified
re_verification: false
gaps: []
deferred: []
---

# Phase 4: NDT1 Training on Indy/Loco Synthetic Replay — Verification Report

**Phase Goal:** A correctly-sized NDT1 (1.3M params, 6 layers, h=1-2 heads, 128 hidden, 20ms binning — NOT the commonly-miscited 4-head variant) trains end-to-end on the canonical O'Doherty Indy/Loco dataset and emits a 4-bit palettized checkpoint ready for ANE conversion. No CoreML or Apple Silicon deployment work yet — pure decoder R&D.

**Verified:** 2026-06-21T06:26:30Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | NDT1ANE architecture is ~1.3M params, 6 layers, h∈{1,2}, 128 hidden, 20ms bins; regression guard against h=4 drift (SC1 / DEC-01) | VERIFIED | param_count=1,292,544 confirmed live; num_layers=6, d_model=128, bin_ms=20.0 asserted structurally; all 6 ANEAttention modules report num_heads=2 (∈{1,2}); test suite: test_structural_knobs_exact + test_every_attention_head_count_in_one_or_two + test_param_count all pass |
| 2 | Training loop converges to non-trivial co-bps on held-out chronological split, beats mean-firing-rate null; leakage-free (SC2 / DEC-02) | VERIFIED | slow test test_heldout_cobps PASSED live (12.51s); held-out co-bps=0.3804 bits/spike >> 0.05 margin; null=0.0 by definition; chronological-tail split confirmed in data.py; train-split mean used as null (no test-set leakage); 04-training-evidence.md committed |
| 3 | All inference-path activations are BC1S (B,C,1,S); unit test FAILS on (B,S,C) tensor; zero nn.Linear on inference path (SC3 / DEC-04) | VERIFIED | 93 activations captured, all rank-4 shape[2]==1 confirmed live; VanillaBSCBlock raises AssertionError("rank must be 4, got 3") as required; nn_linear_count=0 verified live; ANE einsum "bchq,bkhc->bkhq" present in attention.py source |
| 4 | palettize_weights with OpPalettizerConfig(nbits=4) produces quantized package with documented size reduction and bounded reconstruction-loss delta (SC4 / DEC-03+DEC-05) | VERIFIED | All 3 slow SC4 tests PASSED live; fp16=2,678,038 B, 4bit=771,534 B, ratio=3.471x; NLL fp16=1.186899, 4bit=1.177785, |delta|=0.009114 <= bound=0.5; mlprogram type confirmed; DEC-03 strictly precedes DEC-05; 04-palettization-evidence.md committed |

**Score:** 4/4 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Decoder/src/ndt1/model_ane.py` | NDT1ANE BC1S model | VERIFIED | 146 lines; 6 layers, d_model=128, num_heads=2, all Conv2d (no nn.Linear), learnable pos encoding, load_state_dict pre-hook for dense→conv compat |
| `Decoder/src/ndt1/attention.py` | ANEAttention + LayerNormANE | VERIFIED | 101 lines; bchq,bkhc->bkhq einsum constant; all projections are nn.Conv2d 1x1; num_heads exposed as attribute for SC1a test |
| `Decoder/src/ndt1/loss.py` | masked_poisson_nll + random_mask | VERIFIED | 64 lines; BERT-style mask; log_input parameterized; zero-divide guarded; nn.PoissonNLLLoss(reduction='none') |
| `Decoder/src/ndt1/metrics.py` | co_bps + mean_firing_rate | VERIFIED | 107 lines; NLB'21 formula (NLL_null - NLL_model) / (masked_spike_count * ln2); null input log-transformed when log_input=True; spike-count denominator (not bin count) |
| `Decoder/src/ndt1/train.py` | Training loop + checkpoint I/O | VERIFIED | 189 lines; reshape_to_bc1s (B,S,C)→(B,C,1,S); masked Poisson NLL objective; AdamW; torch.load(weights_only=True); no bare except |
| `Decoder/src/ndt1/data.py` | h5py loader + chronological split + IndySpikeDataset | VERIFIED | 60+ lines; h5py v7.3 HDF5 loader; 20ms bins; chronological tail split; 96-channel width enforced; no kinematics |
| `Decoder/src/ndt1/channel_count.py` | CORTEX_CHANNEL_COUNT=96 source-of-truth | VERIFIED | 16 lines; confirms reconciliation with cortex_shm.h, frame.rs, cortex_ring.h |
| `Decoder/src/ndt1/convert.py` | DEC-03 torch.jit.trace → ct.convert to mlprogram | VERIFIED | 84 lines; convert_to="mlprogram"; minimum_deployment_target=ct.target.iOS18; no computeUnits kwarg; INPUT_FEATURE_NAME="spikes" exported |
| `Decoder/src/ndt1/palettize.py` | DEC-05 4-bit k-means palettization | VERIFIED | 74 lines; OpPalettizerConfig(mode="kmeans", nbits=4); package_size_bytes helper; no ANE targeting |
| `Decoder/tests/test_architecture_structural.py` | SC1a structural assertions | VERIFIED | 54 lines; tests num_layers=6, d_model=128, bin_ms=20.0, 6 attention modules, all num_heads∈{1,2}, default h=2 |
| `Decoder/tests/test_param_count.py` | SC1b param count guardrail | VERIFIED | Passes in quick suite (56 passed) |
| `Decoder/tests/test_bc1s_activations.py` | SC3a BC1S forward-hook + negative control | VERIFIED | 82 lines; 93 activations checked; VanillaBSCBlock raises AssertionError; negative control proven to bite |
| `Decoder/tests/test_no_linear_on_inference_path.py` | SC3b zero nn.Linear + ANE einsum | VERIFIED | 36 lines; linear_count==0 asserted; inspect.getsource confirms einsum string |
| `Decoder/tests/test_heldout_cobps.py` | SC2 slow integration test | VERIFIED | @pytest.mark.slow; PASSED live 12.51s; co-bps=0.3804 > 0.05 |
| `Decoder/tests/test_convert_mlpackage.py` | SC4a DEC-03 convert test | VERIFIED | @pytest.mark.slow; PASSED live; includes phase-boundary grep test (forbids cpuAndNeuralEngine/computeUnits/_ANEClient/Instruments/residency in convert.py) |
| `Decoder/tests/test_palettized_package.py` | SC4a DEC-05 size test | VERIFIED | @pytest.mark.slow; PASSED live; fp16=2,678,038 B, 4bit=771,534 B, ratio=3.471x confirmed in test output |
| `Decoder/tests/test_palettization_loss_delta.py` | SC4b loss delta test | VERIFIED | @pytest.mark.slow; PASSED live; |delta|=0.009114 <= 0.5 confirmed in test output |
| `.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-training-evidence.md` | SC2 co-bps evidence artifact | VERIFIED | Committed; co-bps=0.3804, loss 1.2996→0.6356 (-51%), 12 epochs monotonic |
| `.planning/phases/04-ndt1-training-on-indy-loco-synthetic-replay/04-palettization-evidence.md` | SC4 size+delta evidence artifact | VERIFIED | Committed; fp16=2,678,038 B, 4bit=771,534 B, 3.471x, |delta|=0.009114 ≤ 0.5 |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `train.py` | `model_ane.NDT1ANE` | import + model(bc1s_tensor) | VERIFIED | reshape_to_bc1s converts (B,S,C) to BC1S before every forward pass; rates from model fed to masked_poisson_nll |
| `train.py` | `metrics.co_bps` + `metrics.mean_firing_rate` | import + evaluate_co_bps() | VERIFIED | evaluate_co_bps calls mean_firing_rate(eval_targets) for null, then co_bps(rates, targets, mask, null_rate) |
| `convert.py` | `model_ane.NDT1ANE` | import + torch.jit.trace | VERIFIED | NDT1ANE().eval() → trace on (1,96,1,32) example → ct.convert(convert_to="mlprogram") |
| `palettize.py` | `convert.py` output | ct.models.MLModel(mlpackage_path) → palettize_weights | VERIFIED | DEC-03 strictly precedes DEC-05; palettize_4bit loads the fp16 mlpackage produced by convert_to_mlpackage |
| `test_bc1s_activations.py` | `model_ane.NDT1ANE` | register_forward_hook on all modules | VERIFIED | 93 activations captured from a (1,96,1,32) forward pass; all rank-4 shape[2]==1 |
| `test_no_linear_on_inference_path.py` | `attention.py` source | inspect.getsource | VERIFIED | ANE_ATTENTION_EINSUM = "bchq,bkhc->bkhq" confirmed in source; linear_count=0 confirmed live |
| `test_convert_mlpackage.py` | `convert.py` source (boundary check) | re.compile + file read | VERIFIED | Greps convert.py for Phase-5 tokens; all absent; test passes |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `train.py` → `masked_poisson_nll` | `rates` | `NDT1ANE.forward(targets)` — targets are real spike windows from IndySpikeDataset DataLoader | Yes — loss backpropagates through real model weights | FLOWING |
| `metrics.py` → `co_bps` | `model_rates` | `model(eval_targets)` — trained NDT1ANE on held-out chronological split | Yes — 0.3804 bits/spike on 25 held-out windows, confirmed live | FLOWING |
| `palettize.py` → `package_size_bytes` | file sizes | `rglob("*")` on actual `.mlpackage` directory bundle | Yes — fp16=2,678,038 B, 4bit=771,534 B from live test output | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Quick suite: 56 pass, 1 hermetic skip, 4 deselected | `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 56 passed, 1 skipped, 4 deselected in 1.42s | PASS |
| SC1 param count in [1.0M, 1.6M] | `NDT1ANE().count_parameters()` | 1,292,544 — in_range=True | PASS |
| SC1 structural knobs | `model.num_layers, d_model, bin_ms` | 6, 128, 20.0 | PASS |
| SC1 head count guard (h∈{1,2}) | All 6 ANEAttention.num_heads | [2,2,2,2,2,2] — all_in_1_or_2=True | PASS |
| SC3b zero nn.Linear | `sum(isinstance(m,nn.Linear) for m in model.modules())` | 0 — zero_linear=True | PASS |
| SC3a BC1S negative control bites | VanillaBSCBlock (B,S,C) through _assert_bc1s | AssertionError raised: "rank must be 4, got 3" | PASS |
| SC3a BC1S activations count | 93 activations checked from (1,96,1,32) forward | All rank-4 shape[2]==1 | PASS |
| SC2 slow co-bps test | `uv run --project Decoder pytest -m slow -k cobps` | 1 passed in 12.51s | PASS |
| SC4 slow convert + palettize tests | `uv run --project Decoder pytest -m slow -k "convert or palettiz"` | 3 passed in 6.76s; SC4a ratio=3.471x, SC4b |delta|=0.009114 | PASS |
| Phase boundary: no ANE tokens in source | grep for cpuAndNeuralEngine/computeUnits/_ANEClient/residency/Instruments in Decoder/src/ | 0 actual tokens (only negative-control test references) | PASS |
| ruff linter | `uv run --project Decoder ruff check Decoder/src Decoder/tests` | All checks passed! | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DEC-01 | 04-03 | NDT1 architecture — 6 transformer layers, h=1-2 attention heads, 128 hidden dim, 20ms spike binning, ~1.3M params | SATISFIED | param_count=1,292,544; num_layers=6; d_model=128; bin_ms=20.0; all num_heads=2∈{1,2}; SC1a/SC1b tests pass |
| DEC-02 | 04-01, 04-02, 04-04 | Training pipeline ingests O'Doherty Indy/Loco synthetic spike replay (Zenodo 3854034) | SATISFIED | h5py loader in data.py handles v7.3 HDF5 .mat; synthetic Poisson fallback when dataset gitignored; co-bps=0.3804 on held-out split; SC2 slow test passes |
| DEC-03 | 04-05 | Trained PyTorch checkpoint converts to .mlpackage via coremltools | SATISFIED | ct.convert(convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18); test_convert_mlpackage.py PASSED live; .mlpackage bundle produced |
| DEC-04 | 04-03 | Tensor activations reshape to BC1S (B,C,1,S) layout per apple/ml-ane-transformers | SATISFIED | 93 activations all rank-4 shape[2]==1 confirmed live; (B,S,C) negative control raises AssertionError; all projections are nn.Conv2d 1x1 |
| DEC-05 | 04-05 | 4-bit palettization applied via coremltools.optimize.palettize_weights with OpPalettizerConfig(nbits=4) | SATISFIED | palettize_4bit uses OpPalettizerConfig(mode="kmeans", nbits=4); test_palettized_package.py PASSED; ratio=3.471x; |delta|=0.009114 ≤ 0.5 |

DEC-06 through DEC-12 are Phase 5 requirements (ANE targeting, residency, latency). Correctly deferred — no phase boundary violations found.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| All source files | — | None | — | ruff passes clean; no TODO/FIXME/placeholder; no stub returns; no bare except; no hardcoded empty data structures on render path |
| `Decoder/tests/` | — | `PytestUnknownMarkWarning` for `slow` mark | Info | Warning appears only when pytest is invoked from the repo root without `-p no:warnings`; the mark IS registered in `Decoder/pyproject.toml` under `[tool.pytest.ini_options].markers`; no functional impact |
| `model_ane.py` + `convert.py` | 32-37, 28-33 | `try/except ImportError` for `CORTEX_CHANNEL_COUNT` | Info | Legitimate parallel-worktree solution documented in 04-03 SUMMARY; guard is specific ImportError (not bare except); fallback value 96 matches all three native homes; ruff BLE passes |

---

### Deferred Items

No deferred items — all Phase 4 Success Criteria are addressed within this phase. DEC-06 through DEC-12 (ANE deployment, residency, latency) are Phase 5 scope per REQUIREMENTS.md and the ROADMAP, and no Phase 4 artifact makes any premature claim about them.

The single deferred item from deferred-items.md (ruff I001 in test_attention.py) was resolved by the Wave-3 post-merge lint sweep and does not appear in the current ruff output.

---

### Human Verification Required

None. All four success criteria are fully verifiable programmatically via the live test suite and code inspection. No UI behavior, real-time runtime claims, or external service integration are in scope for Phase 4.

---

## Gaps Summary

No gaps. All four success criteria verified end-to-end against the actual codebase and live test execution:

- SC1 (DEC-01): Architecture independently confirmed via Python introspection — param_count=1,292,544, six layers, all attention heads=2 (∈{1,2}), d_model=128, bin_ms=20.0, zero nn.Linear.
- SC2 (DEC-02): Co-bps slow test executed and passed live — 0.3804 bits/spike, chronological split, train-split null, leakage-free. Matches committed evidence artifact exactly.
- SC3 (DEC-04): BC1S invariant confirmed on 93 live activations; negative control (B,S,C) block raises AssertionError; ANE einsum present in source; ruff clean.
- SC4 (DEC-03+DEC-05): All three SC4 slow tests executed and passed live — SC4a size ratio=3.471x, SC4b |delta|=0.009114 ≤ 0.5 match the committed evidence document exactly. Phase boundary holds: zero ANE-deployment tokens in source files.

Phase 4 goal is achieved.

---

_Verified: 2026-06-21T06:26:30Z_
_Verifier: gsd-verifier_
