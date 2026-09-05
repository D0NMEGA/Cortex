"""RD-07 / Plan 10-03 — the held-out residual path in ``scripts/fit_kalman_gain.py``.

Through Phase 9 that script could not fit from data at all: BOTH branches of ``fit_noise`` returned
``default_noise``, so ``KalmanConstants.swift``'s header recorded ``noise source = default`` even
when ``--data-dir`` pointed at the real sessions (10-RESEARCH Correction 1). These tests cover the
implemented replacement.

Tier split, deliberately (Phase 9 D-21, restated as 10-PREREGISTRATION section 13). The four pure
helpers and the data-absent fallback are QUICK: they run on arrays this module builds itself, so the
suite stays green on a clean checkout where ``Decoder/data/`` and ``Decoder/checkpoints/`` are both
absent. The end-to-end ``indy-heldout`` fit is ``slow`` and skips with a reason when either is
missing, because it reads a 382 MB gitignored ``.mat`` and runs 73k encoder forward passes.

D-09 applies to this module and to the script it tests: neither may compare a measured real-data
value against a bar. ``test_no_number_is_a_measured_threshold_assertion`` is the executable form of
that rule. The one inequality the slow test does make is a well-posedness check (a covariance
diagonal must be finite and strictly positive, or the DARE is not solvable), not a claim about the
size or the sign of the residual.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import numpy as np
import pytest

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "fit_kalman_gain.py"
_spec = importlib.util.spec_from_file_location("fit_kalman_gain", _SCRIPT)
assert _spec is not None and _spec.loader is not None
fit_kalman_gain = importlib.util.module_from_spec(_spec)
sys.modules["fit_kalman_gain"] = fit_kalman_gain
_spec.loader.exec_module(fit_kalman_gain)

_DECODER_ROOT = Path(__file__).resolve().parents[1]
_DATA_DIR = _DECODER_ROOT / "data"
_CHECKPOINT_DIR = _DECODER_ROOT / "checkpoints"
_SESSION_MAT = _DATA_DIR / f"{fit_kalman_gain.DEFAULT_SESSION}.mat"
_ENCODER = _CHECKPOINT_DIR / "ndt1_real_pooled.pt"
_VELOCITY = _CHECKPOINT_DIR / "ndt1_real_with_velocity.pt"

#: The workspace side the pre-registered `cursor_bbox_square` box has for `indy_20160630_01`
#: (10-PREREGISTRATION section 3, "about 171.7"). Used here only as a plausible scale for the unit
#: conversions, never as an expected measurement.
_SIDE_MM: float = 171.7


def _dataset_absent() -> str:
    """A skip reason when the gitignored session or either checkpoint is missing; else ``""``."""
    missing = [p.name for p in (_SESSION_MAT, _ENCODER, _VELOCITY) if not p.exists()]
    if not missing:
        return ""
    return (
        f"needs the gitignored real-data artifacts, missing: {missing}. Materialize with "
        f"Decoder/scripts/download_indy.py and the Phase-9 checkpoints."
    )


def test_to_grid_units_scales_by_ten_over_side_mm() -> None:
    """`to_grid_units` is exactly `10.0 / side_mm` per cm/s, and the inverse round-trips.

    10-PREREGISTRATION section 4 step 2 fixes this constant: `k = 10.0 / side_mm` grid-units per
    centimetre, because a grid unit spans `side_mm` millimetres and a centimetre is 10 of them.
    Getting it wrong scales R by `k^2`, which for `side_mm = 171.7` is a factor of about 3400.
    """
    one_cm_s = np.array([[1.0, 0.0], [0.0, 1.0]])
    converted = fit_kalman_gain.to_grid_units(one_cm_s, _SIDE_MM)
    assert converted == pytest.approx(one_cm_s * (10.0 / _SIDE_MM), abs=1e-15)

    arbitrary = np.array([[3.5, -12.25], [0.0, 7.75]])
    round_trip = fit_kalman_gain.to_grid_units(arbitrary, _SIDE_MM) * _SIDE_MM / 10.0
    assert round_trip == pytest.approx(arbitrary, abs=1e-12)


def test_residual_covariance_matches_the_sample_covariance_of_the_difference() -> None:
    """`residual_covariance(decoded, true)` is the 2x2 sample covariance of `decoded - true`.

    Checked against the explicit centered form rather than against `np.cov`, so the test pins the
    definition (mean-centered, `ddof=1`) instead of restating the implementation.
    """
    rng = np.random.default_rng(0)
    true = rng.normal(size=(4096, 2)) * 3.0
    resid = rng.multivariate_normal([0.4, -0.2], [[0.9, 0.3], [0.3, 0.5]], size=4096)
    centered = resid - resid.mean(axis=0)
    expected = centered.T @ centered / (resid.shape[0] - 1)

    measured = fit_kalman_gain.residual_covariance(true + resid, true)
    assert measured.shape == (2, 2)
    assert measured == pytest.approx(expected, abs=1e-9)


def test_jerk_variance_is_zero_on_a_constant_acceleration_track() -> None:
    """A velocity ramp has no jerk: the second difference of a linear track is identically zero."""
    steps = np.arange(4096, dtype=np.float64)
    ramp = np.stack([2.0 + 0.5 * steps, -1.0 - 0.25 * steps], axis=1)
    assert fit_kalman_gain.jerk_variance(ramp) == pytest.approx(0.0, abs=1e-12)


def test_jerk_variance_recovers_an_injected_white_jerk() -> None:
    """Integrating a known white jerk and differentiating back recovers its variance.

    `v` is built by the same constant-acceleration recursion the filter's `A` assumes
    (`a += j*dt`, `v += a*dt`), so `diff2(v) == j*dt^2` exactly and `var(diff2(v)/dt^2) == var(j)`.
    The 10 percent band is sampling error on a variance from 20k draws (about 1 percent), not a
    tolerance on a modelling approximation.
    """
    rng = np.random.default_rng(7)
    dt = fit_kalman_gain.DT
    injected = 4.0
    jerk = rng.normal(scale=np.sqrt(injected), size=(20_000, 2))
    accel = np.cumsum(jerk, axis=0) * dt
    velocity = np.cumsum(accel, axis=0) * dt

    recovered = fit_kalman_gain.jerk_variance(velocity, dt)
    assert recovered == pytest.approx(injected, rel=0.10)


def test_closed_loop_rho_is_below_one_for_the_committed_default_pair() -> None:
    """The documented default `(Q_obs, R)` yields a Schur-stable observable-block closed loop.

    This is the quantity `steady_state_gain` already asserts on internally; `closed_loop_rho`
    exposes it so the number can be RECORDED in the generated header (review D-7) rather than only
    checked transiently during the fit.
    """
    default = fit_kalman_gain.default_noise(0)
    rho = fit_kalman_gain.closed_loop_rho(default.q_obs, default.r)
    assert rho < 1.0, f"the committed default pair is not Schur-stable: rho = {rho}"


def test_closed_loop_rho_rejects_a_degenerate_noise_pair() -> None:
    """A degenerate pair either fails to stabilize or raises; the test accepts whichever happens.

    Zero process noise with an enormous measurement noise drives the gain to zero, leaving the bare
    constant-acceleration `A_obs`, whose eigenvalues all sit on the unit circle. Some scipy builds
    report that as `rho >= 1`; others refuse the solve outright because no stabilizing solution
    exists. Both are correct refusals, so the control asserts the disjunction rather than pinning a
    scipy internal.
    """
    q_obs = np.zeros((4, 4))
    r = np.diag([1e12, 1e12])
    try:
        rho = fit_kalman_gain.closed_loop_rho(q_obs, r)
    except (ValueError, np.linalg.LinAlgError) as exc:
        assert str(exc)
    else:
        assert rho >= 1.0, f"a zero-process-noise gain should not be Schur-stable, got rho = {rho}"


def test_workspace_side_mm_implements_the_preregistered_square_box() -> None:
    """`side_mm` is the LONGER side of the cursor bounding box, in mm, from `planar_cm` times 10.

    10-PREREGISTRATION section 3: `cursor_mm = 10 * planar_cm`, `side_mm = max(width, height)`. The
    box is square so that one grid unit is the same distance on both axes, which is what makes the
    scalar acquisition radius meaningful.
    """
    planar_cm = np.array([[-5.0, 0.0], [12.17, 13.0], [0.0, 6.5]])
    assert fit_kalman_gain.workspace_side_mm(planar_cm) == pytest.approx(171.7, abs=1e-9)


def test_fit_noise_falls_back_to_the_default_when_the_data_dir_is_absent(
    tmp_path: Path,
) -> None:
    """The honest data-absent fallback is PRESERVED, not deleted, by the residual implementation.

    A checkout without the gitignored dataset must still regenerate a buildable constants file, and
    it must say `default` in its provenance header when it does. That branch is the one thing the
    Phase-7 script got right and it stays.
    """
    fit = fit_kalman_gain.fit_noise(tmp_path / "does-not-exist", 0)
    assert fit.source == "default"
    assert fit.r == pytest.approx(0.25 * np.eye(2), abs=0.0)
    assert "DEFAULT Q/R" in fit.note


@pytest.mark.slow
@pytest.mark.skipif(bool(_dataset_absent()), reason=_dataset_absent() or "dataset present")
def test_fit_noise_on_the_real_session_reports_indy_heldout() -> None:
    """The data-present branch fits from the real held-out residual and says so in its provenance.

    Dataset-gated (D-21: CI never touches the dataset). The only numeric assertions are
    well-posedness ones: a measurement-noise covariance must be finite and strictly positive on the
    diagonal or the DARE has no solution. Nothing here asserts the SIZE of the residual, which is a
    measured real-data quantity that belongs in `10-kalman-refit-evidence.md`.
    """
    fit = fit_kalman_gain.fit_noise(_DATA_DIR, 0)
    assert fit.source == "indy-heldout"
    assert fit.r.shape == (2, 2)
    assert np.all(np.isfinite(fit.r))
    assert np.all(np.diag(fit.r) > 0.0)
    assert fit.r[0, 1] == 0.0 and fit.r[1, 0] == 0.0  # diagonal by 10-PREREGISTRATION section 4
    assert fit.q_obs.shape == (4, 4)
    for label in ("session=", "R=diag(", "R_offdiag=", "grid_units_per_cm=", "rho_closed_loop="):
        assert label in fit.note


# GUARD SPLIT MARKER: do not move or reword this line
def test_no_number_is_a_measured_threshold_assertion() -> None:
    """D-09: neither this module nor the script compares a measured real-data value against a bar.

    A source self-check, in the shape of
    ``test_metrics_schema.py::test_no_number_is_a_measured_threshold_assertion``. The forbidden
    shapes are an assertion on a residual, on a fitted jerk variance or on an R2 -- the three
    real-data quantities this plan measures. A gate that policed any of them would go red on an
    honest re-measurement and then be tuned or deleted, which is exactly the pressure
    10-PREREGISTRATION section 13 exists to remove. The rule reaches the script too, not only the
    test module, because the script is where the residual is computed.
    """
    forbidden = (
        r"assert .*resid.*[<>]",
        r"assert .*sigma_jerk.*[<>]",
        r"assert .*r2.*[<>]",
        r"assert .*offdiag.*[<>]",
    )

    test_source = Path(__file__).read_text(encoding="utf-8")
    scanned, marker, _guard = test_source.partition(
        "# GUARD SPLIT MARKER: do not move or reword this line"
    )
    assert marker, "the guard split marker is gone, so this test scanned the whole file or nothing"
    assert "def test_fit_noise_on_the_real_session_reports_indy_heldout" in scanned, (
        "the guard split marker moved above the tests it is supposed to scan"
    )

    sources = {"test module": scanned, "fit_kalman_gain.py": _SCRIPT.read_text(encoding="utf-8")}
    offenders = [
        (where, number, line.strip(), pattern)
        for where, source in sources.items()
        for number, line in enumerate(source.splitlines(), start=1)
        for pattern in forbidden
        if re.search(pattern, line)
    ]
    assert not offenders, (
        f"D-09: a measured real-data value is compared against a bar: {offenders}. The residual "
        f"statistics are published as numbers in 10-kalman-refit-evidence.md and in the generated "
        f"provenance header, where a re-measurement updates them, not as a build gate that a "
        f"re-measurement would redden."
    )
