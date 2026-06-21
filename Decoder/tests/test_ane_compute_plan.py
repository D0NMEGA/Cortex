"""DEC-06 — the slow Mac gate: every op of the compiled 4-bit ``(vx,vy)`` model is ANE-ELIGIBLE.

Phase-5 Decision 2 + 05-RESEARCH TL;DR #1: this is the deterministic, CI-run residency proof.
The slow tests build the ``(vx,vy)`` ``.mlpackage`` (``NDT1ANEWithVelocity`` ->
``convert_to_mlpackage``), palettize it to 4-bit (the shipping artifact, Risk #5), compile it to a
``.mlmodelc`` (Risk #4), and scan the compute plan via
:func:`ndt1.compute_plan.scan_ane_eligibility`. The gate asserts **ELIGIBILITY**
(``neuralEngine ∈ supported`` for every schedulable op, zero CPU-only ops) — NOT **PLACEMENT**
(``preferred == neuralEngine``), which is the iPad-M4 HUMAN-UAT artifact (DEC-08/Plan 05) and would
false-fail on the ~1.29M-param model on Mac (the meridian scale trap, Decision 2).

The einsum-disposition test is the arbiter for the einsum-attention risk (Decision 6): coremltools
lowers ``bchq,bkhc->bkhq`` to MIL ops; if any einsum-derived op is CPU-only the test fails and
points to the Task-3 contingency rewrite. Transient packages build under ``Decoder/checkpoints/``
(gitignored), isolated by ``tmp_path.name``; only the verdict NUMBERS are committed (evidence doc).
"""
from __future__ import annotations

from pathlib import Path

import pytest

from ndt1.attention import ANE_ATTENTION_EINSUM
from ndt1.compute_plan import (
    compiled_model_path,
    scan_ane_eligibility,
    write_residency_artifacts,
)
from ndt1.convert import convert_to_mlpackage
from ndt1.model_ane import NDT1ANEWithVelocity
from ndt1.palettize import palettize_4bit

SEQ_LEN = 32  # matches conftest SEQ_LEN; small window keeps the trace fast.

#: Base op names an einsum scaled-dot-product lowers to (coremltools maps ``einsum`` ->
#: matmul/transpose/reduce). A CPU-only op among these is the Decision-6 fallback trigger.
#: coremltools 9.0 prefixes op types with their opset (e.g. ``ios16.einsum``, ``ios18.transpose``),
#: so :func:`_is_einsum_derived` matches on the LAST dotted segment, not the full string.
EINSUM_DERIVED_OPS = {
    "einsum",
    "matmul",
    "batch_matmul",
    "reduce_sum",
    "reduce_mean",
    "transpose",
}


def _is_einsum_derived(op_type: str) -> bool:
    """True iff ``op_type`` is an einsum-lowering op, robust to the ``ios16.``/``ios18.`` prefix."""
    return op_type.rsplit(".", 1)[-1] in EINSUM_DERIVED_OPS


def _checkpoints_dir() -> Path:
    """The gitignored ``Decoder/checkpoints/`` build directory (created if missing)."""
    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    return ckpt_dir


def _build_and_scan_palettized(tag: str) -> dict:
    """Build the (vx,vy) package, palettize to 4-bit, compile, and scan its compute plan.

    Returns the :func:`scan_ane_eligibility` verdict dict for the COMPILED 4-bit palettized model.
    """
    ckpt_dir = _checkpoints_dir()
    fp16_path = ckpt_dir / f"ndt1_vel_fp16_{tag}.mlpackage"
    palettized_path = ckpt_dir / f"ndt1_vel_4bit_{tag}.mlpackage"

    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    convert_to_mlpackage(model, fp16_path, seq_len=SEQ_LEN)
    palettize_4bit(fp16_path, palettized_path)

    compiled = compiled_model_path(palettized_path)
    return scan_ane_eligibility(compiled)  # default CPU_AND_NE


@pytest.mark.slow
def test_palettized_model_every_op_ane_eligible(tmp_path: Path) -> None:
    """DEC-06 gate: every schedulable op of the compiled 4-bit (vx,vy) model is ANE-eligible.

    Builds the deployment artifact (4-bit palettized), scans its compute plan scoped to
    ``CPU_AND_NE``, asserts ``all_eligible`` with ZERO CPU-only ops, and emits the meridian
    residency artifacts (``runtime_plan.json`` + ``residency.txt``) the evidence doc transcribes.
    The einsum-op device disposition is recorded into ``runtime_plan.json`` either way.
    """
    scan = _build_and_scan_palettized(tmp_path.name)

    # Record the einsum-op disposition INTO the scan before persisting, so runtime_plan.json is
    # evidence of the Decision-6 outcome regardless of pass/fail.
    einsum_ops = [r for r in scan["records"] if _is_einsum_derived(r["op_type"])]
    scan["einsum_derived_ops"] = einsum_ops
    scan["einsum_op_device_tally"] = {
        r["op_type"]: r["supported"] for r in einsum_ops
    }
    write_residency_artifacts(scan, _checkpoints_dir())

    # The einsum lowering MUST be observable — else the disposition guard below is vacuous
    # (coremltools lowers bchq,bkhc->bkhq to einsum/transpose/reduce ops; Decision 6).
    assert einsum_ops, "expected einsum-derived ops in the plan (the disposition would be vacuous)"

    assert scan["n_schedulable"] > 0, "the compiled model must have schedulable ops to scan"
    assert scan["all_eligible"], (
        "non-ANE-eligible ops (DEC-06): "
        f"{[r for r in scan['records'] if not r['ane_eligible']]}"
    )
    assert scan["cpu_only_ops"] == [], (
        f"CPU-only ops (DEC-06 regression): {scan['cpu_only_ops']}"
    )

    # The Mac preferred-device tally is recorded for sanity but NEVER required to be the Neural
    # Engine (the scale trap, Decision 2 — placement is the iPad-M4 artifact, DEC-08/Plan 05).
    assert scan["preferred_tally"], "the preferred-device tally should be non-empty"


@pytest.mark.slow
def test_palettized_op_eligibility_matches_fp16(tmp_path: Path) -> None:
    """Risk #5: palettization does not change the op set/eligibility vs the fp16 package.

    Scans BOTH the 4-bit palettized and the fp16 compiled packages and asserts the SET of
    ANE-eligible op types is identical (4-bit weights are decompressed for the ANE — placement
    must not change). This confirms residency is correctly characterized on the deployment artifact.
    """
    ckpt_dir = _checkpoints_dir()
    fp16_path = ckpt_dir / f"ndt1_vel_fp16_parity_{tmp_path.name}.mlpackage"
    palettized_path = ckpt_dir / f"ndt1_vel_4bit_parity_{tmp_path.name}.mlpackage"

    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    convert_to_mlpackage(model, fp16_path, seq_len=SEQ_LEN)
    palettize_4bit(fp16_path, palettized_path)

    fp16_scan = scan_ane_eligibility(compiled_model_path(fp16_path))
    palettized_scan = scan_ane_eligibility(compiled_model_path(palettized_path))

    fp16_eligible = {r["op_type"] for r in fp16_scan["records"] if r["ane_eligible"]}
    palettized_eligible = {
        r["op_type"] for r in palettized_scan["records"] if r["ane_eligible"]
    }
    assert palettized_eligible == fp16_eligible, (
        "palettization changed the ANE-eligible op set: "
        f"fp16={sorted(fp16_eligible)} 4bit={sorted(palettized_eligible)}"
    )


@pytest.mark.slow
def test_einsum_attention_lowers_to_ane_eligible_ops(tmp_path: Path) -> None:
    """Decision 6 arbiter: the bchq,bkhc->bkhq einsum lowers to ANE-eligible MIL ops.

    Collects every einsum-derived op (matmul/einsum/reduce/transpose) from the compiled 4-bit
    model's compute plan; if ANY is CPU-only, fails with a message pointing to the Task-3 meridian
    rewrite (the contingency). If all are ANE-eligible, the einsum lowering is clean (the expected
    common case) and Task 3 is not triggered.
    """
    scan = _build_and_scan_palettized(f"einsum_{tmp_path.name}")
    cpu_only_einsum = [
        r
        for r in scan["records"]
        if r["op_type"] in EINSUM_DERIVED_OPS and r["supported"] == ["CPU"]
    ]
    if cpu_only_einsum:
        pytest.fail(
            f"einsum attention lowered to CPU-only ops {cpu_only_einsum} — "
            "trigger the Task 3 meridian rewrite (Conv2d + broadcast-mul + reduce_sum)"
        )


def test_ane_attention_einsum_constant_is_the_bchq_string() -> None:
    """Fast: the ANE scaled-dot-product einsum constant is the exact bchq,bkhc->bkhq string.

    The einsum-disposition evidence introspects this constant; pinning it keeps the disposition
    test honest (no conversion needed — this assertion is fast).
    """
    assert ANE_ATTENTION_EINSUM == "bchq,bkhc->bkhq"
