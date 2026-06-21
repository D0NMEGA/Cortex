"""Tests for the co-bps (bits-per-spike) convergence metric (Plan 04-04 Task 1, SC2).

co-bps is the Neural Latents Benchmark '21 standard (Pei et al. 2021, arXiv 2109.04463):

    bits/spike = ( NLL_null(masked) - NLL_model(masked) ) / ( masked_spike_count * ln 2 )

where ``NLL_null`` uses the per-channel MEAN firing rate (from the train split) broadcast as
the prediction. "Non-trivial" reconstruction (SC2) = co_bps meaningfully > 0 (the model beats
the mean-rate null). These tests pin the two anchor points that make the metric meaningful:

  * a model that predicts the targets EXACTLY scores co_bps >> 0, and
  * a model that predicts the mean rate (i.e. == the null) scores co_bps ~= 0.
"""
from __future__ import annotations

import math

import torch

from ndt1.metrics import co_bps, mean_firing_rate


def _toy_targets() -> torch.Tensor:
    """A tiny (B=2, C=3, 1, S=4) integer spike-count tensor with per-channel structure."""
    counts = torch.tensor(
        [
            [[[0.0, 1.0, 2.0, 3.0]], [[4.0, 3.0, 2.0, 1.0]], [[1.0, 1.0, 1.0, 1.0]]],
            [[[3.0, 2.0, 1.0, 0.0]], [[1.0, 2.0, 3.0, 4.0]], [[2.0, 0.0, 2.0, 0.0]]],
        ]
    )
    assert counts.shape == (2, 3, 1, 4)
    return counts


def test_mean_firing_rate_shape_and_value() -> None:
    """mean_firing_rate returns the per-channel mean, broadcastable to (B,C,1,S)."""
    targets = _toy_targets()  # (2, 3, 1, 4)
    rate = mean_firing_rate(targets)
    # One scalar per channel (C == 3), broadcastable over (B, C, 1, S).
    assert rate.shape[1] == 3
    assert rate.numel() == 3
    # Channel 2 is all-ones in both batches -> mean exactly 1.0.
    flat = rate.reshape(-1)
    assert math.isclose(float(flat[2]), 1.0, abs_tol=1e-6)
    # Channel 0 mean over the 8 values {0,1,2,3,3,2,1,0} = 1.5.
    assert math.isclose(float(flat[0]), 1.5, abs_tol=1e-6)


def test_co_bps_perfect_prediction_strongly_positive() -> None:
    """When the model predicts the targets exactly, co_bps is strongly positive (>> 0)."""
    targets = _toy_targets()
    mask = torch.ones_like(targets, dtype=torch.bool)
    mean_rate = mean_firing_rate(targets)
    # log_input=True parameterization (matches the linear readout): log-rate == log(target).
    # A near-perfect model predicts log(target + tiny) so exp(log_rate) ~= target.
    log_rates = torch.log(targets + 1e-6)
    bits = co_bps(log_rates, targets, mask, mean_rate, log_input=True)
    # A perfect predictor scores ~0.34 bits/spike here (not unbounded): PoissonNLLLoss's internal
    # eps floors exp(log_rate) so the masked NLL never reaches exactly 0. 0.34 >> the 0.0 null, so
    # we assert a margin (> 0.25) above the null but below that eps-imposed ceiling.
    assert bits > 0.25, f"perfect-prediction co_bps should be >> 0 (null), got {bits}"


def test_co_bps_mean_rate_prediction_near_zero() -> None:
    """When the model predicts the mean rate (== the null), co_bps is ~= 0."""
    targets = _toy_targets()
    mask = torch.ones_like(targets, dtype=torch.bool)
    mean_rate = mean_firing_rate(targets)  # (1, C, 1, 1)
    # Model "prediction" == the null prediction: broadcast the per-channel mean rate.
    null_log_rates = torch.log(mean_rate + 1e-12).expand_as(targets).contiguous()
    bits = co_bps(null_log_rates, targets, mask, mean_rate, log_input=True)
    assert abs(bits) < 1e-4, f"mean-rate co_bps should be ~= 0, got {bits}"


def test_co_bps_partial_mask_only_scores_masked_positions() -> None:
    """co_bps over a partial mask uses only the masked entries (and stays finite)."""
    targets = _toy_targets()
    mask = torch.zeros_like(targets, dtype=torch.bool)
    mask[:, :, :, :2] = True  # only the first two timesteps are scored
    mean_rate = mean_firing_rate(targets)
    log_rates = torch.log(targets + 1e-6)
    bits = co_bps(log_rates, targets, mask, mean_rate, log_input=True)
    assert math.isfinite(bits)
    assert bits > 0.0  # the (near-)perfect model still beats the null on the masked subset


def test_co_bps_empty_mask_is_zero() -> None:
    """An empty mask (zero masked spikes) returns 0.0, never a divide-by-zero NaN/inf."""
    targets = _toy_targets()
    mask = torch.zeros_like(targets, dtype=torch.bool)
    mean_rate = mean_firing_rate(targets)
    log_rates = torch.log(targets + 1e-6)
    bits = co_bps(log_rates, targets, mask, mean_rate, log_input=True)
    assert bits == 0.0
