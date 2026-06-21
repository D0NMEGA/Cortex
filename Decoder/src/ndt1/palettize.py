"""DEC-05 — 4-bit (k-means) weight palettization of the converted NDT1 ``.mlpackage``.

Step two of the Phase-4 deliverable pipeline (04-RESEARCH.md DEC-05). Palettization is a
Core ML-side op that operates on an ALREADY-CONVERTED ``mlprogram`` ``MLModel`` (Pitfall #4 /
Finding §0.2) — so this module consumes the package produced by :mod:`ndt1.convert` (DEC-03
is a hard prerequisite for DEC-05). It clusters each weight tensor into a ``2**nbits``-entry
lookup table; ``nbits=4`` -> a 16-centroid LUT, which substantially shrinks the stored weights.

This runs as an OFFLINE build step on the dev-Mac (k-means can be slow / multi-process). It
does NOT target the Neural Engine, profile the chip, or assert on-chip placement — that work
is Phase 5 (DEC-06..12). The produced 4-bit package + the fp16 checkpoint are the Phase-5
hand-off artifacts.
"""
from __future__ import annotations

from pathlib import Path

import coremltools as ct
import coremltools.optimize as cto

#: Palettization bit width (SC4): 4 bits -> 2**4 == 16-centroid lookup table per weight tensor.
PALETTIZE_NBITS = 4


def palettize_4bit(mlpackage_path: Path, out_path: Path) -> Path:
    """Palettize an ``mlprogram`` ``.mlpackage`` to a 4-bit k-means LUT package.

    Args:
        mlpackage_path: the fp16 ``mlprogram`` ``.mlpackage`` from
            :func:`ndt1.convert.convert_to_mlpackage`.
        out_path: directory bundle path to save the palettized ``.mlpackage`` to (gitignored).

    Returns:
        ``out_path`` — the saved 4-bit ``.mlpackage`` bundle directory.

    Raises:
        OSError: if ``mlpackage_path`` cannot be loaded from disk.
        RuntimeError: if palettization fails (re-raised with context).
        ValueError: if the optimization config is rejected.
    """
    mlpackage_path = Path(mlpackage_path)
    try:
        model = ct.models.MLModel(str(mlpackage_path))
    except OSError as exc:  # explicit — never a bare/blind except
        raise OSError(f"could not load .mlpackage at {mlpackage_path}: {exc}") from exc

    try:
        # global_config applies one OpPalettizerConfig to every palettizable weight op.
        # mode="kmeans" (default) clusters weights; granularity defaults to "per_tensor"
        # (matches SC4 verbatim — one LUT per tensor, the simplest grouping).
        config = cto.coreml.OptimizationConfig(
            global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=PALETTIZE_NBITS)
        )
        compressed = cto.coreml.palettize_weights(model, config)
    except (RuntimeError, ValueError) as exc:  # explicit — never a bare/blind except
        raise RuntimeError(
            f"4-bit k-means palettization failed for {mlpackage_path}: {exc}"
        ) from exc

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    compressed.save(str(out_path))
    return out_path


def package_size_bytes(mlpackage_path: Path) -> int:
    """Total on-disk size (sum of all file byte-sizes) of a ``.mlpackage`` directory tree.

    A ``.mlpackage`` is a directory bundle; its real footprint is the sum of every file inside
    it (the weight blob dominates). Used to characterize the fp16 -> 4-bit size reduction.
    """
    mlpackage_path = Path(mlpackage_path)
    return sum(p.stat().st_size for p in mlpackage_path.rglob("*") if p.is_file())
