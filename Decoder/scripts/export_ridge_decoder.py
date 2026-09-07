"""Export the matched linear velocity decoder for the Swift replay path.

`fit_baseline_decoders.py` established that a causal ridge filter on raw binned spikes reaches a
higher held-out velocity R2 than the NDT1 encoder readout on this data. That was a measurement made
in Python and reported in a table. This script ships the decoder that produced it, so the same
filter can drive the on-device replay rather than only appearing in a comparison.

**Nothing is refit or retuned here.** The weights come from `_run_history(sessions, history=32)`
in that script, called directly rather than reimplemented, at the history length that sees exactly
the bins the encoder sees (`K = SEQ_LEN = 32`). Its lambda-selection rule is the documented weak
one, and it is deliberately kept: changing it would ship a decoder whose held-out score is not the
number the comparison table publishes.

**Layout, and why the Swift side needs no reordering.** `_windows` writes feature block `tap` from
`binned[SEQ_LEN - history + tap]`, so at `history == SEQ_LEN` block `tap` IS window bin `tap`,
oldest first. `RecordedSpikeSource` hands Swift the same window bin-major as
`window[bin * channels + channel]`. The two index expressions are therefore identical and the
exported weight vector is consumed in its natural order.

The output is a little-endian float32 blob plus a JSON sidecar carrying the provenance and the
held-out R2 the shipped weights achieve, so a number quoted for this decoder can be traced to the
fit that produced it.

    uv run --project Decoder python Decoder/scripts/export_ridge_decoder.py
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

_SCRIPTS = Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

# ruff: noqa: E402  -- sys.path must be extended above before these resolve.
from fit_baseline_decoders import (
    LAG_BINS,
    SEQ_LEN,
    _design,
    _GramAccumulator,
    _predict,
    _run_history,
    _solve,
)

from ndt1.data import BIN_MS
from ndt1.kinematics import heldout_r2
from ndt1.sessions import DEFAULT_DATA_DIR, available_sessions

#: The like-for-like history: the decoder sees exactly the 32 bins the encoder's window holds.
HISTORY_BINS: int = SEQ_LEN

#: Where the Swift package looks for the blob. A SwiftPM resource, committed, ~24 KB.
DEFAULT_OUT = (
    Path(__file__).resolve().parents[2]
    / "Packages/CortexDecoder/Sources/CortexDecoder/Resources/ridge_velocity_k32.bin"
)

#: Bumped whenever the blob's byte layout changes. The Swift loader refuses a version it does not
#: know rather than reading a differently-shaped file as if it were this one.
SCHEMA_VERSION = 1


def _blob(weight: np.ndarray, bias: np.ndarray) -> bytes:
    """Pack the decoder as little-endian float32: a 4-word header, then weights, then bias.

    Header: schema version, history bins, channel count, 0 (reserved), all as float32 so the whole
    file is one dtype and the Swift loader needs no mixed-width reads.
    """
    n_features, n_out = weight.shape
    if n_out != 2:
        raise ValueError(f"expected a 2-output decoder, got {n_out}")
    channels = n_features // HISTORY_BINS
    if channels * HISTORY_BINS != n_features:
        raise ValueError(f"{n_features} features is not a multiple of {HISTORY_BINS} bins")
    header = np.array([SCHEMA_VERSION, HISTORY_BINS, channels, 0], dtype="<f4")
    # Row-major (feature, axis) so Swift reads weight[feature * 2 + axis] in one pass.
    body = np.ascontiguousarray(weight, dtype="<f4")
    tail = np.ascontiguousarray(bias, dtype="<f4")
    return header.tobytes() + body.tobytes() + tail.tobytes()


def _self_check(weight: np.ndarray, bias: np.ndarray, channels: int) -> dict:
    """Predict from a fixed synthetic window, so Swift can assert the same two numbers.

    A parity fixture the size of a real window would be 3,072 floats; this is a deterministic rule
    Swift can reproduce in four lines, which pins the load path, the feature order and the dot
    product without committing a large fixture.
    """
    n_features = HISTORY_BINS * channels
    idx = np.arange(n_features, dtype=np.float64)
    probe = ((idx % 7) - 3.0) / 4.0  # spans negative and positive, never uniform across a bin
    out = probe @ weight + bias
    return {
        "rule": "feature i = ((i % 7) - 3) / 4, i over 0..<(history*channels), bin-major",
        "vx": float(out[0]),
        "vy": float(out[1]),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args(argv)

    sessions, excluded = available_sessions(args.data_dir)
    if not sessions:
        print(f"no sessions under {args.data_dir}; run download_indy.py first", file=sys.stderr)
        return 1
    ids = [s.session_id for s in sessions]
    print(f"loaded {len(ids)} session(s): {', '.join(ids)}", file=sys.stderr)
    for skipped in excluded:
        print(f"  excluded {skipped}", file=sys.stderr)

    # The published fit, called rather than reproduced.
    result = _run_history(sessions, HISTORY_BINS, LAG_BINS)

    # `_run_history` reports but does not return the weights, so rebuild them from the same
    # accumulator inputs and the lambda it selected. Verified below against its own R2.
    designs = [_design(s, HISTORY_BINS, LAG_BINS) for s in sessions]
    acc = _GramAccumulator.empty(designs[0].train_x.shape[1])
    for d in designs:
        acc.add(d.train_x, d.train_y)
    sxx, sxy, mean_x, mean_y = acc.centered()
    weight, bias = _solve(sxx, sxy, mean_x, mean_y, result["lambda"])

    pooled_true = np.concatenate([d.test_y for d in designs], axis=0)
    pooled_pred = np.concatenate([_predict(d.test_x, weight, bias) for d in designs], axis=0)
    check = heldout_r2(pooled_true, pooled_pred, mean_y)
    published = result["heldout_r2"]["pooled"]
    if abs(check["pooled"] - published) > 1e-9:
        raise ValueError(
            f"the exported weights score {check['pooled']:.6f} but _run_history reported "
            f"{published:.6f}; the shipped decoder is not the one that was measured"
        )
    print(f"exported weights reproduce the published pooled R2 {published:.4f}", file=sys.stderr)

    channels = weight.shape[0] // HISTORY_BINS
    blob = _blob(weight, bias)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(blob)

    sidecar = args.out.with_suffix(".json")
    sidecar.write_text(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "what_this_is": (
                    "The matched causal ridge velocity decoder from fit_baseline_decoders.py at "
                    "history=32 bins, shipped so the Swift replay path can run the same filter the "
                    "comparison table scores. Not refit and not retuned here."
                ),
                "binary": args.out.name,
                "binary_sha256": hashlib.sha256(blob).hexdigest(),
                "history_bins": HISTORY_BINS,
                "history_ms": HISTORY_BINS * BIN_MS,
                "channels": channels,
                "lag_bins": LAG_BINS,
                "bin_ms": BIN_MS,
                "lambda": result["lambda"],
                "lambda_selection": result["lambda_selection"],
                "units": {"input": "spike counts/bin", "output": "cm/s"},
                "feature_order": (
                    "bin-major, oldest bin first: feature index = bin * channels + channel, which "
                    "is the order RecordedSpikeSource hands Swift its window in"
                ),
                "sessions_fit_on": ids,
                "heldout_r2": result["heldout_r2"],
                "per_session": result["per_session"],
                "self_check": _self_check(weight, bias, channels),
                "not_a_claim": (
                    "A held-out R2 is a velocity-reconstruction score on recorded data. It is not "
                    "an acquisition rate and says nothing about online control."
                ),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    print(f"wrote {args.out} ({len(blob)} bytes) and {sidecar.name}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
