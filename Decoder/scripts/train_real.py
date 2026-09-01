#!/usr/bin/env python3
"""Retrain NDT1 on the real Indy sessions; write the provenance-bearing metrics (RD-03, RD-04).

Produces, in one run:

  1. **One pooled checkpoint** (D-11) trained on the four sessions' TRAIN halves with the Phase-4
     hyperparameters verbatim (D-14) but NOT the Phase-4 objective, which Plan 09-06b corrected.
     See the masking note below: D-14 comparability with the synthetic 0.3804 is deliberately
     broken, because 0.3804 was produced by the defect.
  2. **Per-session held-out co-bps** (RD-04a) on each session's own chronological tail (D-12),
     scored against BOTH nulls (see below).
  3. **A full four-fold leave-one-session-out rotation** (RD-04b, D-13): retrain from scratch on
     three sessions, evaluate on the fourth's FULL binned matrix with zero exposure, rotate.
  4. **The metrics JSON**, carrying `data_source`, every session id and the sha256 it was produced
     from, the checkpoint's own sha256, the config, the loss curve and every measured number.

**Two nulls, both reported (P8, T-09-06-04).** `co_bps` is a comparison against a constant
per-channel rate predictor, so which constant you pick moves the number:

  * `train_null` -- the per-channel mean of the POOLED TRAIN split. This is the D-22 gate: it is
    fit on data the model trained on, so it is leakage-free, but it cannot adapt to within-session
    drift or to cross-session heterogeneity. Measured drift on `indy_20160630_01` is -8.1% in mean
    rate from train head to test tail, which is the direction that INFLATES a train-null co-bps.
  * `test_mean_null` -- the per-channel mean of the EVALUATION spikes themselves, the NLB'21
    convention. A null fit on the evaluation data is strictly stronger, so this is the drift-robust
    floor.
  * `session_train_null` -- per-session held-out eval only: the per-channel mean of THAT session's
    own train half. It sits between the other two and separates within-session drift from
    cross-session heterogeneity, which the pooled `train_null` otherwise conflates.

**D-22 forbids picking the assertion margin first.** This script writes `co_bps.margin` and
`co_bps.margin_rationale` as `null`, always. The margin is re-derived from the OBSERVED value
afterwards and written by the evidence step. Re-running this script therefore CLEARS a previously
derived margin, which is deliberate: a margin must never outlive the measurement it was derived
from, and `tests/test_cobps_margin.py` fails loudly when it has.

**The scored positions are HIDDEN from the encoder (Plan 09-06b).** They were not when this
script first ran: `train_ndt1` called `model(targets)` on the unmasked counts and used the mask
only to select which positions the Poisson NLL was summed over, so the pooled 1.9116 it published
measured self-reconstruction plus context rather than context alone. `ndt1.train.masked_forward`
now corrupts the input at every scored position and `_score` does the same, so training and
scoring share one objective. Every number this script produced before that correction is
superseded and is preserved in the metrics JSON under `superseded_visible_input_objective`.

This breaks D-14 comparability with the Phase-4 config-verbatim run, deliberately: Phase 4's
0.3804 came out of the same defective objective, so comparability to it was never meaningful.
Everything else in the config is unchanged, so the objective is the only variable between the
superseded numbers and the current ones.

**Do not tune.** D-25: a low honest number completes the phase. A pooled value below the
per-session values is the expected D-15 outcome. A LOSO fold near zero or negative means channel
identity did not transfer across sessions -- a publishable finding, not a defect to reshape the
pool over.

**The epoch budget is decided by a PRE-REGISTERED rule, not by a constant (Plan 09-06c).** The
09-06b run used a fixed 12 epochs inherited from Phase 4 and stopped on a curve still descending
monotonically, so its 0.0062 was a floor rather than an asymptote. The rule that replaces it is
defined on the TRAINING LOSS alone and is committed before the run reads it; see the
PLATEAU_REL_TOL block below. Gradients are also norm-clipped now (`ndt1.train`), which is the
numerical-stability fix for the divergences 09-06b reported and deferred.

Runtime on this machine's CPU is roughly 70 s per pooled epoch and about 211 s per epoch across
the four rotation folds, so a run that goes to the 60-epoch cap is about 4.7 h. CI never runs this
(D-21).

Checkpoints are state-dict `.pt` files under the gitignored `Decoder/checkpoints/`; any load goes
through `ndt1.train.load_checkpoint`, which uses `torch.load(..., weights_only=True)` (T-04-04-01).
No bare/blind `except`.

Usage:
    uv run --project Decoder python Decoder/scripts/train_real.py --smoke   # wiring check
    uv run --project Decoder python Decoder/scripts/train_real.py           # the real run
    uv run --project Decoder python Decoder/scripts/train_real.py --skip-loso
    uv run --project Decoder python Decoder/scripts/train_real.py --diagnostic
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import sys
import time
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import cast

import h5py
import numpy as np
import torch
from torch import Tensor, nn
from torch.utils.data import DataLoader, TensorDataset

from ndt1.data import BIN_MS, IndySpikeDataset
from ndt1.loss import hide_scored_positions, random_mask
from ndt1.metrics import co_bps, mean_firing_rate
from ndt1.model_ane import NDT1ANE
from ndt1.sessions import (
    DEFAULT_DATA_DIR,
    DEFAULT_MANIFEST,
    SessionLoad,
    available_sessions,
    loso_folds,
    pooled_splits,
)
from ndt1.train import (
    DEFAULT_GRAD_CLIP_NORM,
    load_checkpoint,
    reshape_to_bc1s,
    save_checkpoint,
    train_ndt1,
)

# --- Phase-4 config, copied VERBATIM (D-14) ---------------------------------------------------
# These are the exact constants in tests/test_heldout_cobps.py that produced the synthetic co-bps
# 0.3804, and they are unchanged: not for comparability with 0.3804, which Plan 09-06b gave up
# (that number came out of the same defective objective, so comparing to it was never meaningful),
# but so that the OBJECTIVE is the only variable between the superseded numbers in this file and
# the current ones. D-14 permits RAISING the epoch budget if the curve has clearly not converged,
# and forbids lowering it. D-25 forbids moving any of these to improve the result.
SEED: int = 0
SEQ_LEN: int = 32
LR: float = 2e-3
TEST_FRAC: float = 0.2
BATCH_SIZE: int = 16
WEIGHT_DECAY: float = 0.01
LOG_INPUT: bool = True
DEVICE: str = "cpu"

#: Evaluation forward passes are chunked so a 5,254-window session does not materialize every
#: encoder activation at once. Purely a memory bound; it does not change any number.
EVAL_CHUNK: int = 512

# --- The PRE-REGISTERED convergence rule (Plan 09-06c) -----------------------------------------
# Written into 09-training-evidence.md and committed BEFORE the run that reads it, because a
# stopping rule chosen after seeing the curve is a tuned budget with extra steps.
#
# The rule is defined on the TRAINING LOSS and nothing else: `ndt1.train.loss_plateaued` cannot see
# a co-bps. Stopping at the epoch where the headline metric happens to peak is exactly the tuning
# D-22 and D-25 exist to prevent, and it is the failure this task was set up to avoid.
#
# Stop at the first epoch where |(L[i-1] - L[i]) / L[i-1]| < PLATEAU_REL_TOL held for each of the
# last PLATEAU_PATIENCE epochs, provided at least MIN_EPOCHS have run; otherwise stop at EPOCH_CAP
# and report that the curve had NOT converged.
#
#   PLATEAU_REL_TOL = 1e-3. A tenth of a percent per epoch. For scale, the 09-06b run's first-epoch
#     relative improvement was 3.9% and its last three were 0.071%, 0.125% and 0.143%, so this
#     tolerance sits just below where that truncated run stopped and the rule agrees it had not
#     converged (pinned in tests/test_plateau_stop.py). Twenty further epochs inside the band move
#     the loss by under 2%, against the 6% that run achieved in twelve.
#   PLATEAU_PATIENCE = 3. One quiet epoch cannot end a run that is still learning. Three is also
#     the window 09-06 used when it judged convergence by eye ("epochs 10 to 12 oscillating inside
#     0.0018"), so the criterion is continuous with the one this repository already applied.
#   MIN_EPOCHS = 12. The converged run is never SHORTER than the truncated run it replaces, so the
#     new number can never be "we stopped earlier and got a different answer".
#   EPOCH_CAP = 60. A compute bound, not a result-shaped choice: 09-06b measured 844 s for 12
#     pooled epochs (70 s/epoch) and the four LOSO folds together are 21,396 training windows to
#     the pooled 7,132, so a full run costs about 281 s per epoch. Sixty epochs is about 4.7 h of
#     CPU worst case, which is the largest single run this artifact can afford. Hitting it is a
#     reportable outcome, not a silent one: the run records stop_reason="epoch_cap" and the
#     evidence says the curve had not converged.
#
# Every run in the rotation gets the SAME rule and stops independently under it. A fold that
# plateaus sooner stops sooner; the per-fold stopping epoch is committed in the metrics JSON.
EPOCH_CAP: int = 60
PLATEAU_REL_TOL: float = 1e-3
PLATEAU_PATIENCE: int = 3
MIN_EPOCHS: int = 12


_PENDING = "PENDING"
_REPO_ROOT = Path(__file__).resolve().parents[2]
_PHASE_DIR = (
    _REPO_ROOT / ".planning" / "phases" / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
)
_DEFAULT_OUT_JSON = _PHASE_DIR / "09-decoder-metrics.json"
_DEFAULT_CHECKPOINT_DIR = _REPO_ROOT / "Decoder" / "checkpoints"
_POOLED_CHECKPOINT_NAME = "ndt1_real_pooled.pt"
#: A wiring check must never be able to clobber the checkpoint whose sha256 is published in
#: 09-decoder-metrics.json, so --smoke writes somewhere else.
_SMOKE_CHECKPOINT_NAME = "ndt1_real_pooled.smoke.pt"
#: D-03's floor: fewer than three loadable sessions means the dataset is not what this phase says
#: it is, and the substitution branch fires rather than training on a reshaped pool.
MIN_SESSIONS: int = 3
#: Where the numbers measured under the pre-09-06b objective live. Preserved, never deleted, and
#: carried across re-runs, because documents outside this repository may already quote them.
_SUPERSEDED_KEY: str = "superseded_visible_input_objective"
#: Every superseded record shares this prefix, and `_carry_superseded` carries all of them across
#: a re-run. The chain has to stay readable end to end: defective objective -> corrected but
#: truncated at 12 epochs -> corrected and trained to the pre-registered convergence rule.
_SUPERSEDED_PREFIX: str = "superseded_"
#: The blocks that describe one measurement, and therefore the ones a supersession snapshots.
_MEASURED_KEYS: tuple[str, ...] = (
    "checkpoint",
    "co_bps",
    "config",
    "env",
    "losses",
    "loso",
    "loso_summary",
    "wall_clock_s",
)

# --- D-22 margin re-derivation ----------------------------------------------------------------
# Phase 4 committed `CO_BPS_MARGIN = 0.05` against an observed synthetic co-bps of 0.3804
# (04-training-evidence.md), i.e. a margin at 13.1% of the observed value: far enough above the 0.0
# null to mean something, far enough below the observation that run-to-run variation cannot flake
# the gate. `--derive-margin` applies that SAME fraction to the observed REAL value, so the margin
# is computed from the measurement by code rather than chosen by a human who has seen the number.
# The RULE is unchanged across the 09-06b objective correction; only the observation it reads
# moved. Re-deriving under a rule chosen after seeing the corrected number would be the exact
# tuning D-22 exists to prevent.
PHASE4_OBSERVED_CO_BPS: float = 0.3804
PHASE4_MARGIN: float = 0.05
MARGIN_SIGNIFICANT_DIGITS: int = 2


def _log(message: str) -> None:
    """Timestamped, immediately-flushed progress line (this run is long and gets tee'd to a log)."""
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def _sha256_of(path: Path) -> str:
    """Streamed SHA-256 of a file; never loads the whole payload into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _package_version(name: str) -> str:
    """Installed distribution version, or ``"not installed"``; avoids importing heavy packages."""
    try:
        return version(name)
    except PackageNotFoundError:
        return "not installed"


def _json_float(value: float) -> float | None:
    """``None`` for a non-finite value, so the JSON stays parseable by strict readers.

    ``json.dumps`` emits a bare ``NaN`` token by default, which Python accepts and `jq` and every
    other strict JSON parser rejects. A diverged fold must be recorded, not suppressed, and
    ``null`` is the representation that survives the gate scripts that read this file.
    """
    return float(value) if np.isfinite(value) else None


def _windows_bc1s(binned: np.ndarray, *, seq_len: int = SEQ_LEN) -> Tensor:
    """Chunk a ``(bins, 96)`` matrix into whole windows and return them as BC1S ``(N, C, 1, S)``.

    Windowing is done PER SESSION and never across a concatenation of sessions: a window straddling
    two recordings weeks apart is a fabricated neural sequence, and this phase exists to remove
    fabricated inputs, not to add three of them.
    """
    dataset = IndySpikeDataset(binned, seq_len=seq_len)
    if len(dataset) == 0:
        raise ValueError(
            f"{binned.shape[0]} bins is fewer than one seq_len={seq_len} window; the session "
            f"should have been excluded before reaching here"
        )
    stacked = torch.stack([dataset[i] for i in range(len(dataset))])  # (N, S, C)
    return reshape_to_bc1s(stacked)


def _forward_in_chunks(model: nn.Module, targets: Tensor, *, chunk: int = EVAL_CHUNK) -> Tensor:
    """Run ``model`` over ``targets`` in fixed-size window chunks under ``no_grad``."""
    model.eval()
    outputs: list[Tensor] = []
    with torch.no_grad():
        for start in range(0, targets.shape[0], chunk):
            outputs.append(model(targets[start : start + chunk]))
    return torch.cat(outputs, dim=0)


def _score(
    model: nn.Module, eval_bc1s: Tensor, nulls: dict[str, Tensor], *, mask_ratio: float
) -> dict[str, float]:
    """co-bps of ``model`` on ``eval_bc1s`` against every named null, on ONE shared seeded mask.

    One forward pass and one mask serve every null, so the values differ only in the baseline they
    are scored against -- which is the whole point of reporting more than one.

    The mask does BOTH of its jobs here (Plan 09-06b): it selects the positions co-bps is scored
    on, and `hide_scored_positions` removes those positions from the encoder input, exactly as
    `ndt1.train.masked_forward` does during training. Scoring with the input visible while training
    with it hidden would report a number measured under a different objective than the one that
    produced the weights.
    """
    generator = torch.Generator()
    generator.manual_seed(SEED)
    mask = random_mask(eval_bc1s.shape, mask_ratio, generator=generator)
    rates = _forward_in_chunks(model, hide_scored_positions(eval_bc1s, mask))
    return {
        name: co_bps(rates, eval_bc1s, mask, null_rate, log_input=LOG_INPUT)
        for name, null_rate in nulls.items()
    }


def _train_pool(
    train_windows: list[Tensor], *, epochs: int, plateau_rel_tol: float | None
) -> tuple[nn.Module, dict[str, object]]:
    """Train a fresh NDT1ANE on the concatenated per-session train windows (BC1S list -> (B,S,C)).

    ``train_ndt1`` consumes ``(B, S, C)`` windows, so the BC1S tensors are inverted back here.
    Seeding mirrors ``tests/test_heldout_cobps.py`` exactly: ``torch.manual_seed(SEED)`` before the
    model is constructed (init order), and ``train_ndt1`` re-seeds the global RNG and its own mask
    generator (T-04-04-03).

    ``epochs`` is the HARD CAP. Where the run actually stops is decided by the pre-registered
    convergence rule above, on the training loss alone; the pooled run and every LOSO fold get the
    same rule and stop independently under it.
    """
    # (N, C, 1, S) -> (N, S, C)
    pooled = torch.cat([w.squeeze(2).permute(0, 2, 1).contiguous() for w in train_windows], dim=0)
    loader = DataLoader(TensorDataset(pooled), batch_size=BATCH_SIZE, shuffle=False)
    torch.manual_seed(SEED)
    model = NDT1ANE(seq_len=SEQ_LEN)
    steps = (pooled.shape[0] + BATCH_SIZE - 1) // BATCH_SIZE * epochs
    _log(f"  training on {pooled.shape[0]} windows, cap {epochs} epochs, <={steps} steps")
    started = time.monotonic()
    history = train_ndt1(
        model,
        loader,
        epochs=epochs,
        lr=LR,
        log_input=LOG_INPUT,
        device=DEVICE,
        seed=SEED,
        weight_decay=WEIGHT_DECAY,
        plateau_rel_tol=plateau_rel_tol,
        plateau_patience=PLATEAU_PATIENCE,
        min_epochs=MIN_EPOCHS,
    )
    losses = cast(list[float], history["losses"])
    curve = " ".join(f"{x:.4f}" for x in losses)
    _log(
        f"  done in {time.monotonic() - started:.0f}s after {history['epochs_run']} epochs "
        f"(stop_reason={history['stop_reason']}); per-epoch loss: {curve}"
    )
    return model, history


def _read_manifest(path: Path) -> dict[str, dict[str, object]]:
    """Return ``{session_id: manifest entry}``.

    Raises:
        OSError: the manifest cannot be read.
        ValueError: the manifest is not valid JSON or declares no sessions.
    """
    manifest = json.loads(path.read_text(encoding="utf-8"))
    entries = manifest.get("sessions", [])
    if not entries:
        raise ValueError(f"manifest {path} declares no sessions")
    return {str(entry["id"]): entry for entry in entries if "id" in entry}


def _session_provenance(
    sessions: list[SessionLoad], manifest_index: dict[str, dict[str, object]]
) -> list[dict[str, object]]:
    """Copy each session's committed sha256 out of the manifest (T-09-06-02).

    The checksum is COPIED, never recomputed: the claim being made is that the published number came
    from the bytes the manifest pins, and recomputing here would only restate what is already on
    disk. `download_indy.py` owns the disk-to-pin verification.

    Raises:
        ValueError: a session is absent from the manifest, or its sha256 is still ``"PENDING"``.
    """
    provenance: list[dict[str, object]] = []
    for session in sessions:
        entry = manifest_index.get(session.session_id)
        if entry is None:
            raise ValueError(
                f"session {session.session_id} is on disk but absent from the manifest; it cannot "
                f"be provenance-pinned and must not enter the training pool (T-09-06-07)"
            )
        sha256 = str(entry.get("sha256", ""))
        if sha256 == _PENDING or not sha256:
            raise ValueError(
                f"session {session.session_id} has sha256={sha256!r} in the manifest; run "
                f"scripts/download_indy.py to fill it before publishing any number from it"
            )
        provenance.append(
            {
                "id": session.session_id,
                "sha256": sha256,
                "bins": int(session.stats["num_bins"]),
            }
        )
    return provenance


def _environment() -> dict[str, str]:
    """Interpreter, wheel versions and machine identity, for the reproducibility record."""
    return {
        "python": platform.python_version(),
        "torch": torch.__version__,
        "numpy": np.__version__,
        "h5py": h5py.__version__,
        "coremltools": _package_version("coremltools"),
        "platform": platform.platform(),
        "machine": platform.machine(),
    }


def _run_loso(
    loaded: list[SessionLoad],
    train_bc1s: dict[str, Tensor],
    *,
    epochs: int,
    mask_ratio: float,
    plateau_rel_tol: float | None,
) -> list[dict[str, object]]:
    """Full leave-one-session-out rotation (D-13).

    Each fold retrains from scratch on the in-fold sessions' TRAIN halves with the identical config,
    then evaluates on the held-out session's FULL binned matrix -- not just its test tail -- because
    the held-out session had zero exposure, so every one of its bins is legitimately held out.
    """
    by_id = {s.session_id: s for s in loaded}
    folds: list[dict[str, object]] = []
    for fold in loso_folds([s.session_id for s in loaded]):
        held_out = str(fold["held_out"])
        train_ids = [str(sid) for sid in cast(list[str], fold["train_ids"])]
        _log(f"LOSO fold: hold out {held_out}, train on {', '.join(train_ids)}")
        fold_windows = [train_bc1s[sid] for sid in train_ids]
        model, history = _train_pool(
            fold_windows, epochs=epochs, plateau_rel_tol=plateau_rel_tol
        )
        losses = cast(list[float], history["losses"])

        eval_bc1s = _windows_bc1s(by_id[held_out].binned)
        fold_train_mean = mean_firing_rate(torch.cat(fold_windows, dim=0))
        scores = _score(
            model,
            eval_bc1s,
            {"train_null": fold_train_mean, "test_mean_null": mean_firing_rate(eval_bc1s)},
            mask_ratio=mask_ratio,
        )
        _log(
            f"  {held_out}: train_null co-bps {scores['train_null']:.4f}, "
            f"test_mean_null {scores['test_mean_null']:.4f}"
        )
        diverged = not all(
            np.isfinite(v) for v in (*losses, scores["train_null"], scores["test_mean_null"])
        )
        if diverged:
            _log(
                f"  WARNING: fold {held_out} DIVERGED. The loss curve is committed so the epoch it "
                f"happened at is auditable; the fold contributes no value to the summary."
            )
        folds.append(
            {
                "held_out_session": held_out,
                "train_sessions": train_ids,
                "train_null": _json_float(scores["train_null"]),
                "test_mean_null": _json_float(scores["test_mean_null"]),
                "train_windows": int(sum(w.shape[0] for w in fold_windows)),
                "eval_windows": int(eval_bc1s.shape[0]),
                "losses": [_json_float(x) for x in losses],
                "final_loss": _json_float(losses[-1]),
                "epochs_run": int(cast(int, history["epochs_run"])),
                "stop_reason": str(history["stop_reason"]),
                "diverged": diverged,
            }
        )
    return folds


def _visibility_pair(
    model: nn.Module, eval_bc1s: Tensor, nulls: dict[str, Tensor], *, mask_ratio: float
) -> dict[str, float]:
    """Score one eval set twice on the SAME seeded mask: input hidden, then input visible.

    The two labels swapped roles when Plan 09-06b corrected the objective. ``hidden_*`` is now the
    published path: it is what `_score` computes and what the model was trained under, so it
    doubles as a determinism check (T-09-06-01). ``visible_*`` is the probe -- it leaks the scored
    counts back into the encoder, which is what the old objective did on every forward pass.

    Under the OLD objective the gap measured how much self-reconstruction was inflating the
    published number. Under the corrected one it measures something different and weaker: how a
    model trained on hidden inputs responds to an input distribution it never saw. ``visible_*``
    is out of distribution here and is not a corrected, better, or alternative result.
    """
    generator = torch.Generator()
    generator.manual_seed(SEED)
    mask = random_mask(eval_bc1s.shape, mask_ratio, generator=generator)
    hidden_input = hide_scored_positions(eval_bc1s, mask)
    rates_visible = _forward_in_chunks(model, eval_bc1s)
    rates_hidden = _forward_in_chunks(model, hidden_input)
    scores: dict[str, float] = {}
    for name, null_rate in nulls.items():
        scores[f"visible_{name}"] = co_bps(
            rates_visible, eval_bc1s, mask, null_rate, log_input=LOG_INPUT
        )
        scores[f"hidden_{name}"] = co_bps(
            rates_hidden, eval_bc1s, mask, null_rate, log_input=LOG_INPUT
        )
    return scores


def _round_significant(value: float, digits: int = MARGIN_SIGNIFICANT_DIGITS) -> float:
    """Round to `digits` significant figures, so the committed margin is not spuriously precise."""
    if value == 0.0:
        return 0.0
    exponent = math.floor(math.log10(abs(value)))
    return round(value, -(exponent - digits + 1))


def _run_derive_margin(args: argparse.Namespace) -> int:
    """Compute the D-22 margin from the observed value in the metrics JSON and write it back.

    The margin FOLLOWS the observation; it is never chosen first. This mode reads the pooled
    `train_null` that the training pass already committed, multiplies it by the Phase-4 fraction,
    and writes the result plus a generated rationale. Nothing here can see, or move toward, a
    threshold: the only input is a number that is already on disk.

    A non-positive observation yields a margin of exactly 0.0 and a rationale saying so -- the
    honest gate for that outcome under D-25 asserts only that the model is not WORSE than the null.
    """
    out_json = args.out_json if args.out_json is not None else _DEFAULT_OUT_JSON
    if not out_json.is_file():
        print(f"error: {out_json} does not exist; run the training pass first", file=sys.stderr)
        return 1
    payload = json.loads(out_json.read_text(encoding="utf-8"))
    observed = payload["co_bps"]["pooled"]["train_null"]
    if observed is None:
        print(
            f"error: {out_json} has a null pooled train_null; the run did not produce a value to "
            f"derive a margin from",
            file=sys.stderr,
        )
        return 1
    fraction = PHASE4_MARGIN / PHASE4_OBSERVED_CO_BPS
    if observed <= 0.0:
        margin = 0.0
        rationale = (
            f"Observed pooled held-out co-bps on real primate M1 spikes is {observed:.4f} "
            f"bits/spike against the train-split mean-rate null, which is at or below the null. "
            f"The margin is therefore 0.0: the assertion now proves only that the model is not "
            f"WORSE than the null, which is the honest gate for this outcome (D-25). It is "
            f"deliberately not inflated to look like a pass."
        )
    else:
        margin = _round_significant(observed * fraction)
        # The rationale states what the derivation did and what the gate therefore asserts. It
        # deliberately does NOT claim the margin is comfortably clear of the null or robust to
        # run-to-run variation: that is true only when the observation is comfortably positive,
        # and asserting it unconditionally would have the artifact vouch for a gate the number
        # does not support. Whether the margin is large enough to mean anything is left to the
        # reader, with the observation it came from printed beside it.
        rationale = (
            f"Observed pooled held-out co-bps on real primate M1 spikes is {observed:.4f} "
            f"bits/spike against the train-split mean-rate null. The margin {margin} is "
            f"{100.0 * fraction:.1f}% of it: the fraction Phase 4 used when it set "
            f"{PHASE4_MARGIN} against an observed {PHASE4_OBSERVED_CO_BPS}, applied unchanged so "
            f"that the observation is the only input to this derivation. Phase 4's "
            f"{PHASE4_MARGIN} was calibrated on a purpose-built learnable synthetic sinusoid and "
            f"does not transfer to real spikes. What the gate asserts is exactly 'better than the "
            f"constant per-channel mean-rate null by more than {margin} bits/spike' and nothing "
            f"more; whether that is a meaningful demonstration of non-trivial reconstruction "
            f"depends on the size of the observation it was derived from, which is recorded "
            f"beside it at co_bps.pooled.train_null."
        )
    payload["co_bps"]["margin"] = margin
    payload["co_bps"]["margin_rationale"] = rationale
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"observed pooled train_null co-bps = {observed:.10f}")
    _log(f"derived CO_BPS_MARGIN = {margin} ({100.0 * fraction:.4f}% of the observation)")
    _log(f"wrote co_bps.margin and co_bps.margin_rationale into {out_json}")
    return 0


def _run_diagnostic(args: argparse.Namespace, loaded: list[SessionLoad]) -> int:
    """Re-score the committed checkpoint with and without input visibility; merge into the JSON.

    Trains nothing. Loads the pooled checkpoint through `ndt1.train.load_checkpoint`, which uses
    ``torch.load(..., weights_only=True)``, so a tampered checkpoint cannot execute code
    (T-04-04-01).
    """
    out_json = args.out_json if args.out_json is not None else _DEFAULT_OUT_JSON
    if not out_json.is_file():
        print(
            f"error: {out_json} does not exist; run the training pass before the diagnostic",
            file=sys.stderr,
        )
        return 1
    checkpoint_path = Path(args.checkpoint_dir) / _POOLED_CHECKPOINT_NAME
    model = NDT1ANE(seq_len=SEQ_LEN)
    try:
        load_checkpoint(model, checkpoint_path)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    mask_ratio = float(model.mask_ratio)
    _log(f"loaded {checkpoint_path} (weights_only=True)")

    splits = pooled_splits(loaded, test_frac=TEST_FRAC)
    train_bc1s = {sid: _windows_bc1s(tr) for sid, tr, _ in splits}
    test_bc1s = {sid: _windows_bc1s(te) for sid, _, te in splits}
    ordered_ids = [s.session_id for s in loaded]
    pooled_train_null = mean_firing_rate(torch.cat([train_bc1s[i] for i in ordered_ids], dim=0))
    pooled_test = torch.cat([test_bc1s[i] for i in ordered_ids], dim=0)

    per_session: dict[str, dict[str, float]] = {}
    for session_id in ordered_ids:
        per_session[session_id] = _visibility_pair(
            model,
            test_bc1s[session_id],
            {
                "train_null": pooled_train_null,
                "test_mean_null": mean_firing_rate(test_bc1s[session_id]),
            },
            mask_ratio=mask_ratio,
        )
        _log(f"{session_id}: {per_session[session_id]}")
    pooled = _visibility_pair(
        model,
        pooled_test,
        {"train_null": pooled_train_null, "test_mean_null": mean_firing_rate(pooled_test)},
        mask_ratio=mask_ratio,
    )
    _log(f"pooled: {pooled}")

    payload = json.loads(out_json.read_text(encoding="utf-8"))
    payload["co_bps"]["input_visibility_diagnostic"] = {
        "note": (
            "Plan 09-06b corrected the objective: train_ndt1 and every scoring path now hide the "
            "scored positions from the encoder, so hidden_* is the published number and "
            "reproduces co_bps.per_session / co_bps.pooled on the same seeded mask. visible_* "
            "leaks the scored counts back into the encoder, which is what the superseded "
            "objective did on every forward pass. visible_* is an out-of-distribution probe for a "
            "model trained on hidden inputs; it is not a corrected, better or alternative result "
            "and must not be quoted as one."
        ),
        "checkpoint_sha256": _sha256_of(checkpoint_path),
        "pooled": pooled,
        "per_session": per_session,
    }
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"merged the input-visibility diagnostic into {out_json}")
    return 0


def _repo_relative(path: Path) -> str:
    """``path`` relative to the repository root when it is inside it, else its absolute path.

    ``Path.relative_to`` raises on a RELATIVE ``--checkpoint-dir`` (it compares the literal string
    against an absolute root), which used to abort the run at the JSON write -- after the training
    was already done and its only record was the log. Resolving first makes the documented
    `--checkpoint-dir Decoder/checkpoints/repro` invocation work, and a directory genuinely outside
    the repository records an absolute path rather than losing the run.
    """
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(_REPO_ROOT))
    except ValueError:
        return str(resolved)


def _carry_superseded(out_json: Path) -> dict[str, dict[str, object]]:
    """Return EVERY ``superseded_*`` record already in ``out_json``.

    There is more than one now, and there will be more later: a supersession chain that loses its
    middle link is not a record of what happened. Carrying by prefix rather than by name means a
    future correction only has to write its own block, not remember to add it here.

    Raises:
        ValueError: the existing file is not valid JSON, which would silently drop the records.
    """
    if not out_json.is_file():
        return {}
    existing = json.loads(out_json.read_text(encoding="utf-8"))
    return {
        key: value
        for key, value in existing.items()
        if key.startswith(_SUPERSEDED_PREFIX) and isinstance(value, dict)
    }


def _run_supersede_current(args: argparse.Namespace) -> int:
    """Snapshot the CURRENT measured blocks under a new ``superseded_*`` key, then exit.

    Trains nothing and measures nothing. It moves a copy of what is currently published into the
    supersession chain BEFORE a re-run overwrites it, so the correction is a labeling operation
    performed by code rather than a block a human retypes from a summary. The top-level blocks are
    left in place; the next training run replaces them.
    """
    out_json = args.out_json if args.out_json is not None else _DEFAULT_OUT_JSON
    if not out_json.is_file():
        print(f"error: {out_json} does not exist; nothing to supersede", file=sys.stderr)
        return 1
    key = str(args.supersede_current)
    if not key.startswith(_SUPERSEDED_PREFIX):
        print(f"error: --supersede-current key must start with {_SUPERSEDED_PREFIX!r}",
              file=sys.stderr)
        return 1
    payload = json.loads(out_json.read_text(encoding="utf-8"))
    if key in payload:
        print(f"error: {key} already exists in {out_json}; refusing to overwrite a record",
              file=sys.stderr)
        return 1
    if args.supersede_note is None:
        print("error: --supersede-current requires --supersede-note", file=sys.stderr)
        return 1
    snapshot: dict[str, object] = {k: payload[k] for k in _MEASURED_KEYS if k in payload}
    snapshot["note"] = str(args.supersede_note)
    snapshot["superseded_by"] = str(args.supersede_by or "a later plan, same file, top level")
    payload[key] = snapshot
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"snapshotted {len(snapshot) - 2} measured blocks into {key} in {out_json}")
    return 0


def _summarize(values: list[float]) -> dict[str, object]:
    """Mean, sample std, min and max over the FINITE folds (D-13 requires spread, not a mean alone).

    A diverged fold has no value to average, and letting one ``nan`` propagate would turn the whole
    summary into ``nan`` and hide the three folds that did produce a number. The counts are reported
    beside the statistics so the reader can see how much of the rotation the mean rests on.
    """
    arr = np.asarray(values, dtype=np.float64)
    finite = arr[np.isfinite(arr)]
    counts = {
        "folds": int(arr.size),
        "finite_folds": int(finite.size),
        "diverged_folds": int(arr.size - finite.size),
    }
    if finite.size == 0:
        return {"mean": None, "std": None, "min": None, "max": None, **counts}
    return {
        "mean": float(finite.mean()),
        "std": float(finite.std(ddof=1)) if finite.size > 1 else 0.0,
        "min": float(finite.min()),
        "max": float(finite.max()),
        **counts,
    }


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Retrain NDT1 on the real Indy M1 sessions and write the metrics JSON."
    )
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--out-json", type=Path, default=None)
    parser.add_argument("--checkpoint-dir", type=Path, default=_DEFAULT_CHECKPOINT_DIR)
    parser.add_argument("--skip-loso", action="store_true")
    parser.add_argument(
        "--derive-margin",
        action="store_true",
        help=(
            "train nothing: compute co_bps.margin from the OBSERVED pooled value already in "
            "--out-json, at the same fraction Phase 4 used, and write it back with its rationale"
        ),
    )
    parser.add_argument(
        "--diagnostic",
        action="store_true",
        help=(
            "train nothing: load the committed checkpoint and re-score it with the scored "
            "positions zeroed in the encoder input, merging the result into --out-json"
        ),
    )
    parser.add_argument(
        "--supersede-current",
        default=None,
        metavar="superseded_KEY",
        help=(
            "train nothing: snapshot the currently published measured blocks in --out-json under "
            "the given superseded_* key so a re-run cannot lose them"
        ),
    )
    parser.add_argument("--supersede-note", default=None)
    parser.add_argument("--supersede-by", default=None)
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="1 epoch on the two smallest sessions - a wiring check, NEVER a committed number",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Load, split, train, score, rotate, and write the metrics JSON."""
    args = _parse_args(argv)
    started_at = time.time()

    if args.derive_margin:
        return _run_derive_margin(args)

    if args.supersede_current is not None:
        return _run_supersede_current(args)

    try:
        manifest_index = _read_manifest(args.manifest)
    except OSError as exc:
        print(f"error: cannot read manifest {args.manifest}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:  # json.JSONDecodeError is a ValueError subclass
        print(f"error: {exc}", file=sys.stderr)
        return 1

    loaded, excluded = available_sessions(args.data_dir)
    for exclusion in excluded:
        _log(f"excluded {exclusion.session_id}: {exclusion.reason}")
    if len(loaded) < MIN_SESSIONS:
        print(
            f"error: only {len(loaded)} session(s) loaded from {args.data_dir}; D-03 requires at "
            f"least {MIN_SESSIONS}. Materialize the dataset with scripts/download_indy.py.",
            file=sys.stderr,
        )
        return 1

    if args.diagnostic:
        return _run_diagnostic(args, loaded)

    # A wiring check runs one epoch and is never subject to the convergence rule; the real run
    # gets the cap and the pre-registered rule that decides where inside it to stop.
    epochs = 1 if args.smoke else EPOCH_CAP
    plateau_rel_tol = None if args.smoke else PLATEAU_REL_TOL
    if args.smoke:
        loaded = sorted(loaded, key=lambda s: int(s.stats["num_bins"]))[:2]
        _log(
            "SMOKE MODE: 1 epoch on "
            f"{', '.join(s.session_id for s in loaded)}. This is a wiring check. The numbers it "
            "produces are NOT publishable and its JSON is marked data_source=real-smoke."
        )

    try:
        provenance = _session_provenance(loaded, manifest_index)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    # --- Split per session BEFORE any pooling (D-12) ------------------------------------------
    splits = pooled_splits(loaded, test_frac=TEST_FRAC)
    train_bc1s: dict[str, Tensor] = {}
    test_bc1s: dict[str, Tensor] = {}
    for session_id, train_half, test_half in splits:
        train_bc1s[session_id] = _windows_bc1s(train_half)
        test_bc1s[session_id] = _windows_bc1s(test_half)
        _log(
            f"{session_id}: {train_half.shape[0]} train bins "
            f"({train_bc1s[session_id].shape[0]} windows), {test_half.shape[0]} test bins "
            f"({test_bc1s[session_id].shape[0]} windows)"
        )

    for record in provenance:
        sid = str(record["id"])
        record["train_windows"] = int(train_bc1s[sid].shape[0])
        record["test_windows"] = int(test_bc1s[sid].shape[0])

    ordered_ids = [s.session_id for s in loaded]
    pooled_train = torch.cat([train_bc1s[sid] for sid in ordered_ids], dim=0)
    pooled_test = torch.cat([test_bc1s[sid] for sid in ordered_ids], dim=0)
    pooled_train_null = mean_firing_rate(pooled_train)

    # --- Pooled training (D-11, D-14) ----------------------------------------------------------
    _log(f"pooled training on {len(loaded)} sessions")
    model, history = _train_pool(
        [train_bc1s[sid] for sid in ordered_ids], epochs=epochs, plateau_rel_tol=plateau_rel_tol
    )
    losses = [float(x) for x in cast(list[float], history["losses"])]
    if not all(np.isfinite(x) for x in losses):
        _log("WARNING: the POOLED training loss went non-finite; the headline number is not usable")
    mask_ratio = float(model.mask_ratio)

    checkpoint_path = Path(args.checkpoint_dir) / (
        _SMOKE_CHECKPOINT_NAME if args.smoke else _POOLED_CHECKPOINT_NAME
    )
    save_checkpoint(model, checkpoint_path)
    param_count = int(sum(p.numel() for p in model.parameters()))
    _log(f"checkpoint saved to {checkpoint_path} ({param_count} params)")

    # --- Per-session held-out co-bps (RD-04a) --------------------------------------------------
    per_session: dict[str, dict[str, float]] = {}
    for session_id in ordered_ids:
        scores = _score(
            model,
            test_bc1s[session_id],
            {
                "train_null": pooled_train_null,
                "test_mean_null": mean_firing_rate(test_bc1s[session_id]),
                "session_train_null": mean_firing_rate(train_bc1s[session_id]),
            },
            mask_ratio=mask_ratio,
        )
        per_session[session_id] = scores
        _log(
            f"held-out {session_id}: train_null {scores['train_null']:.4f}, "
            f"session_train_null {scores['session_train_null']:.4f}, "
            f"test_mean_null {scores['test_mean_null']:.4f}"
        )

    pooled_scores = _score(
        model,
        pooled_test,
        {"train_null": pooled_train_null, "test_mean_null": mean_firing_rate(pooled_test)},
        mask_ratio=mask_ratio,
    )
    _log(
        f"pooled held-out: train_null {pooled_scores['train_null']:.4f}, "
        f"test_mean_null {pooled_scores['test_mean_null']:.4f}"
    )

    # --- LOSO rotation (RD-04b, D-13) ----------------------------------------------------------
    loso: list[dict[str, object]] = []
    loso_summary: dict[str, object] | None = None
    if args.skip_loso:
        _log("skipping the LOSO rotation (--skip-loso)")
    else:
        loso = _run_loso(
            loaded,
            train_bc1s,
            epochs=epochs,
            mask_ratio=mask_ratio,
            plateau_rel_tol=plateau_rel_tol,
        )
        # The flat mean/std/min/max/folds keys summarize the D-22 gate null, which is what the
        # published LOSO headline quotes; the drift-robust null's spread is nested beside it.
        loso_summary = {
            "null": "train_null",
            **_summarize([cast(float, f["train_null"]) for f in loso]),
            "test_mean_null": _summarize([cast(float, f["test_mean_null"]) for f in loso]),
        }

    payload = {
        "schema_version": 1,
        "data_source": "real-smoke" if args.smoke else "real",
        "smoke": bool(args.smoke),
        "manifest_path": "Decoder/manifests/indy_sessions.json",
        "sessions": provenance,
        "excluded_sessions": [
            {"id": e.session_id, "reason": e.reason} for e in excluded
        ],
        "checkpoint": {
            "path": _repo_relative(checkpoint_path),
            "sha256": _sha256_of(checkpoint_path),
            "param_count": param_count,
        },
        "config": {
            "epochs": epochs,
            "epoch_cap": epochs,
            "epochs_run": int(cast(int, history["epochs_run"])),
            "stop_reason": str(history["stop_reason"]),
            "plateau_rel_tol": plateau_rel_tol,
            "plateau_patience": PLATEAU_PATIENCE,
            "min_epochs": MIN_EPOCHS,
            "grad_clip_norm": DEFAULT_GRAD_CLIP_NORM,
            "lr": LR,
            "batch_size": BATCH_SIZE,
            "seq_len": SEQ_LEN,
            "seed": SEED,
            "mask_ratio": mask_ratio,
            "test_frac": TEST_FRAC,
            "weight_decay": WEIGHT_DECAY,
            "bin_ms": BIN_MS,
            "device": DEVICE,
            "log_input": LOG_INPUT,
        },
        "env": _environment(),
        "losses": [_json_float(x) for x in losses],
        "train_windows": int(pooled_train.shape[0]),
        "test_windows": int(pooled_test.shape[0]),
        "co_bps": {
            "pooled": {
                "train_null": _json_float(pooled_scores["train_null"]),
                "test_mean_null": _json_float(pooled_scores["test_mean_null"]),
            },
            "per_session": {
                sid: {k: _json_float(v) for k, v in scores.items()}
                for sid, scores in per_session.items()
            },
            # D-22: the margin is re-derived from the OBSERVED value AFTER measuring, never chosen
            # first. Left null here on purpose; the evidence step fills it with its rationale.
            "margin": None,
            "margin_rationale": None,
        },
        "loso": loso,
        "loso_summary": loso_summary,
        "wall_clock_s": round(time.time() - started_at, 1),
    }

    out_json = args.out_json
    if out_json is None:
        out_json = (
            Path(args.checkpoint_dir) / "smoke-metrics.json" if args.smoke else _DEFAULT_OUT_JSON
        )
    # The superseded record outlives every re-run. It is the only key carried forward from the
    # file being overwritten: a reader who finds 1.9116 quoted somewhere in the repository needs
    # to be able to look it up here and see why it must not be used, and that would be lost the
    # first time anyone re-ran this script if the block were merged in by hand once.
    payload.update(_carry_superseded(out_json))
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"wrote {out_json}")
    _log(
        "co_bps.margin is null by design (D-22): re-derive it from the observed value above and "
        "record it with its rationale in the metrics JSON and tests/test_heldout_cobps.py."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
