"""D-01 target-track tests: the last-sample-per-bin rule and its mean-aggregation control.

`target_pos` is a step function on a 15 mm discrete grid. Averaging across a bin that spans a
target change emits an off-grid target the subject never saw, which is the fabrication D-01 exists
to prevent (10-RESEARCH Pitfall 4). Every assertion below is either on a synthetic array or on the
committed `tiny_v73.mat`, so the module is green with `Decoder/data/` empty and no test is `slow`.

The sharp test is `test_bin_target_track_emits_no_value_off_the_input_grid`: a mean aggregator
passes every other test in this file and fails that one, because it emits the midpoint of the two
grid points the bin spans.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import h5py
import numpy as np
import pytest

from ndt1.data import BIN_MS, bin_target_track, first_off_grid_index, load_session
from ndt1.kinematics import bin_velocity
from ndt1.sessions import available_sessions

_TESTS_DIR = Path(__file__).resolve().parent
_FIXTURE = _TESTS_DIR / "fixtures" / "tiny_v73.mat"
_TRUTH = _TESTS_DIR / "fixtures" / "tiny_v73.truth.json"

_BIN_S = BIN_MS / 1000.0
_FS_HZ = 250.0  # the Indy behavior clock the fixture reproduces
_SAMPLES_PER_BIN = int(round(_FS_HZ * _BIN_S))  # 5


def _clock(n_samples: int) -> np.ndarray:
    """A uniform 250 Hz behavior clock starting at exactly 0.0 s, as the fixture writes it."""
    return np.arange(n_samples, dtype=np.float64) / _FS_HZ


def _truth() -> dict[str, Any]:
    """Ground truth recorded by the generator when it wrote the committed fixture."""
    loaded: dict[str, Any] = json.loads(_TRUTH.read_text(encoding="utf-8"))
    return loaded


def _expected_track(truth: dict[str, Any]) -> np.ndarray:
    """Expand the truth sidecar's run-length target track into a `(num_bins, 2)` array.

    The generator recorded the runs from a closed-form expression (the target value at sample
    `5 * i + 4`, the last sample of bin `i` on the fixture's uniform clock), not by calling the
    binner, so this is independent ground truth rather than a restatement of the code under test.
    """
    runs = truth["target_track_runs"]
    num_bins = int(truth["num_bins"])
    track = np.zeros((num_bins, 2), dtype=np.float64)
    for index, run in enumerate(runs):
        start = int(run[0])
        stop = int(runs[index + 1][0]) if index + 1 < len(runs) else num_bins
        track[start:stop] = (float(run[1]), float(run[2]))
    return track


def _array(session: dict[str, object], key: str) -> np.ndarray:
    """Pull one array out of `load_session`'s `dict[str, object]` return with a concrete type."""
    return np.asarray(session[key], dtype=np.float64)


def _pairs(track: np.ndarray) -> set[tuple[float, float]]:
    """The distinct `(x, y)` pairs in a `(n, 2)` track, as a comparable set."""
    return {(float(row[0]), float(row[1])) for row in np.asarray(track, dtype=np.float64)}


# ------------------------------------------------------------------ the aggregation rule (D-01)


def test_bin_target_track_takes_the_last_sample_in_the_bin() -> None:
    """A track that steps MID-BIN emits the POST-step value for the bin that spans the step."""
    t = _clock(25)  # 0.000 .. 0.096 s: 5 bins of 20 ms, 5 samples each
    target = np.zeros((25, 2), dtype=np.float64)
    target[7:] = (15.0, 0.0)  # sample 7 is the third of bin 1's five samples (5, 6, 7, 8, 9)

    track = bin_target_track(target, t, t_start=0.0, t_end=0.1)

    assert track.shape == (5, 2)
    assert tuple(track[0]) == (0.0, 0.0)
    assert tuple(track[1]) == (15.0, 0.0), "bin 1's LAST sample (index 9) is post-step"
    assert tuple(track[2]) == (15.0, 0.0)


def test_bin_target_track_emits_no_value_off_the_input_grid() -> None:
    """The Pitfall-4 control: every emitted pair is a member of the input's distinct pairs.

    A mean aggregator emits `(7.5, 0.0)` for the bin spanning the change -- a target on no grid
    the subject ever saw. This is the one test in the file that a mean aggregator fails.
    """
    t = _clock(25)
    target = np.zeros((25, 2), dtype=np.float64)
    target[7:] = (15.0, 0.0)
    grid = {(0.0, 0.0), (15.0, 0.0)}

    emitted = _pairs(bin_target_track(target, t, t_start=0.0, t_end=0.1))

    assert emitted <= grid, emitted
    assert (7.5, 0.0) not in emitted, "a mean aggregator fabricated an off-grid target"


def test_bin_target_track_row_count_matches_bin_velocity() -> None:
    """The target track lands on the SAME bin edges as the velocity, row for row."""
    t = _clock(2501)  # 0.0 .. 10.0 s
    t_start, t_end = float(t[0]), float(t[-1])
    velocity = np.stack([np.sin(t), np.cos(t)], axis=1)
    target = np.zeros((t.size, 2), dtype=np.float64)
    target[1234:] = (15.0, 15.0)

    binned_velocity = bin_velocity(velocity, t, t_start=t_start, t_end=t_end)
    track = bin_target_track(target, t, t_start=t_start, t_end=t_end)

    assert track.shape == binned_velocity.shape
    assert track.shape[0] == int(np.floor((t_end - t_start) / _BIN_S))


def test_bin_target_track_raises_naming_the_first_empty_bin() -> None:
    """An unfilled bin raises rather than emitting a NaN or carrying the previous bin forward."""
    t = np.concatenate([_clock(5), 0.06 + _clock(10)])  # bins 1 and 2 hold no sample
    target = np.zeros((t.size, 2), dtype=np.float64)

    with pytest.raises(ValueError) as excinfo:
        bin_target_track(target, t, t_start=0.0, t_end=0.1)

    message = str(excinfo.value)
    assert "target bin 1" in message, message


def test_bin_target_track_rejects_a_non_monotone_clock() -> None:
    """Out-of-order timestamps make "the last sample" ambiguous, so they raise instead."""
    t = _clock(10)
    t[6], t[7] = t[7], t[6]
    target = np.zeros((10, 2), dtype=np.float64)

    with pytest.raises(ValueError) as excinfo:
        bin_target_track(target, t, t_start=0.0, t_end=0.04)

    assert "monotone" in str(excinfo.value)


def test_first_off_grid_index_catches_the_mean_aggregation_artifact() -> None:
    """The membership guard reports the offending ROW INDEX, and passes a clean track."""
    distinct = np.array([[0.0, 0.0], [15.0, 0.0]], dtype=np.float64)
    clean = np.array([[0.0, 0.0], [15.0, 0.0], [15.0, 0.0]], dtype=np.float64)
    assert first_off_grid_index(clean, distinct) is None

    # (7.5, 0.0) is exactly what a mean aggregator emits for a bin spanning the two grid points.
    fabricated = np.array([[0.0, 0.0], [7.5, 0.0], [15.0, 0.0]], dtype=np.float64)
    assert first_off_grid_index(fabricated, distinct) == 1


# -------------------------------------------------------------- load_session (D-01 loader change)


def test_fixture_exercises_a_mid_bin_step() -> None:
    """The committed fixture genuinely spans a target change inside a bin.

    Without this the last-sample rule would be untested on the fixture: a track that only ever
    steps on a bin boundary is aggregated identically by every rule, including the mean.
    """
    truth = _truth()
    assert int(truth["target_mid_bin_steps"]) >= 1, truth["target_step_sample_indices"]
    assert float(truth["target_pitch_mm"]) == 15.0


def test_load_session_returns_a_target_track_on_the_session_grid() -> None:
    """`target_mm` is `(num_bins, 2)` and every row is one of the session's observed pairs."""
    truth = _truth()
    session = load_session(_FIXTURE)
    track = _array(session, "target_mm")
    distinct = _array(session, "target_distinct")

    assert track.shape == (int(truth["num_bins"]), 2)
    assert distinct.shape == (len(truth["target_distinct_mm"]), 2)
    assert _pairs(track) <= _pairs(distinct)
    assert _pairs(distinct) == {(float(x), float(y)) for x, y in truth["target_distinct_mm"]}


def test_load_session_target_track_matches_the_generator_truth() -> None:
    """The per-bin track equals the generator's independently-recorded expectation, row for row."""
    session = load_session(_FIXTURE)
    np.testing.assert_array_equal(_array(session, "target_mm"), _expected_track(_truth()))


def test_load_session_raises_naming_the_session_when_target_pos_is_absent(
    tmp_path: Path,
) -> None:
    """D-01 makes `target_pos` required: an older session without it fails loudly."""
    stripped = tmp_path / "no_target.mat"
    shutil.copy(_FIXTURE, stripped)
    with h5py.File(stripped, "r+") as handle:
        del handle["target_pos"]

    with pytest.raises(KeyError) as excinfo:
        load_session(stripped)

    assert "no_target.mat" in str(excinfo.value)
    assert "target_pos" in str(excinfo.value)


def test_session_load_carries_the_target_track(tmp_path: Path) -> None:
    """`SessionLoad` exposes both target arrays -- no default, so a missing one cannot be `None`."""
    shutil.copy(_FIXTURE, tmp_path / "indy_20160630_01.mat")
    loaded, excluded = available_sessions(tmp_path)

    assert excluded == [], excluded
    assert len(loaded) == 1
    session = loaded[0]
    assert session.target_mm.shape == (int(_truth()["num_bins"]), 2)
    assert session.target_distinct.shape[1] == 2
    assert _pairs(session.target_mm) <= _pairs(session.target_distinct)


def test_the_target_track_is_row_aligned_with_the_binned_spikes() -> None:
    """`binned`, `target_mm` and `bin_velocity`'s output all carry the same row count."""
    session = load_session(_FIXTURE)
    binned = _array(session, "binned")
    assert _array(session, "target_mm").shape[0] == binned.shape[0]
    assert binned.shape[1] == int(_truth()["n_channels"])


def test_the_last_sample_of_a_bin_is_what_the_fixture_track_reports() -> None:
    """Read `target_pos` straight from HDF5 and confirm the emitted rows are its bin-end samples.

    This bypasses both the loader and the truth sidecar: bin `i` on the fixture's uniform clock
    ends at sample `5 * i + 4`, so the emitted row must equal that sample exactly.
    """
    with h5py.File(_FIXTURE, "r") as handle:
        target = np.asarray(handle["target_pos"][()], dtype=np.float64)  # (2, n_samples)

    track = _array(load_session(_FIXTURE), "target_mm")
    bin_end = np.arange(track.shape[0]) * _SAMPLES_PER_BIN + (_SAMPLES_PER_BIN - 1)
    np.testing.assert_array_equal(track, target[:, bin_end].T)
