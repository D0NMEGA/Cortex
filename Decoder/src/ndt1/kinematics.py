"""D-05 kinematics layer: `finger_pos` -> 20 ms-binned `(vx, vy)` velocity labels.

Turns the behavior arrays `load_session` returns into the supervision signal the shipped
`.mlpackage`'s velocity readout is fit on, and into the alignment that readout's geometry implies:

  load_session(path)["planar_cm"], ["t"]   (n_samples, 2) cm at 250 Hz, sign already undone
        │
        ▼
  planar_velocity_250hz                    (n_samples, 2) cm/s -- finite difference, no filter
        │
        ▼
  bin_velocity(bin_ms=BIN_MS)              (num_bins, 2) -- mean per bin, on bin_spikes' EDGES
        │
        ▼
  apply_lag(rates, vel, k)                 the window ENDING at bin i <-> the velocity at bin i+k

Hard rules enforced here:
  * The derivative is a plain finite difference at the native behavior rate (D-07). There is NO
    smoothing filter: a Savitzky-Golay derivative introduces window-length and polynomial-order
    parameters that would each need justifying, and it can smooth away genuine fast dynamics.
    The 250 Hz clock is already 5x finer than the 20 ms bin the samples are aggregated into, so
    the aggregation is the only averaging that happens, and it is the one the labels need.
  * `bin_velocity` recomputes `num_bins` with the IDENTICAL arithmetic `ndt1.data.bin_spikes`
    uses and reuses its high-edge clip, so the rates matrix and the velocity matrix are row
    aligned BY CONSTRUCTION rather than by a caller remembering to check.
  * A bin containing no behavior samples raises rather than emitting a NaN. At 250 Hz a 20 ms bin
    holds about 5 samples, so an empty bin means the spike clock and the behavior clock disagree,
    and a NaN label would silently poison the ridge fit (T-09-03-01, ASVS V5).
  * A non-monotone or duplicated behavior timestamp raises rather than dividing by zero
    (T-09-03-02).
  * `apply_lag` DROPS the unpaired tail. It never pads, because a padded label is a fabricated
    label.
  * This module is pure array math: no session loading, no file I/O, no training loop.
  * No bare or blind `except` (ruff `BLE` gate); every failure path raises an explicit
    `ValueError` naming the offending value.
"""
from __future__ import annotations

import numpy as np

from ndt1.data import BIN_MS
from ndt1.velocity_head import ridge_fit

#: Native behavior sample rate of the O'Doherty Indy/Loco recordings. Verified on
#: `indy_20160630_01`: the median `diff(t)` is 0.004 s.
BEHAVIOR_HZ: float = 250.0

#: D-08 sweep: whole 20 ms bin offsets spanning 0-160 ms. `nlb_tools/make_tensors.py` sets
#: `'lag': 140` (ms) for `mc_rtt`, which is bin 7 here; M1 activity leads hand velocity by
#: 120-180 ms (PNAS 10.1073/pnas.2212227120). A selected lag far outside 5-8 bins is a signal
#: that the alignment or the sign is wrong, not a discovery.
LAG_BINS_SWEEP: tuple[int, ...] = (0, 1, 2, 3, 4, 5, 6, 7, 8)

#: The two planar velocity axes, in the column order every array in this module uses. Its length
#: is the axis width the shape checks enforce.
_AXIS_NAMES: tuple[str, str] = ("vx", "vy")

_MS_PER_S: float = 1000.0


def planar_velocity_250hz(planar_cm: np.ndarray, t: np.ndarray) -> np.ndarray:
    """Finite-difference (x, y) position in cm -> (vx, vy) in cm/s at the native sample rate.

    A backward difference, `v[i] = (p[i] - p[i-1]) / (t[i] - t[i-1])`, with the undefined first
    row repeating the second so the result keeps `t.size` rows and stays index-aligned with both
    `t` and `planar_cm`. Aggregation into 20 ms bins is :func:`bin_velocity`'s job, not this
    function's, and it is the ONLY averaging applied to the labels (D-07).

    Args:
        planar_cm: `(n_samples, 2)` sign-corrected (x, y) position in cm, i.e. exactly what
            `ndt1.data.load_session` returns as `"planar_cm"`.
        t: `(n_samples,)` behavior timestamps in seconds, strictly increasing.

    Returns:
        A `float64` array of shape `(n_samples, 2)` in cm/s.

    Raises:
        ValueError: if `t` carries fewer than two samples, if `planar_cm` is not
            `(t.size, 2)`, or if the behavior clock is not strictly increasing.
    """
    pos = np.asarray(planar_cm, dtype=np.float64)
    clock = np.asarray(t, dtype=np.float64).ravel()
    if clock.size < 2:
        raise ValueError(f"t must carry at least 2 samples to difference, got {clock.size}")
    if pos.shape != (clock.size, 2):
        raise ValueError(
            f"planar_cm must have shape ({clock.size}, 2) to match t, got {pos.shape}. Row 0 of "
            f"finger_pos is the near-constant depth axis: the planar pair must already have been "
            f"selected and sign-corrected by load_session (09-RESEARCH P4)."
        )

    dt = np.diff(clock)
    if np.any(dt <= 0.0):
        first = int(np.argmax(dt <= 0.0))
        raise ValueError(
            f"the behavior clock is not strictly monotone: dt[{first}] = {float(dt[first])} s "
            f"at t = {float(clock[first])} s. A duplicated timestamp divides by zero and a "
            f"backwards one flips the velocity sign (T-09-03-02)."
        )

    step = np.diff(pos, axis=0) / dt[:, None]
    return np.concatenate([step[:1], step], axis=0)


def bin_velocity(
    vel: np.ndarray,
    t: np.ndarray,
    *,
    t_start: float,
    t_end: float,
    bin_ms: float = BIN_MS,
) -> np.ndarray:
    """Mean-aggregate per-sample velocity into 20 ms bins on the SAME edges as `bin_spikes`.

    `num_bins` is recomputed with the identical `floor((t_end - t_start) / bin_s)` arithmetic
    `ndt1.data.bin_spikes` uses, and the same high-edge clip folds a trailing partial bin into the
    last full bin. That is what makes `binned[i]` and the returned `velocity[i]` describe the same
    20 ms of recording: a one-row disagreement would shift every label by a bin, silently.

    Args:
        vel: `(n_samples, 2)` per-sample velocity, row-aligned with `t`.
        t: `(n_samples,)` behavior timestamps in seconds.
        t_start: window start (seconds, inclusive) -- pass `load_session`'s `"t_start"`.
        t_end: window end (seconds, exclusive) -- pass `load_session`'s `"t_end"`.
        bin_ms: bin width in milliseconds; defaults to `ndt1.data.BIN_MS` (20 ms) so the two
            bin widths cannot drift apart.

    Returns:
        A `float64` array of shape `(num_bins, 2)` where
        `num_bins == floor((t_end - t_start) / (bin_ms / 1000))`.

    Raises:
        ValueError: if the shapes disagree, if the window or bin width is degenerate, or if any
            bin contains no behavior sample.
    """
    v = np.asarray(vel, dtype=np.float64)
    clock = np.asarray(t, dtype=np.float64).ravel()
    if v.ndim != 2 or v.shape[1] != 2:
        raise ValueError(f"vel must be 2-D (n_samples, 2), got shape {v.shape}")
    if v.shape[0] != clock.size:
        raise ValueError(
            f"vel has {v.shape[0]} samples but t has {clock.size}; the two must be row-aligned"
        )
    if bin_ms <= 0.0:
        raise ValueError(f"bin_ms must be positive, got {bin_ms}")
    if t_end <= t_start:
        raise ValueError(f"t_end ({t_end}) must be greater than t_start ({t_start})")

    bin_s = bin_ms / _MS_PER_S
    num_bins = int(np.floor((t_end - t_start) / bin_s))
    if num_bins <= 0:
        raise ValueError(
            f"window [{t_start}, {t_end}) s is shorter than one {bin_ms} ms bin (0 bins)"
        )

    in_range = (clock >= t_start) & (clock < t_end)
    bin_idx = np.floor((clock[in_range] - t_start) / bin_s).astype(np.intp)
    # Mirror bin_spikes' high-edge guard: a sample in the trailing partial bin lands in the last
    # full bin rather than off the end of the matrix.
    np.clip(bin_idx, 0, num_bins - 1, out=bin_idx)

    sums = np.zeros((num_bins, 2), dtype=np.float64)
    counts = np.zeros(num_bins, dtype=np.int64)
    np.add.at(sums, bin_idx, v[in_range])
    np.add.at(counts, bin_idx, 1)

    empty = np.flatnonzero(counts == 0)
    if empty.size:
        per_bin = BEHAVIOR_HZ * bin_s
        raise ValueError(
            f"velocity bin {int(empty[0])} contains no behavior samples ({empty.size} of "
            f"{num_bins} bins are empty). At {BEHAVIOR_HZ:g} Hz a {bin_ms:g} ms bin holds about "
            f"{per_bin:g} samples, so an empty bin means the spike clock and the behavior clock "
            f"disagree. Emitting a NaN label here would silently poison the ridge fit."
        )
    return sums / counts[:, None]


def apply_lag(
    rates: np.ndarray, vel: np.ndarray, lag_bins: int
) -> tuple[np.ndarray, np.ndarray]:
    """Pair the window ENDING at bin `i` with the velocity at bin `i + lag_bins`.

    `VelocityHead.forward` reads `rates[..., -1:]`, a static slice of the LAST bin of its input
    window, so the neural evidence for a velocity sits at the END of the window. "Lag k" therefore
    means: take the rates row at bin `i` and the velocity row at bin `i + k`. The last `k` rates
    rows have no partner and are DROPPED; nothing is padded, because a padded label is a
    fabricated label.

    Args:
        rates: `(n_bins, num_channels)` per-bin rates, in time order.
        vel: `(n_bins, 2)` per-bin velocity labels, in time order and on the same bin edges.
        lag_bins: whole-bin neural-to-kinematic offset, `>= 0`. See :data:`LAG_BINS_SWEEP`.

    Returns:
        `(rates_aligned, vel_aligned)`, both with `min(len(rates), len(vel)) - lag_bins` rows.

    Raises:
        ValueError: if `lag_bins` is negative or consumes every available row.
    """
    if lag_bins < 0:
        raise ValueError(
            f"lag_bins must be >= 0, got {lag_bins}. A negative lag would mean the kinematics "
            f"lead the neural activity, which is the area2_bump somatosensory convention, not "
            f"this motor-cortex one."
        )
    n = min(len(rates), len(vel))
    if lag_bins >= n:
        raise ValueError(
            f"lag_bins={lag_bins} consumes every paired row (only {n} rows available); the "
            f"sweep {LAG_BINS_SWEEP} needs matrices longer than its largest offset"
        )
    kept = n - lag_bins
    return rates[:kept], vel[lag_bins : lag_bins + kept]


def heldout_r2(
    y_true: np.ndarray, y_pred: np.ndarray, train_mean: np.ndarray
) -> dict[str, float]:
    """Held-out R2 of a velocity readout against a CONSTANT TRAIN-MEAN null (D-10).

    `R2_axis = 1 - SS_res / SS_tot` where

        SS_res = sum over TEST bins (y_true - y_pred)^2
        SS_tot = sum over TEST bins (y_true - train_mean)^2

    The null mean MUST come from the TRAIN split, mirroring `ndt1.metrics.co_bps`'s train-split
    mean-rate null. Using the test set's own mean turns `SS_tot` into the test variance and
    silently converts this into the easier textbook R2 -- a different claim. The two are not
    interchangeable on this dataset: measured within-session drift on `indy_20160630_01` is -8.1%
    in mean rate from the train head to the test tail (09-RESEARCH P8), in the direction that
    inflates the train-null score. This is what replaces `velocity_r2.json`'s 0.9998, which
    regressed rates onto labels generated from those same rates and is a self-consistency check
    rather than a decode result.

    A value below zero is returned as measured and is NEVER clamped: a readout worse than
    predicting the average is a real, reportable finding under D-25 (T-09-03-05).

    Args:
        y_true: `(n, 2)` held-out velocity labels.
        y_pred: `(n, 2)` readout predictions on the same held-out bins.
        train_mean: `(2,)` per-axis mean velocity of the TRAIN split -- the null's constant
            prediction. Required, and positional, so it cannot quietly default to the test mean.

    Returns:
        `{"vx": float, "vy": float, "pooled": float, "n": int}`, where `"pooled"` is
        `1 - sum_axes SS_res / sum_axes SS_tot` and NOT the mean of the per-axis values: the two
        axes can carry different variance, and averaging them would over-weight the quiet axis.

    Raises:
        ValueError: if the shapes disagree, or if a held-out axis is constant at the train mean
            so its `SS_tot` is zero and R2 against a mean null is undefined.
    """
    n_axes = len(_AXIS_NAMES)
    truth = np.asarray(y_true, dtype=np.float64)
    pred = np.asarray(y_pred, dtype=np.float64)
    null = np.asarray(train_mean, dtype=np.float64)
    if truth.ndim != 2 or truth.shape[1] != n_axes:
        raise ValueError(f"y_true must be 2-D (n, {n_axes}), got shape {truth.shape}")
    if pred.shape != truth.shape:
        raise ValueError(f"y_pred shape {pred.shape} does not match y_true shape {truth.shape}")
    if null.shape != (n_axes,):
        raise ValueError(f"train_mean must have shape ({n_axes},), got {null.shape}")

    ss_res = ((truth - pred) ** 2).sum(axis=0)
    ss_tot = ((truth - null) ** 2).sum(axis=0)
    constant = np.flatnonzero(ss_tot == 0.0)
    if constant.size:
        axis = int(constant[0])
        raise ValueError(
            f"the held-out signal on axis {axis} ({_AXIS_NAMES[axis]}) is constant at the train "
            f"mean, so its SS_tot is zero and R2 against a mean null is undefined"
        )

    per_axis = 1.0 - ss_res / ss_tot
    scores: dict[str, float] = {
        name: float(per_axis[axis]) for axis, name in enumerate(_AXIS_NAMES)
    }
    scores["pooled"] = float(1.0 - ss_res.sum() / ss_tot.sum())
    scores["n"] = int(truth.shape[0])
    return scores


def lag_sweep_r2(
    rates_train: np.ndarray,
    vel_train: np.ndarray,
    *,
    lags: tuple[int, ...] = LAG_BINS_SWEEP,
    lam: float = 1.0,
) -> list[dict[str, float]]:
    """Fit ridge at each whole-bin lag on the TRAIN split ONLY and score in-sample R2 there.

    D-08: the selection never touches the held-out tail, so there is no leak, and the FULL curve
    is published rather than only the argmax -- the sweep documents how sensitive R2 is to the
    choice instead of leaving it assumed. Both arguments MUST already be the train split; handing
    this a whole session would select the lag on the same rows the reported number is scored on.

    The returned `train_r2` is in-sample, against the mean of the same TRAIN rows the fit used.
    It is a selection criterion, not a result: the reportable number is :func:`heldout_r2` on the
    held-out tail.

    Args:
        rates_train: `(n_bins, num_channels)` TRAIN-split per-bin rates.
        vel_train: `(n_bins, 2)` TRAIN-split per-bin velocity labels, on the same bin edges.
        lags: whole-bin offsets to sweep (default :data:`LAG_BINS_SWEEP`, 0-160 ms).
        lam: ridge regularization strength, passed to :func:`ndt1.velocity_head.ridge_fit`. D-09
            keeps the closed-form ridge, so a lambda sweep is a caller-side loop over this
            argument rather than selection logic in here.

    Returns:
        One `{"lag_bins": int, "lag_ms": float, "train_r2": float, "lambda": float}` entry per
        swept lag, in `lags` order.

    Raises:
        ValueError: if a lag consumes every available row, or a train axis is constant.
    """
    curve: list[dict[str, float]] = []
    for lag in lags:
        rates_lagged, vel_lagged = apply_lag(rates_train, vel_train, lag)
        weight, bias = ridge_fit(rates_lagged, vel_lagged, lam=lam)
        # The linear readout the loaded 1x1 conv reproduces exactly.
        predicted = rates_lagged @ weight.T + bias
        scored = heldout_r2(vel_lagged, predicted, vel_lagged.mean(axis=0))
        curve.append(
            {
                "lag_bins": lag,
                "lag_ms": float(lag) * BIN_MS,
                "train_r2": scored["pooled"],
                "lambda": float(lam),
            }
        )
    return curve
