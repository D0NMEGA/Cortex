#!/usr/bin/env python3
"""Locate, to the step, where the real-data training path loses numerical stability (Plan 09-06c).

`deferred-items-09-06b.md` predicted that gradient clipping "would very likely" fix the divergences
this phase kept hitting. Plan 09-06c applied it and then checked, rather than assuming, and the
prediction was wrong: on the committed slow gate the clip moves the failure from epoch 8 to epoch 4
and turns a finite blow-up into a `nan`.

This script is how that was established, and it is committed so the claim in
`09-training-evidence.md` is reproducible rather than a transcript nobody can re-run. It replays
`tests/test_heldout_cobps.py`'s exact training path -- the naive concatenation of the four real
sessions with a single chronological split, `lr = 2e-3`, `seed = 0` -- one step at a time, and
records for every step:

  * the masked Poisson NLL,
  * the pre-clip total gradient norm (computed with an infinite cap, so it observes without
    changing anything), and
  * `max |predicted log-rate|`, which is the quantity that actually overflows.

The last of those is the point. With `log_input=True` the model term is `exp(x) - target * x`, and
`exp` overflows float32 above about 88.7, so a log-rate excursion becomes a `nan` loss and then
`nan` parameters. Gradient clipping acts one step AFTER that excursion, which is why it cannot
prevent this failure and why the ordering matters enough to measure.

It trains nothing that is kept, writes no checkpoint and no metrics: it prints and exits.

Usage:
    uv run --project Decoder python Decoder/scripts/diagnose_divergence.py            # clip 1.0
    uv run --project Decoder python Decoder/scripts/diagnose_divergence.py --clip 0   # no clip
    uv run --project Decoder python Decoder/scripts/diagnose_divergence.py --epochs 8
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np
import torch
from torch.nn.utils import clip_grad_norm_
from torch.utils.data import DataLoader

from ndt1.data import IndySpikeDataset, chronological_split
from ndt1.loss import hide_scored_positions, masked_poisson_nll, random_mask
from ndt1.model_ane import NDT1ANE
from ndt1.sessions import DEFAULT_DATA_DIR, available_sessions
from ndt1.train import reshape_to_bc1s

# The slow gate's constants, copied so this script reproduces that path and not another one.
SEED: int = 0
SEQ_LEN: int = 32
LR: float = 2e-3
TEST_FRAC: float = 0.2
BATCH_SIZE: int = 16
WEIGHT_DECAY: float = 0.01

#: float32 `exp` overflows above about 88.7; anything near it is already lost.
_OVERFLOW_LOG_RATE: float = 88.0
#: Report a step whose predicted log-rate is this far outside the healthy range (max 13.3 observed
#: over the first three clean epochs), so the excursion is visible before it becomes a `nan`.
_EXCURSION_LOG_RATE: float = 30.0
_TOP_N: int = 5


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Locate where the real-data training path loses numerical stability."
    )
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument(
        "--clip",
        type=float,
        default=1.0,
        help="max gradient norm; 0 disables clipping (the pre-09-06c behaviour)",
    )
    parser.add_argument("--epochs", type=int, default=4)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    loaded, _ = available_sessions(args.data_dir, min_bins=10 * SEQ_LEN)
    if not loaded:
        print(
            f"error: no real sessions under {args.data_dir}; this script diagnoses the REAL "
            f"training path and has nothing to say about the synthetic fallback",
            file=sys.stderr,
        )
        return 1

    pooled = np.concatenate([s.binned for s in loaded], axis=0)
    train_binned, _ = chronological_split(pooled, test_frac=TEST_FRAC)
    loader = DataLoader(
        IndySpikeDataset(train_binned, seq_len=SEQ_LEN), batch_size=BATCH_SIZE, shuffle=False
    )

    torch.manual_seed(SEED)
    model = NDT1ANE(seq_len=SEQ_LEN)
    torch.manual_seed(SEED)
    model.train()
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    mask_gen = torch.Generator(device="cpu")
    mask_gen.manual_seed(SEED)

    clip = None if args.clip <= 0.0 else float(args.clip)
    print(f"clip={clip}  sessions={len(loaded)}  steps/epoch={len(loader)}", flush=True)

    step = 0
    history: list[tuple[float, float, int]] = []  # (pre-clip norm, max |log-rate|, step)
    for epoch in range(1, args.epochs + 1):
        epoch_losses: list[float] = []
        for batch in loader:
            step += 1
            targets = reshape_to_bc1s(batch)
            mask = random_mask(targets.shape, model.mask_ratio, generator=mask_gen)
            rates = model(hide_scored_positions(targets, mask))
            loss = masked_poisson_nll(rates, targets, mask, log_input=True)
            max_log_rate = float(rates.detach().abs().max())

            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            # An infinite cap computes the norm without rescaling anything, so the observation is
            # of the run that actually happens rather than of a run this script perturbed.
            pre_clip = float(clip_grad_norm_(model.parameters(), float("inf")))
            if clip is not None:
                clip_grad_norm_(model.parameters(), clip)
            grads_nonfinite = any(
                p.grad is not None and not torch.isfinite(p.grad).all() for p in model.parameters()
            )
            optimizer.step()
            params_nonfinite = any(not torch.isfinite(p).all() for p in model.parameters())

            value = float(loss.detach())
            epoch_losses.append(value)
            history.append((pre_clip, max_log_rate, step))

            broken = (
                not math.isfinite(value)
                or grads_nonfinite
                or params_nonfinite
                or max_log_rate > _EXCURSION_LOG_RATE
            )
            if broken:
                print(
                    f"  !! step {step} (epoch {epoch}): loss={value:.6g} "
                    f"max|lograte|={max_log_rate:.4g} pre_clip_grad_norm={pre_clip:.6g} "
                    f"grad_nonfinite={grads_nonfinite} param_nonfinite={params_nonfinite}",
                    flush=True,
                )
            if params_nonfinite or not math.isfinite(value):
                by_norm = sorted(history, key=lambda row: -row[0])[:_TOP_N]
                by_rate = sorted(history, key=lambda row: -row[1])[:_TOP_N]
                print(
                    "  top pre-clip grad norms so far: "
                    + ", ".join(f"{n:.4g} (step {s})" for n, _, s in by_norm)
                )
                print(
                    "  top max|lograte| so far: "
                    + ", ".join(f"{r:.4g} (step {s})" for _, r, s in by_rate)
                )
                print(
                    f"  float32 exp overflows above about {_OVERFLOW_LOG_RATE}, so the log-rate "
                    f"excursion is the cause and the exploding gradient is its consequence."
                )
                return 0

        print(
            f"epoch {epoch}: mean loss {sum(epoch_losses) / len(epoch_losses):.6g}  "
            f"max pre-clip grad norm {max(n for n, _, _ in history):.6g}  "
            f"max |lograte| {max(r for _, r, _ in history):.4g}",
            flush=True,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
