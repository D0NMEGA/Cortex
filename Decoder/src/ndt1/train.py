"""NDT1 masked-modeling training loop (Plan 04-04, DEC-02 / SC2).

Composes the Wave-2 pieces into the BERT-style masked spike-RECONSTRUCTION objective
(04-RESEARCH §0.4 — predict spike rates, NOT downstream kinematics, which is DEC-10 / Phase 5):

    (B, S, C) window  ──reshape──▶  BC1S targets (B, C, 1, S)
        │                               │
        │                               ▼
        │                    hide_scored_positions(targets, mask)
        │                               │
        │                               ▼
        │                         NDT1ANE.forward  ──▶  predicted log-rates (B, C, 1, S)
        │                               │
        ▼                               ▼
    random_mask(...) ─▶ masked_poisson_nll(rates, targets, mask) ─▶ backward ─▶ clip ─▶ AdamW.step

The mask does two jobs and both are load-bearing: it selects the positions the Poisson NLL is
summed over, AND it corrupts those same positions in the encoder input (``masked_forward``), so
the model predicts a scored bin from its context and never from its own observed count. Plan 09-06
shipped only the first half; Plan 09-06b added the second and
``tests/test_masked_input_isolation.py`` holds it in place. Every co-bps measured before that
correction is superseded (``09-training-evidence.md``).

Numerical stability is handled in two places, and the order they were added in is the order the
failure happens in. The FORWARD pass is guarded by :data:`ndt1.loss.LOG_RATE_LINEARIZE_ABOVE`
(Plan 09-06d), which linearizes ``exp`` above a log-rate no healthy run reaches, so an excursion
gives a finite loss and a gradient that pulls the rate back down instead of a ``nan``. Gradients
are then norm-clipped between ``backward()`` and ``optimizer.step()`` (Plan 09-06c,
:data:`DEFAULT_GRAD_CLIP_NORM`), which stops an outlier gradient from poisoning AdamW's moment
estimates. 09-06c measured that the clip alone does NOT fix the overflow, because it acts one step
after the cause; the forward-pass guard is what reaches it.

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

import math
from collections.abc import Callable, Sequence
from pathlib import Path

import torch
from torch import Tensor, nn
from torch.nn.utils import clip_grad_norm_
from torch.utils.data import DataLoader

from ndt1.loss import hide_scored_positions, masked_poisson_nll, random_mask
from ndt1.metrics import co_bps, mean_firing_rate

#: Max total gradient norm for :func:`torch.nn.utils.clip_grad_norm_` (Plan 09-06c).
#:
#: 1.0 is the a-priori convention, not a value swept for a better number: it is the default in
#: HuggingFace ``Trainer`` (``max_grad_norm=1.0``) and the value BERT and GPT-2 style training
#: loops use. Nothing here was chosen by looking at a co-bps.
#:
#: Why the guard is needed at all: with ``log_input=True`` the Poisson NLL model term is
#: ``exp(rate) - target * rate``, so one predicted log-rate excursion overflows and the
#: gradients go non-finite. AdamW has nothing to arrest that. The failure fired three times on
#: real Indy spikes under the Plan 09-06b objective (two LOSO folds and the committed slow
#: gate); see ``deferred-items-09-06b.md`` item 1.
#:
#: What the cap does and does not buy, because it is easy to over-claim. AdamW normalizes each
#: coordinate by its own second-moment estimate, so rescaling the whole gradient vector leaves the
#: per-coordinate step roughly at ``lr``. The clip therefore stops an outlier gradient from
#: poisoning the moment estimates; it does NOT make an oversized learning rate safe. Measured in
#: ``tests/test_grad_clipping.py``: on the same batch, the clip turns a non-training run into a
#: descending one at ``lr = 0.05`` and changes nothing at ``lr = 0.1``.
DEFAULT_GRAD_CLIP_NORM: float = 1.0


def reshape_to_bc1s(window: Tensor) -> Tensor:
    """Reshape a ``(B, S, C)`` spike-count window to the ANE-conducive BC1S ``(B, C, 1, S)``.

    The model and loss operate in BC1S (sequence axis ``S`` last); ``IndySpikeDataset`` yields
    ``(S, C)`` windows that batch to ``(B, S, C)``. This is ``permute(0, 2, 1)`` then a unit
    height axis inserted at dim 2.
    """
    if window.ndim != 3:
        raise ValueError(f"expected a (B, S, C) window, got shape {tuple(window.shape)}")
    return window.permute(0, 2, 1).unsqueeze(2).contiguous()


def masked_forward(model: nn.Module, targets: Tensor, mask: Tensor) -> Tensor:
    """Encode ``targets`` with the scored positions hidden, and return the predicted log-rates.

    The one place the encoder input is built, for training and for evaluation alike. Both paths
    call this, because train/eval consistency is not optional: a fix applied to one call site and
    not the other would report a number produced under one objective and scored under another, and
    the mismatch would be invisible in the result.

    Until Plan 09-06b this function did not exist and both call sites ran ``model(targets)`` on the
    unmasked counts, so a scored position was an input to its own prediction and every co-bps the
    repository published measured self-reconstruction plus context.
    ``tests/test_masked_input_isolation.py`` now makes that impossible to reintroduce silently.

    Args:
        model: maps BC1S ``(B, C, 1, S)`` spike counts to log-rates of the same shape.
        targets: observed spike counts; passed through untouched to the caller's loss term.
        mask: boolean tensor; ``True`` marks the positions the loss will score.

    Returns:
        Predicted rates for every position, computed from an input in which the scored positions
        carry no information (see :func:`ndt1.loss.hide_scored_positions` for the masking choice).
    """
    return model(hide_scored_positions(targets, mask))


def loss_plateaued(
    losses: Sequence[float],
    *,
    rel_tol: float,
    patience: int,
    min_epochs: int,
) -> bool:
    """Has the training loss stopped moving? The convergence rule, on the LOSS and nothing else.

    Plan 09-06b's number came from a fixed 12-epoch budget inherited from Phase 4, on a curve that
    was still descending monotonically when the budget ran out, so it was a floor rather than an
    asymptote. Replacing that budget needs a stopping rule, and the rule must be defined on the
    training loss: stopping when the reported metric happens to look good is the tuning D-22 and
    D-25 exist to prevent. This function therefore cannot see a co-bps. Its only input is the loss
    curve.

    The rule: let ``r_i = (L_{i-1} - L_i) / |L_{i-1}|`` be the relative change at epoch ``i``. The
    curve has plateaued when ``|r_i| < rel_tol`` for each of the last ``patience`` epochs, and at
    least ``min_epochs`` epochs have run.

    Three properties of that formulation, each chosen for a reason:

    * **Every epoch in the window must be flat, not their mean.** A window averaging one large
      improvement against two equal regressions has a mean near zero while the run is visibly
      bouncing; the per-epoch form cannot be satisfied that way.
    * **The comparison is on the absolute value.** A run that is getting WORSE has a negative
      relative change, which is trivially "below" a positive tolerance, so a signed comparison
      would report a destabilizing run as converged. A diverging one would satisfy it most of all.
    * **The change is relative.** The same fractional curve gives the same verdict at any loss
      scale, so the rule does not silently mean something different on a different objective.

    Args:
        losses: per-epoch mean training loss, in order, for the epochs run so far.
        rel_tol: the flatness band, as a fraction of the previous epoch's loss. Must be positive.
        patience: how many consecutive epochs must be inside the band. Must be at least 1.
        min_epochs: a floor below which the rule never fires, whatever the curve looks like.

    Returns:
        ``True`` when the curve satisfies the rule; ``False`` otherwise, including whenever any
        loss in the window is non-finite, so a diverged run can never be reported as converged.

    Raises:
        ValueError: ``rel_tol`` is not positive, or ``patience`` is below 1. Both would make the
            rule a silent no-op, which is worse than a loud failure.
    """
    if rel_tol <= 0.0:
        raise ValueError(f"rel_tol must be positive, got {rel_tol}")
    if patience < 1:
        raise ValueError(f"patience must be at least 1, got {patience}")
    if len(losses) < max(min_epochs, patience + 1):
        return False
    window = losses[-(patience + 1) :]
    for previous, current in zip(window[:-1], window[1:], strict=True):
        if not (math.isfinite(previous) and math.isfinite(current)) or previous == 0.0:
            return False
        if abs((previous - current) / abs(previous)) >= rel_tol:
            return False
    return True


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
    grad_clip_norm: float | None = DEFAULT_GRAD_CLIP_NORM,
    plateau_rel_tol: float | None = None,
    plateau_patience: int = 3,
    min_epochs: int = 0,
    on_epoch_end: Callable[[int, float], None] | None = None,
) -> dict[str, object]:
    """Run masked-modeling training: mask → forward → clip → masked Poisson NLL → AdamW step.

    Args:
        model: an ``NDT1ANE`` (carries ``.mask_ratio``); maps BC1S ``(B, C, 1, S)`` → log-rates.
        train_loader: yields ``(B, S, C)`` spike-count windows (or 1-tuples thereof).
        epochs: HARD CAP on passes over ``train_loader``. With ``plateau_rel_tol`` unset this is
            simply the budget; with it set the loop may stop earlier, never later.
        lr: AdamW learning rate.
        log_input: passed to ``masked_poisson_nll`` / ``co_bps``. ``True`` ⇒ the model emits
            log-rates (the natural choice for the linear readout — see 04-03 hand-forward).
        device: torch device string (``"cpu"`` / ``"mps"``); training is hardware-agnostic R&D.
        seed: RNG seed for reproducible masks + init-order (threat T-04-04-03).
        weight_decay: AdamW decoupled weight decay.
        eval_set: optional ``(eval_targets_bc1s, eval_mask)`` for a held-out co-bps reported in
            the history under ``"eval_co_bps"`` (train-split mean rate is the null).
        grad_clip_norm: max total gradient norm applied between ``backward()`` and
            ``optimizer.step()``. On by default, because a numerical-stability guard every caller
            has to remember to switch on is one the next caller will forget. ``None`` disables it,
            which is what every run before Plan 09-06c did; see :data:`DEFAULT_GRAD_CLIP_NORM`.
        plateau_rel_tol: when set, stop early once :func:`loss_plateaued` says the TRAINING LOSS
            has flattened. ``None`` keeps the pre-09-06c fixed-budget behaviour, so no caller
            that does not opt in changes.
        plateau_patience: consecutive flat epochs the rule requires. Ignored when
            ``plateau_rel_tol`` is ``None``.
        min_epochs: floor below which the rule never fires. Ignored likewise.
        on_epoch_end: optional ``(epoch_number, mean_loss) -> None`` progress hook. Read-only
            by contract: a run that takes hours needs to be observable while it runs, and a
            hook that could touch the RNG or the optimizer would make the log a variable.

    Returns:
        ``{"losses": [per-epoch mean loss, ...], "max_log_rate_per_epoch": [...], "epochs_run":
           int, "stop_reason": "plateau" | "epoch_cap", "eval_co_bps": float | None, "config":
           {...}}``. ``max_log_rate_per_epoch`` is the largest raw model output seen during the
        epoch (a LOG-rate whenever ``log_input`` is ``True``, which is the only configuration this
        repository trains in). It exists so a reader can check, against the run that was actually
        published, whether the loss ever entered the linearized branch above
        :data:`ndt1.loss.LOG_RATE_LINEARIZE_ABOVE`.
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
    max_log_rates: list[float] = []
    stop_reason = "epoch_cap"
    for _epoch in range(epochs):
        batch_losses: list[float] = []
        epoch_max_rate = -math.inf
        for batch in train_loader:
            window = _unwrap_batch(batch).to(dev)
            targets = reshape_to_bc1s(window)
            mask = random_mask(targets.shape, mask_ratio, generator=mask_gen).to(dev)

            rates = masked_forward(model, targets, mask)
            loss = masked_poisson_nll(rates, targets, mask, log_input=log_input)
            # Read-only, and the reason it is here: `ndt1.loss.LOG_RATE_LINEARIZE_ABOVE` only
            # changes the objective for outputs above it, so recording the largest output each
            # epoch is what turns "the guard is inert in the healthy regime" from an argument into
            # a measurement on the run that was actually published.
            epoch_max_rate = max(epoch_max_rate, float(rates.detach().max()))

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            if grad_clip_norm is not None:
                clip_grad_norm_(model.parameters(), grad_clip_norm)
            optimizer.step()
            batch_losses.append(float(loss.detach().item()))
        losses.append(sum(batch_losses) / max(len(batch_losses), 1))
        max_log_rates.append(epoch_max_rate)
        if on_epoch_end is not None:
            on_epoch_end(len(losses), losses[-1])
        if plateau_rel_tol is not None and loss_plateaued(
            losses,
            rel_tol=plateau_rel_tol,
            patience=plateau_patience,
            min_epochs=min_epochs,
        ):
            stop_reason = "plateau"
            break

    eval_co_bps: float | None = None
    if eval_set is not None:
        eval_targets, eval_mask = eval_set
        eval_co_bps = evaluate_co_bps(
            model, eval_targets.to(dev), eval_mask.to(dev), log_input=log_input
        )

    return {
        "losses": losses,
        "max_log_rate_per_epoch": max_log_rates,
        "epochs_run": len(losses),
        "stop_reason": stop_reason,
        "eval_co_bps": eval_co_bps,
        "config": {
            "epochs": epochs,
            "lr": lr,
            "log_input": log_input,
            "seed": seed,
            "weight_decay": weight_decay,
            "mask_ratio": mask_ratio,
            "grad_clip_norm": grad_clip_norm,
            "plateau_rel_tol": plateau_rel_tol,
            "plateau_patience": plateau_patience,
            "min_epochs": min_epochs,
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
        rates = masked_forward(model, eval_targets, eval_mask)
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
