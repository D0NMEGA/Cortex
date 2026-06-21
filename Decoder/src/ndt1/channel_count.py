"""Single Python source-of-truth for the neural channel width.

MUST equal CORTEX_CHANNEL_COUNT in all of:
  - Packages/CortexCore/Sources/CortexCoreC/include/cortex_shm.h
  - Packages/CortexRing/rust/src/frame.rs
  - Packages/CortexRing/rust/include/cortex_ring.h
Confirmed = 96 (O'Doherty Indy M1-only sessions; Zenodo 3854034). Closes Phase-2 D-11.

The literal width (the value the three native homes must equal):

    CORTEX_CHANNEL_COUNT = 96
"""
from __future__ import annotations

CORTEX_CHANNEL_COUNT: int = 96
