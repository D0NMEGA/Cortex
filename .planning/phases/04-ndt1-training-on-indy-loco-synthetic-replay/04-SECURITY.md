---
phase: 04
slug: ndt1-training-on-indy-loco-synthetic-replay
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-21
---

# Phase 04 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.
> Phase 04 is the **Decoder/ Python ML subsystem** (NDT1 ~1.3M-param spiking
> decoder, training loop, CoreML conversion + 4-bit palettization). It is
> **local, single-user, offline R&D** — no network services, no auth, no
> user-facing endpoints. ASVS L1 applies (no session/access-control surface).
> The realistic risk surface is **supply-chain, untrusted-deserialization,
> artifact-leak-into-git, and correctness-integrity** (a silently-wrong
> artifact invalidates the project's credibility claim).

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| PyPI registry → local venv | `uv` pulls torch / coremltools / numpy / h5py wheels — supply-chain surface | wheel bytes (executable) |
| filesystem → git | large binary artifacts (datasets, checkpoints, `.mlpackage`) could be committed and leak / bloat history | dataset & model binaries |
| Zenodo (network) → local disk | downloaded Indy/Loco `.mat` dataset files — untrusted bytes from the internet | external neural-recording bytes |
| `.mat` file (HDF5) → loader (h5py) | parsing an externally-produced HDF5 file — malformed / oversized input | spike-count / timestamp arrays |
| Python channel constant → Swift/Rust constants | the 96-channel width must not silently diverge from the IPC frame width | integer width contract |
| spec / roadmap intent → model code | architecture must match the verified NDT1 spec (h ∈ {1,2}, BC1S, ~1.3M params) | correctness invariant |
| Phase-4 scope → Phase-5 scope | no ANE targeting / velocity head / residency may leak into this phase | scope boundary |
| checkpoint `.pt` → `torch.load` | deserializing a saved model — pickle can execute arbitrary code | serialized tensors |
| training data → loss / metric | a degenerate dataset could make co-bps meaningless (silent correctness failure) | float metrics |
| `.mlpackage` / checkpoint → coremltools load | loading a model package — deserialization surface | serialized model |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation (evidence) | Status |
|-----------|----------|-----------|-------------|-----------------------|--------|
| T-04-01-01 | Tampering | dependency supply chain (torch/coremltools/numpy/h5py wheels) | mitigate | Floors pinned `pyproject.toml:6-11`; hash-locked `uv.lock` (torch 2.12.1, coremltools 9.0); no unpinned `pip install` in tree. | closed |
| T-04-01-02 | Information Disclosure | accidental commit of dataset / checkpoints into git | mitigate | `.gitignore:67-76` — `git check-ignore` positive for `.venv/`, `*.mat`, `checkpoints/*.pt`, `*.ckpt`, `*.mlpackage/`. | closed |
| T-04-01-03 | Elevation of Privilege | interpreter newer than supported coremltools range pulls untested wheels | **accept** | `.python-version:1` pins `3.12`; `pyproject.toml:5` `requires-python = ">=3.11,<3.13"` forecloses 3.14 at the resolver. See Accepted Risks Log. | closed |
| T-04-01-04 | Denial of Service | bare `except` swallowing errors masking a broken env | mitigate | `ruff.toml:5` `select=[…,"BLE"]`; zero `except:`/`except Exception` across all impl files. | closed |
| T-04-02-01 | Tampering | downloaded `.mat` integrity (MITM / corrupted mirror) | mitigate | `download_indy.py:24,47-53,88-98` — streaming SHA-256 verified vs committed manifest, raises `ValueError` on mismatch. | closed |
| T-04-02-02 | Denial of Service | h5py parsing a malformed / huge `.mat` (`wf` array) exhausts memory | mitigate | `data.py:167,187-240` reads ONLY `spikes`/`t`; `wf` never referenced; explicit `OSError`/`KeyError`/`ValueError`. | closed |
| T-04-02-03 | Tampering | channel width silently diverges from IPC frame width (96) | mitigate | `test_channel_count_reconcile.py:70-106` reconciles 3 native homes + negative control; `data.py:226-230` raises on `≠96`. | closed |
| T-04-02-04 | Information Disclosure | dataset `.mat` accidentally committed to git | mitigate | `.gitignore:68-69` — `Decoder/data/` + `Decoder/**/*.mat` `git check-ignore` positive; no `.mat` tracked. | closed |
| T-04-03-01 | Tampering | architecture silently drifts to h=4 (documented miscitation) | mitigate | `test_architecture_structural.py:32-46` asserts `num_heads ∈ {1,2}` on EVERY `ANEAttention` module. | closed |
| T-04-03-02 | Tampering | vanilla `(B,S,C)` tensor on inference path → evicted off ANE | mitigate | `test_bc1s_activations.py:50-55` forward-hook rank-4 + shape[2]==1 + negative control (75-81); `test_no_linear_on_inference_path.py:19-23` zero `nn.Linear`. | closed |
| T-04-03-03 | Repudiation | param / layer drift undetected | mitigate | `test_param_count.py:16-23` guardrail `1.0e6 ≤ params ≤ 1.6e6` + tight ~1.3M band. | closed |
| T-04-03-04 | Elevation of Privilege | Phase-5 ANE/velocity scope creeps into Phase 4 | mitigate | Zero `computeUnits`/`_ANEClient`/`cpuAndNeuralEngine`/`vx`/`vy`/`velocity` tokens in `model_ane.py`/`attention.py` (grep clean). | closed |
| T-04-03-05 | Denial of Service | blind `except` swallowing a real model error in a hook | mitigate | Zero `except:`/`except Exception` in `attention.py`/`model_ane.py`; hook uses `isinstance` guard; BLE active. | closed |
| T-04-04-01 | Elevation of Privilege | `torch.load` of checkpoint executing arbitrary pickle code | mitigate | `train.py:185` `torch.load(path, map_location="cpu", weights_only=True)`; explicit `(RuntimeError, EOFError)` re-raise. | closed |
| T-04-04-02 | Tampering | meaningless / degenerate convergence claim (co-bps not beating null) | mitigate | `metrics.py:66-106` co-bps vs mean-rate null; evidence co-bps 0.3804 vs 0.0 (~7.6× over 0.05 margin); chronological-tail split `data.py:103-130`. | closed |
| T-04-04-03 | Repudiation | the SC2 number is unreproducible | mitigate | `train.py:93,100` fixed `seed`; `04-training-evidence.md` records config + runbook; `test_training_smoke.py:45-61` identical trajectory. | closed |
| T-04-04-04 | Denial of Service | blind `except` hiding a NaN / divergence | mitigate | Zero blind `except` in `train.py`/`metrics.py`; `test_training_smoke.py:40-42` asserts finite + decreasing loss; BLE active. | closed |
| T-04-05-01 | Elevation of Privilege | loading a malicious `.mlpackage` / checkpoint via coremltools/torch | mitigate | `convert.py:56-83` traces only the in-repo `NDT1ANE`; `palettize.py:43-45` loads self-produced pkg w/ explicit `OSError`; checkpoint inherits `weights_only=True`. | closed |
| T-04-05-02 | Tampering | claimed 4-bit size / Δloss is unverifiable or wrong | mitigate | `palettize.py:66-73` byte-sum measurement; `04-palettization-evidence.md` fp16 2,678,038 B / 4-bit 771,534 B (3.471×), NLL Δ 0.009114 ≤ 0.5 bound (CPU predict). | closed |
| T-04-05-03 | Elevation of Privilege | Phase-5 ANE scope (computeUnits/residency/Instruments) creeps in | mitigate | Zero `cpuAndNeuralEngine`/`_ANEClient`/`Instruments`/`residency`/`computeUnits` in `convert.py`/`palettize.py`; no compute-unit kwarg at `convert.py:63-74`. | closed |
| T-04-05-04 | Denial of Service | blind `except` masking a convert / palettize failure | mitigate | Explicit `(RuntimeError, ValueError)` / `OSError` at `convert.py:75`, `palettize.py:44,55`; zero blind `except`; BLE active. | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-04-01 | T-04-01-03 | Running an interpreter newer than the coremltools-tested range would pull untested wheels. Foreclosed at the resolver: `.python-version` pins 3.12 and `requires-python = ">=3.11,<3.13"` rejects 3.14. Residual risk is low — local, single-user, offline R&D with a uv-managed interpreter; no multi-user or CI exposure. | d0nmega (gsd-secure-phase) | 2026-06-21 |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-21 | 21 | 21 | 0 | gsd-security-auditor (sonnet), orchestrated by /gsd-secure-phase |

**Audit notes (2026-06-21):** Independent read-only verification of all 21
threats against actual source (50 tool uses). All 20 `mitigate` dispositions
CLOSED with concrete `file:line` evidence; the 1 `accept` (T-04-01-03)
confirmed documented. The ruff **BLE** gate is the structural backbone
enforcing the no-bare-except hard rule across the whole subsystem — present in
`ruff.toml` and clean (zero violations) in all eight implementation files. The
`weights_only=True` deserialization guard, SHA-256 integrity gate, gitignore
artifact exclusions, phase-boundary ANE-token greps, and correctness-invariant
tests (SC1a/SC1b/SC3a/SC3b/co-bps margin) all independently confirmed. No gaps,
no unregistered flags.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-21
