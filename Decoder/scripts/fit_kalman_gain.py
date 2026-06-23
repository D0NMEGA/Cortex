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

Q/R fitting recipe (07-RESEARCH §3.2):
  * **R** (2×2): covariance of the decoder residual ``e_k = z_decoded − v_true`` on a held-out
    Indy split — how noisy the NDT1 velocity readout is.
  * **Q** (4×4 on ``[v,a]``): a discrete **white-noise-jerk** model, ``σ_jerk²`` scaled from the
    empirical distribution of true-acceleration increments on Indy.

When the held-out Indy artifacts are absent (the gitignored ``Decoder/data/`` is not present),
the script does NOT crash: it falls back to the documented default Q/R below, prints a clear note,
and records the seed/source in the generated file's header (mirrors the bench "skip cleanly when
artifacts absent" idiom; threat T-07-01-03 — the fallback is deterministic). Everything is seeded
(``--seed``, default 0); there is no unseeded RNG.

Usage::

    uv run --project Decoder --extra dev python Decoder/scripts/fit_kalman_gain.py
    uv run --project Decoder --extra dev python Decoder/scripts/fit_kalman_gain.py \\
        --data-dir <dir> --seed 0

No bare/blind ``except`` (ruff ``BLE`` gate): only the specific data-absent path is branched on a
``Path.exists`` check, and the model-residual loader (a future Plan-03 hook) raises explicit errors.
"""
from __future__ import annotations

import argparse
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


def fit_noise(data_dir: Path, seed: int) -> NoiseFit:
    """Fit Q/R from held-out Indy residuals if present, else fall back to documented defaults.

    Data-grounded path (when ``data_dir`` exists with downloaded Indy ``.mat`` sessions): fit
    **R** from the decoder velocity residual covariance and **Q** from the empirical jerk
    distribution (07-RESEARCH §3.2). Surfacing the cursor/finger behavior arrays + the decoded
    velocity is a Plan-03 (BPS-harness / D-11 replay) hook; until that lands, an existing but
    un-wired data dir still falls back to the seeded default (and says so) rather than fabricating
    a residual — honesty over a fake number.

    Args:
        data_dir: directory expected to hold the gitignored Indy ``.mat`` sessions.
        seed: RNG seed (recorded for reproducibility; the default path is deterministic).

    Returns:
        A :class:`NoiseFit` (``source`` is ``"default"`` on the absent/un-wired path).
    """
    if not data_dir.exists():
        print(
            f"[fit_kalman_gain] held-out Indy data dir not found: {data_dir}\n"
            f"[fit_kalman_gain] -> using documented DEFAULT Q/R (deterministic, seed={seed}).",
            file=sys.stderr,
        )
        return default_noise(seed)

    # Data dir exists but the residual extraction (decoded velocity vs true Indy velocity) is a
    # Plan-03 hook (it needs the behavior arrays data.py does not yet surface). Until then we do NOT
    # fabricate a residual: fall back to the documented default and say so plainly.
    print(
        f"[fit_kalman_gain] Indy data dir present ({data_dir}) but residual extraction is a "
        f"Plan-03 hook (decoded-vs-true velocity not yet surfaced by data.py).\n"
        f"[fit_kalman_gain] -> using documented DEFAULT Q/R (deterministic, seed={seed}) "
        f"rather than fabricating residuals.",
        file=sys.stderr,
    )
    return default_noise(seed)


def _fmt_f(value: float) -> str:
    """Format a float as a deterministic Swift ``Float`` literal (repr round-trip, no locale)."""
    return repr(float(value))


def _simd_rows(matrix: np.ndarray, width: int) -> str:
    """Render an ``(n, width)`` matrix as Swift ``SIMD{width}<Float>`` row literals.

    Emits swiftformat-clean output by construction (``.swiftformat``: ``--indent 2``,
    ``--commas inline`` ⇒ NO trailing comma on the last element): 4-space element indent (two
    scope levels deep: enum body + array literal), and the final row carries no trailing comma.
    """
    n = len(matrix)
    rows = []
    for i, row in enumerate(matrix):
        elems = ", ".join(_fmt_f(v) for v in row)
        comma = "," if i < n - 1 else ""
        rows.append(f"    SIMD{width}<Float>({elems}){comma}")
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

    The layout MUST match Task 2's ``KalmanConstants`` struct: ``A`` as 6 ``SIMD6<Float>`` rows,
    ``H`` as 2 ``SIMD6<Float>`` rows, ``K`` as 6 ``SIMD2<Float>`` rows, ``Qobs`` as 4
    ``SIMD4<Float>`` rows (observable block), ``R`` as 2 ``SIMD2<Float>`` rows. Foundation-free
    (``import simd`` only) — it lands on the hot path (Plan 02), so it must pass
    ``hotpath-policy.sh``.

    Returns:
        The full Swift source as a string.
    """
    header = "// KalmanConstants.swift — steady-state ReFIT-Kalman matrices (REFIT-01, D-15)."
    # Pre-wrap the provenance note into `//   ` comment lines under swiftformat's --maxwidth 120
    # (emitted swiftformat-clean by construction — no post-hoc wrapSingleLineComments needed).
    note_lines = textwrap.wrap(fit.note, width=110)
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
//
// Observability resolution (07-RESEARCH §2.3): the 6-DOF state [px,py,vx,vy,ax,ay] with a
// velocity-only measurement is NOT observable — position is a pure integrator no measurement
// corrects. The steady-state gain K is therefore solved on the OBSERVABLE 4-DOF [vx,vy,ax,ay]
// sub-block and embedded into a 6x2 K with ZERO position rows (rows 0,1). Position is synced
// externally each tick (Wave-2, Swift side) to the integrator's clamped cursor position. The
// 6-DOF *state* is retained end-to-end; only the *gain derivation* used the observable block.
//
// Hot-path discipline: Foundation-free `import simd` (no `import Foundation`) — the per-tick filter
// op (Plan 02) is fixed-dim simd mat-vecs, zero allocation (hotpath-policy.sh).
import simd

/// Committed steady-state ReFIT-Kalman matrices for the 6-DOF constant-acceleration model.
///
/// Row-major fixed-size simd layout chosen so the Wave-2 predict/update step
/// (`x⁻ = A·x`; `x = x⁻ + K·(z − H·x⁻)`) is a handful of inlined simd dot products with no heap.
public enum KalmanConstants {{
  /// Filter tick in seconds (20 ms, CONTEXT D-01).
  public static let dt: Float = {_fmt_f(DT)}

  /// 6x6 constant-acceleration transition A on [px,py,vx,vy,ax,ay] (row-major; 6 rows).
  public static let A: [SIMD6<Float>] = [
{_simd_rows(a, 6)}
  ]

  /// 2x6 velocity-only measurement H = [0 I 0] (selects (vx,vy); 2 rows).
  public static let H: [SIMD6<Float>] = [
{_simd_rows(h, 6)}
  ]

  /// 6x2 steady-state Kalman gain K with ZERO position rows (rows 0,1); 6 rows of (kx,ky).
  public static let K: [SIMD2<Float>] = [
{_simd_rows(k, 2)}
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
    parser.add_argument("--seed", type=int, default=0, help="RNG seed (deterministic; recorded)")
    parser.add_argument(
        "--out",
        type=Path,
        default=KALMAN_CONSTANTS_SWIFT,
        help="output Swift constants path (KalmanConstants.swift)",
    )
    args = parser.parse_args(argv)

    np.random.seed(args.seed)  # seed everything (no unseeded RNG — threat T-07-01-03)

    fit = fit_noise(args.data_dir, args.seed)
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
