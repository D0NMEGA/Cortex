"""DEC-10 — linear velocity readout head: NDT1 rates -> (vx, vy) cursor velocity.

Appends a kinematics readout to the Phase-4 :class:`~ndt1.model_ane.NDT1ANE` encoder so the
converted Core ML ``.mlpackage`` emits a 2-vector ``(vx, vy)`` fp16 cursor velocity instead of
96-channel Poisson rates (05-RESEARCH Decision 1):

* **Layer** — a 1x1 ``nn.Conv2d(num_channels=96, VELOCITY_DIM=2, kernel_size=1)`` operating on the
  rates in the ANE-pinned BC1S ``(B, C, 1, S)`` layout (1x1 conv is ANE-eligible; ``apple/
  ml-ane-transformers``). The velocity of *this* 20 ms window is read from the LAST time-bin via a
  **static slice** ``rates[..., -1:]`` (NOT dynamic indexing — dynamic gathers fall off the ANE).
* **Fit** — closed-form ridge regression ``W = (XᵀX + λI)⁻¹ XᵀY`` of rates -> velocity. The ridge
  ``W`` matrix loads straight into the 1x1 conv via a ``load_state_dict`` pre-hook that unsqueezes
  the rank-2 ``(out, in)`` weight to the rank-4 ``(out, in, 1, 1)`` conv shape — MIRRORING the
  Phase-4 dense->conv hook (``model_ane.py:_dense_to_conv_pre_hook``). There is NO training loop.
* **Why linear, not Kalman** — a linear ridge readout is the standard iBCI rates->velocity decoder;
  ReFIT-Kalman closed-loop refinement is REFIT-01 / Phase 7 (Swift, post-CoreML). Keeping the head
  linear is also what keeps the converted graph ANE-resident.

"Every 20 ms" (DEC-10) is the Swift CALLER's 50 Hz decode cadence (Plan 04), not a graph-internal
timer: the model consumes one 20 ms-binned window per call and emits one ``(vx, vy)``.

No bare/blind ``except`` (ruff ``BLE`` gate): the only ``except`` is a specific ``ImportError`` for
the channel-count standalone-worktree fallback; ``ridge_fit`` raises an explicit ``ValueError`` on
shape mismatch.
"""
from __future__ import annotations

import numpy as np
import torch
from torch import Tensor, nn

try:  # Channel-width source-of-truth lives in Plan 04-02's channel_count module.
    from ndt1.channel_count import CORTEX_CHANNEL_COUNT
except ImportError:  # 04-02 may land in a sibling worktree; fall back to the locked value (96).
    # NOT a bare/blind except — a specific ImportError so this module stands alone in an isolated
    # worktree where channel_count.py is not yet merged. 96 matches the three repo homes
    # (cortex_shm.h / cortex_ring.h / frame.rs) and the conftest CHANNELS constant.
    CORTEX_CHANNEL_COUNT = 96

#: Cursor-velocity output width — (vx, vy). The converted package emits exactly this many channels.
VELOCITY_DIM: int = 2  # (vx, vy)


class VelocityHead(nn.Module):
    """BC1S-preserving linear velocity readout: rates ``(B,96,1,S)`` -> velocity ``(B,2,1,1)``.

    A single 1x1 ``nn.Conv2d(num_channels -> VELOCITY_DIM)`` applied to the LAST time-bin of the
    rates (selected by the static slice ``rates[..., -1:]``). The conv weight is fit by closed-form
    ridge regression (:func:`ridge_fit`) and loaded via :func:`load_ridge`, which routes through a
    ``load_state_dict`` pre-hook that unsqueezes the rank-2 ridge weight to the rank-4 conv shape
    (the analogue of the Phase-4 dense->conv load path).

    Args:
        num_channels: input channel width of the rates (default ``CORTEX_CHANNEL_COUNT`` == 96).
    """

    def __init__(self, num_channels: int = CORTEX_CHANNEL_COUNT) -> None:
        super().__init__()
        self.num_channels = num_channels
        self.readout = nn.Conv2d(num_channels, VELOCITY_DIM, kernel_size=1)
        # Load a ridge (out, in) weight straight into the (out, in, 1, 1) conv — mirrors the
        # Phase-4 dense->conv pre-hook in model_ane.py.
        self._register_load_state_dict_pre_hook(self._ridge_to_conv_pre_hook)

    @staticmethod
    def _ridge_to_conv_pre_hook(
        state_dict: dict[str, Tensor],
        prefix: str,
        *args: object,
    ) -> None:
        """Unsqueeze a rank-2 ridge ``.weight`` ``(out, in)`` to 1x1-conv shape ``(out, in, 1, 1)``.

        Lets a ridge ``W (2, 96)`` matrix load directly into ``readout.weight`` ``(2, 96, 1, 1)``.
        Operates only on ``*.weight`` entries that are rank-2; the rank-1 bias is left untouched.
        """
        for key, value in list(state_dict.items()):
            if key.startswith(prefix) and key.endswith(".weight") and value.dim() == 2:
                state_dict[key] = value.unsqueeze(-1).unsqueeze(-1)

    def forward(self, rates: Tensor) -> Tensor:
        # rates: (B, num_channels, 1, S) -> velocity (B, VELOCITY_DIM, 1, 1).
        last = rates[..., -1:]  # static slice, NOT dynamic index — ANE-friendly (Decision 1)
        return self.readout(last)


def ridge_fit(
    rates: np.ndarray, vel: np.ndarray, lam: float = 1.0
) -> tuple[np.ndarray, np.ndarray]:
    """Closed-form ridge regression of per-bin rates -> velocity.

    Solves ``W = (XᵀX + λI)⁻¹ XᵀY`` on CENTERED data (so the returned bias is the intercept), via
    ``np.linalg.solve`` — never an explicit matrix inverse. Fitting on the model's PREDICTED rates
    (not ground-truth) avoids train/serve skew (05-RESEARCH Decision 1); the caller in Task 2 passes
    predicted rates.

    Args:
        rates: ``(N, num_channels)`` design matrix of per-bin rates.
        vel: ``(N, VELOCITY_DIM)`` velocity labels (vx, vy).
        lam: ridge regularization strength λ (default 1.0).

    Returns:
        ``(weight, bias)`` where ``weight`` is ``(VELOCITY_DIM, num_channels)`` (Conv2d
        ``(out, in)`` convention — already transposed from the ``(in, out)`` solve) and ``bias``
        is ``(VELOCITY_DIM,)`` (the intercept).

    Raises:
        ValueError: if ``rates``/``vel`` are not 2-D or their sample counts ``N`` disagree.
    """
    x = np.asarray(rates, dtype=np.float64)
    y = np.asarray(vel, dtype=np.float64)
    if x.ndim != 2 or y.ndim != 2:
        raise ValueError(
            f"ridge_fit expects 2-D rates (N, C) and vel (N, {VELOCITY_DIM}); "
            f"got shapes {x.shape} and {y.shape}"
        )
    if x.shape[0] != y.shape[0]:
        raise ValueError(
            f"ridge_fit: rates and vel must share N; got {x.shape[0]} vs {y.shape[0]}"
        )

    num_channels = x.shape[1]
    x_mean = x.mean(axis=0)
    y_mean = y.mean(axis=0)
    xc = x - x_mean
    yc = y - y_mean
    # Closed-form ridge on centered data: (XᵀX + λI) W = XᵀY  ->  W (num_channels, VELOCITY_DIM).
    gram = xc.T @ xc + lam * np.eye(num_channels)
    w = np.linalg.solve(gram, xc.T @ yc)
    weight = w.T  # (VELOCITY_DIM, num_channels) — Conv2d (out, in)
    bias = y_mean - x_mean @ w  # (VELOCITY_DIM,) intercept
    return weight, bias


def load_ridge(head: VelocityHead, weight: np.ndarray, bias: np.ndarray) -> None:
    """Load ridge ``(weight, bias)`` into ``head.readout`` via the rank-2 -> rank-4 pre-hook.

    Builds a ``state_dict`` with ``readout.weight`` ``(VELOCITY_DIM, num_channels)`` and
    ``readout.bias`` ``(VELOCITY_DIM,)`` and calls ``head.load_state_dict`` — the registered
    pre-hook unsqueezes the rank-2 weight to the ``(out, in, 1, 1)`` conv shape. This is the
    analogue of the Phase-4 dense->conv load path.

    Args:
        head: the :class:`VelocityHead` to load into.
        weight: ridge weight ``(VELOCITY_DIM, num_channels)`` (as returned by :func:`ridge_fit`).
        bias: ridge bias ``(VELOCITY_DIM,)``.
    """
    state_dict = {
        "readout.weight": torch.as_tensor(np.asarray(weight), dtype=torch.float32),
        "readout.bias": torch.as_tensor(np.asarray(bias), dtype=torch.float32),
    }
    head.load_state_dict(state_dict)
