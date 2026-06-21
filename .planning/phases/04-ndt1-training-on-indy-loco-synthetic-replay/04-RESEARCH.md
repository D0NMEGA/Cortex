# Phase 4 Research — NDT1 Training on Indy/Loco Synthetic Replay

**Researched:** 2026-06-21 (main-thread browser-harness + Context7 pass — per project research protocol, GSD's HTTP-only subagent researcher is bypassed for this browser-heavy phase)
**Phase goal:** A correctly-sized NDT1 (1.3M params, 6 layers, h∈{1,2}, 128 hidden, 20ms bins) trains end-to-end on O'Doherty Indy/Loco (Zenodo 3854034) and emits a **4-bit palettized model ready for ANE conversion**. Pure decoder R&D — no ANE deployment yet.
**Requirements:** DEC-01, DEC-02, DEC-03, DEC-04, DEC-05

## RESEARCH COMPLETE

---

## 0. The four findings that change how this phase must be planned (read first)

1. **A parameter count assertion CANNOT catch the h=4 miscitation — `num_heads` must be asserted directly.** In `torch.nn.MultiheadAttention`, the projection weights are `in_proj` = `3·d_model²` and `out_proj` = `d_model²` **regardless of `num_heads`** — heads only reshape `d_model` into `(num_heads × head_dim)`, they add zero parameters. So SC1's "parameter count assertion … regression test against accidental drift to h=4" is **under-specified as written**: a model with h=4 has the *identical* param count to h=2. The test MUST assert **both** (a) total params ≈1.3M (catches layer/dim/FFN drift) **and** (b) every attention module reports `num_heads ∈ {1,2}` (the only thing that catches h=4). This is the single most important correctness detail in the phase. (Confidence: A — direct consequence of the `nn.MultiheadAttention` parameterization.)

2. **DEC-05's named API (`palettize_weights` + `OpPalettizerConfig`) is a Core ML-side op that REQUIRES a prior `.mlpackage` conversion (DEC-03).** `coremltools.optimize.coreml.palettize_weights(mlmodel, config)` operates on an **already-converted `mlprogram` MLModel**, not a PyTorch checkpoint. So the goal's phrase "emits a 4-bit palettized **PyTorch** checkpoint" is reconciled as: Phase 4 trains the fp16 PyTorch model, **converts it to `.mlpackage` (DEC-03)**, then palettizes that package (DEC-05). The "**No CoreML or Apple Silicon work yet**" caveat means **no ANE targeting / residency / `computeUnits` / Instruments / on-device latency** (all Phase 5, DEC-06..12) — but the *conversion + palettization themselves run on the dev-Mac CPU* and are legitimately "checkpoint R&D." There is an alternative torch-side path (`coremltools.optimize.torch.PostTrainingPalettizer`), but **SC4 names the coreml-side API verbatim**, so the coreml-side path is canonical. (Confidence: A — verified against coremltools docs.)

3. **Channel count is 96 — this closes the Phase 2 D-11 deferral.** Zenodo 3854034: "*In some sessions recordings were made from both M1 and S1 arrays (**192 channels**); in **most sessions M1 recordings were made alone (96 channels)**.*" Phase 2 D-11 explicitly deferred confirming `CORTEX_CHANNEL_COUNT` ("~96 for O'Doherty Indy") "*against the Zenodo 3854034 dataset in Phase 4*." **Confirmed: use M1-only 96-channel sessions → `CORTEX_CHANNEL_COUNT = 96`.** A Phase-4 task should reconcile this against `cortex_shm.h` / the `CORTEX_CHANNEL_COUNT` `_Static_assert` introduced in Phase 2. (Confidence: A — primary source.)

4. **Phase 4's training objective is masked spike *reconstruction* (Poisson NLL), NOT cursor-velocity decoding.** SC2 = "converges to non-trivial **reconstruction loss** on a held-out split." The NDT is a BERT-style masked-modeling autoencoder over binned spikes (`nn.PoissonNLLLoss`, mask-ratio 0.25). The **(vx, vy) velocity readout is DEC-10 → Phase 5**, and BPS/behavior decoding is PERF-01 → Phase 8. The graph saved for conversion (SC3/SC4) is therefore the **encoder → rate-prediction** forward pass. Do **not** scope-creep a behavior head into Phase 4. (Confidence: A — roadmap SC wording + reference impl.)

---

## 1. Requirement-by-requirement findings

### DEC-01 — NDT1 architecture (6 layers, h∈{1,2}, 128 hidden, 20ms bins, ~1.3M params)
- **What it is:** Ye & Pandarinath 2021, "Representation learning for neural population activity with Neural Data Transformers" (arXiv 2108.01210; NBDT, doi 10.51628/001c.27358). A **non-recurrent Transformer encoder** that models neural population dynamics; 3.9 ms inference on monkey reaching, >6× faster than RNN baselines. Reference code: `snel-repo/neural-data-transformers`.
- **Architecture (verified from reference `src/model.py`):** subclasses `torch.nn.TransformerEncoder` / `TransformerEncoderLayer`. BERT-style **masked language modeling on spike counts** (`MASK_RATIO: 0.25`), loss = `nn.PoissonNLLLoss(reduction='none', log_input=LOGRATE)` computed **only on masked positions**. Learnable positional encoding (`LEARNABLE_POSITION`), `PRE_NORM`, `FIXUP_INIT`/`ScaleNorm` for training stability. Config knobs: `NUM_LAYERS`, `NUM_HEADS`, `HIDDEN_SIZE` (= `dim_feedforward`), `DROPOUT`, `TRIAL_LENGTH` (sequence length).
- **Spec→knob mapping (resolve a naming trap):** the spec's "**128 hidden dim**" = **`d_model = 128`**, NOT `dim_feedforward`. NDT's `HIDDEN_SIZE` config field is the FFN width (`dim_feedforward`) — a *separate* knob the planner tunes to land ~1.3M params. The reference NDT often sets `d_model = num_neurons` (Identity embedder); to get `d_model=128` from 96 channels, use a **linear read-in** `nn.Linear(96→128)` and a **linear readout** `nn.Linear(128→96)`.
- **Param budget (so the SC1 assertion bounds are defensible):** with `d_model=128`, 6 layers, `nhead∈{1,2}`:
  - per layer ≈ `66,688 + 257·F` (attn 66,048 + 2 LayerNorms 512 + FFN `257·F`), where `F = dim_feedforward`
  - 6 layers + read-in (12,416) + readout (12,384) + learnable pos (~6,400) ≈ **`431,584 + 1,542·F`**
  - `F=512` → ~**1.22M**; `F≈560` → ~**1.30M**; `F=600` → ~**1.36M**. **Target `dim_feedforward ≈ 512–600`.**
  - Suggested test: assert structural knobs exactly (`len(layers)==6`, `d_model==128`, `nhead∈{1,2}`, bin width 20 ms) **and** a generous param guardrail (e.g. `1.0e6 ≤ params ≤ 1.6e6`). See §0.1.
- **Recommendation:** port the *architecture* fresh (a clean `torch.nn.TransformerEncoder` + masked-Poisson head) rather than vendoring `snel-repo` wholesale — that repo targets **Python 3.6/3.7**, TF-era LFADS synth data, and `ray[tune]` sweeps (heavy, stale deps). Use it as the **reference for the masking scheme, Poisson head, and config values**, not as a dependency.

### DEC-02 — Training pipeline ingests O'Doherty Indy/Loco (Zenodo 3854034)
- **Dataset (verified, Zenodo record 3854034, v2, O'Doherty/Cardoso/Makin/Sabes 2020):** "Nonhuman Primate Reaching with Multichannel Sensorimotor Cortex Electrophysiology." Self-paced reaches to an 8×8 grid, **not segmented into trials** ("ideal for training BCI decoders"). Two monkeys: **Indy** (37 sessions, ~10 mo, ~20k reaches) + **Loco** (10 sessions, ~1 mo, ~6.5k reaches).
- **File format (`.mat`, per-session, e.g. `indy_20160407_02.mat`):**
  - `spikes` — `n × u` cell array of **spike-event timestamp vectors** (seconds). `u1` = unsorted/hash (threshold crossings); `u2..u5` = sorted units.
  - `cursor_pos` (`k×2`, mm), `finger_pos` (`k×3` or `k×6`, cm), `target_pos` (`k×2`, mm), `t` (`k×1`, s) — behavior sampled at **250 Hz**.
  - `chan_names` (`n×1`), `wf` (`n×u` waveform snippets — large; the bulk of file size).
  - `.mat` is **MATLAB v7.3 = HDF5** → load with `h5py` (or `pymatreader`/`mat73`). `scipy.io.loadmat` does **not** read v7.3.
- **"Synthetic spike replay" defined:** the dataset is *real recorded* spikes; "synthetic replay" = **replaying recorded spike trains offline** through the pipeline (vs. live electrodes — the project has no real BCI hardware in v0/v1, per REQUIREMENTS Out-of-Scope). Phase 4 just trains on the binned recorded data.
- **Preprocessing → model input:** **bin spikes into 20 ms windows** → `(num_bins, 96)` spike-count matrix per session (use M1-only sessions for 96 channels; threshold-crossing/multiunit per channel keeps width = `CORTEX_CHANNEL_COUNT`). Chunk into fixed-length sequences (`TRIAL_LENGTH`, e.g. 30–50 bins = 600–1000 ms). **Held-out split** = chronological tail of each session (the dataset is sequential; `refh_results.csv` itself documents a "sequential from file start (train) / until file end (test)" convention — mirror it to avoid leakage).
- **Convergence metric (SC2):** masked-position **Poisson NLL** on the held-out split; report it as **co-bps (bits-per-spike)** — the Neural Latents Benchmark '21 standard (Pei et al. 2021, arXiv 2109.04463, which packaged *this exact dataset* as the `mc_rtt` task). "Non-trivial" = co-bps meaningfully > 0 (i.e. beats the mean-firing-rate null model).
- **Download scope:** files carry waveform snippets and are sizeable; the raw broadband supplements are very large. **Train on a small subset** (a few Indy M1-only sessions) to demonstrate convergence — do **not** download all 47 sessions. Provide a manifest of the chosen session IDs + a checksum, and a download script (Zenodo is bot-gated on its API — fetch via the record's file URLs, not the `/api/records` endpoint).
- **Alternative loader (cross-check, optional):** NLB packaged `mc_rtt` as **NWB on DANDI** (`pynwb`/`dandi`) — cleaner schema + a ready co-bps evaluator. Canonical source per the roadmap is the **Zenodo `.mat`**, so make that the primary path; NWB is a sanity cross-check only.

### DEC-03 — Trained PyTorch checkpoint converts to `.mlpackage` via coremltools
- **Flow (verified, apple/ml-ane-transformers + coremltools docs):**
  ```python
  import torch, coremltools as ct, numpy as np
  model.eval()
  example = torch.rand(1, 96, 1, S)              # BC1S input (see DEC-04)
  traced = torch.jit.trace(model, example)
  mlmodel = ct.convert(
      traced, convert_to="mlprogram",
      inputs=[ct.TensorType(name="spikes", shape=example.shape, dtype=np.float16)],
      minimum_deployment_target=ct.target.iOS18,  # macOS15; needed for 4-bit grouped palettization
  )
  mlmodel.save("ndt1.mlpackage")
  ```
- **Phase boundary:** convert with **CPU/default compute units only** — do **NOT** set `compute_units=.cpuAndNeuralEngine`, do NOT run Instruments/residency. ANE targeting + `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine` is **DEC-07/Phase 5**. The conversion is just to produce the package that DEC-05 palettizes.
- The output graph = **encoder → predicted rates** (Finding §0.4), input = a `(1, 96, 1, S)` fp16 window.

### DEC-04 — BC1S `(B, C, 1, S)` layout per apple/ml-ane-transformers
- **Verified from Apple's research article ("Deploying Transformers on the Apple Neural Engine," machinelearning.apple.com/research/neural-engine-transformers) — the 4 principles:**
  1. **Data format:** represent the `(B,S,C)` tensor as **4D channels-first `(B, C, 1, S)`** — the ANE's conducive format. **Swap every `nn.Linear` → `nn.Conv2d`** (1×1 conv over the `(B,C,1,S)` tensor). Register a `load_state_dict_pre_hook` that **unsqueezes the `nn.Linear` weights twice** to match the `nn.Conv2d` weight shape (lets you load fp32 Linear weights into the Conv2d model). The **sequence axis S must be the LAST axis** (the last axis of an ANE buffer is unpacked, must be contiguous + 64-byte aligned).
  2. **Chunk attention:** split Q/K/V into an **explicit list of single-head** attentions (smaller chunks → L2 residency + multicore).
  3. **Minimize copies:** do the transpose on the **key** tensor right before the Q·K matmul, and use the **`bchq,bkhc->bkhq` einsum** for scaled-dot-product attention — its layout maps directly to hardware with no intermediate transpose/reshape.
  4. **Bandwidth:** weight palettization (DEC-05) reduces the bandwidth-bound weight traffic.
- **SC3 test ("fails if any tensor retains `(B,S,C)`"):** build the conversion model with `nn.Conv2d` (no `nn.Linear` on the inference path); register **forward hooks**, run a dummy `(1,96,1,S)` input, and **assert every captured activation is rank-4 with `shape[2]==1`** (BC1S), failing if any activation is rank-3 `(B,S,C)`. Complement with a static assert that the inference module tree contains **zero `nn.Linear`** (all replaced by `nn.Conv2d`) and that attention uses the `bchq,bkhc->bkhq` einsum.
- **Reference to read at execution time:** `ane_transformers.reference` in `apple/ml-ane-transformers` (the `LayerNormANE`, `MultiHeadAttention` with the einsum, and the Linear→Conv2d hook are all there to port).

### DEC-05 — 4-bit palettization via `coremltools.optimize.palettize_weights` + `OpPalettizerConfig(nbits=4)`
- **Exact API (verified, coremltools docs):**
  ```python
  import coremltools as ct
  import coremltools.optimize as cto
  model = ct.models.MLModel("ndt1.mlpackage")            # mlprogram from DEC-03
  config = cto.coreml.OptimizationConfig(
      global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=4)
  )
  compressed = cto.coreml.palettize_weights(model, config)
  compressed.save("ndt1_4bit.mlpackage")
  ```
- `OpPalettizerConfig`: `mode="kmeans"` (default; nbits required), `nbits ∈ {1,2,3,4,6,8}` → LUT of `2^nbits` entries (nbits=4 → 16 centroids). `granularity` default `"per_tensor"`; `"per_grouped_channel"` (+`group_size`) is an **iOS18/macOS15** feature → set `minimum_deployment_target=ct.target.iOS18` at conversion if used. **Start with `per_tensor` nbits=4** (matches SC4 verbatim, simplest).
- **SC4 deliverables ("documented size reduction and bounded reconstruction-loss delta"):** (a) record `.mlpackage` size before/after (4-bit LUT ≈ ~4× weight-size reduction vs fp16 weights — measure and report actual); (b) run both the fp16 and palettized packages on the held-out set via `coremltools` CPU prediction, and report **Δ(Poisson NLL / co-bps)**, asserting it stays under a documented bound (set the bound from the observed delta + margin; this is an R&D characterization, not a hard pre-set threshold).
- **Pitfall:** k-means palettization can be **slow / multi-process**; `num_kmeans_workers` tunes it. Run as an offline build step, not in any test hot loop.

---

## Validation Architecture

> This heading is unnumbered intentionally so `/gsd-plan-phase`'s Nyquist gate (`grep "## Validation Architecture"`) detects it and creates `04-VALIDATION.md`. Each phase Success Criterion maps to an automated assertion the planner must turn into a test task.

| # | SC (ROADMAP) | Automated validation | Sampling / signal |
|---|---|---|---|
| 1 | NDT1 spec exact, regression vs h=4 | **Two** asserts: (a) structural — `num_layers==6`, `d_model==128`, **every attention `num_heads ∈ {1,2}`**, bin width==20 ms; (b) param guardrail `1.0e6 ≤ count_parameters(model) ≤ 1.6e6`. **(a) is load-bearing — param count is invariant to head count.** | Construct model, introspect modules + `sum(p.numel())`. Deterministic. |
| 2 | Training converges to non-trivial reconstruction loss on held-out split | Train (short budget acceptable for CI; full run as evidence artifact); assert held-out masked **Poisson NLL / co-bps** beats the mean-rate null by a documented margin; commit the loss curve. | Chronological held-out tail; fixed seed; commit metric JSON + curve (mirror Phase 1/2 evidence-artifact discipline). |
| 3 | Inference graph reshaped to BC1S; test fails on any `(B,S,C)` | Forward-hook every activation on a dummy `(1,96,1,S)` pass → assert **all rank-4 with `shape[2]==1`**; static assert **zero `nn.Linear`** on inference path; assert attention einsum is `bchq,bkhc->bkhq`. | Deterministic dummy forward. Negative control: a `(B,S,C)` variant must make the test fail (prove the trap bites — Phase 1/2 precedent). |
| 4 | `palettize_weights`+`OpPalettizerConfig(nbits=4)` → quantized checkpoint, documented size reduction + bounded loss delta | Assert palettized `.mlpackage` exists + is smaller (record ratio); assert `Δ(NLL/co-bps)` between fp16 and 4-bit ≤ documented bound. | Compare both packages on held-out set via coremltools CPU prediction. |

**Hardware-gating note (mirror Phase 2 D-18):** all Phase-4 validation runs on **any Mac CPU** — there is **no M4/ANE-gated claim** in this phase (that starts Phase 5). CI can run the structural/param/BC1S asserts cheaply; the full training run + palettization characterization are committed **evidence artifacts** (like `sc1-evidence.md`/`sc2-evidence.md`), with a short-budget smoke version for CI.

---

## 3. Environment & repository layout (new subsystem)

- **Python pin is a real blocker:** local Python is **3.14.6**; **torch and coremltools are not installed**, and coremltools (8.x) + PyTorch lag new CPython. **Pin Python 3.11 or 3.12** (coremltools 8.x supported range). Recommend a **`uv`-managed venv** with a pinned interpreter (`uv` honors the global "install what you need" authority and is fast/reproducible).
- **Where Python lives:** this is a Swift repo (`Apps/`, `Packages/`, `Tools/`). Put the decoder R&D in a **dedicated top-level dir** — suggest `Decoder/` (or `python/`) with its own `pyproject.toml` + `uv.lock`, isolated from SwiftPM. Keep artifacts (`.mat` data, checkpoints, `.mlpackage`) **gitignored**; commit only code, configs, manifests (session IDs + checksums), and evidence (loss curves, size/delta JSON).
- **Deps:** `torch` (CPU or MPS wheel), `coremltools>=8`, `numpy`, `h5py` (+ optional `pymatreader`), `pytest`. (`ray[tune]` from the reference repo is **not** needed.)
- **Project rules that bind the Python code:** `ruff` lint + type hints on public funcs; **no bare `except`** (AGENTS.md + cerebrum Do-Not-Repeat); `pytest` + `pytest-asyncio` available; TDD (tests before impl). Mirror the project's "compile-time/structural guarantees beat runtime" ethos → the SC1/SC3 asserts are exactly that for Python.
- **CI:** the existing CI runs on `macos-15`. Decide (planner) whether Phase-4 Python tests run in CI (structural/param/BC1S asserts are cheap and CI-safe; full training is not). Mirror Phase 1/2 split: **CI gates correctness/structure; the convergence + palettization numbers are committed evidence**, not CI-blocking.

---

## 4. Pitfalls (field-checked)

1. **Param count ≠ head-count guard.** (See §0.1.) The most likely silent regression in the whole phase. Assert `num_heads` directly.
2. **`d_model` vs `dim_feedforward` confusion.** "128 hidden" = `d_model`; the FFN width is a separate knob (~512–600) to hit ~1.3M. Mixing these breaks both the size and the param assertion.
3. **`.mat` v7.3 = HDF5.** `scipy.io.loadmat` fails on these; use `h5py`/`pymatreader`/`mat73`. MATLAB cell arrays of spike timestamps need careful dereferencing under h5py.
4. **Palettization requires a converted package.** DEC-05's API is coreml-side; you cannot palettize a raw `.pt`. DEC-03 is a hard prerequisite for DEC-05 (sequence the plan accordingly).
5. **Don't ANE-target in Phase 4.** No `compute_units=.cpuAndNeuralEngine`, no Instruments, no residency assertions — those are Phase 5 and would violate the phase boundary ("no Apple Silicon work yet").
6. **Don't scope-creep a velocity head.** Phase 4 objective is masked spike reconstruction; (vx,vy) is DEC-10/Phase 5. The converted graph outputs rates.
7. **Python 3.14 / version drift.** coremltools/torch may not have 3.14 wheels; pin 3.11/3.12 at env-creation or `ct.convert`/`import torch` will fail at execution time.
8. **Reference repo is stale.** `snel-repo` = Python 3.6, TF-era data, ray sweeps. Port architecture/loss/configs, don't depend on it.
9. **Dataset size.** Don't pull all 47 sessions or the broadband supplements; a few Indy M1 sessions suffice for SC2. Commit a session manifest + checksums for reproducibility (seeds + manifest = deterministic).
10. **Held-out leakage.** Data is continuous (not trial-segmented); split chronologically (tail), don't shuffle-split across time.
11. **Channel-count reconciliation.** 96 must agree with the Phase 2 `CORTEX_CHANNEL_COUNT` `_Static_assert`. If the chosen sessions/units yield ≠96, either filter to 96-channel M1 sessions or surface the mismatch as a cross-phase decision (don't silently diverge from the IPC frame width).

---

## 5. Recommended approach & suggested plan shape

**Pipeline:** `data loader (.mat → 20ms-binned 96-ch sequences) → NDT1 (BC1S, masked-Poisson) → train/eval (held-out co-bps) → ct.convert → palettize(nbits=4) → characterize size+Δloss`.

Suggested wave/plan decomposition (planner refines):
- **Plan A (Wave 1):** Python subsystem scaffold — `Decoder/` + `pyproject.toml` + pinned Python 3.11/3.12 via `uv`, deps, `pytest`, ruff config, `.gitignore` for data/artifacts. (DEC-02 infra)
- **Plan B (Wave 1):** Dataset loader + 20 ms binning + chronological split + session manifest/download script; channel-count==96 reconciliation test vs `CORTEX_CHANNEL_COUNT`. (DEC-02)
- **Plan C (Wave 2):** NDT1 model in **BC1S** form (Conv2d, single-head chunk attention, `bchq,bkhc->bkhq` einsum) + masked-Poisson head; **SC1 tests** (structural `num_heads∈{1,2}` + param guardrail) and **SC3 tests** (BC1S forward-hook + no-`nn.Linear` + negative control). (DEC-01, DEC-04)
- **Plan D (Wave 3):** Training loop (masked modeling) → held-out co-bps convergence + committed loss-curve evidence (short-budget CI smoke + full evidence run). (DEC-02 / SC2)
- **Plan E (Wave 3):** `ct.convert` → `.mlpackage` (CPU, no ANE) then `palettize_weights(OpPalettizerConfig(nbits=4))`; size-reduction + Δloss characterization + evidence doc. (DEC-03, DEC-05)

**Cross-phase outputs to hand forward:** the fp16 checkpoint + 4-bit `.mlpackage` (→ Phase 5 ANE deployment), confirmed `CORTEX_CHANNEL_COUNT=96` (→ reconciles Phase 2 D-11), and the BC1S model definition (→ Phase 5 reuses it for ANE residency).

---

## 6. Sources (verifiable)

- **NDT1 paper** — Ye & Pandarinath 2021, "Representation learning for neural population activity with Neural Data Transformers": https://arxiv.org/abs/2108.01210 · NBDT doi 10.51628/001c.27358
- **NDT reference code** — `snel-repo/neural-data-transformers` (`src/model.py`, `configs/arxiv/*.yaml`): https://github.com/snel-repo/neural-data-transformers
- **Dataset** — Zenodo 3854034 (O'Doherty, Cardoso, Makin, Sabes 2020, "Nonhuman Primate Reaching…", v2): https://zenodo.org/records/3854034
- **Neural Latents Benchmark '21** (packaged this data as `mc_rtt`; co-bps metric) — Pei et al. 2021: https://arxiv.org/abs/2109.04463
- **Apple ANE Transformers** — `apple/ml-ane-transformers` (reference Linear→Conv2d, single-head attention, einsum): https://github.com/apple/ml-ane-transformers
- **Apple research article** — "Deploying Transformers on the Apple Neural Engine" (BC1S + 4 principles): https://machinelearning.apple.com/research/neural-engine-transformers
- **coremltools palettization** — `coremltools.optimize.coreml.OpPalettizerConfig` / `OptimizationConfig` / `palettize_weights`: https://apple.github.io/coremltools/docs-guides/source/opt-palettization-api.html (verified current via Context7 `/apple/coremltools`)
- **coremltools conversion** — `ct.convert(convert_to="mlprogram", minimum_deployment_target=…)`: https://apple.github.io/coremltools/docs-guides/

---

*Phase: 04-ndt1-training-on-indy-loco-synthetic-replay*
*Research method: main-thread browser-harness (`http_get` + real-browser Zenodo) + Context7 `/apple/coremltools`. The GSD HTTP-only subagent researcher was bypassed per project protocol for browser-heavy phases; no main-thread-gated items remain.*
