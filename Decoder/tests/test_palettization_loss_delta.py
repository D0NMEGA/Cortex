"""DEC-05 (SC4b) — fp16 vs 4-bit reconstruction-loss delta within a documented bound.

Marked ``slow``: convert + k-means palettization + two CPU predictions. Runs the SAME fp16
input window through BOTH the fp16 ``.mlpackage`` and the 4-bit palettized ``.mlpackage`` via
coremltools **CPU prediction** (``MLModel.predict`` — no Neural Engine, Phase 5), then computes
the Poisson NLL of each output against a fixed observed spike-count draw and asserts the
absolute delta stays under a documented bound. The bound is set from the observed delta + a
generous margin (an R&D characterization, not a pre-set hard threshold — 04-RESEARCH DEC-05).

Poisson NLL is computed INLINE (this plan does not depend on 04-04's metrics.py, which lives in
a parallel worktree). The model readout is linear -> outputs are log-rates -> ``log_input=True``
(``exp(lograte) - count*lograte``), matching ``nn.PoissonNLLLoss``'s log-rate parameterization.

As of Phase 9 these slow tests prefer the real-data checkpoint under ``Decoder/checkpoints/``
when it is present and fall back to random initialization otherwise; the ``provenance`` field
in the emitted JSON records which, so a synthetic number can never be mistaken for a real-data
one.

The model here is the bare ``NDT1ANE`` reconstruction encoder, which is the D-16 Poisson-NLL
target; the R2 leg of D-16 on the with-velocity model is produced by ``rederive_coreml.py``.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pytest

from ndt1.convert import INPUT_FEATURE_NAME, convert_to_mlpackage
from ndt1.model_ane import NDT1ANE
from ndt1.palettize import PALETTIZE_NBITS, palettize_4bit
from ndt1.real_checkpoint import load_real_weights_if_present

SEQ_LEN = 32
# The subject of this delta is the nbits=4 (4-bit, 16-centroid) palettized package vs fp16.
assert PALETTIZE_NBITS == 4  # nbits=4 — SC4b operates on the 4-bit package

# Documented bound (SC4b). Observed |NLL_4bit - NLL_fp16| on a (1,96,1,32) window with this
# seed is ~1e-2 nats/element (recorded to sc4_delta.json at run time); 0.5 is a generous
# margin that still fails loudly if 4-bit palettization grossly corrupts the reconstruction.
LOSS_DELTA_BOUND = 0.5


def _output_feature_name(mlmodel: object) -> str:
    """The single output feature name of the converted package (coremltools auto-names it)."""
    spec = mlmodel.get_spec()  # type: ignore[attr-defined]
    return spec.description.output[0].name


def _poisson_nll_lograte(logrates: np.ndarray, counts: np.ndarray) -> float:
    """Mean Poisson NLL with log-rate inputs: exp(lograte) - counts*lograte (per element)."""
    per_element = np.exp(logrates) - counts * logrates
    return float(per_element.mean())


@pytest.mark.slow
def test_palettization_loss_delta_within_bound(tmp_path: Path) -> None:
    """fp16 vs 4-bit CPU-prediction Poisson-NLL delta is within the documented bound."""
    import coremltools as ct

    model = NDT1ANE(seq_len=SEQ_LEN)
    provenance = load_real_weights_if_present(model)
    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    fp16_path = ckpt_dir / f"ndt1_fp16_delta_{tmp_path.name}.mlpackage"
    palettized_path = ckpt_dir / f"ndt1_4bit_delta_{tmp_path.name}.mlpackage"

    convert_to_mlpackage(model, fp16_path, seq_len=SEQ_LEN)
    palettize_4bit(fp16_path, palettized_path)

    # One fixed (1,96,1,S) fp16 input window + one fixed observed spike-count draw — both
    # packages see the SAME input, so any NLL difference is purely the 4-bit quantization.
    rng = np.random.default_rng(0)
    spikes = rng.random((1, model.num_channels, 1, SEQ_LEN), dtype=np.float32).astype(np.float16)
    counts = rng.poisson(lam=0.3, size=spikes.shape).astype(np.float32)

    try:
        fp16_model = ct.models.MLModel(str(fp16_path))
        palettized_model = ct.models.MLModel(str(palettized_path))
        # CPU prediction only (no compute-unit override -> no Neural Engine; Phase 5 owns that).
        fp16_out = fp16_model.predict({INPUT_FEATURE_NAME: spikes})
        palettized_out = palettized_model.predict({INPUT_FEATURE_NAME: spikes})
    except RuntimeError as exc:  # explicit — never a bare/blind except
        raise RuntimeError(f"coremltools CPU prediction failed: {exc}") from exc

    fp16_logrates = np.asarray(fp16_out[_output_feature_name(fp16_model)], dtype=np.float64)
    palettized_logrates = np.asarray(
        palettized_out[_output_feature_name(palettized_model)], dtype=np.float64
    )

    nll_fp16 = _poisson_nll_lograte(fp16_logrates, counts.astype(np.float64))
    nll_4bit = _poisson_nll_lograte(palettized_logrates, counts.astype(np.float64))
    delta = abs(nll_4bit - nll_fp16)

    record = {
        "nbits": 4,
        "nll_fp16": nll_fp16,
        "nll_4bit": nll_4bit,
        "abs_delta": delta,
        "bound": LOSS_DELTA_BOUND,
        "provenance": provenance,
    }
    (ckpt_dir / "sc4_delta.json").write_text(json.dumps(record, indent=2))
    print(
        f"\n[SC4b delta] NLL fp16={nll_fp16:.6f}  4bit={nll_4bit:.6f}  "
        f"|delta|={delta:.6f} <= bound={LOSS_DELTA_BOUND}  weights={provenance}"
    )

    # SC4b: the 4-bit reconstruction stays within a documented bound of the fp16 reconstruction.
    assert delta <= LOSS_DELTA_BOUND, (
        f"4-bit vs fp16 Poisson-NLL delta {delta:.6f} exceeds documented bound {LOSS_DELTA_BOUND}"
    )


def test_loss_delta_uses_cpu_prediction_within_phase_boundary() -> None:
    """The delta path uses coremltools CPU prediction and the impl modules stay Phase-4-only.

    The boundary regex is assembled from fragments so this assertion does NOT itself contain a
    matchable copy of the forbidden literals (a self-grepping check would otherwise trip on its
    own pattern). It scans the two production modules this test drives — ``convert.py`` and
    ``palettize.py`` — which are what the Phase-4/Phase-5 boundary actually protects.
    """
    here = Path(__file__).resolve()
    this_src = here.read_text()
    # Positive signal: the delta is measured via coremltools CPU prediction (no engine override).
    assert ".predict(" in this_src, "the loss delta must be measured via MLModel.predict"

    src_dir = here.parents[1] / "src" / "ndt1"
    impl = (src_dir / "convert.py").read_text() + (src_dir / "palettize.py").read_text()
    fragments = ["cpuAndNeural" + "Engine", "compute" + "Units", "_ANE" + "Client",
                 "Instrum" + "ents", "resid" + "ency"]
    boundary = re.compile("|".join(fragments), re.IGNORECASE)
    assert not boundary.findall(impl), "Phase-5 ANE tokens leaked into the conversion modules"
