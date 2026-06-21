"""SC3a — BC1S forward-hook activation test + (B,S,C) negative control (Plan 04-03 Task 3).

Per 04-RESEARCH.md DEC-04: register a forward hook on EVERY module of NDT1ANE, run a dummy
``(1, 96, 1, S)`` input, and assert every captured activation is rank-4 with ``shape[2] == 1``
(BC1S — the singleton height axis). This fails if any activation reverts to a vanilla
rank-3 ``(B, S, C)`` tensor, which would be silently evicted off the ANE in Phase 5.

The negative control PROVES the trap bites (Phase 1/2 "trap must bite" precedent): a vanilla
``(B, S, C)`` block run through the SAME BC1S assertion MUST raise ``AssertionError``. If the
negative control did not raise, the assertion would be vacuous.
"""
from __future__ import annotations

import pytest
import torch
from torch import Tensor, nn

from ndt1.model_ane import NDT1ANE


def _assert_bc1s(tensor: Tensor) -> None:
    """The BC1S invariant: rank-4 with a singleton height axis (shape[2] == 1)."""
    assert tensor.dim() == 4, f"activation must be rank-4 BC1S, got rank {tensor.dim()}"
    assert tensor.shape[2] == 1, f"BC1S height axis must be 1, got {tensor.shape[2]}"


def _capture_and_check(model: nn.Module, x: Tensor) -> int:
    """Hook every module, run ``x``, assert every tensor activation is BC1S. Returns count."""
    captured: list[Tensor] = []

    def capture(_mod: nn.Module, _inp: object, out: object) -> None:
        # isinstance guard (NOT a blind except): only tensor outputs are checked; modules
        # that return tuples/None are skipped explicitly.
        if isinstance(out, Tensor):
            captured.append(out)

    handles = [m.register_forward_hook(capture) for m in model.modules()]
    try:
        model(x)
    finally:
        for h in handles:
            h.remove()

    assert captured, "no activations were captured — hooks did not fire"
    for activation in captured:
        _assert_bc1s(activation)
    return len(captured)


def test_all_activations_are_bc1s(dummy_bc1s_input: Tensor) -> None:
    """Every NDT1ANE activation on a (1, 96, 1, S) pass is rank-4 with shape[2] == 1."""
    model = NDT1ANE()
    model.eval()
    n_checked = _capture_and_check(model, dummy_bc1s_input)
    assert n_checked > 0


class VanillaBSCBlock(nn.Module):
    """NEGATIVE CONTROL: a vanilla (B, S, C) block using a DENSE nn.Linear (rank-3 output).

    This is exactly the non-ANE layout the BC1S invariant must reject. Running it through
    the same ``_assert_bc1s`` check must raise — proving the trap bites and the SC3a
    assertion is not vacuous.
    """

    def __init__(self, channels: int = 96) -> None:
        super().__init__()
        self.linear = nn.Linear(channels, channels)

    def forward(self, x: Tensor) -> Tensor:
        # x: (B, S, C) rank-3 — deliberately NOT BC1S.
        return self.linear(x)


def test_negative_control_bsc_layout_trips_the_invariant() -> None:
    """A (B, S, C) rank-3 vanilla block MUST fail the BC1S assertion (trap bites)."""
    block = VanillaBSCBlock(channels=96)
    block.eval()
    bsc_input = torch.rand(1, 32, 96)  # (B, S, C) — rank-3, the layout BC1S forbids
    with pytest.raises(AssertionError):
        _capture_and_check(block, bsc_input)
