"""Shared pytest fixtures for the NDT1 decoder test-suite (seeded, CPU-only, deterministic)."""
from __future__ import annotations

import numpy as np
import pytest
import torch

CHANNELS: int = 96   # must equal CORTEX_CHANNEL_COUNT (cortex_shm.h / cortex_ring.h / frame.rs)
SEQ_LEN: int = 32     # bins per training sequence (≈640 ms at 20 ms binning)


@pytest.fixture(autouse=True)
def _seed() -> None:
    torch.manual_seed(0)
    np.random.seed(0)


@pytest.fixture
def tiny_spike_counts() -> torch.Tensor:
    """A tiny (B=4, T=SEQ_LEN, C=96) Poisson-ish spike-count tensor for unit tests."""
    rng = np.random.default_rng(0)
    counts = rng.poisson(lam=0.3, size=(4, SEQ_LEN, CHANNELS)).astype("float32")
    return torch.from_numpy(counts)


@pytest.fixture
def dummy_bc1s_input() -> torch.Tensor:
    """A dummy (B=1, C=96, 1, S=SEQ_LEN) BC1S inference input (the ANE-conducive layout)."""
    return torch.rand(1, CHANNELS, 1, SEQ_LEN, dtype=torch.float32)
