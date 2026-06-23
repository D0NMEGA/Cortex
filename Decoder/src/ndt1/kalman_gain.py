"""REFIT-01 / Phase 7 — steady-state Kalman gain on the OBSERVABLE velocity+acceleration block.

The Phase-7 ReFIT-Kalman filter runs on the Swift side (post-CoreML) as a *constant-gain* filter:
the converged gain ``K`` is solved ONCE offline here, in the ``Decoder/`` uv subsystem, and emitted
as committed Swift constants (CONTEXT D-02 / D-15). The Swift hot path then loads constants only —
no Riccati at runtime — and the per-tick op is a few fixed ``simd`` mat-vecs.

State (CONTEXT D-01), grouped by derivative order, ``dt = 0.020 s`` (20 ms tick)::

    s = [px, py, vx, vy, ax, ay]ᵀ

Constant-acceleration transition ``A`` (6×6) and velocity-only measurement ``H`` (2×6), with
``I`` = 2×2 identity and ``0`` = 2×2 zero (07-RESEARCH §2.1)::

            ⎡ I   dt·I   ½dt²·I ⎤
    A (6×6)=⎢ 0   I      dt·I   ⎥        H (2×6) = [0  I  0]   ⇒  z = (vx, vy)
            ⎣ 0   0      I      ⎦

The load-bearing pitfall (07-RESEARCH §2.3): the 6-DOF state with a velocity-only measurement is
**not observable** — position is a pure integrator no measurement ever corrects, so the full 6×6
DARE has no stabilizing solution (``scipy.linalg.solve_discrete_are`` raises ``LinAlgError`` "stable
subspace could not be isolated"). Resolution: solve the steady-state gain on the **observable 4-DOF
``[vx, vy, ax, ay]`` sub-block** (which IS observable from a velocity measurement), embed ``K_obs``
(4×2) into the full **6×2 ``K`` with zero rows for ``px, py``** (position receives no measurement
correction — correct, it isn't measured), and sync the position state externally each tick (Swift
side, Wave 2). The 6-DOF *state* is retained end-to-end; only the *gain derivation* uses the block.

``scipy.linalg.solve_discrete_are(a, b, q, r)`` solves the **control-form** DARE
``AᴴXA − X − (AᴴXB)(R + BᴴXB)⁻¹(BᴴXA) + Q = 0`` (Context7-verified). The Kalman steady-state
**a-priori** covariance is the DUAL — substitute ``a → Aᵀ``, ``b → Hᵀ`` (07-RESEARCH §3.1).

House-style (mirrors ``velocity_head.py``): type hints on every public function; closed-form
linear algebra via ``np.linalg.solve`` where possible; **no bare/blind ``except``** (ruff ``BLE``
gate) — failures raise an explicit ``ValueError``.
"""
from __future__ import annotations

import numpy as np
from scipy import linalg as la

#: Filter tick in seconds — 20 ms (CONTEXT D-01). 50 Hz decode cadence.
DT: float = 0.020

#: Full kinematic state width ``[px, py, vx, vy, ax, ay]`` (CONTEXT D-01).
STATE_DIM: int = 6

#: Measurement width — the decoded ``(vx, vy)`` (07-RESEARCH §2.1).
MEAS_DIM: int = 2

#: Observable sub-block width ``[vx, vy, ax, ay]`` (07-RESEARCH §2.3).
OBS_DIM: int = 4


def full_transition() -> np.ndarray:
    """Return the 6×6 constant-acceleration transition ``A`` on ``[px,py,vx,vy,ax,ay]``.

    Block-upper-triangular constant-acceleration kinematics (07-RESEARCH §2.1)::

        [ I  dt·I  ½dt²·I ]
        [ 0  I     dt·I   ]
        [ 0  0     I      ]

    Returns:
        ``(6, 6)`` float64 transition matrix.
    """
    eye2 = np.eye(2)
    zero2 = np.zeros((2, 2))
    half = 0.5 * DT * DT
    return np.block(
        [
            [eye2, DT * eye2, half * eye2],
            [zero2, eye2, DT * eye2],
            [zero2, zero2, eye2],
        ]
    )


def full_measurement() -> np.ndarray:
    """Return the 2×6 velocity-only measurement ``H = [0 I 0]`` (measures ``(vx, vy)``).

    Returns:
        ``(2, 6)`` float64 measurement matrix (07-RESEARCH §2.1).
    """
    eye2 = np.eye(2)
    zero2 = np.zeros((2, 2))
    return np.block([[zero2, eye2, zero2]])


def observable_blocks() -> tuple[np.ndarray, np.ndarray]:
    """Return the observable 4-DOF sub-block ``(A_obs, H_obs)`` on ``[vx,vy,ax,ay]``.

    The velocity+acceleration block IS observable from a velocity measurement — its observability
    matrix ``[H_obs; H_obs·A_obs]`` has full rank 4 (07-RESEARCH §2.3)::

        A_obs (4×4) = ⎡ I   dt·I ⎤      H_obs (2×4) = [ I   0 ]
                      ⎣ 0   I    ⎦

    Returns:
        ``(A_obs, H_obs)`` — ``(4, 4)`` transition and ``(2, 4)`` measurement, both float64.
    """
    eye2 = np.eye(2)
    zero2 = np.zeros((2, 2))
    a_obs = np.block([[eye2, DT * eye2], [zero2, eye2]])
    h_obs = np.block([[eye2, zero2]])
    return a_obs, h_obs


def closed_loop_spectral_radius(k_obs: np.ndarray) -> float:
    """Return ``max|λ|`` of the closed-loop ``A_obs(I − K_obs·H_obs)`` on the observable block.

    The steady-state estimator is stable iff this spectral radius is ``< 1`` (Schur stability,
    07-RESEARCH §3.1). Exposed for the pytest so the assertion reads the same quantity the solver
    guards.

    Args:
        k_obs: ``(4, 2)`` gain on the observable block.

    Returns:
        The maximum absolute eigenvalue (float) of the closed-loop transition.

    Raises:
        ValueError: if ``k_obs`` is not shape ``(4, 2)``.
    """
    k_obs = np.asarray(k_obs, dtype=np.float64)
    if k_obs.shape != (OBS_DIM, MEAS_DIM):
        raise ValueError(
            f"closed_loop_spectral_radius expects K_obs shape ({OBS_DIM}, {MEAS_DIM}); "
            f"got {k_obs.shape}"
        )
    a_obs, h_obs = observable_blocks()
    closed = a_obs @ (np.eye(OBS_DIM) - k_obs @ h_obs)
    return float(np.max(np.abs(np.linalg.eigvals(closed))))


def observable_gain(q_obs: np.ndarray, r: np.ndarray) -> np.ndarray:
    """Solve the steady-state Kalman gain on the OBSERVABLE 4-DOF block (returns ``K_obs`` 4×2).

    Solves the dual (estimation-form) DARE for the a-priori covariance, then forms the gain
    ``K_obs = P⁻ Hᵀ (H P⁻ Hᵀ + R)⁻¹`` (07-RESEARCH §3.1). ``scipy.linalg.solve_discrete_are``
    solves the *control* form, so the a-priori estimation covariance is obtained by passing the
    transposes ``a = A_obsᵀ``, ``b = H_obsᵀ`` (Context7-verified signature
    ``solve_discrete_are(a, b, q, r)``).

    The closed-loop ``A_obs(I − K_obs·H_obs)`` is asserted Schur-stable (``max|λ| < 1``) — a gain
    solved on the wrong (unobservable) system cannot pass this (threat T-07-01-01).

    Args:
        q_obs: ``(4, 4)`` process-noise covariance on ``[vx,vy,ax,ay]`` (PSD).
        r: ``(2, 2)`` measurement-noise covariance on ``(vx, vy)`` (PD).

    Returns:
        ``(4, 2)`` steady-state Kalman gain on the observable block.

    Raises:
        ValueError: on a malformed ``q_obs``/``r`` shape, or if the closed loop is not Schur-stable.
    """
    q_obs = np.asarray(q_obs, dtype=np.float64)
    r = np.asarray(r, dtype=np.float64)
    if q_obs.shape != (OBS_DIM, OBS_DIM):
        raise ValueError(
            f"observable_gain expects Q_obs shape ({OBS_DIM}, {OBS_DIM}); got {q_obs.shape}"
        )
    if r.shape != (MEAS_DIM, MEAS_DIM):
        raise ValueError(
            f"observable_gain expects R shape ({MEAS_DIM}, {MEAS_DIM}); got {r.shape}"
        )

    a_obs, h_obs = observable_blocks()
    # scipy solves the CONTROL-form DARE; the Kalman a-priori covariance is the DUAL: pass the
    # transposes A_obs.T, H_obs.T (i.e. a=A_obs.T, b=H_obs.T) — 07-RESEARCH §3.1.
    p_pred = la.solve_discrete_are(a_obs.T, h_obs.T, q_obs, r)  # (4, 4) a-priori covariance
    innovation_cov = h_obs @ p_pred @ h_obs.T + r              # (2, 2) innovation covariance S
    # K_obs = P⁻ Hᵀ S⁻¹ — via np.linalg.solve on Sᵀ (never an explicit inverse): (S Kᵀ_factorᵀ)...
    # solve S Xᵀ = (P⁻ Hᵀ)ᵀ column-wise: equivalent to (P⁻ Hᵀ) @ inv(S) with a stable solve.
    k_obs = np.linalg.solve(innovation_cov.T, (p_pred @ h_obs.T).T).T  # (4, 2)

    eig_max = closed_loop_spectral_radius(k_obs)
    if not eig_max < 1.0:
        raise ValueError(f"closed-loop not Schur-stable: max|lambda|={eig_max:.6f} >= 1")
    return k_obs


def steady_state_gain(q_obs: np.ndarray, r: np.ndarray) -> np.ndarray:
    """Solve the steady-state gain on the observable block and embed it into the full ``6×2`` ``K``.

    Calls :func:`observable_gain` (which asserts Schur stability), then embeds ``K_obs`` into rows
    ``2..6`` (``vx,vy,ax,ay``) of a ``6×2`` matrix, leaving rows ``0,1`` (``px,py``) **exactly
    zero** — position receives no measurement correction (it is unobservable; 07-RESEARCH §2.3).

    Args:
        q_obs: ``(4, 4)`` process-noise covariance on ``[vx,vy,ax,ay]``.
        r: ``(2, 2)`` measurement-noise covariance on ``(vx, vy)``.

    Returns:
        ``(6, 2)`` steady-state Kalman gain with zero position rows (rows 0, 1).

    Raises:
        ValueError: on malformed inputs or a non-Schur-stable closed loop (via
            :func:`observable_gain`).
    """
    k_obs = observable_gain(q_obs, r)
    gain = np.zeros((STATE_DIM, MEAS_DIM))
    # Embed K_obs into rows 2..6 (the K[2:6, :] = K_obs step); rows 0,1 (px,py) stay exactly zero.
    gain[2:6, :] = k_obs  # zero position rows (0,1) -> 6×2
    return gain
