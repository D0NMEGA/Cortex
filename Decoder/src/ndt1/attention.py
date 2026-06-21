"""ANE-conducive attention primitives for NDT1 (Plan 04-03, DEC-04).

Ports the ``apple/ml-ane-transformers`` reference principles
(https://machinelearning.apple.com/research/neural-engine-transformers) onto the
BC1S ``(B, C, 1, S)`` layout the Apple Neural Engine pins:

* **Conv2d, not dense layers** — every projection is a 1x1 ``nn.Conv2d`` over the
  ``(B, C, 1, S)`` tensor (Apple principle #1). There are ZERO dense (fully-connected)
  layers here; the SC3 tests in Plan 04-03 statically assert that absence.
* **Single-head chunks** — Q/K/V are split into ``num_heads`` single-head chunks of
  width ``d_model // num_heads`` (principle #2: smaller chunks → L2 residency).
* **Minimal copies** — the KEY is transposed (channel axis last) immediately before the
  Q·K product, and scaled-dot-product uses the ``bchq,bkhc->bkhq`` einsum (principle #3),
  whose layout maps directly to hardware with no intermediate reshape.

The sequence axis ``S`` is the LAST axis throughout (the last ANE buffer axis must be
contiguous + 64-byte aligned). ``LayerNormANE`` normalizes over the CHANNEL axis
(``dim=1``) rather than the last axis, matching the channels-first layout.
"""
from __future__ import annotations

import torch
import torch.nn.functional as F
from torch import Tensor, nn

# The exact ANE scaled-dot-product einsum (Apple principle #3). Kept as a module-level
# constant so the SC3b "inference path uses the ANE einsum" test can introspect it and
# the string is defined in exactly one place.
ANE_ATTENTION_EINSUM = "bchq,bkhc->bkhq"


class LayerNormANE(nn.Module):
    """Layer normalization over the CHANNEL axis (dim=1) of a ``(B, C, 1, S)`` tensor.

    Vanilla ``nn.LayerNorm`` normalizes the last axis; in the BC1S layout the feature
    (channel) axis is ``dim=1``, so we normalize there and keep learnable affine
    parameters shaped ``(1, num_channels, 1, 1)`` to broadcast over batch/height/sequence.
    """

    def __init__(self, num_channels: int, eps: float = 1e-5) -> None:
        super().__init__()
        self.num_channels = num_channels
        self.eps = eps
        self.weight = nn.Parameter(torch.ones(1, num_channels, 1, 1))
        self.bias = nn.Parameter(torch.zeros(1, num_channels, 1, 1))

    def forward(self, x: Tensor) -> Tensor:
        mean = x.mean(dim=1, keepdim=True)
        var = x.var(dim=1, keepdim=True, unbiased=False)
        normed = (x - mean) / torch.sqrt(var + self.eps)
        return normed * self.weight + self.bias


class ANEAttention(nn.Module):
    """Single-head-chunked scaled-dot-product attention on a ``(B, d_model, 1, S)`` tensor.

    Q/K/V/out projections are 1x1 ``nn.Conv2d`` (no dense fully-connected layers). The
    input is split into ``num_heads`` single-head chunks; each head computes attention via the
    ``bchq,bkhc->bkhq`` einsum (Apple principle #3) with softmax over the key axis. Output
    is rank-4 BC1S (``shape[2] == 1`` preserved). ``num_heads`` is exposed as an attribute
    so the SC1a structural test can assert it directly (param count is invariant to heads).
    """

    def __init__(self, d_model: int = 128, num_heads: int = 2, dropout: float = 0.1) -> None:
        super().__init__()
        if d_model % num_heads != 0:
            raise ValueError(f"d_model ({d_model}) must be divisible by num_heads ({num_heads})")
        self.d_model = d_model
        self.num_heads = num_heads
        self.head_dim = d_model // num_heads
        self.scale = self.head_dim**-0.5

        self.q_proj = nn.Conv2d(d_model, d_model, kernel_size=1)
        self.k_proj = nn.Conv2d(d_model, d_model, kernel_size=1)
        self.v_proj = nn.Conv2d(d_model, d_model, kernel_size=1)
        self.out_proj = nn.Conv2d(d_model, d_model, kernel_size=1)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x: Tensor) -> Tensor:
        # x: (B, d_model, 1, S) — project then split into single-head chunks along channels.
        q = torch.split(self.q_proj(x), self.head_dim, dim=1)
        k = torch.split(self.k_proj(x), self.head_dim, dim=1)
        v = torch.split(self.v_proj(x), self.head_dim, dim=1)

        head_outputs: list[Tensor] = []
        for q_head, k_head, v_head in zip(q, k, v, strict=True):
            # q_head/k_head/v_head: (B, head_dim, 1, S) == (b, c, h, q).
            # Transpose the KEY so its channel axis is LAST, right before Q·K (principle #3):
            #   k_t: (b, k=S, h=1, c=head_dim)
            k_t = k_head.permute(0, 3, 2, 1)
            # Scaled dot-product via the ANE einsum -> attention weights (b, k=S, h=1, q=S).
            attn = torch.einsum(ANE_ATTENTION_EINSUM, q_head, k_t) * self.scale
            attn = F.softmax(attn, dim=1)  # softmax over the KEY axis (dim=1)
            attn = self.dropout(attn)
            # Combine with value: weights (b, k, h, q) · v (b, c, h, k) -> (b, c, h, q).
            head_out = torch.einsum("bkhq,bchk->bchq", attn, v_head)
            head_outputs.append(head_out)

        concatenated = torch.cat(head_outputs, dim=1)  # (B, d_model, 1, S)
        return self.out_proj(concatenated)
