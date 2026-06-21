"""Short-budget smoke test for the NDT1 masked-modeling training loop (Plan 04-04 Task 2, SC2).

This is the QUICK (non-slow) CI gate: it proves the loop's convergence DIRECTION (the final-epoch
mean loss is strictly below the first-epoch mean loss) on the tiny synthetic fixture in a handful of
epochs — without the long training-to-convergence run (that is the committed evidence artifact, and
the held-out co-bps margin is the @pytest.mark.slow test). It also asserts losses stay finite (no
NaN/inf divergence) and that checkpoints save/load round-trip with ``weights_only=True``.
"""
from __future__ import annotations

import math

import torch
from torch.utils.data import DataLoader, TensorDataset

from ndt1.model_ane import NDT1ANE
from ndt1.train import load_checkpoint, save_checkpoint, train_ndt1

SEQ_LEN: int = 16  # small sequence for a fast smoke (the model's pos-encoding is sized to match)


def _tiny_loader(tiny_spike_counts: torch.Tensor, seq_len: int) -> DataLoader:
    """Wrap the (B, T, C) fixture into a trivial loader of (S, C) windows for the trainer."""
    windows = tiny_spike_counts[:, :seq_len, :]  # (B, seq_len, C)
    dataset = TensorDataset(windows)
    return DataLoader(dataset, batch_size=2, shuffle=False)


def test_training_loss_decreases_and_is_finite(tiny_spike_counts: torch.Tensor) -> None:
    """The masked-modeling loop reduces loss over a few epochs and never goes NaN/inf."""
    model = NDT1ANE(seq_len=SEQ_LEN)
    loader = _tiny_loader(tiny_spike_counts, SEQ_LEN)

    history = train_ndt1(
        model, loader, epochs=8, lr=1e-3, log_input=True, device="cpu", seed=0
    )

    losses = history["losses"]
    assert len(losses) == 8
    assert all(math.isfinite(x) for x in losses), f"non-finite loss in {losses}"
    # Convergence DIRECTION: final-epoch mean loss strictly below the first-epoch mean loss.
    assert losses[-1] < losses[0], f"loss did not decrease: first={losses[0]} last={losses[-1]}"


def test_training_is_deterministic(tiny_spike_counts: torch.Tensor) -> None:
    """Same seed + same init → identical loss trajectory (reproducibility, threat T-04-04-03).

    The global RNG is re-seeded immediately BEFORE each model's construction: ``nn.Module`` init
    draws from the global RNG, so the two models must start from identical weights for the
    trajectories to match. ``train_ndt1`` then re-seeds its own mask/optimizer RNG from ``seed``,
    making the run deterministic given a fixed initial model.
    """
    loader_a = _tiny_loader(tiny_spike_counts, SEQ_LEN)
    loader_b = _tiny_loader(tiny_spike_counts, SEQ_LEN)
    torch.manual_seed(0)
    model_a = NDT1ANE(seq_len=SEQ_LEN)
    torch.manual_seed(0)
    model_b = NDT1ANE(seq_len=SEQ_LEN)
    hist_a = train_ndt1(model_a, loader_a, epochs=4, lr=1e-3, log_input=True, device="cpu", seed=0)
    hist_b = train_ndt1(model_b, loader_b, epochs=4, lr=1e-3, log_input=True, device="cpu", seed=0)
    assert hist_a["losses"] == hist_b["losses"]


def test_checkpoint_round_trip(tmp_path, tiny_spike_counts: torch.Tensor) -> None:
    """save_checkpoint / load_checkpoint round-trip via torch.load(weights_only=True)."""
    model = NDT1ANE(seq_len=SEQ_LEN)
    loader = _tiny_loader(tiny_spike_counts, SEQ_LEN)
    train_ndt1(model, loader, epochs=2, lr=1e-3, log_input=True, device="cpu", seed=0)

    path = tmp_path / "ndt1_smoke.pt"
    save_checkpoint(model, path)
    assert path.exists()

    # Fresh model with the SAME architecture; load the saved weights back in.
    restored = NDT1ANE(seq_len=SEQ_LEN)
    # Sanity: a couple of params differ before loading (random init differs from trained).
    before = restored.read_in.weight.detach().clone()
    load_checkpoint(restored, path)
    after = restored.read_in.weight.detach()
    assert torch.equal(after, model.read_in.weight.detach()), "loaded weights != saved weights"
    assert not torch.equal(after, before), "load was a no-op (weights unchanged)"


def test_load_checkpoint_missing_file_raises(tmp_path) -> None:
    """A missing checkpoint raises FileNotFoundError (explicit; not a bare except)."""
    model = NDT1ANE(seq_len=SEQ_LEN)
    missing = tmp_path / "does_not_exist.pt"
    try:
        load_checkpoint(model, missing)
    except FileNotFoundError:
        return
    raise AssertionError("load_checkpoint should raise FileNotFoundError for a missing file")
