#!/usr/bin/env python3
"""Turn one SHA-256-pinned session `.mat` into the D-06 replay export (D-07 materializer).

The export itself is gitignored, exactly like `Decoder/data/`: it is a derived work of a CC-BY
dataset, so it is produced by this committed script rather than committed. That keeps the Phase-9
D-21 tier split intact -- CI never trains and never touches the dataset -- and raises no
redistribution question. The ONE tracked export is the synthetic fixture that
`Decoder/scripts/make_tiny_replay.py` writes.

What it does, in order:

  1. read the manifest, take the session's committed sha256, refuse a "PENDING" one
  2. `load_session` -> binned counts, the behavior clock, `planar_cm`, and the D-01 target track
  3. derive the true binned velocity and apply the LOCKED 1-bin lag to all four arrays
  4. read `cursor_pos` and verify the x10 cursor/finger frame relation ON THIS SESSION
  5. compute the pre-registered `cursor_bbox_square` workspace box FROM the recorded `cursor_pos`
     track (10-PREREGISTRATION section 3a), and check that the x10 finger track is inside it too
  6. report the firing-rate band (reported, never enforced -- D-09)
  7. write the binary and its sidecar through `ndt1.replay_export`

ROW SEMANTICS, stated here because the lag makes them non-obvious. Row `i` of the export pairs the
spike bin `i` with the kinematics at bin `i + lag_bins`, which is what `ndt1.kinematics.apply_lag`
means and what the Phase-9 velocity readout was fit under. So `spikes[i]` and `t_start[i]` describe
bin `i`, while `velocity[i]` and `target[i]` describe bin `i + lag_bins`, `lag_ms` later. Both
`lag_bins` and `lag_ms` are in the sidecar, so a reader recovers the kinematic time as
`t_start + lag_ms / 1000`.

D-09: nothing here asserts a measured value against a bar. The band check prints and continues; a
real-data observation does not turn the build red. The one hard failure is the frame-relation check
in step 4, which is not a measurement of the decoder -- an unverified x10 relation would silently
mis-scale the whole workspace mapping, so it aborts.

No bare/blind `except`: only `OSError`, `KeyError` and `ValueError` are caught, by name.

Usage:
    uv sync --project Decoder --extra dev
    uv run --project Decoder python Decoder/scripts/export_replay.py --session indy_20160630_01
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any

import numpy as np

from ndt1.data import BIN_MS, load_session
from ndt1.kinematics import apply_lag, bin_velocity, planar_velocity_250hz
from ndt1.qc import band_violations, firing_rate_stats
from ndt1.real_checkpoint import (
    REAL_ENCODER_CHECKPOINT,
    REAL_VELOCITY_CHECKPOINT,
    checkpoint_sha256,
)
from ndt1.replay_export import (
    FRAME_SCALE_MM_PER_CM,
    build_sidecar,
    count_outside_box,
    workspace_from_cursor,
    write_export,
)

_PENDING = "PENDING"

#: Phase 9 locked the lag at 1 bin (20 ms) together with ridge lambda 0.1, and 10-PREREGISTRATION
#: section 2 forbids re-sweeping either in Phase 10. A non-default value is allowed for a diagnostic
#: run but announces itself on stderr, because an export at another lag is not the shipped pairing.
DEFAULT_LAG_BINS = 1

#: How closely the fitted cursor/finger slope must sit on 10.0, and how much of the variance the
#: linear relation must explain, for the frame relation to count as verified on this session.
FRAME_SLOPE_TOLERANCE = 0.01
FRAME_MIN_R2 = 0.999

_DECODER_ROOT = Path(__file__).resolve().parents[1]
_DEFAULT_MANIFEST = _DECODER_ROOT / "manifests" / "indy_sessions.json"
_DEFAULT_DATA_DIR = _DECODER_ROOT / "data"
_DEFAULT_OUT_DIR = _DECODER_ROOT / "exports"
_DEFAULT_SESSION = "indy_20160630_01"


def session_entry(manifest: dict[str, Any], session_id: str) -> dict[str, Any]:
    """The manifest entry for `session_id`, refusing an absent or `PENDING` checksum.

    T-10-02-02: a sidecar naming a session whose bytes were never verified is an unverifiable
    claim, so the digest is copied from the manifest verbatim and a placeholder is refused.
    """
    for entry in manifest.get("sessions", []):
        if entry.get("id") == session_id:
            digest = str(entry.get("sha256", _PENDING))
            if digest == _PENDING or len(digest) != 64:
                raise ValueError(
                    f"{session_id}: manifest sha256 is {digest!r}; an export must be bound to a "
                    f"verified 64-hex digest before anything is published from it"
                )
            return entry
    raise ValueError(f"{session_id}: no such session in the manifest")


def linear_fit(x: np.ndarray, y: np.ndarray) -> tuple[float, float, float]:
    """Least-squares `y ~ slope * x + intercept`; returns `(slope, intercept, r2)`."""
    slope, intercept = np.polyfit(np.asarray(x, np.float64), np.asarray(y, np.float64), 1)
    predicted = slope * x + intercept
    ss_res = float(((y - predicted) ** 2).sum())
    ss_tot = float(((y - y.mean()) ** 2).sum())
    if ss_tot == 0.0:
        raise ValueError("the cursor axis is constant, so the frame relation cannot be fitted")
    return float(slope), float(intercept), 1.0 - ss_res / ss_tot


def read_cursor_mm(path: Path) -> np.ndarray:
    """Read the session's recorded `cursor_pos` as an `(n_samples, 2)` float64 array in mm.

    This is the ONE h5py cursor read on the export path, and it is here rather than in
    `ndt1.data.load_session`, which D-01 keeps free of `cursor_pos`. `Decoder/scripts/
    fit_kalman_gain.py` imports this function rather than opening the file a second time, so there
    is one reader and one box (10-PREREGISTRATION section 3a). The waveform array is never touched
    (T-04-02-02, carried forward as T-10-01-03): only `cursor_pos` is indexed and the file is
    closed immediately.

    The array is the workspace box's DEFINING input, not a diagnostic: section 3a boxes the
    recorded cursor track because a box derived from `10 x planar_cm` does not contain it.
    """
    import h5py

    try:
        with h5py.File(path, "r") as handle:
            cursor = np.asarray(handle["cursor_pos"][()], dtype=np.float64)
    except OSError as exc:
        raise OSError(f"{path.name}: cannot open the session .mat: {exc}") from exc
    except KeyError as exc:
        raise KeyError(f"{path.name}: the session .mat has no cursor_pos: {exc}") from exc

    if cursor.ndim != 2 or cursor.shape[0] != 2:
        raise ValueError(f"{path.name}: cursor_pos has shape {cursor.shape}; expected (2, n)")
    return cursor.T


def verify_frame_relation(
    label: str, cursor_mm: np.ndarray, planar_cm: np.ndarray
) -> list[dict[str, float]]:
    """Confirm `cursor_pos` is `finger_pos` times ten ON THIS SESSION.

    The relation is what puts the decoded cm/s velocity into the millimetre target frame and it is
    the 10.0 in `grid_units_per_cm = 10.0 / side_mm`; assuming it instead of checking it would
    silently mis-scale the whole mapping, so a failure aborts. It is NOT what defines the workspace
    box (10-PREREGISTRATION section 3a): its fitted slope is 10.005, and a box built through that
    0.05 percent error stops containing the recorded track.
    """
    if cursor_mm.shape != planar_cm.shape:
        raise ValueError(
            f"{label}: cursor_pos is {cursor_mm.shape} but planar_cm is {planar_cm.shape}; the two "
            f"tracks must be sample-aligned for the frame relation to mean anything"
        )

    fits: list[dict[str, float]] = []
    for axis, name in enumerate(("x", "y")):
        slope, intercept, r2 = linear_fit(planar_cm[:, axis], cursor_mm[:, axis])
        fits.append({"axis": axis, "slope": slope, "intercept_mm": intercept, "r2": r2})
        print(
            f"frame relation {name}: cursor_{name} = {slope:.6f} * planar_{name}(cm) "
            f"+ {intercept:.6f}  R2 = {r2:.8f}"
        )
        if abs(slope - FRAME_SCALE_MM_PER_CM) >= FRAME_SLOPE_TOLERANCE or r2 <= FRAME_MIN_R2:
            raise ValueError(
                f"{label}: the {name} frame relation is slope {slope:.6f} (expected "
                f"{FRAME_SCALE_MM_PER_CM} +/- {FRAME_SLOPE_TOLERANCE}) with R2 {r2:.8f} (expected "
                f"> {FRAME_MIN_R2}). The mm-per-cm scale is unverified on this session, and an "
                f"unverified scale mis-sizes the whole workspace mapping"
            )
    return fits


def target_grid_summary(target_distinct: np.ndarray) -> dict[str, float]:
    """`distinct_targets`, the grid `pitch_mm`, and `log2_n_task` for the presented target set."""
    distinct = np.asarray(target_distinct, dtype=np.float64)
    spacings: list[float] = []
    for axis in range(distinct.shape[1]):
        values = np.unique(distinct[:, axis])
        steps = np.diff(values)
        spacings.extend(float(step) for step in steps if step > 0.0)
    if not spacings:
        raise ValueError("the session presented a single target position; there is no grid pitch")
    count = int(distinct.shape[0])
    return {
        "distinct_targets": count,
        "pitch_mm": min(spacings),
        "log2_n_task": math.log2(count),
    }


def count_trials(target_track: np.ndarray) -> int:
    """Trials in a binned target track: the segments between target changes, so `changes + 1`.

    The same definition `Decoder/scripts/webgrid_ceiling.py::trial_bounds` uses on the sample-level
    track, so the export's count and the pre-registered recorded-cursor replay reference describe
    the same trials rather than differing by one.
    """
    track = np.asarray(target_track, dtype=np.float64)
    changes = int(np.count_nonzero(np.any(np.diff(track, axis=0) != 0.0, axis=1)))
    return changes + 1


def main(argv: list[str] | None = None) -> int:
    """Materialize one session's replay export. Returns a process exit code."""
    parser = argparse.ArgumentParser(
        description="Export one pinned session as the D-06 replay binary plus its JSON sidecar."
    )
    parser.add_argument("--session", default=_DEFAULT_SESSION)
    parser.add_argument("--data-dir", type=Path, default=_DEFAULT_DATA_DIR)
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--out-dir", type=Path, default=_DEFAULT_OUT_DIR)
    parser.add_argument("--lag-bins", type=int, default=DEFAULT_LAG_BINS)
    args = parser.parse_args(argv)

    if args.lag_bins != DEFAULT_LAG_BINS:
        print(
            f"warning: --lag-bins {args.lag_bins} is not the {DEFAULT_LAG_BINS}-bin lag Phase 9 "
            f"locked; this export does not carry the shipped pairing",
            file=sys.stderr,
        )

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        entry = session_entry(manifest, args.session)
    except OSError as exc:
        print(f"error: cannot read manifest {args.manifest}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:  # json.JSONDecodeError is a ValueError subclass
        print(f"error: {exc}", file=sys.stderr)
        return 1

    mat_path = Path(args.data_dir) / f"{args.session}.mat"
    if not mat_path.is_file():
        print(
            f"error: {mat_path} is absent. The dataset is gitignored; materialize it with "
            f"Decoder/scripts/download_indy.py",
            file=sys.stderr,
        )
        return 1

    try:
        session = load_session(mat_path)
        binned = np.asarray(session["binned"], dtype=np.float32)
        clock = np.asarray(session["t"], dtype=np.float64)
        t_start = float(session["t_start"])  # type: ignore[arg-type]
        t_end = float(session["t_end"])  # type: ignore[arg-type]
        planar_cm = np.asarray(session["planar_cm"], dtype=np.float64)
        target_mm = np.asarray(session["target_mm"], dtype=np.float64)
        target_distinct = np.asarray(session["target_distinct"], dtype=np.float64)

        velocity = bin_velocity(
            planar_velocity_250hz(planar_cm, clock),
            clock,
            t_start=t_start,
            t_end=t_end,
            bin_ms=BIN_MS,
        )
        spikes, velocity = apply_lag(binned, velocity, args.lag_bins)
        n_bins = int(spikes.shape[0])
        # The target rides with the KINEMATICS: the velocity at bin i + lag is the one the subject
        # was producing toward the target it was shown at bin i + lag.
        target = target_mm[args.lag_bins : args.lag_bins + n_bins]
        # Computed AFTER the lag slice so it labels the rows actually written. It is the SPIKE
        # bin's start time (see the module docstring's row semantics).
        bin_starts = t_start + np.arange(n_bins, dtype=np.float64) * (BIN_MS / 1000.0)
        counts = (n_bins, int(velocity.shape[0]), int(target.shape[0]), int(bin_starts.shape[0]))
        if len(set(counts)) != 1:
            raise ValueError(
                f"the four exported arrays disagree on row count: spikes {counts[0]}, velocity "
                f"{counts[1]}, target {counts[2]}, bin_starts {counts[3]}"
            )

        cursor_mm = read_cursor_mm(mat_path)
        fits = verify_frame_relation(mat_path.name, cursor_mm, planar_cm)
        # 10-PREREGISTRATION section 3a: the box is the RECORDED cursor track, not 10 x planar.
        workspace = workspace_from_cursor(cursor_mm)
        # And the reason it is, made executable rather than asserted in prose: the recorded-cursor
        # box is the one that contains BOTH tracks. The converse fails -- 13 of this session's
        # 365,809 recorded cursor samples fall outside the 10 x planar box. This is a correctness
        # check on the mapping, not an assertion about a measured result (D-09): a finger sample
        # outside the box is a cursor excursion the [0,1] clamp would clip, and a clipped
        # trajectory is fabricated cursor behavior.
        escaped = count_outside_box(workspace, FRAME_SCALE_MM_PER_CM * planar_cm)
        if escaped:
            raise ValueError(
                f"{args.session}: {escaped} of {planar_cm.shape[0]} finger-derived samples "
                f"(10 x planar_cm) fall outside the recorded-cursor box. The box is supposed to "
                f"contain both tracks (10-PREREGISTRATION section 3a); if it no longer does, the "
                f"frame relation or the cursor track has changed and the mapping is unsound"
            )
        print(
            f"containment: 0 of {cursor_mm.shape[0]} recorded cursor samples and 0 of "
            f"{planar_cm.shape[0]} finger-derived samples fall outside the box"
        )
        grid = target_grid_summary(target_distinct)

        stats = firing_rate_stats(spikes)
        violations = band_violations(stats)
        print(
            f"firing-rate band: mean {stats['mean_rate_hz']:.2f} Hz, median "
            f"{stats['median_rate_hz']:.2f} Hz, live fraction "
            f"{stats['live_channel_fraction']:.3f}, zero fraction {stats['zero_fraction']:.3f}"
        )
        if violations:
            # Reported, never enforced (D-09): a real-data observation does not fail a build.
            for violation in violations:
                print(f"band violation: {violation}", file=sys.stderr)

        binary_name = f"{args.session}.replay.bin"
        sidecar = build_sidecar(
            session_id=args.session,
            source_sha256=str(entry["sha256"]),
            manifest_path=str(args.manifest.relative_to(_DECODER_ROOT.parent))
            if args.manifest.is_absolute()
            else str(args.manifest),
            binary_path=binary_name,
            n_bins=n_bins,
            lag_bins=args.lag_bins,
            workspace=workspace,
            target_grid=grid,
            trials=count_trials(target),
            encoder_checkpoint_sha256=checkpoint_sha256(REAL_ENCODER_CHECKPOINT),
            velocity_checkpoint_sha256=checkpoint_sha256(REAL_VELOCITY_CHECKPOINT),
        )
        binary_path = Path(args.out_dir) / binary_name
        sidecar_path = Path(args.out_dir) / f"{args.session}.replay.json"
        write_export(
            binary_path,
            sidecar_path,
            spikes=spikes,
            velocity=velocity,
            target=target,
            bin_starts=bin_starts,
            sidecar=sidecar,
        )
    except (KeyError, ValueError) as exc:
        print(f"error: {args.session}: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"error: {args.session}: {exc}", file=sys.stderr)
        return 1

    written = json.loads(sidecar_path.read_text(encoding="utf-8"))
    print(f"{binary_path} ({binary_path.stat().st_size} bytes, {n_bins} bins)")
    print(f"{sidecar_path}")
    print(f"binary sha256 {written['binary_sha256']}")
    print(
        f"workspace side {workspace['side_mm']:.4f} mm, cell {workspace['cell_mm']:.4f} mm, "
        f"acquisition radius {workspace['acquisition_radius_mm']:.4f} mm, "
        f"grid units per cm {workspace['grid_units_per_cm']:.6f}"
    )
    print(
        f"targets {grid['distinct_targets']} distinct at {grid['pitch_mm']:.1f} mm pitch "
        f"(log2 {grid['log2_n_task']:.4f}), trials {written['trials']}"
    )
    print(f"frame fits {fits}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
