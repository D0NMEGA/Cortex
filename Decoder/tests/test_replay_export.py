"""D-06 replay-export tests: the binary layout, the sidecar schema and the reader's refusals.

Hermetic. Every array is built with numpy in `tmp_path`, so the module is green on a clean clone
with `Decoder/data/` empty and `Decoder/exports/` absent. No test is marked `slow`.

The reader is a new parser of a file the repo does not control end to end, so the refusals are the
point (ASVS V5, V12): a declared shape is checked against the binary's ACTUAL byte length before
any allocation, a schema bump is refused rather than guessed at, and a `binary_path` that resolves
outside the sidecar's own directory is refused rather than followed.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import numpy as np
import pytest

from ndt1.replay_export import (
    EXPORT_SCHEMA_VERSION,
    N_CHANNELS,
    OPEN_LOOP_DISCLOSURE,
    RECORD_BYTES,
    build_sidecar,
    count_outside_box,
    read_export,
    workspace_from_cursor,
    write_export,
)

_N_BINS = 8
_BIN_S = 0.020
#: The module under test, read as source by the ordering self-check (the `test_fixture_v73` idiom).
_EXPORT_SOURCE = Path(__file__).resolve().parents[1] / "src" / "ndt1" / "replay_export.py"
#: The committed SYNTHETIC export fixture, written by `Decoder/scripts/make_tiny_replay.py`.
_FIXTURE_SIDECAR = Path(__file__).resolve().parent / "fixtures" / "tiny_replay.json"


def _arrays(n_bins: int = _N_BINS) -> dict[str, np.ndarray]:
    """Four row-aligned arrays with distinguishable values in every column."""
    rng = np.random.default_rng(0)
    return {
        "spikes": rng.poisson(0.3, size=(n_bins, N_CHANNELS)).astype(np.float32),
        "velocity": np.stack(
            [np.arange(n_bins, dtype=np.float64), -np.arange(n_bins, dtype=np.float64)], axis=1
        ),
        "target": np.tile(np.array([[15.0, -30.0]]), (n_bins, 1)),
        "bin_starts": 100.0 + np.arange(n_bins, dtype=np.float64) * _BIN_S,
    }


def _workspace() -> dict[str, Any]:
    """A pre-registered box over a small synthetic RECORDED cursor track, in millimetres."""
    angle = np.linspace(0.0, 2.0 * np.pi, 64)
    cursor_mm = np.stack([30.0 * np.cos(angle), 20.0 * np.sin(angle)], axis=1)
    return workspace_from_cursor(cursor_mm)


def _sidecar(n_bins: int = _N_BINS, **overrides: Any) -> dict[str, Any]:
    """A schema-complete sidecar for the synthetic export."""
    sidecar = build_sidecar(
        session_id="tiny_synthetic",
        source_sha256="a" * 64,
        manifest_path="Decoder/manifests/indy_sessions.json",
        binary_path="tiny.replay.bin",
        n_bins=n_bins,
        lag_bins=1,
        workspace=_workspace(),
        target_grid={"distinct_targets": 4, "pitch_mm": 15.0, "log2_n_task": 2.0},
        trials=3,
        encoder_checkpoint_sha256="b" * 64,
        velocity_checkpoint_sha256="c" * 64,
    )
    sidecar.update(overrides)
    return sidecar


def _write(tmp_path: Path) -> tuple[Path, Path, dict[str, np.ndarray]]:
    """Write a valid export into `tmp_path`; return `(sidecar_path, binary_path, arrays)`."""
    arrays = _arrays()
    binary = tmp_path / "tiny.replay.bin"
    sidecar_path = tmp_path / "tiny.replay.json"
    write_export(binary, sidecar_path, sidecar=_sidecar(), **arrays)
    return sidecar_path, binary, arrays


def _tamper(sidecar_path: Path, **overrides: Any) -> None:
    """Rewrite a written sidecar's header fields in place.

    The refusals below are tested against a sidecar that is wrong ON DISK, which is the threat
    (a hand-edited, truncated or substituted export), rather than against a writer talked into
    emitting one -- `build_sidecar` takes those fields from module constants, so the writer cannot
    emit them wrong on its own.
    """
    sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
    sidecar.update(overrides)
    sidecar_path.write_text(json.dumps(sidecar, sort_keys=True, indent=2) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------------ the binary layout


def test_record_bytes_is_the_pinned_layout() -> None:
    """96 float32 counts + 2 float64 velocity + 2 float64 target + 1 float64 bin start."""
    assert RECORD_BYTES == N_CHANNELS * 4 + 2 * 8 + 2 * 8 + 8 == 424
    assert EXPORT_SCHEMA_VERSION == 1


def test_written_binary_length_is_exactly_n_bins_times_the_record(tmp_path: Path) -> None:
    """No header in the binary: the header is the sidecar, so the file is a flat record array."""
    _, binary, _ = _write(tmp_path)
    assert binary.stat().st_size == _N_BINS * RECORD_BYTES


def test_round_trip_returns_bit_identical_arrays(tmp_path: Path) -> None:
    """Write then read reproduces all four arrays exactly, with no dtype or ordering drift."""
    sidecar_path, _, arrays = _write(tmp_path)
    export = read_export(sidecar_path)

    np.testing.assert_array_equal(export.spikes, arrays["spikes"])
    np.testing.assert_array_equal(export.velocity, arrays["velocity"])
    np.testing.assert_array_equal(export.target, arrays["target"])
    np.testing.assert_array_equal(export.bin_starts, arrays["bin_starts"])
    assert export.spikes.dtype == np.float32
    assert export.velocity.dtype == np.float64


def test_the_sidecar_is_written_last(tmp_path: Path) -> None:
    """A rejected write leaves no sidecar, so a half-written export fails the reader's own check."""
    arrays = _arrays()
    arrays["velocity"] = arrays["velocity"][:-1]  # one row short: the shape check must bite
    binary = tmp_path / "tiny.replay.bin"
    sidecar_path = tmp_path / "tiny.replay.json"

    with pytest.raises(ValueError) as excinfo:
        write_export(binary, sidecar_path, sidecar=_sidecar(), **arrays)

    assert "velocity" in str(excinfo.value)
    assert not sidecar_path.exists(), "a sidecar was written for an export that was never valid"


def test_write_export_rejects_a_row_count_that_disagrees_with_the_sidecar(
    tmp_path: Path,
) -> None:
    """`n_bins` is the sidecar's claim; the arrays are the fact, and they must agree."""
    with pytest.raises(ValueError) as excinfo:
        write_export(
            tmp_path / "tiny.replay.bin",
            tmp_path / "tiny.replay.json",
            sidecar=_sidecar(n_bins=_N_BINS + 1),
            **_arrays(),
        )
    assert str(_N_BINS) in str(excinfo.value)


# ------------------------------------------------------------------------------ the reader refuses


def test_read_export_rejects_a_truncated_binary_naming_both_sizes(tmp_path: Path) -> None:
    """One byte short is a mismatch, and the message names the declared AND the actual size."""
    sidecar_path, binary, _ = _write(tmp_path)
    truncated = binary.read_bytes()[:-1]
    binary.write_bytes(truncated)

    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)

    message = str(excinfo.value)
    assert str(_N_BINS * RECORD_BYTES) in message, message
    assert str(len(truncated)) in message, message


def test_read_export_refuses_to_size_an_allocation_from_the_sidecar(tmp_path: Path) -> None:
    """A sidecar declaring 10^9 bins over a 3 KB file raises on the size check, not on memory."""
    sidecar_path, _, _ = _write(tmp_path)
    _tamper(sidecar_path, n_bins=10**9)

    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)

    assert str(10**9 * RECORD_BYTES) in str(excinfo.value)


def test_the_size_check_precedes_the_read() -> None:
    """A source self-check: the bound is computed BEFORE the array read, not after it."""
    source = _EXPORT_SOURCE.read_text(encoding="utf-8")
    body = source.partition("def read_export")[2]
    assert body, "read_export is gone"
    assert body.index("getsize") < body.index("fromfile"), (
        "the declared size must be bounded against the file's actual size before any allocation"
    )


def test_read_export_rejects_a_schema_bump(tmp_path: Path) -> None:
    """A future layout is refused, never guessed at: the record layout IS the schema."""
    sidecar_path, _, _ = _write(tmp_path)
    _tamper(sidecar_path, schema_version=EXPORT_SCHEMA_VERSION + 1)
    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)
    assert "schema_version" in str(excinfo.value)


@pytest.mark.parametrize(
    ("key", "value", "token"),
    [
        ("n_channels", 64, "n_channels"),
        ("n_bins", 0, "n_bins"),
        ("n_bins", -1, "n_bins"),
        ("record_bytes", 400, "record_bytes"),
    ],
)
def test_read_export_rejects_an_impossible_header(
    tmp_path: Path, key: str, value: int, token: str
) -> None:
    """Non-positive counts, a wrong channel width and a wrong record size are all refused."""
    sidecar_path, _, _ = _write(tmp_path)
    _tamper(sidecar_path, **{key: value})
    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)
    assert token in str(excinfo.value)


@pytest.mark.parametrize("digest", ["PENDING", "A" * 64, "abc", "a" * 63, "g" * 64])
def test_read_export_rejects_a_source_sha256_that_is_not_64_lowercase_hex(
    tmp_path: Path, digest: str
) -> None:
    """T-10-02-02: a sidecar naming bytes that were never verified is an unverifiable claim."""
    sidecar_path, _, _ = _write(tmp_path)
    _tamper(sidecar_path, source_sha256=digest)
    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)
    assert "source_sha256" in str(excinfo.value)


def test_read_export_refuses_a_binary_outside_the_sidecars_directory(tmp_path: Path) -> None:
    """V12: the reader resolves both paths and refuses a symlink that escapes the export dir."""
    exports = tmp_path / "exports"
    exports.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()

    arrays = _arrays()
    binary = exports / "tiny.replay.bin"
    sidecar_path = exports / "tiny.replay.json"
    write_export(binary, sidecar_path, sidecar=_sidecar(), **arrays)

    escaped = outside / "tiny.replay.bin"
    binary.rename(escaped)
    binary.symlink_to(escaped)

    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path)
    assert "outside" in str(excinfo.value) or "directory" in str(excinfo.value)


def test_read_export_reports_a_missing_binary_rather_than_substituting_anything(
    tmp_path: Path,
) -> None:
    """Fail closed: an absent binary raises, and no synthetic stand-in is invented."""
    sidecar_path, binary, _ = _write(tmp_path)
    binary.unlink()
    with pytest.raises(OSError) as excinfo:
        read_export(sidecar_path)
    assert "tiny.replay.bin" in str(excinfo.value)


def test_read_export_verifies_the_binary_digest_on_request(tmp_path: Path) -> None:
    """`verify_digest=True` catches a binary edited after its sidecar was written."""
    sidecar_path, binary, _ = _write(tmp_path)
    assert read_export(sidecar_path, verify_digest=True).sidecar["n_bins"] == _N_BINS

    tampered = bytearray(binary.read_bytes())
    tampered[0] ^= 0xFF
    binary.write_bytes(bytes(tampered))

    read_export(sidecar_path)  # unverified read still succeeds: the size is unchanged
    with pytest.raises(ValueError) as excinfo:
        read_export(sidecar_path, verify_digest=True)
    assert "binary_sha256" in str(excinfo.value)


# ---------------------------------------------------------------------------- the workspace box


def test_workspace_from_cursor_squares_the_larger_span_and_contains_every_sample() -> None:
    """10-PREREGISTRATION section 3: a square box on the larger span, 30x30, half-cell radius."""
    # Explicit extremes rather than a sampled curve: 60 mm of x excursion, 40 mm of y. The input is
    # the RECORDED cursor track in MILLIMETRES (section 3a), not a centimetre finger track.
    cursor_mm = np.array(
        [[-30.0, -20.0], [30.0, 20.0], [0.0, 0.0], [15.0, -10.0], [-22.5, 7.5]], dtype=np.float64
    )

    box = workspace_from_cursor(cursor_mm)

    assert box["normalisation"] == "cursor_bbox_square"
    assert box["side_mm"] == pytest.approx(60.0)
    assert box["cell_mm"] == pytest.approx(60.0 / 30.0)
    assert box["acquisition_radius_mm"] == pytest.approx(box["cell_mm"] / 2.0)
    assert box["grid_rows"] == box["grid_cols"] == 30
    assert box["grid_units_per_cm"] == pytest.approx(10.0 / box["side_mm"])

    assert cursor_mm[:, 0].min() >= box["x_min_mm"]
    assert cursor_mm[:, 0].max() <= box["x_max_mm"]
    assert cursor_mm[:, 1].min() >= box["y_min_mm"]
    assert cursor_mm[:, 1].max() <= box["y_max_mm"]
    assert box["y_max_mm"] - box["y_min_mm"] == pytest.approx(box["side_mm"])


def test_workspace_from_cursor_takes_millimetres_not_a_centimetre_track() -> None:
    """Section 3a: the input is `cursor_pos` in mm, so no x10 conversion happens inside.

    The regression this pins is the superseded section-3 reading, where the box was built from
    `10.0 * planar_cm`. Feeding a centimetre track now yields a box ten times too small, and the
    difference is not cosmetic: `side_mm` sets `k = 10 / side_mm`, so R scales by `k^2`.
    """
    track_mm = np.array([[0.0, 0.0], [60.0, 40.0]], dtype=np.float64)
    assert workspace_from_cursor(track_mm)["side_mm"] == pytest.approx(60.0)
    assert workspace_from_cursor(track_mm / 10.0)["side_mm"] == pytest.approx(6.0)


def test_workspace_from_cursor_raises_when_a_sample_escapes_the_box() -> None:
    """A non-finite sample cannot be contained, and a silently clipped track is fabricated data."""
    cursor_mm = np.array([[0.0, 0.0], [10.0, 10.0], [np.nan, 5.0]], dtype=np.float64)
    with pytest.raises(ValueError) as excinfo:
        workspace_from_cursor(cursor_mm)
    assert "containment" in str(excinfo.value)


def test_count_outside_box_catches_a_track_the_box_does_not_contain() -> None:
    """The section-3a containment argument, in miniature, on a track whose answer is known by hand.

    A box built on one track is checked against a slightly LARGER second track, which is exactly
    the finger-versus-cursor situation on `indy_20160630_01`: the box built from the smaller track
    cannot contain the larger one, whatever the centring. Two of the four scaled corners escape on
    the governing axis; the other two sit inside the padded axis.
    """
    track_mm = np.array(
        [[-30.0, -20.0], [30.0, 20.0], [-30.0, 20.0], [30.0, -20.0]], dtype=np.float64
    )
    box = workspace_from_cursor(track_mm)

    assert count_outside_box(box, track_mm) == 0
    assert count_outside_box(box, 1.01 * track_mm) == 4
    assert count_outside_box(box, 0.99 * track_mm) == 0
    assert count_outside_box(box, np.array([[np.nan, 0.0]], dtype=np.float64)) == 1


# ------------------------------------------------------------------------------- disclosure + D-09


def test_the_sidecar_carries_the_verbatim_open_loop_disclosure(tmp_path: Path) -> None:
    """The pre-registered string is byte-identical wherever it appears (section 12)."""
    sidecar_path, _, _ = _write(tmp_path)
    written = json.loads(sidecar_path.read_text(encoding="utf-8"))
    assert written["disclosure"] == OPEN_LOOP_DISCLOSURE
    assert OPEN_LOOP_DISCLOSURE == (
        "open-loop replay of a recorded session; the subject was not in the loop"
    )


# --------------------------------------------------------------------- the committed fixture (3d)


def test_the_committed_synthetic_fixture_reads_through_the_current_reader() -> None:
    """The committed bytes and the current reader agree, and the fixture says it is synthetic.

    This is what lets every export-touching test run on a clean clone: no dataset and no
    `Decoder/exports/`, just the 256-bin fixture `Decoder/scripts/make_tiny_replay.py` wrote
    through the same writer the real path uses.
    """
    assert _FIXTURE_SIDECAR.is_file(), f"missing committed fixture sidecar at {_FIXTURE_SIDECAR}"
    export = read_export(_FIXTURE_SIDECAR, verify_digest=True)

    sidecar = export.sidecar
    assert sidecar["n_bins"] == 256
    assert sidecar["n_channels"] == 96
    assert sidecar["record_bytes"] == 424
    assert "synthetic fixture" in sidecar["disclosure"]
    assert sidecar["session_id"] == "tiny_replay_synthetic"

    assert export.spikes.shape == (256, N_CHANNELS)
    assert export.velocity.shape == export.target.shape == (256, 2)
    assert export.bin_starts.shape == (256,)
    assert (_FIXTURE_SIDECAR.parent / "tiny_replay.bin").stat().st_size == 256 * RECORD_BYTES


# Everything ABOVE the marker line below is scanned by the guard test that follows. The guard
# itself is excluded, because it has to name the patterns it forbids in order to forbid them.
# GUARD SPLIT MARKER: do not move or reword this line


def test_no_number_is_a_measured_threshold_assertion() -> None:
    """D-09: this module gates shape and provenance, never a measured value against a bar.

    A source self-check, copied from `test_metrics_schema.py`. A gate that policed a co-bps, an R2
    or a p99 would go red on an honest re-measurement and then be tuned or deleted.
    """
    forbidden = (r"co_bps.*>", r"r2.*>", r"p99.*<")
    source = Path(__file__).read_text(encoding="utf-8")
    scanned, marker, _guard = source.partition(
        "# GUARD SPLIT MARKER: do not move or reword this line"
    )
    assert marker, "the guard split marker is gone, so this test scanned the whole file or nothing"
    assert "def test_round_trip_returns_bit_identical_arrays" in scanned, (
        "the guard split marker moved above the tests it is supposed to scan"
    )

    offenders = [
        (number, line.strip(), pattern)
        for number, line in enumerate(scanned.splitlines(), start=1)
        for pattern in forbidden
        if re.search(pattern, line)
    ]
    assert not offenders, (
        f"D-09: this module compares a measured value against a bar: {offenders}. Schema tests "
        f"gate shape and provenance; measured numbers belong in the committed evidence artifacts."
    )
