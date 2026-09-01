"""The pre-registered convergence rule, as a pure function (Plan 09-06c).

Plan 09-06b published a co-bps measured at a fixed 12-epoch budget on a loss curve that was still
descending monotonically when the budget ran out, so the number was a floor rather than an
asymptote. The 12 came from Phase 4, where it was calibrated against an objective that let the
model copy its input and reached a 43% loss reduction; under the corrected objective the same
budget yields 6%.

Replacing it needs a stopping rule, and the rule has to be defined on the TRAINING LOSS. Stopping
when the headline metric looks good is the exact tuning this whole correction exists to avoid, so
:func:`ndt1.train.loss_plateaued` cannot see a co-bps: its only input is the loss curve. The
parameters the evidence run uses are pre-registered in ``train_real.py`` and were committed before
the run, not chosen from its output.

These tests fix the rule's behaviour on the edges that matter for an honest report:

  * it cannot fire before the epoch floor, so the converged run is never shorter than the truncated
    one it replaces,
  * a diverged run never counts as converged, and
  * the arithmetic is relative, not absolute, so the rule does not silently mean something
    different at a different loss scale.
"""
from __future__ import annotations

import math

import pytest

from ndt1.train import loss_plateaued

_REL_TOL: float = 1e-3
_PATIENCE: int = 3
_MIN_EPOCHS: int = 12
_RULE: dict[str, float] = {"rel_tol": _REL_TOL, "patience": _PATIENCE, "min_epochs": _MIN_EPOCHS}


def _flat(n: int, value: float = 0.5) -> list[float]:
    """A perfectly flat curve: zero relative improvement everywhere."""
    return [value] * n


def test_a_flat_curve_below_the_epoch_floor_does_not_stop() -> None:
    """The floor is load-bearing: it keeps the converged run at least as long as the old budget."""
    for n in range(1, _MIN_EPOCHS):
        assert not loss_plateaued(_flat(n), **_RULE), f"stopped at epoch {n}, below the floor"


def test_a_flat_curve_stops_at_the_epoch_floor() -> None:
    """Once the floor is reached, a curve that is not improving at all must terminate."""
    assert loss_plateaued(_flat(_MIN_EPOCHS), **_RULE)


def test_a_curve_still_improving_faster_than_the_tolerance_does_not_stop() -> None:
    """1% per epoch is ten times the tolerance, so the run continues however long it has run."""
    losses = [0.6 * (0.99**i) for i in range(40)]
    assert not loss_plateaued(losses, **_RULE)


def test_the_09_06b_twelve_epoch_curve_does_not_satisfy_the_rule() -> None:
    """The committed 09-06b curve. The rule must agree it had NOT converged at 12 epochs.

    This is the whole reason the rule exists, so it is pinned against the real numbers rather than
    against a constructed example.
    """
    losses = [
        0.5939, 0.5708, 0.5673, 0.5657, 0.5644, 0.5637,
        0.5632, 0.5615, 0.5603, 0.5599, 0.5592, 0.5584,
    ]
    assert not loss_plateaued(losses, **_RULE)


def test_a_single_flat_epoch_inside_a_descending_run_does_not_stop() -> None:
    """Patience 3 means one quiet epoch cannot end a run that is otherwise still learning."""
    losses = [0.6 * (0.99**i) for i in range(20)]
    losses.append(losses[-1])  # one epoch with no improvement at all
    assert not loss_plateaued(losses, **_RULE)


def test_a_diverged_curve_never_counts_as_converged() -> None:
    """A blow-up makes the improvements negative or non-finite; neither may read as a plateau."""
    finite_blowup = _flat(14) + [1e22, 4e22, 5e22]
    assert not loss_plateaued(finite_blowup, **_RULE)
    for bad in (math.nan, math.inf):
        assert not loss_plateaued(_flat(14) + [bad, bad, bad], **_RULE)


def test_the_tolerance_is_relative_not_absolute() -> None:
    """The same fractional curve gives the same verdict at any loss scale."""
    shape = [1.0 * (0.9995**i) for i in range(30)]  # 0.05% per epoch, below the tolerance
    assert loss_plateaued(shape, **_RULE)
    assert loss_plateaued([1000.0 * x for x in shape], **_RULE)
    assert loss_plateaued([0.001 * x for x in shape], **_RULE)


def test_a_worsening_curve_does_not_stop_even_though_improvement_is_below_tolerance() -> None:
    """A run that is getting WORSE has improvement below the tolerance but has not converged."""
    losses = _flat(14, 0.5) + [0.52, 0.55, 0.58]
    assert not loss_plateaued(losses, **_RULE)


def test_a_non_positive_tolerance_is_rejected() -> None:
    """A tolerance of 0 or below can never fire on a real curve; it is a silent no-op."""
    with pytest.raises(ValueError):
        loss_plateaued(_flat(20), rel_tol=0.0, patience=3, min_epochs=12)


def test_patience_must_be_at_least_one() -> None:
    with pytest.raises(ValueError):
        loss_plateaued(_flat(20), rel_tol=1e-3, patience=0, min_epochs=12)


# --- The loop actually obeys the rule -----------------------------------------------------------
# The tests above fix the arithmetic. These two fix the wiring, on a tiny real training run, because
# a rule the loop does not consult is a rule that does not exist.


def _tiny_run(**stop_kwargs: float | int | None) -> dict[str, object]:
    import numpy as np
    import torch
    from torch.utils.data import DataLoader, TensorDataset

    from ndt1.model_ane import NDT1ANE
    from ndt1.train import train_ndt1

    rng = np.random.default_rng(0)
    counts = rng.poisson(0.3, size=(8, 32, 96)).astype(np.float32)
    loader = DataLoader(TensorDataset(torch.from_numpy(counts)), batch_size=4, shuffle=False)
    torch.manual_seed(0)
    model = NDT1ANE(seq_len=32, d_model=16, num_layers=1, num_heads=2, dim_feedforward=32)
    return train_ndt1(
        model, loader, epochs=20, lr=1e-4, log_input=True, device="cpu", seed=0, **stop_kwargs  # type: ignore[arg-type]
    )


def test_the_loop_runs_the_full_cap_when_no_rule_is_supplied() -> None:
    """Default off: a caller that does not opt in gets exactly the pre-09-06c fixed budget."""
    history = _tiny_run()
    assert history["epochs_run"] == 20
    assert history["stop_reason"] == "epoch_cap"
    assert len(history["losses"]) == 20  # type: ignore[arg-type]


def test_the_loop_stops_early_when_the_rule_fires_and_says_so() -> None:
    """A wide tolerance fires immediately at the floor, so the stop is observable in a fast test."""
    history = _tiny_run(plateau_rel_tol=0.5, plateau_patience=_PATIENCE, min_epochs=5)
    assert history["stop_reason"] == "plateau"
    assert history["epochs_run"] == 5
    assert len(history["losses"]) == 5  # type: ignore[arg-type]


def test_the_rule_parameters_are_recorded_in_the_history_config() -> None:
    """A committed metrics JSON must carry the rule the run was stopped by, not just the epoch."""
    config = _tiny_run(plateau_rel_tol=0.5, plateau_patience=_PATIENCE, min_epochs=5)["config"]
    assert config["plateau_rel_tol"] == 0.5  # type: ignore[index]
    assert config["plateau_patience"] == _PATIENCE  # type: ignore[index]
    assert config["min_epochs"] == 5  # type: ignore[index]
    assert config["epochs"] == 20  # type: ignore[index]
