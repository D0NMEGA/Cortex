"""DEC-06 — programmatic ANE op-ELIGIBILITY scan of the compiled NDT1 ``(vx,vy)`` model.

Phase-5 Decision 2 / 05-RESEARCH TL;DR #1: ANE residency is CI-assertable on the dev Mac via
coremltools' :class:`~coremltools.models.compute_plan.MLComputePlan`, which exposes the
per-operation compute-device usage of a *compiled* Core ML model. This module loads that plan
for the 4-bit palettized ``(vx,vy)`` deployment artifact and verifies that the Neural Engine is
in **every** schedulable op's ``supported_compute_devices`` (i.e. every op *can* run on the ANE),
with **zero** ops pinned CPU-only.

**The eligibility / placement split (load-bearing — do NOT conflate):**

* **ELIGIBILITY** — ``neuralEngine ∈ op.supported_compute_devices``. A *compiler* property: it is
  device-independent and the real regression we guard (e.g. an einsum lowering that needs GPU/CPU).
  This module proves ELIGIBILITY and is the DEC-06 Mac CI gate.
* **PLACEMENT** — ``op.preferred_compute_device == neuralEngine`` (100% runtime residency). This is
  scheduler-, scale-, and chip-dependent. At Cortex NDT1's ~1.29M params the M-series *Mac*
  scheduler may legitimately pick CPU as ``preferred`` (the meridian scale trap, Decision 2).
  PLACEMENT (DEC-08) is therefore the **iPad-M4 HUMAN-UAT artifact** (Plan 05) — NOT asserted here.

Consequently this module **tallies** the Mac ``preferred`` device only as INFORMATIONAL output —
the preferred-device tally is never a pass/fail input. ``MLComputePlan.load_from_path`` needs a
compiled
``.mlmodelc`` (Risk #4), so :func:`compiled_model_path` compiles the ``.mlpackage`` first via
``MLModel.get_compiled_path()``. Residency is characterized on the **4-bit palettized** package
(the shipping artifact, Risk #5). Per the no-bare/blind-except discipline (ruff ``BLE``), only the
explicit ``(OSError, RuntimeError, ValueError)`` set is caught around compile/load.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

import coremltools as ct

#: The production compute set scanned for eligibility (DEC-07 — CPU + Neural Engine, not ``.all``).
DEFAULT_COMPUTE_UNITS = ct.ComputeUnit.CPU_AND_NE

#: Short device-class -> tag map used for the per-op ``supported``/``preferred`` records.
_DEVICE_TAGS: dict[type, str] = {
    ct.models.compute_device.MLNeuralEngineComputeDevice: "NE",
    ct.models.compute_device.MLCPUComputeDevice: "CPU",
    ct.models.compute_device.MLGPUComputeDevice: "GPU",
}


def _device_tag(device: object) -> str:
    """Map an ``MLComputeDevice`` instance to a short tag (``"NE"`` / ``"CPU"`` / ``"GPU"``)."""
    for device_cls, tag in _DEVICE_TAGS.items():
        if isinstance(device, device_cls):
            return tag
    return type(device).__name__  # unknown device class — surface its class name verbatim


def _is_ane(device: object) -> bool:
    """True iff ``device`` is the Neural Engine compute device."""
    return isinstance(device, ct.models.compute_device.MLNeuralEngineComputeDevice)


def compiled_model_path(mlpackage_path: Path) -> Path:
    """Compile an ``.mlpackage`` and return its persistent ``.mlmodelc`` directory path.

    ``MLComputePlan.load_from_path`` operates on a COMPILED model, not a raw ``.mlpackage``
    (05-RESEARCH Risk #4). The coremltools 9.0 path that produces a *persistent* ``.mlmodelc`` is
    :func:`coremltools.models.utils.compile_model` (it writes the compiled dir to disk and returns
    its path). We deliberately do NOT use ``MLModel(...).get_compiled_path`` /
    ``get_compiled_model_path`` here: that path is documented to live only for the lifetime of the
    transient ``MLModel`` Python object, so it can be reclaimed before the compute-plan scan reads
    it. ``compile_model`` writes a stable ``.mlmodelc`` next to the package (gitignored).

    Args:
        mlpackage_path: the ``.mlpackage`` bundle to compile (e.g. the 4-bit palettized artifact).

    Returns:
        The path to the compiled ``.mlmodelc`` directory.

    Raises:
        OSError: if the ``.mlpackage`` cannot be read from disk.
        RuntimeError: if compilation fails (re-raised with context).
        ValueError: if the package is rejected by the compiler.
    """
    mlpackage_path = Path(mlpackage_path)
    destination = mlpackage_path.with_suffix(".mlmodelc")
    try:
        compiled = ct.models.utils.compile_model(
            str(mlpackage_path), destination_path=str(destination)
        )
        return Path(compiled)
    except (OSError, RuntimeError, ValueError) as exc:  # explicit — never a bare/blind except
        raise RuntimeError(
            f"could not compile .mlpackage at {mlpackage_path} for MLComputePlan: {exc}"
        ) from exc


def scan_ane_eligibility(
    compiled_mlmodelc_path: Path, compute_units: ct.ComputeUnit | None = None
) -> dict:
    """Scan every schedulable op of a compiled model for Neural-Engine ELIGIBILITY.

    Loads the compiled model's :class:`~coremltools.models.compute_plan.MLComputePlan` scoped to
    ``compute_units`` (default :data:`DEFAULT_COMPUTE_UNITS` == ``CPU_AND_NE``), walks the ``main``
    function's operations, and records each *schedulable* op's ANE eligibility, its supported and
    preferred compute devices, and its estimated cost. Ops whose device usage is ``None`` (consts
    and other non-schedulable nodes) are EXCLUDED from the eligibility denominator.

    The verdict asserts ELIGIBILITY only: ``all_eligible`` is True iff every schedulable op has
    the Neural Engine in ``supported_compute_devices``; ``cpu_only_ops`` lists any op pinned
    CPU-only (the DEC-06 regression). ``preferred_tally`` is the Mac ``preferred``-device
    histogram — INFORMATIONAL, never a pass/fail input (the scale trap, Decision 2).

    Args:
        compiled_mlmodelc_path: path to a COMPILED ``.mlmodelc`` directory (see
            :func:`compiled_model_path`).
        compute_units: the compute set to scope the plan to; defaults to ``CPU_AND_NE``.

    Returns:
        A dict with keys:

        * ``records``: list of per-op dicts ``{op_type, ane_eligible, supported, preferred, cost}``.
        * ``all_eligible``: bool — every schedulable op is ANE-eligible.
        * ``cpu_only_ops``: list of records whose ``supported == ["CPU"]`` (the regression).
        * ``preferred_tally``: dict[str, int] — Mac preferred-device histogram (INFORMATIONAL).
        * ``n_schedulable``: int — number of schedulable ops (the eligibility denominator).

    Raises:
        ValueError: if the model is not an ``mlprogram`` (no ``model_structure.program``).
        RuntimeError: if the compute plan cannot be loaded (re-raised with context).
    """
    if compute_units is None:
        compute_units = DEFAULT_COMPUTE_UNITS

    try:
        plan = ct.models.compute_plan.MLComputePlan.load_from_path(
            path=str(compiled_mlmodelc_path),
            compute_units=compute_units,
        )
    except (OSError, RuntimeError, ValueError) as exc:  # explicit — never a bare/blind except
        raise RuntimeError(
            f"could not load MLComputePlan from {compiled_mlmodelc_path}: {exc}"
        ) from exc

    program = plan.model_structure.program
    if program is None:
        raise ValueError(
            f"expected an mlprogram model structure at {compiled_mlmodelc_path}; got None"
        )

    records: list[dict] = []
    for op in program.functions["main"].block.operations:
        usage = plan.get_compute_device_usage_for_mlprogram_operation(op)
        if usage is None:
            continue  # non-schedulable op (const, etc.) — excluded from the eligibility denominator
        cost = plan.get_estimated_cost_for_mlprogram_operation(op)
        supported = [_device_tag(d) for d in usage.supported_compute_devices]
        records.append(
            {
                "op_type": op.operator_name,
                "ane_eligible": any(_is_ane(d) for d in usage.supported_compute_devices),
                "supported": supported,
                "preferred": _device_tag(usage.preferred_compute_device),
                "cost": float(cost.weight) if cost is not None else None,
            }
        )

    all_eligible = all(r["ane_eligible"] for r in records)
    cpu_only_ops = [r for r in records if r["supported"] == ["CPU"]]
    preferred_tally = dict(Counter(r["preferred"] for r in records))
    return {
        "records": records,
        "all_eligible": all_eligible,
        "cpu_only_ops": cpu_only_ops,
        "preferred_tally": preferred_tally,
        "n_schedulable": len(records),
    }


def write_residency_artifacts(scan: dict, out_dir: Path) -> tuple[Path, Path]:
    """Emit the meridian-convention residency artifacts for a scan (gitignored).

    Writes two files into ``out_dir`` (created if missing):

    * ``runtime_plan.json`` — the full ``records`` list plus the verdict
      (``all_eligible``, ``cpu_only_ops``, ``preferred_tally``, ``n_schedulable``).
    * ``residency.txt`` — a human-readable per-op table followed by a one-line summary.

    Args:
        scan: the dict returned by :func:`scan_ane_eligibility`.
        out_dir: directory to write the artifacts into (e.g. ``Decoder/checkpoints/``, gitignored).

    Returns:
        ``(runtime_plan_json_path, residency_txt_path)``.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / "runtime_plan.json"
    txt_path = out_dir / "residency.txt"

    json_path.write_text(json.dumps(scan, indent=2))

    n = scan["n_schedulable"]
    eligible = sum(1 for r in scan["records"] if r["ane_eligible"])
    lines = [
        f"{'op_type':<24} {'eligible':<9} {'supported':<18} {'preferred':<10} cost",
        "-" * 72,
    ]
    for record in scan["records"]:
        cost = "n/a" if record["cost"] is None else f"{record['cost']:.6g}"
        lines.append(
            f"{record['op_type']:<24} {str(record['ane_eligible']):<9} "
            f"{','.join(record['supported']):<18} {record['preferred']:<10} {cost}"
        )
    lines.append("-" * 72)
    lines.append(
        f"ANE-eligible: {eligible}/{n} ops; CPU-only: {len(scan['cpu_only_ops'])}; "
        f"preferred tally (Mac, INFORMATIONAL): {scan['preferred_tally']}"
    )
    txt_path.write_text("\n".join(lines) + "\n")
    return json_path, txt_path
