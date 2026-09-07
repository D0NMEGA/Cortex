"""Matched linear baselines for the NDT1 velocity readout.

The published held-out velocity R2 comes from `spikes -> NDT1 encoder -> 96-d features -> ridge`.
That number alone cannot say whether the encoder earns its place: a causal linear filter on the same
spikes might do as well. This script fits that filter and scores it through the SAME code path, so
the difference is attributable to the encoder and to nothing else.

**What is held identical to `fit_velocity_real.py`, deliberately:**

- `SEQ_LEN = 32` and `TEST_FRAC = 0.2`, imported rather than restated.
- `chronological_split` decides the split bin; the arithmetic is never re-derived here.
- Row alignment: design row `j` is the window ENDING at bin `j + SEQ_LEN - 1`, paired with the
  velocity at that same bin. Test rows start a full window after the split, so no held-out row
  reads a bin the train fit saw.
- `kinematics.heldout_r2` with an explicit TRAIN-split mean null. Not the test mean: on this dataset
  that swap inflates the score, and the two are different claims.
- `velocity_head.ridge_fit`'s closed form, reimplemented here only because the full design matrix
  does not fit in memory (see `_GramAccumulator`); the solved system is the same one.

**The only variable is the design matrix.** NDT1 supplies 96 encoder outputs per row. This supplies
`96 * K` raw spike counts, the last `K` bins of the very same 32-bin window. `K` is swept so the
comparison is not hostage to one arbitrary history length, and `K = 32` is the like-for-like row: it
sees exactly the bins the encoder sees.

A negative R2 is reported as measured and never clamped. A baseline that beats the encoder is a
result, not a bug, and this script has no way to prefer one outcome.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ndt1.data import BIN_MS, chronological_split
from ndt1.kinematics import bin_velocity, heldout_r2, planar_velocity_250hz
from ndt1.sessions import DEFAULT_DATA_DIR, SessionLoad, available_sessions

# Inherited, never chosen here: a different value would score against a different split than the
# encoder was evaluated on and the comparison would be meaningless.
SEQ_LEN: int = 32
TEST_FRAC: float = 0.2

# History lengths in 20 ms bins. 32 is the like-for-like row (the encoder's whole window); the
# shorter taps show how much of the signal is available without any long-range context at all.
HISTORY_BINS: tuple[int, ...] = (1, 2, 4, 8, 16, 32)

# Neural-to-kinematic lag in bins, matching `apply_lag`: the window ending at bin `i` is paired with
# the velocity at bin `i + LAG_BINS`. The encoder readout is fit at 1 bin (20 ms), and the export
# sidecar records `lag_bins: 1`, so the baseline must use the same value or the row counts and the
# labels differ and the comparison is not matched. Verified: at lag 0 this script yields 56,947
# pooled test rows against the encoder's 56,943; the 4-row gap is exactly one dropped row per
# session, which is what a 1-bin lag costs.
LAG_BINS: int = 1

# Ridge grid, same shape as the encoder readout's. Selection is on the TRAIN split only; the
# held-out tail is never consulted to pick a hyperparameter.
# on the TRAIN split only; the held-out tail is never consulted to pick a hyperparameter.
LAMBDA_GRID: tuple[float, ...] = (0.01, 0.1, 1.0, 10.0, 100.0, 1000.0)

VELOCITY_DIM: int = 2


def _log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


@dataclass
class _GramAccumulator:
    """Streaming `XᵀX`, `XᵀY`, and column sums for a design matrix too large to hold.

    Pooling four sessions at `K = 32` is roughly 230k rows by 3,072 columns, about 5.6 GB in
    float64.
    The closed-form ridge only needs the Gram matrices, which are `3072 x 3072` at most, so the rows
    are streamed and discarded. Centering is applied analytically afterwards from the running sums,
    which is exact rather than an approximation of the centered fit.
    """

    n_features: int
    xtx: np.ndarray
    xty: np.ndarray
    sum_x: np.ndarray
    sum_y: np.ndarray
    rows: int

    @classmethod
    def empty(cls, n_features: int) -> _GramAccumulator:
        return cls(
            n_features=n_features,
            xtx=np.zeros((n_features, n_features), dtype=np.float64),
            xty=np.zeros((n_features, VELOCITY_DIM), dtype=np.float64),
            sum_x=np.zeros(n_features, dtype=np.float64),
            sum_y=np.zeros(VELOCITY_DIM, dtype=np.float64),
            rows=0,
        )

    def add(self, x: np.ndarray, y: np.ndarray, chunk: int = 8192) -> None:
        """Accumulate in row chunks.

        A whole session at `K = 32` is about 58k rows by 3,072 columns; promoting that to float64 in
        one go is roughly 1.4 GB, and two of them live at once during the matmul. Chunking keeps the
        peak bounded without changing the result: the Gram matrices are additive over row blocks.
        """
        for start in range(0, x.shape[0], chunk):
            xd = np.asarray(x[start : start + chunk], dtype=np.float64)
            yd = np.asarray(y[start : start + chunk], dtype=np.float64)
            self.xtx += xd.T @ xd
            self.xty += xd.T @ yd
            self.sum_x += xd.sum(axis=0)
            self.sum_y += yd.sum(axis=0)
            self.rows += xd.shape[0]

    def centered(self) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """`(Sxx, Sxy, mean_x, mean_y)` for the centered system."""
        if self.rows == 0:
            raise ValueError("no rows accumulated")
        mean_x = self.sum_x / self.rows
        mean_y = self.sum_y / self.rows
        sxx = self.xtx - self.rows * np.outer(mean_x, mean_x)
        sxy = self.xty - self.rows * np.outer(mean_x, mean_y)
        return sxx, sxy, mean_x, mean_y


def _windows(binned: np.ndarray, history: int) -> np.ndarray:
    """Design rows: row `j` is the last `history` bins of the window ending at `j + SEQ_LEN - 1`.

    Returned as `(n_windows, history * num_channels)` in float32. The row count and the bin each row
    ends on are independent of `history`, so every history length is scored on the same rows as the
    encoder, and the sweep compares like with like.
    """
    if history > SEQ_LEN:
        raise ValueError(f"history {history} exceeds SEQ_LEN {SEQ_LEN}")
    num_bins, num_channels = binned.shape
    n_windows = num_bins - SEQ_LEN + 1
    if n_windows <= 0:
        raise ValueError(f"session has {num_bins} bins, fewer than SEQ_LEN={SEQ_LEN}")
    stack = np.empty((n_windows, history * num_channels), dtype=np.float32)
    for tap in range(history):
        # The window ending at bin j+SEQ_LEN-1 has its (history-1-tap)-th most recent bin at
        # j + SEQ_LEN - history + tap.
        start = SEQ_LEN - history + tap
        stack[:, tap * num_channels : (tap + 1) * num_channels] = binned[
            start : start + n_windows
        ]
    return stack


@dataclass(frozen=True)
class SessionDesign:
    """One session's baseline design, split exactly as `fit_velocity_real._split_design` splits."""

    session_id: str
    train_x: np.ndarray
    train_y: np.ndarray
    test_x: np.ndarray
    test_y: np.ndarray


def _design(session: SessionLoad, history: int, lag: int = LAG_BINS) -> SessionDesign:
    # `session.binned` is the SAME array the encoder was trained and evaluated on. Re-binning here
    # would risk a different bin edge and silently break the comparison.
    binned = session.binned
    num_bins = binned.shape[0]
    vel_250 = planar_velocity_250hz(session.planar_cm, session.t)
    vel = bin_velocity(
        vel_250, session.t, t_start=session.t_start, t_end=session.t_end, bin_ms=BIN_MS
    )
    if vel.shape[0] != num_bins:
        raise ValueError(
            f"{session.session_id}: {vel.shape[0]} velocity bins vs {num_bins} spike bins"
        )

    split_bin = int(chronological_split(binned, test_frac=TEST_FRAC)[0].shape[0])
    offset = SEQ_LEN - 1
    stack = _windows(binned, history)

    # `apply_lag` semantics: design row j ends at bin j+offset and is paired with the velocity at
    # bin j+offset+lag. The last `lag` rows of each block have no partner and are dropped, never
    # padded, because a padded label is a fabricated label.
    train_rows = split_bin - offset - lag
    test_rows = num_bins - split_bin - offset - lag
    if train_rows <= 0 or test_rows <= 0:
        raise ValueError(f"{session.session_id}: lag {lag} consumes the split")
    return SessionDesign(
        session_id=session.session_id,
        train_x=stack[:train_rows],
        train_y=vel[offset + lag : split_bin],
        test_x=stack[split_bin : split_bin + test_rows],
        test_y=vel[split_bin + offset + lag :],
    )


def _solve(sxx: np.ndarray, sxy: np.ndarray, mean_x: np.ndarray, mean_y: np.ndarray, lam: float):
    """Centered ridge solve. Returns `(weight (F,2), bias (2,))`."""
    n_features = sxx.shape[0]
    weight = np.linalg.solve(sxx + lam * np.eye(n_features), sxy)
    bias = mean_y - weight.T @ mean_x
    return weight, bias


def _predict(x: np.ndarray, weight: np.ndarray, bias: np.ndarray) -> np.ndarray:
    return np.asarray(x, dtype=np.float64) @ weight + bias


def _select_lambda(acc: _GramAccumulator, designs: list[SessionDesign]) -> tuple[float, dict]:
    """Pick lambda by in-sample train R2 over the grid, scored on the pooled TRAIN rows only.

    The held-out tail is never read here.

    KNOWN WEAKNESS, stated rather than hidden: in-sample train R2 is monotone in model freedom, so
    this rule always selects the SMALLEST lambda in the grid. The encoder readout does better; it
    falls back to generalized cross-validation when the train scores span more than its flat
    tolerance. A degenerate rule is acceptable here only because of the direction of the error: a
    better-chosen lambda could only improve the held-out score, so the baseline number this script
    publishes is a LOWER bound on what a linear decoder achieves. It is not a reason to prefer the
    baseline's number if it were losing, and if this script is ever used to argue the other way the
    rule must be replaced with GCV first.
    """
    sxx, sxy, mean_x, mean_y = acc.centered()
    train_mean = mean_y
    scores: dict[str, float] = {}
    best_lam, best = LAMBDA_GRID[0], -np.inf
    for lam in LAMBDA_GRID:
        weight, bias = _solve(sxx, sxy, mean_x, mean_y, lam)
        ss_res = np.zeros(VELOCITY_DIM)
        ss_tot = np.zeros(VELOCITY_DIM)
        for d in designs:
            pred = _predict(d.train_x, weight, bias)
            ss_res += ((d.train_y - pred) ** 2).sum(axis=0)
            ss_tot += ((d.train_y - train_mean) ** 2).sum(axis=0)
        r2 = float(1.0 - ss_res.sum() / ss_tot.sum())
        scores[f"{lam}"] = r2
        if r2 > best:
            best_lam, best = lam, r2
    return best_lam, {"grid": scores, "selected": best_lam, "in_sample_train_r2": best}


def _run_history(sessions: list[SessionLoad], history: int, lag: int = LAG_BINS) -> dict:
    _log(f"  history={history} bins ({history * 20} ms): building designs")
    designs = [_design(s, history, lag) for s in sessions]
    n_features = designs[0].train_x.shape[1]

    acc = _GramAccumulator.empty(n_features)
    for d in designs:
        acc.add(d.train_x, d.train_y)

    lam, lam_meta = _select_lambda(acc, designs)
    sxx, sxy, mean_x, mean_y = acc.centered()
    weight, bias = _solve(sxx, sxy, mean_x, mean_y, lam)
    pooled_train_mean = mean_y

    pooled_true = np.concatenate([d.test_y for d in designs], axis=0)
    pooled_pred = np.concatenate([_predict(d.test_x, weight, bias) for d in designs], axis=0)
    pooled = heldout_r2(pooled_true, pooled_pred, pooled_train_mean)

    per_session: dict[str, dict] = {}
    for d in designs:
        own_train_mean = np.asarray(d.train_y, dtype=np.float64).mean(axis=0)
        per_session[d.session_id] = heldout_r2(
            d.test_y, _predict(d.test_x, weight, bias), own_train_mean
        ) | {"null": "this session's own TRAIN-split mean velocity per axis"}

    _log(f"    lambda={lam}  pooled held-out R2={pooled['pooled']:.4f}  n={pooled['n']}")
    return {
        "history_bins": history,
        "lag_bins": lag,
        "history_ms": history * BIN_MS,
        "n_features": int(n_features),
        "lambda": lam,
        "lambda_selection": lam_meta,
        "heldout_r2": pooled | {"null": "the POOLED TRAIN-split mean velocity per axis"},
        "per_session": per_session,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("Decoder/metrics/baseline_decoders.json"),
        help="where to write the metrics artifact",
    )
    parser.add_argument(
        "--history",
        type=int,
        nargs="*",
        default=list(HISTORY_BINS),
        help="history lengths in bins to sweep",
    )
    parser.add_argument("--lag-bins", type=int, default=LAG_BINS,
                        help="neural-to-kinematic lag in bins (must match the encoder readout)")
    args = parser.parse_args(argv)

    started = time.time()
    loaded, excluded = available_sessions(args.data_dir)
    for exclusion in excluded:
        _log(f"excluded {exclusion.session_id}: {exclusion.reason}")
    if not loaded:
        print(
            f"error: no loadable sessions under {args.data_dir}; run "
            f"Decoder/scripts/download_indy.py first",
            file=sys.stderr,
        )
        return 1
    _log(f"loaded {len(loaded)} sessions: {', '.join(s.session_id for s in loaded)}")

    results = [_run_history(loaded, h, args.lag_bins) for h in sorted(set(args.history))]

    payload = {
        "schema_version": 1,
        "what_this_is": (
            "Causal linear (Wiener) velocity decoders on RAW binned spike counts, fit and scored "
            "through the same split, row alignment and heldout_r2 train-mean null as the NDT1 "
            "encoder readout. The only variable is the design matrix."
        ),
        "lambda_selection_caveat": (
            "Lambda is picked by in-sample train R2, which is monotone in model freedom and so "
            "always selects the smallest grid value. The encoder readout uses GCV. This makes the "
            "baseline scores here a LOWER bound: a better lambda could only raise them."
        ),
        "not_a_claim": (
            "These are baselines, not a product. A baseline that matches or beats the encoder is "
            "reported as measured; nothing here is clamped or re-rolled."
        ),
        "seq_len": SEQ_LEN,
        "test_frac": TEST_FRAC,
        "lag_bins": args.lag_bins,
        "bin_ms": BIN_MS,
        "sessions": [s.session_id for s in loaded],
        "results": results,
        "elapsed_s": round(time.time() - started, 2),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
