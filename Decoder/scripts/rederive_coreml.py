#!/usr/bin/env python
"""RD-05 / RD-06 -- re-derive every CoreML-side number on the REAL-data checkpoints.

Phase 4 and Phase 5 measured the 4-bit size ratio, the palettization loss delta, the ANE op tally
and the decoder latency on models that had never seen a spike from a real recording. RD-05 forbids
carrying any of those forward, so this script re-measures each one on
`Decoder/checkpoints/ndt1_real_pooled.pt` (the reconstruction encoder, Plan 09-06) and
`Decoder/checkpoints/ndt1_real_with_velocity.pt` (the shipped model, Plan 09-07), and refuses to
run at all if either is missing or does not load.

What it measures, and on which model (D-16):

* the fp16 -> 4-bit package size ratio, on BOTH models;
* the Poisson-NLL delta, on the RECONSTRUCTION model, whose output is 96-channel log-rates;
* the held-out velocity R2 delta, on the SHIPPED model, whose output is `(vx, vy)`, scored through
  the converted packages against the same constant TRAIN-split mean-velocity null Plan 09-07 used;
* which weight tensors cleared coremltools' `weight_threshold=2048`, and specifically that the
  2 x 96 = 192-element velocity readout did NOT, so the shipped model's R2 delta is entirely
  encoder-attributable;
* the ANE op-eligibility tally of the compiled 4-bit shipped model, recorded AS MEASURED;
* whether two independent palettization runs of the same package agree.

It does NOT measure latency: that is `CortexDecoderBench`, run separately, and its Mac number is
corroborating rather than canonical. See `09-coreml-evidence.md`.

Run:
    uv run --project Decoder python Decoder/scripts/rederive_coreml.py
    uv run --project Decoder python Decoder/scripts/rederive_coreml.py --smoke   # wiring check
"""
from __future__ import annotations

import argparse
import json
import platform
import shutil
import sys
import time
from collections import Counter
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

from ndt1.compute_plan import compiled_model_path, scan_ane_eligibility
from ndt1.convert import INPUT_FEATURE_NAME, convert_to_mlpackage
from ndt1.data import BIN_MS, chronological_split
from ndt1.kinematics import apply_lag, bin_velocity, heldout_r2, planar_velocity_250hz
from ndt1.model_ane import NDT1ANE, NDT1ANEWithVelocity
from ndt1.palettize import PALETTIZE_NBITS, package_size_bytes, palettize_4bit
from ndt1.real_checkpoint import (
    REAL_ENCODER_CHECKPOINT,
    REAL_VELOCITY_CHECKPOINT,
    checkpoint_sha256,
    load_real_weights_if_present,
)
from ndt1.sessions import DEFAULT_DATA_DIR, available_sessions

SEQ_LEN: int = 32
TEST_FRAC: float = 0.2

#: The lag Plan 09-07 locked by its pre-registered rule, in 20 ms bins. The readout in the shipped
#: checkpoint was fit at this lag, so scoring it at any other one would misreport the model.
LAG_BINS: int = 1

#: coremltools 9.0 `OpPalettizerConfig` default: weight tensors with fewer elements are SKIPPED.
WEIGHT_THRESHOLD: int = 2048

#: The velocity readout is a 1x1 Conv2d(96 -> 2): 2 x 96 = 192 elements, far under the threshold.
VELOCITY_HEAD_ELEMENTS: int = 192

#: Rows per Core ML prediction batch. Purely a throughput knob; it does not affect any result.
PREDICT_BATCH: int = 512

#: Seed for the fixed NLL probe window, matching `test_palettization_loss_delta.py` exactly so the
#: script and the slow test are measuring the same thing.
NLL_SEED: int = 0

#: Held-out rows kept in `--smoke`, which exists to exercise the wiring, never to publish.
SMOKE_ROWS: int = 256

# The Phase-4/5 figures being re-derived. Committed alongside the new ones under an explicit
# `phase4_synthetic_baseline` / `phase5_baseline` key so inheritance would be visible, not silent.
PHASE4_SIZE_RATIO: float = 3.471
PHASE4_NLL_DELTA: float = 0.009114
PHASE5_ANE_BASELINE: str = "226/226 eligible, 0 CPU-only (randomly-initialized graph)"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_PHASE_DIR = (
    _REPO_ROOT / ".planning" / "phases" / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
)
_DEFAULT_METRICS = _PHASE_DIR / "09-decoder-metrics.json"
_DEFAULT_OUT_DIR = _REPO_ROOT / "Decoder" / "checkpoints"


def _log(message: str) -> None:
    """Progress to stdout, flushed, so a detached run's log is readable while it runs."""
    print(message, flush=True)


def _package_version(name: str) -> str:
    """Installed version of `name`, or `"unknown"` when the distribution is not registered."""
    try:
        return version(name)
    except PackageNotFoundError:
        return "unknown"


def _environment() -> dict[str, str]:
    """The machine and pinned wheels every number here is attributed to."""
    return {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "torch": _package_version("torch"),
        "coremltools": _package_version("coremltools"),
        "numpy": _package_version("numpy"),
        "scikit-learn": _package_version("scikit-learn"),
    }


def _fresh_compile(mlpackage_path: Path) -> Path:
    """Compile `mlpackage_path`, guaranteeing the `.mlmodelc` destination did not pre-exist.

    `compiled_model_path` derives its destination from the package name and hands it to
    coremltools' `compile_model`, which moves the freshly compiled directory to that destination
    with `shutil.move`. When the destination ALREADY EXISTS, `shutil.move` nests the new compile
    inside it rather than replacing it, and the function still returns the unchanged destination --
    so the scan reads the FIRST compile ever written there. Removing the destination first is what
    makes "the tally was measured on the real-data model" true rather than merely intended.
    """
    destination = Path(mlpackage_path).with_suffix(".mlmodelc")
    if destination.exists():
        shutil.rmtree(destination)
    compiled = compiled_model_path(mlpackage_path)
    nested = list(Path(compiled).glob("*.mlmodelc"))
    if nested:
        raise RuntimeError(
            f"{compiled} contains {len(nested)} nested compiled model(s), which means the "
            f"destination was not replaced and the scan would read a stale artifact"
        )
    return Path(compiled)


def _require_real(model: torch.nn.Module, label: str) -> str:
    """Load the real-data weights and abort unless the provenance label says they arrived."""
    provenance = load_real_weights_if_present(model)
    if "real-data" not in provenance:
        raise SystemExit(
            f"error: {label} did not load real-data weights ({provenance}). This script exists to "
            f"re-measure RD-05/RD-06 on the real checkpoints and must never quietly measure random "
            f"ones; run Decoder/scripts/train_real.py and fit_velocity_real.py first."
        )
    _log(f"  {label}: {provenance}")
    return provenance


def _convert_and_palettize(
    model: torch.nn.Module, out_dir: Path, stem: str, seq_len: int
) -> dict[str, object]:
    """Convert to an fp16 `.mlpackage`, palettize to 4-bit, record both sizes and the ratio."""
    fp16_path = out_dir / f"{stem}_fp16.mlpackage"
    palettized_path = out_dir / f"{stem}_4bit.mlpackage"
    convert_to_mlpackage(model, fp16_path, seq_len=seq_len)
    palettize_4bit(fp16_path, palettized_path)
    fp16_bytes = package_size_bytes(fp16_path)
    palettized_bytes = package_size_bytes(palettized_path)
    _log(
        f"  {stem}: fp16={fp16_bytes} B  4bit={palettized_bytes} B  "
        f"ratio={fp16_bytes / palettized_bytes:.4f}x"
    )
    return {
        "fp16_path": fp16_path,
        "palettized_path": palettized_path,
        "fp16_bytes": fp16_bytes,
        "palettized_bytes": palettized_bytes,
        "size_ratio": fp16_bytes / palettized_bytes,
    }


def _output_name(mlmodel: ct.models.MLModel) -> str:
    """The single auto-named output feature of a converted package."""
    return mlmodel.get_spec().description.output[0].name


def _predict(mlpackage_path: Path, windows: np.ndarray) -> np.ndarray:
    """Run `windows` (n, C, 1, S) fp16 through a package on CPU, returning `(n, -1)` outputs.

    Batched only for throughput: Core ML scores each row independently, so the batch size cannot
    change a value.
    """
    model = ct.models.MLModel(str(mlpackage_path))
    name = _output_name(model)
    chunks: list[np.ndarray] = []
    for start in range(0, windows.shape[0], PREDICT_BATCH):
        block = windows[start : start + PREDICT_BATCH]
        payload = [{INPUT_FEATURE_NAME: row[None, ...]} for row in block]
        outputs = model.predict(payload)
        chunks.append(np.stack([np.asarray(o[name]).reshape(-1) for o in outputs]))
    return np.concatenate(chunks, axis=0).astype(np.float64)


def _poisson_nll_delta(leg: dict[str, object], num_channels: int, seq_len: int) -> dict[str, float]:
    """fp16-vs-4-bit Poisson-NLL delta on one fixed seeded window (D-16 leg 1).

    Identical construction to `test_palettization_loss_delta.py`: the same seed, the same
    `exp(lograte) - counts * lograte` per-element mean, and the same single window through both
    packages, so any difference is the 4-bit quantization and nothing else.
    """
    rng = np.random.default_rng(NLL_SEED)
    spikes = rng.random((1, num_channels, 1, seq_len), dtype=np.float32).astype(np.float16)
    counts = rng.poisson(lam=0.3, size=spikes.shape).astype(np.float64)

    def nll(path: Path) -> float:
        model = ct.models.MLModel(str(path))
        lograte = np.asarray(
            model.predict({INPUT_FEATURE_NAME: spikes})[_output_name(model)], dtype=np.float64
        )
        return float((np.exp(lograte) - counts * lograte).mean())

    nll_fp16 = nll(leg["fp16_path"])
    nll_4bit = nll(leg["palettized_path"])
    delta = abs(nll_4bit - nll_fp16)
    _log(f"  Poisson NLL fp16={nll_fp16:.6f}  4bit={nll_4bit:.6f}  delta={delta:.6f}")
    return {"nll_fp16": nll_fp16, "nll_4bit": nll_4bit, "nll_delta": delta}


#: Train-split rows sampled to estimate the 4-bit constant offset for the bias-corrected
#: DIAGNOSTIC. Taken from the END of the train split, contiguous, and never from the test tail, so
#: the diagnostic reads no held-out information.
OFFSET_ROWS: int = 4096


def _session_heldout(
    session: object, seq_len: int
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """One session's held-out windows and labels, its TRAIN labels, and a tail of TRAIN windows.

    The geometry is Plan 09-07's, restated through the same functions rather than re-derived: the
    split point comes from `chronological_split`, held-out window rows begin at the split bin so
    the first held-out window ENDS a full window after it, and `apply_lag` does the pairing.
    """
    binned = np.asarray(session.binned, dtype=np.float32)
    vel_250 = planar_velocity_250hz(session.planar_cm, session.t)
    vel = bin_velocity(
        vel_250, session.t, t_start=session.t_start, t_end=session.t_end, bin_ms=BIN_MS
    )
    if vel.shape[0] != binned.shape[0]:
        raise ValueError(
            f"session {session.session_id}: {vel.shape[0]} velocity bins against "
            f"{binned.shape[0]} spike bins; the two binning paths have diverged"
        )
    split_bin = int(chronological_split(binned, test_frac=TEST_FRAC)[0].shape[0])
    offset = seq_len - 1
    windows = np.lib.stride_tricks.sliding_window_view(binned, seq_len, axis=0)  # (n, C, S)
    test_windows = np.ascontiguousarray(windows[split_bin:])[:, :, None, :]  # (n, C, 1, S)
    test_vel = vel[split_bin + offset :]
    train_vel = vel[offset:split_bin]

    rows = min(test_windows.shape[0], test_vel.shape[0])
    _, test_vel_lagged = apply_lag(test_windows[:rows].reshape(rows, -1), test_vel[:rows], LAG_BINS)
    test_windows = test_windows[: rows - LAG_BINS]
    _, train_vel_lagged = apply_lag(np.zeros((train_vel.shape[0], 1)), train_vel, LAG_BINS)

    # The tail of the TRAIN window block, for the bias-corrected diagnostic. Train rows are window
    # indices 0 .. split_bin, so this stops short of the split and reads no held-out bin.
    train_windows = np.ascontiguousarray(
        windows[max(0, split_bin - OFFSET_ROWS) : split_bin]
    )[:, :, None, :]
    return (
        test_windows.astype(np.float16),
        test_vel_lagged,
        train_vel_lagged,
        train_windows.astype(np.float16),
    )


def _r2_leg(leg: dict[str, object], data_dir: Path, seq_len: int, smoke: bool) -> dict[str, object]:
    """Held-out velocity R2 through the fp16 and 4-bit packages (D-16 leg 2)."""
    sessions, excluded = available_sessions(data_dir)
    for exclusion in excluded:
        _log(f"  excluded {exclusion.session_id}: {exclusion.reason}")
    if not sessions:
        raise SystemExit(f"error: no loadable sessions under {data_dir}")

    windows_all, test_all, train_all, offset_all, ids = [], [], [], [], []
    for session in sessions:
        windows, test_vel, train_vel, train_windows = _session_heldout(session, seq_len)
        if smoke:
            windows, test_vel = windows[:SMOKE_ROWS], test_vel[:SMOKE_ROWS]
            train_windows = train_windows[:SMOKE_ROWS]
        windows_all.append(windows)
        test_all.append(test_vel)
        train_all.append(train_vel)
        offset_all.append(train_windows)
        ids.append(session.session_id)
        _log(f"  {session.session_id}: {windows.shape[0]} held-out windows")

    windows = np.concatenate(windows_all, axis=0)
    test_vel = np.concatenate(test_all, axis=0)
    train_windows = np.concatenate(offset_all, axis=0)
    null = np.concatenate(train_all, axis=0).mean(axis=0)

    scored: dict[str, object] = {}
    predictions: dict[str, np.ndarray] = {}
    for label, key in (("fp16_path", "fp16"), ("palettized_path", "4bit")):
        started = time.monotonic()
        predictions[key] = _predict(leg[label], windows)
        record = heldout_r2(test_vel, predictions[key], null)
        scored[f"r2_{key}"] = record["pooled"]
        scored[f"r2_{key}_axes"] = {"vx": record["vx"], "vy": record["vy"]}
        _log(
            f"  R2 {key}: pooled={record['pooled']:.6f} vx={record['vx']:.6f} "
            f"vy={record['vy']:.6f} over {record['n']} rows in {time.monotonic() - started:.1f} s"
        )
    scored["r2_delta"] = scored["r2_4bit"] - scored["r2_fp16"]
    scored["n"] = int(test_vel.shape[0])
    scored["sessions"] = ids
    scored["lag_bins"] = LAG_BINS
    scored["null"] = "the POOLED TRAIN-split mean velocity per axis (the Plan 09-07 null)"
    scored["diagnostic_bias_corrected"] = _bias_corrected_diagnostic(
        leg, train_windows, predictions["4bit"], test_vel, null
    )
    return scored


def _bias_corrected_diagnostic(
    leg: dict[str, object],
    train_windows: np.ndarray,
    predicted_4bit: np.ndarray,
    test_vel: np.ndarray,
    null: np.ndarray,
) -> dict[str, object]:
    """Does 4-bit palettization DESTROY the velocity signal, or merely OFFSET it?

    A DIAGNOSTIC, excluded from the headline delta by construction and reported separately. The
    constant offset between the 4-bit and fp16 predictions is estimated on TRAIN rows ONLY and
    then subtracted from the held-out 4-bit predictions, so no held-out information reaches it.
    This is not a fix and is not proposed as one: it answers whether the information survives
    quantization, which is what determines whether the remedy is a refit or a redesign.
    """
    offset = (
        _predict(leg["palettized_path"], train_windows)
        - _predict(leg["fp16_path"], train_windows)
    ).mean(axis=0)
    record = heldout_r2(test_vel, predicted_4bit - offset, null)
    _log(
        f"  [diagnostic] train-estimated 4-bit offset = {np.round(offset, 4).tolist()} cm/s; "
        f"bias-corrected R2 = {record['pooled']:.6f}"
    )
    return {
        "r2_4bit_bias_corrected": record["pooled"],
        "axes": {"vx": record["vx"], "vy": record["vy"]},
        "offset_cm_s": offset.tolist(),
        "offset_rows": int(train_windows.shape[0]),
        "status": "DIAGNOSTIC, estimated on train rows only; NOT the reported r2_4bit",
    }


def _threshold_census(model: torch.nn.Module, palettized_path: Path) -> dict[str, object]:
    """Which weight tensors cleared `weight_threshold`, and the readout's disclosure.

    Reported from two independent directions so the claim is measured rather than reasoned: the
    torch parameter census says which tensors are large enough to be eligible, and the MIL program
    of the saved 4-bit package says how many were actually replaced by a lookup table.
    """
    census = [
        {"name": name, "elements": int(tensor.numel()), "shape": list(tensor.shape)}
        for name, tensor in model.named_parameters()
    ]
    over = [row for row in census if row["elements"] >= WEIGHT_THRESHOLD]
    under = [row for row in census if row["elements"] < WEIGHT_THRESHOLD]

    spec = ct.models.MLModel(str(palettized_path)).get_spec()
    function = spec.mlProgram.functions["main"]
    operations = function.block_specializations[function.opset].operations
    lut_ops = sum(1 for op in operations if op.type == "constexpr_lut_to_dense")

    head = [
        row
        for row in census
        if "velocity_head" in row["name"] and row["name"].endswith("weight")
    ]
    head_elements = head[0]["elements"] if head else None
    if head and head_elements >= WEIGHT_THRESHOLD:
        raise RuntimeError(
            f"the velocity readout has {head_elements} elements, at or above the "
            f"{WEIGHT_THRESHOLD} threshold; the evidence's claim that the shipped model's R2 delta "
            f"is entirely encoder-attributable would no longer hold"
        )
    _log(
        f"  {len(over)} of {len(census)} parameter tensors clear the {WEIGHT_THRESHOLD}-element "
        f"threshold; the package carries {lut_ops} palettized tensors"
    )
    return {
        "tensors_total": len(census),
        "tensors_over_threshold": len(over),
        "tensors_under_threshold": len(under),
        "palettized_tensors_in_package": lut_ops,
        "velocity_head_weight_elements": head_elements,
        "velocity_head_palettized": False,
        "largest_skipped_elements": max((row["elements"] for row in under), default=0),
        "smallest_palettized_elements": min((row["elements"] for row in over), default=0),
    }


def _ane_leg(palettized_path: Path, provenance: str) -> dict[str, object]:
    """ANE op-ELIGIBILITY of the compiled 4-bit shipped model, recorded AS MEASURED (RD-06a)."""
    scan = scan_ane_eligibility(_fresh_compile(palettized_path))
    tally = dict(Counter(record["op_type"] for record in scan["records"]))
    _log(
        f"  ANE: {scan['n_schedulable']} schedulable ops, all_eligible={scan['all_eligible']}, "
        f"CPU-only={len(scan['cpu_only_ops'])}"
    )
    return {
        "model": "NDT1ANEWithVelocity (real-data, 4-bit)",
        "n_schedulable": int(scan["n_schedulable"]),
        "all_eligible": bool(scan["all_eligible"]),
        "cpu_only_ops": len(scan["cpu_only_ops"]),
        "preferred_tally": scan["preferred_tally"],
        "op_type_tally": dict(sorted(tally.items())),
        "provenance": provenance,
        "tool": "MLComputePlan via ndt1.compute_plan, scoped to CPU_AND_NE",
        "claim": (
            "ELIGIBILITY (neuralEngine in supported_compute_devices) only. PLACEMENT "
            "(preferred == neuralEngine) is NOT asserted: at 1.29M params Core ML CPU-places on "
            "Mac, which is why preferred_tally is informational."
        ),
        "phase5_baseline": PHASE5_ANE_BASELINE,
    }


def _determinism(
    model: torch.nn.Module, leg: dict[str, object], out_dir: Path, num_channels: int, seq_len: int
) -> dict[str, object]:
    """Palettize the SAME fp16 package a second time and compare, rather than assume (T-04-04-03).

    k-means palettization is stochastic in general. `num_kmeans_workers=1` removes multi-process
    nondeterminism but not algorithmic nondeterminism, and this model's 4,096-element positional
    encoding takes scikit-learn's KMeans rather than coremltools' kmeans1d, so the question is
    worth answering with a measurement instead of a citation.
    """
    del model
    second = out_dir / "ndt1_real_repeat_4bit.mlpackage"
    palettize_4bit(leg["fp16_path"], second)
    repeat = {"fp16_path": leg["fp16_path"], "palettized_path": second}
    first_delta = _poisson_nll_delta(leg, num_channels, seq_len)["nll_delta"]
    second_delta = _poisson_nll_delta(repeat, num_channels, seq_len)["nll_delta"]
    same_bytes = package_size_bytes(second) == leg["palettized_bytes"]
    identical = first_delta == second_delta and same_bytes
    verdict = (
        "identical across two runs"
        if identical
        else f"differs across two runs by {abs(second_delta - first_delta):.3e} nats/element"
    )
    _log(f"  determinism: {verdict}")
    return {
        "verdict": verdict,
        "run1_nll_delta": first_delta,
        "run2_nll_delta": second_delta,
        "package_bytes_identical": same_bytes,
        "note": (
            "Two palettize_4bit calls on the same fp16 package, compared by package size and by "
            "the Poisson-NLL delta each produces on the same fixed window."
        ),
    }


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--metrics", type=Path, default=_DEFAULT_METRICS)
    parser.add_argument("--out-dir", type=Path, default=_DEFAULT_OUT_DIR)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--seq-len", type=int, default=SEQ_LEN)
    parser.add_argument(
        "--smoke",
        action="store_true",
        help="wiring check on a few held-out rows; writes to a scratch metrics file, never the "
        "published one",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Re-measure the palettization, ANE and threshold facts on the real-data checkpoints."""
    args = _parse_args(argv)
    torch.manual_seed(0)
    started = time.time()

    for path in (REAL_ENCODER_CHECKPOINT, REAL_VELOCITY_CHECKPOINT):
        if not path.is_file():
            print(f"error: no real-data checkpoint at {path}", file=sys.stderr)
            return 1
    args.out_dir.mkdir(parents=True, exist_ok=True)

    _log("reconstruction model (D-16 leg 1: Poisson NLL)")
    encoder = NDT1ANE(seq_len=args.seq_len)
    encoder_provenance = _require_real(encoder, "NDT1ANE")
    recon = _convert_and_palettize(encoder, args.out_dir, "ndt1_real", args.seq_len)
    recon_nll = _poisson_nll_delta(recon, encoder.num_channels, args.seq_len)

    _log("shipped with-velocity model (D-16 leg 2: held-out R2)")
    shipped = NDT1ANEWithVelocity(seq_len=args.seq_len)
    shipped_provenance = _require_real(shipped, "NDT1ANEWithVelocity")
    vel = _convert_and_palettize(shipped, args.out_dir, "ndt1_real_vel", args.seq_len)
    vel_r2 = _r2_leg(vel, args.data_dir, args.seq_len, args.smoke)

    _log("weight_threshold census")
    census = _threshold_census(shipped, vel["palettized_path"])

    _log("ANE op eligibility (RD-06a)")
    ane = _ane_leg(vel["palettized_path"], shipped_provenance)

    _log("palettization determinism")
    determinism = _determinism(encoder, recon, args.out_dir, encoder.num_channels, args.seq_len)

    palettization = {
        "nbits": PALETTIZE_NBITS,
        "mode": "kmeans",
        "granularity": "per_tensor",
        "weight_threshold": WEIGHT_THRESHOLD,
        "velocity_head_palettized": False,
        "velocity_head_elements": VELOCITY_HEAD_ELEMENTS,
        "velocity_head_note": (
            "weight_threshold=2048 skips any weight tensor with fewer elements. The velocity "
            "readout is a 1x1 Conv2d(96 -> 2), i.e. 2 x 96 = 192 elements, so it is never "
            "quantized and the shipped model's R2 delta is entirely encoder-attributable."
        ),
        "reconstruction_model": {
            "model": "NDT1ANE (real-data pooled)",
            "checkpoint": REAL_ENCODER_CHECKPOINT.name,
            "sha256": checkpoint_sha256(REAL_ENCODER_CHECKPOINT),
            "provenance": encoder_provenance,
            "fp16_bytes": recon["fp16_bytes"],
            "palettized_bytes": recon["palettized_bytes"],
            "size_ratio": recon["size_ratio"],
            **recon_nll,
        },
        "shipped_model": {
            "model": "NDT1ANEWithVelocity (real-data)",
            "checkpoint": REAL_VELOCITY_CHECKPOINT.name,
            "sha256": checkpoint_sha256(REAL_VELOCITY_CHECKPOINT),
            "provenance": shipped_provenance,
            "fp16_bytes": vel["fp16_bytes"],
            "palettized_bytes": vel["palettized_bytes"],
            "size_ratio": vel["size_ratio"],
            **vel_r2,
        },
        "threshold_census": census,
        "determinism": determinism["verdict"],
        "determinism_detail": determinism,
        "phase4_synthetic_baseline": {
            "size_ratio": PHASE4_SIZE_RATIO,
            "nll_delta": PHASE4_NLL_DELTA,
            "note": "04-palettization-evidence.md, measured on a randomly-initialized NDT1ANE",
        },
        "env": _environment(),
        "smoke": bool(args.smoke),
    }

    metrics_path = (
        args.out_dir / "coreml-smoke-metrics.json" if args.smoke else Path(args.metrics)
    )
    metrics = json.loads(metrics_path.read_text(encoding="utf-8")) if metrics_path.is_file() else {}
    metrics["palettization"] = palettization
    metrics["ane"] = {**ane, "env": _environment(), "smoke": bool(args.smoke)}
    metrics_path.write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    _log(f"wrote palettization + ane sections to {metrics_path} in {time.time() - started:.1f} s")
    _log("latency is NOT written here: run CortexDecoderBench and transcribe its device-annotated")
    _log("number into the `latency` section, marked corroborating rather than canonical.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
