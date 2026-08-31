"""Firing-rate plausibility band regression tests (RD-02d, D-02).

**Where the band comes from.** Every centre value was MEASURED on `indy_20160630_01` through this
repo's own `ndt1.data.load_session` at 20 ms bins over all units (09-RESEARCH section 3):
per-channel mean 13.76 Hz, median 6.63 Hz, min/max 0.000/51.65 Hz, 6 of 96 channels completely
silent, 9 under 1 Hz, max count in any (bin, channel) 5, and 0.787 of all (bin, channel) entries
zero. The bounds in
`ndt1.qc.PLAUSIBLE_BAND` widen those measurements by judgment. They are EMPIRICAL and explicitly not
a literature constant: no paper was found stating a canonical numeric Hz band for macaque M1
threshold crossings that could be quoted as authoritative, so the derivation is stated here rather
than dressed up as a citation.

**Why population statistics.** A per-channel band such as `assert (rates > 0.5).all()` FAILS on
correctly parsed data, because of those six silent channels, and then gets loosened until it asserts
nothing (09-RESEARCH pitfall P6). The band is therefore population statistics plus an explicit
dead-channel allowance. `test_dead_channels_do_not_fail_the_band` is the control for the first half
of that trap and `test_inflated_density_falls_outside_the_band` is the control for the second: it
proves the band still bites.

Everything runs on the committed `tiny_v73.mat` fixture and on variants generated into `tmp_path`,
so the module is green with `Decoder/data/` empty. No test is marked `slow`.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from types import ModuleType

import numpy as np
import pytest

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.data import load_session
from ndt1.qc import PLAUSIBLE_BAND, band_violations, firing_rate_stats

_TESTS_DIR = Path(__file__).resolve().parent
_DECODER_ROOT = _TESTS_DIR.parent
_FIXTURE = _TESTS_DIR / "fixtures" / "tiny_v73.mat"
_GENERATOR = _DECODER_ROOT / "scripts" / "make_tiny_v73.py"


def _generator() -> ModuleType:
    """Import `scripts/make_tiny_v73.py` by path -- it is a script, not an installed module."""
    spec = importlib.util.spec_from_file_location("make_tiny_v73", _GENERATOR)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load the fixture generator at {_GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _fixture_binned() -> np.ndarray:
    """The committed fixture's `(500, 96)` binned count matrix."""
    binned = load_session(_FIXTURE)["binned"]
    assert isinstance(binned, np.ndarray)
    return binned


# ------------------------------------------------------------------------- firing_rate_stats


def test_stats_report_the_dead_channel_tail() -> None:
    """The fixture's six silent channels are counted, and nothing divides by zero."""
    stats = firing_rate_stats(_fixture_binned())
    assert stats["num_bins"] == 500
    assert stats["num_channels"] == CORTEX_CHANNEL_COUNT
    assert stats["duration_s"] == pytest.approx(10.0)
    assert stats["dead_channels"] == 6
    assert stats["live_channels"] == 90
    assert stats["live_channel_fraction"] == pytest.approx(90.0 / 96.0)
    # The mean is over LIVE channels, so the dead tail does not drag it toward zero.
    assert stats["mean_rate_hz"] == pytest.approx(13.5389, abs=1e-3)
    assert np.isfinite(stats["mean_rate_hz"])


def test_stats_reject_a_non_2d_input() -> None:
    """A 1-D or 3-D matrix is a caller bug, not something to reduce silently."""
    with pytest.raises(ValueError, match="2-D"):
        firing_rate_stats(np.zeros(96, dtype=np.float32))


def test_stats_reject_an_empty_matrix() -> None:
    """Zero bins would make duration_s zero and every rate a division by zero."""
    with pytest.raises(ValueError, match="num_bins"):
        firing_rate_stats(np.zeros((0, 96), dtype=np.float32))


# ------------------------------------------------------------------------- band_violations


def test_fixture_is_inside_the_band() -> None:
    """A correctly parsed session produces ZERO violations -- the band does not over-bite."""
    violations = band_violations(firing_rate_stats(_fixture_binned()))
    assert violations == [], f"the committed fixture fell outside the band: {violations}"


def test_inflated_density_falls_outside_the_band(tmp_path: Path) -> None:
    """The 10x-density negative control: the band bites (09-VALIDATION RD-02d)."""
    inflated = _generator().build_fixture(tmp_path / "inflated_10x.mat", variant="inflated_10x")
    stats = firing_rate_stats(load_session(inflated)["binned"])
    violations = band_violations(stats)
    assert violations, "the 10x-inflated control did NOT bite -- the band asserts nothing"
    assert any("mean_rate_hz" in message for message in violations), violations


def test_all_zero_matrix_violates_live_and_zero_fraction() -> None:
    """An all-zero parse -- the shape a broken cell dereference produces -- is caught."""
    stats = firing_rate_stats(np.zeros((500, CORTEX_CHANNEL_COUNT), dtype=np.float32))
    # No live channel means no denominator; the mean must be 0.0, never nan or a ZeroDivisionError.
    assert stats["live_channels"] == 0
    assert stats["mean_rate_hz"] == 0.0
    violations = band_violations(stats)
    assert any("live_channel_fraction" in message for message in violations), violations
    assert any("zero_fraction" in message for message in violations), violations


def test_dead_channels_do_not_fail_the_band() -> None:
    """P6 control: six MORE silent channels on correct data must not trip the band.

    A per-channel band would fail here on data that is parsed perfectly well. This test is the
    reason `PLAUSIBLE_BAND` is population statistics with a dead-channel allowance.
    """
    binned = _fixture_binned().copy()
    binned[:, :6] = 0.0  # the fixture's own dead tail is channels 90-95, so this makes 12 total
    stats = firing_rate_stats(binned)
    assert stats["dead_channels"] >= 6
    assert band_violations(stats) == [], "a dead-channel allowance is missing from the band"


def test_missing_stat_key_raises() -> None:
    """A bound whose statistic is absent must raise, never be silently skipped."""
    with pytest.raises(KeyError):
        band_violations({}, PLAUSIBLE_BAND)


def test_violation_message_names_bound_value_and_range() -> None:
    """Each violation is readable by an operator: bound name, observed value, allowed range."""
    stats = firing_rate_stats(np.zeros((500, CORTEX_CHANNEL_COUNT), dtype=np.float32))
    messages = band_violations(stats, {"zero_fraction": (0.3, 0.95)})
    assert len(messages) == 1
    message = messages[0]
    assert "zero_fraction" in message
    assert "1.0000" in message
    assert "0.3" in message and "0.95" in message
