"""Hermetic negative controls for the download_indy.py integrity gates (RD-01c / RD-01d).

Every test here runs against a payload this module writes into ``tmp_path`` itself, so
``_process_session`` finds the destination already on disk and never touches the network, and
nothing under ``Decoder/data/`` is read or required. Each refusal is paired with the positive
control that must NOT raise, so the gates are proven to discriminate rather than to always fail.

Gate order under test (all before any sha256 is computed or written back):

  1. magic bytes  -- the payload must start with ``MATLAB 7.3 MAT-f`` (P2: an HTML error page)
  2. size         -- ``st_size`` must equal the manifest ``size_bytes`` (P2/P11: truncation)
  3. md5          -- the streamed md5 must equal the publisher's ``zenodo_md5`` (P2)
  4. sha256       -- the existing T-04-02-01 pin, verified or filled from ``PENDING``
"""
from __future__ import annotations

import hashlib
import importlib.util
import sys
from pathlib import Path
from typing import Any

import pytest

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "download_indy.py"
_spec = importlib.util.spec_from_file_location("download_indy", _SCRIPT)
assert _spec is not None and _spec.loader is not None
download_indy = importlib.util.module_from_spec(_spec)
sys.modules["download_indy"] = download_indy
_spec.loader.exec_module(download_indy)

_SESSION_ID = "indy_fake_01"
_URL = f"https://zenodo.org/records/3854034/files/{_SESSION_ID}.mat"
_MAGIC = b"MATLAB 7.3 MAT-f"
_VALID_PAYLOAD = _MAGIC + b"\x00" * 512
_HEX = set("0123456789abcdef")


def _write_session(
    tmp_path: Path, payload: bytes, *, sha256: str | None = None
) -> dict[str, Any]:
    """Write `payload` to the destination `_process_session` expects; return its session dict.

    The declared ``size_bytes`` / ``zenodo_md5`` are the payload's REAL values, so a test that
    wants a specific gate to bite mutates exactly one field and leaves the rest honest.
    """
    dest = tmp_path / f"{_SESSION_ID}.mat"
    dest.write_bytes(payload)
    return {
        "id": _SESSION_ID,
        "url": _URL,
        "sha256": sha256 if sha256 is not None else "PENDING",
        "size_bytes": len(payload),
        "zenodo_md5": hashlib.md5(payload, usedforsecurity=False).hexdigest(),
    }


def test_valid_payload_fills_pending_sha256(tmp_path: Path) -> None:
    """RD-01d positive control: real magic bytes, real size and real md5 must NOT raise."""
    session = _write_session(tmp_path, _VALID_PAYLOAD)

    changed, summary = download_indy._process_session(session, tmp_path)

    assert changed is True
    assert session["sha256"] == hashlib.sha256(_VALID_PAYLOAD).hexdigest()
    assert len(session["sha256"]) == 64
    assert set(session["sha256"]) <= _HEX
    assert _SESSION_ID in summary


def test_rejects_html_error_page(tmp_path: Path) -> None:
    """RD-01d: a Zenodo HTML error page is refused on magic bytes, before any checksum."""
    session = _write_session(tmp_path, b"<!DOCTYPE html><html>Zenodo is down</html>")

    with pytest.raises(ValueError, match="MATLAB"):
        download_indy._process_session(session, tmp_path)

    assert session["sha256"] == "PENDING", "an error page must never be checksummed as canonical"


def test_rejects_size_mismatch(tmp_path: Path) -> None:
    """P2/P11: a truncated or partially-written transfer is refused on byte size."""
    session = _write_session(tmp_path, _VALID_PAYLOAD)
    session["size_bytes"] = len(_VALID_PAYLOAD) + 1

    with pytest.raises(ValueError, match="size mismatch"):
        download_indy._process_session(session, tmp_path)

    assert session["sha256"] == "PENDING"


def test_rejects_md5_mismatch(tmp_path: Path) -> None:
    """P2: the publisher-side md5 cross-check is independent of our own first fetch."""
    session = _write_session(tmp_path, _VALID_PAYLOAD)
    session["zenodo_md5"] = "0" * 32

    with pytest.raises(ValueError, match="md5"):
        download_indy._process_session(session, tmp_path)

    assert session["sha256"] == "PENDING"


def test_rejects_sha256_mismatch(tmp_path: Path) -> None:
    """RD-01c: the committed sha256 pin still bites (threat T-04-02-01, unchanged)."""
    session = _write_session(tmp_path, _VALID_PAYLOAD, sha256="a" * 64)

    with pytest.raises(ValueError, match="checksum mismatch"):
        download_indy._process_session(session, tmp_path)


def test_matching_sha256_verifies_without_rewrite(tmp_path: Path) -> None:
    """RD-01c discriminator: a matching pin verifies quietly instead of always raising."""
    real_sha256 = hashlib.sha256(_VALID_PAYLOAD).hexdigest()
    session = _write_session(tmp_path, _VALID_PAYLOAD, sha256=real_sha256)

    changed, summary = download_indy._process_session(session, tmp_path)

    assert changed is False
    assert session["sha256"] == real_sha256
    assert _SESSION_ID in summary


def test_missing_size_bytes_is_an_error(tmp_path: Path) -> None:
    """A manifest entry without size_bytes cannot be cross-checked, so it is not trusted."""
    session = _write_session(tmp_path, _VALID_PAYLOAD)
    del session["size_bytes"]

    with pytest.raises(ValueError, match="size_bytes"):
        download_indy._process_session(session, tmp_path)

    assert session["sha256"] == "PENDING"


def test_missing_zenodo_md5_is_an_error(tmp_path: Path) -> None:
    """A manifest entry without zenodo_md5 loses the publisher-independent cross-check."""
    session = _write_session(tmp_path, _VALID_PAYLOAD)
    del session["zenodo_md5"]

    with pytest.raises(ValueError, match="zenodo_md5"):
        download_indy._process_session(session, tmp_path)

    assert session["sha256"] == "PENDING"
