"""REFIT-01 / 07-RESEARCH §6 row 2 — steady-state Kalman gain assertions.

Guards the load-bearing observability resolution (07-RESEARCH §2.3 / §3.1):

  * the steady-state gain solved on the OBSERVABLE 4-DOF block returns a 6×2 ``K`` whose position
    rows (0, 1) are exactly zero,
  * the closed-loop ``A_obs(I − K_obs·H_obs)`` is Schur-stable (``max|λ| < 1``),
  * the NEGATIVE CONTROL — a naive ``solve_discrete_are`` on the FULL 6×6 system (velocity-only
    measurement ⇒ position unobservable) RAISES — documenting WHY the observable-block path exists
    (threat T-07-01-01: a gain solved on the wrong system cannot pass these).

Deterministic (the shared ``conftest`` seeds numpy); pure linear algebra, no model, no data.
"""
from __future__ import annotations

import numpy as np
import pytest
from scipy import linalg as la

from ndt1.kalman_gain import (
    DT,
    MEAS_DIM,
    OBS_DIM,
    STATE_DIM,
    closed_loop_spectral_radius,
    full_measurement,
    full_transition,
    observable_blocks,
    observable_gain,
    steady_state_gain,
)


def _representative_noise() -> tuple[np.ndarray, np.ndarray]:
    """A representative ``(Q_obs, R)`` pair: PSD process noise + PD measurement noise."""
    q_obs = np.diag([1e-3, 1e-3, 1e-2, 1e-2])  # process noise on [vx,vy,ax,ay]
    r = np.diag([4e-2, 4e-2])                   # decoder velocity-residual noise on (vx,vy)
    return q_obs, r


def test_steady_state_gain_shape() -> None:
    """``steady_state_gain`` returns a full ``(6, 2)`` gain (REFIT-01)."""
    q_obs, r = _representative_noise()
    gain = steady_state_gain(q_obs, r)
    assert gain.shape == (STATE_DIM, MEAS_DIM) == (6, 2)


def test_position_rows_are_zero() -> None:
    """Rows 0 and 1 (px, py) of the gain are exactly zero — position is unobservable (§2.3)."""
    q_obs, r = _representative_noise()
    gain = steady_state_gain(q_obs, r)
    assert np.allclose(gain[0:2, :], 0.0)
    # The velocity/acceleration rows must NOT all be zero (the gain is real, not a degenerate zero).
    assert not np.allclose(gain[2:6, :], 0.0)


def test_closed_loop_is_schur_stable() -> None:
    """The closed-loop ``A_obs(I − K_obs·H_obs)`` is Schur-stable: ``max|λ| < 1`` (§3.1)."""
    q_obs, r = _representative_noise()
    k_obs = observable_gain(q_obs, r)
    eig_max = closed_loop_spectral_radius(k_obs)
    assert eig_max < 1.0, f"closed-loop spectral radius {eig_max} must be < 1"


def test_embedded_gain_matches_observable_block() -> None:
    """The 6×2 gain's rows 2..6 equal the 4×2 observable-block gain (clean embedding)."""
    q_obs, r = _representative_noise()
    k_obs = observable_gain(q_obs, r)
    gain = steady_state_gain(q_obs, r)
    assert np.allclose(gain[2:6, :], k_obs)


def test_full_6x6_dare_raises_negative_control() -> None:
    """NEGATIVE CONTROL: the FULL 6×6 ``solve_discrete_are`` is unsolvable and RAISES (§2.3).

    The velocity-only measurement leaves position unobservable, so the full-state DARE has no
    stabilizing solution — ``scipy`` raises ``LinAlgError`` ("stable subspace could not be
    isolated"). This is the structural trap (threat T-07-01-01): the observable-block path exists
    precisely because this solve cannot succeed.
    """
    a_full = full_transition()      # 6×6
    h_full = full_measurement()     # 2×6
    q_full = np.eye(STATE_DIM)      # any PSD 6×6 process noise
    r = np.eye(MEAS_DIM)            # any PD 2×2 measurement noise
    with pytest.raises((la.LinAlgError, np.linalg.LinAlgError, ValueError)):
        # Same dual substitution (a=A.T, b=H.T) — it is the UNOBSERVABILITY, not a wrong call,
        # that makes this fail.
        la.solve_discrete_are(a_full.T, h_full.T, q_full, r)


def test_multistep_trajectory_propagates_without_divergence() -> None:
    """≥50-tick steady-state filter trajectory stays finite (§6 row 1 propagation bar).

    Runs the constant-gain update ``x = A·x + K·(z − H·A·x)`` over a synthetic constant-velocity
    reach for 60 ticks and asserts the velocity estimate tracks the measurement and never diverges
    (NaN/Inf). Exercises propagation, not just a single step.
    """
    q_obs, r = _representative_noise()
    a_full = full_transition()
    h_full = full_measurement()
    gain = steady_state_gain(q_obs, r)

    rng = np.random.default_rng(0)
    true_velocity = np.array([0.5, -0.3])  # constant grid-units/s
    state = np.zeros(STATE_DIM)            # [px,py,vx,vy,ax,ay]
    n_ticks = 60
    last_vel_err = np.inf
    for _ in range(n_ticks):
        # Synthetic noisy velocity measurement around the true constant velocity.
        z = true_velocity + 0.02 * rng.standard_normal(MEAS_DIM)
        predicted = a_full @ state
        innovation = z - h_full @ predicted
        state = predicted + gain @ innovation
        assert np.all(np.isfinite(state)), "filter state diverged (NaN/Inf)"
        last_vel_err = float(np.linalg.norm(state[2:4] - true_velocity))

    # After convergence the velocity estimate tracks the constant true velocity to within the
    # measurement-noise scale (loose bound — this is a divergence/propagation guard, not a tuning
    # assertion).
    assert last_vel_err < 0.1, f"velocity estimate did not track true velocity: err={last_vel_err}"


def test_observable_blocks_have_expected_structure() -> None:
    """``observable_blocks`` returns ``A_obs = [[I, dt·I],[0,I]]`` and ``H_obs = [I, 0]`` (§2.3)."""
    a_obs, h_obs = observable_blocks()
    assert a_obs.shape == (OBS_DIM, OBS_DIM)
    assert h_obs.shape == (MEAS_DIM, OBS_DIM)
    # A_obs top-right velocity→acceleration coupling is dt·I.
    assert np.allclose(a_obs[0:2, 2:4], DT * np.eye(2))
    assert np.allclose(a_obs[0:2, 0:2], np.eye(2))
    assert np.allclose(a_obs[2:4, 0:2], 0.0)
    # H_obs selects velocity, not acceleration.
    assert np.allclose(h_obs[:, 0:2], np.eye(2))
    assert np.allclose(h_obs[:, 2:4], 0.0)


def test_full_transition_constant_acceleration_structure() -> None:
    """``full_transition`` carries dt velocity coupling and ½dt² acceleration coupling (§2.1)."""
    a_full = full_transition()
    assert a_full.shape == (STATE_DIM, STATE_DIM)
    half_dt_sq = 0.5 * DT * DT
    # px,py rows: I, dt·I, ½dt²·I across [pos | vel | acc].
    assert np.allclose(a_full[0:2, 0:2], np.eye(2))
    assert np.allclose(a_full[0:2, 2:4], DT * np.eye(2))
    assert np.allclose(a_full[0:2, 4:6], half_dt_sq * np.eye(2))
    # vx,vy rows: 0, I, dt·I.
    assert np.allclose(a_full[2:4, 2:4], np.eye(2))
    assert np.allclose(a_full[2:4, 4:6], DT * np.eye(2))


def test_malformed_noise_shapes_raise() -> None:
    """``observable_gain`` raises an explicit ``ValueError`` on a wrong-shaped Q/R."""
    q_obs, r = _representative_noise()
    with pytest.raises(ValueError):
        observable_gain(np.eye(3), r)     # wrong Q_obs shape
    with pytest.raises(ValueError):
        observable_gain(q_obs, np.eye(3))  # wrong R shape
