"""Masked Poisson NLL reconstruction loss for NDT1 (Plan 04-03, DEC-01).

NDT is a BERT-style masked-modeling autoencoder over binned spike counts
(snel-repo/neural-data-transformers ``src/model.py``): a fraction ``mask_ratio`` (0.25) of
bins is masked, and the loss is the Poisson negative log-likelihood computed **only on the
masked positions**. ``nn.PoissonNLLLoss(reduction='none')`` gives the per-element loss; we
sum it over the mask and divide by the number of masked positions (guarded against an
empty mask so the loss is always finite).
"""
from __future__ import annotations

import torch
from torch import Tensor, nn

DEFAULT_MASK_RATIO: float = 0.25


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
