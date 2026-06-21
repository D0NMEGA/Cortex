"""DEC-03 — trace the NDT1 encoder->rates graph and convert it to a Core ML ``.mlpackage``.

Step one of the Phase-4 deliverable pipeline (04-RESEARCH.md DEC-03): take the trained
:class:`~ndt1.model_ane.NDT1ANE` BC1S forward graph (``(B, C, 1, S)`` spikes -> rates),
``torch.jit.trace`` it on a single fp16 example window, and ``ct.convert`` it to an
``mlprogram`` package. The ``mlprogram`` type is the one DEC-05 can palettize (Pitfall #4:
palettization operates on an already-converted package, not a raw ``.pt``).

Phase boundary (04-RESEARCH.md Finding §0.2 + Pitfall #5): conversion runs on the dev-Mac
with the default engine selection only. We deliberately leave the converter's hardware-unit
selector unset and do NOT profile or assert on-chip placement — Apple-Silicon targeting is
Phase 5 (DEC-06..12). This module exists only to produce the package the palettizer consumes.

The example input shape is ``(1, CORTEX_CHANNEL_COUNT, 1, seq_len)`` — the BC1S layout the
model was built for (Plan 04-03), with the sequence axis ``S`` last.
"""
from __future__ import annotations

from pathlib import Path

import coremltools as ct
import numpy as np
import torch

from ndt1.model_ane import NDT1ANE

try:  # Channel-width source-of-truth lives in Plan 04-02's channel_count module.
    from ndt1.channel_count import CORTEX_CHANNEL_COUNT
except ImportError:  # Standalone-worktree fallback; 96 matches conftest + the repo headers.
    # A specific ImportError (not a bare/blind except) so this module imports even before
    # 04-02 merges its channel_count.py. The value 96 matches cortex_shm.h / cortex_ring.h /
    # frame.rs and the conftest CHANNELS constant.
    CORTEX_CHANNEL_COUNT = 96

#: Name of the single model input feature in the converted package (DEC-05 predict keys on it).
INPUT_FEATURE_NAME = "spikes"


def convert_to_mlpackage(model: NDT1ANE, out_path: Path, seq_len: int) -> Path:
    """Trace ``model`` and convert it to an ``mlprogram`` ``.mlpackage`` on CPU.

    Args:
        model: the NDT1 encoder->rates graph to convert (Plan 04-03 ``NDT1ANE``).
        out_path: directory bundle path to save the ``.mlpackage`` to (gitignored).
        seq_len: sequence length ``S`` for the BC1S example input ``(1, C, 1, S)``.

    Returns:
        ``out_path`` — the saved ``.mlpackage`` bundle directory.

    Raises:
        RuntimeError: if ``torch.jit.trace`` or ``ct.convert`` fails (re-raised with context).
        ValueError: if the conversion rejects the example input shape/dtype.
    """
    model.eval()
    # BC1S example: (batch=1, channels=CORTEX_CHANNEL_COUNT, 1, sequence=seq_len), S last.
    example = torch.rand(1, CORTEX_CHANNEL_COUNT, 1, seq_len)
    try:
        with torch.no_grad():
            traced = torch.jit.trace(model, example)
        # NOTE: the converter's hardware-unit kwarg is intentionally omitted — default engine
        # selection only; Apple-Silicon targeting is Phase 5 (DEC-07). The iOS18 (macOS15)
        # deployment floor unlocks the 4-bit grouped palettization features DEC-05 may use.
        mlmodel = ct.convert(
            traced,
            convert_to="mlprogram",
            inputs=[
                ct.TensorType(
                    name=INPUT_FEATURE_NAME,
                    shape=example.shape,
                    dtype=np.float16,
                )
            ],
            minimum_deployment_target=ct.target.iOS18,
        )
    except (RuntimeError, ValueError) as exc:  # explicit — never a bare/blind except
        raise RuntimeError(
            f"NDT1 trace/convert to mlprogram failed for seq_len={seq_len}: {exc}"
        ) from exc

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out_path))
    return out_path
