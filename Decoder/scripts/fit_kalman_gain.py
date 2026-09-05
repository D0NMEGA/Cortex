#!/usr/bin/env python3
"""REFIT-01 / D-15 — fit Q/R, solve the steady-state Kalman gain, EMIT ``KalmanConstants.swift``.

This is the offline half of the Phase-7 ReFIT-Kalman filter (CONTEXT D-02 / D-15). It:

  1. Builds ``Q_obs`` (4×4 process noise on ``[vx,vy,ax,ay]``) and ``R`` (2×2 measurement noise on
     ``(vx,vy)``) — from **held-out Indy residual statistics** when the gitignored R&D data is
     present, otherwise from **documented, seeded defaults** (07-RESEARCH §3.2).
  2. Solves the steady-state gain on the OBSERVABLE block via
     :func:`ndt1.kalman_gain.steady_state_gain` (asserts Schur stability; zeros position rows).
  3. Writes the committed Swift constants file
     ``Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift`` (the code-gen TARGET; Task 2
     owns the matching ``KalmanConstants`` Swift struct layout — this script writes literal values
     into that shape).

Q/R fitting recipe (07-RESEARCH §3.2, units fixed by 10-PREREGISTRATION §4 and §5):
  * **R** (2×2): covariance of the decoder residual ``e_k = z_decoded − v_true`` on the held-out
    chronological tail of the locked session — how noisy the NDT1 velocity readout is. Computed in
    **grid-units/s**, the units the Swift filter runs in, NOT cm/s: the two differ by
    ``grid_units_per_cm²``, which for this workspace is a factor of about 295.
  * **Q** (4×4 on ``[v,a]``): a discrete **white-noise-jerk** model whose ``σ_jerk²`` is the
    variance of the second difference of the true binned velocity on the same held-out rows,
    also in grid units.

RD-07 / Plan 10-03 note. Through Phase 9 this script could NOT fit from data: both branches of
``fit_noise`` returned ``default_noise``, so the committed header said ``noise source = default``
even when ``--data-dir`` pointed at the real sessions (10-RESEARCH Correction 1). The data-present
branch below is the implementation of that missing path; the generated provenance header, not the
fact that the script ran, is the evidence the fit happened (10-RESEARCH Pitfall 1).

The decoder whose residual is measured is the SHIPPED one: the Phase-9 pooled encoder plus the
pooled ridge readout stored in ``Decoder/checkpoints/ndt1_real_with_velocity.pt``, applied to the
held-out tail this readout never saw. That is the same decoder and the same rows whose held-out R2
``09-decoder-metrics.json`` publishes, so R describes the noise of the decoder that actually ships
rather than of a readout re-fit here and never deployed.

When the held-out Indy artifacts are absent (the gitignored ``Decoder/data/`` is not present),
the script does NOT crash: it falls back to the documented default Q/R below, prints a clear note,
and records the seed/source in the generated file's header (mirrors the bench "skip cleanly when
artifacts absent" idiom; threat T-07-01-03 — the fallback is deterministic). A data dir that EXISTS
but is missing the session or the checkpoints raises instead of falling back: a silent fallback
there is precisely the defect Plan 10-03 exists to remove. Everything is seeded (``--seed``,
default 0); there is no unseeded RNG.

Usage::

    uv run --project Decoder --extra dev python Decoder/scripts/fit_kalman_gain.py
    uv run --project Decoder python Decoder/scripts/fit_kalman_gain.py \\
        --data-dir Decoder/data --session indy_20160630_01 \\
        --out Packages/CortexReFIT/Sources/CortexReFIT/KalmanConstants.swift

No bare/blind ``except`` (ruff ``BLE`` gate): only the specific data-absent path is branched on a
``Path.exists`` check, and every other failure raises an explicit error.
"""
from __future__ import annotations

import argparse
import json
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ndt1.kalman_gain import (
    DT,
    MEAS_DIM,
    OBS_DIM,
    full_measurement,
    full_transition,
    steady_state_gain,
)
from ndt1.replay_export import workspace_from_cursor

# Repo-relative paths (this file lives at Decoder/scripts/fit_kalman_gain.py).
_DECODER_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = _DECODER_ROOT.parent
_DEFAULT_DATA_DIR = _DECODER_ROOT / "data"  # gitignored R&D Indy .mat home (DEC-02 downloader)
#: The code-gen TARGET — the committed Swift constants file consumed by the CortexReFIT package.
KALMAN_CONSTANTS_SWIFT = (
    _REPO_ROOT / "Packages" / "CortexReFIT" / "Sources" / "CortexReFIT" / "KalmanConstants.swift"
)

# ---------------------------------------------------------------------------
# Documented DEFAULT Q/R (used when held-out Indy artifacts are absent — 07-RESEARCH §3.2).
#
# These are deterministic, reviewer-defensible seeds (NOT zeros): a white-noise-jerk process model
# on the observable [vx,vy,ax,ay] block and a diagonal decoder-noise floor. They are recorded as the
# "source: default" provenance in the generated Swift header so a reader knows the gain was not fit
# to real residuals on this run.

#: Default jerk PSD σ_jerk² (grid-units/s³)² — the white-noise-jerk intensity driving acceleration.
_DEFAULT_SIGMA_JERK_SQ: float = 1.0

#: Default per-axis decoder velocity-residual variance (grid-units/s)² — the measurement-noise floor
#: (a documented stand-in for the held-out ``cov(z_decoded − v_true)`` diagonal; 07-RESEARCH §3.2).
_DEFAULT_R_VAR: float = 0.25

# ---------------------------------------------------------------------------
# The held-out residual fit (RD-07; conventions pre-registered in 10-PREREGISTRATION §3, §4, §5
# BEFORE this code ran, so none of them could be chosen after seeing a number).

#: Millimetres per centimetre, and therefore the cursor-frame/finger-frame relation: the session's
#: own ``cursor_pos`` is ``10 × planar_cm`` to R² 0.99997 with an offset under 0.03 mm
#: (10-RESEARCH "the cursor frame is the finger frame times ten"). Not a fitted constant.
#:
#: It is the 10.0 in ``k = 10.0 / side_mm`` (§4 step 2). It is NOT what defines the box: §3a boxes
#: the RECORDED ``cursor_pos`` track, because the relation's fitted slope is 10.005 and a box built
#: through it does not contain the track it is supposed to bound.
GRID_MM_PER_CM: float = 10.0

#: The replayed session, locked by CONTEXT D-08 before any Phase-10 outcome was known.
DEFAULT_SESSION: str = "indy_20160630_01"

#: Neural-to-kinematic lag in 20 ms bins, and the ridge strength the SHIPPED readout was fit at.
#: Both are Phase-9 outcomes locked by 10-PREREGISTRATION §2; they are re-read from
#: ``09-decoder-metrics.json`` at fit time so the emitted header cannot record a lag or a lambda
#: the deployed readout was not actually fit with.
LAG_BINS: int = 1
RIDGE_LAMBDA: float = 0.1

#: Millimetres of disagreement tolerated between this module's §3 arithmetic and Plan 10-02's
#: exporter. Both are exact bounding-box maxima over the same float64 track, so anything above
#: float noise means the two definitions of the box have genuinely diverged.
_SIDE_MM_TOL: float = 1e-6

_SCRIPTS_DIR = Path(__file__).resolve().parent
_PHASE_09_METRICS = (
    _REPO_ROOT
    / ".planning"
    / "phases"
    / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
    / "09-decoder-metrics.json"
)


@dataclass(frozen=True)
class NoiseFit:
    """The fitted (or defaulted) process/measurement noise + its provenance.

    Attributes:
        q_obs: ``(4, 4)`` process-noise covariance on ``[vx,vy,ax,ay]``.
        r: ``(2, 2)`` measurement-noise covariance on ``(vx, vy)``.
        source: ``"default"`` (no Indy data) or ``"indy-heldout"`` (fit to residuals).
        seed: the RNG seed used (recorded for reproducibility — threat T-07-01-03).
        note: a one-line human description for the generated-file header.
    """

    q_obs: np.ndarray
    r: np.ndarray
    source: str
    seed: int
    note: str


def white_noise_jerk_q(sigma_jerk_sq: float, dt: float = DT) -> np.ndarray:
    """Return the 4×4 discrete white-noise-jerk process covariance on ``[vx,vy,ax,ay]``.

    The standard discrete white-noise-jerk model for a [velocity, acceleration] block driven by a
    continuous white jerk of PSD ``σ_jerk²`` (07-RESEARCH §3.2). Per 2-D axis the 2×2 block is::

        Q_axis = σ_jerk² · ⎡ dt⁴/4   dt³/2 ⎤
                           ⎣ dt³/2   dt²   ⎦

    laid out across the interleaved ``[vx,vy,ax,ay]`` ordering (so velocity and acceleration each
    span two axes). The result is symmetric PSD.

    Args:
        sigma_jerk_sq: jerk PSD ``σ_jerk²`` ≥ 0.
        dt: tick in seconds (default :data:`ndt1.kalman_gain.DT` = 0.020).

    Returns:
        ``(4, 4)`` float64 process-noise covariance.

    Raises:
        ValueError: if ``sigma_jerk_sq`` is negative.
    """
    if sigma_jerk_sq < 0.0:
        raise ValueError(f"sigma_jerk_sq must be >= 0; got {sigma_jerk_sq}")
    q_vv = sigma_jerk_sq * (dt**4) / 4.0
    q_va = sigma_jerk_sq * (dt**3) / 2.0
    q_aa = sigma_jerk_sq * (dt**2)
    eye2 = np.eye(2)
    # Block layout on [v(2), a(2)]: [[q_vv·I, q_va·I], [q_va·I, q_aa·I]].
    return np.block([[q_vv * eye2, q_va * eye2], [q_va * eye2, q_aa * eye2]])


def default_noise(seed: int) -> NoiseFit:
    """Return the documented DEFAULT Q/R (used when held-out Indy data is absent).

    Deterministic — no RNG draw is actually needed, but the seed is recorded for provenance so the
    fallback path is honestly traceable (threat T-07-01-03).

    Args:
        seed: the seed to record in the provenance.

    Returns:
        A :class:`NoiseFit` with ``source == "default"``.
    """
    q_obs = white_noise_jerk_q(_DEFAULT_SIGMA_JERK_SQ)
    r = _DEFAULT_R_VAR * np.eye(MEAS_DIM)
    note = (
        f"DEFAULT Q/R (held-out Indy data absent): white-noise-jerk sigma_jerk^2="
        f"{_DEFAULT_SIGMA_JERK_SQ}, R=diag({_DEFAULT_R_VAR}) per axis. Re-run with --data-dir "
        f"pointing at downloaded Indy .mat to fit R from decoder residuals (07-RESEARCH 3.2)."
    )
    return NoiseFit(q_obs=q_obs, r=r, source="default", seed=seed, note=note)


def to_grid_units(v_cm_s: np.ndarray, side_mm: float) -> np.ndarray:
    """Convert a velocity from cm/s to GRID-UNITS/s (10-PREREGISTRATION §4 step 2).

    One grid unit spans the whole ``side_mm``-millimetre workspace box, and a centimetre is
    :data:`GRID_MM_PER_CM` millimetres, so the scale factor is ``k = 10.0 / side_mm`` grid-units per
    centimetre. R and Q are fit in these units because the Swift filter runs in them; a residual fit
    in cm/s and normalised afterwards is wrong by ``k²``.

    Args:
        v_cm_s: any array of velocities in centimetres per second.
        side_mm: the workspace box side in millimetres (see :func:`workspace_side_mm`).

    Returns:
        The same array in grid-units per second, as float64.

    Raises:
        ValueError: if ``side_mm`` is not positive.
    """
    if not float(side_mm) > 0.0:
        raise ValueError(f"side_mm must be positive; got {side_mm}")
    return np.asarray(v_cm_s, dtype=np.float64) * (GRID_MM_PER_CM / float(side_mm))


def residual_covariance(decoded: np.ndarray, true: np.ndarray) -> np.ndarray:
    """Return the 2×2 sample covariance of ``decoded − true`` (mean-centered, ``ddof=1``).

    This is R before the diagonal is taken. 10-PREREGISTRATION §4 step 3 says ``cov``, i.e. about
    the mean, so a systematic decoder bias does NOT inflate R; the residual mean is published in the
    provenance note and in the evidence artifact instead of being folded in silently.

    Args:
        decoded: ``(n, 2)`` decoded velocity.
        true: ``(n, 2)`` true velocity on the same rows and in the same units.

    Returns:
        ``(2, 2)`` covariance of the residual.

    Raises:
        ValueError: on mismatched shapes, a non-2-column array, or fewer than 2 rows.
    """
    decoded = np.asarray(decoded, dtype=np.float64)
    true = np.asarray(true, dtype=np.float64)
    if decoded.shape != true.shape:
        raise ValueError(
            f"decoded {decoded.shape} and true {true.shape} must be the same shape; a mismatch "
            f"means the two tracks are not row-aligned and the residual would pair unrelated bins"
        )
    if decoded.ndim != 2 or decoded.shape[1] != MEAS_DIM:
        raise ValueError(f"expected (n, {MEAS_DIM}) velocity arrays; got {decoded.shape}")
    if decoded.shape[0] < 2:
        raise ValueError(f"need at least 2 rows for a sample covariance; got {decoded.shape[0]}")
    resid = decoded - true
    centered = resid - resid.mean(axis=0)
    return centered.T @ centered / float(resid.shape[0] - 1)


def jerk_variance(true_grid_s: np.ndarray, dt: float = DT) -> float:
    """Return ``σ_jerk²`` implied by a velocity track: the variance of ``diff²(v) / dt²``.

    The filter's ``A`` is constant-acceleration, so jerk is the second derivative of velocity and
    its discrete estimate is ``(v[k+2] − 2v[k+1] + v[k]) / dt²`` in grid-units/s³. Averaged over the
    two axes because :func:`white_noise_jerk_q` takes one isotropic scalar (10-PREREGISTRATION §5).

    Args:
        true_grid_s: ``(n, 2)`` true velocity in GRID-UNITS/s (convert first — the units matter).
        dt: tick in seconds.

    Returns:
        The mean per-axis jerk variance, in ``(grid-units/s³)²``.

    Raises:
        ValueError: on a non-2-column array or fewer than 3 rows.
    """
    velocity = np.asarray(true_grid_s, dtype=np.float64)
    if velocity.ndim != 2 or velocity.shape[1] != MEAS_DIM:
        raise ValueError(f"expected (n, {MEAS_DIM}) velocity array; got {velocity.shape}")
    if velocity.shape[0] < 3:
        raise ValueError(f"a second difference needs at least 3 rows; got {velocity.shape[0]}")
    jerk = np.diff(velocity, n=2, axis=0) / (float(dt) * float(dt))
    return float(np.mean(np.var(jerk, axis=0)))


def closed_loop_rho(q_obs: np.ndarray, r: np.ndarray) -> float:
    """Spectral radius of ``(I − K_obs·H_obs)·A_obs`` on the OBSERVABLE ``[vx,vy,ax,ay]`` block.

    Restricted to the observable block on purpose (review D-7): K's position rows are zero by
    construction, so the full 6×6 closed loop keeps ``A``'s position integrators and has spectral
    radius exactly 1 BY DESIGN — a full-matrix stability check would fail on a correct gain. Indices
    2..5 are the block :func:`~ndt1.kalman_gain.steady_state_gain` itself solves.

    :func:`~ndt1.kalman_gain.observable_gain` already refuses to return a non-Schur gain, so this
    function exists to RECORD the number in the generated header rather than to re-check it: a
    string in a committed file is auditable months later, a transient assertion is not.

    Args:
        q_obs: ``(4, 4)`` process-noise covariance on ``[vx,vy,ax,ay]``.
        r: ``(2, 2)`` measurement-noise covariance on ``(vx, vy)``.

    Returns:
        ``max|λ|`` of the closed-loop observable block.

    Raises:
        ValueError: propagated from the solver when the pair does not stabilize.
    """
    a_obs = full_transition()[2:6, 2:6]
    h_obs = full_measurement()[:, 2:6]
    k_obs = steady_state_gain(q_obs, r)[2:6, :]
    closed = (np.eye(OBS_DIM) - k_obs @ h_obs) @ a_obs
    return float(np.max(np.abs(np.linalg.eigvals(closed))))


def workspace_side_mm(cursor_mm: np.ndarray) -> float:
    """Side of the pre-registered ``cursor_bbox_square`` workspace box, in millimetres.

    10-PREREGISTRATION §3 as amended by §3a: take the axis-aligned bounding box of the session's
    RECORDED ``cursor_pos`` track over the WHOLE session, and use ``side_mm = max(width, height)``.
    Square, so one grid unit is the same physical distance on both axes.

    This is a CROSS-CHECK, not the authority. ``ndt1.replay_export.workspace_from_cursor`` is the
    one authoritative implementation of the box (§3a); :func:`_resolve_side_mm` returns ITS value
    and uses this arithmetic only to catch a divergence. Keeping a second, independent restatement
    of the rule is what turned the §3 ambiguity into a loud failure instead of a silent 0.7 percent
    error in R, so it stays.

    Args:
        cursor_mm: ``(n, 2)`` RECORDED cursor track in millimetres. NOT a centimetre finger track:
            §3a removed the ``× 10`` that used to live inside this function.

    Returns:
        The longer bounding-box side, in millimetres.

    Raises:
        ValueError: on a non-2-column array or an empty track.
    """
    cursor = np.asarray(cursor_mm, dtype=np.float64)
    if cursor.ndim != 2 or cursor.shape[1] != 2:
        raise ValueError(f"expected an (n, 2) cursor track in mm; got {cursor.shape}")
    if cursor.shape[0] == 0:
        raise ValueError("cannot bound an empty track")
    spans = cursor.max(axis=0) - cursor.min(axis=0)
    return float(spans.max())


def _resolve_side_mm(cursor_mm: np.ndarray) -> tuple[float, str]:
    """``(side_mm, source_label)`` from the authoritative box, cross-checked against §3 here.

    ``ndt1.replay_export.workspace_from_cursor`` is authoritative and its value is what is
    returned. :func:`workspace_side_mm` restates 10-PREREGISTRATION §3 independently and a
    disagreement RAISES: two implementations of the same pre-registered box that quietly diverge
    would normalise R by different constants, and the difference is a factor of ``k²``. That trap
    is not decorative -- it is what fires if anything ever puts a centimetre track back into this
    path, which is exactly the defect §3a corrects.
    """
    local = workspace_side_mm(cursor_mm)
    exported = float(workspace_from_cursor(cursor_mm)["side_mm"])
    if abs(exported - local) > _SIDE_MM_TOL:
        raise ValueError(
            f"ndt1.replay_export.workspace_from_cursor reports side_mm={exported!r} but the "
            f"10-PREREGISTRATION section 3 arithmetic gives {local!r}; the two definitions of the "
            f"cursor_bbox_square box have diverged and R would be normalised by the wrong constant"
        )
    # One space-free token on purpose: the label lands in the generated Swift provenance header,
    # which is wrapped at 110 columns, and a label with spaces in it wraps across two comment lines
    # (the same reason `render_swift` disables hyphen breaking).
    return exported, "ndt1.replay_export.workspace_from_cursor+section-3a-cross-check"


def _phase09_velocity_record() -> dict[str, object]:
    """The Phase-9 ``velocity`` metrics block, or ``{}`` when the JSON is absent.

    Read so the header's ``lag_bins`` and ``lambda`` describe how the SHIPPED readout was actually
    fit rather than restating a constant, and so the checkpoint whose residual is measured can be
    matched against the one that produced the published held-out R2.
    """
    if not _PHASE_09_METRICS.is_file():
        return {}
    payload = json.loads(_PHASE_09_METRICS.read_text(encoding="utf-8"))
    record = payload.get("velocity", {})
    return record if isinstance(record, dict) else {}


def _dig(record: dict[str, object], *keys: str) -> object:
    """Nested lookup returning ``None`` at the first missing or non-dict level.

    The metrics JSON is external input to this script, so every level is checked rather than
    assumed; a schema change upstream should degrade the provenance print, not crash the fit.
    """
    current: object = record
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


@dataclass(frozen=True)
class HeldOutResidual:
    """The held-out decoded/true velocity pair R is fit from, with the provenance of both.

    Frozen: this record is the audit trail behind every number the generated header publishes, so a
    caller that needs a variant builds a new one rather than mutating this.
    """

    session_id: str
    session_sha256: str
    encoder_sha256: str
    velocity_sha256: str
    checkpoint_label: str
    decoded_cm_s: np.ndarray  # (n, 2) the shipped readout's output on the held-out tail
    true_cm_s: np.ndarray  # (n, 2) the binned true velocity on the same rows
    side_mm: float
    side_mm_source: str
    lag_bins: int
    ridge_lambda: float
    heldout_r2_pooled: float


def heldout_decoded_and_true(data_dir: Path, session_id: str) -> HeldOutResidual:
    """Decode the held-out chronological tail with the SHIPPED readout and return it beside truth.

    Every numeric step is Plan 09-07's, imported from ``fit_velocity_real`` rather than restated:
    the stride-1 BC1S window stack, the encoder forward pass, the chronological split and the lag
    alignment. Reimplementing any of them is the fastest way to introduce an off-by-one against the
    committed held-out R2. Those helpers are module-private by naming convention only; importing
    them is deliberately preferred over copying their bodies, which is what would actually drift.

    The readout is NOT re-fit here. ``ndt1_real_with_velocity.pt`` holds the pooled ridge head that
    produced the published R2, and the tail rows below were never in its fit, so the residual is the
    held-out error of the decoder that ships.

    Args:
        data_dir: directory holding the gitignored Indy ``.mat`` sessions.
        session_id: session stem, e.g. ``indy_20160630_01``.

    Returns:
        A :class:`HeldOutResidual`.

    Raises:
        FileNotFoundError: if the session or either checkpoint is absent. This path never falls back
            to the default: a silent fallback is the defect Plan 10-03 exists to remove.
        ValueError: if the checkpoint on disk is not the one the Phase-9 metrics published, or if
            the locked lag/lambda disagree with how that readout was fit.
    """
    # Imported here, not at module scope: the pure helpers above and the data-absent fallback must
    # stay importable (and fast) on a checkout with no torch-heavy work to do.
    if str(_SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(_SCRIPTS_DIR))
    import fit_velocity_real as fvr

    # The box is the RECORDED cursor track (10-PREREGISTRATION §3a), which `load_session` does not
    # return: D-01 keeps `cursor_pos` out of the loader. `export_replay` owns the one h5py cursor
    # reader on the export path, so it is imported rather than duplicated here -- one reader, one
    # box, one `k`.
    from export_replay import read_cursor_mm

    from ndt1.data import load_session
    from ndt1.kinematics import apply_lag, heldout_r2
    from ndt1.model_ane import NDT1ANEWithVelocity
    from ndt1.qc import band_violations, firing_rate_stats
    from ndt1.real_checkpoint import (
        REAL_ENCODER_CHECKPOINT,
        REAL_VELOCITY_CHECKPOINT,
        checkpoint_sha256,
        load_real_weights_if_present,
    )
    from ndt1.sessions import SessionLoad
    from ndt1.velocity_head import VELOCITY_DIM

    mat = Path(data_dir) / f"{session_id}.mat"
    if not mat.is_file():
        raise FileNotFoundError(
            f"no session at {mat}. The R fit reads a REAL held-out residual and will not fabricate "
            f"one; materialize the dataset with Decoder/scripts/download_indy.py, or point "
            f"--data-dir at a path that does not exist to take the documented default fallback."
        )
    for checkpoint in (REAL_ENCODER_CHECKPOINT, REAL_VELOCITY_CHECKPOINT):
        if not checkpoint.is_file():
            raise FileNotFoundError(
                f"no checkpoint at {checkpoint}. Both Phase-9 checkpoints are required: the "
                f"with-velocity one supplies the shipped readout, and the pooled encoder supplies "
                f"the encoder digest the provenance header records."
            )

    published = _phase09_velocity_record()
    velocity_sha = checkpoint_sha256(REAL_VELOCITY_CHECKPOINT)
    encoder_sha = checkpoint_sha256(REAL_ENCODER_CHECKPOINT)
    lag_bins, ridge_lambda = LAG_BINS, RIDGE_LAMBDA
    recorded = _dig(published, "checkpoint", "sha256")
    if isinstance(recorded, str) and recorded != velocity_sha:
        raise ValueError(
            f"{REAL_VELOCITY_CHECKPOINT.name} sha256 {velocity_sha[:12]} is not the "
            f"{recorded[:12]} that 09-decoder-metrics.json published; this is not the readout "
            f"whose held-out R2 the evidence cites, so its residual is not that decoder's"
        )
    recorded_lag = _dig(published, "lag_bins")
    recorded_lambda = _dig(published, "lambda")
    if isinstance(recorded_lag, (int, float)):
        lag_bins = int(recorded_lag)
    if isinstance(recorded_lambda, (int, float)):
        ridge_lambda = float(recorded_lambda)
    if (lag_bins, ridge_lambda) != (LAG_BINS, RIDGE_LAMBDA):
        raise ValueError(
            f"the shipped readout was fit at lag {lag_bins} bins / lambda {ridge_lambda}, but "
            f"10-PREREGISTRATION section 2 locks lag {LAG_BINS} / lambda {RIDGE_LAMBDA}; the "
            f"provenance header would record a lag and lambda the decoder was not fit with"
        )

    raw = load_session(mat)
    binned = np.asarray(raw["binned"], dtype=np.float32)
    stats = firing_rate_stats(binned)
    session = SessionLoad(
        session_id=session_id,
        path=mat,
        binned=binned,
        planar_cm=np.asarray(raw["planar_cm"], dtype=np.float64),
        t=np.asarray(raw["t"], dtype=np.float64),
        t_start=float(raw["t_start"]),
        t_end=float(raw["t_end"]),
        stats=stats,
        # D-01's third behavior array. Both fields are required, with no default, since Plan 10-02;
        # this call site was written in a parallel worktree where they did not exist yet, so on the
        # merged tree it raised `TypeError` before reaching the fit. Passed through, not defaulted:
        # a default here would let a caller build a SessionLoad whose target track is silently
        # empty, which is the failure mode the no-default choice exists to prevent.
        target_mm=np.asarray(raw["target_mm"], dtype=np.float64),
        target_distinct=np.asarray(raw["target_distinct"], dtype=np.float64),
        # Surfaced, not acted on, exactly as `available_sessions` does (D-03).
        band_violations=band_violations(stats),
    )
    cursor_mm = read_cursor_mm(mat)
    side_mm, side_mm_source = _resolve_side_mm(cursor_mm)
    print(
        f"[fit_kalman_gain] {session_id}: {binned.shape[0]} bins, "
        f"{cursor_mm.shape[0]} recorded cursor samples, side_mm={side_mm!r} "
        f"({side_mm_source}), band_violations={session.band_violations or 'none'}"
    )

    model = NDT1ANEWithVelocity(seq_len=fvr.SEQ_LEN)
    label = load_real_weights_if_present(model, REAL_VELOCITY_CHECKPOINT)
    if "real-data" not in label:
        raise FileNotFoundError(
            f"{label}: refusing to fit R on random weights, which would publish a number that "
            f"describes no decoder at all"
        )
    model.eval()
    print(f"[fit_kalman_gain] readout: {label} (shipped pooled ridge head, NOT re-fit here)")

    vel_cm_s = fvr._velocity_bins(session, binned.shape[0])
    rates = fvr._encoder_last_bin(model, binned)
    design = fvr._split_design(session_id, binned, rates, vel_cm_s)
    test_rates, test_vel = apply_lag(design.test_rates, design.test_vel, lag_bins)
    _, train_vel = apply_lag(design.train_rates, design.train_vel, lag_bins)

    weight = (
        model.velocity_head.readout.weight.detach()
        .numpy()
        .reshape(VELOCITY_DIM, -1)
        .astype(np.float64)
    )
    bias = model.velocity_head.readout.bias.detach().numpy().astype(np.float64)
    decoded = test_rates @ weight.T + bias  # the arithmetic the 1x1 conv reproduces (Plan 09-07 R4)

    scored = heldout_r2(test_vel, decoded, train_vel.mean(axis=0))
    print(
        f"[fit_kalman_gain] wiring check: held-out R2 pooled {scored['pooled']:+.6f} "
        f"(vx {scored['vx']:+.6f}, vy {scored['vy']:+.6f}) on {int(scored['n'])} rows, against "
        f"this session's own train-split mean. 09-decoder-metrics.json publishes "
        f"{_dig(published, 'per_session', session_id, 'pooled')} for the same rows. Recorded, "
        f"never reconciled by tuning."
    )
    return HeldOutResidual(
        session_id=session_id,
        session_sha256=fvr._sha256_of(mat),
        encoder_sha256=encoder_sha,
        velocity_sha256=velocity_sha,
        checkpoint_label=label,
        decoded_cm_s=decoded,
        true_cm_s=np.asarray(test_vel, dtype=np.float64),
        side_mm=side_mm,
        side_mm_source=side_mm_source,
        lag_bins=lag_bins,
        ridge_lambda=ridge_lambda,
        heldout_r2_pooled=float(scored["pooled"]),
    )


def _residual_note(
    held: HeldOutResidual,
    r_full: np.ndarray,
    r: np.ndarray,
    sigma_jerk_sq: float,
    rho: float,
    resid_grid: np.ndarray,
) -> str:
    """The one-line provenance the generated header carries verbatim.

    ``R=diag(...)`` beside ``R_offdiag=...`` is the diagonal-R resolution made auditable from the
    generated file alone: 10-PREREGISTRATION §4 step 3 fixes the filter's R as the diagonal because
    the measurement model is per-axis, and the discarded off-diagonal is published rather than
    dropped. ``resid_mean_grid_s`` is there for the same reason — R is a covariance about the mean,
    so a decoder bias does not enter it and must therefore be visible next to it.
    """
    rms = np.sqrt(np.mean(resid_grid**2, axis=0))
    mean = resid_grid.mean(axis=0)
    return (
        f"session={held.session_id} sha256={held.session_sha256[:12]} "
        f"n_heldout={int(resid_grid.shape[0])} lag_bins={held.lag_bins} "
        f"lambda={held.ridge_lambda} side_mm={held.side_mm:.4f} "
        f"grid_units_per_cm={GRID_MM_PER_CM / held.side_mm:.8f} "
        f"sigma_jerk_sq={sigma_jerk_sq:.6f} R=diag({r[0, 0]:.8f},{r[1, 1]:.8f}) "
        f"R_offdiag={r_full[0, 1]:.8f} rho_closed_loop={rho:.6f} "
        f"resid_rms_grid_s=({rms[0]:.6f},{rms[1]:.6f}) "
        f"encoder_sha={held.encoder_sha256[:12]} velocity_sha={held.velocity_sha256[:12]} "
        f"resid_mean_grid_s=({mean[0]:+.6f},{mean[1]:+.6f}) "
        f"heldout_r2_pooled={held.heldout_r2_pooled:+.6f} readout=shipped_pooled_ridge "
        f"side_mm_source={held.side_mm_source}"
    )


def fit_noise(data_dir: Path, seed: int, session_id: str = DEFAULT_SESSION) -> NoiseFit:
    """Fit Q/R from the held-out Indy residual when present, else the documented default.

    Data-present path (10-PREREGISTRATION §4 and §5, in order): decode the held-out chronological
    tail with the shipped readout, convert the residual to grid-units/s, take
    ``R = diag(cov(resid))``, take ``σ_jerk²`` from the second difference of the true velocity on
    the same rows, and solve the gain through :func:`~ndt1.kalman_gain.steady_state_gain` — which
    raises on a non-Schur solve, HERE, before anything is written. That raise is not caught: §5
    says the fallback is to report it, not to silently revert to the default.

    Args:
        data_dir: directory expected to hold the gitignored Indy ``.mat`` sessions.
        seed: RNG seed (recorded for reproducibility; both paths are deterministic).
        session_id: which session's held-out residual to fit (CONTEXT D-08 locks the default).

    Returns:
        A :class:`NoiseFit` whose ``source`` is ``"indy-heldout"`` on the data-present path and
        ``"default"`` only when ``data_dir`` does not exist.

    Raises:
        FileNotFoundError: if ``data_dir`` exists but the session or a checkpoint does not.
        ValueError: on a degenerate residual or a gain that does not stabilize.
    """
    if not data_dir.exists():
        print(
            f"[fit_kalman_gain] held-out Indy data dir not found: {data_dir}\n"
            f"[fit_kalman_gain] -> using documented DEFAULT Q/R (deterministic, seed={seed}).",
            file=sys.stderr,
        )
        return default_noise(seed)

    held = heldout_decoded_and_true(Path(data_dir), session_id)
    decoded_grid = to_grid_units(held.decoded_cm_s, held.side_mm)
    true_grid = to_grid_units(held.true_cm_s, held.side_mm)
    resid_grid = decoded_grid - true_grid

    r_full = residual_covariance(decoded_grid, true_grid)
    if not np.all(np.isfinite(r_full)):
        raise ValueError(f"the held-out residual covariance is not finite: {r_full!r}")
    # 10-PREREGISTRATION section 4 step 3: the filter's measurement model is per-axis, so R is the
    # DIAGONAL. The off-diagonal is computed and published (see `_residual_note`), never used.
    r = np.diag(np.diag(r_full))
    if not np.all(np.diag(r) > 0.0):
        raise ValueError(
            f"R has a non-positive diagonal {np.diag(r)!r}; a degenerate measurement-noise "
            f"covariance has no stabilizing DARE solution"
        )

    sigma_jerk_sq = jerk_variance(true_grid)
    q_obs = white_noise_jerk_q(sigma_jerk_sq)
    # Solve HERE so a non-Schur pair raises before any file is written (10-PREREGISTRATION §5).
    steady_state_gain(q_obs, r)
    rho = closed_loop_rho(q_obs, r)

    note = _residual_note(held, r_full, r, sigma_jerk_sq, rho, resid_grid)
    print(f"[fit_kalman_gain] fit on real held-out residuals: {note}")
    return NoiseFit(q_obs=q_obs, r=r, source="indy-heldout", seed=seed, note=note)


def _fmt_f(value: float) -> str:
    """Format a float as a deterministic Swift ``Float`` literal (repr round-trip, no locale)."""
    return repr(float(value))


def _simd_rows(matrix: np.ndarray, simd_width: int) -> str:
    """Render an ``(n, k)`` matrix as Swift ``SIMD{simd_width}<Float>`` row literals (zero-padded).

    Swift's ``simd`` only defines SIMD2/3/4/8/16/… — there is **no ``SIMD6``**. A 6-wide row is
    therefore emitted as ``SIMD8<Float>`` with the trailing ``simd_width − k`` lanes zero-padded
    (the pad lanes contribute nothing to an inlined ``simd_dot``; ``simd_width >= k`` is required).

    Emits swiftformat-clean output by construction (``.swiftformat``: ``--indent 2``,
    ``--commas inline`` ⇒ NO trailing comma on the last element): 4-space element indent (two
    scope levels deep: enum body + array literal), and the final row carries no trailing comma.

    Raises:
        ValueError: if any row is wider than ``simd_width``.
    """
    n = len(matrix)
    rows = []
    for i, row in enumerate(matrix):
        if len(row) > simd_width:
            raise ValueError(f"row width {len(row)} exceeds SIMD{simd_width}")
        padded = list(row) + [0.0] * (simd_width - len(row))
        elems = ", ".join(_fmt_f(v) for v in padded)
        comma = "," if i < n - 1 else ""
        rows.append(f"    SIMD{simd_width}<Float>({elems}){comma}")
    return "\n".join(rows)


def render_swift(
    a: np.ndarray,
    h: np.ndarray,
    k: np.ndarray,
    q_obs: np.ndarray,
    r: np.ndarray,
    fit: NoiseFit,
) -> str:
    """Render the committed ``KalmanConstants.swift`` source from the solved matrices.

    The layout MUST match Task 2's ``KalmanConstants`` struct: ``A`` as 6 ``SIMD8<Float>`` rows and
    ``H`` as 2 ``SIMD8<Float>`` rows (6 meaningful lanes + 2 zero-pad — Swift has no ``SIMD6``),
    ``K`` as 6 ``SIMD2<Float>`` rows, ``Qobs`` as 4 ``SIMD4<Float>`` rows (observable block), ``R``
    as 2 ``SIMD2<Float>`` rows. Foundation-free (``import simd`` only) — it lands on the hot path
    (Plan 02), so it must pass ``hotpath-policy.sh``.

    TWO gains are emitted (Phase 10, RD-07 / D-09). ``K`` is the SHIPPED gain, solved from whatever
    ``fit`` this run produced. ``phase7BaselineK`` is the FROZEN gain the documented DEFAULT Q/R
    produces, solved here unconditionally so it is emitted by the SAME generator through the SAME
    :func:`~ndt1.kalman_gain.steady_state_gain` rather than transcribed. The synthetic regression
    fixture runs on the frozen one, which is what makes ``refit_bps.json`` immune to a real-data
    re-fit of ``K`` — a red build on a real-data finding is pressure to tune
    (10-PREREGISTRATION §13).

    Returns:
        The full Swift source as a string.
    """
    # The FROZEN Phase-7 baseline: the documented default Q/R through the same solver. Computed
    # here, never copied, so it cannot drift from what `default_noise` actually means.
    baseline = default_noise(fit.seed)
    k_baseline = steady_state_gain(baseline.q_obs, baseline.r)
    baseline_qr = f"sigma_jerk^2 = {_DEFAULT_SIGMA_JERK_SQ}, R = diag({_DEFAULT_R_VAR})"
    header = "// KalmanConstants.swift — steady-state ReFIT-Kalman matrices (REFIT-01, D-15)."
    # Pre-wrap the provenance note into `//   ` comment lines under swiftformat's --maxwidth 120
    # (emitted swiftformat-clean by construction — no post-hoc wrapSingleLineComments needed).
    # `break_on_hyphens=False`: the note is a sequence of `key=value` provenance tokens that are
    # grepped as literals, and a wrap point inside `shipped_pooled_ridge` or a hyphenated source
    # label would split a token across two comment lines and break that grep.
    note_lines = textwrap.wrap(fit.note, width=110, break_on_hyphens=False)
    note_block = "\n".join(f"//   {line}" for line in note_lines)
    return f"""{header}
//
// GENERATED by Decoder/scripts/fit_kalman_gain.py (D-15) — re-run to regenerate; do NOT hand-edit
// the numeric literals (a hand-edit breaking the structural invariants fails KalmanConstantsTests
// and CI — threat T-07-01-02).
//
// Provenance:
//   dt          = {DT}  (20 ms tick, CONTEXT D-01)
//   noise source = {fit.source}   seed = {fit.seed}
{note_block}
//   two gains: K SHIPS (fit from the noise source above); phase7BaselineK is FROZEN on the
//   documented default Q/R and is read by the SYNTHETIC regression fixture only (Phase-10 D-09).
//   grid normalisation: R and Q are fit in GRID-UNITS/s using grid_units_per_cm = 10.0 / side_mm
//   (10-PREREGISTRATION section 4, pre-registered before the fit ran). A residual fit in cm/s and
//   normalised afterwards differs by grid_units_per_cm^2, which is large.
//
// Observability resolution (07-RESEARCH §2.3): the 6-DOF state [px,py,vx,vy,ax,ay] with a
// velocity-only measurement is NOT observable — position is a pure integrator no measurement
// corrects. The steady-state gain K is therefore solved on the OBSERVABLE 4-DOF [vx,vy,ax,ay]
// sub-block and embedded into a 6x2 K with ZERO position rows (rows 0,1). Position is synced
// externally each tick (Wave-2, Swift side) to the integrator's clamped cursor position. The
// 6-DOF *state* is retained end-to-end; only the *gain derivation* used the observable block.
//
// Hot-path discipline: Foundation-free (uses `import simd` only, never the Obj-C runtime) — the
// per-tick filter op (Plan 02) is fixed-dim simd mat-vecs, zero allocation (hotpath-policy.sh,
// which forbids the Foundation/ObjectiveC imports on the hot path Plan 02 adds CortexReFIT to).
import simd

/// Committed steady-state ReFIT-Kalman matrices for the 6-DOF constant-acceleration model.
///
/// Layout choice (CONTEXT "implementer's discretion"): Swift `simd` has no `SIMD6`, so each 6-wide row
/// of A and H is stored as a `SIMD8<Float>` with the last 2 lanes zero-padded — the pad lanes
/// contribute nothing to an inlined `simd_dot`, so the Wave-2 predict/update step
/// (`x⁻ = A·x`; `x = x⁻ + K·(z − H·x⁻)`) stays a handful of fixed-size simd dot products with no
/// heap. Only the first 6 lanes of each A/H row are meaningful.
///
/// `nonisolated`: the constants are immutable `Sendable` compile-time data, so the hot-path
/// ``KalmanFilter`` (which is `nonisolated` — it runs on the decoder pthread, SC#3, NOT the
/// package-default `MainActor`) can load A/H/K synchronously with no isolation hop. Mirrors how
/// `IntentRotation` / `CursorVelocity` opt out of `.defaultIsolation(MainActor.self)`.
public nonisolated enum KalmanConstants {{
  /// Filter tick in seconds (20 ms, CONTEXT D-01).
  public static let dt: Float = {_fmt_f(DT)}

  /// 6x6 constant-acceleration transition A on [px,py,vx,vy,ax,ay] (6 rows; SIMD8 with 2 zero-pad
  /// lanes — Swift has no SIMD6). Columns 0..5 are [px,py,vx,vy,ax,ay]; columns 6,7 are padding.
  public static let A: [SIMD8<Float>] = [
{_simd_rows(a, 8)}
  ]

  /// 2x6 velocity-only measurement H = [0 I 0] (selects (vx,vy); 2 rows; SIMD8, 2 zero-pad lanes).
  public static let H: [SIMD8<Float>] = [
{_simd_rows(h, 8)}
  ]

  /// 6x2 steady-state Kalman gain K with ZERO position rows (rows 0,1); 6 rows of (kx,ky).
  /// This is the SHIPPED gain — every runtime filter uses it.
  public static let K: [SIMD2<Float>] = [
{_simd_rows(k, 2)}
  ]

  /// The FROZEN Phase-7 baseline gain: the gain the documented DEFAULT Q/R produces
  /// ({baseline_qr} in grid-units/s). It exists so the SYNTHETIC
  /// regression fixture (`CortexReFITBench --smoke` -> `refit_bps.json`) keeps guarding the FILTER
  /// CODE with the gain HELD FIXED, and is therefore immune to a real-data re-fit of `K`. Phase-10
  /// D-09 requires that fixture to stay byte-identical, because a red build on a real-data finding
  /// is pressure to tune. The SHIPPED gain is `K` above; this constant is used by the synthetic
  /// fixture ONLY.
  public static let phase7BaselineK: [SIMD2<Float>] = [
{_simd_rows(k_baseline, 2)}
  ]

  /// 4x4 process-noise covariance Q on the observable [vx,vy,ax,ay] block (provenance; 4 rows).
  public static let Qobs: [SIMD4<Float>] = [
{_simd_rows(q_obs, 4)}
  ]

  /// 2x2 measurement-noise covariance R on (vx,vy) (provenance; 2 rows).
  public static let R: [SIMD2<Float>] = [
{_simd_rows(r, 2)}
  ]
}}
"""


def main(argv: list[str] | None = None) -> int:
    """Fit Q/R, solve the steady-state gain, and write ``KalmanConstants.swift``.

    Returns:
        Process exit code (0 on success).
    """
    parser = argparse.ArgumentParser(description="Fit ReFIT-Kalman Q/R and emit Swift constants.")
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=_DEFAULT_DATA_DIR,
        help="held-out Indy .mat dir (gitignored); absent -> documented default Q/R",
    )
    parser.add_argument(
        "--session",
        default=DEFAULT_SESSION,
        help="session whose held-out residual R is fit from (CONTEXT D-08 locks the default)",
    )
    parser.add_argument("--seed", type=int, default=0, help="RNG seed (deterministic; recorded)")
    parser.add_argument(
        "--out",
        type=Path,
        default=KALMAN_CONSTANTS_SWIFT,
        help="output Swift constants path (KalmanConstants.swift)",
    )
    args = parser.parse_args(argv)

    np.random.seed(args.seed)  # seed everything (no unseeded RNG — threat T-07-01-03)

    # Printed BEFORE the write so the transcript of any run names the inputs it resolved, and so a
    # default-noise run is visible in the log rather than only in the file it produced.
    print(f"[fit_kalman_gain] data-dir={args.data_dir}  session={args.session}  seed={args.seed}")
    fit = fit_noise(args.data_dir, args.seed, args.session)
    print(f"[fit_kalman_gain] noise source={fit.source}")
    a = full_transition().astype(np.float64)
    h = full_measurement().astype(np.float64)
    k = steady_state_gain(fit.q_obs, fit.r)  # raises if not Schur-stable; zero position rows
    assert k.shape == (6, MEAS_DIM)
    assert fit.q_obs.shape == (OBS_DIM, OBS_DIM)

    swift_src = render_swift(a, h, k, fit.q_obs, fit.r, fit)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(swift_src, encoding="utf-8")
    print(f"[fit_kalman_gain] wrote {args.out} (noise source={fit.source}, seed={fit.seed})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
