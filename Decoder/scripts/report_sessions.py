#!/usr/bin/env python3
"""Per-session ingest report for the real Indy M1 sessions (RD-02e, D-04).

Prints what actually loaded out of ``Decoder/data/``: per-session bin count, duration, firing-rate
statistics, channel yield (dead / sub-1 Hz / live), the ``finger_pos`` column width, the
out-of-window spike accounting from 09-RESEARCH pitfall P10, and the plausibility-band verdict from
``ndt1.qc``. Sessions that failed a loader gate are listed with the loader's own message.

**Why this exists.** D-04 forbids per-session rate normalization: the Poisson NLL objective and
co-bps are both defined on raw counts. Session heterogeneity is therefore SURFACED rather than
normalized away, and this report is the surface. It is also where the ``finger_pos`` width outlier
becomes visible -- three of the four sessions store six rows and ``indy_20160915_01`` stores three.

**Provenance cross-check (T-09-06-07).** Every ``.mat`` on disk is checked against
``Decoder/manifests/indy_sessions.json``. The committed sha256 is PRINTED, never recomputed: the
point is that a published number cites the committed pin, and re-hashing 1.77 GB here would only
prove the file has not changed since the last hash, which ``download_indy.py`` already establishes.
A ``.mat`` present on disk but absent from the manifest makes this script print a loud WARNING and
exit nonzero, so an unpinned session cannot silently enter the training pool.

An empty or absent data directory is the normal state of a fresh checkout (the dataset is
gitignored), so it prints one line and exits 0.

No bare/blind ``except``: only ``OSError`` / ``ValueError`` / ``KeyError`` are caught, and each is
caught where it is expected.

Usage:
    uv run --project Decoder python Decoder/scripts/report_sessions.py
    uv run --project Decoder python Decoder/scripts/report_sessions.py --json /tmp/report.json
    uv run --project Decoder python Decoder/scripts/report_sessions.py --data-dir <dir>
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import h5py
import numpy as np

from ndt1.channel_count import CORTEX_CHANNEL_COUNT
from ndt1.data import BIN_MS
from ndt1.sessions import (
    DEFAULT_DATA_DIR,
    DEFAULT_MANIFEST,
    SessionExclusion,
    SessionLoad,
    available_sessions,
)

_PENDING = "PENDING"

#: Columns of the main per-session table, in print order.
_COLUMNS: tuple[str, ...] = (
    "session_id",
    "sha256[:12]",
    "bins",
    "duration_s",
    "mean_rate_hz",
    "median_rate_hz",
    "max_rate_hz",
    "dead_ch",
    "sub_1hz_ch",
    "live_ch",
    "max_count_per_bin",
    "zero_fraction",
    "finger_pos_cols",
    "band",
)


def _finger_pos_cols(path: Path) -> int:
    """Row count of ``finger_pos`` as h5py sees it (MATLAB's column width): 3 or 6.

    Read here rather than taken from ``SessionLoad`` because ``load_session`` deliberately returns
    only the sign-corrected planar pair (rows 1-2, 09-RESEARCH C-02). The raw width is the
    heterogeneity D-04 wants visible, so it is read straight from the file.
    """
    with h5py.File(path, "r") as f:
        return int(f["finger_pos"].shape[0])


def _out_of_window_spikes(path: Path, t_start: float, t_end: float) -> tuple[int, int, int]:
    """Count spike timestamps before ``t_start``, after/at ``t_end``, and inside the window (P10).

    ``ndt1.data.bin_spikes`` drops every timestamp outside ``[t_start, t_end)``. That is correct
    behavior, and 09-RESEARCH P10 requires the dropped counts to appear in the evidence rather than
    being invisible. ``load_session`` does not return them, so this is a deliberate second parse --
    it costs about 0.2 s per session.

    The dereference logic mirrors ``ndt1.data.load_session`` exactly, including the ``MATLAB_empty``
    discriminator (C-05: MATLAB writes empty cells as TRUTHY references) and the channel-axis
    transpose heuristic. The returned in-window count is cross-checked against the binned matrix's
    own total by the caller, which is what keeps this copy honest if the loader ever changes.

    Returns:
        ``(before, after, in_window)`` timestamp counts.
    """
    before = after = in_window = 0
    with h5py.File(path, "r") as f:
        ref_array = np.asarray(f["spikes"])
        if ref_array.ndim == 1:
            ref_array = ref_array.reshape(-1, 1)
        n_dim0, n_dim1 = ref_array.shape
        if n_dim1 == CORTEX_CHANNEL_COUNT and n_dim0 != CORTEX_CHANNEL_COUNT:
            ref_array = ref_array.T
        for ch in range(ref_array.shape[0]):
            for ref in ref_array[ch]:
                if not ref:
                    continue
                dataset = f[ref]
                if "MATLAB_empty" in dataset.attrs:
                    continue
                vec = np.asarray(dataset[()], dtype=np.float64).ravel()
                if not vec.size:
                    continue
                before += int(np.count_nonzero(vec < t_start))
                after += int(np.count_nonzero(vec >= t_end))
                in_window += int(np.count_nonzero((vec >= t_start) & (vec < t_end)))
    return before, after, in_window


def _markdown_table(header: tuple[str, ...], rows: list[list[str]]) -> str:
    """Render a markdown table with the header and rows given, no column padding games."""
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join(["---"] * len(header)) + "|"]
    lines.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(lines)


def _session_row(
    session: SessionLoad, sha256: str, finger_cols: int
) -> list[str]:
    """One row of the main table for a loaded session."""
    stats = session.stats
    band = "ok" if not session.band_violations else "; ".join(session.band_violations)
    return [
        session.session_id,
        sha256[:12] if sha256 else "MISSING",
        f"{int(stats['num_bins'])}",
        f"{stats['duration_s']:.1f}",
        f"{stats['mean_rate_hz']:.2f}",
        f"{stats['median_rate_hz']:.2f}",
        f"{stats['max_rate_hz']:.2f}",
        f"{int(stats['dead_channels'])}",
        f"{int(stats['sub_1hz_channels'])}",
        f"{int(stats['live_channels'])}",
        f"{int(stats['max_count_per_bin'])}",
        f"{stats['zero_fraction']:.4f}",
        f"{finger_cols}",
        band,
    ]


def _read_manifest(path: Path) -> tuple[dict[str, dict[str, object]], str | None]:
    """Return ``({session_id: entry}, error)``; ``error`` is set when the manifest is unusable."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        return {}, f"cannot read manifest {path}: {exc}"
    except ValueError as exc:  # json.JSONDecodeError is a ValueError subclass
        return {}, f"manifest {path} is not valid JSON: {exc}"
    entries = manifest.get("sessions", [])
    if not isinstance(entries, list) or not entries:
        return {}, f"manifest {path} has no sessions"
    return {str(e["id"]): e for e in entries if "id" in e}, None


def _print_exclusions(excluded: list[SessionExclusion]) -> None:
    """Print ``## Excluded`` (D-03: an exclusion is documented data, not a silent drop)."""
    print("\n## Excluded\n")
    if not excluded:
        print("None. Every `.mat` under the data directory loaded and passed the width gate.")
        return
    print(
        _markdown_table(
            ("session_id", "reason"),
            [[e.session_id, e.reason] for e in excluded],
        )
    )


def main(argv: list[str] | None = None) -> int:
    """Scan the data directory, print the per-session ingest report, cross-check the manifest."""
    parser = argparse.ArgumentParser(
        description="Per-session ingest report for the real Indy M1 sessions (RD-02e)."
    )
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument(
        "--json", type=Path, default=None, help="also write a machine-readable dump here"
    )
    args = parser.parse_args(argv)

    manifest_index, manifest_error = _read_manifest(args.manifest)
    if manifest_error is not None:
        print(f"error: {manifest_error}", file=sys.stderr)
        return 1

    loaded, excluded = available_sessions(args.data_dir)
    on_disk = sorted(p.stem for p in Path(args.data_dir).glob("*.mat")) if (
        Path(args.data_dir).is_dir()
    ) else []

    print(f"# Indy session ingest report\n\nData dir: `{args.data_dir}`")
    print(f"Manifest: `{args.manifest}`")
    print(f"Bin width: {BIN_MS:.0f} ms; channel width gate: {CORTEX_CHANNEL_COUNT}\n")

    if not on_disk:
        print(f"no sessions present under {args.data_dir} (the dataset is gitignored; "
              f"materialize it with scripts/download_indy.py)")
        return 0

    rows: list[list[str]] = []
    edge_rows: list[list[str]] = []
    records: list[dict[str, object]] = []
    for session in loaded:
        entry = manifest_index.get(session.session_id, {})
        sha256 = str(entry.get("sha256", ""))
        finger_cols = _finger_pos_cols(session.path)
        rows.append(_session_row(session, sha256, finger_cols))

        before, after, in_window = _out_of_window_spikes(
            session.path, session.t_start, session.t_end
        )
        binned_total = int(session.stats["total_counts"])
        agrees = "yes" if in_window == binned_total else f"NO ({binned_total} binned)"
        edge_rows.append(
            [
                session.session_id,
                f"{session.t_start:.3f}",
                f"{session.t_end:.3f}",
                f"{before}",
                f"{after}",
                f"{in_window}",
                agrees,
            ]
        )
        records.append(
            {
                "session_id": session.session_id,
                "path": str(session.path),
                "manifest_sha256": sha256,
                "finger_pos_cols": finger_cols,
                "t_start": session.t_start,
                "t_end": session.t_end,
                "dropped_spikes_before_t_start": before,
                "dropped_spikes_after_t_end": after,
                "in_window_spikes": in_window,
                "binned_total_counts": binned_total,
                "stats": session.stats,
                "band_violations": session.band_violations,
            }
        )

    print("## Loaded sessions\n")
    print(_markdown_table(_COLUMNS, rows) if rows else "None loaded.")

    print("\n## Out-of-window spike accounting (09-RESEARCH P10)\n")
    print(
        "`bin_spikes` drops every timestamp outside `[t_start, t_end)`; `in_window` must equal the "
        "binned matrix's own total count, which is the cross-check in the last column.\n"
    )
    print(
        _markdown_table(
            (
                "session_id",
                "t_start_s",
                "t_end_s",
                "dropped_spikes_before_t_start",
                "dropped_spikes_after_t_end",
                "in_window",
                "matches_binned_total",
            ),
            edge_rows,
        )
        if edge_rows
        else "None loaded."
    )

    _print_exclusions(excluded)

    total_bins = sum(int(s.stats["num_bins"]) for s in loaded)
    total_duration_s = sum(float(s.stats["duration_s"]) for s in loaded)
    print("\n## Totals\n")
    print(
        f"{len(loaded)} sessions loaded, {len(excluded)} excluded. "
        f"Total bins: {total_bins}. Pooled duration: {total_duration_s:.1f} s "
        f"({total_duration_s / 60.0:.1f} min)."
    )

    unpinned = [sid for sid in on_disk if sid not in manifest_index]
    pending = [
        s.session_id
        for s in loaded
        if str(manifest_index.get(s.session_id, {}).get("sha256", "")) == _PENDING
    ]
    if args.json is not None:
        payload = {
            "data_dir": str(args.data_dir),
            "manifest": str(args.manifest),
            "bin_ms": BIN_MS,
            "sessions": records,
            "excluded": [
                {"session_id": e.session_id, "path": str(e.path), "reason": e.reason}
                for e in excluded
            ],
            "totals": {
                "sessions_loaded": len(loaded),
                "sessions_excluded": len(excluded),
                "total_bins": total_bins,
                "total_duration_s": total_duration_s,
            },
            "unpinned_on_disk": unpinned,
            "pending_sha256": pending,
        }
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"\nWrote machine-readable dump to {args.json}")

    status = 0
    for sid in unpinned:
        print(
            f"WARNING: {sid} is on disk but not in the manifest - it will not be "
            f"provenance-pinned",
            file=sys.stderr,
        )
        status = 1
    for sid in pending:
        print(
            f"WARNING: {sid} has a PENDING sha256 in the manifest - it is not "
            f"provenance-pinned",
            file=sys.stderr,
        )
        status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
