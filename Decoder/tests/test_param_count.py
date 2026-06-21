"""SC1b — NDT1ANE parameter-count guardrail (Plan 04-03 Task 2, DEC-01).

A generous bound ``1.0e6 ≤ params ≤ 1.6e6`` that catches layer / d_model / dim_feedforward
drift (04-RESEARCH.md §1: ``431,584 + 1,542·F``; default ``dim_feedforward=560`` → ~1.30M).
NOTE: this guardrail is INVARIANT to ``num_heads`` — the h=4 miscitation is caught only by
``test_architecture_structural.py`` (SC1a), not here.
"""
from __future__ import annotations

from ndt1.model_ane import NDT1ANE

PARAM_LOWER_BOUND = 1.0e6
PARAM_UPPER_BOUND = 1.6e6


def test_param_count_within_guardrail() -> None:
    """Total parameter count is in [1.0M, 1.6M] (~1.3M target)."""
    model = NDT1ANE()
    n = model.count_parameters()
    assert PARAM_LOWER_BOUND <= n <= PARAM_UPPER_BOUND, (
        f"param count {n:,} outside guardrail [{PARAM_LOWER_BOUND:,.0f}, "
        f"{PARAM_UPPER_BOUND:,.0f}] — layer/d_model/dim_feedforward drift?"
    )


def test_count_parameters_matches_sum_of_parameters() -> None:
    """count_parameters() equals the literal sum over model.parameters()."""
    model = NDT1ANE()
    assert model.count_parameters() == sum(p.numel() for p in model.parameters())


def test_default_dim_feedforward_lands_near_target() -> None:
    """Default config lands close to the ~1.3M target (within the guardrail, tight band)."""
    model = NDT1ANE()
    n = model.count_parameters()
    # 1.30M ± 0.15M — a tighter sanity band than the guardrail, asserting the default
    # dim_feedforward was actually tuned (not merely inside the wide [1.0M, 1.6M] bound).
    assert 1.15e6 <= n <= 1.45e6, f"default param count {n:,} not near the 1.3M target"
