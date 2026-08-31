"""Multi-session load, per-session split and LOSO rotation tests (D-11, D-12, D-13, D-03).

Two failure modes are pinned here, both of which are silent rather than loud:

  * A single rejected `.mat` must not abort the run. `test_rejected_session_is_excluded_not_raised`
    deliberately names its 192-channel file so it sorts FIRST in the directory, which is exactly the
    ordering that makes today's alphabetically-first-`.mat` code crash (09-RESEARCH pitfall P5). The
    exclusion must carry the loader's own message, so an operator can see the measured width.
  * A pooled shuffle would leak future bins into training. `test_pooled_splits_are_chronological`
    pins that `pooled_splits` is a per-session chronological tail (D-12, 04-RESEARCH pitfall #10),
    and `test_loso_is_a_full_rotation` pins that each session is held out exactly once (D-13).

Everything runs on the committed `tiny_v73.mat` fixture copied into `tmp_path` and on variants
generated there, so the module is green with `Decoder/data/` empty. No test is marked `slow`.
"""
from __future__ import annotations

import importlib.util
import shutil
from pathlib import Path
from types import ModuleType

import numpy as np
import pytest

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.sessions import (
    SessionExclusion,
    SessionLoad,
    available_sessions,
    loso_folds,
    pooled_splits,
)

_TESTS_DIR = Path(__file__).resolve().parent
_DECODER_ROOT = _TESTS_DIR.parent
_FIXTURE = _TESTS_DIR / "fixtures" / "tiny_v73.mat"
_GENERATOR = _DECODER_ROOT / "scripts" / "make_tiny_v73.py"

# The committed fixture is 500 bins; a 192-channel variant is the file the loader must reject.
_FIXTURE_BINS = 500


def _generator() -> ModuleType:
    """Import `scripts/make_tiny_v73.py` by path -- it is a script, not an installed module."""
    spec = importlib.util.spec_from_file_location("make_tiny_v73", _GENERATOR)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load the fixture generator at {_GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _place_good_session(data_dir: Path, name: str = "indy_20160630_01.mat") -> Path:
    """Copy the committed fixture into `data_dir` under a realistic session filename."""
    destination = data_dir / name
    shutil.copyfile(_FIXTURE, destination)
    return destination


# ------------------------------------------------------------------------ available_sessions


def test_empty_data_dir_returns_nothing(tmp_path: Path) -> None:
    """An empty data dir yields no sessions and no exclusions, and does not raise."""
    assert available_sessions(tmp_path) == ([], [])


def test_absent_data_dir_returns_nothing(tmp_path: Path) -> None:
    """A data dir that does not exist at all is the normal state of a fresh checkout."""
    assert available_sessions(tmp_path / "does-not-exist") == ([], [])


def test_rejected_session_is_excluded_not_raised(tmp_path: Path) -> None:
    """A 192-channel file that sorts FIRST is excluded with its measured width, not raised (P5)."""
    # `indy_00000000_00` sorts ahead of every real session id, which is the ordering that makes
    # the alphabetically-first-`.mat` pattern crash the whole suite.
    _generator().build_fixture(tmp_path / "indy_00000000_00.mat", variant="width_192")
    _place_good_session(tmp_path)

    loaded, excluded = available_sessions(tmp_path)

    assert len(loaded) == 1
    assert loaded[0].session_id == "indy_20160630_01"
    assert len(excluded) == 1
    assert excluded[0].session_id == "indy_00000000_00"
    assert "192" in excluded[0].reason, excluded[0].reason
    assert "ValueError" in excluded[0].reason, excluded[0].reason


def test_short_session_is_excluded_with_a_reason(tmp_path: Path) -> None:
    """A session too short to split into train and test windows is excluded, with the count."""
    _place_good_session(tmp_path)
    loaded, excluded = available_sessions(tmp_path, min_bins=10_000)

    assert loaded == []
    assert len(excluded) == 1
    assert str(_FIXTURE_BINS) in excluded[0].reason, excluded[0].reason
    assert "10000" in excluded[0].reason, excluded[0].reason


def test_session_load_carries_the_full_record(tmp_path: Path) -> None:
    """Every loaded session carries its arrays, its window, its stats and its band violations."""
    path = _place_good_session(tmp_path)
    loaded, excluded = available_sessions(tmp_path)
    assert excluded == []
    session = loaded[0]

    assert isinstance(session, SessionLoad)
    assert session.path == path
    assert session.binned.shape == (_FIXTURE_BINS, CORTEX_CHANNEL_COUNT)
    assert session.planar_cm.ndim == 2 and session.planar_cm.shape[1] == 2
    assert session.t.shape[0] == session.planar_cm.shape[0]
    assert session.t_start == pytest.approx(0.0)
    assert session.t_end == pytest.approx(10.0)
    assert session.stats["num_channels"] == CORTEX_CHANNEL_COUNT
    assert session.stats["dead_channels"] == 6
    # A correctly parsed session is inside the band, but a violation is surfaced rather than
    # auto-excluded: D-03 requires the exclusion to be a documented decision.
    assert session.band_violations == []


def test_band_violations_do_not_auto_exclude(tmp_path: Path) -> None:
    """A session outside the plausibility band still LOADS, with its violations attached (D-03)."""
    _generator().build_fixture(tmp_path / "indy_19700101_01.mat", variant="inflated_10x")
    loaded, excluded = available_sessions(tmp_path)

    assert excluded == [], "a band violation must not be a silent drop"
    assert len(loaded) == 1
    assert loaded[0].band_violations, "the 10x session should carry violations"
    assert any("mean_rate_hz" in message for message in loaded[0].band_violations)


def test_exclusion_is_a_typed_record(tmp_path: Path) -> None:
    """Exclusions come back as data, not as log lines that vanish."""
    built = _generator().build_fixture(tmp_path / "indy_00000000_00.mat", variant="width_192")
    _loaded, excluded = available_sessions(tmp_path)
    assert isinstance(excluded[0], SessionExclusion)
    assert excluded[0].path == built


# ----------------------------------------------------------------------------- pooled_splits


def test_pooled_splits_are_chronological(tmp_path: Path) -> None:
    """Per-session chronological tail: concatenating train and test restores the input (D-12)."""
    _place_good_session(tmp_path, "indy_20160630_01.mat")
    _place_good_session(tmp_path, "indy_20160915_01.mat")
    loaded, _excluded = available_sessions(tmp_path)
    assert len(loaded) == 2

    splits = pooled_splits(loaded, test_frac=0.2)

    assert [session_id for session_id, _train, _test in splits] == [
        "indy_20160630_01",
        "indy_20160915_01",
    ]
    for (session_id, train, test), session in zip(splits, loaded, strict=True):
        assert session_id == session.session_id
        np.testing.assert_array_equal(np.concatenate([train, test], axis=0), session.binned)
        expected_test = round(session.binned.shape[0] * 0.2)
        assert abs(test.shape[0] - expected_test) <= 1
        # No pooled shuffle: the test block is literally the tail rows of this session.
        np.testing.assert_array_equal(test, session.binned[train.shape[0] :])


# -------------------------------------------------------------------------------- loso_folds


def test_loso_is_a_full_rotation() -> None:
    """Four sessions give four folds; each is held out exactly once against the other three."""
    ids = ["indy_20160630_01", "indy_20160915_01", "indy_20161005_06", "indy_20170131_02"]
    folds = loso_folds(ids)

    assert len(folds) == len(ids)
    assert sorted(str(fold["held_out"]) for fold in folds) == sorted(ids)
    for fold in folds:
        train_ids = fold["train_ids"]
        assert isinstance(train_ids, list)
        assert len(train_ids) == len(ids) - 1
        assert fold["held_out"] not in train_ids
        assert sorted([*train_ids, fold["held_out"]]) == sorted(ids)


def test_loso_rejects_a_single_session() -> None:
    """One session cannot be a leave-one-out rotation; a single held-out set is not a claim."""
    with pytest.raises(ValueError, match="at least two"):
        loso_folds(["indy_20160630_01"])


def test_loso_rejects_duplicate_session_ids() -> None:
    """A duplicate id would put the same session in both train and held-out -- silent leakage."""
    with pytest.raises(ValueError, match="duplicate"):
        loso_folds(["indy_20160630_01", "indy_20160630_01", "indy_20160915_01"])
