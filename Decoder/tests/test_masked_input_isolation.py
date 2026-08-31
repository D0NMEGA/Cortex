"""The encoder must not be able to read the positions the objective scores it on (Plan 09-06b).

Plan 09-06 published a pooled held-out co-bps of 1.9116 bits/spike and then measured, rather than
assumed, the caveat that made it unquotable: ``train_ndt1`` called ``model(targets)`` on the
UNMASKED counts and used the mask only to select which positions the Poisson NLL was summed over.
``NDT1ANE.forward`` performs no input masking either. So every position the loss scored was an
input to the prediction of that same position, and the number measured self-reconstruction plus
context rather than context alone. The module docstring called the objective "BERT-style masked
spike-RECONSTRUCTION", but BERT corrupts its input and this never did.

These tests make that defect impossible to reintroduce silently. The discriminating probe is a
perturbation test rather than a source grep:

    perturb the observed counts at the scored positions, and the prediction at those positions
    must not move by a single bit.

Under the defect the perturbed value reaches the encoder and every output shifts. Under a correct
objective the corrupted input is identical, so the outputs are bit-identical. A source grep would
pass on a rewrite that hid the input in one call site and not the other;
``test_train_ndt1_never_shows_the_encoder_a_scored_position`` and its eval twin check the two paths
that actually produce committed numbers.

The anti-degenerate direction is checked too: a model that ignored its input entirely would satisfy
"the scored value cannot move the prediction" trivially, so
``test_unscored_positions_still_influence_predictions`` asserts the UNMASKED context does still
reach the encoder.

Quick tests: a 6-channel, 1-layer NDT1ANE on 4 synthetic windows. No dataset, no convergence, no
training budget -- the property is structural, not statistical.
"""
from __future__ import annotations

import torch
from torch import Tensor, nn
from torch.utils.data import DataLoader, TensorDataset

from ndt1.loss import random_mask
from ndt1.model_ane import NDT1ANE
from ndt1.train import evaluate_co_bps, masked_forward, reshape_to_bc1s, train_ndt1

SEED: int = 0
SEQ_LEN: int = 8
NUM_CHANNELS: int = 6
BATCH: int = 4
MASK_RATIO: float = 0.25
#: Large enough that a leak could not hide inside float32 rounding: if the perturbed value reached
#: the encoder, the readout moves far more than any tolerance would excuse.
PERTURBATION: float = 7.0


def _tiny_model() -> NDT1ANE:
    """A small NDT1ANE with the same forward graph as the 1.29M-param model, built in ~1 ms."""
    torch.manual_seed(SEED)
    model = NDT1ANE(
        num_channels=NUM_CHANNELS,
        d_model=16,
        num_layers=1,
        num_heads=1,
        dim_feedforward=16,
        seq_len=SEQ_LEN,
        mask_ratio=MASK_RATIO,
    )
    model.eval()  # dropout off, so two forwards on identical inputs are bit-identical
    return model


def _counts_and_mask() -> tuple[Tensor, Tensor]:
    """Deterministic BC1S Poisson counts and a mask that is neither empty nor everything."""
    generator = torch.Generator()
    generator.manual_seed(SEED)
    counts = torch.poisson(
        torch.full((BATCH, NUM_CHANNELS, 1, SEQ_LEN), 1.5), generator=generator
    )
    mask_gen = torch.Generator()
    mask_gen.manual_seed(SEED)
    mask = random_mask(counts.shape, MASK_RATIO, generator=mask_gen)
    assert bool(mask.any()) and not bool(mask.all()), "the probe needs a partial mask"
    return counts, mask


class _RecordingModel(nn.Module):
    """Wraps a model and keeps every tensor it was actually asked to encode.

    This is how the trainer and the evaluator are checked: not by reading their source, but by
    looking at what reached the encoder. ``mask_ratio`` is mirrored because ``train_ndt1`` reads it
    off the model to size its mask.
    """

    def __init__(self, inner: NDT1ANE) -> None:
        super().__init__()
        self.inner = inner
        self.mask_ratio = float(inner.mask_ratio)
        self.seen: list[Tensor] = []

    def forward(self, x: Tensor) -> Tensor:
        self.seen.append(x.detach().clone())
        return self.inner(x)


def test_a_scored_position_cannot_influence_its_own_prediction() -> None:
    """Perturbing the counts at scored positions must not move the prediction there, at all.

    This is the defect Plan 09-06 measured and Plan 09-06b closes. It fails loudly on the old code:
    ``model(targets)`` makes the scored value an input to its own prediction.
    """
    model = _tiny_model()
    counts, mask = _counts_and_mask()

    perturbed = counts + mask.to(counts.dtype) * PERTURBATION
    assert not torch.equal(counts, perturbed), "the perturbation must actually change something"
    assert torch.equal(counts[~mask], perturbed[~mask]), "only scored positions may be perturbed"

    rates = masked_forward(model, counts, mask)
    rates_perturbed = masked_forward(model, perturbed, mask)

    assert torch.equal(rates[mask], rates_perturbed[mask]), (
        "the prediction at a scored position moved when that position's own observed count was "
        "perturbed, so the encoder can read the values the Poisson NLL scores it on. The objective "
        "is measuring self-reconstruction, not context (Plan 09-06 deferred item 1). Max delta at "
        f"scored positions: {(rates[mask] - rates_perturbed[mask]).abs().max().item():.6g}"
    )
    # Strictly stronger, and the reason the property is checkable at all: a hidden input makes the
    # two forward passes bit-identical everywhere, not only where the loss looks.
    assert torch.equal(rates, rates_perturbed)


def test_unscored_positions_still_influence_predictions() -> None:
    """A model that ignored its input would pass the test above; this one it cannot pass.

    Perturbing the UNMASKED context must move the predictions at the scored positions, because
    predicting a hidden bin from its surrounding context is the entire objective.
    """
    model = _tiny_model()
    counts, mask = _counts_and_mask()

    perturbed = counts + (~mask).to(counts.dtype) * PERTURBATION
    assert torch.equal(counts[mask], perturbed[mask]), "only context positions may be perturbed"

    rates = masked_forward(model, counts, mask)
    rates_perturbed = masked_forward(model, perturbed, mask)

    delta = (rates[mask] - rates_perturbed[mask]).abs().max().item()
    assert delta > 1e-4, (
        "perturbing the unmasked context did not move the predictions at the scored positions "
        f"(max delta {delta:.6g}). The encoder is ignoring its input, which would satisfy the "
        "isolation test for the wrong reason."
    )


def test_train_ndt1_never_shows_the_encoder_a_scored_position() -> None:
    """Every tensor the training loop hands the encoder is zero wherever the loss will score it.

    The masks are reproduced exactly: ``train_ndt1`` draws them from a generator seeded with
    ``seed`` and consumes the loader in order, so the same sequence of ``random_mask`` calls
    reconstructs them. Checking the recorded inputs is stronger than checking the source, because
    it catches a fix applied to one call site and not the other.
    """
    counts, _ = _counts_and_mask()
    windows = counts.squeeze(2).permute(0, 2, 1).contiguous()  # BC1S -> (B, S, C)
    loader = DataLoader(TensorDataset(windows), batch_size=2, shuffle=False)

    recorder = _RecordingModel(_tiny_model())
    train_ndt1(recorder, loader, epochs=1, lr=1e-3, log_input=True, device="cpu", seed=SEED)
    assert recorder.seen, "the training loop never called the encoder"

    replay = torch.Generator()
    replay.manual_seed(SEED)
    for seen in recorder.seen:
        mask = random_mask(seen.shape, MASK_RATIO, generator=replay)
        leaked = int((seen[mask] != 0.0).sum().item())
        assert leaked == 0, (
            f"{leaked} of {int(mask.sum().item())} scored positions carried a nonzero value into "
            "the encoder during training. train_ndt1 must corrupt the input at the positions the "
            "masked Poisson NLL is summed over."
        )


def test_evaluate_co_bps_never_shows_the_encoder_a_scored_position() -> None:
    """The evaluation path hides the same positions the training path does.

    Train/eval consistency is not optional here. An eval-only or train-only fix would report a
    number produced under one objective and scored under another, which is worse than the defect
    it replaces because the mismatch is invisible in the result.
    """
    counts, mask = _counts_and_mask()
    recorder = _RecordingModel(_tiny_model())

    value = evaluate_co_bps(recorder, counts, mask, log_input=True)
    assert isinstance(value, float)
    assert len(recorder.seen) == 1, f"expected one encoder call, saw {len(recorder.seen)}"

    leaked = int((recorder.seen[0][mask] != 0.0).sum().item())
    assert leaked == 0, (
        f"{leaked} of {int(mask.sum().item())} scored positions carried a nonzero value into the "
        "encoder during evaluation, so the reported co-bps includes self-reconstruction."
    )


def test_reshape_round_trip_used_by_the_probe_is_faithful() -> None:
    """Guards the ``(B, S, C)`` inversion the trainer probe relies on, so failures are clear."""
    counts, _ = _counts_and_mask()
    windows = counts.squeeze(2).permute(0, 2, 1).contiguous()
    assert torch.equal(reshape_to_bc1s(windows), counts)
