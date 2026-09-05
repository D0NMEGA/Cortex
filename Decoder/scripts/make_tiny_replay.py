#!/usr/bin/env python3
"""Deterministic generator for the committed SYNTHETIC replay-export fixture.

THIS FIXTURE IS SYNTHETIC. Its counts are Poisson draws from a seeded generator, its velocity is a
closed-form Lissajous curve and its target track is a four-point step function. It is not real
neural data and must never be presented as a real-data artifact: its own sidecar says so in the
`disclosure` field, its `session_id` is `tiny_replay_synthetic`, and
`Decoder/tests/test_replay_export.py` asserts both.

It exists so that every export-touching test runs on a clean clone with `Decoder/data/` empty and
`Decoder/exports/` absent (Phase-9 D-21: CI never touches the dataset). It is written through the
SAME `ndt1.replay_export.write_export` the real path uses, so the committed bytes and the current
writer cannot drift apart without the test noticing.

Provenance: `source_sha256` is the sha256 of THIS SCRIPT, so the fixture is still bound to
something real -- the code that produced it. The checkpoint digest fields are 64 zeros, because no
checkpoint produced this file and claiming one would be the fabrication the disclosure exists to
prevent.

No bare/blind `except`: only `OSError` is caught explicitly.

Usage:
    uv run --project Decoder python Decoder/scripts/make_tiny_replay.py
    uv run --project Decoder python Decoder/scripts/make_tiny_replay.py --out-dir /tmp/x
"""
from __future__ import annotations

import argparse
import hashlib
import math
import sys
from pathlib import Path

import numpy as np

from ndt1.replay_export import (
    FRAME_SCALE_MM_PER_CM,
    N_CHANNELS,
    build_sidecar,
    workspace_from_cursor,
    write_export,
)

SEED = 0
N_BINS = 256
BIN_S = 0.020
SPIKE_RATE_PER_BIN = 0.3  # counts per 20 ms bin, in the band a real multiunit channel sits in

#: The Lissajous the synthetic kinematics trace, in centimetres. Closed form, so the velocity is
#: the analytic derivative rather than a difference of a sampled path.
AMPLITUDE_X_CM = 3.0
AMPLITUDE_Y_CM = 2.0
FREQ_X_HZ = 0.35
FREQ_Y_HZ = 0.55
PHASE_Y_RAD = math.pi / 4.0

#: A four-point step function on the same 15.0 mm pitch the real sessions use.
TARGET_PITCH_MM = 15.0
TARGET_POINTS_MM: tuple[tuple[float, float], ...] = (
    (-15.0, 0.0),
    (0.0, 0.0),
    (0.0, 15.0),
    (15.0, 15.0),
)
TARGET_STEP_BINS: tuple[int, ...] = (61, 127, 194)

#: Verbatim in the committed sidecar, and asserted by the fixture test.
SYNTHETIC_DISCLOSURE = (
    "synthetic fixture - not real neural data; exists so the export format is covered on a "
    "clean clone"
)

_DECODER_ROOT = Path(__file__).resolve().parents[1]
_DEFAULT_OUT_DIR = _DECODER_ROOT / "tests" / "fixtures"
_STEM = "tiny_replay"


def kinematics(n_bins: int) -> tuple[np.ndarray, np.ndarray]:
    """`(planar_cm, velocity_cm_s)` for `n_bins` bins, both closed form and deterministic."""
    t = np.arange(n_bins, dtype=np.float64) * BIN_S
    omega_x = 2.0 * math.pi * FREQ_X_HZ
    omega_y = 2.0 * math.pi * FREQ_Y_HZ
    planar_cm = np.stack(
        [
            AMPLITUDE_X_CM * np.sin(omega_x * t),
            AMPLITUDE_Y_CM * np.sin(omega_y * t + PHASE_Y_RAD),
        ],
        axis=1,
    )
    velocity = np.stack(
        [
            AMPLITUDE_X_CM * omega_x * np.cos(omega_x * t),
            AMPLITUDE_Y_CM * omega_y * np.cos(omega_y * t + PHASE_Y_RAD),
        ],
        axis=1,
    )
    return planar_cm, velocity


def target_track(n_bins: int) -> np.ndarray:
    """The `(n_bins, 2)` step function over :data:`TARGET_POINTS_MM`."""
    track = np.empty((n_bins, 2), dtype=np.float64)
    bounds = (0, *TARGET_STEP_BINS, n_bins)
    for index, (start, stop) in enumerate(zip(bounds[:-1], bounds[1:], strict=True)):
        track[start:stop] = TARGET_POINTS_MM[index]
    return track


def build_fixture(out_dir: Path) -> tuple[Path, Path]:
    """Write `tiny_replay.bin` and `tiny_replay.json` into `out_dir`; return both paths."""
    rng = np.random.default_rng(SEED)
    spikes = rng.poisson(SPIKE_RATE_PER_BIN, size=(N_BINS, N_CHANNELS)).astype(np.float32)
    planar_cm, velocity = kinematics(N_BINS)
    target = target_track(N_BINS)
    bin_starts = np.arange(N_BINS, dtype=np.float64) * BIN_S

    sidecar = build_sidecar(
        session_id="tiny_replay_synthetic",
        source_sha256=_sha256_of(Path(__file__).resolve()),
        manifest_path="Decoder/scripts/make_tiny_replay.py",
        binary_path=f"{_STEM}.bin",
        n_bins=N_BINS,
        lag_bins=1,
        # `workspace_from_cursor` takes the RECORDED cursor track in MILLIMETRES
        # (10-PREREGISTRATION section 3a). A synthetic session has no recorded cursor, so the
        # fixture's cursor IS its finger track under the x10 frame relation, converted here rather
        # than inside the box function, where the conversion is what the amendment removed.
        workspace=workspace_from_cursor(FRAME_SCALE_MM_PER_CM * planar_cm),
        target_grid={
            "distinct_targets": len(TARGET_POINTS_MM),
            "pitch_mm": TARGET_PITCH_MM,
            "log2_n_task": math.log2(len(TARGET_POINTS_MM)),
        },
        trials=len(TARGET_POINTS_MM),
        encoder_checkpoint_sha256="0" * 64,
        velocity_checkpoint_sha256="0" * 64,
        disclosure=SYNTHETIC_DISCLOSURE,
    )

    binary_path = out_dir / f"{_STEM}.bin"
    sidecar_path = out_dir / f"{_STEM}.json"
    write_export(
        binary_path,
        sidecar_path,
        spikes=spikes,
        velocity=velocity,
        target=target,
        bin_starts=bin_starts,
        sidecar=sidecar,
    )
    return binary_path, sidecar_path


def _sha256_of(path: Path) -> str:
    """Streamed sha256 of a file, in constant memory."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    """Generate the committed synthetic export fixture. Returns a process exit code."""
    parser = argparse.ArgumentParser(
        description="Generate the committed SYNTHETIC replay-export fixture."
    )
    parser.add_argument("--out-dir", type=Path, default=_DEFAULT_OUT_DIR)
    args = parser.parse_args(argv)

    try:
        binary_path, sidecar_path = build_fixture(args.out_dir)
    except OSError as exc:
        print(f"error: could not write the fixture into {args.out_dir}: {exc}", file=sys.stderr)
        return 1

    print(f"{binary_path} ({binary_path.stat().st_size} bytes, {N_BINS} bins)")
    print(f"{sidecar_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
