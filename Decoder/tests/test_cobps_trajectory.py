"""The co-bps-versus-epoch probe must observe the run without being part of it (Plan 09-06d).

Plan 09-06d publishes the whole co-bps trajectory rather than a value chosen by a stopping rule,
which means a full held-out scoring pass now runs INSIDE training every ``COBPS_SAMPLE_EVERY``
epochs. That pass flips the model into ``eval()`` mode, runs forward passes over thousands of
windows, and flips it back. If any of that touched the RNG or the optimizer, the published loss
curve would be a curve produced by the act of measuring it.

The argument that it does not is short -- ``nn.Dropout`` draws no random numbers in ``eval()``
mode, the scoring mask comes from its own explicitly seeded ``torch.Generator``, and the forward
passes run under ``no_grad`` -- but an argument is not a measurement. These tests assert the
equality directly: a run with the probe attached produces a loss curve BIT-IDENTICAL to a run
without it.

They also pin the per-epoch ``max_log_rate`` record, which is what lets the evidence say whether
the 09-06d loss stabilizer ever activated on the run that was actually published rather than only
whether it could have.
"""
from __future__ import annotations

from typing import cast

import torch
from torch.utils.data import DataLoader, TensorDataset

from ndt1.loss import LOG_RATE_LINEARIZE_ABOVE
from ndt1.model_ane import NDT1ANE
from ndt1.train import masked_forward, train_ndt1

SEED: int = 0
SEQ_LEN: int = 8
EPOCHS: int = 4


def _tiny_loader(*, num_windows: int = 24, channels: int = 96) -> DataLoader:
    """A deterministic (B, S, C) loader small enough for the quick gate."""
    generator = torch.Generator()
    generator.manual_seed(SEED)
    counts = torch.poisson(
        torch.full((num_windows, SEQ_LEN, channels), 0.3), generator=generator
    )
    return DataLoader(TensorDataset(counts), batch_size=8, shuffle=False)


def _fresh_model() -> NDT1ANE:
    torch.manual_seed(SEED)
    return NDT1ANE(seq_len=SEQ_LEN)


def _run(on_epoch_end=None) -> dict[str, object]:
    return train_ndt1(
        _fresh_model(),
        _tiny_loader(),
        epochs=EPOCHS,
        lr=2e-3,
        log_input=True,
        seed=SEED,
        on_epoch_end=on_epoch_end,
    )


def test_a_scoring_probe_inside_training_does_not_move_the_loss_curve() -> None:
    """The load-bearing one: measuring co-bps mid-run must not change the run.

    The probe here does everything the real one does -- ``eval()``, a seeded mask, chunked
    ``no_grad`` forward passes over a held-out set, then ``train()`` again -- so if any of that
    consumed the training RNG stream, this comparison would catch it.
    """
    baseline = _run()

    probe_calls: list[int] = []
    model_box: dict[str, NDT1ANE] = {}

    def probe(epoch: int, _loss: float) -> None:
        model = model_box["model"]
        probe_calls.append(epoch)
        generator = torch.Generator()
        generator.manual_seed(SEED)
        held_out = torch.poisson(torch.full((16, 96, 1, SEQ_LEN), 0.3), generator=generator)
        mask = torch.rand(held_out.shape, generator=generator) < 0.25
        model.eval()
        with torch.no_grad():
            masked_forward(model, held_out, mask)
        model.train()

    torch.manual_seed(SEED)
    model = NDT1ANE(seq_len=SEQ_LEN)
    model_box["model"] = model
    probed = train_ndt1(
        model,
        _tiny_loader(),
        epochs=EPOCHS,
        lr=2e-3,
        log_input=True,
        seed=SEED,
        on_epoch_end=probe,
    )

    assert probe_calls == list(range(1, EPOCHS + 1))
    assert probed["losses"] == baseline["losses"], (
        "the co-bps probe changed the training loss curve, so the published trajectory would be a "
        "record of the measurement rather than of the run"
    )


def test_the_history_records_the_max_log_rate_per_epoch() -> None:
    """One entry per epoch, finite, so the stabilizer's inertness is checkable after the fact."""
    history = _run()
    max_log_rates = history["max_log_rate_per_epoch"]
    assert isinstance(max_log_rates, list)
    assert len(max_log_rates) == len(cast(list[float], history["losses"])) == EPOCHS
    assert all(isinstance(x, float) for x in max_log_rates)


def test_healthy_training_stays_far_below_the_linearization_threshold() -> None:
    """A healthy run does not enter the linearized branch, so the guard changes nothing here."""
    history = _run()
    max_log_rates = cast(list[float], history["max_log_rate_per_epoch"])
    assert max(max_log_rates) < LOG_RATE_LINEARIZE_ABOVE, (
        f"training reached a log-rate of {max(max_log_rates)}, at or above the "
        f"{LOG_RATE_LINEARIZE_ABOVE} threshold, so the loss stabilizer was active during a run "
        f"that is supposed to be healthy"
    )
