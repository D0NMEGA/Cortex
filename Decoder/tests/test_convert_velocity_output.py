"""DEC-10 conversion coverage — NDT1ANEWithVelocity -> fp16 (vx,vy) .mlpackage + parity.

Three behaviors (Plan 05-01 Task 2):

1. (fast) ``NDT1ANEWithVelocity(seq_len=S).forward(dummy_bc1s_input)`` returns ``(1, 2, 1, 1)`` —
   the composed encoder->rates->VelocityHead graph emits a single ``(vx, vy)`` per window.
2. (slow) ``convert_to_mlpackage`` on the with-velocity model writes a ``.mlpackage`` whose single
   output feature is fp16 and has 2 elements (read from the reloaded ``ct.models.MLModel`` spec).
3. (slow) parity — the SAME fixed ``(1,96,1,S)`` fp16 window through PyTorch-fp32 (``model.eval()``)
   and the converted CoreML model (CPU predict) agree to within a documented max-abs-delta bound
   (``VELOCITY_PARITY_BOUND``, an R&D characterization like 04-05's ``LOSS_DELTA_BOUND``).

The slow tests build the ``.mlpackage`` transiently under gitignored ``Decoder/checkpoints/`` and
record the parity delta + the velocity R^2 to gitignored ``velocity_parity.json``. The ridge head
is fit on the model's PREDICTED rates over seeded-synthetic windows (no real session .mat needed —
the parity claim is conversion fidelity on a fixed window, Decision 1 fit-on-predicted-rates).
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import torch

from ndt1.convert import INPUT_FEATURE_NAME, convert_to_mlpackage
from ndt1.model_ane import NDT1ANEWithVelocity

SEQ_LEN = 32  # matches conftest SEQ_LEN; small window keeps the trace fast.
CHANNELS = 96
VELOCITY_DIM = 2

# Documented parity bound (R&D characterization). PyTorch-fp32-vs-CoreML-fp16 max-abs-delta on a
# (1,96,1,S) window is dominated by fp16 rounding of a 1x1-conv readout (~1e-3..1e-2); 0.5 is a
# generous margin (mirrors 04-05 LOSS_DELTA_BOUND=0.5) that still fails loudly on a corrupted
# conversion. The OBSERVED delta is recorded to velocity_parity.json at run time.
VELOCITY_PARITY_BOUND = 0.5


def _fit_head_on_predicted_rates(model: NDT1ANEWithVelocity) -> dict:
    """Fit the ridge head on the model's PREDICTED rates over seeded-synthetic windows.

    Returns the R^2 dict from ``model.fit_velocity_head``. Synthetic (vx, vy) labels are a seeded
    linear function of the per-window predicted rates + small noise so the ridge is non-degenerate.
    """
    rng = np.random.default_rng(0)
    n_windows = 64
    windows = torch.rand(n_windows, CHANNELS, 1, SEQ_LEN, dtype=torch.float32)
    model.eval()
    with torch.no_grad():
        rates = model.encoder(windows)  # (N, 96, 1, S) predicted rates
    # Use the last-bin predicted rates (what the head reads) as the design matrix.
    last_bin = rates[..., -1].squeeze(-1).numpy().astype(np.float64)  # (N, 96)
    w_true = rng.standard_normal((CHANNELS, VELOCITY_DIM)) * 0.05
    vel = last_bin @ w_true + 0.01 * rng.standard_normal((n_windows, VELOCITY_DIM))
    return model.fit_velocity_head(last_bin, vel, lam=1.0)


def test_with_velocity_forward_shape(dummy_bc1s_input: torch.Tensor) -> None:
    """NDT1ANEWithVelocity composes encoder->rates->VelocityHead -> (1, 2, 1, 1)."""
    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    out = model(dummy_bc1s_input)
    assert out.shape == (1, VELOCITY_DIM, 1, 1)


@pytest.mark.slow
def test_converted_output_is_fp16_two_vector(tmp_path: Path) -> None:
    """The converted .mlpackage's single output feature is fp16 with exactly 2 elements."""
    import coremltools as ct

    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    _fit_head_on_predicted_rates(model)

    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    out_path = ckpt_dir / f"ndt1_velocity_{tmp_path.name}.mlpackage"

    convert_to_mlpackage(model, out_path, seq_len=SEQ_LEN)

    reloaded = ct.models.MLModel(str(out_path))
    spec = reloaded.get_spec()
    assert len(spec.description.output) == 1, "with-velocity graph has a single output feature"
    out_feature = spec.description.output[0]

    multi_array = out_feature.type.multiArrayType
    # fp16 output dtype (compute_precision=FLOAT16). coremltools enum: FLOAT16 = 65552.
    assert multi_array.dataType == multi_array.FLOAT16, (
        f"output dtype must be FLOAT16, got {multi_array.dataType}"
    )
    # Exactly 2 elements (vx, vy) — shape (1,2,1,1) flattens to 2.
    n_elements = int(np.prod(list(multi_array.shape)))
    assert n_elements == VELOCITY_DIM, (
        f"output must have {VELOCITY_DIM} elements (vx, vy); shape={list(multi_array.shape)}"
    )


@pytest.mark.slow
def test_pytorch_vs_coreml_velocity_parity(tmp_path: Path) -> None:
    """PyTorch-fp32 vs CoreML-fp16 velocity on a FIXED window agree within the documented bound."""
    import coremltools as ct

    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    r2 = _fit_head_on_predicted_rates(model)
    model.eval()

    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    out_path = ckpt_dir / f"ndt1_velocity_parity_{tmp_path.name}.mlpackage"
    convert_to_mlpackage(model, out_path, seq_len=SEQ_LEN)

    # One fixed (1,96,1,S) fp16 input window — both paths see exactly the same bytes.
    rng = np.random.default_rng(7)
    window = rng.random((1, CHANNELS, 1, SEQ_LEN), dtype=np.float32).astype(np.float16)

    with torch.no_grad():
        torch_out = (
            model(torch.from_numpy(window.astype(np.float32)))
            .squeeze()
            .numpy()
            .astype(np.float64)
        )  # (2,)

    try:
        cm_model = ct.models.MLModel(str(out_path))
        out_name = cm_model.get_spec().description.output[0].name
        cm_pred = cm_model.predict({INPUT_FEATURE_NAME: window})
    except RuntimeError as exc:  # explicit — never a bare/blind except
        raise RuntimeError(f"coremltools CPU prediction failed: {exc}") from exc

    coreml_out = np.asarray(cm_pred[out_name], dtype=np.float64).reshape(-1)  # (2,)
    max_abs_delta = float(np.max(np.abs(torch_out - coreml_out)))

    record = {
        "max_abs_delta": max_abs_delta,
        "bound": VELOCITY_PARITY_BOUND,
        "torch_velocity": torch_out.tolist(),
        "coreml_velocity": coreml_out.tolist(),
        "velocity_r2": r2.get("r2") if isinstance(r2, dict) else None,
    }
    (ckpt_dir / "velocity_parity.json").write_text(json.dumps(record, indent=2))
    print(
        f"\n[DEC-10 parity] torch={torch_out}  coreml={coreml_out}  "
        f"|max_abs_delta|={max_abs_delta:.6f} <= bound={VELOCITY_PARITY_BOUND}"
    )

    assert max_abs_delta <= VELOCITY_PARITY_BOUND, (
        f"PyTorch-vs-CoreML velocity max-abs-delta {max_abs_delta:.6f} exceeds documented "
        f"bound {VELOCITY_PARITY_BOUND}"
    )
