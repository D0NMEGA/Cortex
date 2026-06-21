"""DEC-10 unit coverage — VelocityHead: 1x1 Conv2d(96->2) + static last-bin slice + ridge fit.

The four behaviors (Plan 05-01 Task 1):

1. ``VelocityHead(num_channels=96).forward(rates (B,96,1,S))`` returns ``(B, 2, 1, 1)`` — exactly
   2 output channels (vx, vy), height 1, sequence collapsed to 1 by the last-bin slice.
2. The last-bin slice is ``rates[..., -1:]`` — a rates tensor whose LAST bin is a known constant
   and earlier bins are zero yields a velocity depending ONLY on the last bin (mutating bin 0
   leaves the output unchanged). This is the ANE-friendly static slice (Decision 1), NOT a dynamic
   index, and the negative control (``[..., :1]``) must break this test.
3. ``ridge_fit(X (N,96), Y (N,2), lam)`` equals the independent closed-form numpy solution
   ``np.linalg.solve(X.T@X + lam*I, X.T@Y)`` (transposed into the Conv2d ``(2,96)`` weight) to 1e-5.
4. Loading the ridge weights via the head's load hook makes ``VelocityHead`` reproduce
   ``X @ W.T + b`` on held data; the velocity-decode R^2 is recorded to a gitignored json and
   asserted finite + > 0 (non-degenerate — credibility evidence, not a hard SC).

Fast unit tests (no ``ct.convert``) — no ``slow`` marker. The conftest autouse seed applies.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest
import torch

from ndt1.velocity_head import (
    VELOCITY_DIM,
    VelocityHead,
    load_ridge,
    ridge_fit,
)

CHANNELS = 96
SEQ_LEN = 32


def test_forward_returns_b2_1_1_shape() -> None:
    """forward(rates (B,96,1,S)) -> (B, 2, 1, 1): exactly two channels, height 1, S collapsed."""
    head = VelocityHead(num_channels=CHANNELS)
    rates = torch.rand(4, CHANNELS, 1, SEQ_LEN)
    out = head(rates)
    assert out.shape == (4, VELOCITY_DIM, 1, 1)
    assert VELOCITY_DIM == 2


def test_output_depends_only_on_last_bin() -> None:
    """The static last-bin slice rates[..., -1:] makes the output a function of the LAST bin only.

    Build a rates tensor whose last bin is a known constant and all earlier bins are zero. Mutating
    an earlier bin (bin 0) must NOT change the velocity; only the last bin drives it. The negative
    control — flipping the slice to rates[..., :1] (first bin) — makes this assertion fail.
    """
    head = VelocityHead(num_channels=CHANNELS)
    head.eval()

    rates = torch.zeros(1, CHANNELS, 1, SEQ_LEN)
    rates[..., -1:] = 0.7  # only the last bin carries signal
    with torch.no_grad():
        out_a = head(rates)

    # Mutate bin 0 (an EARLIER bin) — the last-bin readout must be invariant to this.
    rates_mut = rates.clone()
    rates_mut[..., 0:1] = 5.0
    with torch.no_grad():
        out_b = head(rates_mut)

    assert torch.allclose(out_a, out_b, atol=1e-6), (
        "output must depend ONLY on the last bin (static slice rates[..., -1:]); "
        "changing bin 0 changed the velocity"
    )

    # And it must actually be reading the last bin: a different last-bin value changes the output.
    rates_diff = torch.zeros(1, CHANNELS, 1, SEQ_LEN)
    rates_diff[..., -1:] = 3.0
    with torch.no_grad():
        out_c = head(rates_diff)
    assert not torch.allclose(out_a, out_c, atol=1e-6), (
        "a different last-bin value must change the output — the head must read the last bin"
    )


def test_ridge_fit_matches_independent_closed_form() -> None:
    """ridge_fit equals the independent numpy closed-form solve to 1e-5 (transposed to (2,96))."""
    rng = np.random.default_rng(0)
    n = 500
    x = rng.standard_normal((n, CHANNELS)).astype(np.float64)
    y = rng.standard_normal((n, VELOCITY_DIM)).astype(np.float64)
    lam = 1.0

    weight, bias = ridge_fit(x, y, lam)

    # Independent reference: center the data (bias = intercept), solve the ridge normal eqs.
    xc = x - x.mean(0)
    yc = y - y.mean(0)
    w_ref = np.linalg.solve(xc.T @ xc + lam * np.eye(CHANNELS), xc.T @ yc)  # (96, 2)
    weight_ref = w_ref.T  # (2, 96) — Conv2d (out, in) convention
    bias_ref = y.mean(0) - x.mean(0) @ w_ref  # (2,)

    assert weight.shape == (VELOCITY_DIM, CHANNELS)
    assert bias.shape == (VELOCITY_DIM,)
    np.testing.assert_allclose(weight, weight_ref, atol=1e-5)
    np.testing.assert_allclose(bias, bias_ref, atol=1e-5)


def test_ridge_fit_raises_on_shape_mismatch() -> None:
    """ridge_fit rejects mismatched N (explicit ValueError, never a silent broadcast)."""
    x = np.zeros((10, CHANNELS))
    y = np.zeros((9, VELOCITY_DIM))  # N mismatch
    with pytest.raises(ValueError):
        ridge_fit(x, y, 1.0)


def test_load_ridge_reproduces_linear_map_and_records_r2() -> None:
    """After load_ridge, the head reproduces X @ W.T + b on held data; R^2 finite and > 0."""
    rng = np.random.default_rng(1)
    n = 800
    x_all = rng.standard_normal((n, CHANNELS)).astype(np.float64)
    # A genuine linear relationship + small noise so the ridge readout is non-degenerate (R^2 > 0).
    w_true = rng.standard_normal((CHANNELS, VELOCITY_DIM)) * 0.1
    b_true = rng.standard_normal(VELOCITY_DIM)
    y_all = x_all @ w_true + b_true + 0.01 * rng.standard_normal((n, VELOCITY_DIM))

    split = 600
    x_tr, y_tr = x_all[:split], y_all[:split]
    x_te, y_te = x_all[split:], y_all[split:]

    weight, bias = ridge_fit(x_tr, y_tr, lam=1.0)

    head = VelocityHead(num_channels=CHANNELS)
    load_ridge(head, weight, bias)
    head.eval()

    # Reproduce the linear map: drive the head with held-out rates placed in the LAST bin.
    # Build a (N_te, 96, 1, S) batch where every earlier bin is zero and the last bin is x_te.
    n_te = x_te.shape[0]
    rates = torch.zeros(n_te, CHANNELS, 1, SEQ_LEN, dtype=torch.float32)
    # Place x_te (N,96) into the LAST bin, keeping the (1,1) height/last-bin singleton dims.
    rates[..., -1:] = torch.from_numpy(x_te.astype(np.float32)).reshape(n_te, CHANNELS, 1, 1)
    with torch.no_grad():
        pred = head(rates).squeeze(-1).squeeze(-1).numpy().astype(np.float64)  # (N_te, 2)

    # Reference forward: X @ W.T + b == X @ weight.T + bias.
    ref = x_te @ weight.T + bias
    np.testing.assert_allclose(pred, ref, atol=1e-4)

    # R^2 of the held-out velocity decode (credibility evidence; recorded to a gitignored json).
    ss_res = float(((y_te - pred) ** 2).sum())
    ss_tot = float(((y_te - y_te.mean(0)) ** 2).sum())
    r2 = 1.0 - ss_res / ss_tot

    ckpt_dir = Path(__file__).resolve().parents[1] / "checkpoints"
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    (ckpt_dir / "velocity_r2.json").write_text(
        json.dumps({"r2": r2, "n_test": n_te, "lambda": 1.0}, indent=2)
    )

    assert np.isfinite(r2), "R^2 must be finite"
    assert r2 > 0.0, f"R^2 must be > 0 (non-degenerate ridge readout), got {r2}"
