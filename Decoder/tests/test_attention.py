"""Unit tests for the ANE attention primitives + masked-Poisson loss (Plan 04-03 Task 1).

Covers the load-bearing DEC-04 ANE conventions in isolation, before the full NDT1ANE
model composes them (Task 2): the ``bchq,bkhc->bkhq`` single-head-chunked attention,
``LayerNormANE`` channel-axis normalization, and the masked Poisson NLL reconstruction
head (masked positions only). All BC1S ``(B, C, 1, S)`` — rank-4, ``shape[2] == 1``.
"""
from __future__ import annotations

import math

import torch
import torch.nn.functional as F
from ndt1.attention import ANEAttention, LayerNormANE
from ndt1.loss import masked_poisson_nll, random_mask


def test_ane_attention_preserves_bc1s_shape(dummy_bc1s_input: torch.Tensor) -> None:
    """ANEAttention on a (B, d_model, 1, S) input returns (B, d_model, 1, S) — rank-4, h==1."""
    d_model = 128
    # The conftest dummy is (1, 96, 1, S); attention runs at d_model width, so build a
    # matching d_model-wide BC1S input from its sequence length.
    seq_len = dummy_bc1s_input.shape[-1]
    x = torch.rand(2, d_model, 1, seq_len)
    attn = ANEAttention(d_model=d_model, num_heads=2)
    out = attn(x)
    assert out.dim() == 4, "attention output must stay rank-4 BC1S"
    assert out.shape[2] == 1, "the singleton height axis (BC1S) must be preserved"
    assert out.shape == x.shape


def test_ane_attention_exposes_num_heads() -> None:
    """num_heads is an introspectable attribute (the SC1a head-count guard depends on it)."""
    attn = ANEAttention(d_model=128, num_heads=2)
    assert attn.num_heads == 2
    attn1 = ANEAttention(d_model=128, num_heads=1)
    assert attn1.num_heads == 1


def test_ane_attention_matches_reference_sdpa() -> None:
    """The bchq,bkhc->bkhq einsum is numerically equivalent to vanilla (B,S,C) multi-head SDPA.

    Zero out the projection convs to identity so the attention math itself is compared
    (verifies the einsum convention + softmax-over-key axis, not the learned projections).
    """
    d_model, num_heads, seq_len, batch = 8, 2, 5, 2
    head_dim = d_model // num_heads
    attn = ANEAttention(d_model=d_model, num_heads=num_heads, dropout=0.0)
    attn.eval()
    # Force q/k/v/out projections to identity (weight = identity 1x1 conv, bias 0).
    eye = torch.eye(d_model).view(d_model, d_model, 1, 1)
    for proj in (attn.q_proj, attn.k_proj, attn.v_proj, attn.out_proj):
        with torch.no_grad():
            proj.weight.copy_(eye)
            proj.bias.zero_()

    x = torch.rand(batch, d_model, 1, seq_len)
    got = attn(x)

    # Reference: vanilla (B, S, C) multi-head scaled-dot-product attention on the same input.
    xt = x.squeeze(2).transpose(1, 2)  # (B, S, d_model)
    qh = xt.view(batch, seq_len, num_heads, head_dim).transpose(1, 2)  # (B, nh, S, hd)
    ref = F.scaled_dot_product_attention(qh, qh, qh)  # (B, nh, S, hd)
    ref = ref.transpose(1, 2).reshape(batch, seq_len, d_model).transpose(1, 2).unsqueeze(2)

    assert torch.allclose(got, ref, atol=1e-5), "ANE einsum attention must equal reference SDPA"


def test_layernorm_ane_preserves_bc1s_and_normalizes_channels() -> None:
    """LayerNormANE normalizes over the CHANNEL axis (dim=1) of (B, C, 1, S), shape preserved."""
    d_model, seq_len, batch = 128, 7, 3
    ln = LayerNormANE(d_model)
    x = torch.randn(batch, d_model, 1, seq_len) * 5.0 + 2.0
    out = ln(x)
    assert out.shape == x.shape
    assert out.dim() == 4 and out.shape[2] == 1
    # With default affine (weight=1, bias=0) the per-(b,s) channel slice is ~zero-mean/unit-var.
    mean = out.mean(dim=1)
    var = out.var(dim=1, unbiased=False)
    assert torch.allclose(mean, torch.zeros_like(mean), atol=1e-5)
    assert torch.allclose(var, torch.ones_like(var), atol=1e-3)


def test_masked_poisson_nll_toy_value() -> None:
    """A hand-computed masked Poisson NLL (log_input=False) matches the implementation.

    PoissonNLLLoss(log_input=False) per element = rate - target*log(rate + eps).
    Averaged over MASKED positions only.
    """
    rates = torch.tensor([[1.0, 2.0, 3.0, 4.0]])
    targets = torch.tensor([[1.0, 0.0, 2.0, 1.0]])
    mask = torch.tensor([[True, False, True, False]])  # positions 0 and 2 only
    eps = 1e-8
    # element 0: 1 - 1*log(1+eps) = 1.0 ; element 2: 3 - 2*log(3+eps)
    expected = (1.0 - 1.0 * math.log(1.0 + eps) + 3.0 - 2.0 * math.log(3.0 + eps)) / 2.0
    got = masked_poisson_nll(rates, targets, mask, log_input=False)
    assert math.isclose(got.item(), expected, rel_tol=1e-5)


def test_masked_poisson_nll_empty_mask_returns_zero() -> None:
    """An all-False mask returns 0 (guarded division), never NaN/inf."""
    rates = torch.rand(2, 4)
    targets = torch.rand(2, 4)
    mask = torch.zeros(2, 4, dtype=torch.bool)
    got = masked_poisson_nll(rates, targets, mask, log_input=False)
    assert torch.isfinite(got)
    assert got.item() == 0.0


def test_masked_poisson_nll_log_input_branch() -> None:
    """log_input=True uses exp(rate) - target*rate (the log-rate parameterization)."""
    rates = torch.tensor([[0.0, 0.5]])  # interpreted as log-rates
    targets = torch.tensor([[2.0, 1.0]])
    mask = torch.tensor([[True, True]])
    expected = ((math.exp(0.0) - 2.0 * 0.0) + (math.exp(0.5) - 1.0 * 0.5)) / 2.0
    got = masked_poisson_nll(rates, targets, mask, log_input=True)
    assert math.isclose(got.item(), expected, rel_tol=1e-5)


def test_random_mask_ratio_is_approximately_quarter() -> None:
    """random_mask produces a boolean mask with mean ≈ 0.25 (BERT-style mask_ratio default)."""
    gen = torch.Generator().manual_seed(0)
    mask = random_mask((64, 96), mask_ratio=0.25, generator=gen)
    assert mask.dtype == torch.bool
    assert abs(mask.float().mean().item() - 0.25) < 0.03
