"""DEC-03 (SC4a, part 1) — the NDT1 encoder->rates graph converts to an mlprogram .mlpackage.

Marked ``slow``: ``torch.jit.trace`` + ``ct.convert`` is a heavy offline build step (seconds),
excluded from the quick ``-m "not slow"`` CI run. Conversion runs on the dev-Mac with DEFAULT
compute units only — there is NO Neural-Engine targeting / residency / Instruments here (that
is Phase 5). The ``.mlpackage`` is built transiently under ``Decoder/checkpoints/`` (gitignored)
and is never committed; only its structure is asserted.
"""
from __future__ import annotations

import re
from pathlib import Path

import coremltools as ct
import pytest

from ndt1.convert import INPUT_FEATURE_NAME, convert_to_mlpackage
from ndt1.model_ane import NDT1ANE

SEQ_LEN = 32  # matches conftest SEQ_LEN; small window keeps the trace fast.


def _package_file_count(pkg: Path) -> int:
    return sum(1 for p in pkg.rglob("*") if p.is_file())


@pytest.mark.slow
def test_convert_produces_loadable_mlprogram_package(tmp_path: Path) -> None:
    """convert_to_mlpackage traces NDT1ANE and writes a non-empty, reloadable .mlpackage."""
    model = NDT1ANE(seq_len=SEQ_LEN)
    # Save under Decoder/checkpoints/ (gitignored) per the plan, isolated by tmp_path name.
    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    out_path = ckpt_dir / f"ndt1_fp16_{tmp_path.name}.mlpackage"

    returned = convert_to_mlpackage(model, out_path, seq_len=SEQ_LEN)

    assert returned == out_path
    assert out_path.exists(), "the .mlpackage bundle directory should exist"
    assert out_path.is_dir(), ".mlpackage is a directory bundle"
    assert _package_file_count(out_path) > 0, "the .mlpackage should be non-empty"

    # It must load back as a Core ML MLModel (round-trips the mlprogram).
    reloaded = ct.models.MLModel(str(out_path))
    spec = reloaded.get_spec()
    input_names = {inp.name for inp in spec.description.input}
    assert INPUT_FEATURE_NAME in input_names, f"expected '{INPUT_FEATURE_NAME}' input feature"


def test_convert_source_targets_cpu_not_ane() -> None:
    """Phase boundary: convert.py must not request the Neural Engine / set compute units."""
    src = (Path(__file__).resolve().parents[1] / "src" / "ndt1" / "convert.py").read_text()
    # Phase-5-only tokens must be ABSENT from the conversion source (case-insensitive).
    forbidden = re.compile(
        r"cpuAndNeuralEngine|computeUnits|compute_units|_ANEClient|Instruments|residency",
        re.IGNORECASE,
    )
    offenders = [tok for tok in forbidden.findall(src)]
    assert not offenders, f"Phase-5 ANE tokens leaked into convert.py: {offenders}"
    # And it must produce the palettizable mlprogram type (DEC-03 precedes DEC-05).
    assert 'convert_to="mlprogram"' in src
