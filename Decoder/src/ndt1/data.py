"""DEC-02 dataset layer: O'Doherty Indy/Loco `.mat` → 20 ms binned spike counts.

Turns a recorded session into the NDT1 training input:

  load_session (h5py, v7.3=HDF5)  →  per-channel spike-timestamp vectors (seconds)
        │
        ▼
  bin_spikes(bin_ms=20.0)         →  float32 (num_bins, 96) spike-count matrix
        │
        ▼
  chronological_split(test_frac)  →  (train, test); test = the chronological TAIL
        │
        ▼
  IndySpikeDataset(seq_len)       →  fixed-length (seq_len, 96) windows for the model

Hard rules enforced here:
  * v7.3 `.mat` is HDF5 → loaded with `h5py`, NEVER the legacy SciPy ``io.loadmat`` reader (it
    cannot read v7.3 — 04-RESEARCH Pitfall #3). MATLAB cell arrays of spike timestamps are HDF5
    object references dereferenced through the file object (`f[ref][()]`).
  * Width is pinned to `CORTEX_CHANNEL_COUNT` (96). A session yielding a different count raises
    `ValueError` rather than silently diverging from the IPC frame width (Pitfall #11, T-04-02-03).
  * The held-out split is the chronological tail — never a shuffle-split across time (Pitfall #10).
  * Only `spikes` and `t` are read; the large `wf` waveform array is never touched (T-04-02-02).
  * No bare/blind `except`: only `OSError`/`KeyError`/`ValueError` are caught explicitly.

Behavior arrays (cursor/finger/target position) are intentionally NOT used in Phase 4 — the
velocity head is DEC-10/Phase 5. Phase 4 trains on binned spike counts alone.
"""
from __future__ import annotations

from pathlib import Path

import h5py
import numpy as np
import torch
from torch.utils.data import Dataset

from ndt1.channel_count import CORTEX_CHANNEL_COUNT

BIN_MS: float = 20.0  # spike-count bin width in milliseconds (DEC-02)
_MS_PER_S: float = 1000.0


def bin_spikes(
    spike_times_per_channel: list[np.ndarray],
    *,
    num_channels: int = CORTEX_CHANNEL_COUNT,
    t_start: float,
    t_end: float,
    bin_ms: float = BIN_MS,
) -> np.ndarray:
    """Bin per-channel spike timestamps into a ``(num_bins, num_channels)`` count matrix.

    Args:
        spike_times_per_channel: one 1-D array of spike timestamps (seconds) per channel; its
            length MUST equal ``num_channels``.
        num_channels: channel width of the output (default ``CORTEX_CHANNEL_COUNT`` = 96).
        t_start: window start (seconds, inclusive).
        t_end: window end (seconds, exclusive).
        bin_ms: bin width in milliseconds (default 20 ms).

    Returns:
        A ``float32`` array of shape ``(num_bins, num_channels)`` where
        ``num_bins == floor((t_end - t_start) / (bin_ms / 1000))``. Each entry is the count of
        spikes in that ``(bin, channel)``. Spikes outside ``[t_start, t_end)`` are dropped.

    Raises:
        ValueError: if the channel count, bin width, or time window is invalid.
    """
    if len(spike_times_per_channel) != num_channels:
        raise ValueError(
            f"spike_times_per_channel has {len(spike_times_per_channel)} channels, "
            f"expected num_channels={num_channels} (Pitfall #11 — width must not diverge)"
        )
    if bin_ms <= 0.0:
        raise ValueError(f"bin_ms must be positive, got {bin_ms}")
    if t_end <= t_start:
        raise ValueError(f"t_end ({t_end}) must be greater than t_start ({t_start})")

    bin_s = bin_ms / _MS_PER_S
    num_bins = int(np.floor((t_end - t_start) / bin_s))
    if num_bins <= 0:
        raise ValueError(
            f"window [{t_start}, {t_end}) s is shorter than one {bin_ms} ms bin (0 bins)"
        )

    binned = np.zeros((num_bins, num_channels), dtype=np.float32)
    for channel, times in enumerate(spike_times_per_channel):
        if times is None or len(times) == 0:
            continue
        t = np.asarray(times, dtype=np.float64).ravel()
        in_range = (t >= t_start) & (t < t_end)
        if not np.any(in_range):
            continue
        bin_idx = np.floor((t[in_range] - t_start) / bin_s).astype(np.intp)
        # Guard the high edge: a spike exactly at t_end-epsilon must land in the last bin.
        np.clip(bin_idx, 0, num_bins - 1, out=bin_idx)
        np.add.at(binned, (bin_idx, channel), 1.0)
    return binned


def chronological_split(
    binned: np.ndarray, *, test_frac: float = 0.2
) -> tuple[np.ndarray, np.ndarray]:
    """Split a binned matrix into ``(train, test)`` where ``test`` is the chronological TAIL.

    The dataset is a continuous self-paced recording (not trial-segmented), so the held-out set
    MUST be the temporal tail — a shuffle-split would leak future bins into training (Pitfall #10).

    Args:
        binned: a ``(num_bins, num_channels)`` matrix in time order.
        test_frac: fraction of bins (from the end) held out for test; must be in ``(0, 1)``.

    Returns:
        ``(train, test)`` = ``(binned[:k], binned[k:])`` with ``k = round(num_bins * (1 - frac))``.
        The two slices never overlap and concatenating them restores the input order.

    Raises:
        ValueError: if ``test_frac`` is not in ``(0, 1)`` or the split degenerates to empty.
    """
    if not 0.0 < test_frac < 1.0:
        raise ValueError(f"test_frac must be in (0, 1), got {test_frac}")
    num_bins = int(binned.shape[0])
    split = int(round(num_bins * (1.0 - test_frac)))
    if split <= 0 or split >= num_bins:
        raise ValueError(
            f"test_frac={test_frac} on {num_bins} bins yields a degenerate split (k={split}); "
            f"need at least one bin in each of train and test"
        )
    return binned[:split], binned[split:]


class IndySpikeDataset(Dataset):
    """Fixed-length ``(seq_len, num_channels)`` windows over a binned spike-count matrix.

    Chunks the continuous binned recording into non-overlapping windows of ``seq_len`` bins
    (≈ ``seq_len * 20 ms``; 30-50 bins ≈ 600-1000 ms per 04-RESEARCH). Any trailing partial
    window shorter than ``seq_len`` is dropped so every sample is full-length.
    """

    def __init__(self, binned: np.ndarray, *, seq_len: int = 32) -> None:
        if seq_len <= 0:
            raise ValueError(f"seq_len must be positive, got {seq_len}")
        arr = np.asarray(binned, dtype=np.float32)
        if arr.ndim != 2:
            raise ValueError(f"binned must be 2-D (num_bins, num_channels), got shape {arr.shape}")
        self._seq_len = seq_len
        self._num_windows = arr.shape[0] // seq_len
        # Keep only the rows that fill complete windows, as a contiguous tensor.
        usable = self._num_windows * seq_len
        self._data = torch.from_numpy(np.ascontiguousarray(arr[:usable]))

    def __len__(self) -> int:
        return self._num_windows

    def __getitem__(self, index: int) -> torch.Tensor:
        if not 0 <= index < self._num_windows:
            raise IndexError(f"window index {index} out of range [0, {self._num_windows})")
        start = index * self._seq_len
        return self._data[start : start + self._seq_len]


def load_session(path: Path) -> dict[str, object]:
    """Load one O'Doherty Indy/Loco session ``.mat`` (v7.3 = HDF5) into binned spike counts.

    Reads ONLY the ``spikes`` cell array (per-(channel,unit) timestamp vectors) and the time
    vector ``t``; the large ``wf`` waveform array is never read (memory-DoS guard, T-04-02-02).
    Spike units (unsorted hash + sorted) are aggregated per channel into a multiunit train, then
    binned at 20 ms. Width is enforced == ``CORTEX_CHANNEL_COUNT`` (96).

    Args:
        path: path to a session ``.mat`` (MATLAB v7.3 = HDF5, loaded with h5py — the legacy
            MATLAB-reader path cannot read v7.3).

    Returns:
        A dict with ``"binned"`` (the ``(num_bins, 96)`` float32 matrix), ``"t_start"``,
        ``"t_end"``, and ``"num_channels"``.

    Raises:
        ValueError: if the session does not yield exactly ``CORTEX_CHANNEL_COUNT`` channels, or
            required datasets are malformed.
        OSError: if the file cannot be opened/read as HDF5.
        KeyError: if the expected ``spikes``/``t`` datasets are absent.
    """
    path = Path(path)
    try:
        with h5py.File(path, "r") as f:
            if "spikes" not in f:
                raise KeyError(f"session {path.name} has no 'spikes' dataset")
            if "t" not in f:
                raise KeyError(f"session {path.name} has no 't' (time) dataset")

            spikes_refs = f["spikes"]  # n_channels × n_units array of HDF5 object references
            # MATLAB stores cell arrays column-major; the channel axis is the larger dimension.
            ref_array = np.asarray(spikes_refs)
            if ref_array.ndim == 1:
                ref_array = ref_array.reshape(-1, 1)
            n_dim0, n_dim1 = ref_array.shape
            # Channels = the axis matching the expected count (h5py may transpose vs MATLAB).
            if n_dim1 == CORTEX_CHANNEL_COUNT and n_dim0 != CORTEX_CHANNEL_COUNT:
                ref_array = ref_array.T
            num_channels = ref_array.shape[0]

            per_channel: list[np.ndarray] = []
            for ch in range(num_channels):
                unit_trains: list[np.ndarray] = []
                for ref in ref_array[ch]:
                    if not ref:  # zero-filled reference = empty cell
                        continue
                    vec = np.asarray(f[ref][()], dtype=np.float64).ravel()
                    if vec.size:
                        unit_trains.append(vec)
                merged = (
                    np.concatenate(unit_trains) if unit_trains else np.empty(0, dtype=np.float64)
                )
                per_channel.append(merged)

            t = np.asarray(f["t"][()], dtype=np.float64).ravel()
            if t.size == 0:
                raise ValueError(f"session {path.name} has an empty time vector 't'")
            t_start = float(t[0])
            t_end = float(t[-1])
    except OSError as exc:
        raise OSError(f"could not read session .mat at {path}: {exc}") from exc

    if num_channels != CORTEX_CHANNEL_COUNT:
        raise ValueError(
            f"session {path.name} yielded {num_channels} channels, expected "
            f"{CORTEX_CHANNEL_COUNT} (use M1-only 96-channel sessions — Pitfall #11)"
        )

    binned = bin_spikes(
        per_channel, num_channels=CORTEX_CHANNEL_COUNT, t_start=t_start, t_end=t_end
    )
    return {
        "binned": binned,
        "t_start": t_start,
        "t_end": t_end,
        "num_channels": CORTEX_CHANNEL_COUNT,
    }
