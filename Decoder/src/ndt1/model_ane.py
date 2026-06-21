"""NDT1 encoder in the ANE-conducive BC1S form (Plan 04-03, DEC-01 + DEC-04).

A non-recurrent Transformer encoder over 20 ms-binned 96-channel spike counts
(Ye & Pandarinath 2021, "Neural Data Transformers", arXiv 2108.01210), laid out for the
Apple Neural Engine per ``apple/ml-ane-transformers`` (DEC-04):

* read-in / readout are 1x1 ``nn.Conv2d`` (NOT dense fully-connected layers); the whole
  inference path carries ``(B, C, 1, S)`` tensors with the sequence axis ``S`` LAST.
* 6 PRE_NORM encoder layers, each ``LayerNormANE → ANEAttention → residual →
  LayerNormANE → Conv2d-FFN (GELU) → residual``; attention uses the
  ``bchq,bkhc->bkhq`` einsum (see ``ndt1.attention``).
* learnable positional encoding broadcast over ``(B, d_model, 1, S)``.

Phase boundary (Plan 04-03): this is the encoder → predicted-rates forward graph ONLY.
There is NO velocity / ``(vx, vy)`` readout (DEC-10 / Phase 5) and NO Core ML conversion /
ANE targeting / ``computeUnits`` (Plans 04-05 / Phase 5).

A ``load_state_dict`` pre-hook unsqueezes any dense-layer-shaped weights (``out, in``) to
the 1x1-conv shape (``out, in, 1, 1``) so fp32 reference checkpoints saved with dense
layers can be loaded into this conv model — per the Apple reference. The inference path
itself contains zero dense fully-connected layers (verified by Plan 04-03 SC3b).
"""
from __future__ import annotations

import torch
import torch.nn.functional as F
from torch import Tensor, nn

from ndt1.attention import ANEAttention, LayerNormANE

try:  # Channel-width source-of-truth lives in Plan 04-02's channel_count module.
    from ndt1.channel_count import CORTEX_CHANNEL_COUNT
except ImportError:  # 04-02 lands in a sibling worktree; fall back to the locked value (96).
    # NOT a bare/blind except — a specific ImportError so this module stands alone in an
    # isolated worktree where channel_count.py is not yet merged. The value 96 matches the
    # three repo homes (cortex_shm.h / cortex_ring.h / frame.rs) and conftest CHANNELS.
    CORTEX_CHANNEL_COUNT = 96


class _EncoderLayer(nn.Module):
    """A single PRE_NORM Transformer encoder layer in BC1S form (all 1x1 Conv2d)."""

    def __init__(
        self,
        d_model: int,
        num_heads: int,
        dim_feedforward: int,
        dropout: float,
    ) -> None:
        super().__init__()
        self.norm1 = LayerNormANE(d_model)
        self.attn = ANEAttention(d_model, num_heads, dropout=dropout)
        self.norm2 = LayerNormANE(d_model)
        # FFN as two 1x1 convs (d_model -> dim_feedforward -> d_model) with GELU between.
        self.ff1 = nn.Conv2d(d_model, dim_feedforward, kernel_size=1)
        self.ff2 = nn.Conv2d(dim_feedforward, d_model, kernel_size=1)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x: Tensor) -> Tensor:
        # PRE_NORM residual attention block.
        x = x + self.dropout(self.attn(self.norm1(x)))
        # PRE_NORM residual feed-forward block.
        ff = self.ff2(self.dropout(F.gelu(self.ff1(self.norm2(x)))))
        return x + self.dropout(ff)


class NDT1ANE(nn.Module):
    """NDT1 encoder → predicted Poisson rates, in BC1S ``(B, C, 1, S)`` form.

    Args:
        num_channels: input/output channel width (default ``CORTEX_CHANNEL_COUNT`` == 96).
        d_model: Transformer hidden width (the spec's "128 hidden dim").
        num_layers: number of encoder layers (NDT1 spec: 6).
        num_heads: attention heads per layer (NDT1 spec: ∈ {1, 2}).
        dim_feedforward: FFN width — the knob tuned to ~1.3M params (default 560 → ~1.30M).
        seq_len: sequence length the learnable positional encoding is sized for.
        dropout: dropout probability.
        mask_ratio: BERT-style mask fraction kept on the module for the trainer (Plan 04-04).
        bin_ms: temporal bin width in milliseconds (NDT1 spec: 20 ms).

    forward(x: Tensor[B, C, 1, S]) -> rates: Tensor[B, C, 1, S].
    """

    def __init__(
        self,
        num_channels: int = CORTEX_CHANNEL_COUNT,
        d_model: int = 128,
        num_layers: int = 6,
        num_heads: int = 2,
        dim_feedforward: int = 560,
        seq_len: int = 32,
        dropout: float = 0.1,
        mask_ratio: float = 0.25,
        bin_ms: float = 20.0,
    ) -> None:
        super().__init__()
        self.num_channels = num_channels
        self.d_model = d_model
        self.num_layers = num_layers
        self.num_heads = num_heads
        self.dim_feedforward = dim_feedforward
        self.seq_len = seq_len
        self.mask_ratio = mask_ratio
        self.bin_ms = bin_ms

        # Conv2d read-in / readout (NOT dense layers) — BC1S in, BC1S out.
        self.read_in = nn.Conv2d(num_channels, d_model, kernel_size=1)
        self.readout = nn.Conv2d(d_model, num_channels, kernel_size=1)
        # Learnable positional encoding, broadcast over (B, d_model, 1, S).
        self.pos_encoding = nn.Parameter(torch.zeros(1, d_model, 1, seq_len))
        self.layers = nn.ModuleList(
            _EncoderLayer(d_model, num_heads, dim_feedforward, dropout)
            for _ in range(num_layers)
        )

        # Apple reference: load dense-layer-shaped (out, in) weights into 1x1 convs by
        # unsqueezing twice to (out, in, 1, 1). The inference path stays conv-only.
        self._register_load_state_dict_pre_hook(self._dense_to_conv_pre_hook)

    @staticmethod
    def _dense_to_conv_pre_hook(
        state_dict: dict[str, Tensor],
        prefix: str,
        *args: object,
    ) -> None:
        """Unsqueeze dense-layer-shaped weights (rank-2) to 1x1-conv shape (rank-4).

        Lets an fp32 reference checkpoint saved with dense ``(out, in)`` weight matrices be
        loaded into this conv model (whose weights are ``(out, in, 1, 1)``). Operates only
        on ``*.weight`` entries that are rank-2; conv/bias entries are left untouched.
        """
        for key, value in list(state_dict.items()):
            if key.startswith(prefix) and key.endswith(".weight") and value.dim() == 2:
                state_dict[key] = value.unsqueeze(-1).unsqueeze(-1)

    def forward(self, x: Tensor) -> Tensor:
        # x: (B, num_channels, 1, S) spike counts -> predicted rates (B, num_channels, 1, S).
        h = self.read_in(x) + self.pos_encoding
        for layer in self.layers:
            h = layer(h)
        return self.readout(h)

    def count_parameters(self) -> int:
        """Total number of parameters (the SC1b guardrail introspects this)."""
        return sum(p.numel() for p in self.parameters())
