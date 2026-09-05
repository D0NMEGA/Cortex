"""D-06: the one artifact the Swift side replays -- a compact binary plus a JSON sidecar.

One export carries the 20 ms binned counts, the paired true velocity and the target track for a
single recorded session, as a flat little-endian record array with a JSON sidecar beside it, so
Swift reads it with no parsing risk and the sidecar is what the provenance gate binds to. Binning
stays in `ndt1`, where `bin_spikes`, `bin_velocity` and `bin_target_track` share bin-edge arithmetic
by construction, because a second binner in Swift would be a silent drift hole. This file is the
ONLY writer of the format and the ONLY Python reader of it.

The binary carries no header. The header is the sidecar, so a human and a gate can both read it,
and the reader validates the sidecar's declared shape against the binary's ACTUAL byte length
before it allocates anything (ASVS V5). A `binary_path` that resolves outside the sidecar's own
directory is refused rather than followed (ASVS V12), an absent binary raises rather than being
quietly replaced with synthetic data, and a `source_sha256` that is not 64 lowercase hex is refused
because a sidecar naming bytes that were never verified is an unverifiable claim.

Nothing here asserts a measured value against a bar (D-09). This module writes and reads; a low
number is published, not gated.
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.data import BIN_MS
from ndt1.kinematics import BEHAVIOR_HZ

#: Any change to the record layout or the sidecar key set is a SCHEMA BUMP, not an edit: bump this,
#: and let the reader refuse the old file rather than reinterpreting its bytes.
EXPORT_SCHEMA_VERSION = 1

#: Channel width of the export, pinned to the IPC frame width so the two cannot drift apart.
N_CHANNELS: int = CORTEX_CHANNEL_COUNT

#: 96 float32 counts + 2 float64 velocity + 2 float64 target + 1 float64 bin start, per bin.
#: 96*4 + 2*8 + 2*8 + 8 = 384 + 16 + 16 + 8 = 424. Changing this is a schema bump (see above).
RECORD_BYTES = 424

#: The 30x30 webgrid D-02 locks, and the pre-registered name of the normalisation (section 3).
GRID_ROWS: int = 30
GRID_COLS: int = 30
NORMALISATION: str = "cursor_bbox_square"

#: `cursor_pos` and `target_pos` are in millimetres; `finger_pos` planar is in centimetres. The
#: relation is a pure unit conversion (measured on indy_20160630_01: slope 10.005, R2 0.99997), and
#: `Decoder/scripts/export_replay.py` re-verifies it on the session it exports rather than assuming.
FRAME_SCALE_MM_PER_CM: float = 10.0

#: Verbatim, byte-identical wherever it appears (10-PREREGISTRATION section 12).
OPEN_LOOP_DISCLOSURE: str = (
    "open-loop replay of a recorded session; the subject was not in the loop"
)

#: The unit of every column, recorded so a downstream reader never has to infer one.
UNITS: dict[str, str] = {
    "spikes": "counts/bin",
    "velocity": "cm/s",
    "target": "mm",
    "t_start": "s",
}

#: The exact sidecar key set, fixed by 10-PREREGISTRATION section 11 and 10-RESEARCH Pattern 1
#: before the first export was written. The reader refuses a sidecar that does not carry all of
#: them, and `build_sidecar` is the only thing that assembles one.
SIDECAR_KEYS: tuple[str, ...] = (
    "schema_version",
    "session_id",
    "source_sha256",
    "manifest_path",
    "bin_ms",
    "n_bins",
    "n_channels",
    "record_bytes",
    "binary_path",
    "binary_sha256",
    "lag_bins",
    "lag_ms",
    "behavior_hz",
    "units",
    "frame_scale_mm_per_cm",
    "workspace",
    "target_grid",
    "trials",
    "encoder_checkpoint_sha256",
    "velocity_checkpoint_sha256",
    "env",
    "disclosure",
)

_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_HASH_CHUNK_BYTES = 1024 * 1024

#: The on-disk record, little-endian and packed. numpy structured dtypes are unaligned by default,
#: so `itemsize` is the sum of the fields and matches what a Swift `unsafeLoad` sees.
_RECORD_DTYPE = np.dtype(
    [
        ("spikes", "<f4", (N_CHANNELS,)),
        ("velocity", "<f8", (2,)),
        ("target", "<f8", (2,)),
        ("t_start", "<f8"),
    ]
)
if _RECORD_DTYPE.itemsize != RECORD_BYTES:  # pragma: no cover - an import-time invariant
    raise ValueError(
        f"the record dtype is {_RECORD_DTYPE.itemsize} bytes but RECORD_BYTES says {RECORD_BYTES}; "
        f"the two are the same fact stated twice and they have drifted"
    )


@dataclass(frozen=True)
class ReplayExport:
    """One export, read back: four row-aligned arrays plus the sidecar that describes them."""

    spikes: np.ndarray  # (n_bins, 96) float32 counts/bin
    velocity: np.ndarray  # (n_bins, 2) float64 cm/s, the true binned velocity at the locked lag
    target: np.ndarray  # (n_bins, 2) float64 mm, the last-sample-per-bin target
    bin_starts: np.ndarray  # (n_bins,) float64 seconds
    sidecar: dict[str, Any]


def workspace_from_cursor(planar_cm: np.ndarray) -> dict[str, Any]:
    """The pre-registered `cursor_bbox_square` workspace box (10-PREREGISTRATION section 3).

    A square, axis-aligned box derived from the session's OWN cursor track:
    `cursor_mm = 10.0 * planar_cm`, the side is the larger of the two bounding-box spans, and the
    box is centred on the bounding-box centre. Square keeps the grid isotropic in grid units, so
    the scalar acquisition radius means the same distance on both axes. Deriving the box from the
    cursor rather than from the 105 mm target field is what stops `CursorIntegrator`'s `[0, 1]`
    clamp from CLIPPING real excursions, and a clipped trajectory is fabricated cursor behavior.

    Args:
        planar_cm: `(n_samples, 2)` sign-corrected `(x, y)` cursor position in cm, i.e. exactly
            what `ndt1.data.load_session` returns as `"planar_cm"`.

    Returns:
        The workspace dict written verbatim into the sidecar.

    Raises:
        ValueError: if the input is not `(n, 2)`, or if any sample falls outside the computed box
            (which a non-finite sample does).
    """
    planar = np.asarray(planar_cm, dtype=np.float64)
    if planar.ndim != 2 or planar.shape[1] != 2:
        raise ValueError(f"planar_cm must be 2-D (n_samples, 2), got shape {planar.shape}")
    if planar.shape[0] == 0:
        raise ValueError("planar_cm is empty; a workspace box needs at least one cursor sample")

    cursor_mm = FRAME_SCALE_MM_PER_CM * planar
    x_min, x_max = float(cursor_mm[:, 0].min()), float(cursor_mm[:, 0].max())
    y_min, y_max = float(cursor_mm[:, 1].min()), float(cursor_mm[:, 1].max())
    side_mm = max(x_max - x_min, y_max - y_min)
    centre_x = (x_max + x_min) / 2.0
    centre_y = (y_max + y_min) / 2.0
    half = side_mm / 2.0

    # The axis whose span DEFINES side_mm keeps its observed extremes verbatim. Evaluating
    # `centre +/- half` on that axis leaves the extreme sample up to an ulp outside the box, which
    # the strict containment check below would then correctly refuse. Same square either way: this
    # fixes the floating-point evaluation, not the convention (the Plan 10-01 finding).
    if (x_max - x_min) >= (y_max - y_min):
        box_x_min, box_x_max = x_min, x_max
        box_y_min, box_y_max = centre_y - half, centre_y + half
    else:
        box_x_min, box_x_max = centre_x - half, centre_x + half
        box_y_min, box_y_max = y_min, y_max

    contained = (
        (cursor_mm[:, 0] >= box_x_min)
        & (cursor_mm[:, 0] <= box_x_max)
        & (cursor_mm[:, 1] >= box_y_min)
        & (cursor_mm[:, 1] <= box_y_max)
    )
    outside = int(cursor_mm.shape[0] - int(np.count_nonzero(contained)))
    if outside:
        raise ValueError(
            f"cursor_bbox_square containment failed for {outside} of {cursor_mm.shape[0]} "
            f"samples; a non-finite or out-of-box sample would silently clip the replayed "
            f"trajectory, and a clipped trajectory is fabricated cursor behavior"
        )

    cell_mm = side_mm / GRID_ROWS
    return {
        "normalisation": NORMALISATION,
        "x_min_mm": box_x_min,
        "x_max_mm": box_x_max,
        "y_min_mm": box_y_min,
        "y_max_mm": box_y_max,
        "side_mm": side_mm,
        "centre_x_mm": centre_x,
        "centre_y_mm": centre_y,
        "grid_rows": GRID_ROWS,
        "grid_cols": GRID_COLS,
        "cell_mm": cell_mm,
        "acquisition_radius_mm": cell_mm / 2.0,
        "grid_units_per_cm": FRAME_SCALE_MM_PER_CM / side_mm,
    }


def build_sidecar(
    *,
    session_id: str,
    source_sha256: str,
    manifest_path: str,
    binary_path: str,
    n_bins: int,
    lag_bins: int,
    workspace: dict[str, Any],
    target_grid: dict[str, Any],
    trials: int,
    encoder_checkpoint_sha256: str,
    velocity_checkpoint_sha256: str,
    bin_ms: float = BIN_MS,
    behavior_hz: float = BEHAVIOR_HZ,
    n_channels: int = N_CHANNELS,
    disclosure: str = OPEN_LOOP_DISCLOSURE,
) -> dict[str, Any]:
    """Assemble a sidecar carrying exactly :data:`SIDECAR_KEYS`.

    `binary_sha256` is left empty here and filled by :func:`write_export` from the bytes it
    actually wrote, so the digest can never describe a file that was never written. `env` is read
    at call time and is never hardcoded.
    """
    return {
        "schema_version": EXPORT_SCHEMA_VERSION,
        "session_id": session_id,
        "source_sha256": source_sha256,
        "manifest_path": manifest_path,
        "bin_ms": float(bin_ms),
        "n_bins": int(n_bins),
        "n_channels": int(n_channels),
        "record_bytes": RECORD_BYTES,
        "binary_path": binary_path,
        "binary_sha256": "",
        "lag_bins": int(lag_bins),
        "lag_ms": float(lag_bins) * float(bin_ms),
        "behavior_hz": float(behavior_hz),
        "units": dict(UNITS),
        "frame_scale_mm_per_cm": FRAME_SCALE_MM_PER_CM,
        "workspace": workspace,
        "target_grid": target_grid,
        "trials": int(trials),
        "encoder_checkpoint_sha256": encoder_checkpoint_sha256,
        "velocity_checkpoint_sha256": velocity_checkpoint_sha256,
        "env": _env(),
        "disclosure": disclosure,
    }


def write_export(
    binary_path: Path,
    sidecar_path: Path,
    *,
    spikes: np.ndarray,
    velocity: np.ndarray,
    target: np.ndarray,
    bin_starts: np.ndarray,
    sidecar: dict[str, Any],
) -> None:
    """Write one export: the record array, then its sidecar.

    The sidecar is written LAST, and only after the binary's digest has been taken, so an
    interrupted write leaves a binary with no sidecar. The reader's existence check then refuses
    it, instead of some later reader treating a half-written file as valid.

    Args:
        binary_path: destination for the record array (parent directories are created).
        sidecar_path: destination for the JSON sidecar.
        spikes: `(n_bins, 96)` counts per bin.
        velocity: `(n_bins, 2)` true binned velocity in cm/s.
        target: `(n_bins, 2)` last-sample-per-bin target in mm.
        bin_starts: `(n_bins,)` bin start times in seconds.
        sidecar: a dict carrying exactly :data:`SIDECAR_KEYS`, as :func:`build_sidecar` returns.

    Raises:
        ValueError: if the sidecar's key set is wrong, if any array's shape is wrong, or if the
            four row counts and the sidecar's `n_bins` do not all agree.
        OSError: if either file cannot be written.
    """
    _require_keys(sidecar, Path(sidecar_path).name)

    counts = np.ascontiguousarray(spikes, dtype=np.float32)
    if counts.ndim != 2 or counts.shape[1] != N_CHANNELS:
        raise ValueError(
            f"spikes must be 2-D (n_bins, {N_CHANNELS}), got shape {counts.shape}"
        )
    n_bins = int(counts.shape[0])

    vel = np.ascontiguousarray(velocity, dtype=np.float64)
    tgt = np.ascontiguousarray(target, dtype=np.float64)
    starts = np.ascontiguousarray(bin_starts, dtype=np.float64).ravel()
    for name, array, shape in (
        ("velocity", vel, (n_bins, 2)),
        ("target", tgt, (n_bins, 2)),
        ("bin_starts", starts, (n_bins,)),
    ):
        if array.shape != shape:
            raise ValueError(
                f"{name} has shape {array.shape} but must be {shape} to stay row-aligned with the "
                f"{n_bins} rows of spikes; a misaligned export shifts every label by a bin"
            )

    declared_bins = int(sidecar["n_bins"])
    if declared_bins != n_bins:
        raise ValueError(
            f"the sidecar declares n_bins={declared_bins} but the arrays carry {n_bins} rows"
        )

    records = np.zeros(n_bins, dtype=_RECORD_DTYPE)
    records["spikes"] = counts
    records["velocity"] = vel
    records["target"] = tgt
    records["t_start"] = starts

    binary_path = Path(binary_path)
    binary_path.parent.mkdir(parents=True, exist_ok=True)
    binary_path.write_bytes(records.tobytes())

    payload = {**sidecar, "binary_sha256": _sha256_of(binary_path)}
    sidecar_path = Path(sidecar_path)
    sidecar_path.parent.mkdir(parents=True, exist_ok=True)
    sidecar_path.write_text(
        json.dumps(payload, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )


def read_export(sidecar_path: Path, *, verify_digest: bool = False) -> ReplayExport:
    """Read one export, validating the sidecar's claims against the binary before allocating.

    Validation order, and nothing is allocated from a declared number until all of it has passed:
    the sidecar parses and carries every key; `schema_version` is the one this reader understands;
    `n_channels` is 96; `n_bins` is positive; `record_bytes` is :data:`RECORD_BYTES`;
    `source_sha256` is 64 lowercase hex; the binary exists; its resolved parent is the sidecar's
    own resolved parent (V12); and its size on disk equals `n_bins * RECORD_BYTES`.

    Args:
        sidecar_path: the export's JSON sidecar. The binary is located relative to it.
        verify_digest: also re-hash the binary and compare it with the sidecar's `binary_sha256`.

    Returns:
        The four arrays plus the sidecar.

    Raises:
        ValueError: on any invalid or inconsistent header, on a path that escapes the export
            directory, or on a size or digest mismatch.
        OSError: if the sidecar or the binary cannot be read, including when the binary is absent.
    """
    sidecar_path = Path(sidecar_path)
    try:
        raw = sidecar_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise OSError(f"cannot read the export sidecar at {sidecar_path}: {exc}") from exc
    try:
        sidecar = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"{sidecar_path.name} is not valid JSON: {exc}") from exc
    if not isinstance(sidecar, dict):
        raise ValueError(f"{sidecar_path.name} is a {type(sidecar).__name__}, expected an object")
    _require_keys(sidecar, sidecar_path.name)

    version = sidecar["schema_version"]
    if version != EXPORT_SCHEMA_VERSION:
        raise ValueError(
            f"{sidecar_path.name} declares schema_version {version!r}, but this reader understands "
            f"only {EXPORT_SCHEMA_VERSION}. The record layout IS the schema, so a bump is refused "
            f"rather than reinterpreted"
        )
    n_channels = _as_int(sidecar, "n_channels", sidecar_path.name)
    if n_channels != N_CHANNELS:
        raise ValueError(
            f"{sidecar_path.name} declares n_channels={n_channels}, expected {N_CHANNELS}: the "
            f"export width is pinned to the IPC frame width"
        )
    n_bins = _as_int(sidecar, "n_bins", sidecar_path.name)
    if n_bins <= 0:
        raise ValueError(f"{sidecar_path.name} declares n_bins={n_bins}, which must be positive")
    record_bytes = _as_int(sidecar, "record_bytes", sidecar_path.name)
    if record_bytes != RECORD_BYTES:
        raise ValueError(
            f"{sidecar_path.name} declares record_bytes={record_bytes}, expected {RECORD_BYTES}"
        )
    digest = sidecar["source_sha256"]
    if not isinstance(digest, str) or not _SHA256_RE.match(digest):
        raise ValueError(
            f"{sidecar_path.name} carries source_sha256={digest!r}, which is not 64 lowercase hex; "
            f"an export naming bytes that were never verified is an unverifiable claim"
        )

    home = sidecar_path.resolve().parent
    binary = home / str(sidecar["binary_path"])
    if not binary.exists():
        raise FileNotFoundError(
            f"{sidecar_path.name} names binary_path {sidecar['binary_path']!r} but "
            f"{binary} does not exist. The export is materialized by "
            f"Decoder/scripts/export_replay.py; nothing is substituted for it"
        )
    resolved = binary.resolve()
    if resolved.parent != home:
        raise ValueError(
            f"{sidecar_path.name} names binary_path {sidecar['binary_path']!r}, which resolves to "
            f"{resolved} -- outside the sidecar's own directory {home}. Refusing to follow it"
        )

    declared_size = n_bins * RECORD_BYTES
    actual_size = os.path.getsize(resolved)
    if actual_size != declared_size:
        raise ValueError(
            f"{sidecar_path.name} declares {n_bins} bins = {declared_size} bytes but "
            f"{resolved.name} is {actual_size} bytes on disk. Refusing to size a read from a "
            f"header the file does not support"
        )
    if verify_digest:
        actual_digest = _sha256_of(resolved)
        if actual_digest != sidecar["binary_sha256"]:
            raise ValueError(
                f"{resolved.name} hashes to {actual_digest} but the sidecar's binary_sha256 is "
                f"{sidecar['binary_sha256']!r}; the binary changed after its sidecar was written"
            )

    records = np.fromfile(resolved, dtype=_RECORD_DTYPE, count=n_bins)
    if int(records.shape[0]) != n_bins:
        raise ValueError(
            f"{resolved.name} yielded {int(records.shape[0])} records, expected {n_bins}"
        )
    return ReplayExport(
        spikes=np.ascontiguousarray(records["spikes"]),
        velocity=np.ascontiguousarray(records["velocity"]),
        target=np.ascontiguousarray(records["target"]),
        bin_starts=np.ascontiguousarray(records["t_start"]),
        sidecar=sidecar,
    )


def _require_keys(sidecar: dict[str, Any], name: str) -> None:
    """Refuse a sidecar whose key set is not exactly :data:`SIDECAR_KEYS`."""
    present = set(sidecar)
    missing = sorted(set(SIDECAR_KEYS) - present)
    unknown = sorted(present - set(SIDECAR_KEYS))
    if missing or unknown:
        raise ValueError(
            f"{name} has the wrong sidecar key set: missing {missing}, unknown {unknown}. The key "
            f"set is pinned by 10-PREREGISTRATION section 11; changing it is a schema bump"
        )


def _as_int(sidecar: dict[str, Any], key: str, name: str) -> int:
    """Read an integer header field, refusing a value that is not one."""
    value = sidecar[key]
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{name} carries {key}={value!r}, which is not an integer")
    return value


def _sha256_of(path: Path) -> str:
    """Streamed sha256 of a file, in constant memory."""
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(_HASH_CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _env() -> dict[str, str]:
    """The versions that produced an export, read at write time and never hardcoded."""
    import h5py

    return {
        "python": platform.python_version(),
        "numpy": np.__version__,
        "h5py": str(h5py.__version__),
    }
