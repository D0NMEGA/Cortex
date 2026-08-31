"""Fixture-backed tests for `ndt1.data.load_session` against the committed v7.3 file (RD-02).

Everything here runs on `Decoder/tests/fixtures/tiny_v73.mat` (D-20) and on variants generated
into `tmp_path`, so the whole module is green with `Decoder/data/` empty and takes well under a
second. No test is marked `slow`.

Each assertion has a negative control that fails if the corresponding fix in `data.py` is reverted:

  RD-02a  `MATLAB_empty` cells contribute no counts -- controlled by the `no_matlab_empty` variant
  RD-02b  the channel-axis transpose, and a 192-channel file naming its true width
  RD-02c  the `finger_pos` planar pair is rows 1-2 -- controlled by the near-constant row 0
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any

import h5py
import numpy as np
import pytest

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.data import BIN_MS, bin_spikes, load_session

_MAT_V73_MAGIC = b"MATLAB 7.3 MAT-f"
_BIN_S = BIN_MS / 1000.0
_DATA_SOURCE = Path(__file__).resolve().parents[1] / "src" / "ndt1" / "data.py"

_TESTS_DIR = Path(__file__).resolve().parent
_DECODER_ROOT = _TESTS_DIR.parent
_FIXTURE = _TESTS_DIR / "fixtures" / "tiny_v73.mat"
_TRUTH = _TESTS_DIR / "fixtures" / "tiny_v73.truth.json"
_GENERATOR = _DECODER_ROOT / "scripts" / "make_tiny_v73.py"


def _generator() -> ModuleType:
    """Import `scripts/make_tiny_v73.py` by path -- it is a script, not an installed module."""
    spec = importlib.util.spec_from_file_location("make_tiny_v73", _GENERATOR)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load the fixture generator at {_GENERATOR}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _build(tmp_path: Path, variant: str) -> tuple[Path, dict[str, Any]]:
    """Build a variant into `tmp_path` and return `(mat_path, ground_truth)`."""
    out = tmp_path / f"{variant}.mat"
    _generator().build_fixture(out, variant=variant)
    truth: dict[str, Any] = json.loads(out.with_suffix(".truth.json").read_text(encoding="utf-8"))
    return out, truth


def _truth() -> dict[str, Any]:
    """Ground truth recorded by the generator when it wrote the committed fixture."""
    loaded: dict[str, Any] = json.loads(_TRUTH.read_text(encoding="utf-8"))
    return loaded


def _finger_pos() -> np.ndarray:
    """Read `finger_pos` out of the committed fixture directly, bypassing the loader."""
    with h5py.File(_FIXTURE, "r") as f:
        return np.asarray(f["finger_pos"][()], dtype=np.float64)


def _array(session: dict[str, object], key: str) -> np.ndarray:
    """Pull one array out of `load_session`'s `dict[str, object]` return with a concrete type."""
    return np.asarray(session[key], dtype=np.float64)


def _per_channel_trains() -> list[np.ndarray]:
    """Read the fixture's 96 multiunit trains straight from HDF5, skipping `MATLAB_empty` cells.

    Used only to feed `bin_spikes` directly in the windowing tests, so those exercise the binner
    rather than the loader.
    """
    trains: list[np.ndarray] = []
    with h5py.File(_FIXTURE, "r") as f:
        refs = np.asarray(f["spikes"]).T  # h5py gives (n_units, n_channels)
        for channel in range(refs.shape[0]):
            units = [
                np.asarray(f[ref][()], dtype=np.float64).ravel()
                for ref in refs[channel]
                if "MATLAB_empty" not in f[ref].attrs
            ]
            trains.append(np.concatenate(units) if units else np.empty(0, dtype=np.float64))
    return trains


# --------------------------------------------------------------------------- the fixture


def test_fixture_is_tracked_and_v73() -> None:
    """The committed fixture exists and is a genuine MATLAB v7.3 file, not a bare HDF5 blob."""
    assert _FIXTURE.is_file(), f"missing committed fixture at {_FIXTURE}"
    assert _FIXTURE.read_bytes()[:16] == _MAT_V73_MAGIC
    assert _TRUTH.is_file(), f"missing generator ground truth at {_TRUTH}"


# ------------------------------------------------------------------------------ RD-02a


def test_empty_cells_contribute_no_counts() -> None:
    """Total binned counts equal the real timestamps the generator wrote -- empties add zero.

    The bin-0 assertion is the sharp one. The committed fixture's clock starts at 0.0, so the
    spurious 0.0-valued timestamps a `if not ref` guard would inject all land in bin 0.
    """
    truth = _truth()
    binned = _array(load_session(_FIXTURE), "binned")
    assert float(binned.sum()) == pytest.approx(float(truth["total_real_timestamps"]))
    assert float(binned[0].sum()) == pytest.approx(float(truth["bin0_real_timestamps"]))


def test_matlab_empty_attribute_is_the_discriminator(tmp_path: Path) -> None:
    """The `no_matlab_empty` variant yields strictly MORE counts than the clean fixture.

    This is the control proving the attribute check, not luck, is what does the work: the two
    files are byte-for-byte equivalent apart from the `MATLAB_empty` attribute, so any difference
    in the loaded counts is attributable to that attribute alone.
    """
    variant_path, _ = _build(tmp_path, "no_matlab_empty")
    clean_total = float(_array(load_session(_FIXTURE), "binned").sum())
    variant_total = float(_array(load_session(variant_path), "binned").sum())
    assert variant_total > clean_total


# ------------------------------------------------------------------------------ RD-02b


def test_192_channel_session_raises_naming_the_true_width(tmp_path: Path) -> None:
    """A 192-channel M1+S1 structure raises a ValueError naming 192 and `chan_names`.

    h5py reports such a file as `(3, 192)`: neither axis is 96, no transpose fires, and the old
    message reported the UNIT count ("yielded 3 channels"), leaving the operator no way to tell
    this was an M1+S1 recording.
    """
    variant_path, _ = _build(tmp_path, "width_192")
    with pytest.raises(ValueError) as excinfo:
        load_session(variant_path)
    message = str(excinfo.value)
    assert "192" in message, message
    assert "chan_names" in message, message


# ------------------------------------------------------------------------------ RD-02c


def test_finger_pos_planar_pair_is_rows_1_and_2() -> None:
    """`planar_cm` is `(n_samples, 2)` and BOTH columns vary -- the rows-0-1 control.

    The fixture's `finger_pos` row 0 is the near-constant depth axis, so an extractor taking rows
    0-1 would put a flat signal into column 0 and fail the `std() >= 1.0` assertion below.
    """
    finger = _finger_pos()
    planar = _array(load_session(_FIXTURE), "planar_cm")
    assert planar.shape == (finger.shape[1], 2), planar.shape
    assert planar.std(axis=0).min() >= 1.0, planar.std(axis=0)
    # The control that makes the assertion above meaningful.
    assert float(np.std(finger[0])) <= 0.01, float(np.std(finger[0]))


def test_finger_pos_sign_is_undone() -> None:
    """`planar_cm` columns are the NEGATED `finger_pos` rows 1-2, i.e. true (x, y) in cm."""
    finger = _finger_pos()
    planar = _array(load_session(_FIXTURE), "planar_cm")
    assert float(np.corrcoef(planar[:, 0], -finger[1])[0, 1]) > 0.99
    assert float(np.corrcoef(planar[:, 1], -finger[2])[0, 1]) > 0.99


def test_channel_axis_transpose_is_correct() -> None:
    """The `(5, 96)` fixture loads as 96 channels -- the existing transpose heuristic is right."""
    session = load_session(_FIXTURE)
    assert session["num_channels"] == CORTEX_CHANNEL_COUNT
    assert _array(session, "binned").shape[1] == CORTEX_CHANNEL_COUNT


def test_six_row_finger_pos_uses_the_same_planar_rows(tmp_path: Path) -> None:
    """A `(6, k)` finger_pos -- the real Indy row count -- yields the same rows-1-2 planar pair.

    The extra rows are azimuth, elevation and roll; they must not shift the planar indices.
    """
    variant_path, truth = _build(tmp_path, "finger6")
    with h5py.File(variant_path, "r") as f:
        finger = np.asarray(f["finger_pos"][()], dtype=np.float64)
    assert finger.shape[0] == 6
    planar = _array(load_session(variant_path), "planar_cm")
    assert planar.shape == (int(truth["n_samples"]), 2), planar.shape
    assert planar.std(axis=0).min() >= 1.0, planar.std(axis=0)
    assert float(np.corrcoef(planar[:, 0], -finger[1])[0, 1]) > 0.99
    assert float(np.corrcoef(planar[:, 1], -finger[2])[0, 1]) > 0.99


# ---------------------------------------------------------------- windowing controls (P10)


def test_out_of_window_spikes_are_dropped() -> None:
    """Timestamps below `t_start` or at/above `t_end` never reach the binned matrix."""
    truth = _truth()
    t_start = float(truth["t_start"])
    t_end = float(truth["t_end"])
    trains = _per_channel_trains()
    assert sum(int(train.size) for train in trains) == int(truth["total_real_timestamps"])

    polluted = list(trains)
    polluted[0] = np.concatenate(
        [trains[0], np.array([t_start - 1.0, -0.001, t_end, t_end + 1.0], dtype=np.float64)]
    )
    binned = bin_spikes(
        polluted, num_channels=CORTEX_CHANNEL_COUNT, t_start=t_start, t_end=t_end
    )
    assert float(binned.sum()) == pytest.approx(float(truth["total_real_timestamps"]))


def test_trailing_partial_bin_is_clipped_into_the_last_bin() -> None:
    """`num_bins == floor((t_end - t_start) / 20 ms)`, and the last representable instant lands
    in the final bin rather than one past it."""
    truth = _truth()
    t_start = float(truth["t_start"])
    t_end = float(truth["t_end"])
    expected_bins = int(np.floor((t_end - t_start) / _BIN_S))
    binned = _array(load_session(_FIXTURE), "binned")
    assert binned.shape[0] == expected_bins == int(truth["num_bins"])

    # `t_end - 1e-9` and the largest float strictly below `t_end` must both land in bin
    # `expected_bins - 1`; the second is what the binner's np.clip high-edge guard exists for.
    for late in (t_end - 1e-9, float(np.nextafter(t_end, 0.0))):
        edge = bin_spikes(
            [np.array([late], dtype=np.float64)],
            num_channels=1,
            t_start=t_start,
            t_end=t_end,
        )
        assert edge.shape[0] == expected_bins
        assert float(edge[-1, 0]) == 1.0, late
        assert float(edge.sum()) == 1.0, late


# -------------------------------------------------------------------- wf guard (T-04-02-02)


def test_wf_is_never_opened() -> None:
    """The fixture carries a `wf` array; the loader neither reads it nor returns anything from it.

    The memory-DoS guard: `wf` is the large waveform array, and opening it on a real 1.5 GB
    session is the failure T-04-02-02 exists to prevent.
    """
    with h5py.File(_FIXTURE, "r") as f:
        assert "wf" in f, "the fixture must carry a wf array for this guard to mean anything"
    session = load_session(_FIXTURE)
    assert not any("wf" in key for key in session), sorted(session)
    source = _DATA_SOURCE.read_text(encoding="utf-8")
    assert 'f["wf"]' not in source
    assert "f['wf']" not in source
