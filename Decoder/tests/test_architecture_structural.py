"""SC1a — NDT1ANE structural assertions (Plan 04-03 Task 2, DEC-01).

This is the load-bearing head-count guard. Per 04-RESEARCH.md §0.1, a parameter-count
assertion CANNOT catch the documented h=4 miscitation: ``nn.MultiheadAttention`` projection
weights are ``3·d_model² + d_model²`` REGARDLESS of ``num_heads`` (heads only reshape
``d_model``, they add zero parameters). The same is true of this Conv2d formulation — the
q/k/v/out 1x1 convs are sized by ``d_model``, not ``num_heads``. So the ONLY assertion that
catches a drift to h=4 is asserting ``num_heads ∈ {1, 2}`` DIRECTLY on every attention
module. SC1b (test_param_count.py) catches layer/dim/FFN drift; this test catches head drift.
"""
from __future__ import annotations

from ndt1.attention import ANEAttention
from ndt1.model_ane import NDT1ANE


def test_structural_knobs_exact() -> None:
    """num_layers==6, d_model==128, bin_ms==20.0 exactly (the NDT1 spec knobs)."""
    model = NDT1ANE()
    assert model.num_layers == 6
    assert model.d_model == 128
    assert model.bin_ms == 20.0


def test_six_encoder_layers_present() -> None:
    """Iterating the module tree finds exactly 6 encoder layers' worth of attention."""
    model = NDT1ANE()
    attentions = [m for m in model.modules() if isinstance(m, ANEAttention)]
    assert len(attentions) == 6, f"expected 6 attention modules, got {len(attentions)}"


def test_every_attention_head_count_in_one_or_two() -> None:
    """EVERY attention module reports num_heads ∈ {1, 2}.

    THE load-bearing guard (04-RESEARCH.md §0.1): the only assertion that catches the h=4
    miscitation, since param count is invariant to head count. Introspect ALL attention
    modules via model.modules(), not just one.
    """
    model = NDT1ANE()
    attentions = [m for m in model.modules() if isinstance(m, ANEAttention)]
    assert len(attentions) > 0, "no attention modules found to assert head count on"
    for attn in attentions:
        assert attn.num_heads in {1, 2}, (
            f"num_heads must be in {{1, 2}} (NDT1 spec — NOT the h=4 miscitation), "
            f"got {attn.num_heads}"
        )


def test_default_num_heads_is_two() -> None:
    """The default constructor uses h=2 (within the {1,2} spec band)."""
    model = NDT1ANE()
    attentions = [m for m in model.modules() if isinstance(m, ANEAttention)]
    assert all(a.num_heads == 2 for a in attentions)
