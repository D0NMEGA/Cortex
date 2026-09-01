"""Held-out co-bps convergence test for NDT1 (Plan 04-04 Task 3, SC2) — @pytest.mark.slow.

SC2: "Training loop ingests Zenodo 3854034 and converges to non-trivial reconstruction loss on a
held-out split." This test runs a short-but-REAL training budget, then asserts the trained model's
**held-out co-bps beats the train-split mean-firing-rate null** by a documented positive margin.

It is marked ``@pytest.mark.slow`` so the quick CI gate (``-m "not slow"``) excludes it — the quick
gate only proves convergence DIRECTION (``test_training_smoke.py``); the full
training-to-convergence number is the committed evidence artifact (``04-training-evidence.md``).

**Runs without the gitignored dataset:** if a real Indy ``.mat`` is present under ``Decoder/data/``
(materialized via Plan 04-02's ``download_indy.py``), it is preferred; OTHERWISE the test falls back
to a deterministic SYNTHETIC Poisson dataset whose per-channel rate is a smooth time-varying signal
the model can learn but the global per-channel mean (the null) cannot — so a non-trivial co-bps is
both achievable and meaningful. A fixed seed keeps the held-out number reproducible (T-04-04-03).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest
import torch
from torch.utils.data import DataLoader

from ndt1.data import IndySpikeDataset, chronological_split
from ndt1.loss import random_mask
from ndt1.metrics import co_bps, mean_firing_rate
from ndt1.model_ane import NDT1ANE
from ndt1.sessions import available_sessions
from ndt1.train import masked_forward, reshape_to_bc1s, train_ndt1

# --- Training config (committed in the evidence artifact; fixed for reproducibility) ----------
SEED: int = 0
SEQ_LEN: int = 32
EPOCHS: int = 12
LR: float = 2e-3
TEST_FRAC: float = 0.2
BATCH_SIZE: int = 16
# Documented margin, RE-DERIVED from the real-data observation (Plan 09-06c, D-22), machine-derived
# by `train_real.py --derive-margin` and bound to the committed JSON by tests/test_cobps_margin.py.
#
# The pooled held-out co-bps measured on the four real Indy M1 sessions under the corrected
# objective, with gradient clipping and the pre-registered convergence rule, is 0.0713 bits/spike
# against the train-split mean-rate null, and 0.0094 is 13.1% of that: the fraction Phase 4 used
# when it set 0.05 against an observed 0.3804, applied unchanged so that the observation is the
# only input to the derivation. The RULE has never moved across three re-derivations; only the
# observation it reads has.
#
# Read 09-training-evidence.md before reading this constant. Three predecessors are superseded and
# all three are named below so a regression says WHY:
#   0.05    Phase 4, from 0.3804 on a purpose-built learnable synthetic sinusoid
#   0.25    Plan 09-06, from 1.9116 under an objective the encoder could read the answers through
#   0.00082 Plan 09-06b, from 0.0062 at a fixed 12-epoch unclipped budget on a curve that had not
#           flattened and whose training diverged in one LOSO fold and in this very gate
#
# It is NOT inflated to look like a pass, and this gate does not currently reach the assertion at
# all: its own training path still diverges (see the module docstring and deferred-items-09-06c.md).
CO_BPS_MARGIN: float = 0.0094

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"
_CHECKPOINT_DIR = Path(__file__).resolve().parent.parent / "checkpoints"


def _make_synthetic(num_bins: int = 4000, num_channels: int = 96, seed: int = SEED) -> np.ndarray:
    """Deterministic synthetic Poisson spike counts with LEARNABLE per-channel temporal structure.

    Each channel's instantaneous rate is ``base_c + amp_c * (0.5 + 0.5*sin(2π f_c t + φ_c))`` — a
    smooth, always-positive, per-channel sinusoid (distinct frequency/phase/baseline per channel).
    The global per-channel MEAN (the null) averages this away; a sequence model that sees the
    surrounding context CAN predict the local rate, so beating the null is non-trivial and real.
    """
    rng = np.random.default_rng(seed)
    t = np.arange(num_bins)
    freqs = rng.uniform(0.01, 0.05, size=num_channels)
    phases = rng.uniform(0.0, 2.0 * np.pi, size=num_channels)
    base = rng.uniform(0.3, 1.2, size=num_channels)
    amp = base * 0.8
    rate = base[None, :] + amp[None, :] * (
        0.5 + 0.5 * np.sin(2.0 * np.pi * freqs[None, :] * t[:, None] + phases[None, :])
    )
    return rng.poisson(rate).astype(np.float32)


def _load_binned() -> tuple[np.ndarray, str]:
    """Prefer real sessions when present; excluded sessions are skipped, never raised (P5).

    The naive concatenation here is only the smoke path for this single test. The D-12-correct
    per-session chronological split used for the committed numbers is
    ``ndt1.sessions.pooled_splits``, driven by the Plan 09-06 evidence runner.
    """
    loaded, excluded = available_sessions(_DATA_DIR, min_bins=10 * SEQ_LEN)
    if loaded:
        pooled = np.concatenate([s.binned for s in loaded], axis=0)
        ids = ", ".join(s.session_id for s in loaded)
        note = f" (excluded: {len(excluded)})" if excluded else ""
        return pooled, f"real sessions [{ids}]{note}"
    return _make_synthetic(), "synthetic Poisson fallback (no .mat present)"


def _stack_windows(dataset: IndySpikeDataset) -> torch.Tensor:
    """Stack all ``(S, C)`` windows of a dataset into a single ``(N, S, C)`` batch."""
    return torch.stack([dataset[i] for i in range(len(dataset))])


@pytest.mark.slow
def test_heldout_cobps_beats_mean_rate_null() -> None:
    """Short-budget training → held-out co-bps beats the train-split mean-rate null by a margin."""
    binned, source = _load_binned()
    train_binned, test_binned = chronological_split(binned, test_frac=TEST_FRAC)
    train_ds = IndySpikeDataset(train_binned, seq_len=SEQ_LEN)
    test_ds = IndySpikeDataset(test_binned, seq_len=SEQ_LEN)
    assert len(train_ds) > 0 and len(test_ds) > 0, "split produced an empty train/test set"

    loader = DataLoader(train_ds, batch_size=BATCH_SIZE, shuffle=False)
    torch.manual_seed(SEED)
    model = NDT1ANE(seq_len=SEQ_LEN)
    history = train_ndt1(
        model, loader, epochs=EPOCHS, lr=LR, log_input=True, device="cpu", seed=SEED
    )

    # Held-out co-bps: score the model on a masked held-out batch vs the TRAIN-split mean rate.
    test_bc1s = reshape_to_bc1s(_stack_windows(test_ds))
    train_bc1s = reshape_to_bc1s(_stack_windows(train_ds))
    null_rate = mean_firing_rate(train_bc1s)  # null = train-split per-channel mean (no leakage)
    gen = torch.Generator()
    gen.manual_seed(SEED)
    mask = random_mask(test_bc1s.shape, model.mask_ratio, generator=gen)

    # masked_forward, not model(test_bc1s): the scored positions must be hidden from the encoder
    # here exactly as they are during training (Plan 09-06b). Scoring with the input visible while
    # training with it hidden measures a different objective than the one that produced the weights.
    model.eval()
    with torch.no_grad():
        rates = masked_forward(model, test_bc1s, mask)
    heldout_co_bps = co_bps(rates, test_bc1s, mask, null_rate, log_input=True)

    # Persist the SC2 metrics to a gitignored JSON for the evidence artifact (not a CI gate).
    _CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    (_CHECKPOINT_DIR / "sc2_metrics.json").write_text(
        json.dumps(
            {
                "source": source,
                "held_out_co_bps": heldout_co_bps,
                "co_bps_margin": CO_BPS_MARGIN,
                "losses": history["losses"],
                "config": history["config"],
            },
            indent=2,
        )
    )

    # Order matters. The "did it train" checks come FIRST so that a diverged run reports the
    # divergence instead of reporting a meaningless co-bps as if it were a model-quality verdict.
    # Both assertions already existed; only their position changed (Plan 09-06b). The
    # log_input=True Poisson NLL has model term exp(rate) - target*rate, so a predicted log-rate
    # excursion overflows and there is no gradient clipping at lr=2e-3 to arrest it. That failure
    # mode is live on this data: see 09-training-evidence.md and deferred-items-09-06b.md item 1.
    losses = history["losses"]
    assert all(math.isfinite(x) for x in losses), (
        f"training did not stay finite, so the co-bps below is a divergence artifact and not a "
        f"measure of anything: per-epoch loss {losses}"
    )
    assert losses[-1] < losses[0], (
        f"the loop did not train: final loss {losses[-1]:.6g} is not below the first epoch's "
        f"{losses[0]:.6g}. Per-epoch loss {losses}. A co-bps computed from these weights "
        f"(observed: {heldout_co_bps:.5f}) describes the divergence, not the model."
    )

    assert heldout_co_bps > CO_BPS_MARGIN, (
        f"held-out co_bps {heldout_co_bps:.5f} did not beat the mean-rate null by the documented "
        f"margin {CO_BPS_MARGIN} (source: {source})"
    )
