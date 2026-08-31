"""Firing-rate plausibility band for 20 ms-binned M1 threshold-crossing counts (D-02, RD-02d).

A misparsed session is the failure this phase most needs to catch automatically. It raises no
exception, it trains, and the co-bps it produces lands in an evidence artifact as if it meant
something. `firing_rate_stats` reduces a `(num_bins, 96)` binned count matrix to population
statistics; `band_violations` checks them against `PLAUSIBLE_BAND`. A factor-of-2 unit-aggregation
error, a transposed load, or a dereference that empties most channels falls outside the band and is
reported rather than published.

**The band is POPULATION statistics with an explicit dead-channel allowance, never a per-channel
assertion.** Six of 96 channels on `indy_20160630_01` are completely silent and nine more are under
1 Hz, so `assert (rates > 0.5).all()` fails on correctly parsed data and then gets loosened until it
asserts nothing (09-RESEARCH pitfall P6).

**The bounds are EMPIRICAL and are not a literature constant.** Their centre values were measured on
`indy_20160630_01` through this repo's own `ndt1.data.load_session` (09-RESEARCH section 3); their
width is judgment with generous margin. Research found no paper stating a canonical numeric Hz band
for macaque M1 threshold crossings that could be quoted as authoritative, so this docstring says so
rather than dressing the numbers up. The detection convention behind the observed rates is a single
negative threshold at -4.5x the per-electrode spike-band RMS, which is why threshold-crossing rates
run well above sorted single-unit rates.

**D-04: these are RAW spike counts, never per-session rate-normalized.** The Poisson NLL objective
and co-bps are both defined on actual counts, so normalizing would break the metric and its
comparability to Phase 4 and to NLB'21. Session heterogeneity is surfaced by reporting per-session
channel yield -- `dead_channels`, `sub_1hz_channels`, `live_channel_fraction` -- not by normalizing
it away.

A band violation is NOT an automatic exclusion. `ndt1.sessions.available_sessions` records the
violations on each loaded session and leaves the decision to the caller, because D-03 requires an
exclusion to be a documented decision rather than a silent drop.

No bare/blind `except`: this module raises, it does not catch.
"""
from __future__ import annotations

import numpy as np

_MS_PER_S: float = 1000.0

#: Empirical plausibility band for 20 ms-binned 96-channel M1 threshold-crossing counts.
#: Centre values MEASURED on indy_20160630_01 via ndt1.data.load_session (09-RESEARCH section 3);
#: the WIDTH is judgment with generous margin. These are POPULATION statistics with an explicit
#: dead-channel allowance -- a per-channel band fails on correctly-parsed data, because 6 of 96
#: channels are completely silent and 9 more are under 1 Hz (pitfall P6).
PLAUSIBLE_BAND: dict[str, tuple[float, float]] = {
    "mean_rate_hz":           (1.0, 60.0),    # observed 13.76
    "median_rate_hz":         (0.5, 40.0),    # observed 6.63
    "max_rate_hz":            (0.0, 200.0),   # observed 51.65; a hard physiological ceiling
    "live_channel_fraction":  (0.625, 1.0),   # observed 87/96 = 0.906; 60/96 is the floor
    "max_count_per_bin":      (0.0, 20.0),    # observed 5; >20 at 20 ms implies 1000 Hz
    "zero_fraction":          (0.3, 0.95),    # observed 0.787
}

#: A channel counts as live above this rate. Set below the lowest plausible real rate so that the
#: nine sub-1 Hz channels on indy_20160630_01 still count as live and only true silence is excluded.
LIVE_CHANNEL_RATE_HZ: float = 0.1

_BAND_SOURCE: str = "09-RESEARCH section 3, measured on indy_20160630_01"


def firing_rate_stats(binned: np.ndarray, *, bin_ms: float = 20.0) -> dict[str, float]:
    """Population firing-rate statistics for a (num_bins, num_channels) count matrix.

    Per-channel rate is `column_sum / duration_s` with `duration_s = num_bins * bin_ms / 1000`.

    `mean_rate_hz` is the mean over LIVE channels only (rate above `LIVE_CHANNEL_RATE_HZ`), so the
    silent tail does not drag it toward zero and hide a genuine rate collapse. `median_rate_hz` is
    the median over ALL channels, which is robust to that same dead tail without needing the
    liveness threshold at all. Reporting both makes a disagreement between them visible.

    Args:
        binned: a `(num_bins, num_channels)` spike-count matrix in time order.
        bin_ms: bin width in milliseconds (default 20 ms, matching `ndt1.data.BIN_MS`).

    Returns:
        A dict carrying every key named in `PLAUSIBLE_BAND` plus the per-session channel yield
        D-04 requires: `num_bins`, `num_channels`, `duration_s`, `mean_rate_hz`, `median_rate_hz`,
        `max_rate_hz`, `min_rate_hz`, `dead_channels`, `sub_1hz_channels`, `live_channels`,
        `live_channel_fraction`, `max_count_per_bin`, `zero_fraction`, `total_counts`.

    Raises:
        ValueError: if `binned` is not 2-D, has zero bins or zero channels, or `bin_ms` is not
            positive. Each of those would make a rate a division by zero or an empty reduction,
            and a nan flowing out of a quality gate is worse than no gate.
    """
    arr = np.asarray(binned, dtype=np.float64)
    if arr.ndim != 2:
        raise ValueError(
            f"binned must be 2-D (num_bins, num_channels), got shape {arr.shape} "
            f"({arr.ndim}-D)"
        )
    num_bins, num_channels = int(arr.shape[0]), int(arr.shape[1])
    if num_bins == 0:
        raise ValueError("binned has num_bins=0; there is no window to compute a rate over")
    if num_channels == 0:
        raise ValueError("binned has num_channels=0; there is no channel to compute a rate over")
    if bin_ms <= 0.0:
        raise ValueError(f"bin_ms must be positive, got {bin_ms}")

    duration_s = num_bins * bin_ms / _MS_PER_S
    per_channel_rate = arr.sum(axis=0) / duration_s
    live = per_channel_rate > LIVE_CHANNEL_RATE_HZ
    live_channels = int(np.count_nonzero(live))
    # An all-zero parse has no live channel and therefore no denominator. Report 0.0 rather than
    # dividing by zero -- 0.0 is itself outside the mean-rate bound, so the gate still bites.
    mean_rate_hz = float(per_channel_rate[live].mean()) if live_channels else 0.0

    return {
        "num_bins": num_bins,
        "num_channels": num_channels,
        "duration_s": duration_s,
        "mean_rate_hz": mean_rate_hz,
        "median_rate_hz": float(np.median(per_channel_rate)),
        "max_rate_hz": float(per_channel_rate.max()),
        "min_rate_hz": float(per_channel_rate.min()),
        "dead_channels": int(np.count_nonzero(per_channel_rate == 0.0)),
        "sub_1hz_channels": int(np.count_nonzero(per_channel_rate < 1.0)),
        "live_channels": live_channels,
        "live_channel_fraction": live_channels / num_channels,
        "max_count_per_bin": float(arr.max()),
        "zero_fraction": float(np.count_nonzero(arr == 0.0) / arr.size),
        "total_counts": float(arr.sum()),
    }


def band_violations(
    stats: dict[str, float], band: dict[str, tuple[float, float]] | None = None
) -> list[str]:
    """Return one human-readable message per violated bound; empty means the session is plausible.

    Args:
        stats: the output of `firing_rate_stats` (or any dict carrying every key in `band`).
        band: the bounds to check, `(lo, hi)` inclusive per key. Defaults to `PLAUSIBLE_BAND`.

    Returns:
        A list of messages, each naming the bound, the observed value and the allowed range, in
        `band` iteration order. An empty list means every bound held.

    Raises:
        KeyError: if a bound's statistic is absent from `stats`. A silently skipped bound is a gate
            that does not bite, which is the exact P6 failure mode this module exists to prevent.
    """
    bounds = PLAUSIBLE_BAND if band is None else band
    violations: list[str] = []
    for key, (low, high) in bounds.items():
        if key not in stats:
            raise KeyError(
                f"stats is missing {key!r}, which the plausibility band checks; a skipped bound "
                f"is a gate that does not bite ({_BAND_SOURCE})"
            )
        value = float(stats[key])
        if not low <= value <= high:
            violations.append(
                f"{key}={value:.4f} is outside the plausible band [{low}, {high}] ({_BAND_SOURCE})"
            )
    return violations
