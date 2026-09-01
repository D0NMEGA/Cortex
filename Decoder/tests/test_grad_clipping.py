"""Gradient-norm clipping in the NDT1 training loop (Plan 09-06c).

The `log_input=True` Poisson NLL has model term ``exp(rate) - target * rate``, so a single
predicted log-rate excursion overflows and the gradients go non-finite. Without clipping, AdamW has
nothing to arrest that: the failure fired three times on real Indy spikes under the Plan 09-06b
objective (two LOSO folds and the committed slow gate), and it is the reason
``tests/test_heldout_cobps.py`` was red on main. See ``deferred-items-09-06b.md`` item 1.

These tests are quick (a 32-d, 1-layer NDT1ANE on eight synthetic windows, no dataset) and they are
behavioural rather than a source grep:

  * a control that the pathological batch really does blow the unclipped loop up, so the clipped
    result cannot pass for the wrong reason,
  * the same batch under the DEFAULT settings, which must stay finite and descend, and
  * a spy proving the clip is actually binding on that batch rather than decorative.

The clip is applied by default, because a numerical-stability guard that every caller has to
remember to switch on is one the next caller will forget.
"""
from __future__ import annotations

import math
from unittest import mock

import numpy as np
import pytest
import torch
from torch.utils.data import DataLoader, TensorDataset

import ndt1.train as train_module
from ndt1.model_ane import NDT1ANE
from ndt1.train import DEFAULT_GRAD_CLIP_NORM, train_ndt1

#: A learning rate far above the 2e-3 the evidence runs use. It is not a claim about the real
#: config; it is the smallest knob that reproduces the real failure mode (an exp() overflow in the
#: Poisson NLL) in under a second, so the guard can be tested without a 16-minute training run.
_DIVERGING_LR: float = 0.2
_BURST_COUNT: float = 10.0
_EPOCHS: int = 6
_SEED: int = 0


def _pathological_loader(seed: int = _SEED) -> DataLoader:
    """Sparse Poisson counts with a few large bursts: the shape that overflows ``exp(rate)``."""
    rng = np.random.default_rng(seed)
    counts = rng.poisson(0.2, size=(8, 32, 96)).astype(np.float32)
    flat = counts.reshape(-1)
    flat[rng.integers(0, flat.size, size=40)] = _BURST_COUNT
    return DataLoader(TensorDataset(torch.from_numpy(counts)), batch_size=4, shuffle=False)


def _small_model() -> NDT1ANE:
    torch.manual_seed(_SEED)
    return NDT1ANE(seq_len=32, d_model=32, num_layers=1, num_heads=2, dim_feedforward=64)


def test_the_pathological_batch_diverges_when_clipping_is_disabled() -> None:
    """The control. Without the guard this batch goes non-finite, so the guard has work to do."""
    history = train_ndt1(
        _small_model(),
        _pathological_loader(),
        epochs=_EPOCHS,
        lr=_DIVERGING_LR,
        log_input=True,
        device="cpu",
        seed=_SEED,
        grad_clip_norm=None,
    )
    losses = history["losses"]
    assert not all(math.isfinite(x) for x in losses), (
        f"the unclipped loop stayed finite on the batch built to blow it up, so this module is "
        f"not testing anything: per-epoch loss {losses}"
    )


def test_the_default_keeps_the_same_batch_finite_and_descending() -> None:
    """No ``grad_clip_norm`` argument at all: the stability guard must be on by default."""
    history = train_ndt1(
        _small_model(),
        _pathological_loader(),
        epochs=_EPOCHS,
        lr=_DIVERGING_LR,
        log_input=True,
        device="cpu",
        seed=_SEED,
    )
    losses = history["losses"]
    assert all(math.isfinite(x) for x in losses), (
        f"training went non-finite with the default clip: per-epoch loss {losses}"
    )
    assert losses[-1] < losses[0], (
        f"the clipped loop stayed finite but did not train: final loss {losses[-1]:.6g} is not "
        f"below the first epoch's {losses[0]:.6g}. Per-epoch loss {losses}"
    )


def test_the_clip_is_binding_and_is_applied_at_every_step() -> None:
    """Spy on the real clip: called once per optimizer step, at the configured norm, and binding."""
    real_clip = train_module.clip_grad_norm_
    observed: list[float] = []

    def spy(parameters: object, max_norm: float, **kwargs: object) -> torch.Tensor:
        total = real_clip(parameters, max_norm, **kwargs)  # type: ignore[arg-type]
        observed.append(float(total))
        assert max_norm == DEFAULT_GRAD_CLIP_NORM
        return total

    loader = _pathological_loader()
    with mock.patch.object(train_module, "clip_grad_norm_", spy):
        train_ndt1(
            _small_model(),
            loader,
            epochs=_EPOCHS,
            lr=_DIVERGING_LR,
            log_input=True,
            device="cpu",
            seed=_SEED,
        )

    assert len(observed) == _EPOCHS * len(loader), (
        f"clip_grad_norm_ ran {len(observed)} times for {_EPOCHS * len(loader)} optimizer steps; "
        f"it must run on every step, not on some of them"
    )
    assert max(observed) > DEFAULT_GRAD_CLIP_NORM, (
        f"the largest pre-clip gradient norm observed was {max(observed):.6g}, which never exceeds "
        f"the {DEFAULT_GRAD_CLIP_NORM} cap, so the clip never bound and this test would pass "
        f"against a no-op"
    )


def test_the_default_clip_norm_is_the_conventional_one() -> None:
    """1.0 is the a-priori convention, not a value swept for a better co-bps."""
    assert DEFAULT_GRAD_CLIP_NORM == pytest.approx(1.0)
