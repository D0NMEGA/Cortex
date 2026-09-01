"""Gradient-norm clipping in the NDT1 training loop (Plan 09-06c).

The ``log_input=True`` Poisson NLL has model term ``exp(rate) - target * rate``, so a single
predicted log-rate excursion overflows and the gradients explode. Without clipping, AdamW has
nothing to arrest that: one outlier gradient poisons the first-moment estimate and the run never
recovers. The failure fired three times on real Indy spikes under the Plan 09-06b objective (two
LOSO folds and the committed slow gate), which is why ``tests/test_heldout_cobps.py`` was red on
main. See ``deferred-items-09-06b.md`` item 1.

**What these tests are, and are not.** They are a quick regression guard (a 32-d, 1-layer NDT1ANE
on eight synthetic windows, no dataset, under a second) proving the clip is wired in, binding, and
outcome-changing. They are NOT the verification that clipping fixes the real divergence: the proxy
below reaches the same *signature* as the real failure (a run that stays finite but ends above
where it started) by inflating the learning rate to 0.05, not by reproducing the real 2e-3
dynamics. The real verification is the committed slow gate re-run on real spikes, recorded in
``09-training-evidence.md``.

**A limit worth stating, because it is easy to over-claim.** A norm cap does not make any learning
rate safe. AdamW normalizes each coordinate by its own second-moment estimate, so rescaling the
whole gradient vector leaves the per-coordinate step roughly at ``lr``; the clip stops an outlier
gradient from poisoning the moments, it does not stop an oversized step. Measured here: at
``lr = 0.1`` on this same batch the clipped run diverges too. The guard buys stability against
gradient spikes at a sane learning rate, and nothing more.
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
#: config; it is the smallest knob that reproduces the real failure SIGNATURE (a finite run that
#: ends above where it started) in under a second, so the guard has a test that does not need a
#: 16-minute training run.
_PROXY_LR: float = 0.05
_BURST_COUNT: float = 10.0
_EPOCHS: int = 8
#: Two seeds, because a single seed would make the difference below a coin flip rather than an
#: effect. Both are seeds on which the unclipped loop fails; a third (seed 2) does not fail
#: unclipped and is deliberately not used to claim more than the guard is worth.
_SEEDS: tuple[int, ...] = (0, 1)


def _pathological_loader(seed: int) -> DataLoader:
    """Sparse Poisson counts with a few large bursts: the shape that overflows ``exp(rate)``."""
    rng = np.random.default_rng(seed)
    counts = rng.poisson(0.2, size=(8, 32, 96)).astype(np.float32)
    flat = counts.reshape(-1)
    flat[rng.integers(0, flat.size, size=40)] = _BURST_COUNT
    return DataLoader(TensorDataset(torch.from_numpy(counts)), batch_size=4, shuffle=False)


def _small_model(seed: int) -> NDT1ANE:
    torch.manual_seed(seed)
    return NDT1ANE(seq_len=32, d_model=32, num_layers=1, num_heads=2, dim_feedforward=64)


def _losses(seed: int, **clip_kwargs: float | None) -> list[float]:
    history = train_ndt1(
        _small_model(seed),
        _pathological_loader(seed),
        epochs=_EPOCHS,
        lr=_PROXY_LR,
        log_input=True,
        device="cpu",
        seed=seed,
        **clip_kwargs,  # type: ignore[arg-type]
    )
    return list(history["losses"])  # type: ignore[arg-type]


def _trained(losses: list[float]) -> bool:
    """The same "did it train" criterion the committed slow gate applies to a real run."""
    return all(math.isfinite(x) for x in losses) and losses[-1] < losses[0]


def test_the_pathological_batch_does_not_train_when_clipping_is_disabled() -> None:
    """The control. Without the guard this batch ends above where it started, so it has work."""
    for seed in _SEEDS:
        losses = _losses(seed, grad_clip_norm=None)
        assert not _trained(losses), (
            f"seed {seed}: the unclipped loop trained on the batch built to destabilize it, so "
            f"this module is not testing anything. Per-epoch loss {losses}"
        )


def test_the_default_recovers_a_descending_curve_on_the_same_batch() -> None:
    """No ``grad_clip_norm`` argument at all: the stability guard must be on by default."""
    for seed in _SEEDS:
        losses = _losses(seed)
        assert _trained(losses), (
            f"seed {seed}: with the default clip the loop still did not train. Final loss "
            f"{losses[-1]:.6g} against a first epoch of {losses[0]:.6g}. Per-epoch loss {losses}"
        )


def test_the_clip_is_binding_and_is_applied_at_every_step() -> None:
    """Spy on the real clip: called once per optimizer step, at the configured norm, and binding."""
    real_clip = train_module.clip_grad_norm_
    observed: list[float] = []
    norms_requested: list[float] = []

    def spy(parameters: object, max_norm: float, **kwargs: object) -> torch.Tensor:
        total = real_clip(parameters, max_norm, **kwargs)  # type: ignore[arg-type]
        observed.append(float(total))
        norms_requested.append(max_norm)
        return total

    seed = _SEEDS[0]
    loader = _pathological_loader(seed)
    with mock.patch.object(train_module, "clip_grad_norm_", spy):
        train_ndt1(
            _small_model(seed),
            loader,
            epochs=_EPOCHS,
            lr=_PROXY_LR,
            log_input=True,
            device="cpu",
            seed=seed,
        )

    assert len(observed) == _EPOCHS * len(loader), (
        f"clip_grad_norm_ ran {len(observed)} times for {_EPOCHS * len(loader)} optimizer steps; "
        f"it must run on every step, not on some of them"
    )
    assert set(norms_requested) == {DEFAULT_GRAD_CLIP_NORM}, (
        f"the clip was requested at {sorted(set(norms_requested))}, not at the documented "
        f"{DEFAULT_GRAD_CLIP_NORM}"
    )
    assert max(observed) > DEFAULT_GRAD_CLIP_NORM, (
        f"the largest pre-clip gradient norm observed was {max(observed):.6g}, which never exceeds "
        f"the {DEFAULT_GRAD_CLIP_NORM} cap, so the clip never bound and this test would pass "
        f"against a no-op"
    )


def test_the_default_clip_norm_is_the_conventional_one() -> None:
    """1.0 is the a-priori convention, not a value swept for a better co-bps."""
    assert DEFAULT_GRAD_CLIP_NORM == pytest.approx(1.0)


def test_the_history_records_whether_the_run_was_clipped() -> None:
    """A committed metrics JSON must say which of the two regimes produced its numbers."""
    seed = _SEEDS[0]
    clipped = train_ndt1(
        _small_model(seed),
        _pathological_loader(seed),
        epochs=1,
        lr=_PROXY_LR,
        log_input=True,
        device="cpu",
        seed=seed,
    )
    unclipped = train_ndt1(
        _small_model(seed),
        _pathological_loader(seed),
        epochs=1,
        lr=_PROXY_LR,
        log_input=True,
        device="cpu",
        seed=seed,
        grad_clip_norm=None,
    )
    assert clipped["config"]["grad_clip_norm"] == DEFAULT_GRAD_CLIP_NORM  # type: ignore[index]
    assert unclipped["config"]["grad_clip_norm"] is None  # type: ignore[index]
