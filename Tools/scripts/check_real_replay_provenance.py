#!/usr/bin/env python3
"""D-09 cross-file set comparison for the Phase-10 real-data artifact trio.

Compares ``Decoder/manifests/indy_sessions.json`` against the three committed Phase-10 artifacts:
``10-refit-real.json``, ``10-replay.json``, and ``10-ceiling.json``. FAILS (exit 1) unless every
structural provenance invariant holds across all four files.

This leg exists as a separate helper because it cannot be a grep. The agreements checked here
compare values across two or more files -- a structural check that a regex over either file alone
cannot perform. A committed artifact can carry a perfectly well-formed 64-hex checksum that is
simply the wrong one, and no regex over one file will see that.

This script asserts PROVENANCE, SCHEMA and STRUCTURE only. It never asserts the sign or magnitude
of a real-data result (D-09). The assertion about ``ticks_model_backed`` in particular is a
STRUCTURAL check about whether the model ran at all -- it is not a measurement of latency or
throughput and is not a D-09 violation.

Assertions, in order:
    1. All four files parse as JSON.
    2. The manifest has a non-empty ``sessions`` array and no session's ``sha256`` is ``"PENDING"``.
    3. Each of the three phase artifacts has ``data_source == "real"`` and a non-empty
       ``session_id``.
    4. All three ``session_id`` values are identical, and that id is present in the manifest.
    5. All three ``source_sha256`` values are 64 lowercase hex, identical to each other, and
       byte-equal to the manifest entry for that session id.
    6. ``10-refit-real.json`` and ``10-replay.json`` carry the same ``export_sidecar_sha256``
       (64 lowercase hex).
    7. ``10-replay.json``'s ``replay_reference_hits`` equals ``10-ceiling.json``'s
       ``canonical_hits``, and ``replay_reference_ref`` is a non-empty dict. This confirms the
       replay records the same recorded-cursor reference it was measured against. Per section 11
       of 10-PREREGISTRATION, the field is named ``replay_reference_hits``, not ``ceiling_hits``.
    8. ``10-refit-real.json``'s ``encoder_checkpoint_sha256`` and ``velocity_checkpoint_sha256``
       are both 64 lowercase hex.
    9. ``10-replay.json``'s ``ticks_model_backed == ticks_total``, and both are positive. This is
       a STRUCTURAL assertion about whether the model ran at all, not an assertion about a measured
       value. A replay that completed zero model-backed ticks ran nothing.

Usage:
    python3 Tools/scripts/check_real_replay_provenance.py \\
        <manifest.json> <refit-real.json> <replay.json> <ceiling.json>

Runs under the runner's preinstalled ``python3`` with no uv environment and no third-party import,
the same way ``Tools/scripts/check_refit_uplift.py`` and ``check_decoder_provenance.py`` do.

Exit 0: all assertions pass. Exit 1: any assertion fails (see ERROR line on stderr).
No bare ``except`` (project rule): every failure mode is caught by its specific exception type.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

SHA256_LEN = 64
HEX_DIGITS = frozenset("0123456789abcdef")
PENDING = "PENDING"
USAGE = (
    "usage: python3 Tools/scripts/check_real_replay_provenance.py"
    " <manifest.json> <refit-real.json> <replay.json> <ceiling.json>"
)


def _fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1


def _load_json(path: Path, label: str) -> dict | None:
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


def _is_hex_sha256(value: str) -> bool:
    return len(value) == SHA256_LEN and all(c in HEX_DIGITS for c in value)


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(
            f"ERROR: expected 4 arguments, got {len(argv) - 1}. {USAGE}",
            file=sys.stderr,
        )
        return 1

    manifest_path = Path(argv[1])
    refit_path = Path(argv[2])
    replay_path = Path(argv[3])
    ceiling_path = Path(argv[4])

    # Assertion 1: all four files parse as JSON.
    manifest = _load_json(manifest_path, "manifest")
    if manifest is None:
        return 1
    refit = _load_json(refit_path, "refit-real")
    if refit is None:
        return 1
    replay = _load_json(replay_path, "replay")
    if replay is None:
        return 1
    ceiling = _load_json(ceiling_path, "ceiling")
    if ceiling is None:
        return 1

    # Assertion 2: manifest has non-empty sessions array, no PENDING sha256.
    sessions = manifest.get("sessions")
    if not isinstance(sessions, list) or not sessions:
        return _fail(f"manifest at {manifest_path} has no non-empty 'sessions' array")
    for entry in sessions:
        try:
            sha = entry.get("sha256", "")
        except (TypeError, ValueError):
            return _fail(f"manifest at {manifest_path}: a session entry is not an object")
        if sha == PENDING:
            sid = entry.get("id", "<unknown>") if isinstance(entry, dict) else "<unknown>"
            return _fail(
                f"manifest session '{sid}' still has sha256 PENDING: the file was never "
                f"verified, so any number pinned to it is unprovenanced (D-09/RD-07)"
            )

    # Assertion 3: each phase artifact has data_source == "real" and non-empty session_id.
    for label, artifact in (
        ("refit-real", refit),
        ("replay", replay),
        ("ceiling", ceiling),
    ):
        ds = artifact.get("data_source")
        if ds != "real":
            return _fail(
                f"{label}: data_source must be 'real', got {ds!r}. A published real-data "
                f"artifact must declare its source (D-09)"
            )
        sid = artifact.get("session_id")
        if not isinstance(sid, str) or not sid:
            return _fail(
                f"{label}: session_id must be a non-empty string, got {sid!r}"
            )

    # Assertion 4: all three session_id values are identical and present in the manifest.
    refit_sid = refit["session_id"]
    replay_sid = replay["session_id"]
    ceiling_sid = ceiling["session_id"]
    if not (refit_sid == replay_sid == ceiling_sid):
        return _fail(
            f"session_id disagrees across artifacts: "
            f"refit-real={refit_sid!r} replay={replay_sid!r} ceiling={ceiling_sid!r}. "
            f"All three must name the same session."
        )
    session_id = refit_sid
    manifest_by_id = {
        entry["id"]: entry
        for entry in sessions
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }
    if session_id not in manifest_by_id:
        return _fail(
            f"session_id {session_id!r} is not in the manifest at {manifest_path}. "
            f"A published number cannot be pinned to a session the manifest never recorded."
        )

    # Assertion 5: all three source_sha256 values are 64 lowercase hex, identical, and agree
    # with the manifest entry for the session.
    for label, artifact in (
        ("refit-real", refit),
        ("replay", replay),
        ("ceiling", ceiling),
    ):
        sha = artifact.get("source_sha256", "")
        if not isinstance(sha, str) or not _is_hex_sha256(sha):
            return _fail(
                f"{label}: source_sha256 {sha!r} is not 64 lowercase hex digits. "
                f"A placeholder cannot pin a number to any bytes."
            )

    refit_sha = refit["source_sha256"]
    replay_sha = replay["source_sha256"]
    ceiling_sha = ceiling["source_sha256"]
    if not (refit_sha == replay_sha == ceiling_sha):
        return _fail(
            f"source_sha256 disagrees across artifacts: "
            f"refit-real={refit_sha!r} replay={replay_sha!r} ceiling={ceiling_sha!r}. "
            f"All three must name the same session bytes."
        )
    source_sha = refit_sha
    manifest_sha = manifest_by_id[session_id].get("sha256", "")
    if source_sha != manifest_sha:
        return _fail(
            f"session={session_id!r}: source_sha256 in artifacts is {source_sha!r} but "
            f"the manifest records {manifest_sha!r}. The published numbers were produced from "
            f"different bytes than the manifest pins, so the provenance chain is broken."
        )

    # Assertion 6: refit-real and replay carry the same export_sidecar_sha256 (64 lowercase hex).
    refit_sidecar = refit.get("export_sidecar_sha256", "")
    replay_sidecar = replay.get("export_sidecar_sha256", "")
    if not isinstance(refit_sidecar, str) or not _is_hex_sha256(refit_sidecar):
        return _fail(
            f"refit-real: export_sidecar_sha256 {refit_sidecar!r} is not 64 lowercase hex"
        )
    if not isinstance(replay_sidecar, str) or not _is_hex_sha256(replay_sidecar):
        return _fail(
            f"replay: export_sidecar_sha256 {replay_sidecar!r} is not 64 lowercase hex"
        )
    if refit_sidecar != replay_sidecar:
        return _fail(
            f"export_sidecar_sha256 disagrees: refit-real={refit_sidecar!r} "
            f"replay={replay_sidecar!r}. Both artifacts must record the same export bytes."
        )

    # Assertion 7: replay's replay_reference_hits == ceiling's canonical_hits, and
    # replay_reference_ref is a non-empty dict. Per 10-PREREGISTRATION section 11, the field is
    # named replay_reference_hits (not ceiling_hits).
    replay_ref_hits = replay.get("replay_reference_hits")
    ceiling_canonical_hits = ceiling.get("canonical_hits")
    if not isinstance(replay_ref_hits, int):
        return _fail(
            f"replay: replay_reference_hits must be an int; got {replay_ref_hits!r}. "
            f"Per 10-PREREGISTRATION section 11, the field is replay_reference_hits, "
            f"not ceiling_hits."
        )
    if not isinstance(ceiling_canonical_hits, int):
        return _fail(
            f"ceiling: canonical_hits must be an int; got {ceiling_canonical_hits!r}"
        )
    if replay_ref_hits != ceiling_canonical_hits:
        return _fail(
            f"replay.replay_reference_hits={replay_ref_hits} but "
            f"ceiling.canonical_hits={ceiling_canonical_hits}. "
            f"The replay and ceiling artifacts must record the same recorded-cursor hit count."
        )
    replay_ref_ref = replay.get("replay_reference_ref")
    if not isinstance(replay_ref_ref, dict) or not replay_ref_ref:
        return _fail(
            f"replay: replay_reference_ref must be a non-empty dict naming the ceiling artifact; "
            f"got {replay_ref_ref!r}"
        )

    # Assertion 8: refit-real's checkpoint sha256s are 64 lowercase hex.
    for key in ("encoder_checkpoint_sha256", "velocity_checkpoint_sha256"):
        val = refit.get(key, "")
        if not isinstance(val, str) or not _is_hex_sha256(val):
            return _fail(
                f"refit-real: {key} {val!r} is not 64 lowercase hex. "
                f"The checkpoint that produced these numbers must be pinned."
            )

    # Assertion 9: replay's ticks_model_backed == ticks_total, both positive.
    # STRUCTURAL assertion: did the model run at all? Not a D-09 violation (see module docstring).
    tmb = replay.get("ticks_model_backed")
    tt = replay.get("ticks_total")
    if not isinstance(tmb, int) or not isinstance(tt, int):
        return _fail(
            f"replay: ticks_model_backed ({tmb!r}) and ticks_total ({tt!r}) must both be ints"
        )
    if tmb != tt:
        return _fail(
            f"replay: ticks_model_backed={tmb} != ticks_total={tt}. "
            f"Structural check that the model ran for every tick."
        )
    if tmb <= 0:
        return _fail(
            f"replay: ticks_model_backed={tmb} must be positive. "
            f"A replay that completed zero model-backed ticks ran nothing."
        )

    print(
        f"OK: session={session_id!r} source_sha256={source_sha[:16]}... "
        f"sidecar_sha256={refit_sidecar[:16]}... -- "
        f"all three phase artifacts agree with the manifest."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
