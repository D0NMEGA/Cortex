"""Unit tests for the kinematics layer: 250 Hz finite difference, 20 ms binning, whole-bin lag.

Every test runs on hand-built arrays or on the committed `tests/fixtures/tiny_v73.mat`, so the
module is green with `Decoder/data/` absent, and none is marked `slow`.

What the discriminating tests protect:

  D-07  the velocity is a plain finite difference at the native behavior rate, no smoothing filter
  D-08  "lag k" pairs the window ENDING at bin i with the velocity at bin i + k, which is the
        pairing `VelocityHead.forward`'s `rates[..., -1:]` static slice implies
  D-10  held-out R2 is scored against a constant TRAIN-split mean, never the test set's own mean
"""
from __future__ import annotations

import numpy as np
import pytest

from ndt1.data import bin_spikes
from ndt1.kinematics import (
    BEHAVIOR_HZ,
    LAG_BINS_SWEEP,
    apply_lag,
    bin_velocity,
    heldout_r2,
    lag_sweep_r2,
    planar_velocity_250hz,
)

_BIN_S: float = 0.020


def _clock(n: int, *, t_start: float = 0.0) -> np.ndarray:
    """A monotone behavior clock of `n` samples at the native 250 Hz rate."""
    return t_start + np.arange(n, dtype=np.float64) / BEHAVIOR_HZ


# --------------------------------------------------------------------- planar_velocity_250hz


def test_behavior_hz_is_250() -> None:
    """The native behavior sample rate constant is 250 Hz (median dt = 0.004 s)."""
    assert BEHAVIOR_HZ == 250.0


def test_linear_ramp_gives_constant_velocity() -> None:
    """x(t) = 3t, y(t) = -2t differentiates to a constant (3.0, -2.0) cm/s."""
    t = _clock(2500)
    pos = np.stack([3.0 * t, -2.0 * t], axis=1)
    vel = planar_velocity_250hz(pos, t)
    # Every interior sample, not just a spot check: a ramp has no interior structure to lose.
    np.testing.assert_allclose(vel[1:, 0], 3.0, atol=1e-9)
    np.testing.assert_allclose(vel[1:, 1], -2.0, atol=1e-9)


def test_velocity_row_count_matches_t() -> None:
    """The output has exactly `t.size` rows, so it stays index-aligned with the clock."""
    t = _clock(777)
    pos = np.stack([t**2, np.sin(t)], axis=1)
    vel = planar_velocity_250hz(pos, t)
    assert vel.shape == (t.size, 2)
    # The first row repeats the second's velocity — the backward difference is undefined at t[0].
    np.testing.assert_allclose(vel[0], vel[1])


def test_non_monotone_clock_raises() -> None:
    """A backwards step in `t` raises rather than producing a negative or infinite velocity."""
    t = _clock(50)
    t[20] = t[19] - 0.001
    pos = np.zeros((t.size, 2), dtype=np.float64)
    with pytest.raises(ValueError, match="monotone"):
        planar_velocity_250hz(pos, t)


def test_duplicate_timestamp_raises() -> None:
    """A repeated timestamp (dt == 0) raises rather than dividing by zero."""
    t = _clock(50)
    t[30] = t[29]
    pos = np.zeros((t.size, 2), dtype=np.float64)
    with pytest.raises(ValueError, match="monotone"):
        planar_velocity_250hz(pos, t)


def test_shape_mismatch_raises() -> None:
    """A three-column `planar_cm` raises: the planar pair must already have been selected."""
    t = _clock(50)
    with pytest.raises(ValueError, match="planar_cm"):
        planar_velocity_250hz(np.zeros((t.size, 3), dtype=np.float64), t)


# ------------------------------------------------------------------------------ bin_velocity


@pytest.mark.parametrize("n_samples", [751, 750])
def test_bin_count_matches_bin_spikes(n_samples: int) -> None:
    """`bin_velocity` and `bin_spikes` produce the SAME row count for the same window.

    This is the row-alignment contract the whole velocity path rests on: the rates matrix and the
    velocity matrix are paired by row index, so a one-row disagreement silently shifts every label
    by 20 ms. `n_samples=751` spans exactly 3.0 s (a whole number of bins); `n_samples=750` spans
    2.996 s, so the trailing partial bin is dropped by both.
    """
    t = _clock(n_samples)
    t_start, t_end = float(t[0]), float(t[-1])
    vel = np.zeros((t.size, 2), dtype=np.float64)

    binned = bin_spikes(
        [np.empty(0, dtype=np.float64) for _ in range(96)],
        num_channels=96,
        t_start=t_start,
        t_end=t_end,
    )
    velocity_bins = bin_velocity(vel, t, t_start=t_start, t_end=t_end)

    assert velocity_bins.shape[0] == binned.shape[0]
    assert velocity_bins.shape == (int(np.floor((t_end - t_start) / _BIN_S)), 2)


def test_constant_velocity_survives_binning() -> None:
    """Mean-aggregating a constant velocity returns that same constant in every bin."""
    t = _clock(1251)
    vel = np.tile(np.array([1.5, -2.5]), (t.size, 1))
    binned = bin_velocity(vel, t, t_start=float(t[0]), t_end=float(t[-1]))
    np.testing.assert_allclose(binned[:, 0], 1.5)
    np.testing.assert_allclose(binned[:, 1], -2.5)


def test_bin_with_no_samples_raises() -> None:
    """An empty 20 ms bin raises and NAMES the bin index rather than emitting a NaN.

    At 250 Hz there are ~5 behavior samples per 20 ms bin, so an empty bin means the spike clock
    and the behavior clock disagree. A NaN here would poison the ridge fit silently (T-09-03-01).
    """
    # Bin 0 = [0.000, 0.020) has 5 samples, bin 1 = [0.020, 0.040) has NONE, bin 2 has 3.
    t = np.array([0.000, 0.004, 0.008, 0.012, 0.016, 0.040, 0.044, 0.048], dtype=np.float64)
    vel = np.ones((t.size, 2), dtype=np.float64)
    with pytest.raises(ValueError, match=r"bin 1\b"):
        bin_velocity(vel, t, t_start=0.0, t_end=0.060)


def test_bin_velocity_rejects_mismatched_rows() -> None:
    """`vel` and `t` must carry the same number of samples."""
    t = _clock(100)
    with pytest.raises(ValueError):
        bin_velocity(np.zeros((99, 2)), t, t_start=float(t[0]), t_end=float(t[-1]))


# --------------------------------------------------------------------------------- apply_lag


def test_lag_sweep_constant_spans_zero_to_160_ms() -> None:
    """The D-08 sweep is whole 20 ms bins over 0-160 ms, bracketing nlb_tools' 140 ms at bin 7."""
    assert LAG_BINS_SWEEP == (0, 1, 2, 3, 4, 5, 6, 7, 8)
    assert LAG_BINS_SWEEP[-1] * 20 == 160


def test_apply_lag_zero_is_identity() -> None:
    """Lag 0 returns both arrays unchanged."""
    rng = np.random.default_rng(0)
    rates = rng.normal(size=(120, 96))
    vel = rng.normal(size=(120, 2))
    out_rates, out_vel = apply_lag(rates, vel, 0)
    np.testing.assert_array_equal(out_rates, rates)
    np.testing.assert_array_equal(out_vel, vel)


def test_apply_lag_seven_drops_seven_rows() -> None:
    """Lag 7 pairs the window ending at bin i with the velocity at bin i + 7, dropping the tail."""
    rng = np.random.default_rng(1)
    rates = rng.normal(size=(120, 96))
    vel = rng.normal(size=(120, 2))
    out_rates, out_vel = apply_lag(rates, vel, 7)
    assert out_rates.shape == (113, 96)
    assert out_vel.shape == (113, 2)
    np.testing.assert_array_equal(out_rates[0], rates[0])
    np.testing.assert_array_equal(out_vel[0], vel[7])
    np.testing.assert_array_equal(out_vel[-1], vel[119])


def test_apply_lag_rejects_negative_and_oversized() -> None:
    """A negative lag, or one that consumes every row, raises instead of returning empty arrays."""
    rates = np.zeros((10, 96))
    vel = np.zeros((10, 2))
    with pytest.raises(ValueError):
        apply_lag(rates, vel, -1)
    with pytest.raises(ValueError):
        apply_lag(rates, vel, 10)


# -------------------------------------------------------------------------------- heldout_r2


def test_perfect_prediction_is_one() -> None:
    """A prediction equal to the truth scores 1.0 on both axes and pooled."""
    rng = np.random.default_rng(0)
    y = rng.normal(size=(500, 2)) * np.array([1.0, 10.0])
    scores = heldout_r2(y, y, y.mean(axis=0))
    assert scores["vx"] == pytest.approx(1.0)
    assert scores["vy"] == pytest.approx(1.0)
    assert scores["pooled"] == pytest.approx(1.0)
    assert scores["n"] == 500


def test_null_prediction_is_zero() -> None:
    """Predicting the constant train mean scores exactly 0.0 -- the definition of the null."""
    rng = np.random.default_rng(2)
    y = rng.normal(size=(400, 2))
    train_mean = y.mean(axis=0)
    scores = heldout_r2(y, np.broadcast_to(train_mean, y.shape), train_mean)
    assert scores["vx"] == pytest.approx(0.0, abs=1e-12)
    assert scores["vy"] == pytest.approx(0.0, abs=1e-12)
    assert scores["pooled"] == pytest.approx(0.0, abs=1e-12)


def test_worse_than_null_is_negative_and_unclamped() -> None:
    """A readout worse than the null reports a NEGATIVE R2 at full magnitude (D-25, T-09-03-05).

    Clamping to 0 would turn "this readout is worse than predicting the average" into "this
    readout explains none of the variance", which reads as a much smaller failure than it is.
    """
    rng = np.random.default_rng(3)
    y = rng.normal(size=(400, 2))
    train_mean = y.mean(axis=0)
    pred = np.broadcast_to(train_mean, y.shape) + 100.0
    scores = heldout_r2(y, pred, train_mean)
    assert scores["vx"] < 0.0
    assert scores["vy"] < 0.0
    # Unclamped: a 100 cm/s constant offset against unit-variance truth lands near -10,000, not
    # at 0.0 and not at -1.0.
    assert scores["pooled"] < -1000.0


def test_pooled_is_not_the_mean_of_axes() -> None:
    """Pooled R2 is 1 - sum SS_res / sum SS_tot, NOT the average of the two per-axis values.

    Built so the two definitions cannot agree: vy carries 100x the variance of vx, and the
    prediction is perfect on vx and exactly the null on vy. Averaging the axes would report 0.5;
    the honest variance-weighted figure is near 0.01, because the axis that was not decoded is
    the axis that carries the signal.
    """
    rng = np.random.default_rng(4)
    n = 400
    y = np.stack([rng.normal(0.0, 1.0, n), rng.normal(0.0, 10.0, n)], axis=1)
    train_mean = y.mean(axis=0)
    pred = np.empty_like(y)
    pred[:, 0] = y[:, 0]
    pred[:, 1] = train_mean[1]

    scores = heldout_r2(y, pred, train_mean)
    assert scores["vx"] == pytest.approx(1.0)
    assert scores["vy"] == pytest.approx(0.0, abs=1e-12)
    mean_of_axes = (scores["vx"] + scores["vy"]) / 2.0
    assert abs(scores["pooled"] - mean_of_axes) > 1e-6
    assert scores["pooled"] < 0.1


def test_train_mean_null_differs_from_test_mean_null() -> None:
    """The P8 / D-10 control: the test set's own mean is a DIFFERENT, easier claim.

    Within-session drift is real here -- measured at -8.1% in mean rate from the train head to
    the test tail on indy_20160630_01 -- and it is the direction that inflates a train-null
    score. If heldout_r2 ever silently recomputed the null from y_true, the two calls below would
    return the same number and this assertion would stop biting.
    """
    rng = np.random.default_rng(5)
    n = 300
    train = rng.normal(0.0, 1.0, size=(n, 2))
    test = rng.normal(0.0, 1.0, size=(n, 2)) + np.array([4.0, -3.0])  # the tail has drifted
    pred = test + rng.normal(0.0, 0.5, size=(n, 2))

    against_train_null = heldout_r2(test, pred, train.mean(axis=0))["pooled"]
    against_test_null = heldout_r2(test, pred, test.mean(axis=0))["pooled"]

    assert abs(against_train_null - against_test_null) > 1e-6
    # The drift inflates SS_tot under the train null, so that is the FLATTERING of the two.
    assert against_train_null > against_test_null


def test_constant_axis_raises() -> None:
    """A constant held-out axis makes SS_tot zero; R2 against a mean null is then undefined."""
    y = np.stack([np.linspace(0.0, 1.0, 50), np.full(50, 2.5)], axis=1)
    with pytest.raises(ValueError, match="constant"):
        heldout_r2(y, y, np.array([0.5, 2.5]))


def test_heldout_r2_rejects_bad_shapes() -> None:
    """Mismatched row counts, a wrong axis width and a wrong train_mean shape all raise."""
    y = np.zeros((10, 2))
    with pytest.raises(ValueError):
        heldout_r2(y, np.zeros((9, 2)), np.zeros(2))
    with pytest.raises(ValueError):
        heldout_r2(y, y, np.zeros(3))
    with pytest.raises(ValueError):
        heldout_r2(np.zeros((10, 3)), np.zeros((10, 3)), np.zeros(3))


# ------------------------------------------------------------------------------ lag_sweep_r2


def test_lag_sweep_returns_full_curve() -> None:
    """The FULL curve is returned, not only the argmax -- D-08 publishes the whole sweep."""
    rng = np.random.default_rng(7)
    rates = rng.normal(size=(300, 96))
    vel = rng.normal(size=(300, 2))
    curve = lag_sweep_r2(rates, vel)
    assert len(curve) == len(LAG_BINS_SWEEP)
    for entry, lag in zip(curve, LAG_BINS_SWEEP, strict=True):
        assert set(entry) == {"lag_bins", "lag_ms", "train_r2", "lambda"}
        assert entry["lag_bins"] == lag
        assert entry["lag_ms"] == lag * 20.0
        assert entry["lambda"] == 1.0


def test_lag_sweep_recovers_a_planted_lag() -> None:
    """A velocity that is a linear function of the rates shifted by 5 bins peaks at lag 5.

    This is what proves the pairing convention matches VelocityHead's `rates[..., -1:]` geometry:
    an off-by-one or a reversed slice in `apply_lag` moves the argmax off the planted value.
    """
    rng = np.random.default_rng(11)
    n, planted = 900, 5
    rates = rng.normal(size=(n, 96))
    w_true = rng.normal(size=(2, 96)) / np.sqrt(96.0)
    latent = rates @ w_true.T
    vel = np.empty((n, 2))
    vel[planted:] = latent[: n - planted]  # vel[i + planted] is a linear function of rates[i]
    vel[:planted] = rng.normal(size=(planted, 2))  # the unpaired head, deliberately unrelated

    curve = lag_sweep_r2(rates, vel)
    best = max(curve, key=lambda entry: entry["train_r2"])
    assert best["lag_bins"] == planted
    assert best["train_r2"] > 0.99
