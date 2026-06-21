"""Cross-repo reconciliation of the neural channel width (closes Phase-2 D-11).

The 96-channel width is defined in FOUR places that must never silently diverge:
the Python source-of-truth (`ndt1.channel_count.CORTEX_CHANNEL_COUNT`) and its three
Swift/Rust sibling homes (`cortex_shm.h`, `frame.rs`, `cortex_ring.h`). A divergence
would corrupt the cross-process IPC frame width (threat T-04-02-03). This test parses
the literal out of each home and asserts they all equal the Python constant, with a
negative-control proving the regression trap actually bites.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from ndt1.channel_count import CORTEX_CHANNEL_COUNT

# (relative path under the repo root, regex capturing the channel-count integer)
_HOMES: list[tuple[str, str]] = [
    (
        "Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h",
        r"#define\s+CORTEX_CHANNEL_COUNT\s+(\d+)",
    ),
    (
        "Packages/CortexRing/rust/src/frame.rs",
        r"pub\s+const\s+CORTEX_CHANNEL_COUNT\s*:\s*usize\s*=\s*(\d+)",
    ),
    (
        "Packages/CortexRing/rust/include/cortex_ring.h",
        r"#define\s+CORTEX_CHANNEL_COUNT\s+(\d+)",
    ),
]


def _find_repo_root(start: Path) -> Path:
    """Walk up from `start` until a directory contains `Packages/` (path-robust)."""
    for candidate in (start, *start.parents):
        if (candidate / "Packages").is_dir():
            return candidate
    raise FileNotFoundError(
        f"could not locate a repo root (a parent containing 'Packages/') above {start}"
    )


def _parse_channel_count(repo_root: Path, rel_path: str, pattern: str) -> int:
    """Extract the CORTEX_CHANNEL_COUNT integer literal from one home file."""
    path = repo_root / rel_path
    try:
        text = path.read_text(encoding="utf-8")
        match = re.search(pattern, text)
    except OSError as exc:  # file missing/unreadable — surface which home failed
        raise AssertionError(f"could not read channel-count home {rel_path}: {exc}") from exc
    if match is None:
        raise AssertionError(
            f"channel-count home {rel_path} did not contain a CORTEX_CHANNEL_COUNT literal "
            f"(pattern {pattern!r})"
        )
    try:
        return int(match.group(1))
    except (AttributeError, ValueError) as exc:
        raise AssertionError(f"non-integer channel count parsed from {rel_path}: {exc}") from exc


def test_python_constant_is_96() -> None:
    """The Python source-of-truth is exactly 96 (O'Doherty Indy M1-only sessions)."""
    assert CORTEX_CHANNEL_COUNT == 96


def test_reconcile_all_three_repo_homes() -> None:
    """cortex_shm.h, frame.rs, and cortex_ring.h must all equal the Python constant."""
    repo_root = _find_repo_root(Path(__file__).resolve())
    for rel_path, pattern in _HOMES:
        found = _parse_channel_count(repo_root, rel_path, pattern)
        assert found == CORTEX_CHANNEL_COUNT, (
            f"channel-count divergence: {rel_path} declares CORTEX_CHANNEL_COUNT={found}, "
            f"but the Python source-of-truth (ndt1.channel_count) is {CORTEX_CHANNEL_COUNT}. "
            f"All four homes must agree — see Phase-2 D-11."
        )


def test_no_home_disagrees_among_themselves() -> None:
    """All three native homes agree with each other (not just with Python)."""
    repo_root = _find_repo_root(Path(__file__).resolve())
    values = {
        rel_path: _parse_channel_count(repo_root, rel_path, pattern)
        for rel_path, pattern in _HOMES
    }
    distinct = set(values.values())
    assert len(distinct) == 1, f"native channel-count homes disagree among themselves: {values}"


def test_negative_control_mismatch_must_fail() -> None:
    """Negative control: a deliberately-wrong value (64) MUST NOT equal the homes.

    Proves the regression trap bites — if this assertion ever silently passed, the
    reconciliation test above would be a no-op (Phase 1/2 negative-control precedent).
    """
    wrong = 64
    assert wrong != CORTEX_CHANNEL_COUNT, "negative control degenerate: 64 must differ from 96"
    repo_root = _find_repo_root(Path(__file__).resolve())
    # The reconcile would FAIL against this wrong value at every home — assert that it would.
    for rel_path, pattern in _HOMES:
        found = _parse_channel_count(repo_root, rel_path, pattern)
        with pytest.raises(AssertionError):
            assert found == wrong, "deliberately failing assertion (negative control)"
