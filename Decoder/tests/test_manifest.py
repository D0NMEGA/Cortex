"""Offline structural test for the Indy session manifest (no network — CI-safe, DEC-02).

Asserts the committed manifest's reproducibility contract: it parses, pins Zenodo record
3854034, and every session carries an ``id``/``url``/``sha256`` and a DIRECT file URL (not the
bot-gated ``/api/`` endpoint — 04-RESEARCH DEC-02). The actual download + checksum-fill is done
by ``scripts/download_indy.py`` and is intentionally NOT exercised here (tests stay hermetic).

Phase 9 adds the ``size_bytes`` / ``zenodo_md5`` transport cross-checks, pins the identity of the
four confirmed 96-channel M1-only sessions, and pins the two facts the manifest must NOT assert:
that the dropped April sessions were 192-channel M1+S1 (C-01), and that nothing here is the NLB'21
``mc_rtt`` benchmark session (C-03 - ``mc_rtt`` is ``indy_20170202_02``, absent from record
3854034). Zero-``PENDING`` is asserted later by ``decoder-policy.sh``, not here: this plan
legitimately leaves three sessions ``PENDING`` until the verified fetch.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_MANIFEST_PATH = Path(__file__).resolve().parents[1] / "manifests" / "indy_sessions.json"
_HEX = set("0123456789abcdef")

#: The four confirmed 96-channel M1-only sessions (Option B, user decision 2026-08-30), in order.
_SELECTED_IDS = [
    "indy_20160624_03",
    "indy_20160627_01",
    "indy_20160630_01",
    "indy_20160915_01",
]

#: Dropped because they are 192-channel M1+S1 recordings the loader is right to reject (C-01).
_DROPPED_IDS = ["indy_20160407_02", "indy_20160411_01"]


def _load_manifest() -> dict[str, Any]:
    manifest: dict[str, Any] = json.loads(_MANIFEST_PATH.read_text(encoding="utf-8"))
    return manifest


def _sessions(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    sessions: list[dict[str, Any]] = manifest["sessions"]
    return sessions


def test_manifest_exists_and_parses() -> None:
    """The manifest file exists and is valid JSON."""
    assert _MANIFEST_PATH.is_file()
    manifest = _load_manifest()
    assert isinstance(manifest, dict)


def test_manifest_pins_record_3854034() -> None:
    """The manifest pins Zenodo record 3854034 (O'Doherty Indy/Loco)."""
    manifest = _load_manifest()
    assert manifest["record"] == "3854034"


def test_every_session_has_required_keys() -> None:
    """Every session declares id, url, and sha256 (the reproducibility triple)."""
    sessions = _sessions(_load_manifest())
    assert len(sessions) >= 3  # a curated handful (Pitfall #9 — not all 47 sessions)
    for session in sessions:
        assert "id" in session, f"session missing 'id': {session}"
        assert "url" in session, f"session missing 'url': {session}"
        assert "sha256" in session, f"session missing 'sha256': {session}"


def test_every_url_is_direct_file_not_api() -> None:
    """Every session URL is a direct Zenodo file URL, never the bot-gated /api/ endpoint."""
    for session in _sessions(_load_manifest()):
        url = session["url"]
        assert "zenodo.org/records/3854034/files/" in url, f"not a direct file URL: {url}"
        assert "/api/" not in url, f"URL uses the bot-gated /api/ endpoint: {url}"


def test_sessions_are_indy_m1() -> None:
    """The chosen sessions are Indy (M1) sessions matching their .mat filename."""
    for session in _sessions(_load_manifest()):
        assert session["id"].startswith("indy_"), f"expected an Indy session, got {session['id']}"
        assert session["url"].endswith(f"{session['id']}.mat")


def test_every_session_declares_size_and_md5() -> None:
    """Every session carries the publisher-side transport cross-checks download_indy.py needs."""
    for session in _sessions(_load_manifest()):
        size = session["size_bytes"]
        assert isinstance(size, int), f"{session['id']}: size_bytes must be an int, got {size!r}"
        assert size > 0, f"{session['id']}: size_bytes must be positive, got {size}"

        md5 = session["zenodo_md5"]
        assert isinstance(md5, str), f"{session['id']}: zenodo_md5 must be a string"
        assert len(md5) == 32, f"{session['id']}: zenodo_md5 must be 32 hex chars, got {md5!r}"
        assert set(md5) <= _HEX, f"{session['id']}: zenodo_md5 must be lowercase hex, got {md5!r}"


def test_session_ids_are_the_four_selected() -> None:
    """The manifest names exactly the four confirmed 96-channel M1-only sessions, in order."""
    assert [s["id"] for s in _sessions(_load_manifest())] == _SELECTED_IDS


def test_manifest_records_dropped_sessions() -> None:
    """The two 192-channel M1+S1 exclusions are recorded with their reason (C-01, D-03)."""
    dropped = _load_manifest()["dropped_sessions"]
    assert [d["id"] for d in dropped] == _DROPPED_IDS
    for entry in dropped:
        assert "192-channel" in entry["reason"], f"{entry['id']}: reason must state the width"


def test_manifest_note_makes_no_mc_rtt_claim() -> None:
    """C-03: mc_rtt is indy_20170202_02 and is absent from record 3854034 - claim nothing."""
    assert "mc_rtt" not in _load_manifest()["note"]


def test_sha256_is_pending_or_64_hex() -> None:
    """Each sha256 is either still PENDING or a full 64-char lowercase hex digest."""
    for session in _sessions(_load_manifest()):
        sha256 = session["sha256"]
        if sha256 == "PENDING":
            continue
        assert len(sha256) == 64, f"{session['id']}: sha256 must be 64 chars, got {sha256!r}"
        assert set(sha256) <= _HEX, f"{session['id']}: sha256 must be lowercase hex, got {sha256!r}"
