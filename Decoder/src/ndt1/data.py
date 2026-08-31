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
    The width named in that error comes from `chan_names`, which is authoritative, so a 192-channel
    M1+S1 file is announced as 192 rather than as its unit count.
  * An EMPTY MATLAB cell is discriminated by its `MATLAB_empty` attribute, never by `bool(ref)`:
    MATLAB writes empty cells as TRUTHY references (09-RESEARCH C-05, T-09-02-01).
  * The held-out split is the chronological tail — never a shuffle-split across time (Pitfall #10).
  * Only `spikes`, `t`, `finger_pos` and `chan_names` are read; the `wf` array is never touched.
  * No bare/blind `except`: only `OSError`/`KeyError`/`ValueError` are caught explicitly.

Behavior arrays: as of Phase 9 (D-05) `finger_pos` IS read, because the shipped `.mlpackage` must
carry a velocity readout fit on real kinematics rather than a fabricated one. Only `finger_pos` is
read; `cursor_pos` and `target_pos` are not, and the large `wf` array is still never touched
(T-04-02-02). `finger_pos` rows are `(z, -x, -y[, azimuth, elevation, roll])` in cm, so the planar
pair is rows 1 and 2 and the negation is undone once, here.
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

    Reads ONLY the ``spikes`` cell array (per-(channel,unit) timestamp vectors), the time vector
    ``t``, ``finger_pos`` (D-05) and ``chan_names``; the ``wf`` array is never read (memory-DoS
    guard, T-04-02-02). Spike units (unsorted hash + sorted) are aggregated per channel into a
    multiunit train, then binned at 20 ms. Width is enforced == ``CORTEX_CHANNEL_COUNT`` (96).

    Args:
        path: path to a session ``.mat`` (MATLAB v7.3 = HDF5, loaded with h5py — the legacy
            MATLAB-reader path cannot read v7.3).

    Returns:
        A dict with ``"binned"`` (the ``(num_bins, 96)`` float32 matrix), ``"t_start"``,
        ``"t_end"``, ``"num_channels"``, ``"t"`` (the raw time vector, seconds) and
        ``"planar_cm"`` (the ``(n_samples, 2)`` sign-corrected ``(x, y)`` kinematics in cm).

    Raises:
        ValueError: if the session does not yield exactly ``CORTEX_CHANNEL_COUNT`` channels, or
            required datasets are malformed.
        OSError: if the file cannot be opened/read as HDF5.
        KeyError: if the expected ``spikes``/``t``/``finger_pos`` datasets are absent.
    """
    path = Path(path)
    try:
        with h5py.File(path, "r") as f:
            if "spikes" not in f:
                raise KeyError(f"session {path.name} has no 'spikes' dataset")
            if "t" not in f:
                raise KeyError(f"session {path.name} has no 't' (time) dataset")

            # `chan_names` is the AUTHORITATIVE width (96 for M1-only, 192 for M1+S1). The
            # transpose heuristic below cannot recover it when neither spikes axis is 96, so
            # capture it here and name it in the width error (T-04-02-03, T-09-02-02).
            declared_width: int | None = None
            if "chan_names" in f:
                declared_width = int(np.asarray(f["chan_names"]).size)

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
                    if not ref:  # a genuinely null HDF5 reference
                        continue
                    dataset = f[ref]
                    # MATLAB writes an EMPTY cell as a TRUTHY reference to a (2,) uint64 dataset
                    # whose payload is the array dimensions and which carries a MATLAB_empty
                    # attribute — `if not ref` never fires on it. On indy_20160630_01 the old
                    # guard injected 498 spurious timestamps (values 0.0 and 1.0) across 92 of 96
                    # channels; they were discarded only because that session's clock starts at
                    # t = 148.984 s. A session whose clock starts near zero would silently corrupt
                    # every rate (09-RESEARCH C-05, T-09-02-01).
                    if "MATLAB_empty" in dataset.attrs:
                        continue
                    vec = np.asarray(dataset[()], dtype=np.float64).ravel()
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

            if "finger_pos" not in f:
                raise KeyError(f"session {path.name} has no 'finger_pos' dataset")
            finger = np.asarray(f["finger_pos"][()], dtype=np.float64)
            if finger.ndim != 2 or finger.shape[0] not in (3, 6):
                raise ValueError(
                    f"session {path.name} finger_pos has shape {finger.shape}; expected (3, k) "
                    f"or (6, k) as h5py sees it (MATLAB k x 3 or k x 6)"
                )
            if finger.shape[1] != t.size:
                raise ValueError(
                    f"session {path.name} finger_pos has {finger.shape[1]} samples but t has "
                    f"{t.size}"
                )
            # finger_pos rows are (z, -x, -y[, azimuth, elevation, roll]) in cm — the PLANAR pair
            # is rows 1 and 2, NOT rows 0 and 1. Row 0 is depth (std ~0.24 cm on
            # indy_20160630_01); taking rows 0-1 raises no exception and would silently halve the
            # decode R2 (09-RESEARCH C-02 / P4). Verified: corr(cursor_pos[0], finger_pos[1]) ==
            # -1.0000. Negate once here so downstream code and the Phase-10 R fit see true (x, y)
            # in cm rather than inheriting the sign implicitly.
            planar_cm = (-finger[1:3, :]).T  # (n_samples, 2) == (x, y) in cm
    except OSError as exc:
        raise OSError(f"could not read session .mat at {path}: {exc}") from exc

    if num_channels != CORTEX_CHANNEL_COUNT:
        detail = (
            f"chan_names declares {declared_width} channels"
            if declared_width is not None
            else "chan_names is absent, so the width could not be confirmed"
        )
        raise ValueError(
            f"session {path.name} yielded {num_channels} channels, expected "
            f"{CORTEX_CHANNEL_COUNT} ({detail}). A 192-channel value means this is an M1+S1 "
            f"recording, not an M1-only session — use an M1-only session (Pitfall #11, "
            f"T-04-02-03)."
        )

    binned = bin_spikes(
        per_channel, num_channels=CORTEX_CHANNEL_COUNT, t_start=t_start, t_end=t_end
    )
    return {
        "binned": binned,
        "t_start": t_start,
        "t_end": t_end,
        "num_channels": CORTEX_CHANNEL_COUNT,
        "t": t,
        "planar_cm": planar_cm,
    }
