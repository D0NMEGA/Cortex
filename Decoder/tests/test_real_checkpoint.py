"""Task 09-08-1 — the provenance label that keeps a random-weight number out of a real-data claim.

Every CoreML number Plan 09-08 publishes replaces a Phase-4/5 figure that was measured on a
randomly-initialized or synthetic-data model. The only structural defence against republishing one
of those by accident is that the load itself returns a LABEL naming what it loaded, and that every
artifact records that label. These tests pin the label's two states and the two ways the load is
allowed to fail.

Quick tests: they build tiny models and never convert, palettize or train.
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

import pytest
import torch

from ndt1.model_ane import NDT1ANE, NDT1ANEWithVelocity
from ndt1.real_checkpoint import (
    REAL_ENCODER_CHECKPOINT,
    REAL_VELOCITY_CHECKPOINT,
    checkpoint_sha256,
    load_real_weights_if_present,
)

SEQ_LEN = 32
#: The label must carry enough of the digest to identify the file, and exactly this much.
SHA_PREFIX_PATTERN = re.compile(r"sha256=[0-9a-f]{12}\b")


def _state_fingerprint(model: torch.nn.Module) -> str:
    """A hash over every parameter's bytes, so "unchanged" is checked rather than assumed."""
    digest = hashlib.sha256()
    for key, tensor in sorted(model.state_dict().items()):
        digest.update(key.encode("utf-8"))
        digest.update(tensor.detach().cpu().numpy().tobytes())
    return digest.hexdigest()


def test_missing_checkpoint_returns_random_init_label(tmp_path: Path) -> None:
    """With no checkpoint on disk the model is untouched and the label says so."""
    model = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    before = _state_fingerprint(model)

    label = load_real_weights_if_present(model, tmp_path / "absent.pt")

    assert "random init" in label
    assert "real-data" not in label
    assert _state_fingerprint(model) == before, "a missing checkpoint must not perturb the weights"


def test_present_checkpoint_loads_and_labels(tmp_path: Path) -> None:
    """A present checkpoint is loaded and the label names it and its sha256 prefix."""
    source = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    path = tmp_path / "ndt1_real_with_velocity.pt"
    torch.save(source.state_dict(), path)

    target = NDT1ANEWithVelocity(seq_len=SEQ_LEN)
    assert _state_fingerprint(target) != _state_fingerprint(source), "distinct random inits"

    label = load_real_weights_if_present(target, path)

    assert "real-data" in label
    assert path.name in label
    assert SHA_PREFIX_PATTERN.search(label), f"no 12-hex sha256 prefix in {label!r}"
    assert checkpoint_sha256(path).startswith(label.split("sha256=")[1][:12])
    assert _state_fingerprint(target) == _state_fingerprint(source), "the weights must now match"


def test_mismatched_state_dict_raises(tmp_path: Path) -> None:
    """A checkpoint whose keys do not match the model is loud, never a partial load."""
    path = tmp_path / "encoder_only.pt"
    torch.save(NDT1ANE(seq_len=SEQ_LEN).state_dict(), path)

    with pytest.raises((RuntimeError, OSError)):
        load_real_weights_if_present(NDT1ANEWithVelocity(seq_len=SEQ_LEN), path)


def test_failed_load_never_falls_back_to_random_weights(tmp_path: Path) -> None:
    """A corrupt checkpoint raises rather than quietly returning a `random init` label.

    This is the failure mode the label exists to prevent: silently degrading to random weights
    while the caller goes on to publish the resulting number as a real-data measurement.
    """
    path = tmp_path / "corrupt.pt"
    path.write_bytes(b"not a torch checkpoint")

    with pytest.raises((RuntimeError, OSError)):
        load_real_weights_if_present(NDT1ANEWithVelocity(seq_len=SEQ_LEN), path)


def test_checkpoint_sha256_matches_hashlib(tmp_path: Path) -> None:
    """The streamed digest equals a whole-file digest (the chunking must not drop bytes)."""
    path = tmp_path / "payload.bin"
    path.write_bytes(bytes(range(256)) * 8192)  # 2 MiB — spans more than one 1 MiB chunk
    assert checkpoint_sha256(path) == hashlib.sha256(path.read_bytes()).hexdigest()


def test_default_paths_point_at_the_phase9_checkpoints() -> None:
    """The defaults are the two Plan 09-06/09-07 checkpoints, by name and location."""
    assert REAL_ENCODER_CHECKPOINT.name == "ndt1_real_pooled.pt"
    assert REAL_VELOCITY_CHECKPOINT.name == "ndt1_real_with_velocity.pt"
    assert REAL_ENCODER_CHECKPOINT.parent.name == "checkpoints"
    assert REAL_VELOCITY_CHECKPOINT.parent == REAL_ENCODER_CHECKPOINT.parent


def test_default_path_is_chosen_by_model_type(tmp_path: Path) -> None:
    """A with-velocity model defaults to the velocity checkpoint, a bare encoder to the pooled one.

    Exercised through the missing-file branch so the assertion needs no checkpoint on disk and the
    test stays quick and hermetic.
    """
    velocity_label = load_real_weights_if_present(NDT1ANEWithVelocity(seq_len=SEQ_LEN))
    encoder_label = load_real_weights_if_present(NDT1ANE(seq_len=SEQ_LEN))
    for label, expected in (
        (velocity_label, REAL_VELOCITY_CHECKPOINT),
        (encoder_label, REAL_ENCODER_CHECKPOINT),
    ):
        # On a machine that HAS the checkpoint the label names it; on one that does not, the
        # `random init` label names the path it looked for. Either way the file is identified.
        assert expected.name in label


def test_no_unguarded_torch_load() -> None:
    """T-04-04-01: the module never reaches `torch.load` without `weights_only=True`.

    Loading routes through `ndt1.train.load_checkpoint`, which pins `weights_only=True`. If a
    direct call is ever added here, it must carry the flag on the same line.
    """
    source = (
        Path(__file__).resolve().parents[1] / "src" / "ndt1" / "real_checkpoint.py"
    ).read_text()
    for line in source.splitlines():
        if "torch.load" in line and not line.lstrip().startswith("#"):
            assert "weights_only=True" in line, f"unguarded torch.load: {line.strip()!r}"
    assert "load_checkpoint" in source, "the load must route through ndt1.train.load_checkpoint"


def test_no_blind_except() -> None:
    """The project's BLE rule, asserted on this module specifically (never a silent fallback)."""
    source = (
        Path(__file__).resolve().parents[1] / "src" / "ndt1" / "real_checkpoint.py"
    ).read_text()
    assert not re.search(r"except\s*:", source)
    assert not re.search(r"except\s+Exception", source)
