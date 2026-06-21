"""Wave-0 smoke: env imports resolve and shared fixtures have the contracted shapes."""
from __future__ import annotations

import torch

from tests.conftest import CHANNELS, SEQ_LEN


def test_channels_constant_is_96() -> None:
    assert CHANNELS == 96


def test_dummy_bc1s_shape(dummy_bc1s_input: torch.Tensor) -> None:
    assert tuple(dummy_bc1s_input.shape) == (1, 96, 1, SEQ_LEN)
    assert dummy_bc1s_input.shape[2] == 1  # the BC1S singleton height axis


def test_tiny_spike_counts_shape(tiny_spike_counts: torch.Tensor) -> None:
    assert tiny_spike_counts.shape[-1] == CHANNELS
