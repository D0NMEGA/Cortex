#!/usr/bin/env python3
"""Fit the shipped velocity readout on REAL `finger_pos` kinematics and score it held out (D-05).

Produces, in one run:

  1. **The full 0-160 ms lag sweep** (D-08), fit and scored on the TRAIN split only.
  2. **The full ridge-lambda sweep** at the locked lag, also TRAIN-only.
  3. **`Decoder/checkpoints/ndt1_real_with_velocity.pt`** -- the Plan 09-06 pooled encoder
     UNCHANGED plus a closed-form ridge readout, the checkpoint Plan 09-08 converts.
  4. **A `velocity` section in the metrics JSON**: both sweeps, and held-out R2 per axis, per
     session and pooled, against a constant TRAIN-split mean null (D-10).

What this replaces: `velocity_r2.json`'s 0.99985. `tests/test_convert_velocity_output.py:55`
generates labels as `last_bin @ w_true + 0.01 * noise` and then regresses those same rates onto
them. That confirms `load_ridge` reproduces `X @ W.T + b`; it is not a decode result.

--- The pre-registered rules, written before the run -----------------------------------------

**R1, the lag.** Sweep `LAG_BINS_SWEEP` (0-8 bins, 0-160 ms) at `lam = DEFAULT_LAMBDA`, fit on the
pooled TRAIN rows and scored in-sample there. Lock the argmax. The held-out tail is never touched
by the selection, and the whole nine-point curve is published. `nlb_tools/make_tensors.py` sets
`'lag': 140` ms for `mc_rtt` (bin 7) and M1 leads hand velocity by 120-180 ms
(PNAS 10.1073/pnas.2212227120), so an argmax outside 5-8 bins prints a warning: it is a signal that
the alignment or the sign is wrong, not a discovery. That warning is then ANSWERED rather than left
hanging. The same curve is computed over `LAG_DIAGNOSTIC_SWEEP`, the eight offsets on the negative
side of zero, purely as a diagnostic: a one-sided sweep pins its argmax at lag 0 both when the
labels are shifted late and when zero really is the optimum, and only the other side of zero tells
those apart. The diagnostic never participates in the selection, and the locked lag is the argmax
of `LAG_BINS_SWEEP` whatever the diagnostic says.

**R2, the lambda.** In-sample train R2 is monotone NON-INCREASING in lambda by construction, so it
cannot select a lambda -- it can only document sensitivity. The rule is therefore: publish the whole
`LAMBDA_GRID` curve, and lock `DEFAULT_LAMBDA = 1.0`, the value `ridge_fit` already defaults to and
which was fixed in Phase 5 long before any real number existed, UNLESS the curve's train-R2 spread
exceeds `LAMBDA_FLAT_TOL`, in which case lock the argmin of generalized cross-validation (GCV) --
09-RESEARCH section 7 option 1, closed-form on the train split with no extra split and no leak.
Either way the locked value is decided by a rule fixed before the numbers were seen.

**R3, the held-out R2.** Computed ONCE, at the locked lag and lambda. `SS_res` over TEST bins,
`SS_tot` against the TRAIN-split mean (`kinematics.heldout_r2`, which requires the null explicitly).
Per session the null is THAT session's own train mean, which is the harder null under within-session
drift; pooled, it is the pooled train mean. Nothing is clamped and nothing is re-rolled: D-25 says a
low honest number completes the phase, and a negative R2 means the readout is worse than a
constant-velocity null, which is then the finding.

**R5, the readout rotation (`--loso`).** A separate pass, merged into the velocity section a full
run has already written, mirroring `train_real.py --only-loso`. For each session: fit on the other
three sessions' TRAIN rows, **re-selecting the lag and the lambda on those three alone** by R1 and
R2, and score held-out R2 on the excluded session's own TEST tail against **its own train-split
mean**, the drift-robust null. The training-pool mean is reported beside it and is never the
headline, for the same reason Plan 09-06d refuses to headline its LOSO `train_null`. A fold that
fails to fit is recorded with its exception, never dropped. The encoder is the same pooled
checkpoint in every fold and was pretrained on all four sessions, so R5 isolates the READOUT's
transfer and is a strictly weaker claim than Plan 09-06d's encoder rotation. Nothing in R5 changes
the shipped checkpoint: the readout that ships is the globally fit one.

**R4, the forward-parity gate.** The fitted head is only accepted if the assembled
`NDT1ANEWithVelocity` reproduces `X @ W.T + b` to within `PARITY_TOL` cm/s on real held-out windows.
This is what proves the design matrix is exactly the tensor the shipped graph feeds its readout.

--- Three things this script does NOT do -----------------------------------------------------

**It does not exponentiate the encoder output.** `NDT1ANEWithVelocity.forward` is
`velocity_head(encoder(x))`: the 1x1 conv reads the encoder's RAW output. With `log_input=True`
that output is log-rates, so the readout the graph ships applies `W` to log-rates. Fitting `W` on
`exp(log_rates)` would produce weights the shipped graph never applies, and inserting an `exp` into
the graph to match would add an op type D-09 forbids. R4 above is the assertion that keeps this
honest: it fails loudly if the design matrix and the graph ever disagree.

**It does not mask the encoder input.** Training hides the scored positions
(`ndt1.loss.hide_scored_positions`) and co-bps is scored the same way, but the DEPLOYED model is fed
a real unmasked 32-bin window every 20 ms. The readout is therefore fit and scored under the
SERVING condition. This is deliberate and is the 05-RESEARCH Decision-1 no-train/serve-skew rule; it
also means these numbers are not comparable to the co-bps numbers in the same JSON, which are
measured under the masked objective.

**It does not train anything.** The encoder is loaded and frozen; the readout is one closed-form
`np.linalg.solve` through the existing `ridge_fit` / `load_ridge` rank-2 to rank-4 pre-hook, so the
traced graph stays exactly the one Phase 5 proved 226/226 ANE-eligible (D-09).

--- Row bookkeeping, which is where a silent defect would live -------------------------------

`VelocityHead.forward` reads `rates[..., -1:]`, so one design row is one 32-bin window and its bin
index is the window's LAST bin. The deployed cadence is one window per 20 ms bin, so the design
matrix is built at stride 1: row `j` is the window ending at bin `j + SEQ_LEN - 1`. That is exactly
the `(n_bins, num_channels)` layout `kinematics.apply_lag` documents, which is what lets "lag k"
mean "the window ending at bin `i` paired with the velocity at bin `i + k`".

Per session, with `k = len(chronological_split(binned)[0])`:

    train rows  end bins [SEQ_LEN-1, k-1]      <-> vel_bins[SEQ_LEN-1 : k]
    test rows   end bins [k+SEQ_LEN-1, N-1]    <-> vel_bins[k+SEQ_LEN-1 : N]

The test rows start a full window AFTER the split, so no held-out prediction reads a single bin the
encoder trained on. `apply_lag` is applied PER SESSION and only then concatenated: lagging a
concatenation would pair the tail of one recording with the head of another, weeks apart, which is
the fabricated-input failure this phase exists to remove.

Runtime: about 20 min of CPU for the roughly 285k stride-1 encoder forward passes, plus session
load. Long enough to run detached (`nohup ... &`); `--reuse-rates` skips the forward pass when the
cached design matrices still match the encoder and session hashes. CI never runs this (D-21).

Checkpoints and the rates cache are gitignored `Decoder/checkpoints/` artifacts; the encoder is
loaded through `ndt1.train.load_checkpoint`, i.e. `torch.load(..., weights_only=True)`
(T-04-04-01). No bare/blind `except`.

Usage:
    uv run --project Decoder python Decoder/scripts/fit_velocity_real.py --smoke
    uv run --project Decoder python Decoder/scripts/fit_velocity_real.py
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import sys
import time
from dataclasses import dataclass
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

import h5py
import numpy as np
import torch
from torch import Tensor

from ndt1.data import BIN_MS, chronological_split
from ndt1.kinematics import (
    LAG_BINS_SWEEP,
    apply_lag,
    bin_velocity,
    heldout_r2,
    planar_velocity_250hz,
)
from ndt1.model_ane import NDT1ANEWithVelocity
from ndt1.sessions import DEFAULT_DATA_DIR, SessionLoad, available_sessions
from ndt1.train import load_checkpoint, reshape_to_bc1s, save_checkpoint
from ndt1.velocity_head import VELOCITY_DIM, ridge_fit

# --- Config, inherited rather than chosen ------------------------------------------------------
# SEQ_LEN and TEST_FRAC must match Plan 09-06's run exactly: the positional encoding is sized for
# SEQ_LEN, and a different split would score the readout on bins the encoder trained on.
SEQ_LEN: int = 32
TEST_FRAC: float = 0.2
SEED: int = 0
#: Forward passes are chunked so a 168k-bin session does not materialize 168k windows at once.
#: A memory bound only; it changes no number.
EVAL_CHUNK: int = 512
#: Ridge strengths swept at the locked lag (R2 above). Six points over five orders of magnitude.
LAMBDA_GRID: tuple[float, ...] = (1e-2, 1e-1, 1.0, 1e1, 1e2, 1e3)
#: `ridge_fit`'s own default, fixed in Phase 5 before any real measurement existed.
DEFAULT_LAMBDA: float = 1.0
#: Train-R2 spread below which the lambda curve is called flat and DEFAULT_LAMBDA is locked.
LAMBDA_FLAT_TOL: float = 1e-3
#: The lag range corroborated by nlb_tools (140 ms for mc_rtt) and by the PNAS 120-180 ms
#: cross-correlation. An argmax outside it warns; it never changes the selection.
LAG_ANCHOR_BINS: tuple[int, int] = (5, 8)
#: Offsets on the OTHER side of zero, computed as an alignment DIAGNOSTIC and never as a
#: selection (R1 locks the argmax of `LAG_BINS_SWEEP` alone). D-08's sweep is one-sided, so a
#: shifted label would pin its argmax at lag 0 and look identical to a genuine zero-lag optimum.
#: Probing negative offsets is what tells the two apart: a true optimum is interior on both
#: sides, whereas labels that are systematically late keep improving as the offset goes negative.
LAG_DIAGNOSTIC_SWEEP: tuple[int, ...] = (-8, -7, -6, -5, -4, -3, -2, -1)
#: Max abs cm/s disagreement tolerated between the assembled graph and `X @ W.T + b` (R4). The
#: conv holds float32 weights against a float64 solve, so the floor is fp32 rounding, not zero.
PARITY_TOL: float = 1e-4
#: Windows the parity gate checks, taken from real HELD-OUT bins.
PARITY_WINDOWS: int = 64
#: D-03's floor, mirrored from train_real.py: fewer loadable sessions than this means the dataset
#: is not what this phase says it is.
MIN_SESSIONS: int = 3
#: `--smoke` truncates every session to this many bins. A wiring check, never a measurement.
SMOKE_BINS: int = 3000

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PHASE_DIR = (
    _REPO_ROOT / ".planning" / "phases" / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
)
_DEFAULT_METRICS = _PHASE_DIR / "09-decoder-metrics.json"
_DEFAULT_CHECKPOINT_DIR = _REPO_ROOT / "Decoder" / "checkpoints"
_DEFAULT_ENCODER = _DEFAULT_CHECKPOINT_DIR / "ndt1_real_pooled.pt"
_DEFAULT_OUT_CHECKPOINT = _DEFAULT_CHECKPOINT_DIR / "ndt1_real_with_velocity.pt"
#: A wiring check must never clobber the artifact whose sha256 the metrics JSON publishes.
_SMOKE_OUT_CHECKPOINT = _DEFAULT_CHECKPOINT_DIR / "ndt1_real_with_velocity.smoke.pt"
_SMOKE_METRICS = _DEFAULT_CHECKPOINT_DIR / "velocity-smoke-metrics.json"
_DEFAULT_RATES_CACHE = _DEFAULT_CHECKPOINT_DIR / "09-07-rates"

_SUPERSEDES = (
    "05-velocity-head-evidence.md velocity_r2.json R2 0.99985 (a self-consistency check on "
    "synthetic labels, not a decode result)"
)
_LABEL_SOURCE = "finger_pos rows 1-2 (planar), negation undone; NOT rows 0-1 (z, -x)"
_DERIVATION = "finite difference at 250 Hz then mean aggregate per 20 ms bin; no smoothing filter"
_NULL_DESCRIPTION = "constant TRAIN-split mean velocity per axis"


def _log(message: str) -> None:
    """Timestamped, immediately-flushed progress line; this run is tee'd to a log."""
    print(f"[{time.strftime('%H:%M:%S')}] {message}", flush=True)


def _sha256_of(path: Path) -> str:
    """Streamed SHA-256 of a file; never loads the whole payload into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _package_version(name: str) -> str:
    """Installed distribution version, or ``"not installed"``."""
    try:
        return version(name)
    except PackageNotFoundError:
        return "not installed"


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


def _repo_relative(path: Path) -> str:
    """``path`` relative to the repository root when inside it, else its absolute path."""
    resolved = path.resolve()
    try:
        return str(resolved.relative_to(_REPO_ROOT))
    except ValueError:
        return str(resolved)


@dataclass(frozen=True)
class SessionDesign:
    """One session's design matrix and labels, already split and already bin-aligned.

    `train_rates[j]` is the encoder's last-bin output for the window ending at bin
    `j + SEQ_LEN - 1`, and `train_vel[j]` is the velocity at that same bin, so the pair is exactly
    what `kinematics.apply_lag` documents. The test pair starts a full window after the split, so
    no held-out row reads a bin the encoder trained on.
    """

    session_id: str
    num_bins: int
    split_bin: int
    train_rates: np.ndarray  # (k - SEQ_LEN + 1, 96)
    train_vel: np.ndarray  # (k - SEQ_LEN + 1, 2)
    test_rates: np.ndarray  # (N - k - SEQ_LEN + 1, 96)
    test_vel: np.ndarray  # (N - k - SEQ_LEN + 1, 2)


@dataclass(frozen=True)
class RidgeFit:
    """One closed-form ridge solution on the pooled TRAIN rows, with its in-sample score.

    `train_r2` is a SELECTION criterion, never a result: it is scored on the same rows the fit
    used, against those rows' own mean. The reportable number is `heldout_r2` on the tail.
    """

    lam: float
    weight: np.ndarray  # (2, 96)
    bias: np.ndarray  # (2,)
    train_r2: float
    ss_res: float
    rows: int


def _sliding_windows_bc1s(binned: np.ndarray, start: int, stop: int) -> Tensor:
    """Rows `start:stop` of the stride-1 window stack, as BC1S ``(b, 96, 1, SEQ_LEN)``.

    `sliding_window_view` yields `(n_windows, C, S)` as a VIEW, so only the requested chunk is ever
    copied. Row `j` is the window covering bins `[j, j + SEQ_LEN)`, i.e. the window ENDING at bin
    `j + SEQ_LEN - 1`.
    """
    view = np.lib.stride_tricks.sliding_window_view(binned, SEQ_LEN, axis=0)
    chunk = np.ascontiguousarray(view[start:stop])  # (b, C, S)
    return torch.from_numpy(chunk).unsqueeze(2)


def _assert_bc1s_layout(binned: np.ndarray) -> None:
    """Prove the fast `(b, C, S) -> (b, C, 1, S)` path equals `reshape_to_bc1s`'s `(b, S, C)` one.

    The whole design matrix rests on this axis order. A transposed window would still satisfy every
    shape assertion downstream and would quietly fit the readout on scrambled channels, so the two
    constructions are compared directly on real bins rather than reasoned about.
    """
    rows = min(8, binned.shape[0] - SEQ_LEN + 1)
    fast = _sliding_windows_bc1s(binned, 0, rows)
    view = np.lib.stride_tricks.sliding_window_view(binned, SEQ_LEN, axis=0)
    as_bsc = np.ascontiguousarray(view[:rows].transpose(0, 2, 1))  # (b, S, C)
    if not torch.equal(fast, reshape_to_bc1s(torch.from_numpy(as_bsc))):
        raise ValueError(
            "the stride-1 BC1S window construction disagrees with ndt1.train.reshape_to_bc1s; "
            "the channel and sequence axes are transposed somewhere and the readout would be fit "
            "on scrambled channels"
        )


def _encoder_last_bin(model: NDT1ANEWithVelocity, binned: np.ndarray) -> np.ndarray:
    """Encoder output at the LAST bin of every stride-1 window: `(n_bins - SEQ_LEN + 1, 96)`.

    This is the exact tensor `VelocityHead.forward` slices with `rates[..., -1:]`, so it is the
    design matrix the shipped graph's readout consumes. It is NOT exponentiated, and the input is
    the raw unmasked counts: see the module docstring.
    """
    _assert_bc1s_layout(binned)
    total = binned.shape[0] - SEQ_LEN + 1
    out = np.empty((total, binned.shape[1]), dtype=np.float32)
    model.eval()
    with torch.no_grad():
        for start in range(0, total, EVAL_CHUNK):
            stop = min(start + EVAL_CHUNK, total)
            rates = model.encoder(_sliding_windows_bc1s(binned, start, stop))
            out[start:stop] = rates[..., -1].squeeze(-1).numpy()
    return out.astype(np.float64)


def _velocity_bins(session: SessionLoad, num_bins: int) -> np.ndarray:
    """20 ms-binned `(vx, vy)` for one session, asserted row-aligned with its spike matrix.

    `session.planar_cm` already comes from `finger_pos` rows 1-2 with the negation undone
    (Plan 09-02 / C-02), so nothing is re-indexed or re-negated here.
    """
    vel_250 = planar_velocity_250hz(session.planar_cm, session.t)
    vel = bin_velocity(
        vel_250, session.t, t_start=session.t_start, t_end=session.t_end, bin_ms=BIN_MS
    )
    if vel.shape[0] != num_bins:
        raise ValueError(
            f"session {session.session_id}: bin_velocity produced {vel.shape[0]} bins but "
            f"bin_spikes produced {num_bins}; the two binning paths have diverged and every "
            f"label would be shifted"
        )
    return vel


def _split_design(
    session_id: str, binned: np.ndarray, rates: np.ndarray, vel: np.ndarray
) -> SessionDesign:
    """Cut the bin-aligned rates and labels into the chronological train and test blocks.

    The split point comes from `chronological_split` itself rather than from a restatement of its
    arithmetic, so the readout is fit and scored on exactly the blocks the encoder was trained and
    evaluated on.
    """
    num_bins = binned.shape[0]
    split_bin = int(chronological_split(binned, test_frac=TEST_FRAC)[0].shape[0])
    offset = SEQ_LEN - 1
    train_rows = split_bin - offset
    test_rows = num_bins - split_bin - offset
    longest_lag = max(LAG_BINS_SWEEP)
    if train_rows <= longest_lag or test_rows <= longest_lag:
        raise ValueError(
            f"session {session_id} yields {train_rows} train and {test_rows} test design rows, "
            f"which cannot absorb the {longest_lag}-bin lag sweep"
        )
    return SessionDesign(
        session_id=session_id,
        num_bins=num_bins,
        split_bin=split_bin,
        train_rates=rates[:train_rows],
        train_vel=vel[offset:split_bin],
        test_rates=rates[split_bin:],
        test_vel=vel[split_bin + offset :],
    )


def _cache_meta(encoder_sha: str, session_sha: str, num_bins: int) -> dict[str, object]:
    """The identity a cached design matrix must match before it may be reused."""
    return {
        "encoder_sha256": encoder_sha,
        "session_sha256": session_sha,
        "seq_len": SEQ_LEN,
        "num_bins": int(num_bins),
    }


def _load_cached_rates(cache_dir: Path, session_id: str, meta: dict[str, object]) -> np.ndarray:
    """Cached last-bin rates whose recorded identity matches `meta`, else an empty array.

    A stale or absent cache recomputes rather than failing. Reusing one that does NOT match would
    fit the readout on a different encoder's output than the one that ships.
    """
    payload = cache_dir / f"{session_id}.npy"
    stamp = cache_dir / f"{session_id}.json"
    if not (payload.is_file() and stamp.is_file()):
        return np.empty((0, 0))
    if json.loads(stamp.read_text(encoding="utf-8")) != meta:
        _log(f"  cache for {session_id} does not match the current inputs; recomputing")
        return np.empty((0, 0))
    return np.load(payload)


def _store_cached_rates(
    cache_dir: Path, session_id: str, meta: dict[str, object], rates: np.ndarray
) -> None:
    """Persist the expensive part of the run so an interruption cannot cost the forward pass."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    np.save(cache_dir / f"{session_id}.npy", rates)
    (cache_dir / f"{session_id}.json").write_text(
        json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def _build_design(
    model: NDT1ANEWithVelocity,
    session: SessionLoad,
    *,
    encoder_sha: str,
    session_sha: str,
    cache_dir: Path,
    reuse: bool,
    smoke: bool,
) -> tuple[SessionDesign, np.ndarray]:
    """One session end to end: labels, encoder forward pass, chronological split.

    Returns the design record and the (possibly truncated) binned matrix it was built from, which
    the parity gate needs so it can re-run the full graph on real held-out windows.
    """
    binned = np.asarray(session.binned, dtype=np.float32)
    vel = _velocity_bins(session, binned.shape[0])
    if smoke:
        binned = binned[:SMOKE_BINS]
        vel = vel[:SMOKE_BINS]
    meta = _cache_meta(encoder_sha, session_sha, binned.shape[0])
    rates = _load_cached_rates(cache_dir, session.session_id, meta) if reuse else np.empty((0, 0))
    if rates.size:
        _log(f"  {session.session_id}: reusing {rates.shape[0]} cached design rows")
    else:
        started = time.monotonic()
        rates = _encoder_last_bin(model, binned)
        _log(
            f"  {session.session_id}: {rates.shape[0]} design rows from {binned.shape[0]} bins "
            f"in {time.monotonic() - started:.1f} s"
        )
        _store_cached_rates(cache_dir, session.session_id, meta, rates)
    return _split_design(session.session_id, binned, rates, vel), binned


def _stack_at_lag(
    pairs: list[tuple[np.ndarray, np.ndarray]], lag: int
) -> tuple[np.ndarray, np.ndarray]:
    """Apply `lag` PER SESSION, then concatenate. Never the other way round.

    Lagging a concatenation would pair the last rows of one recording with the first rows of
    another recorded weeks later, which is a fabricated neural-to-kinematic pair.

    `apply_lag` refuses a negative offset, and rightly: it is the motor-cortex convention that the
    neural activity leads. The diagnostic offsets get there by SWAPPING its arguments instead of
    weakening it -- `apply_lag(vel, rates, -lag)` pairs `vel[m]` with `rates[m - lag]`, which is
    the same thing as pairing the window ending at bin `i` with the velocity at bin `i + lag` for
    a negative `lag`.
    """
    if lag >= 0:
        lagged = [apply_lag(rates, vel, lag) for rates, vel in pairs]
    else:
        lagged = [(r, v) for v, r in (apply_lag(vel, rates, -lag) for rates, vel in pairs)]
    return (
        np.concatenate([r for r, _ in lagged], axis=0),
        np.concatenate([v for _, v in lagged], axis=0),
    )


def _fit_train(rates: np.ndarray, vel: np.ndarray, lam: float) -> RidgeFit:
    """Closed-form ridge on the pooled TRAIN rows, scored in-sample against those rows' own mean.

    `heldout_r2` is reused for the arithmetic so there is exactly one definition of R2 in play.
    """
    weight, bias = ridge_fit(rates, vel, lam=lam)
    predicted = rates @ weight.T + bias
    scored = heldout_r2(vel, predicted, vel.mean(axis=0))
    return RidgeFit(
        lam=float(lam),
        weight=weight,
        bias=bias,
        train_r2=float(scored["pooled"]),
        ss_res=float(((vel - predicted) ** 2).sum()),
        rows=int(rates.shape[0]),
    )


def _gcv_score(fit: RidgeFit, eigenvalues: np.ndarray) -> float:
    """Generalized cross-validation for centered ridge (09-RESEARCH section 7, option 1).

    `GCV(lam) = (SS_res / n) / (1 - tr(H)/n)^2` with `tr(H) = sum_i d_i^2 / (d_i^2 + lam) + 1`,
    where `d_i^2` are the eigenvalues of the centered Gram matrix and the `+1` is the intercept the
    centering absorbs. Closed-form on the train split: no extra split, so no leak.
    """
    trace_h = float(np.sum(eigenvalues / (eigenvalues + fit.lam))) + 1.0
    denominator = 1.0 - trace_h / float(fit.rows)
    if denominator <= 0.0:
        raise ValueError(
            f"GCV is undefined at lambda={fit.lam}: the effective degrees of freedom "
            f"{trace_h:.1f} reach the row count {fit.rows}"
        )
    return (fit.ss_res / float(fit.rows)) / (denominator * denominator)


def _select_lag(sweep: list[dict[str, float]]) -> int:
    """Argmax of the TRAIN-only curve (R1). Warns, never re-selects, outside the anchor range."""
    lag = int(max(sweep, key=lambda row: row["train_r2"])["lag_bins"])
    low, high = LAG_ANCHOR_BINS
    if not low <= lag <= high:
        _log(
            f"WARNING: the lag argmax is {lag} bins ({lag * BIN_MS:.0f} ms), outside the "
            f"{low}-{high} bin ({low * BIN_MS:.0f}-{high * BIN_MS:.0f} ms) range anchored by "
            f"nlb_tools' 'lag': 140 for mc_rtt and by the PNAS 120-180 ms cross-correlation. "
            f"Read this as a signal that the label alignment or the sign is wrong, not as a "
            f"discovery."
        )
    return lag


def _as_lag_rows(curve: list[dict[str, float]]) -> list[dict[str, object]]:
    """JSON shape for one lag curve: whole-bin offsets and row counts serialized as ints."""
    return [
        {
            "lag_bins": int(row["lag_bins"]),
            "lag_ms": row["lag_ms"],
            "train_r2": row["train_r2"],
            "lambda": row["lambda"],
            "n": int(row["n"]),
        }
        for row in curve
    ]


def _alignment_verdict(
    diagnostic: list[dict[str, float]], sweep: list[dict[str, float]], locked: int
) -> str:
    """State whether the negative offsets support the locked lag or contradict the alignment.

    The question the D-08 warning raises has exactly one measurable answer: is the locked lag an
    INTERIOR maximum of the two-sided curve, or does the curve keep climbing past the edge of the
    pre-registered sweep? The first says the labels are aligned and the optimum is simply where it
    is; the second says the labels are shifted and the one-sided sweep could not see it.
    """
    combined = sorted(diagnostic + sweep, key=lambda row: row["lag_bins"])
    best = max(combined, key=lambda row: row["train_r2"])
    best_lag = int(best["lag_bins"])
    if best_lag == locked:
        return (
            f"alignment OK: over the two-sided curve "
            f"{int(combined[0]['lag_bins'])} to {int(combined[-1]['lag_bins'])} bins the maximum "
            f"is still lag {locked}, an INTERIOR optimum, so the labels are not shifted"
        )
    return (
        f"WARNING: the two-sided maximum is lag {best_lag} bins "
        f"(train R2 {best['train_r2']:.6f}) against the locked {locked}; the pre-registered "
        f"one-sided sweep could not see it, which is what a shifted label alignment looks like"
    )


def _select_lambda(sweep: list[dict[str, float]]) -> tuple[float, str]:
    """Apply R2's pre-registered lambda rule and return `(locked, rationale)`."""
    scores = [row["train_r2"] for row in sweep]
    spread = max(scores) - min(scores)
    if spread <= LAMBDA_FLAT_TOL:
        return DEFAULT_LAMBDA, (
            f"train R2 spans {spread:.2e} across lambda {LAMBDA_GRID[0]:g} to "
            f"{LAMBDA_GRID[-1]:g}, inside the pre-registered flat tolerance "
            f"{LAMBDA_FLAT_TOL:g}, so the curve documents insensitivity and ridge_fit's existing "
            f"default is locked"
        )
    best = min(sweep, key=lambda row: row["gcv"])
    return best["lambda"], (
        f"train R2 spans {spread:.2e} across the grid, above the pre-registered flat tolerance "
        f"{LAMBDA_FLAT_TOL:g}, so the tie-breaker fired: generalized cross-validation on the "
        f"train split alone, minimized at lambda={best['lambda']:g}"
    )


def _parity_delta(
    model: NDT1ANEWithVelocity, held_out_binned: np.ndarray, fit: RidgeFit
) -> float:
    """Max abs cm/s gap between the assembled graph and `X @ W.T + b` on real held-out windows (R4).

    Runs the FULL `NDT1ANEWithVelocity.forward` -- encoder, last-bin slice, 1x1 conv -- and compares
    it against the arithmetic the reported R2 is computed from. If the design matrix were not the
    tensor the graph feeds its readout (for instance if it had been exponentiated), this gap would
    be enormous rather than fp32 rounding.
    """
    rows = min(PARITY_WINDOWS, held_out_binned.shape[0] - SEQ_LEN + 1)
    windows = _sliding_windows_bc1s(held_out_binned, 0, rows)
    model.eval()
    with torch.no_grad():
        graph = model(windows).reshape(rows, VELOCITY_DIM).numpy().astype(np.float64)
        rates = model.encoder(windows)[..., -1].squeeze(-1).numpy().astype(np.float64)
    return float(np.abs(graph - (rates @ fit.weight.T + fit.bias)).max())


def _finite(value: float, label: str) -> float:
    """Reject a non-finite measurement rather than serializing it as ``null``."""
    if not np.isfinite(value):
        raise ValueError(f"{label} is not finite ({value}); the fit or the labels are degenerate")
    return float(value)


def _r2_record(scored: dict[str, float], label: str, null: str) -> dict[str, object]:
    """One held-out R2 row, with every axis checked finite and the null named in the record."""
    return {
        "vx": _finite(scored["vx"], f"{label} vx R2"),
        "vy": _finite(scored["vy"], f"{label} vy R2"),
        "pooled": _finite(scored["pooled"], f"{label} pooled R2"),
        "n": int(scored["n"]),
        "null": null,
    }


def _score_heldout(
    design: SessionDesign,
    lag: int,
    fit: RidgeFit,
    *,
    null_mean: np.ndarray | None = None,
    null_label: str = "this session's own TRAIN-split mean velocity per axis",
) -> dict[str, object]:
    """Held-out R2 on one session's TEST tail, by default against ITS OWN train-split mean (R3).

    That default is the harder null under within-session drift: any mean taken over other
    recordings sits further from this session's tail, which inflates R2. `null_mean` overrides it
    so the rotation (R5) can also report the weaker training-pool-mean variant through the same
    scoring arithmetic rather than a second copy of it.
    """
    _, train_vel = apply_lag(design.train_rates, design.train_vel, lag)
    test_rates, test_vel = apply_lag(design.test_rates, design.test_vel, lag)
    predicted = test_rates @ fit.weight.T + fit.bias
    null = train_vel.mean(axis=0) if null_mean is None else null_mean
    return _r2_record(heldout_r2(test_vel, predicted, null), design.session_id, null_label)


def _summarize(values: list[float]) -> dict[str, object]:
    """Fold count, mean, sample std, min and max over the folds that FITTED.

    D-13's discipline: a rotation reported as a mean alone hides its spread, and a fold that did
    not produce a value is recorded as a failure rather than averaged away.
    """
    if not values:
        return {"folds": 0, "mean": None, "std": None, "min": None, "max": None}
    arr = np.asarray(values, dtype=np.float64)
    return {
        "folds": int(arr.size),
        "mean": float(arr.mean()),
        "std": float(arr.std(ddof=1)) if arr.size > 1 else 0.0,
        "min": float(arr.min()),
        "max": float(arr.max()),
    }


def _run_readout_loso(
    designs: list[SessionDesign], within: dict[str, object]
) -> tuple[list[dict[str, object]], dict[str, object]]:
    """Leave-one-session-out READOUT rotation (R5). Returns `(folds, summary)`.

    For each session: fit the ridge on the other three sessions' TRAIN rows, re-selecting the lag
    and the lambda on those three alone, and score held-out R2 on the excluded session's own TEST
    tail. Re-selecting per fold is not optional: locking the lag or the lambda once globally would
    have chosen them on data that includes the held-out session.

    **What this measures, and what it does not.** The encoder is the SAME pooled checkpoint in
    every fold, and it was pretrained on all four sessions, so this isolates whether the linear
    READOUT transfers. It is NOT Plan 09-06d's leave-one-session-out co-bps, where the encoder
    itself was retrained from scratch without the held-out session, and it is a strictly weaker
    transfer claim than that one.
    """
    folds: list[dict[str, object]] = []
    for held_out in designs:
        others = [d for d in designs if d.session_id != held_out.session_id]
        pairs = [(d.train_rates, d.train_vel) for d in others]
        _log(f"fold holding out {held_out.session_id}, training on {len(others)} sessions")
        try:
            lag = _select_lag(_run_lag_sweep(pairs, LAG_BINS_SWEEP))
            rates, vel = _stack_at_lag(pairs, lag)
            lambda_curve, fits = _run_lambda_sweep(rates, vel)
            lam, rationale = _select_lambda(lambda_curve)
            fit = fits[lam]
            own = _score_heldout(held_out, lag, fit)
            pool = _score_heldout(
                held_out,
                lag,
                fit,
                null_mean=vel.mean(axis=0),
                null_label="the mean velocity of the fold's three TRAINING sessions",
            )
        except (ValueError, np.linalg.LinAlgError) as exc:
            # Recorded, never dropped: a fold that produced no value is a fact about the rotation.
            _log(f"  FOLD FAILED: {type(exc).__name__}: {exc}")
            folds.append(
                {
                    "held_out_session": held_out.session_id,
                    "fitted": False,
                    "reason": f"{type(exc).__name__}: {exc}",
                }
            )
            continue
        baseline = within.get(held_out.session_id, {})
        in_pool = baseline.get("pooled") if isinstance(baseline, dict) else None
        delta = None if in_pool is None else own["pooled"] - float(in_pool)
        _log(
            f"  lag {lag}, lambda {lam:g}, fit on {fit.rows} rows -> held-out R2 "
            f"{own['pooled']:+.4f} (vx {own['vx']:+.4f}, vy {own['vy']:+.4f}) on {own['n']} bins"
        )
        if delta is not None:
            _log(f"  versus {float(in_pool):+.4f} with this session IN the pool: {delta:+.4f}")
        folds.append(
            {
                "held_out_session": held_out.session_id,
                "fitted": True,
                "train_sessions": [d.session_id for d in others],
                "lag_bins": lag,
                "lag_ms": float(lag) * BIN_MS,
                "lambda": lam,
                "lambda_rule": rationale,
                "train_rows": fit.rows,
                "train_r2": fit.train_r2,
                "heldout_r2": own,
                "heldout_r2_training_pool_null": pool,
                "in_pool_heldout_r2": in_pool,
                "delta_versus_in_pool": delta,
            }
        )
    fitted = [f for f in folds if f["fitted"]]
    scores = [float(f["heldout_r2"]["pooled"]) for f in fitted]
    deltas = [
        float(f["delta_versus_in_pool"])
        for f in fitted
        if f["delta_versus_in_pool"] is not None
    ]
    summary = {
        "null": "the held-out session's OWN TRAIN-split mean velocity per axis",
        **_summarize(scores),
        "failed_folds": [f["held_out_session"] for f in folds if not f["fitted"]],
        "positive_folds": sum(1 for s in scores if s > 0.0),
        "delta_versus_in_pool": _summarize(deltas),
        "training_pool_null": _summarize(
            [float(f["heldout_r2_training_pool_null"]["pooled"]) for f in fitted]
        ),
        "encoder_note": (
            "READOUT-only rotation: the encoder is the same pooled checkpoint in every fold and "
            "was pretrained on all four sessions, so this is a strictly weaker transfer claim "
            "than Plan 09-06d's leave-one-session-out co-bps, where the encoder was retrained "
            "from scratch without the held-out session"
        ),
    }
    return folds, summary


def _resolve_paths(args: argparse.Namespace) -> tuple[Path, Path]:
    """`(metrics, out_checkpoint)`, redirected to scratch paths under `--smoke`."""
    default_metrics = _SMOKE_METRICS if args.smoke else _DEFAULT_METRICS
    default_out = _SMOKE_OUT_CHECKPOINT if args.smoke else _DEFAULT_OUT_CHECKPOINT
    metrics = args.metrics if args.metrics is not None else default_metrics
    out = args.out_checkpoint if args.out_checkpoint is not None else default_out
    return Path(metrics), Path(out)


def _verify_provenance(
    payload: dict[str, object], session_shas: dict[str, str], encoder_sha: str
) -> str:
    """Empty string when the data and the encoder on disk are the ones the metrics JSON records.

    The readout must be fit on exactly the data the encoder was trained on, so the id SET, every
    session's sha256, and the encoder's own sha256 are all checked. Any of the three disagreeing
    means the number this script would publish describes a different artifact than the JSON says.
    """
    entries = payload.get("sessions", [])
    if not isinstance(entries, list):
        return "the metrics JSON has no sessions[] array to check provenance against"
    recorded = {str(entry["id"]): str(entry["sha256"]) for entry in entries}
    if set(recorded) != set(session_shas):
        return (
            f"session ids on disk {sorted(session_shas)} do not match the metrics JSON's "
            f"{sorted(recorded)}"
        )
    drifted = [sid for sid, digest in session_shas.items() if recorded[sid] != digest]
    if drifted:
        return f"session bytes changed since training for {drifted} (sha256 mismatch)"
    checkpoint = payload.get("checkpoint", {})
    expected = str(checkpoint.get("sha256", "")) if isinstance(checkpoint, dict) else ""
    if expected and expected != encoder_sha:
        return (
            f"encoder checkpoint sha256 {encoder_sha} does not match the metrics JSON's "
            f"{expected}; this is not the Plan 09-06 pooled encoder"
        )
    return ""


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fit the NDT1 velocity readout on real finger_pos kinematics (D-05)."
    )
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument(
        "--metrics",
        type=Path,
        default=None,
        help="metrics JSON updated in place (default: the Plan 09-06 file; a scratch file "
        "under --smoke)",
    )
    parser.add_argument("--encoder-checkpoint", type=Path, default=_DEFAULT_ENCODER)
    parser.add_argument("--out-checkpoint", type=Path, default=None)
    parser.add_argument("--rates-cache", type=Path, default=_DEFAULT_RATES_CACHE)
    parser.add_argument(
        "--reuse-rates",
        action="store_true",
        help="reuse cached design matrices when their encoder and session hashes still match",
    )
    parser.add_argument(
        "--loso",
        action="store_true",
        help="run the READOUT leave-one-session-out rotation (R5) and merge it into the velocity "
        "section a full run has already written; pair it with --reuse-rates",
    )
    parser.add_argument(
        "--smoke",
        action="store_true",
        help=f"wiring check on the first {SMOKE_BINS} bins per session, to scratch paths",
    )
    return parser.parse_args(argv)


def _run_lag_sweep(
    pairs: list[tuple[np.ndarray, np.ndarray]], lags: tuple[int, ...]
) -> list[dict[str, float]]:
    """A lag curve on TRAIN rows only, at `DEFAULT_LAMBDA`. `LAG_BINS_SWEEP` is the D-08 sweep."""
    curve: list[dict[str, float]] = []
    for lag in lags:
        rates, vel = _stack_at_lag(pairs, lag)
        fit = _fit_train(rates, vel, DEFAULT_LAMBDA)
        curve.append(
            {
                "lag_bins": float(lag),
                "lag_ms": float(lag) * BIN_MS,
                "train_r2": fit.train_r2,
                "lambda": fit.lam,
                "n": float(fit.rows),
            }
        )
        _log(
            f"  lag {lag} bins ({lag * BIN_MS:.0f} ms): train R2 {fit.train_r2:.6f} "
            f"on {fit.rows} rows"
        )
    return curve


def _run_lambda_sweep(
    rates: np.ndarray, vel: np.ndarray
) -> tuple[list[dict[str, float]], dict[float, RidgeFit]]:
    """The full lambda curve at the locked lag, with each fit kept for the eventual lock."""
    centered = rates - rates.mean(axis=0)
    eigenvalues = np.linalg.eigvalsh(centered.T @ centered)
    eigenvalues = eigenvalues[eigenvalues > 0.0]
    curve: list[dict[str, float]] = []
    fits: dict[float, RidgeFit] = {}
    for lam in LAMBDA_GRID:
        fit = _fit_train(rates, vel, lam)
        gcv = _gcv_score(fit, eigenvalues)
        fits[fit.lam] = fit
        curve.append(
            {"lambda": fit.lam, "train_r2": fit.train_r2, "gcv": gcv, "n": float(fit.rows)}
        )
        _log(f"  lambda {lam:g}: train R2 {fit.train_r2:.6f}, GCV {gcv:.6e}")
    return curve, fits


def _load_sessions(data_dir: Path) -> tuple[list[SessionLoad], int]:
    """Scan `data_dir`, reporting exclusions; returns `(loaded, exit_code)`."""
    loaded, excluded = available_sessions(data_dir)
    for exclusion in excluded:
        _log(f"excluded {exclusion.session_id}: {exclusion.reason}")
    if len(loaded) < MIN_SESSIONS:
        print(
            f"error: only {len(loaded)} loadable sessions under {data_dir}, need at least "
            f"{MIN_SESSIONS}; run Decoder/scripts/download_indy.py first",
            file=sys.stderr,
        )
        return loaded, 1
    return loaded, 0


def main(argv: list[str] | None = None) -> int:
    """Fit the velocity readout on real kinematics and publish an honest held-out R2."""
    args = _parse_args(argv)
    torch.manual_seed(SEED)
    started = time.time()
    metrics_path, out_checkpoint = _resolve_paths(args)

    loaded, code = _load_sessions(args.data_dir)
    if code:
        return code

    encoder_path = Path(args.encoder_checkpoint)
    if not encoder_path.is_file():
        print(f"error: no encoder checkpoint at {encoder_path}", file=sys.stderr)
        return 1
    encoder_sha = _sha256_of(encoder_path)
    session_shas = {session.session_id: _sha256_of(session.path) for session in loaded}

    payload: dict[str, object] = {}
    if metrics_path.is_file():
        payload = json.loads(metrics_path.read_text(encoding="utf-8"))
    if not args.smoke:
        if not payload:
            print(
                f"error: {metrics_path} does not exist; this script merges a velocity section "
                f"into the metrics a Plan 09-06 training run has already written",
                file=sys.stderr,
            )
            return 1
        problem = _verify_provenance(payload, session_shas, encoder_sha)
        if problem:
            print(f"error: {problem}", file=sys.stderr)
            return 1

    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    load_checkpoint(model.encoder, encoder_path)
    model.eval()
    _log(f"encoder {_repo_relative(encoder_path)} sha256 {encoder_sha[:12]} loaded and frozen")

    _log(f"building design matrices for {len(loaded)} sessions")
    built = [
        _build_design(
            model,
            session,
            encoder_sha=encoder_sha,
            session_sha=session_shas[session.session_id],
            # A truncated wiring check must not overwrite the real run's cached forward pass.
            cache_dir=Path(args.rates_cache) / "smoke" if args.smoke else Path(args.rates_cache),
            reuse=args.reuse_rates,
            smoke=args.smoke,
        )
        for session in loaded
    ]
    designs = [design for design, _ in built]
    train_pairs = [(d.train_rates, d.train_vel) for d in designs]

    if args.loso:
        published = payload.get("velocity", {})
        if not isinstance(published, dict) or "per_session" not in published:
            print(
                f"error: {metrics_path} has no velocity.per_session to attach a rotation to; the "
                f"full run has either not happened or did not produce one",
                file=sys.stderr,
            )
            return 1
        _log("readout leave-one-session-out rotation (R5): lag and lambda re-selected per fold")
        folds, summary = _run_readout_loso(designs, published["per_session"])
        published["loso"] = folds
        published["loso_summary"] = summary
        published["wall_clock_loso_s"] = round(time.time() - started, 1)
        metrics_path.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        _log(
            f"rotation: {summary['folds']} fitted, {summary['positive_folds']} positive, "
            f"mean {summary['mean']:+.4f}" if summary["folds"] else "rotation: no fold fitted"
        )
        _log(f"merged velocity.loso into {_repo_relative(metrics_path)}")
        return 0

    _log("lag sweep (R1): TRAIN rows only, 0-160 ms in whole bins")
    lag_curve = _run_lag_sweep(train_pairs, LAG_BINS_SWEEP)
    lag_bins = _select_lag(lag_curve)
    lag_sweep = _as_lag_rows(lag_curve)
    _log(f"locked lag {lag_bins} bins ({lag_bins * BIN_MS:.0f} ms)")

    _log("alignment diagnostic: negative offsets, TRAIN rows only, NOT part of the selection")
    diagnostic_curve = _run_lag_sweep(train_pairs, LAG_DIAGNOSTIC_SWEEP)
    lag_diagnostic = _as_lag_rows(diagnostic_curve)
    _log(_alignment_verdict(diagnostic_curve, lag_curve, lag_bins))

    _log("lambda sweep (R2): TRAIN rows only, at the locked lag")
    rates_train, vel_train = _stack_at_lag(train_pairs, lag_bins)
    lambda_curve, fits = _run_lambda_sweep(rates_train, vel_train)
    locked_lambda, lambda_rationale = _select_lambda(lambda_curve)
    lambda_sweep = [
        {
            "lambda": row["lambda"],
            "train_r2": row["train_r2"],
            "gcv": row["gcv"],
            "n": int(row["n"]),
        }
        for row in lambda_curve
    ]
    _log(f"locked lambda {locked_lambda:g} -- {lambda_rationale}")

    fit = fits[locked_lambda]
    in_sample = model.fit_velocity_head(rates_train, vel_train, lam=locked_lambda)
    _log(
        f"head loaded: in-sample R2 {in_sample['r2']:.6f} on {in_sample['n']} rows -- the kind of "
        f"number D-10 REPLACES, recorded only to show the load path ran"
    )

    held_out_bins = built[0][1][designs[0].split_bin :]
    parity = _parity_delta(model, held_out_bins, fit)
    _log(f"forward parity (R4): max abs {parity:.3e} cm/s against X @ W.T + b")
    if parity > PARITY_TOL:
        print(
            f"error: the assembled graph disagrees with the fitted readout by {parity:.3e} cm/s, "
            f"above the {PARITY_TOL:g} tolerance; the design matrix is not the tensor the shipped "
            f"graph feeds its readout",
            file=sys.stderr,
        )
        return 1

    per_session = {d.session_id: _score_heldout(d, lag_bins, fit) for d in designs}
    test_rates, test_vel = _stack_at_lag([(d.test_rates, d.test_vel) for d in designs], lag_bins)
    pooled = _r2_record(
        heldout_r2(test_vel, test_rates @ fit.weight.T + fit.bias, vel_train.mean(axis=0)),
        "pooled",
        "the POOLED TRAIN-split mean velocity per axis",
    )
    for sid, scores in per_session.items():
        _log(
            f"  {sid}: held-out R2 vx {scores['vx']:+.4f} vy {scores['vy']:+.4f} "
            f"pooled {scores['pooled']:+.4f} on {scores['n']} bins"
        )
    _log(
        f"POOLED held-out R2 {pooled['pooled']:+.4f} "
        f"(vx {pooled['vx']:+.4f}, vy {pooled['vy']:+.4f}) on {pooled['n']} bins"
    )

    save_checkpoint(model, out_checkpoint)
    out_sha = _sha256_of(out_checkpoint)
    _log(f"wrote {_repo_relative(out_checkpoint)} sha256 {out_sha}")

    payload["velocity"] = {
        "label_source": _LABEL_SOURCE,
        "derivation": _DERIVATION,
        "design_matrix": {
            "rows": "one stride-1 32-bin window per bin, indexed by the window's LAST bin",
            "columns": "the encoder's raw output at that last bin, NOT exponentiated",
            "encoder_input": "raw unmasked spike counts, i.e. the serving condition",
            "train_rows": fit.rows,
            "held_out_rows": pooled["n"],
        },
        "lag_bins": lag_bins,
        "lag_ms": float(lag_bins) * BIN_MS,
        "lag_sweep": lag_sweep,
        "lag_alignment_diagnostic": {
            "note": (
                "negative offsets, computed AFTER the pre-registered sweep and never part of the "
                "selection. D-08's sweep is one-sided, so a shifted label would pin its argmax at "
                "lag 0; these rows are what distinguish that from a genuine interior optimum."
            ),
            "verdict": _alignment_verdict(diagnostic_curve, lag_curve, lag_bins),
            "curve": lag_diagnostic,
        },
        "lambda": locked_lambda,
        "lambda_sweep": lambda_sweep,
        "lambda_rule": lambda_rationale,
        "heldout_r2": pooled,
        "per_session": per_session,
        "null": _NULL_DESCRIPTION,
        "forward_parity_max_abs_cm_s": parity,
        "in_sample_train_r2": float(in_sample["r2"]),
        "encoder": {"path": _repo_relative(encoder_path), "sha256": encoder_sha},
        "checkpoint": {"path": _repo_relative(out_checkpoint), "sha256": out_sha},
        "env": _environment(),
        "wall_clock_s": round(time.time() - started, 1),
        "smoke": bool(args.smoke),
        "supersedes": _SUPERSEDES,
    }
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"merged the velocity section into {_repo_relative(metrics_path)}")
    return 0


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    raise SystemExit(main())
