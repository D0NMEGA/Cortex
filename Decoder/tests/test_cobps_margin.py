"""The co-bps assertion margin must FOLLOW the real-data observation, not precede it (RD-03b, D-22).

The margin has been derived twice and both predecessors are superseded, for different reasons.

Phase 4 committed ``CO_BPS_MARGIN = 0.05`` against a co-bps of 0.3804 measured on a purpose-built
learnable synthetic sinusoid (``04-training-evidence.md``: "No real ``.mat`` was present under
``Decoder/data/``"). That constant is calibrated to a dataset the model was guaranteed to be able to
fit, so carrying it onto real primate M1 spikes would assert nothing about the real number.

Plan 09-06 then committed ``0.25`` against a co-bps of 1.9116 measured on real spikes -- but under
an objective in which the encoder received the true count at every position it was scored on, so
that observation was a self-reconstruction score (see ``test_masked_input_isolation.py``). Plan
09-06b corrected the objective, re-measured, and re-derived the margin from the corrected value with
the derivation rule unchanged.

These five quick tests hold the re-derivation in place:

  * the constant is neither the Phase-4 synthetic value nor the superseded 09-06 value,
  * the committed metrics JSON records the margin AND the rationale that produced it,
  * the test constant and the published number cannot drift apart, and
  * the superseded numbers stay in the JSON, labeled, rather than being quietly deleted.

They read only the committed JSON and the sibling test module -- no dataset, no training, no torch
forward pass -- so they belong in the quick CI gate (D-18) alongside the structural tests, while the
number itself stays a human-run runbook artifact (D-21).

**Why the third test matters most.** A margin that lives in two places will eventually disagree in
two places. Binding them means a re-run of ``train_real.py`` (which resets ``co_bps.margin`` to
``null`` on purpose, so a margin never outlives the measurement it came from) fails this gate loudly
instead of leaving a stale assertion guarding a number that no longer exists.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tests.test_heldout_cobps import CO_BPS_MARGIN

#: What Phase 4 committed, against a SYNTHETIC observation. Named here so the assertion message can
#: explain itself rather than just reporting an inequality.
PHASE4_SYNTHETIC_MARGIN: float = 0.05

#: What Plan 09-06 committed, against a REAL observation produced by a defective objective.
VISIBLE_INPUT_MARGIN: float = 0.25

#: The JSON key under which the pre-09-06b numbers are preserved.
SUPERSEDED_KEY: str = "superseded_visible_input_objective"

_METRICS_PATH = (
    Path(__file__).resolve().parents[2]
    / ".planning"
    / "phases"
    / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
    / "09-decoder-metrics.json"
)

_MIN_RATIONALE_CHARS: int = 40


def _metrics() -> dict[str, Any]:
    metrics: dict[str, Any] = json.loads(_METRICS_PATH.read_text(encoding="utf-8"))
    return metrics


def test_margin_is_not_the_phase4_synthetic_constant() -> None:
    """The committed margin is not the Phase-4 value calibrated on a synthetic sinusoid."""
    assert CO_BPS_MARGIN != PHASE4_SYNTHETIC_MARGIN, (
        f"CO_BPS_MARGIN is still {PHASE4_SYNTHETIC_MARGIN}, the Phase-4 constant chosen against a "
        f"co-bps of 0.3804 measured on a purpose-built learnable synthetic sinusoid. D-22 requires "
        f"the margin to be re-derived from the observed REAL value after measuring it."
    )


def test_metrics_json_records_margin_and_rationale() -> None:
    """The committed metrics JSON carries a non-null margin and a substantive rationale."""
    co_bps_block = _metrics()["co_bps"]
    margin = co_bps_block["margin"]
    assert margin is not None, (
        "co_bps.margin is null in the committed metrics JSON. train_real.py writes null on every "
        "training run by design, so a margin never outlives its measurement; re-derive it with "
        "`train_real.py --derive-margin` after the run that produced the number."
    )
    assert isinstance(margin, (int, float))
    rationale = co_bps_block["margin_rationale"]
    assert isinstance(rationale, str), f"margin_rationale is {type(rationale).__name__}, not a str"
    assert len(rationale) >= _MIN_RATIONALE_CHARS, (
        f"margin_rationale is {len(rationale)} characters; D-22 requires the reasoning behind the "
        f"margin to be recorded, not merely the number"
    )


def test_margin_matches_the_committed_metrics() -> None:
    """The test constant and the published number are the same value."""
    published = _metrics()["co_bps"]["margin"]
    assert CO_BPS_MARGIN == published, (
        f"tests/test_heldout_cobps.py asserts against {CO_BPS_MARGIN} while "
        f"09-decoder-metrics.json publishes {published}. A margin that lives in two places must "
        f"not be allowed to disagree in two places."
    )


def test_margin_is_not_the_superseded_visible_input_constant() -> None:
    """The margin is not the one derived from a co-bps the encoder could see the answers to."""
    assert CO_BPS_MARGIN != VISIBLE_INPUT_MARGIN, (
        f"CO_BPS_MARGIN is still {VISIBLE_INPUT_MARGIN}, the Plan 09-06 constant derived from an "
        f"observed 1.9116 that was measured while the encoder received the true count at every "
        f"position it was scored on. Plan 09-06b hid those positions and re-measured; the margin "
        f"must follow the corrected observation."
    )


def test_the_superseded_numbers_are_preserved_and_labeled() -> None:
    """Correcting a published number means labeling the old one, not deleting it.

    Documents outside this repository may already quote 1.9116. A reader who finds it must be able
    to look it up here and learn why it must not be used, so the record is retained with its
    warning rather than removed.
    """
    superseded = _metrics().get(SUPERSEDED_KEY)
    assert isinstance(superseded, dict), (
        f"{SUPERSEDED_KEY} is missing from the committed metrics JSON. The numbers Plan 09-06 "
        f"published are retained, labeled, and never deleted; train_real.py carries this key "
        f"across re-runs for exactly that reason."
    )
    assert superseded["co_bps"]["pooled"]["train_null"] == 1.9115827904116325
    note = superseded["note"]
    assert isinstance(note, str) and "MUST NOT BE QUOTED" in note, (
        "the superseded record must carry the warning that says how it may be used"
    )
