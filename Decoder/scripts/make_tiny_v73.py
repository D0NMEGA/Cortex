#!/usr/bin/env python3
"""Deterministic generator for the committed tiny MATLAB v7.3 CI fixture (D-20).

Writes a small HDF5 file that is structurally a MATLAB v7.3 `.mat` -- 512-byte MAT userblock, a
`#refs#` group holding the cell payloads, `MATLAB_class` attributes -- but whose values are wholly
fabricated. No Zenodo bytes are redistributed, so there is no licensing question, yet CI can
exercise `ndt1.data.load_session`'s cell dereference, channel-axis transpose and `finger_pos`
extraction with `Decoder/data/` empty.

The fixture is built to make three specific defects impossible to reintroduce (09-RESEARCH C-05,
C-02, T-04-02-03):

  * Empty cells are written the way MATLAB writes them: a TRUTHY reference to a `(2,) uint64`
    dataset carrying a `MATLAB_empty` attribute. A `if not ref: continue` guard does not fire on
    those, so it injects two spurious timestamps (values 0.0 and 1.0) per empty cell.
  * `t` starts at exactly 0.0, which is load-bearing. Those spurious 0.0/1.0 timestamps only land
    inside `[t_start, t_end)` -- and so only corrupt the counts -- when the clock starts near zero.
    On the real `indy_20160630_01` the clock starts at 148.984 s and hides the defect.
  * `finger_pos` row 0 is near-constant (the depth axis) while rows 1 and 2 vary, so an extractor
    that takes rows 0-1 instead of 1-2 puts a flat axis into the planar pair and fails loudly
    instead of silently halving decode R2.

Variants (only "clean" is committed; the rest are built into a tmp dir by tests):

  clean            the committed fixture: (5, 96) spikes, 90 live channels, 6 dead
  no_matlab_empty  identical, but the empty-cell datasets omit the MATLAB_empty attribute --
                   the negative control proving the attribute is what does the work
  width_192        (3, 192) spikes and a (1, 192) chan_names running M1 001 .. S1 096
  inflated_10x     clean geometry at 10x timestamp density, for the RD-02d firing-rate band control
  finger6          clean geometry with a (6, k) finger_pos, the real Indy row count

Every variant also writes a `<stem>.truth.json` sidecar recording the counts the generator
actually wrote. That sidecar, not a reimplementation of the loader, is the ground truth the
fixture tests assert against.

No bare/blind `except`: only `OSError` is caught explicitly.

Usage:
    uv run --project Decoder python Decoder/scripts/make_tiny_v73.py \
        --out Decoder/tests/fixtures/tiny_v73.mat
    uv run --project Decoder python Decoder/scripts/make_tiny_v73.py \
        --variant width_192 --out /tmp/w.mat
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import h5py
import numpy as np

SEED: int = 0
CHANNELS: int = 96  # must equal CORTEX_CHANNEL_COUNT
UNITS: int = 5  # unsorted hash + 4 sorted units, as h5py sees the real (5, 96) spikes array
DEAD_CHANNELS: int = 6  # 6 of 96 silent, the ratio 09-RESEARCH P6 warns about
SAMPLE_RATE_HZ: float = 250.0  # the real Indy behavior clock rate
N_SAMPLES: int = 2501  # 0.0 .. 10.0 s inclusive at 250 Hz -> exactly 500 bins of 20 ms
BIN_S: float = 0.020
MAX_COUNTS_PER_BIN: int = 5
RATE_BAND_HZ: tuple[float, float] = (12.0, 15.0)  # per-channel multiunit rate, inside 09-04's band
INFLATION_FACTOR: float = 10.0
HASH_UNIT_SHARE: float = 0.7  # fraction of a channel's spikes assigned to the unsorted-hash unit
DEPTH_MEAN_CM: float = 5.0
DEPTH_NOISE_CM: float = 0.002  # keeps finger_pos row 0 std well under the 0.01 cm assertion
PLANAR_AMPLITUDE_CM: float = 3.0  # std = A/sqrt(2) ~ 2.12 cm, comfortably over the 1.0 cm floor
PLANAR_NOISE_CM: float = 0.05

VARIANTS: tuple[str, ...] = (
    "clean",
    "no_matlab_empty",
    "width_192",
    "inflated_10x",
    "finger6",
)

_USERBLOCK_BYTES: int = 512
# A fixed timestamp, not `now()`: the committed fixture must be byte-reproducible from this script.
_MAT_DESCRIPTION: str = (
    "MATLAB 7.3 MAT-file, Platform: MACI64, "
    "Created on: Sat Aug 30 00:00:00 2026 HDF5 schema 1.0 ."
)

_DECODER_ROOT = Path(__file__).resolve().parents[1]
_DEFAULT_OUT = _DECODER_ROOT / "tests" / "fixtures" / "tiny_v73.mat"


def _mat_userblock() -> bytes:
    """Build the 512-byte MAT-file userblock that makes the file identify as MATLAB 7.3.

    Layout per the MAT-file format: bytes 0-115 description, 116-123 subsystem offset,
    124-125 version (0x0200), 126-127 endian indicator ("IM" on little-endian), then zero padding
    out to the HDF5 userblock size.
    """
    description = _MAT_DESCRIPTION.encode("ascii")
    if len(description) > 116:
        raise ValueError(f"MAT description is {len(description)} bytes, must be <= 116")
    header = bytearray(b"\x00" * _USERBLOCK_BYTES)
    header[0 : len(description)] = description
    header[len(description) : 116] = b" " * (116 - len(description))
    header[116:124] = b" " * 8  # no subsystem data
    header[124:126] = b"\x00\x02"  # version 0x0200
    header[126:128] = b"IM"  # little-endian indicator
    return bytes(header)


def _stamp_userblock(path: Path) -> None:
    """Write the MAT header into the HDF5 userblock reserved at file-creation time."""
    with path.open("r+b") as handle:
        handle.seek(0)
        handle.write(_mat_userblock())


class _RefStore:
    """Sequentially-named payload datasets under `/#refs#/`, the way MATLAB stores cell contents."""

    def __init__(self, file: h5py.File) -> None:
        self._group = file.create_group("#refs#")
        self._next = 0

    def _name(self) -> str:
        name = f"c{self._next:05d}"
        self._next += 1
        return name

    def numeric(self, values: np.ndarray) -> h5py.Reference:
        """Store a MATLAB `double` column vector and return a reference to it."""
        column = np.asarray(values, dtype=np.float64).reshape(-1, 1)
        dset = self._group.create_dataset(self._name(), data=column)
        dset.attrs["MATLAB_class"] = np.bytes_("double")
        return dset.ref

    def empty(self, *, dims: tuple[int, int], tag_empty: bool = True) -> h5py.Reference:
        """Store an EMPTY MATLAB cell exactly as MATLAB does.

        The payload is the array's dimensions as `(2,) uint64`, not a null reference, and the
        dataset carries `MATLAB_empty`. `bool(ref)` on the result is True, which is precisely why
        `data.py`'s old `if not ref: continue` guard never fired (09-RESEARCH C-05).

        `tag_empty=False` produces the `no_matlab_empty` negative control.
        """
        dset = self._group.create_dataset(self._name(), data=np.asarray(dims, dtype=np.uint64))
        dset.attrs["MATLAB_class"] = np.bytes_("double")
        if tag_empty:
            dset.attrs["MATLAB_empty"] = np.array([1], dtype=np.uint8)
        return dset.ref

    def char(self, text: str) -> h5py.Reference:
        """Store a MATLAB `char` row vector (uint16 code points) and return a reference to it."""
        codes = np.asarray([ord(ch) for ch in text], dtype=np.uint16).reshape(-1, 1)
        dset = self._group.create_dataset(self._name(), data=codes)
        dset.attrs["MATLAB_class"] = np.bytes_("char")
        dset.attrs["MATLAB_int_decode"] = np.array([2], dtype=np.int64)
        return dset.ref


def _draw_spike_times(
    rng: np.random.Generator, *, rate_hz: float, t_end: float, max_per_bin: int | None
) -> np.ndarray:
    """Draw one channel's multiunit spike train, thinned so no 20 ms bin exceeds `max_per_bin`."""
    count = int(round(rate_hz * t_end))
    times = np.sort(rng.uniform(0.0, t_end, size=count))
    if max_per_bin is None:
        return times
    bin_index = np.floor(times / BIN_S).astype(np.intp)
    keep = np.ones(times.size, dtype=bool)
    seen: dict[int, int] = {}
    for position, bin_id in enumerate(bin_index):
        occupancy = seen.get(int(bin_id), 0)
        if occupancy >= max_per_bin:
            keep[position] = False  # deterministic thinning: the earliest spikes in a bin survive
        else:
            seen[int(bin_id)] = occupancy + 1
    return times[keep]


def _split_across_units(
    rng: np.random.Generator, times: np.ndarray, n_units: int
) -> list[np.ndarray]:
    """Split one channel's train into `n_units` cells: unit 0 is the hash, unit 1 a sorted unit.

    Units 2 and up stay empty, mirroring the real files where roughly half the cells are empty.
    """
    trains: list[np.ndarray] = [np.empty(0, dtype=np.float64) for _ in range(n_units)]
    if times.size == 0:
        return trains
    to_hash = rng.random(times.size) < HASH_UNIT_SHARE
    trains[0] = times[to_hash]
    if n_units > 1:
        trains[1] = times[~to_hash]
    return trains


def _behavior_arrays(n_samples: int, *, n_rows: int) -> tuple[np.ndarray, np.ndarray]:
    """Build `t` (seconds, starting at exactly 0.0) and `finger_pos` (cm) as h5py sees them.

    `finger_pos` rows are `(z, -x, -y[, azimuth, elevation, roll])`. Row 0 is the near-constant
    depth axis; the PLANAR pair is rows 1 and 2 and is stored NEGATED, as the real file does.
    """
    t = np.arange(n_samples, dtype=np.float64) / SAMPLE_RATE_HZ
    rng = np.random.default_rng(SEED + 1)
    phase = 2.0 * np.pi * 0.35 * t  # ~0.35 Hz, a slow self-paced reach
    true_x = PLANAR_AMPLITUDE_CM * np.sin(phase) + rng.normal(0.0, PLANAR_NOISE_CM, n_samples)
    true_y = PLANAR_AMPLITUDE_CM * np.cos(phase) + rng.normal(0.0, PLANAR_NOISE_CM, n_samples)
    depth = DEPTH_MEAN_CM + rng.normal(0.0, DEPTH_NOISE_CM, n_samples)

    finger = np.zeros((n_rows, n_samples), dtype=np.float64)
    finger[0] = depth
    finger[1] = -true_x  # the real file stores -x here, so the loader must undo the sign
    finger[2] = -true_y
    for row in range(3, n_rows):  # azimuth, elevation, roll -- present but unused
        finger[row] = rng.normal(0.0, 0.2, n_samples)
    return t, finger


def _channel_names(n_channels: int) -> list[str]:
    """`M1 001` .. `M1 096`, then `S1 001` .. `S1 096` once the width exceeds one array."""
    names: list[str] = []
    for index in range(n_channels):
        array = "M1" if index < CHANNELS else "S1"
        names.append(f"{array} {index % CHANNELS + 1:03d}")
    return names


def _variant_geometry(variant: str) -> tuple[int, int, int, float, int | None, int]:
    """Return `(n_channels, n_units, n_live, rate_scale, max_per_bin, finger_rows)`."""
    if variant == "width_192":
        # (3, 192) is exactly what h5py reports for a real M1+S1 file: neither axis is 96, so no
        # transpose fires and the loader must name the chan_names width rather than the unit count.
        return 2 * CHANNELS, 3, 2 * CHANNELS - DEAD_CHANNELS, 1.0, MAX_COUNTS_PER_BIN, 3
    if variant == "inflated_10x":
        # No per-bin cap: the point of this variant is to sit OUTSIDE the plausible rate band.
        return CHANNELS, UNITS, CHANNELS - DEAD_CHANNELS, INFLATION_FACTOR, None, 3
    if variant == "finger6":
        return CHANNELS, UNITS, CHANNELS - DEAD_CHANNELS, 1.0, MAX_COUNTS_PER_BIN, 6
    return CHANNELS, UNITS, CHANNELS - DEAD_CHANNELS, 1.0, MAX_COUNTS_PER_BIN, 3


def build_fixture(out_path: Path, *, variant: str = "clean") -> Path:
    """Write one fixture variant plus its `<stem>.truth.json` sidecar; return the `.mat` path.

    Args:
        out_path: destination `.mat` path (parent directories are created).
        variant: one of `VARIANTS`.

    Returns:
        `out_path`, for chaining.

    Raises:
        ValueError: if `variant` is not one of `VARIANTS`.
    """
    if variant not in VARIANTS:
        raise ValueError(f"unknown variant {variant!r}; expected one of {VARIANTS}")

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    n_channels, n_units, n_live, rate_scale, max_per_bin, finger_rows = _variant_geometry(variant)
    tag_empty = variant != "no_matlab_empty"

    rng = np.random.default_rng(SEED)
    t, finger = _behavior_arrays(N_SAMPLES, n_rows=finger_rows)
    t_end = float(t[-1])

    per_channel_trains: list[list[np.ndarray]] = []
    total_real = 0
    bin0_real = 0
    for channel in range(n_channels):
        if channel >= n_live:  # the tail channels are dead, as ~6 of 96 are on a real session
            per_channel_trains.append([np.empty(0, dtype=np.float64) for _ in range(n_units)])
            continue
        rate_hz = float(rng.uniform(*RATE_BAND_HZ)) * rate_scale
        times = _draw_spike_times(rng, rate_hz=rate_hz, t_end=t_end, max_per_bin=max_per_bin)
        total_real += int(times.size)
        bin0_real += int(np.count_nonzero(times < BIN_S))
        per_channel_trains.append(_split_across_units(rng, times, n_units))

    empty_cells = 0
    channels_with_empty_cells: set[int] = set()
    empty_dims_used: set[tuple[int, int]] = set()

    with h5py.File(out_path, "w", userblock_size=_USERBLOCK_BYTES) as f:
        store = _RefStore(f)

        # `spikes` is (n_units, n_channels) -- the transposed view h5py gives of MATLAB's n x u.
        spike_refs = np.empty((n_units, n_channels), dtype=h5py.ref_dtype)
        for channel in range(n_channels):
            for unit in range(n_units):
                train = per_channel_trains[channel][unit]
                if train.size:
                    spike_refs[unit, channel] = store.numeric(train)
                    continue
                # Alternate the two payload shapes MATLAB emits for an empty cell (0x0 and 0x1).
                dims = (0, 0) if empty_cells % 2 == 0 else (0, 1)
                spike_refs[unit, channel] = store.empty(dims=dims, tag_empty=tag_empty)
                empty_cells += 1
                channels_with_empty_cells.add(channel)
                empty_dims_used.add(dims)
        spikes = f.create_dataset("spikes", data=spike_refs, dtype=h5py.ref_dtype)
        spikes.attrs["MATLAB_class"] = np.bytes_("cell")

        # `wf` exists only to prove the loader never opens it (T-04-02-02). One shared payload
        # keeps the committed fixture small; the loader can no more open a shared ref than a
        # per-cell one.
        waveform_ref = store.numeric(np.zeros(4, dtype=np.float64))
        wf_refs = np.empty((n_units, n_channels), dtype=h5py.ref_dtype)
        wf_refs[:, :] = waveform_ref
        wf = f.create_dataset("wf", data=wf_refs, dtype=h5py.ref_dtype)
        wf.attrs["MATLAB_class"] = np.bytes_("cell")

        name_refs = np.empty((1, n_channels), dtype=h5py.ref_dtype)
        for channel, name in enumerate(_channel_names(n_channels)):
            name_refs[0, channel] = store.char(name)
        chan_names = f.create_dataset("chan_names", data=name_refs, dtype=h5py.ref_dtype)
        chan_names.attrs["MATLAB_class"] = np.bytes_("cell")

        t_dset = f.create_dataset("t", data=t.reshape(1, -1))
        t_dset.attrs["MATLAB_class"] = np.bytes_("double")
        finger_dset = f.create_dataset("finger_pos", data=finger)
        finger_dset.attrs["MATLAB_class"] = np.bytes_("double")

    _stamp_userblock(out_path)

    truth = {
        "variant": variant,
        "seed": SEED,
        "n_channels": n_channels,
        "n_units": n_units,
        "n_live_channels": n_live,
        "n_samples": N_SAMPLES,
        "finger_rows": finger_rows,
        "t_start": float(t[0]),
        "t_end": t_end,
        "bin_s": BIN_S,
        "num_bins": int(np.floor(t_end / BIN_S)),
        "total_real_timestamps": total_real,
        "bin0_real_timestamps": bin0_real,
        "empty_cells": empty_cells,
        "channels_with_empty_cells": len(channels_with_empty_cells),
        "empty_payload_shapes": sorted(list(dims) for dims in empty_dims_used),
        "matlab_empty_attribute_written": tag_empty,
    }
    truth_path = out_path.with_suffix(".truth.json")
    truth_path.write_text(json.dumps(truth, indent=2) + "\n", encoding="utf-8")
    return out_path


def main(argv: list[str] | None = None) -> int:
    """Generate one fixture variant. Returns a process exit code."""
    parser = argparse.ArgumentParser(description="Generate the tiny MATLAB v7.3 CI fixture (D-20).")
    parser.add_argument("--out", type=Path, default=_DEFAULT_OUT)
    parser.add_argument("--variant", choices=VARIANTS, default="clean")
    args = parser.parse_args(argv)

    try:
        path = build_fixture(args.out, variant=args.variant)
    except OSError as exc:
        print(f"error: could not write fixture to {args.out}: {exc}", file=sys.stderr)
        return 1

    size = path.stat().st_size
    print(f"{path} ({args.variant}, {size} bytes)")
    print(f"{path.with_suffix('.truth.json')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
