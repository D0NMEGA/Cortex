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

#: Native behavior sample rate of the O'Doherty Indy/Loco recordings. Verified on
#: `indy_20160630_01`: the median `diff(t)` is 0.004 s.
BEHAVIOR_HZ: float = 250.0

#: D-08 sweep: whole 20 ms bin offsets spanning 0-160 ms. `nlb_tools/make_tensors.py` sets
#: `'lag': 140` (ms) for `mc_rtt`, which is bin 7 here; M1 activity leads hand velocity by
#: 120-180 ms (PNAS 10.1073/pnas.2212227120). A selected lag far outside 5-8 bins is a signal
#: that the alignment or the sign is wrong, not a discovery.
LAG_BINS_SWEEP: tuple[int, ...] = (0, 1, 2, 3, 4, 5, 6, 7, 8)

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
