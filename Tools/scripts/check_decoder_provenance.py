#!/usr/bin/env python3
"""D-19 leg (c): the committed decoder numbers agree with the manifest bytes they came from.

Compares ``Decoder/manifests/indy_sessions.json`` against the committed ``09-decoder-metrics.json``
and FAILS (exit 1) unless every session the metrics claim to have been produced from appears in the
manifest under a byte-identical sha256.

This leg exists as a separate helper because it cannot be a grep. The other two assertions in
``decoder-policy.sh`` are token-presence checks, which a regex does fine; AGREEMENT between two
files is a set comparison. A metrics file can carry a perfectly well-formed 64-hex checksum that is
simply not the one in the manifest, and no regex over either file alone can see that.

It also asserts the two preconditions that make the comparison mean anything:

* the manifest carries no ``"PENDING"`` sha256 -- an unverified session pins nothing, so a number
  attributed to it is unprovenanced;
* the metrics declare a non-empty ``data_source`` -- a number that does not record whether it came
  from real or synthetic spikes is not traceable at all.

Sessions the manifest lists but the metrics did not train on are allowed ONLY when the metrics name
them under ``excluded_sessions``. With no exclusions -- the committed case -- that reduces to plain
set equality; with an honest exclusion it stays green instead of forcing the artifact to lie.

Usage:
    python3 Tools/scripts/check_decoder_provenance.py <manifest.json> <metrics.json>

Runs under the runner's preinstalled ``python3`` with no uv environment and no third-party import,
the same way ``Tools/scripts/check_refit_uplift.py`` does.

Exit 0: the checksum sets agree. Exit 1: a PENDING checksum, a missing or empty ``data_source``, a
malformed file, or a disagreement (which names the session and prints both values).
No bare ``except`` (project rule): every failure mode is caught by its specific exception type.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

PENDING = "PENDING"
SHA256_LEN = 64
HEX_DIGITS = frozenset("0123456789abcdef")
USAGE = "usage: python3 Tools/scripts/check_decoder_provenance.py <manifest.json> <metrics.json>"


def fail(message: str) -> int:
    """Print a single ERROR line to stderr and return the failing exit code."""
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def load_json(path: Path, label: str) -> dict | None:
    """Parse a JSON object, or print why it could not be parsed and return None."""
    if not path.is_file():
        print(f"ERROR: {label} not found at {path}", file=sys.stderr)
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: {label} at {path} is not valid JSON: {exc}", file=sys.stderr)
        return None
    except OSError as exc:
        print(f"ERROR: could not read {label} at {path}: {exc}", file=sys.stderr)
        return None
    if not isinstance(payload, dict):
        print(
            f"ERROR: {label} at {path} is a {type(payload).__name__}, not a JSON object",
            file=sys.stderr,
        )
        return None
    return payload


def session_entries(payload: dict, path: Path, label: str) -> list[dict] | None:
    """Return a non-empty list of session objects, or print why one could not be read."""
    sessions = payload.get("sessions")
    if not isinstance(sessions, list) or not sessions:
        print(
            f"ERROR: {label} at {path} has no non-empty 'sessions' array, so it names no bytes",
            file=sys.stderr,
        )
        return None
    for index, entry in enumerate(sessions):
        if not isinstance(entry, dict):
            print(
                f"ERROR: {label} at {path} sessions[{index}] is a {type(entry).__name__}, "
                f"not an object",
                file=sys.stderr,
            )
            return None
    return sessions


def id_and_sha(entry: dict, index: int, path: Path, label: str) -> tuple[str, str] | None:
    """Return an entry's (id, sha256), or print which field is missing or malformed."""
    session_id = entry.get("id")
    sha256 = entry.get("sha256")
    if not isinstance(session_id, str) or not session_id:
        print(
            f"ERROR: {label} at {path} sessions[{index}] has no non-empty string 'id'",
            file=sys.stderr,
        )
        return None
    if not isinstance(sha256, str) or not sha256:
        print(
            f"ERROR: {label} at {path} session '{session_id}' has no non-empty string 'sha256'",
            file=sys.stderr,
        )
        return None
    return session_id, sha256


def is_hex_sha256(value: str) -> bool:
    """True when value is exactly 64 lowercase hex digits."""
    return len(value) == SHA256_LEN and all(char in HEX_DIGITS for char in value)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"ERROR: expected 2 arguments, got {len(argv) - 1}. {USAGE}", file=sys.stderr)
        return 1

    manifest_path = Path(argv[1])
    metrics_path = Path(argv[2])

    manifest = load_json(manifest_path, "manifest")
    if manifest is None:
        return 1
    metrics = load_json(metrics_path, "metrics")
    if metrics is None:
        return 1

    # (1) The manifest names verified bytes for every session it lists.
    manifest_sessions = session_entries(manifest, manifest_path, "manifest")
    if manifest_sessions is None:
        return 1
    manifest_pairs: set[tuple[str, str]] = set()
    for index, entry in enumerate(manifest_sessions):
        pair = id_and_sha(entry, index, manifest_path, "manifest")
        if pair is None:
            return 1
        if pair[1] == PENDING:
            return fail(
                f"manifest session '{pair[0]}' still has sha256 {PENDING}: the file was never "
                f"verified, so any number pinned to it is unprovenanced (D-19a, RD-01a)"
            )
        manifest_pairs.add(pair)

    # (2) The metrics say where their numbers came from.
    data_source = metrics.get("data_source")
    if not isinstance(data_source, str) or not data_source.strip():
        return fail(
            f"metrics at {metrics_path} has no non-empty string 'data_source': a published number "
            f"that does not record whether it was measured on real or synthetic spikes is not "
            f"traceable (D-19b)"
        )

    # (3) The metrics name well-formed checksums.
    metrics_sessions = session_entries(metrics, metrics_path, "metrics")
    if metrics_sessions is None:
        return 1
    metrics_pairs: set[tuple[str, str]] = set()
    for index, entry in enumerate(metrics_sessions):
        pair = id_and_sha(entry, index, metrics_path, "metrics")
        if pair is None:
            return 1
        if not is_hex_sha256(pair[1]):
            return fail(
                f"metrics session '{pair[0]}' has sha256 '{pair[1]}', which is not 64 lowercase "
                f"hex digits: a placeholder cannot pin a number to any bytes (D-19b)"
            )
        metrics_pairs.add(pair)

    manifest_ids = {session_id for session_id, _ in manifest_pairs}
    metrics_ids = {session_id for session_id, _ in metrics_pairs}
    manifest_sha_by_id = dict(manifest_pairs)

    # (4a) Every session the metrics claim must exist in the manifest.
    unknown = sorted(metrics_ids - manifest_ids)
    if unknown:
        return fail(
            f"metrics name session(s) the manifest does not list: {', '.join(unknown)}. "
            f"A number cannot be pinned to bytes the reproducibility record never recorded (D-19c)"
        )

    # (4b) Manifest sessions the metrics skipped must be named as deliberate exclusions.
    excluded = metrics.get("excluded_sessions")
    excluded_ids: set[str] = set()
    if isinstance(excluded, list):
        for entry in excluded:
            if isinstance(entry, dict) and isinstance(entry.get("id"), str):
                excluded_ids.add(entry["id"])
    unaccounted = sorted(manifest_ids - metrics_ids - excluded_ids)
    if unaccounted:
        return fail(
            f"manifest session(s) {', '.join(unaccounted)} appear in neither metrics.sessions nor "
            f"metrics.excluded_sessions. A session that silently vanished from a run is the "
            f"difference between a pooled number and a smaller one (D-19c)"
        )

    # (4c) Shared sessions must carry byte-identical checksums.
    disagreements = sorted(
        (session_id, sha256, manifest_sha_by_id[session_id])
        for session_id, sha256 in metrics_pairs
        if manifest_sha_by_id[session_id] != sha256
    )
    if disagreements:
        for session_id, metrics_sha, manifest_sha in disagreements:
            print(
                f"ERROR: session '{session_id}' checksum disagrees -- "
                f"metrics {metrics_sha} vs manifest {manifest_sha}",
                file=sys.stderr,
            )
        return fail(
            f"{len(disagreements)} session checksum(s) disagree between {metrics_path} and "
            f"{manifest_path}. The published numbers were produced from different bytes than the "
            f"manifest pins, so the provenance chain is broken (D-19c)"
        )

    skipped = f", {len(excluded_ids)} declared exclusion(s)" if excluded_ids else ""
    print(
        f"OK: {len(metrics_pairs)} session(s) agree on id and sha256 between "
        f"{manifest_path} and {metrics_path} (data_source={data_source!r}{skipped})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
