#!/usr/bin/env python3
"""The PRE-REGISTERED recorded-cursor dwell-to-select replay reference for RD-08 (Plan 10-01).

This script replays the ANIMAL'S OWN recorded cursor trajectory against its own recorded target
track, through this repo's dwell-to-select rule, and reports how many trials that trajectory would
have selected. Its number is published BEFORE any decoded hit count is scored (10-RESEARCH
Correction 4, 10-CONTEXT D-11, 10-PREREGISTRATION sections 3 / 11 / 14 / 16). Publishing it first
is the whole point: it turns a decoded zero from an uninterpretable non-result into a finding.

WHAT THIS NUMBER IS NOT. It is a property of ONE recorded trajectory under ONE acceptance rule at
ONE radius and ONE dwell. It is not a bound on what a decoder can achieve: a decoder producing
different trajectories, with straighter approaches or longer holds inside the radius, can exceed
it. The framing that this is what any decoder could at best score was reviewed and rejected on
2026-09-05. The word "ceiling" survives here only in this file's name and in the identifiers that
already carried it; every published sentence uses the recorded-cursor replay wording.

DATA ACCESS, and the boundary it respects. This script is the ONLY place in the repo that reads
`cursor_pos`. `ndt1.data.load_session` leaves `cursor_pos` unread (10-CONTEXT D-01) and that stays
true: this script opens the `.mat` with h5py itself, reads `target_pos` and `cursor_pos`, and
closes the file. It never touches the 1.1 GB `wf` waveform array (threat T-04-02-02, carried
forward as T-10-01-03), and `test_webgrid_ceiling.py` asserts that structurally by scanning this
source for every dataset name it indexes.

DWELL SEMANTICS. `Packages/CortexReFIT/Sources/CortexReFIT/WebgridAcquisition.swift::runTrial`
counts CONTINUOUS ticks whose distance to the target is inside the acquisition radius, and the
counter RESETS on any excursion. That reset is replicated exactly here, not approximated by a
"fraction of samples inside the radius". One documented difference: the Swift side accepts a
sample exactly ON the radius (`<=`) while this script is strictly inside (`<`), matching the
reference implementation the pre-registered table was measured with. On continuous-valued
millimetre distances the boundary is measure-zero, so the two agree on real data; the strict form
is kept so the emitted table is byte-reproducible against 10-RESEARCH Correction 4.

D-09. Nothing here asserts a measured value against a bar. This script computes and emits; the
build never goes red because the number came out low.

Usage:
    uv sync --project Decoder --extra dev
    uv run --project Decoder python Decoder/scripts/webgrid_ceiling.py \
      --session indy_20160630_01 \
      --out .planning/phases/10-v1-real-data-closed-loop-launch/10-ceiling.json
"""
from __future__ import annotations

import argparse
import json
import platform
import sys
from pathlib import Path
from typing import Any

import numpy as np

_PENDING = "PENDING"
_GRID = 30  # the 30x30 webgrid D-02 locks
_BEHAVIOR_FS_HZ = 250.0  # the Indy behavior clock (median diff(t) = 0.004 s)

#: The radius x dwell grid the evidence artifact reports, in millimetres and seconds. The first six
#: radii reproduce 10-RESEARCH Correction 4 exactly so the run doubles as a reproduction check; the
#: computed `acq_radius_mm` from the pre-registered box is appended at run time.
REFERENCE_RADII_MM: tuple[float, ...] = (1.75, 2.32, 2.86, 3.50, 7.50, 15.00)
DWELLS_S: tuple[float, ...] = (0.30, 0.10)

#: The canonical dwell, pre-registered in 10-PREREGISTRATION section 14 and not relaxed.
CANONICAL_DWELL_S = 0.30

#: Verbatim, byte-identical wherever it appears (10-PREREGISTRATION section 12).
OPEN_LOOP_DISCLOSURE = (
    "open-loop replay of a recorded session; the subject was not in the loop"
)

#: The exact top-level key set of `10-ceiling.json`, fixed by 10-PREREGISTRATION section 11 before
#: this script was ever run. The schema test compares against this tuple.
REPORT_KEYS: tuple[str, ...] = (
    "schema_version",
    "data_source",
    "session_id",
    "source_sha256",
    "manifest_path",
    "workspace",
    "canonical_radius_mm",
    "canonical_dwell_s",
    "canonical_hits",
    "trials",
    "table",
    "env",
    "disclosure",
)

SCHEMA_VERSION = 1

# Repo-relative default paths (this file lives at Decoder/scripts/webgrid_ceiling.py).
_DECODER_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = _DECODER_ROOT.parent
_DEFAULT_MANIFEST = _DECODER_ROOT / "manifests" / "indy_sessions.json"
_DEFAULT_DATA_DIR = _DECODER_ROOT / "data"
_DEFAULT_OUT = (
    _REPO_ROOT
    / ".planning"
    / "phases"
    / "10-v1-real-data-closed-loop-launch"
    / "10-ceiling.json"
)


# --------------------------------------------------------------------------------------------
# Pure functions. Each takes numpy arrays, never paths, so every one is unit-tested with no
# dataset present (Phase 9 D-21: the quick suite must run on an empty Decoder/data/).
# --------------------------------------------------------------------------------------------


def longest_run_inside(distances: np.ndarray, radius_mm: float) -> int:
    """The longest CONTINUOUS run of samples strictly inside ``radius_mm``.

    Any single excursion resets the run to zero, exactly as ``WebgridAcquisition.runTrial`` does.
    ``[0, 0, 9, 0, 0, 0]`` at radius 1 returns 3, not 5.
    """
    inside = np.asarray(distances, dtype=np.float64) < float(radius_mm)
    best = 0
    run = 0
    for is_inside in inside:
        run = run + 1 if is_inside else 0
        if run > best:
            best = run
    return int(best)


def trial_bounds(target_track: np.ndarray) -> np.ndarray:
    """Segment boundaries at every index where the target changes on either axis.

    ``target_pos`` is a per-sample piecewise-constant step function, not a per-trial list, so a
    trial is the span between two changes. Returns ``[0, ..., N]``, so consecutive pairs are the
    half-open segments and ``len(result) - 1`` is the trial count.
    """
    track = np.asarray(target_track, dtype=np.float64)
    n_samples = track.shape[1]
    changed = np.any(np.diff(track, axis=1) != 0.0, axis=0)
    return np.r_[0, np.flatnonzero(changed) + 1, n_samples].astype(np.int64)


def ceiling(
    distances: np.ndarray,
    bounds: np.ndarray,
    radius_mm: float,
    dwell_s: float,
    fs: float = _BEHAVIOR_FS_HZ,
) -> int:
    """Count segments whose longest continuous inside-run reaches the dwell requirement.

    ``need = round(dwell_s * fs)`` samples, held continuously inside ``radius_mm``.
    """
    need = int(round(float(dwell_s) * float(fs)))
    distances = np.asarray(distances, dtype=np.float64)
    hits = 0
    for start, stop in zip(bounds[:-1], bounds[1:], strict=True):
        if longest_run_inside(distances[int(start):int(stop)], radius_mm) >= need:
            hits += 1
    return int(hits)


def square_box(cursor_mm: np.ndarray) -> dict[str, Any]:
    """The pre-registered ``cursor_bbox_square`` workspace box (10-PREREGISTRATION section 3).

    A square, axis-aligned box derived from the session's OWN cursor track: the side is the larger
    of the two bounding-box spans and the box is centred on the bounding-box centre. Square keeps
    the grid isotropic in grid units, so the scalar ``acquisitionRadius`` means the same distance
    on both axes. Deriving it from the cursor rather than from the 105 mm target field is what
    stops ``CursorIntegrator``'s ``[0, 1]`` clamp from CLIPPING real excursions, and a clipped
    trajectory is fabricated cursor behavior.

    Raises ``ValueError`` naming the offending sample count if containment does not hold.
    """
    cursor = np.asarray(cursor_mm, dtype=np.float64)
    x_min, x_max = float(cursor[0].min()), float(cursor[0].max())
    y_min, y_max = float(cursor[1].min()), float(cursor[1].max())
    side_mm = max(x_max - x_min, y_max - y_min)
    centre_x = (x_max + x_min) / 2.0
    centre_y = (y_max + y_min) / 2.0
    half = side_mm / 2.0

    # The axis whose span DEFINES side_mm gets the observed extremes verbatim, so containment on it
    # holds exactly. Evaluating `centre +/- half` on that axis instead leaves the extreme sample up
    # to an ulp outside the box (measured on indy_20160630_01: the x_max sample fell 1.4e-14 mm
    # outside), which the strict containment check below correctly refuses. It is the same square
    # either way: this fixes the floating-point evaluation, not the convention, so
    # 10-PREREGISTRATION section 3 is unchanged.
    if (x_max - x_min) >= (y_max - y_min):
        box_x_min, box_x_max = x_min, x_max
        box_y_min, box_y_max = centre_y - half, centre_y + half
    else:
        box_x_min, box_x_max = centre_x - half, centre_x + half
        box_y_min, box_y_max = y_min, y_max

    contained = (
        (cursor[0] >= box_x_min)
        & (cursor[0] <= box_x_max)
        & (cursor[1] >= box_y_min)
        & (cursor[1] <= box_y_max)
    )
    outside = int(cursor.shape[1] - int(np.count_nonzero(contained)))
    if outside:
        raise ValueError(
            f"cursor_bbox_square containment failed for {outside} of {cursor.shape[1]} samples; "
            "a non-finite or out-of-box sample would silently clip the replayed trajectory"
        )

    cell_mm = side_mm / _GRID
    return {
        "x_min_mm": box_x_min,
        "x_max_mm": box_x_max,
        "y_min_mm": box_y_min,
        "y_max_mm": box_y_max,
        "side_mm": side_mm,
        "centre_x_mm": centre_x,
        "centre_y_mm": centre_y,
        "cell_mm": cell_mm,
        "acq_radius_mm": cell_mm / 2.0,
        "normalisation": "cursor_bbox_square",
    }


def session_entry(manifest: dict[str, Any], session_id: str) -> dict[str, Any]:
    """The manifest entry for ``session_id``, refusing an absent or ``PENDING`` checksum.

    T-10-01-01: a published number that does not name the bytes it came from is an unverifiable
    assertion and cannot function as a reference point.
    """
    for entry in manifest.get("sessions", []):
        if entry.get("id") == session_id:
            digest = str(entry.get("sha256", _PENDING))
            if digest == _PENDING or len(digest) != 64:
                raise ValueError(
                    f"{session_id}: manifest sha256 is {digest!r}; a recorded-cursor replay "
                    "reference must be bound to a verified 64-hex digest before it is published"
                )
            return entry
    raise ValueError(f"{session_id}: no such session in the manifest")


def build_report(
    *,
    session_id: str,
    source_sha256: str,
    manifest_path: str,
    workspace: dict[str, Any],
    table: list[dict[str, Any]],
    canonical_radius_mm: float,
    canonical_dwell_s: float,
    canonical_hits: int,
    trials: int,
) -> dict[str, Any]:
    """Assemble the committed artifact with exactly the pre-registered top-level keys."""
    return {
        "schema_version": SCHEMA_VERSION,
        "data_source": "real",
        "session_id": session_id,
        "source_sha256": source_sha256,
        "manifest_path": manifest_path,
        "workspace": workspace,
        "canonical_radius_mm": canonical_radius_mm,
        "canonical_dwell_s": canonical_dwell_s,
        "canonical_hits": canonical_hits,
        "trials": trials,
        "table": table,
        "env": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "h5py": _h5py_version(),
            "platform": platform.platform(),
            "machine": platform.machine(),
        },
        "disclosure": OPEN_LOOP_DISCLOSURE,
    }


def _h5py_version() -> str:
    """h5py's version, imported lazily so the pure functions stay importable without it."""
    import h5py

    return str(h5py.__version__)


# --------------------------------------------------------------------------------------------
# I/O layer.
# --------------------------------------------------------------------------------------------


def load_tracks(path: Path) -> tuple[np.ndarray, np.ndarray]:
    """Read ``(target_pos, cursor_pos)`` as float64 ``(2, N)`` arrays and close the file.

    Only those two datasets are indexed. The waveform array is never touched (T-10-01-03).
    """
    import h5py

    try:
        with h5py.File(path, "r") as handle:
            target = np.asarray(handle["target_pos"][()], dtype=np.float64)
            cursor = np.asarray(handle["cursor_pos"][()], dtype=np.float64)
    except OSError as exc:
        raise OSError(f"{path.name}: cannot open the session .mat at {path}: {exc}") from exc
    except KeyError as exc:
        raise KeyError(
            f"{path.name}: the session .mat is missing target_pos or cursor_pos: {exc}"
        ) from exc

    if target.shape != cursor.shape or target.shape[0] != 2:
        raise ValueError(
            f"{path.name}: expected matching (2, N) target_pos and cursor_pos, got "
            f"{target.shape} and {cursor.shape}"
        )
    return target, cursor


def main(argv: list[str] | None = None) -> int:
    """Compute the recorded-cursor replay table for one session and write the JSON artifact."""
    parser = argparse.ArgumentParser(
        description=(
            "Replay a session's own recorded cursor through the repo's dwell-to-select rule "
            "(the pre-registered RD-08 reference point)."
        )
    )
    parser.add_argument("--session", default="indy_20160630_01")
    parser.add_argument("--data-dir", type=Path, default=_DEFAULT_DATA_DIR)
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--out", type=Path, default=_DEFAULT_OUT)
    args = parser.parse_args(argv if argv is None else argv[1:])

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except OSError as exc:
        print(f"error: cannot read manifest {args.manifest}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:  # json.JSONDecodeError is a ValueError subclass
        print(f"error: manifest {args.manifest} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    try:
        entry = session_entry(manifest, args.session)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    mat_path = args.data_dir / f"{args.session}.mat"
    try:
        target, cursor = load_tracks(mat_path)
    except (OSError, KeyError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        print(
            "hint: materialize the dataset with "
            "`uv run --project Decoder python Decoder/scripts/download_indy.py`",
            file=sys.stderr,
        )
        return 1

    try:
        workspace = square_box(cursor)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    distances = np.linalg.norm(cursor - target, axis=0)
    bounds = trial_bounds(target)
    trials = int(len(bounds) - 1)

    canonical_radius_mm = float(workspace["acq_radius_mm"])
    radii = sorted({*REFERENCE_RADII_MM, round(canonical_radius_mm, 6)})

    table: list[dict[str, Any]] = []
    canonical_hits = 0
    for radius_mm in radii:
        for dwell_s in DWELLS_S:
            hits = ceiling(distances, bounds, radius_mm, dwell_s)
            is_canonical = (
                radius_mm == round(canonical_radius_mm, 6) and dwell_s == CANONICAL_DWELL_S
            )
            if is_canonical:
                canonical_hits = hits
            table.append(
                {
                    "radius_mm": radius_mm,
                    "dwell_s": dwell_s,
                    "hits": hits,
                    "trials": trials,
                    "fraction": (hits / trials) if trials else 0.0,
                    "canonical": is_canonical,
                }
            )

    report = build_report(
        session_id=args.session,
        source_sha256=str(entry["sha256"]),
        manifest_path=str(args.manifest.relative_to(_REPO_ROOT))
        if args.manifest.is_relative_to(_REPO_ROOT)
        else str(args.manifest),
        workspace=workspace,
        table=table,
        canonical_radius_mm=canonical_radius_mm,
        canonical_dwell_s=CANONICAL_DWELL_S,
        canonical_hits=canonical_hits,
        trials=trials,
    )

    try:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        print(f"error: cannot write {args.out}: {exc}", file=sys.stderr)
        return 1

    print(
        f"{args.session}: recorded-cursor replay hits {canonical_hits} of {trials} trials at "
        f"r = {canonical_radius_mm:.4f} mm, dwell {CANONICAL_DWELL_S:.2f} s "
        f"(side {workspace['side_mm']:.4f} mm, cell {workspace['cell_mm']:.4f} mm)"
    )
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
