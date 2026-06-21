"""Unit tests for the DEC-02 dataset layer: 20 ms binning, chronological split, dataset.

All logic is exercised on deterministic synthetic inputs — no real `.mat` is required (the
O'Doherty Indy/Loco files are gitignored). The one `load_session` test SKIPS when no `.mat`
is present but still imports/type-checks the loader. Pitfalls covered: #3 (v7.3=HDF5 → h5py,
never the legacy MATLAB reader), #10 (chronological tail split, no shuffle leakage),
#11 (width pinned to 96).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.data import (
    BIN_MS,
    IndySpikeDataset,
    bin_spikes,
    chronological_split,
    load_session,
)
from tests.conftest import SEQ_LEN

# ----------------------------------------------------------------------------- bin_spikes


def test_bin_ms_is_20() -> None:
    """The bin width module constant is exactly 20 ms (DEC-02)."""
    assert BIN_MS == 20.0


def test_bin_spikes_known_counts() -> None:
    """Hand-built spike timestamps produce the expected per-20ms-bin count matrix."""
    # Window [0.0, 0.06) s at 20 ms → exactly 3 bins: [0,20), [20,40), [40,60) ms.
    # Channel 0: spikes at 5ms, 10ms (bin0), 25ms (bin1)            -> [2, 1, 0]
    # Channel 1: spike at 45ms (bin2)                                -> [0, 0, 1]
    # Channel 2: empty                                               -> [0, 0, 0]
    spikes_per_channel = [
        np.array([0.005, 0.010, 0.025], dtype=np.float64),
        np.array([0.045], dtype=np.float64),
        np.array([], dtype=np.float64),
    ]
    binned = bin_spikes(
        spikes_per_channel, bin_ms=20.0, num_channels=3, t_start=0.0, t_end=0.06
    )
    assert binned.shape == (3, 3)
    assert binned.dtype == np.float32
    np.testing.assert_array_equal(binned[:, 0], np.array([2.0, 1.0, 0.0], dtype=np.float32))
    np.testing.assert_array_equal(binned[:, 1], np.array([0.0, 0.0, 1.0], dtype=np.float32))
    np.testing.assert_array_equal(binned[:, 2], np.array([0.0, 0.0, 0.0], dtype=np.float32))


def test_bin_spikes_num_bins_is_floor() -> None:
    """num_bins == floor((t_end - t_start) / 0.020) — a partial trailing bin is dropped."""
    # 0.07 s / 0.020 = 3.5 → floor → 3 bins (the trailing 10 ms is not a full bin).
    binned = bin_spikes([np.array([], dtype=np.float64)], num_channels=1, t_start=0.0, t_end=0.07)
    assert binned.shape[0] == 3


def test_bin_spikes_count_conservation() -> None:
    """Total binned counts equal the number of in-range spikes (out-of-range dropped)."""
    rng = np.random.default_rng(0)
    # 96-channel synthetic: random timestamps in [0, 2) s, a few deliberately out of range.
    per_channel = [np.sort(rng.uniform(0.0, 2.0, size=int(rng.integers(0, 8)))) for _ in range(96)]
    # Inject out-of-range spikes (negative + beyond t_end) that must NOT be counted.
    per_channel[0] = np.concatenate([per_channel[0], np.array([-0.5, 5.0])])
    in_range = sum(int(np.sum((c >= 0.0) & (c < 2.0))) for c in per_channel)
    binned = bin_spikes(per_channel, num_channels=96, t_start=0.0, t_end=2.0)
    assert binned.sum() == pytest.approx(float(in_range))


def test_bin_spikes_width_is_96() -> None:
    """The binned matrix width is exactly CORTEX_CHANNEL_COUNT (96) — IPC frame contract."""
    per_channel = [np.array([], dtype=np.float64) for _ in range(CORTEX_CHANNEL_COUNT)]
    binned = bin_spikes(per_channel, num_channels=CORTEX_CHANNEL_COUNT, t_start=0.0, t_end=1.0)
    assert binned.shape[1] == CORTEX_CHANNEL_COUNT
    assert binned.shape[1] == 96


def test_bin_spikes_rejects_wrong_channel_count() -> None:
    """Passing a per-channel list whose length != num_channels raises ValueError (Pitfall #11)."""
    with pytest.raises(ValueError, match="channel"):
        bin_spikes([np.array([0.001])], num_channels=96, t_start=0.0, t_end=0.1)


# -------------------------------------------------------------------- chronological_split


def test_chronological_split_is_tail_no_overlap() -> None:
    """test = the chronological TAIL; train = the head; the two never overlap (Pitfall #10)."""
    binned = np.arange(100 * 96, dtype=np.float32).reshape(100, 96)
    train, test = chronological_split(binned, test_frac=0.2)
    assert train.shape[0] == 80
    assert test.shape[0] == 20
    # Tail property: the test block is exactly the LAST 20 rows, in original order.
    np.testing.assert_array_equal(test, binned[80:])
    np.testing.assert_array_equal(train, binned[:80])
    # No overlap: the max time-index in train precedes the min time-index in test.
    assert float(train[-1, 0]) < float(test[0, 0])


def test_chronological_split_no_shuffle() -> None:
    """The split preserves time order (no shuffle): train then test reconstructs the input."""
    binned = np.arange(50 * 96, dtype=np.float32).reshape(50, 96)
    train, test = chronological_split(binned, test_frac=0.3)
    recombined = np.concatenate([train, test], axis=0)
    np.testing.assert_array_equal(recombined, binned)


def test_chronological_split_rejects_bad_frac() -> None:
    """test_frac outside (0, 1) raises ValueError."""
    binned = np.zeros((10, 96), dtype=np.float32)
    with pytest.raises(ValueError, match="test_frac"):
        chronological_split(binned, test_frac=1.5)


# ------------------------------------------------------------------------ IndySpikeDataset


def test_dataset_window_shape_and_len() -> None:
    """IndySpikeDataset yields fixed-length (seq_len, 96) float32 windows."""
    binned = np.ones((SEQ_LEN * 4, CORTEX_CHANNEL_COUNT), dtype=np.float32)
    ds = IndySpikeDataset(binned, seq_len=SEQ_LEN)
    assert len(ds) == 4  # 4*SEQ_LEN rows / SEQ_LEN → 4 non-overlapping windows
    sample = ds[0]
    assert tuple(sample.shape) == (SEQ_LEN, CORTEX_CHANNEL_COUNT)
    assert sample.dtype.__str__() == "torch.float32"


def test_dataset_drops_incomplete_tail_window() -> None:
    """A trailing partial window (< seq_len rows) is dropped — every sample is full-length."""
    binned = np.ones((SEQ_LEN * 3 + 5, CORTEX_CHANNEL_COUNT), dtype=np.float32)
    ds = IndySpikeDataset(binned, seq_len=SEQ_LEN)
    assert len(ds) == 3
    for i in range(len(ds)):
        assert ds[i].shape[0] == SEQ_LEN


# ------------------------------------------------------------------------------ load_session

_DATA_DIR = Path(__file__).resolve().parents[1] / "data"
_HAS_MAT = _DATA_DIR.is_dir() and any(_DATA_DIR.glob("*.mat"))


@pytest.mark.skipif(not _HAS_MAT, reason="no real .mat present (dataset is gitignored)")
def test_load_session_real_mat() -> None:
    """When a real session .mat exists, load_session returns 96-channel binned counts."""
    mat_path = next(_DATA_DIR.glob("*.mat"))
    session = load_session(mat_path)
    assert "binned" in session
    assert session["binned"].shape[1] == CORTEX_CHANNEL_COUNT


def test_load_session_is_importable_and_typed() -> None:
    """load_session imports + is callable even without data (type-check / contract smoke)."""
    assert callable(load_session)
