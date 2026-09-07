"""Schema tests for the Phase 10 real-data replay artifacts.

These tests assert PROVENANCE, STRUCTURE, and SCHEMA SHAPE only.  They
never assert the sign or magnitude of any measured result (D-09).  The
guard split marker near the bottom checks that this module itself stays clean.
"""

import json
import math
import re
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PHASE_DIR = _REPO_ROOT / ".planning" / "phases" / "10-v1-real-data-closed-loop-launch"
_REFIT_REAL_PATH = _PHASE_DIR / "10-refit-real.json"
_REPLAY_PATH = _PHASE_DIR / "10-replay.json"

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

_PREREGISTERED_ARM_ORDER = ["raw", "kalman_only", "refit", "refit_reversed_target"]
_PREREGISTERED_ROTATION_SOURCES = ["none", "none", "true_track", "reversed_track"]
_PERCENTILE_KEYS = {"p1", "p5", "p25", "p50", "p90"}
_D11_FACTORS = {
    "decode_r2",
    "dwell_and_timeout",
    "open_loop_no_error_correction",
    "velocity_amplitude_shrinkage",
    "workspace_to_grid_scale",
}
_VERBATIM_DISCLOSURE = (
    "open-loop replay of a recorded session; the subject was not in the loop"
)


def _load(path: Path) -> dict:
    with path.open() as fh:
        return json.load(fh)


def _refit_real() -> dict:
    return _load(_REFIT_REAL_PATH)


def _replay() -> dict:
    return _load(_REPLAY_PATH)


# ── refit-real shape tests ────────────────────────────────────────────────────


def test_refit_real_parses_and_declares_provenance() -> None:
    r = _refit_real()
    assert isinstance(r["schema_version"], int), "schema_version must be int"
    assert r["data_source"] == "real", "data_source must be 'real'"
    assert r["session_id"], "session_id must be non-empty"
    assert _SHA256_RE.match(r["source_sha256"]), (
        "source_sha256 must be 64 lowercase hex"
    )
    manifest_file = _REPO_ROOT / r["manifest_path"]
    assert manifest_file.is_file(), (
        f"manifest_path {r['manifest_path']!r} must resolve to an existing file"
    )


def test_four_arms_in_the_preregistered_order() -> None:
    r = _refit_real()
    names = [arm["name"] for arm in r["arms"]]
    assert names == _PREREGISTERED_ARM_ORDER, (
        f"arm order mismatch: {names} != {_PREREGISTERED_ARM_ORDER}"
    )


def test_every_arm_reports_gain_and_smoothing() -> None:
    """SC#1d: realized_gain and realized_smoothing are present as finite numbers.

    Values are not compared against any threshold (D-09).
    """
    r = _refit_real()
    for arm in r["arms"]:
        name = arm["name"]
        for field in ("realized_gain", "realized_smoothing"):
            val = arm[field]
            assert isinstance(val, (int, float)), (
                f"{name}.{field} must be numeric, got {type(val).__name__}"
            )
            assert math.isfinite(float(val)), f"{name}.{field} must be finite"


def test_rotation_target_sources_are_preregistered() -> None:
    """SC#1c: the four rotation_target_source values match the preregistration."""
    r = _refit_real()
    actual = [arm["rotation_target_source"] for arm in r["arms"]]
    assert actual == _PREREGISTERED_ROTATION_SOURCES, (
        f"rotation_target_source mismatch: {actual}"
    )


def test_both_normalisations_present() -> None:
    r = _refit_real()
    for arm in r["arms"]:
        name = arm["name"]
        for field in ("bps_n64", "bps_n900"):
            val = arm[field]
            assert isinstance(val, (int, float)), (
                f"{name}.{field} must be numeric, got {type(val).__name__}"
            )


def test_distance_proxy_present_in_every_arm() -> None:
    """SC#2c: each arm carries distance_to_target_mm with the five percentile keys."""
    r = _refit_real()
    for arm in r["arms"]:
        name = arm["name"]
        dtm = arm.get("distance_to_target_mm")
        assert isinstance(dtm, dict), (
            f"{name}.distance_to_target_mm must be a dict"
        )
        assert _PERCENTILE_KEYS <= dtm.keys(), (
            f"{name}.distance_to_target_mm missing keys: {_PERCENTILE_KEYS - dtm.keys()}"
        )


# ── replay shape tests ────────────────────────────────────────────────────────


def test_replay_parses_and_declares_provenance() -> None:
    rp = _replay()
    assert rp["data_source"] == "real", "data_source must be 'real'"
    assert rp["session_id"], "session_id must be non-empty"
    assert _SHA256_RE.match(rp["source_sha256"]), (
        "source_sha256 must be 64 lowercase hex"
    )


def test_two_distinct_seams() -> None:
    """SC#2f: replay carries exactly two seam entries with labels A and B."""
    rp = _replay()
    seams = rp["seams"]
    assert len(seams) == 2, f"expected 2 seams, got {len(seams)}"
    labels = {s["seam"] for s in seams}
    assert labels == {"A", "B"}, f"seam labels must be exactly {{A, B}}, got {labels}"
    for seam in seams:
        label = seam["seam"]
        assert seam.get("boundary"), f"seam {label} must have a non-empty boundary"
    seam_a = next(s for s in seams if s["seam"] == "A")
    for field in ("p50_ns", "p99_ns", "max_ns", "count"):
        val = seam_a[field]
        assert isinstance(val, int), (
            f"seam A.{field} must be int, got {type(val).__name__}"
        )


def test_no_seam_carries_a_perf04_verdict() -> None:
    """D-09 variant: neither seam entry nor the top level carries 'passed' or 'budget_ns'.

    These keys would imply a latency gate was adjudicated inside the artifact,
    which would make a red build pressure to tune measured latency numbers.
    """
    rp = _replay()
    forbidden_keys = {"passed", "budget_ns"}
    for key in forbidden_keys:
        assert key not in rp, f"top-level replay must not carry '{key}'"
    for seam in rp["seams"]:
        for key in forbidden_keys:
            assert key not in seam, (
                f"seam {seam['seam']} must not carry '{key}'"
            )


def test_sc2_disposition_present_but_unasserted() -> None:
    """SC#2 disposition is present and is a valid enum member.

    Asserting the VALUE (met vs not_met) would be a D-09 violation: a red
    build on a measured finding creates pressure to tune that finding.
    Only presence and enum membership are checked here.
    """
    rp = _replay()
    valid_dispositions = {"met", "not_met", "unachievable_at_this_geometry"}
    valid_rules = {"A", "B", "C"}
    assert rp["sc2_disposition"] in valid_dispositions, (
        f"sc2_disposition {rp['sc2_disposition']!r} not in {valid_dispositions}"
    )
    assert rp["sc2_rule"] in valid_rules, (
        f"sc2_rule {rp['sc2_rule']!r} not in {valid_rules}"
    )


def test_seam_data_source_is_declared() -> None:
    rp = _replay()
    for seam in rp["seams"]:
        assert seam.get("data_source") == "real", (
            f"seam {seam['seam']} must declare data_source == 'real'"
        )


def test_every_mac_number_is_labeled_corroborating() -> None:
    """D-17: Mac/M5-Pro numbers must be labeled corroborating, not canonical."""
    rp = _replay()
    for seam in rp["seams"]:
        label = seam["seam"]
        device = seam.get("device", "")
        assert "iPad" not in device, (
            f"seam {label} device {device!r} must not be an iPad"
        )
        assert seam.get("status") == "corroborating", (
            f"seam {label} status must be 'corroborating', got {seam.get('status')!r}"
        )


def test_decomposition_has_all_five_d11_factors() -> None:
    """D-11: the five decomposition factors are all present in the replay artifact."""
    rp = _replay()
    decomp = rp.get("decomposition", {})
    missing = _D11_FACTORS - decomp.keys()
    assert not missing, f"decomposition missing D-11 factors: {missing}"


def test_distance_proxy_is_present_whatever_the_hit_count() -> None:
    """SC#2c replay variant: top-level distance_to_target_mm has the five percentile keys.

    PRESENCE and SHAPE only -- no value is asserted (D-09).
    """
    rp = _replay()
    dtm = rp.get("distance_to_target_mm")
    assert isinstance(dtm, dict), "replay.distance_to_target_mm must be a dict"
    assert _PERCENTILE_KEYS <= dtm.keys(), (
        f"replay.distance_to_target_mm missing keys: {_PERCENTILE_KEYS - dtm.keys()}"
    )


# ── combined provenance tests ─────────────────────────────────────────────────


def test_disclosure_is_verbatim_in_both_artifacts() -> None:
    r = _refit_real()
    rp = _replay()
    for label, artifact in (("refit-real", r), ("replay", rp)):
        assert _VERBATIM_DISCLOSURE in artifact["disclosure"], (
            f"{label} disclosure missing the required verbatim sentence"
        )


# GUARD SPLIT MARKER: do not move or reword this line


def test_no_number_is_a_measured_threshold_assertion() -> None:
    """Verify this module contains no numeric threshold assertions above the marker.

    Forbidden patterns (D-09): co_bps comparison, r2 comparison, p99 comparison,
    bps comparison, tp (Fitts TP) comparison.  These patterns would make CI a
    gate that fires on honest measured numbers, creating pressure to tune them.
    """
    source = Path(__file__).read_text()
    marker = "# GUARD SPLIT MARKER: do not move or reword this line"
    assert marker in source, "guard split marker not found in this file"
    scanned, _, _ = source.partition(marker)
    assert "def test_two_distinct_seams" in scanned, (
        "the guard split marker moved above the tests it is supposed to scan"
    )
    forbidden = (r"co_bps.*>", r"r2.*>", r"p99.*<", r"bps.*>", r"tp.*>")
    for pattern in forbidden:
        matches = re.findall(pattern, scanned)
        assert not matches, (
            f"forbidden pattern {pattern!r} found in scanned portion: {matches}"
        )
