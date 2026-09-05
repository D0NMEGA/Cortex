"""Hermetic tests for the recorded-cursor dwell-to-select replay reference (Plan 10-01, RD-08).

Every test here runs on synthetic numpy arrays this module builds itself. Nothing under
``Decoder/data/`` is opened, and no ``.mat`` file needs to exist, so the quick suite stays green on
a clean checkout (Phase 9 D-21 tier split: CI gates structure, never a measured number).

What is pinned here is the SEGMENTATION and DWELL semantics that
``Packages/CortexReFIT/Sources/CortexReFIT/WebgridAcquisition.swift`` implements in Swift: the
dwell counter is CONTINUOUS and RESETS on any excursion, so a trial that spends many scattered
samples near the target is not a hit. A "fraction of samples inside the radius" approximation would
score the same trajectory very differently, which is why the reset is unit-tested on an array whose
answer is known by hand rather than only checked against the full session.

D-09 applies to this module and to the script it tests: neither may assert a measured value against
a bar. ``test_no_number_is_a_measured_threshold_assertion`` is the executable form of that rule.
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

import numpy as np
import pytest

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "webgrid_ceiling.py"
_spec = importlib.util.spec_from_file_location("webgrid_ceiling", _SCRIPT)
assert _spec is not None and _spec.loader is not None
webgrid_ceiling = importlib.util.module_from_spec(_spec)
sys.modules["webgrid_ceiling"] = webgrid_ceiling
_spec.loader.exec_module(webgrid_ceiling)


def _step_track(lengths: list[int]) -> np.ndarray:
    """A (2, sum(lengths)) piecewise-constant target track with one distinct target per segment."""
    xs: list[float] = []
    ys: list[float] = []
    for index, length in enumerate(lengths):
        xs.extend([float(index) * 15.0] * length)
        ys.extend([float(index) * -15.0] * length)
    return np.asarray([xs, ys], dtype=np.float64)


def test_longest_run_inside_resets_on_any_excursion() -> None:
    """The dwell is CONTINUOUS: one sample outside the radius resets the counter to zero.

    ``[0, 0, 9, 0, 0, 0]`` at radius 1 has five samples inside but the longest CONTINUOUS run is
    three. A "count the samples inside" reading would return 5 and silently inflate every hit
    count in the phase.
    """
    distances = np.asarray([0.0, 0.0, 9.0, 0.0, 0.0, 0.0], dtype=np.float64)
    assert webgrid_ceiling.longest_run_inside(distances, 1.0) == 3


def test_longest_run_inside_edge_cases() -> None:
    """All-inside, all-outside, empty, and the strict-inequality boundary."""
    all_inside = np.zeros(7, dtype=np.float64)
    all_outside = np.full(7, 99.0, dtype=np.float64)
    empty = np.zeros(0, dtype=np.float64)

    assert webgrid_ceiling.longest_run_inside(all_inside, 1.0) == 7
    assert webgrid_ceiling.longest_run_inside(all_outside, 1.0) == 0
    assert webgrid_ceiling.longest_run_inside(empty, 1.0) == 0
    # Strictly inside: a sample exactly ON the radius is outside (the reference implementation the
    # pre-registered table was measured with uses `<`, not `<=`).
    on_the_radius = np.asarray([1.0, 1.0, 1.0], dtype=np.float64)
    assert webgrid_ceiling.longest_run_inside(on_the_radius, 1.0) == 0


def test_trial_bounds_segments_at_every_target_change() -> None:
    """A 3-step track of lengths 4/5/6 yields exactly 3 segments with those lengths."""
    track = _step_track([4, 5, 6])
    bounds = webgrid_ceiling.trial_bounds(track)

    assert bounds.tolist() == [0, 4, 9, 15]
    segment_lengths = (bounds[1:] - bounds[:-1]).tolist()
    assert segment_lengths == [4, 5, 6]
    assert len(segment_lengths) == 3


def test_trial_bounds_detects_a_change_on_either_axis() -> None:
    """A target that moves on y alone still opens a new trial."""
    track = np.asarray(
        [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 15.0, 15.0]],
        dtype=np.float64,
    )
    assert webgrid_ceiling.trial_bounds(track).tolist() == [0, 2, 4]


def test_ceiling_counts_only_segments_that_satisfy_the_dwell() -> None:
    """A hand-built case: at fs=10 Hz and dwell 0.3 s the rule needs 3 continuous samples.

    Segment 0 holds 3 continuous samples inside 1 mm  -> hit.
    Segment 1 never enters the radius                 -> miss.
    Segment 2 enters 5 times but never for 3 in a row -> miss (this is the reset under test).
    """
    distances = np.asarray(
        [0.0, 0.0, 0.0, 5.0, 5.0, 5.0, 0.0, 9.0, 0.0, 9.0, 0.0, 9.0, 0.0, 9.0, 0.0],
        dtype=np.float64,
    )
    bounds = np.asarray([0, 3, 6, 15], dtype=np.int64)

    assert webgrid_ceiling.ceiling(distances, bounds, 1.0, 0.3, fs=10.0) == 1
    # A shorter dwell (1 sample) turns both of the other segments into hits.
    assert webgrid_ceiling.ceiling(distances, bounds, 1.0, 0.1, fs=10.0) == 2


def test_square_box_is_square_centred_and_contains_every_sample() -> None:
    """`side_mm` is the LARGER span, the box is centred on the bbox centre, containment holds."""
    rng = np.random.default_rng(0)
    cursor = np.vstack(
        [
            rng.uniform(-80.0, 92.0, size=4000),  # a wider x span
            rng.uniform(5.0, 115.0, size=4000),
        ]
    )
    box = webgrid_ceiling.square_box(cursor)

    x_span = float(cursor[0].max() - cursor[0].min())
    y_span = float(cursor[1].max() - cursor[1].min())
    assert box["side_mm"] == pytest.approx(max(x_span, y_span))
    assert box["normalisation"] == "cursor_bbox_square"
    assert box["cell_mm"] == pytest.approx(box["side_mm"] / 30.0)
    assert box["acq_radius_mm"] == pytest.approx(box["cell_mm"] / 2.0)

    # The box is square on both axes and centred on the bounding-box centre.
    assert (box["x_max_mm"] - box["x_min_mm"]) == pytest.approx(box["side_mm"])
    assert (box["y_max_mm"] - box["y_min_mm"]) == pytest.approx(box["side_mm"])
    assert box["centre_x_mm"] == pytest.approx((cursor[0].max() + cursor[0].min()) / 2.0)
    assert box["centre_y_mm"] == pytest.approx((cursor[1].max() + cursor[1].min()) / 2.0)

    # Containment: every sample falls inside. Clipping a real excursion would fabricate cursor
    # behavior, which is the reason the box is derived from the cursor and not from the target
    # field (10-PREREGISTRATION section 3).
    assert bool(np.all(cursor[0] >= box["x_min_mm"]))
    assert bool(np.all(cursor[0] <= box["x_max_mm"]))
    assert bool(np.all(cursor[1] >= box["y_min_mm"]))
    assert bool(np.all(cursor[1] <= box["y_max_mm"]))


def test_square_box_raises_and_names_the_offending_count() -> None:
    """A non-finite sample breaks containment, so the box refuses instead of emitting a bad span."""
    cursor = np.asarray([[0.0, 1.0, np.nan], [0.0, 1.0, 2.0]], dtype=np.float64)
    with pytest.raises(ValueError, match=r"containment"):
        webgrid_ceiling.square_box(cursor)


def test_build_report_emits_exactly_the_preregistered_key_set() -> None:
    """The 13 top-level keys are fixed by 10-PREREGISTRATION section 11, before any run."""
    cursor = np.asarray([[0.0, 10.0, 20.0, 30.0], [0.0, 5.0, 10.0, 15.0]], dtype=np.float64)
    box = webgrid_ceiling.square_box(cursor)
    report = webgrid_ceiling.build_report(
        session_id="indy_fake_01",
        source_sha256="0" * 64,
        manifest_path="Decoder/manifests/indy_sessions.json",
        workspace=box,
        table=[{"radius_mm": 1.0, "dwell_s": 0.3, "hits": 0, "trials": 4, "fraction": 0.0}],
        canonical_radius_mm=box["acq_radius_mm"],
        canonical_dwell_s=0.30,
        canonical_hits=0,
        trials=4,
    )

    assert sorted(report) == sorted(webgrid_ceiling.REPORT_KEYS)
    assert report["data_source"] == "real"
    assert report["disclosure"] == webgrid_ceiling.OPEN_LOOP_DISCLOSURE
    assert "open-loop replay" in report["disclosure"]
    assert set(report["env"]) == {"h5py", "machine", "numpy", "platform", "python"}


def test_load_tracks_names_the_session_when_the_file_is_absent(tmp_path: Path) -> None:
    """The I/O layer catches OSError by name and re-raises with the path in the message."""
    missing = tmp_path / "indy_absent_01.mat"
    with pytest.raises(OSError, match=r"indy_absent_01"):
        webgrid_ceiling.load_tracks(missing)


def test_session_entry_refuses_a_pending_or_absent_checksum() -> None:
    """A number bound to a `PENDING` checksum is not bound to any bytes (T-10-01-01)."""
    manifest = {"sessions": [{"id": "indy_fake_01", "sha256": "PENDING"}]}
    with pytest.raises(ValueError, match=r"PENDING"):
        webgrid_ceiling.session_entry(manifest, "indy_fake_01")
    with pytest.raises(ValueError, match=r"indy_missing_01"):
        webgrid_ceiling.session_entry(manifest, "indy_missing_01")


def test_the_script_never_reads_the_waveform_array() -> None:
    """T-04-02-02 / T-10-01-03: only target_pos and cursor_pos are read from the HDF5 file."""
    source = _SCRIPT.read_text(encoding="utf-8")
    datasets = set(re.findall(r"""handle\[["']([a-z_]+)["']\]""", source))
    assert datasets == {"target_pos", "cursor_pos"}


# GUARD SPLIT MARKER: do not move or reword this line
def test_no_number_is_a_measured_threshold_assertion() -> None:
    """D-09: neither this module nor the script compares a measured value against a bar.

    A source self-check, in the shape of
    ``test_metrics_schema.py::test_no_number_is_a_measured_threshold_assertion``. The forbidden
    shapes are an assertion on a hit count, a canonical value or a bitrate: those are the
    real-data quantities this plan publishes, and a gate that policed any of them would go red on
    an honest re-measurement and then be tuned or deleted. The recorded-cursor replay reference is
    a real-data number, so the rule reaches the script too, not only the test module.
    """
    forbidden = (r"assert .*hits.*[<>]", r"assert .*canonical.*[<>]", r"assert .*bps.*[<>]")

    test_source = Path(__file__).read_text(encoding="utf-8")
    scanned, marker, _guard = test_source.partition(
        "# GUARD SPLIT MARKER: do not move or reword this line"
    )
    assert marker, "the guard split marker is gone, so this test scanned the whole file or nothing"
    assert "def test_ceiling_counts_only_segments_that_satisfy_the_dwell" in scanned, (
        "the guard split marker moved above the tests it is supposed to scan"
    )

    sources = {"test module": scanned, "webgrid_ceiling.py": _SCRIPT.read_text(encoding="utf-8")}
    offenders = [
        (where, number, line.strip(), pattern)
        for where, source in sources.items()
        for number, line in enumerate(source.splitlines(), start=1)
        for pattern in forbidden
        if re.search(pattern, line)
    ]
    assert not offenders, (
        f"D-09: a measured value is compared against a bar: {offenders}. The recorded-cursor "
        f"replay reference is published as a number in a committed evidence artifact, where a "
        f"re-measurement updates it, not as a build gate that a re-measurement would redden."
    )
