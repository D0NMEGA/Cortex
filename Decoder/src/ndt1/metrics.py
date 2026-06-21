"""co-bps (bits-per-spike) convergence metric for NDT1 (Plan 04-04, DEC-02 / SC2).

The Neural Latents Benchmark '21 standard (Pei et al. 2021, "Neural Latents Benchmark '21",
arXiv 2109.04463 — which packaged this exact O'Doherty dataset as the ``mc_rtt`` task). co-bps
measures how much better the model reconstructs the held-out (masked) spike counts than a
trivial **mean-firing-rate null model**, in bits per spike:

    bits/spike = ( NLL_null(masked) - NLL_model(masked) ) / ( masked_spike_count * ln 2 )

Both NLLs are Poisson negative log-likelihoods SUMMED over the masked positions (in nats); the
``/ ln 2`` converts nats → bits and the ``/ masked_spike_count`` makes it per-spike. ``NLL_null``
uses the per-channel MEAN firing rate (computed on the TRAIN split) broadcast as a constant
prediction. "Non-trivial" reconstruction (SC2) means co_bps meaningfully > 0 — i.e. the trained
model beats the mean-rate null.

The masked-position summed Poisson NLL is computed here with ``nn.PoissonNLLLoss(reduction='none')``
exactly as ``ndt1.loss.masked_poisson_nll`` does (same parameterization, ``log_input`` and ``eps``),
so the model term in co-bps is consistent with the training objective. No bare/blind ``except``.
"""
from __future__ import annotations

import math

import torch
from torch import Tensor, nn

_LN2: float = math.log(2.0)  # nats -> bits conversion (0.6931...)


def mean_firing_rate(train_counts: Tensor) -> Tensor:
    """Per-channel mean firing rate — the constant prediction of the mean-rate null model.

    The channel axis is dim 1 of a BC1S ``(B, C, 1, S)`` tensor (or any tensor whose channel
    axis is dim 1). The mean is taken over every OTHER axis, leaving one scalar per channel.

    Args:
        train_counts: spike counts whose channel axis is dim 1, e.g. ``(B, C, 1, S)``.

    Returns:
        A ``(1, C, 1, ..., 1)`` tensor (channel axis kept, all others reduced to size 1) that
        broadcasts onto the input layout — the per-channel mean used as the null prediction.
    """
    if train_counts.ndim < 2:
        raise ValueError(
            f"train_counts must have a channel axis at dim 1 (ndim >= 2), got shape "
            f"{tuple(train_counts.shape)}"
        )
    reduce_dims = tuple(d for d in range(train_counts.ndim) if d != 1)
    return train_counts.to(torch.float32).mean(dim=reduce_dims, keepdim=True)


def _summed_poisson_nll(
    rates: Tensor, targets: Tensor, mask: Tensor, log_input: bool, eps: float
) -> Tensor:
    """Poisson NLL SUMMED over masked positions (nats) — the bits-arithmetic numerator term.

    Mirrors ``ndt1.loss.masked_poisson_nll`` but returns the SUM (not the mean) over the masked
    positions, since co-bps needs the total nats to divide by the total spike count.
    """
    criterion = nn.PoissonNLLLoss(reduction="none", log_input=log_input, eps=eps)
    per_element = criterion(rates, targets)
    mask_f = mask.to(per_element.dtype)
    return (per_element * mask_f).sum()


def co_bps(
    model_rates: Tensor,
    targets: Tensor,
    mask: Tensor,
    mean_rate: Tensor,
    log_input: bool,
    eps: float = 1e-8,
) -> float:
    """Bits-per-spike improvement of the model over the mean-firing-rate null on masked positions.

    Args:
        model_rates: model output — log-rates if ``log_input=True``, else rates. Same shape as
            ``targets`` (BC1S ``(B, C, 1, S)``).
        targets: observed spike counts (same shape as ``model_rates``).
        mask: boolean tensor; ``True`` marks the held-out positions co-bps is scored on.
        mean_rate: per-channel mean firing rate from the TRAIN split (from ``mean_firing_rate``),
            broadcastable to ``targets`` — the null model's constant prediction (a rate, not a
            log-rate; it is log-transformed here when ``log_input=True``).
        log_input: matches the model's parameterization and ``nn.PoissonNLLLoss``. ``True`` →
            inputs are log-rates (``exp(input) - target*input``); ``False`` → inputs are rates.
        eps: numerical-stability epsilon (matches ``ndt1.loss``).

    Returns:
        bits/spike = ``(NLL_null - NLL_model) / (masked_spike_count * ln 2)`` as a float; ``0.0``
        when no spikes fall on masked positions (guarded against divide-by-zero — always finite).
    """
    mask_b = mask.to(torch.bool)
    # The null predicts the per-channel mean rate at EVERY position. PoissonNLLLoss wants the
    # same parameterization as the model: log(mean_rate) when log_input=True, else the rate.
    null_rate = mean_rate.to(model_rates.dtype).expand_as(targets)
    null_input = torch.log(null_rate + eps) if log_input else null_rate

    nll_model = _summed_poisson_nll(model_rates, targets, mask_b, log_input, eps)
    nll_null = _summed_poisson_nll(null_input, targets, mask_b, log_input, eps)

    # co-bps is PER SPIKE: divide by the total observed spike count on masked positions (NLB'21),
    # not by the number of masked bins. Guard the spikeless-mask case.
    masked_spike_count = float((targets * mask_b.to(targets.dtype)).sum().item())
    if masked_spike_count <= 0.0:
        return 0.0
    return float((nll_null - nll_model).item() / (masked_spike_count * _LN2))
