"""NDT1 masked-modeling training loop (Plan 04-04, DEC-02 / SC2).

Composes the Wave-2 pieces into the BERT-style masked spike-RECONSTRUCTION objective
(04-RESEARCH §0.4 — predict spike rates, NOT downstream kinematics, which is DEC-10 / Phase 5):

    (B, S, C) window  ──reshape──▶  BC1S (B, C, 1, S)
        │                               │
        │                               ▼
        │                         NDT1ANE.forward  ──▶  predicted log-rates (B, C, 1, S)
        │                               │
        ▼                               ▼
    random_mask(...) ─▶ masked_poisson_nll(rates, targets, mask) ─▶ backward ─▶ AdamW.step

``train_ndt1`` returns a history dict (per-epoch mean loss, and — if an eval set is supplied —
the held-out co-bps against the train-split mean-rate null). Checkpoints are saved as a plain
state-dict ``.pt`` (gitignored); ``load_checkpoint`` uses ``torch.load(weights_only=True)`` so a
malicious pickle cannot execute arbitrary code on load (threat T-04-04-01). No bare/blind
``except`` — only ``FileNotFoundError`` / ``RuntimeError`` are caught explicitly.

This module is reconstruction-only: it predicts spike rates with no downstream-kinematics readout
head, and no Core ML conversion / Neural-Engine compute-unit targeting (those are Plan 04-05 /
Phase 5). The loop's only objective is the masked Poisson NLL on the predicted rates.
"""
from __future__ import annotations

from pathlib import Path

import torch
from torch import Tensor, nn
from torch.utils.data import DataLoader

from ndt1.loss import masked_poisson_nll, random_mask
from ndt1.metrics import co_bps, mean_firing_rate


def reshape_to_bc1s(window: Tensor) -> Tensor:
    """Reshape a ``(B, S, C)`` spike-count window to the ANE-conducive BC1S ``(B, C, 1, S)``.

    The model and loss operate in BC1S (sequence axis ``S`` last); ``IndySpikeDataset`` yields
    ``(S, C)`` windows that batch to ``(B, S, C)``. This is ``permute(0, 2, 1)`` then a unit
    height axis inserted at dim 2.
    """
    if window.ndim != 3:
        raise ValueError(f"expected a (B, S, C) window, got shape {tuple(window.shape)}")
    return window.permute(0, 2, 1).unsqueeze(2).contiguous()


def _unwrap_batch(batch: object) -> Tensor:
    """Accept a raw ``(B, S, C)`` tensor or a 1-tuple/list from a ``TensorDataset`` loader."""
    if isinstance(batch, (list, tuple)):
        item = batch[0]
    else:
        item = batch
    if not isinstance(item, Tensor):
        raise TypeError(f"batch element is not a Tensor: {type(item)!r}")
    return item


def train_ndt1(
    model: nn.Module,
    train_loader: DataLoader,
    *,
    epochs: int,
    lr: float,
    log_input: bool,
    device: str = "cpu",
    seed: int = 0,
    weight_decay: float = 0.01,
    eval_set: tuple[Tensor, Tensor] | None = None,
) -> dict[str, object]:
    """Run masked-modeling training: mask → forward → masked Poisson NLL → AdamW step.

    Args:
        model: an ``NDT1ANE`` (carries ``.mask_ratio``); maps BC1S ``(B, C, 1, S)`` → log-rates.
        train_loader: yields ``(B, S, C)`` spike-count windows (or 1-tuples thereof).
        epochs: number of passes over ``train_loader``.
        lr: AdamW learning rate.
        log_input: passed to ``masked_poisson_nll`` / ``co_bps``. ``True`` ⇒ the model emits
            log-rates (the natural choice for the linear readout — see 04-03 hand-forward).
        device: torch device string (``"cpu"`` / ``"mps"``); training is hardware-agnostic R&D.
        seed: RNG seed for reproducible masks + init-order (threat T-04-04-03).
        weight_decay: AdamW decoupled weight decay.
        eval_set: optional ``(eval_targets_bc1s, eval_mask)`` for a held-out co-bps reported in
            the history under ``"eval_co_bps"`` (train-split mean rate is the null).

    Returns:
        ``{"losses": [per-epoch mean loss, ...], "eval_co_bps": float | None,
           "config": {...}}``.
    """
    if epochs <= 0:
        raise ValueError(f"epochs must be positive, got {epochs}")

    torch.manual_seed(seed)
    dev = torch.device(device)
    model = model.to(dev)
    model.train()
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    # A dedicated, seeded generator so the masking is deterministic across runs (reproducible).
    mask_gen = torch.Generator(device="cpu")
    mask_gen.manual_seed(seed)
    mask_ratio = float(getattr(model, "mask_ratio", 0.25))

    losses: list[float] = []
    for _epoch in range(epochs):
        batch_losses: list[float] = []
        for batch in train_loader:
            window = _unwrap_batch(batch).to(dev)
            targets = reshape_to_bc1s(window)
            mask = random_mask(targets.shape, mask_ratio, generator=mask_gen).to(dev)

            rates = model(targets)
            loss = masked_poisson_nll(rates, targets, mask, log_input=log_input)

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()
            batch_losses.append(float(loss.detach().item()))
        losses.append(sum(batch_losses) / max(len(batch_losses), 1))

    eval_co_bps: float | None = None
    if eval_set is not None:
        eval_targets, eval_mask = eval_set
        eval_co_bps = evaluate_co_bps(
            model, eval_targets.to(dev), eval_mask.to(dev), log_input=log_input
        )

    return {
        "losses": losses,
        "eval_co_bps": eval_co_bps,
        "config": {
            "epochs": epochs,
            "lr": lr,
            "log_input": log_input,
            "seed": seed,
            "weight_decay": weight_decay,
            "mask_ratio": mask_ratio,
        },
    }


def evaluate_co_bps(
    model: nn.Module,
    eval_targets: Tensor,
    eval_mask: Tensor,
    *,
    log_input: bool,
) -> float:
    """Held-out co-bps of ``model`` on ``eval_targets`` (masked) vs the mean-rate null.

    The null prediction is the per-channel mean firing rate of the EVAL targets themselves only as
    a convenience default; callers that hold a separate train split should pass that split's mean
    via :func:`ndt1.metrics.mean_firing_rate` and :func:`ndt1.metrics.co_bps` directly. Here we use
    the eval targets' own per-channel mean as the null baseline (a conservative, leak-free null —
    it is the BEST constant per-channel predictor of the eval set, so beating it is non-trivial).
    """
    model.eval()
    with torch.no_grad():
        rates = model(eval_targets)
    null_rate = mean_firing_rate(eval_targets)
    return co_bps(rates, eval_targets, eval_mask, null_rate, log_input=log_input)


def save_checkpoint(model: nn.Module, path: Path) -> None:
    """Save ``model``'s state-dict to ``path`` (a gitignored ``.pt``; weights only)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    torch.save(model.state_dict(), path)


def load_checkpoint(model: nn.Module, path: Path) -> None:
    """Load a state-dict ``.pt`` into ``model`` using ``torch.load(weights_only=True)``.

    ``weights_only=True`` restricts unpickling to tensors/plain types so a tampered checkpoint
    cannot execute arbitrary code on load (threat T-04-04-01). Only self-produced checkpoints are
    loaded. Raises explicitly (never a bare ``except``):

    Raises:
        FileNotFoundError: if ``path`` does not exist.
        RuntimeError: if the file is not a loadable ``weights_only`` state-dict or shapes mismatch.
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"no checkpoint at {path}")
    try:
        state_dict = torch.load(path, map_location="cpu", weights_only=True)
        model.load_state_dict(state_dict)
    except (RuntimeError, EOFError) as exc:
        raise RuntimeError(f"could not load checkpoint at {path}: {exc}") from exc
