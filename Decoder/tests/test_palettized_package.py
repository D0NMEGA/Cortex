"""DEC-05 (SC4a, part 2) — the fp16 .mlpackage palettizes to a smaller 4-bit k-means package.

Marked ``slow``: convert + k-means palettization is a heavy offline build step, excluded from
the quick ``-m "not slow"`` CI run. DEC-05 runs on the DEC-03 output (correct ordering:
convert -> palettize), CPU-only — NO Neural-Engine targeting (Phase 5). Both packages are
built transiently under ``Decoder/checkpoints/`` (gitignored); only the size ratio is recorded
(to ``sc4_size.json``, also gitignored) and committed numerically in the evidence note.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from ndt1.convert import convert_to_mlpackage
from ndt1.model_ane import NDT1ANE
from ndt1.palettize import PALETTIZE_NBITS, package_size_bytes, palettize_4bit

SEQ_LEN = 32

# Expectation (NOT a hard assert): a 4-bit LUT stores ~4 bits/weight vs fp16's 16, so the
# WEIGHT footprint should fall ~4x. The package also carries fixed metadata, so the whole-
# package ratio is smaller than 4x; we measure the actual ratio rather than hard-asserting 4x.


@pytest.mark.slow
def test_palettized_package_exists_and_is_smaller(tmp_path: Path) -> None:
    """convert (DEC-03) -> palettize (DEC-05): 4-bit package exists and shrinks vs fp16."""
    model = NDT1ANE(seq_len=SEQ_LEN)
    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    fp16_path = ckpt_dir / f"ndt1_fp16_{tmp_path.name}.mlpackage"
    palettized_path = ckpt_dir / f"ndt1_4bit_{tmp_path.name}.mlpackage"

    # DEC-03 must precede DEC-05 (palettization needs an already-converted mlprogram).
    convert_to_mlpackage(model, fp16_path, seq_len=SEQ_LEN)
    palettize_4bit(fp16_path, palettized_path)

    assert palettized_path.exists(), "the 4-bit .mlpackage bundle should exist"
    assert palettized_path.is_dir(), ".mlpackage is a directory bundle"

    fp16_size = package_size_bytes(fp16_path)
    palettized_size = package_size_bytes(palettized_path)
    assert fp16_size > 0 and palettized_size > 0, "both packages must be non-empty"
    # SC4a: the palettized package is measurably smaller than the fp16 package.
    assert palettized_size < fp16_size, (
        f"4-bit package ({palettized_size} B) is not smaller than fp16 ({fp16_size} B)"
    )

    ratio = fp16_size / palettized_size
    record = {
        "nbits": PALETTIZE_NBITS,
        "fp16_bytes": fp16_size,
        "palettized_bytes": palettized_size,
        "size_ratio_fp16_over_4bit": round(ratio, 4),
    }
    (ckpt_dir / "sc4_size.json").write_text(json.dumps(record, indent=2))
    print(f"\n[SC4a size] fp16={fp16_size} B  4bit={palettized_size} B  ratio={ratio:.3f}x")


def test_palettize_source_is_kmeans_4bit_no_ane() -> None:
    """Source uses the SC4 verbatim API (kmeans, nbits=4) and stays inside the phase boundary."""
    src = (Path(__file__).resolve().parents[1] / "src" / "ndt1" / "palettize.py").read_text()
    assert "palettize_weights" in src
    assert "OpPalettizerConfig" in src
    assert "OptimizationConfig" in src
    assert "global_config" in src
    assert 'mode="kmeans"' in src
    assert "nbits=4" in src
    forbidden = re.compile(r"cpuAndNeuralEngine|computeUnits|_ANEClient", re.IGNORECASE)
    assert not forbidden.findall(src), "Phase-5 ANE tokens leaked into palettize.py"
