"""Multi-session layer for real-data NDT1 training: load, split, rotate (D-11, D-12, D-13).

This module is the discipline of D-11/D-12/D-13 expressed as data structures. It has no training
loop, no torch, and no CoreML: it decides *what* is trained on and *how it is split*, and hands
those decisions to the runner as immutable records.

  `available_sessions`  every `.mat` under the data dir is attempted; a file that fails a gate
                        becomes a `SessionExclusion` carrying the loader's own message, never an
                        exception that aborts the scan (09-RESEARCH pitfall P5).
  `pooled_splits`       one chronological tail split PER SESSION (D-12). There is no pooled
                        shuffle and no cross-session leakage.
  `loso_folds`          a full N-fold leave-one-session-out rotation (D-13), each session held out
                        exactly once.

**Exclusions are data, not log lines.** A session dropped quietly is a number that looks better for
a reason the reader cannot see. `available_sessions` returns its exclusions alongside its loads so
the evidence artifact can print both. It computes each loaded session's firing-rate statistics and
band violations (`ndt1.qc`) but deliberately does NOT exclude on a band violation: D-03 requires an
exclusion to be a documented decision by the caller rather than a silent drop here.

No bare/blind `except`: the scan catches exactly `(ValueError, KeyError, OSError)`, the three types
`ndt1.data.load_session` documents. A blind except would swallow a real parse defect and let a
misparsed session train quietly, which is the failure this phase exists to prevent.
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import numpy as np

from ndt1.data import chronological_split, load_session
from ndt1.qc import band_violations, firing_rate_stats

#: `Decoder/data` -- gitignored, materialized by `scripts/download_indy.py`.
DEFAULT_DATA_DIR = Path(__file__).resolve().parents[2] / "data"

#: The committed session list. `available_sessions` scans the DIRECTORY rather than this manifest
#: on purpose, so a `.mat` present on disk but absent from the manifest is still surfaced (and a
#: manifest entry that was never downloaded simply does not appear) instead of being invisible.
DEFAULT_MANIFEST = Path(__file__).resolve().parents[2] / "manifests" / "indy_sessions.json"

#: Minimum bins for a session to be usable: 320 bins is 256 train + 64 test at `test_frac=0.2`,
#: which is 8 and 2 whole `IndySpikeDataset` windows at `seq_len=32`.
MIN_SESSION_BINS: int = 320


@dataclass(frozen=True)
class SessionLoad:
    """One session that loaded cleanly, with its arrays and its quality report.

    Frozen because the loaded record is the audit trail for whatever number gets published from it;
    a caller that needs a variant builds a new record rather than mutating this one.
    """

    session_id: str
    path: Path
    binned: np.ndarray  # (num_bins, 96) float32 spike counts
    planar_cm: np.ndarray  # (n_samples, 2) float64 sign-corrected (x, y) kinematics in cm
    t: np.ndarray  # (n_samples,) float64 behavior clock in seconds
    t_start: float
    t_end: float
    stats: dict[str, float]  # ndt1.qc.firing_rate_stats output
    band_violations: list[str]  # ndt1.qc.band_violations output; empty means plausible


@dataclass(frozen=True)
class SessionExclusion:
    """One session that was NOT used, and the measured reason it was not used (D-03)."""

    session_id: str
    path: Path
    reason: str


def available_sessions(
    data_dir: Path = DEFAULT_DATA_DIR, *, min_bins: int = MIN_SESSION_BINS
) -> tuple[list[SessionLoad], list[SessionExclusion]]:
    """Load every `.mat` under `data_dir`, excluding (never crashing on) the ones that fail a gate.

    A missing or empty directory is the normal state of a fresh checkout -- the dataset is
    gitignored -- so it yields two empty lists rather than an error.

    Args:
        data_dir: directory to scan for `*.mat`, in sorted filename order.
        min_bins: a session with fewer 20 ms bins than this is excluded as too short to split into
            train and test windows.

    Returns:
        `(loaded, excluded)`. `loaded` preserves sorted filename order; `excluded` records every
        file that was attempted and rejected, with the loader's own message.
    """
    data_dir = Path(data_dir)
    loaded: list[SessionLoad] = []
    excluded: list[SessionExclusion] = []
    if not data_dir.is_dir():
        return loaded, excluded

    for mat in sorted(data_dir.glob("*.mat")):
        session_id = mat.stem
        try:
            session = load_session(mat)
        except (ValueError, KeyError, OSError) as exc:
            # Exactly the three types load_session documents. Recording the message verbatim is
            # what carries the measured width of a 192-channel M1+S1 file into the evidence
            # artifact instead of losing it to a generic "session failed".
            excluded.append(
                SessionExclusion(
                    session_id=session_id, path=mat, reason=f"{type(exc).__name__}: {exc}"
                )
            )
            continue

        binned = np.asarray(session["binned"], dtype=np.float32)
        if binned.shape[0] < min_bins:
            excluded.append(
                SessionExclusion(
                    session_id=session_id,
                    path=mat,
                    reason=(
                        f"too short: {binned.shape[0]} bins is under min_bins={min_bins}, which "
                        f"is the floor for a train and test split of seq_len=32 windows"
                    ),
                )
            )
            continue

        stats = firing_rate_stats(binned)
        loaded.append(
            SessionLoad(
                session_id=session_id,
                path=mat,
                binned=binned,
                planar_cm=np.asarray(session["planar_cm"], dtype=np.float64),
                t=np.asarray(session["t"], dtype=np.float64),
                # load_session's dict is typed `object`; these two are floats by its contract.
                t_start=cast(float, session["t_start"]),
                t_end=cast(float, session["t_end"]),
                stats=stats,
                # Surfaced, NOT acted on: excluding here would make the drop invisible (D-03).
                band_violations=band_violations(stats),
            )
        )
    return loaded, excluded


def pooled_splits(
    sessions: Sequence[SessionLoad], *, test_frac: float = 0.2
) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """Per-session chronological tail split (D-12). Returns `[(session_id, train, test), ...]`.

    There is no pooled shuffle and no cross-session leakage. The recording is a continuous,
    self-paced reach, not trial-segmented, so a shuffle split would leak future bins into training
    (04-RESEARCH pitfall #10). Each session is split independently and the held-out block is that
    session's own temporal tail, which is also what makes RD-04's per-session co-bps meaningful.

    Args:
        sessions: the loaded sessions, in the order the caller wants them pooled.
        test_frac: fraction of each session's bins held out from the end.

    Returns:
        One `(session_id, train, test)` triple per session, in input order.

    Raises:
        ValueError: propagated from `chronological_split` when `test_frac` degenerates a session.
    """
    return [
        (session.session_id, *chronological_split(session.binned, test_frac=test_frac))
        for session in sessions
    ]


def loso_folds(session_ids: Sequence[str]) -> list[dict[str, object]]:
    """Full leave-one-session-out rotation (D-13): N folds, each holding out exactly one session.

    D-13 requires a full rotation, not one held-out session: train on the rest, evaluate co-bps on
    the held-out session with no exposure to it, rotate through all of them, and report every fold
    plus the mean and spread. A single held-out session is an anecdote, not a generalization claim.

    Args:
        session_ids: the session ids to rotate over; at least two, all distinct.

    Returns:
        `[{"held_out": session_id, "train_ids": [the others, in input order]}, ...]`, one entry per
        id in input order.

    Raises:
        ValueError: if fewer than two ids are supplied, or if any id repeats. A repeated id would
            place the same session in both the training set and the held-out set, which is exactly
            the leakage the rotation exists to rule out.
    """
    ids = list(session_ids)
    if len(ids) < 2:
        raise ValueError(
            f"leave-one-session-out needs at least two sessions, got {len(ids)}; a single "
            f"held-out session is not a generalization claim (D-13)"
        )
    duplicates = sorted({sid for sid in ids if ids.count(sid) > 1})
    if duplicates:
        raise ValueError(
            f"duplicate session ids {duplicates} would appear in both the train and held-out "
            f"sets of the same fold (leakage, T-09-04-05)"
        )
    return [
        {"held_out": held_out, "train_ids": [sid for sid in ids if sid != held_out]}
        for held_out in ids
    ]
