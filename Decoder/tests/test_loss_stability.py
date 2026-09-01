"""The masked Poisson NLL must not overflow on a forward-pass log-rate excursion (Plan 09-06d).

Plan 09-06c diagnosed, with a committed instrumented replay
(``Decoder/scripts/diagnose_divergence.py``), the one reproducible real-data divergence this
repository has. The ordering is:

  1. the model emits a predicted log-rate far outside the data regime (43.7, then 97.3, against a
     healthy maximum of 13.3 over the preceding three clean epochs),
  2. ``exp`` overflows float32 above about 88.7, so the loss becomes ``inf`` and then ``nan``,
  3. the gradient goes non-finite one step LATER, which is why gradient clipping -- applied and
     measured in 09-06c -- cannot reach this failure and made it fire earlier instead.

The fix is to linearize ``exp`` above a threshold ``C``: the loss at an escaped log-rate becomes
large but FINITE, and its gradient becomes the finite constant ``exp(C)``, which is positive and
therefore pulls the rate back down. ``torch.clamp`` is the wrong tool and this module proves it
rather than asserting it: above the bound a clamped ``exp`` contributes nothing to the derivative,
so the surviving ``- target * rate`` term leaves a NEGATIVE gradient, and a descent step moves an
already-escaped rate further up.

**The load-bearing test in this file is the no-op pair.** A numerical guard is only free if it
cannot change the number being reported, so the stabilized loss is asserted BIT-IDENTICAL to the
unmodified ``nn.PoissonNLLLoss`` formulation -- in value and in gradient -- everywhere below ``C``.
``C = 20`` is 812x further out in rate space than the largest log-rate healthy training has ever
produced here, so the regime all healthy training occupies is provably untouched and the change
activates only on an excursion that would otherwise produce ``nan``.

The reference implementation is written out here rather than imported, so these tests do not depend
on the module they guard.
"""
from __future__ import annotations

import math

import pytest
import torch
from torch import Tensor, nn

from ndt1.loss import LOG_RATE_LINEARIZE_ABOVE, masked_poisson_nll, stable_exp

#: The largest ``max |predicted log-rate|`` observed over three clean epochs of the real training
#: path, from the 09-06c instrumented replay committed in ``diagnose_divergence.py``.
HEALTHY_MAX_LOG_RATE: float = 13.3

#: ``exp`` overflows float32 above about this; ``diagnose_divergence.py`` pins the same bound.
FLOAT32_EXP_OVERFLOW: float = 88.7

#: The log-rate the diverging run actually reached, at step 1365 of the 09-06c replay.
OBSERVED_EXCURSION: float = 97.33


def _reference_masked_poisson_nll(
    rates: Tensor, targets: Tensor, mask: Tensor, *, log_input: bool, eps: float = 1e-8
) -> Tensor:
    """The pre-09-06d implementation, transcribed so the identity tests have an anchor.

    This is exactly what ``ndt1.loss.masked_poisson_nll`` was before the stabilization, including
    its use of ``nn.PoissonNLLLoss``, so "bit-identical to the reference" means "bit-identical to
    the objective every superseded number in this phase was measured under".
    """
    criterion = nn.PoissonNLLLoss(reduction="none", log_input=log_input, eps=eps)
    per_element = criterion(rates, targets)
    mask_f = mask.to(per_element.dtype)
    total = (per_element * mask_f).sum()
    count = mask_f.sum().clamp(min=1.0)
    return total / count


def _value_and_grad(fn, rates: Tensor) -> tuple[Tensor, Tensor]:
    """Evaluate ``fn`` on a fresh leaf copy of ``rates``; return the value and its gradient."""
    leaf = rates.detach().clone().requires_grad_(True)
    value = fn(leaf)
    value.backward()
    assert leaf.grad is not None
    return value.detach(), leaf.grad.detach()


def _below_threshold_grid() -> Tensor:
    """Log-rates spanning the whole regime healthy training occupies, up to just under ``C``.

    Deliberately includes the healthy maximum 13.3 and stops one float32 ulp-ish below ``C``, so
    the identity claim is tested right up against the boundary rather than only in the middle.
    """
    grid = torch.linspace(-40.0, LOG_RATE_LINEARIZE_ABOVE - 1e-3, steps=2048, dtype=torch.float32)
    anchors = torch.tensor(
        [-40.0, -1.2, 0.0, 1.6, HEALTHY_MAX_LOG_RATE, LOG_RATE_LINEARIZE_ABOVE - 1e-4],
        dtype=torch.float32,
    )
    return torch.cat([grid, anchors])


def test_stable_exp_is_bit_identical_to_exp_below_the_threshold() -> None:
    """Below ``C`` the stabilizer is ``torch.exp``, to the bit, in value and in gradient."""
    rates = _below_threshold_grid()
    got_value, got_grad = _value_and_grad(lambda x: stable_exp(x).sum(), rates)
    want_value, want_grad = _value_and_grad(lambda x: torch.exp(x).sum(), rates)
    assert torch.equal(got_value, want_value)
    assert torch.equal(got_grad, want_grad)


def test_masked_poisson_nll_is_bit_identical_below_the_threshold() -> None:
    """The objective itself is unchanged below ``C``, in value and in gradient.

    This is the test that makes the stabilization free: if it passes, no number this repository has
    measured, or will measure on a healthy run, can move because of it.
    """
    rates = _below_threshold_grid()
    torch.manual_seed(0)
    targets = torch.randint(0, 6, rates.shape, dtype=torch.float32)
    mask = torch.rand(rates.shape) < 0.25
    got_value, got_grad = _value_and_grad(
        lambda x: masked_poisson_nll(x, targets, mask, log_input=True), rates
    )
    want_value, want_grad = _value_and_grad(
        lambda x: _reference_masked_poisson_nll(x, targets, mask, log_input=True), rates
    )
    assert torch.equal(got_value, want_value)
    assert torch.equal(got_grad, want_grad)


def test_the_log_input_false_branch_is_untouched() -> None:
    """The stabilization applies to the ``exp`` branch only; the rate-input branch is unchanged."""
    torch.manual_seed(0)
    rates = torch.rand(512, dtype=torch.float32) + 0.05
    targets = torch.randint(0, 6, rates.shape, dtype=torch.float32)
    mask = torch.rand(rates.shape) < 0.25
    got_value, got_grad = _value_and_grad(
        lambda x: masked_poisson_nll(x, targets, mask, log_input=False), rates
    )
    want_value, want_grad = _value_and_grad(
        lambda x: _reference_masked_poisson_nll(x, targets, mask, log_input=False), rates
    )
    assert torch.equal(got_value, want_value)
    assert torch.equal(got_grad, want_grad)


def test_the_threshold_sits_between_the_healthy_maximum_and_float32_overflow() -> None:
    """``C`` is outside every regime healthy training occupies and inside float32's exp range."""
    assert HEALTHY_MAX_LOG_RATE < LOG_RATE_LINEARIZE_ABOVE < FLOAT32_EXP_OVERFLOW
    # In RATE space the margin is what matters: exp(20) is 4.85e8 spikes per 20 ms bin against a
    # corpus maximum of 5, and 812x beyond the largest log-rate healthy training has produced.
    assert math.exp(LOG_RATE_LINEARIZE_ABOVE) / math.exp(HEALTHY_MAX_LOG_RATE) > 500.0
    # And the linear extension has room to spare: even an absurd log-rate stays finite in float32.
    absurd = torch.tensor([1e20], dtype=torch.float32)
    assert torch.isfinite(stable_exp(absurd)).all()


def test_float32_exp_really_does_overflow_above_the_documented_bound() -> None:
    """The premise of this whole module, pinned empirically rather than quoted."""
    over = torch.tensor([FLOAT32_EXP_OVERFLOW + 1.0], dtype=torch.float32)
    under = torch.tensor([FLOAT32_EXP_OVERFLOW - 1.0], dtype=torch.float32)
    assert not torch.isfinite(torch.exp(over)).all()
    assert torch.isfinite(torch.exp(under)).all()


def test_the_observed_excursion_is_non_finite_under_the_reference_loss() -> None:
    """The failure being fixed is real: the pre-09-06d objective goes non-finite at 97.33."""
    rates = torch.full((8,), OBSERVED_EXCURSION, dtype=torch.float32)
    targets = torch.ones(8, dtype=torch.float32)
    mask = torch.ones(8, dtype=torch.bool)
    value, grad = _value_and_grad(
        lambda x: _reference_masked_poisson_nll(x, targets, mask, log_input=True), rates
    )
    assert not torch.isfinite(value).all()
    assert not torch.isfinite(grad).all()


def test_the_observed_excursion_is_finite_under_the_stabilized_loss() -> None:
    """At the log-rate that produced the committed ``nan``, the loss and its gradient are finite."""
    rates = torch.full((8,), OBSERVED_EXCURSION, dtype=torch.float32)
    targets = torch.ones(8, dtype=torch.float32)
    mask = torch.ones(8, dtype=torch.bool)
    value, grad = _value_and_grad(
        lambda x: masked_poisson_nll(x, targets, mask, log_input=True), rates
    )
    assert torch.isfinite(value).all()
    assert torch.isfinite(grad).all()
    assert float(value) > 0.0


def test_the_gradient_above_the_threshold_pulls_the_rate_down() -> None:
    """Above ``C`` the derivative is the finite constant ``exp(C) - target``, and it is positive.

    Positive means a descent step DECREASES the log-rate, which is the whole point: an escaped
    model is given a signal back toward the data regime rather than a dead end.
    """
    target_value = 3.0
    rates = torch.full((4,), LOG_RATE_LINEARIZE_ABOVE + 5.0, dtype=torch.float32)
    targets = torch.full((4,), target_value, dtype=torch.float32)
    mask = torch.ones(4, dtype=torch.bool)
    _, grad = _value_and_grad(
        lambda x: masked_poisson_nll(x, targets, mask, log_input=True).mul(4.0), rates
    )
    expected = math.exp(LOG_RATE_LINEARIZE_ABOVE) - target_value
    assert float(grad[0]) > 0.0
    assert float(grad[0]) == pytest.approx(expected, rel=1e-6)


def test_a_clamped_exp_would_push_an_escaped_rate_further_up() -> None:
    """The control for the design choice: ``torch.clamp`` has the WRONG-SIGNED gradient, not none.

    Above the bound a clamped ``exp`` contributes zero to the derivative, so all that survives is
    the ``- target * rate`` term. Its gradient is ``-target``, which is negative, so a descent step
    increases an already-escaped log-rate. That is worse than no guard, and it is why the
    linearization is used instead.
    """
    target_value = 3.0
    rates = torch.full((4,), LOG_RATE_LINEARIZE_ABOVE + 5.0, dtype=torch.float32)
    targets = torch.full((4,), target_value, dtype=torch.float32)

    def clamped_loss(x: Tensor) -> Tensor:
        capped = torch.clamp(x, max=LOG_RATE_LINEARIZE_ABOVE)
        return (torch.exp(capped) - targets * x).sum()

    _, clamped_grad = _value_and_grad(clamped_loss, rates)
    assert float(clamped_grad[0]) == pytest.approx(-target_value, rel=1e-6)
    assert float(clamped_grad[0]) < 0.0

    mask = torch.ones(4, dtype=torch.bool)
    _, stabilized_grad = _value_and_grad(
        lambda x: masked_poisson_nll(x, targets, mask, log_input=True), rates
    )
    assert float(stabilized_grad[0]) > 0.0


def test_gradient_descent_returns_an_escaped_rate_to_the_data_regime() -> None:
    """End to end: from the observed 97.33, plain SGD on the stabilized loss walks back below ``C``.

    ``lr`` is set from the constant gradient ``exp(C)`` so each step moves the log-rate by about
    half a unit; nothing here is tuned against a result, and the assertion is only that the descent
    goes in the right direction and stays finite the whole way.
    """
    rates = torch.full((8,), OBSERVED_EXCURSION, dtype=torch.float32).requires_grad_(True)
    targets = torch.ones(8, dtype=torch.float32)
    mask = torch.ones(8, dtype=torch.bool)
    optimizer = torch.optim.SGD([rates], lr=1e-9)
    for _ in range(300):
        optimizer.zero_grad(set_to_none=True)
        loss = masked_poisson_nll(rates, targets, mask, log_input=True)
        assert torch.isfinite(loss).all()
        loss.backward()
        optimizer.step()
    assert torch.isfinite(rates).all()
    assert float(rates.max()) < LOG_RATE_LINEARIZE_ABOVE
