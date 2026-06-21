#!/usr/bin/env python3
"""Reproducible Zenodo downloader for the curated Indy M1-only sessions (DEC-02).

Reads ``Decoder/manifests/indy_sessions.json`` and fetches each session's ``.mat`` to
``Decoder/data/`` (gitignored) via its **direct file URL** (``urllib.request``, streamed) —
NOT Zenodo's ``/api/records`` endpoint, which is bot-gated (04-RESEARCH DEC-02). For each file
it computes a SHA-256 and either:

  * fills the manifest's ``sha256`` when it is ``"PENDING"`` (first verified fetch), or
  * verifies the download against the committed ``sha256`` and raises ``ValueError`` on a
    mismatch — the integrity gate against MITM / a corrupted Zenodo mirror (threat T-04-02-01).

The committed manifest + checksums make the training data reproducible without committing the
large ``.mat`` files. No bare/blind ``except``: only ``OSError`` / ``urllib.error.URLError`` /
``ValueError`` are caught explicitly.

Usage:
    uv run --project Decoder python Decoder/scripts/download_indy.py
    uv run --project Decoder python Decoder/scripts/download_indy.py --manifest <path> --out <dir>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

_PENDING = "PENDING"
_CHUNK = 1 << 20  # 1 MiB streaming chunks — never load a whole .mat into memory
# Zenodo bot-gates default urllib; a real browser UA is required to fetch the file bytes.
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    )
}

# Repo-relative default paths (this file lives at Decoder/scripts/download_indy.py).
_DECODER_ROOT = Path(__file__).resolve().parents[1]
_DEFAULT_MANIFEST = _DECODER_ROOT / "manifests" / "indy_sessions.json"
_DEFAULT_OUT = _DECODER_ROOT / "data"


def _sha256_of(path: Path) -> str:
    """Stream a file through SHA-256 (constant memory) and return the hex digest."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(_CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def _download(url: str, dest: Path) -> None:
    """Stream `url` to `dest` (1 MiB chunks). Raises on a non-direct (/api/) URL."""
    if "/api/" in url:
        raise ValueError(
            f"refusing to fetch via the bot-gated /api/ endpoint: {url} "
            "(use the direct /records/<id>/files/<name> URL — 04-RESEARCH DEC-02)"
        )
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers=_HEADERS)  # noqa: S310 (https Zenodo URL)
    with urllib.request.urlopen(request) as response, dest.open("wb") as out:  # noqa: S310
        while True:
            chunk = response.read(_CHUNK)
            if not chunk:
                break
            out.write(chunk)


def _process_session(
    session: dict[str, str], out_dir: Path
) -> tuple[bool, str]:
    """Fetch + checksum one session. Returns (manifest_changed, one_line_summary).

    Fills a ``PENDING`` checksum, or verifies an existing one (raising on mismatch).
    """
    session_id = session["id"]
    url = session["url"]
    expected = session.get("sha256", _PENDING)
    dest = out_dir / f"{session_id}.mat"

    if not dest.exists():
        _download(url, dest)

    digest = _sha256_of(dest)

    if expected == _PENDING:
        session["sha256"] = digest
        return True, f"{session_id}: fetched, sha256 filled ({digest[:12]}…)"

    if digest != expected:
        raise ValueError(
            f"checksum mismatch for {session_id}: expected {expected}, got {digest} — "
            "the downloaded .mat is corrupt or tampered (integrity gate T-04-02-01)"
        )
    return False, f"{session_id}: verified ({digest[:12]}…)"


def main(argv: list[str] | None = None) -> int:
    """Read the manifest, fetch + checksum each session, persist any filled checksums."""
    parser = argparse.ArgumentParser(description="Download + checksum the Indy M1 sessions.")
    parser.add_argument("--manifest", type=Path, default=_DEFAULT_MANIFEST)
    parser.add_argument("--out", type=Path, default=_DEFAULT_OUT)
    args = parser.parse_args(argv)

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except OSError as exc:
        print(f"error: cannot read manifest {args.manifest}: {exc}", file=sys.stderr)
        return 1
    except ValueError as exc:  # json.JSONDecodeError is a ValueError subclass
        print(f"error: manifest {args.manifest} is not valid JSON: {exc}", file=sys.stderr)
        return 1

    sessions = manifest.get("sessions", [])
    if not sessions:
        print(f"error: manifest {args.manifest} has no sessions", file=sys.stderr)
        return 1

    changed = False
    for session in sessions:
        try:
            session_changed, summary = _process_session(session, args.out)
        except (OSError, urllib.error.URLError) as exc:
            print(f"{session.get('id', '?')}: download failed: {exc}", file=sys.stderr)
            return 1
        except ValueError as exc:
            print(f"{session.get('id', '?')}: {exc}", file=sys.stderr)
            return 1
        changed = changed or session_changed
        print(summary)

    if changed:
        try:
            args.manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        except OSError as exc:
            print(f"error: could not write filled checksums to {args.manifest}: {exc}",
                  file=sys.stderr)
            return 1
        print(f"manifest updated with filled checksums: {args.manifest}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
