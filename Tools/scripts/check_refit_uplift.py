#!/usr/bin/env python3
"""Deterministic CI guard for the Phase-7 ReFIT BPS uplift (REFIT-03, D-10).

Reads the committed ``refit_bps.json`` and FAILS (exit 1) unless ``refit_bps >= raw_bps`` — the
ReFIT intent-rotation must never regress below the raw NDT1 output on the fixed seed. This mirrors
Phase-4's ``co-bps > null`` gate (04-training-evidence.md): a structural invariant on the committed
evidence so a filter regression that erases the uplift fails the build, deterministically (the JSON
is produced by a seed/index-driven harness with no clock/RNG, so this is non-flaky).

The number guarded is **Soukoreff & MacKenzie 2004 ISO 9241-9 Fitts throughput** (TP = IDe/MT,
effective-width method) — NOT the Neuralink/BrainGate Webgrid bitrate; this guard asserts the
raw->ReFIT ORDERING on the identical seed-locked replay, not any comparison to the 4.16/8.5 reference
numbers (that comparison is Phase 8, deferred per D-13).

Usage:
    python3 Tools/scripts/check_refit_uplift.py [path/to/refit_bps.json]

Defaults to .planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json.
Exit 0: refit_bps >= raw_bps (uplift holds). Exit 1: regression, malformed JSON, or missing keys.
No bare ``except`` (project rule): each failure mode is caught by its specific exception type.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

DEFAULT_JSON = Path(
    ".planning/phases/07-refit-kalman-closed-loop-recalibration/refit_bps.json"
)
REQUIRED_KEYS = ("raw_bps", "kalman_only_bps", "refit_bps", "delta", "n_trials", "seed", "dt")


def main(argv: list[str]) -> int:
    json_path = Path(argv[1]) if len(argv) > 1 else DEFAULT_JSON

    if not json_path.is_file():
        print(f"ERROR: refit_bps.json not found at {json_path}", file=sys.stderr)
        return 1

    try:
        payload = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"ERROR: {json_path} is not valid JSON: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"ERROR: could not read {json_path}: {exc}", file=sys.stderr)
        return 1

    missing = [k for k in REQUIRED_KEYS if k not in payload]
    if missing:
        print(
            f"ERROR: {json_path} is missing required key(s): {', '.join(missing)}",
            file=sys.stderr,
        )
        return 1

    try:
        raw_bps = float(payload["raw_bps"])
        refit_bps = float(payload["refit_bps"])
    except (TypeError, ValueError) as exc:
        print(f"ERROR: raw_bps/refit_bps are not numeric in {json_path}: {exc}", file=sys.stderr)
        return 1

    if refit_bps >= raw_bps:
        print(
            "OK: refit_bps >= raw_bps "
            f"(refit_bps={refit_bps}, raw_bps={raw_bps}, delta={refit_bps - raw_bps}). "
            "The ReFIT intent-rotation uplift holds on the fixed seed "
            f"(seed={payload['seed']}, n_trials={payload['n_trials']}). "
            "[S&M-2004 Fitts throughput — NOT the Webgrid bitrate; no 4.16/8.5 comparison, D-13.]"
        )
        return 0

    print(
        "ERROR: refit_bps < raw_bps "
        f"(refit_bps={refit_bps}, raw_bps={raw_bps}) — the ReFIT uplift regressed below raw NDT1 "
        "(REFIT-03 / D-10 violated). A filter change erased the intent-rotation benefit; "
        "regenerate refit_bps.json from CortexReFITBench --smoke and investigate.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
