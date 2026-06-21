"""SC3b — zero dense nn.Linear on the inference path + ANE einsum present (Plan 04-03 Task 3).

Per 04-RESEARCH.md DEC-04: the BC1S inference module tree must contain ZERO ``nn.Linear``
(every projection is a 1x1 ``nn.Conv2d``), and attention must use the ``bchq,bkhc->bkhq``
einsum. A stray ``nn.Linear`` would emit a rank-3 ``(B, S, C)`` tensor that gets evicted off
the ANE in Phase 5; statically asserting its absence closes that boundary.
"""
from __future__ import annotations

import inspect

from torch import nn

import ndt1.attention
from ndt1.attention import ANEAttention
from ndt1.model_ane import NDT1ANE


def test_no_nn_linear_on_inference_path() -> None:
    """The NDT1ANE module tree contains zero dense nn.Linear modules."""
    model = NDT1ANE()
    linear_count = sum(isinstance(m, nn.Linear) for m in model.modules())
    assert linear_count == 0, f"inference path must have zero nn.Linear, found {linear_count}"


def test_attention_uses_ane_einsum() -> None:
    """The attention source uses the bchq,bkhc->bkhq einsum (the ANE scaled-dot-product)."""
    source = inspect.getsource(ndt1.attention)
    assert "bchq,bkhc->bkhq" in source, "attention must use the ANE einsum on the inference path"


def test_attention_module_present_in_tree() -> None:
    """At least one ANEAttention is present in the NDT1ANE module tree."""
    model = NDT1ANE()
    assert any(isinstance(m, ANEAttention) for m in model.modules())
