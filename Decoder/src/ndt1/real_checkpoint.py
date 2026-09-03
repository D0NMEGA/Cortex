"""Load the Phase-9 real-data checkpoints, and always say which weights were loaded.

Every CoreML-side number Plan 09-08 publishes -- the 4-bit size ratio, both palettization loss
deltas, the ANE op tally, the decoder p99 -- replaces a Phase-4/5 figure that was measured on a
randomly-initialized or synthetic-data model. RD-05 forbids inheriting any of them, so each has to
be re-measured on `ndt1_real_pooled.pt` (the reconstruction encoder, Plan 09-06) or
`ndt1_real_with_velocity.pt` (the shipped model, Plan 09-07).

The hazard is not that the load fails; it is that the load quietly does not happen. A slow test on a
checkout without the gitignored checkpoints produces a perfectly plausible number from random
weights, and nothing in the emitted JSON says so. This module removes that ambiguity by making the
PROVENANCE LABEL the return value: the caller cannot obtain the weights without also obtaining the
string that names them, and every artifact records that string. A checkpoint that is present but
unloadable raises instead of falling back, because a silent fallback is exactly the failure the
label exists to prevent.

Loading routes through :func:`ndt1.train.load_checkpoint` so `weights_only=True` is inherited
(T-04-04-01); this module never unpickles a checkpoint itself.
"""
from __future__ import annotations

import hashlib
import pickle
from pathlib import Path

from torch import nn

from ndt1.model_ane import NDT1ANEWithVelocity
from ndt1.train import load_checkpoint

#: Bytes read per digest update. Large enough that hashing a 5 MB checkpoint is a handful of
#: reads, small enough that nothing here depends on the file fitting in memory.
_HASH_CHUNK_BYTES = 1024 * 1024

_CHECKPOINT_DIR = Path(__file__).resolve().parents[2] / "checkpoints"

#: Plan 09-06's pooled encoder: the reconstruction model, scored by held-out co-bps.
REAL_ENCODER_CHECKPOINT = _CHECKPOINT_DIR / "ndt1_real_pooled.pt"

#: Plan 09-07's shipped model: the same encoder tensors plus the 194-parameter ridge readout.
REAL_VELOCITY_CHECKPOINT = _CHECKPOINT_DIR / "ndt1_real_with_velocity.pt"

#: How much of the digest goes into the label. Twelve hex characters identify a file among the
#: handful this repository produces while keeping the label readable in a one-line JSON field.
SHA_PREFIX_LEN = 12


def checkpoint_sha256(path: Path) -> str:
    """Streamed sha256 of a checkpoint file, read in :data:`_HASH_CHUNK_BYTES` chunks.

    Args:
        path: the checkpoint to digest.

    Returns:
        The full 64-character lowercase hex digest.

    Raises:
        OSError: if the file cannot be read.
    """
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(_HASH_CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def default_checkpoint_for(model: nn.Module) -> Path:
    """The real-data checkpoint that matches ``model``'s architecture.

    :class:`~ndt1.model_ane.NDT1ANEWithVelocity` takes the shipped with-velocity checkpoint;
    anything else (in practice the bare :class:`~ndt1.model_ane.NDT1ANE` encoder) takes the pooled
    reconstruction checkpoint. Dispatching on type rather than asking the caller to name a path is
    what stops the encoder checkpoint being loaded into the shipped model, which would load a
    partial state dict and raise -- loudly, but one step later than necessary.
    """
    if isinstance(model, NDT1ANEWithVelocity):
        return REAL_VELOCITY_CHECKPOINT
    return REAL_ENCODER_CHECKPOINT


def load_real_weights_if_present(model: nn.Module, path: Path | None = None) -> str:
    """Load the real-data checkpoint into ``model`` when it exists; return a PROVENANCE LABEL.

    Returns either::

        "real-data checkpoint <name> sha256=<first 12 hex>"

    or::

        "random init (no checkpoint at <path>)"

    Never silently mixes the two: the label is the string every downstream artifact records, so a
    number measured on random weights can never be mistaken for a real-data number. The `random
    init` branch deliberately does NOT contain the substring `real-data`, because callers gate on
    exactly that substring; a label reading "no real-data checkpoint at ..." would satisfy the
    guard it is supposed to trip. A checkpoint
    that exists but does not load is re-raised with context rather than degraded into the
    `random init` branch.

    Args:
        model: the module to load into, mutated in place on success.
        path: the checkpoint to load; defaults to :func:`default_checkpoint_for`.

    Returns:
        The provenance label described above.

    Raises:
        RuntimeError: if the checkpoint exists but cannot be read, is not a `weights_only`
            state dict, or does not match ``model``'s parameter names and shapes. A truncated or
            corrupt file surfaces here too: unpickling one raises `pickle.UnpicklingError`, which
            is outside the set `ndt1.train.load_checkpoint` catches, so it is caught and re-raised
            with context here rather than escaping bare.
    """
    checkpoint = Path(path) if path is not None else default_checkpoint_for(model)
    if not checkpoint.is_file():
        return f"random init (no checkpoint at {checkpoint})"

    digest = checkpoint_sha256(checkpoint)
    try:
        load_checkpoint(model, checkpoint)
    except (OSError, RuntimeError, pickle.UnpicklingError) as exc:  # explicit types only
        raise RuntimeError(
            f"real-data checkpoint {checkpoint} exists but could not be loaded into "
            f"{type(model).__name__}: {exc}. Refusing to continue on random weights, because a "
            f"number measured that way would be published as a real-data number."
        ) from exc
    return f"real-data checkpoint {checkpoint.name} sha256={digest[:SHA_PREFIX_LEN]}"
