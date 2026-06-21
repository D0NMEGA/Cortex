"""Offline structural test for the Indy session manifest (no network — CI-safe, DEC-02).

Asserts the committed manifest's reproducibility contract: it parses, pins Zenodo record
3854034, and every session carries an ``id``/``url``/``sha256`` and a DIRECT file URL (not the
bot-gated ``/api/`` endpoint — 04-RESEARCH DEC-02). The actual download + checksum-fill is done
by ``scripts/download_indy.py`` and is intentionally NOT exercised here (tests stay hermetic).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_MANIFEST_PATH = Path(__file__).resolve().parents[1] / "manifests" / "indy_sessions.json"


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
