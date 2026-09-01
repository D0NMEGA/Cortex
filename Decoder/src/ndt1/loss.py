"""Masked Poisson NLL reconstruction loss for NDT1 (Plan 04-03, DEC-01).

NDT is a BERT-style masked-modeling autoencoder over binned spike counts
(snel-repo/neural-data-transformers ``src/model.py``): a fraction ``mask_ratio`` (0.25) of
bins is masked, and the loss is the Poisson negative log-likelihood computed **only on the
masked positions**. Masking means two things at once, and this module supplies both:
``random_mask`` chooses the positions, ``hide_scored_positions`` removes them from the encoder
input, and ``masked_poisson_nll`` scores them against the true counts. Dropping the second is
what made every co-bps this repository published before Plan 09-06b a self-reconstruction score
rather than a context-only one. ``nn.PoissonNLLLoss(reduction='none')`` gives the per-element
loss; we sum it over the mask and divide by the number of masked positions (guarded against an
empty mask so the loss is always finite).
"""
from __future__ import annotations

import math

import torch
from torch import Tensor, nn

DEFAULT_MASK_RATIO: float = 0.25

#: Predicted log-rates above this are scored on a LINEARIZATION of ``exp`` rather than on ``exp``
#: itself (Plan 09-06d). Below it nothing changes, to the bit.
#:
#: **Why a threshold is needed.** With ``log_input=True`` the Poisson NLL model term is
#: ``exp(x) - target * x``. Plan 09-06c instrumented the one reproducible real-data divergence this
#: repository has, step by step (``scripts/diagnose_divergence.py``), and found the ordering to be:
#: the model emits a log-rate of 43.7 on a batch it had already seen three times without incident;
#: eight steps later the log-rate reaches 97.33; ``exp`` overflows float32 above about 88.7; the
#: loss becomes ``nan``; the gradient goes non-finite one step LATER. Gradient clipping therefore
#: acts on the symptom after the cause, which is why 09-06c measured it NOT fixing this failure.
#:
#: **Why 20.** It has to be far outside every regime healthy training occupies, and far inside
#: float32's exp range:
#:
#: * Real 20 ms bins in this corpus carry 0 to 5 spikes and the per-channel mean rate is about 0.3
#:   spikes/bin, so a healthy log-rate sits near ``log(0.3) = -1.2``. The largest ``|log-rate|``
#:   ever observed over a clean epoch of this training path is 13.3 (09-06c's replay).
#: * ``exp(20)`` is 4.85e8 spikes per 20 ms bin: eight orders of magnitude beyond the largest count
#:   in the data, and 812x further out in rate space than that observed healthy maximum.
#: * Going higher buys nothing -- the loss at the threshold is already astronomically large -- and
#:   costs headroom twice over: ``exp(C)`` is the constant gradient above the threshold, and both
#:   the linear extension and the sum of squares inside ``clip_grad_norm_`` have to stay inside
#:   float32. At ``C = 20`` the linear branch is still finite at a log-rate of 1e20.
#:
#: Nothing here was chosen by looking at a co-bps: the value is fixed by the data range and by
#: float32, and ``tests/test_loss_stability.py`` proves the loss is bit-identical below it in value
#: AND in gradient, so the guard cannot move a number produced by a healthy run.
LOG_RATE_LINEARIZE_ABOVE: float = 20.0


def stable_exp(x: Tensor, threshold: float = LOG_RATE_LINEARIZE_ABOVE) -> Tensor:
    """``exp(x)`` below ``threshold``; its tangent line at ``threshold`` above it.

    ``f(x) = exp(C) * (1 + (x - C))`` for ``x > C`` is the first-order Taylor expansion of ``exp``
    at ``C``, so ``f`` and ``f'`` both agree with ``exp`` at the join and the result is C1
    continuous. Above the threshold the value grows linearly instead of exponentially (finite for
    any finite input) and the derivative is the finite positive constant ``exp(C)``.

    **Not ``torch.clamp``.** Clamping the exponent gives a derivative of exactly zero above the
    bound, so the ``- target * x`` term of the Poisson NLL is all that survives and the total
    gradient is ``-target``: negative, so a descent step drives an already-escaped log-rate further
    up. ``tests/test_loss_stability.py`` asserts that wrong sign explicitly, because the difference
    between "no signal" and "a signal pointing the wrong way" is the reason this function exists.

    The exponent fed to ``torch.exp`` is itself replaced by ``threshold`` on the linearized branch,
    so ``exp`` never evaluates an overflowing argument even on the discarded side of the
    ``torch.where``; otherwise the ``0 * inf`` in its backward pass would reintroduce the ``nan``
    this function exists to remove.

    Args:
        x: input tensor (predicted log-rates).
        threshold: the value ``C`` above which ``exp`` is replaced by its tangent line.

    Returns:
        A tensor of the same shape, finite for every finite input.
    """
    over = x > threshold
    safe = torch.where(over, torch.full_like(x, threshold), x)
    exponential = torch.exp(safe)
    linear = math.exp(threshold) * (1.0 + (x - threshold))
    return torch.where(over, linear, exponential)


def masked_poisson_nll(
    rates: Tensor,
    targets: Tensor,
    mask: Tensor,
    log_input: bool,
    eps: float = 1e-8,
) -> Tensor:
    """Poisson NLL averaged over masked positions only.

    Args:
        rates: predicted rates (``log_input=False``) or log-rates (``log_input=True``).
        targets: observed spike counts (same shape as ``rates``).
        mask: boolean tensor; ``True`` marks positions the loss is computed on.
        log_input: passed to ``nn.PoissonNLLLoss``. If ``True`` the loss is
            ``exp(rates) - targets*rates``; if ``False`` it is
            ``rates - targets*log(rates + eps)``.
        eps: numerical-stability epsilon used when ``log_input=False``.

    Returns:
        Scalar mean loss over masked positions; ``0.0`` when the mask is empty.
    """
    criterion = nn.PoissonNLLLoss(reduction="none", log_input=log_input, eps=eps)
    per_element = criterion(rates, targets)
    mask_f = mask.to(per_element.dtype)
    total = (per_element * mask_f).sum()
    count = mask_f.sum().clamp(min=1.0)
    return total / count


def hide_scored_positions(targets: Tensor, mask: Tensor) -> Tensor:
    """Zero the ENCODER INPUT wherever the loss will score it; ``targets`` itself is untouched.

    This is the corruption half of masked modeling, and its absence was the Plan 09-06 defect: the
    mask selected which positions the Poisson NLL summed over, but the encoder still received the
    true count at every one of them, so the objective measured self-reconstruction plus context
    rather than context alone.

    **The masking choice, and why (Plan 09-06b).** Masked positions are set to zero rather than
    replaced by a learned mask embedding:

    * ``NDT1ANE.forward(x) -> Tensor`` stays a single tensor in, single tensor out. A learned
      embedding needs either a 97th input channel or a new ``nn.Parameter``; the first changes the
      ``read_in`` 1x1 Conv2d and the Core ML input signature the Phase-5 conversion path depends
      on, and both move the parameter count away from the 1,292,544 that ``test_param_count.py``
      guards. Zeroing keeps the correction inside the objective, where the defect was.
    * It is what NDT does with the bulk of its masked bins (Ye and Pandarinath 2021,
      snel-repo/neural-data-transformers).

    **The cost, stated rather than hidden.** Zero is a legitimate spike count, and most bins in
    this corpus are zero, so a masked position is indistinguishable from a genuinely silent one.
    The model cannot condition on "this bin is hidden"; it predicts under the possibility that the
    bin really was empty, which biases predictions at scored positions downward. The resulting
    co-bps is therefore a LOWER bound on what a mask-token model of the same size would reach.
    That is the safe direction for a number this repository publishes: the ambiguity can only
    understate the result, never inflate it.

    **Every scored position is corrupted, not 80% of them.** NDT and BERT keep a fraction of masked
    positions unchanged to reduce train/serve skew. That fraction is exactly the leak this function
    exists to remove, so it is not reproduced here; the train/serve mismatch it would have bought
    back is accepted and recorded in ``09-training-evidence.md``.

    Args:
        targets: observed spike counts, any shape.
        mask: boolean tensor broadcastable to ``targets``; ``True`` marks the scored positions.

    Returns:
        A new tensor equal to ``targets`` off the mask and ``0`` on it. ``targets`` is not mutated,
        so the caller still holds the true counts the loss needs.
    """
    keep = (~mask.to(torch.bool)).to(targets.dtype)
    return targets * keep


def random_mask(
    shape: tuple[int, ...],
    mask_ratio: float = 0.25,  # BERT-style default; == DEFAULT_MASK_RATIO
    generator: torch.Generator | None = None,
) -> Tensor:
    """Produce a BERT-style boolean mask where each position is ``True`` with prob ``mask_ratio``.

    Args:
        shape: shape of the mask to produce.
        mask_ratio: probability a given position is masked (default 0.25).
        generator: optional RNG for deterministic masks.

    Returns:
        A boolean tensor of the requested shape (``True`` ≈ ``mask_ratio`` of the time).
    """
    probs = torch.rand(shape, generator=generator)
    return probs < mask_ratio
