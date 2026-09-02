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

Plan 09-06b's own ``0.00082`` is superseded in turn. It came from a 12-epoch unclipped run whose
loss was still descending when the budget ran out, and the budget itself had been calibrated
against the DEFECTIVE objective. Plan 09-06c added gradient clipping, replaced the fixed budget
with a rule pre-registered on the training loss, and re-derived once more. The derivation RULE has
never changed across any of these; only the observation it reads has.

Plan 09-06c's own ``0.0094`` is superseded in turn. Its objective was correct and its numerics
were guarded, but the pre-registered stopping rule fired at its own 12-epoch floor, and a probe
registered before it ran then measured that epochs 12 to 60 move the training loss 1.3% while
pooled co-bps rises 4.2x. Plan 09-06d removed the stopping rule instead of replacing it -- 200
epochs to a fixed cap, the whole co-bps trajectory published, the value at the cap reported -- and
fixed the forward-pass overflow that had cost a LOSO fold. Fourth re-derivation, same fraction.

The chain is four links long now and none of them may be deleted:

  1.9116  defective objective                       superseded_visible_input_objective
  0.0062  corrected objective, 12 unclipped epochs   superseded_truncated_budget
  0.0713  clipped, stopping rule fired at its floor  superseded_rule_stopped_at_floor
  (top)   no stopping rule, 200 epochs to the cap

These quick tests hold the re-derivation in place:

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

#: What Plan 09-06b committed, against a REAL observation under the corrected objective but from a
#: 12-epoch unclipped run on a curve that had not flattened.
TRUNCATED_BUDGET_MARGIN: float = 0.00082

#: What Plan 09-06c committed, against a REAL observation under the corrected objective with
#: gradient clipping, from a run its own pre-registered stopping rule ended at that rule's floor.
RULE_STOPPED_MARGIN: float = 0.0094

#: The JSON keys under which each superseded measurement is preserved.
SUPERSEDED_KEY: str = "superseded_visible_input_objective"
TRUNCATED_BUDGET_KEY: str = "superseded_truncated_budget"
RULE_STOPPED_KEY: str = "superseded_rule_stopped_at_floor"

#: The pooled train-null co-bps each superseded run published, to full double precision.
VISIBLE_INPUT_CO_BPS: float = 1.9115827904116325
TRUNCATED_BUDGET_CO_BPS: float = 0.006214627530704778
RULE_STOPPED_CO_BPS: float = 0.07133016502133391

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
    assert superseded["co_bps"]["pooled"]["train_null"] == VISIBLE_INPUT_CO_BPS
    note = superseded["note"]
    assert isinstance(note, str) and "MUST NOT BE QUOTED" in note, (
        "the superseded record must carry the warning that says how it may be used"
    )


def test_margin_is_not_the_superseded_truncated_budget_constant() -> None:
    """The margin is not the one derived from a run that stopped before its loss flattened."""
    assert CO_BPS_MARGIN != TRUNCATED_BUDGET_MARGIN, (
        f"CO_BPS_MARGIN is still {TRUNCATED_BUDGET_MARGIN}, the Plan 09-06b constant derived from "
        f"an observed {TRUNCATED_BUDGET_CO_BPS:.4f} measured at a fixed 12-epoch budget with no "
        f"gradient clipping. Plan 09-06c clipped, stopped by a pre-registered rule on the training "
        f"loss, and re-measured; the margin must follow the new observation."
    )


def test_the_truncated_budget_numbers_are_preserved_and_labeled() -> None:
    """The middle link of the chain. A supersession that loses it is not a record of what happened.

    Unlike the 1.9116, this block was NOT measuring self-reconstruction: its objective was already
    correct. What supersedes it is the budget and the numerics, and the note has to say so, because
    a reader who finds 0.0062 quoted elsewhere needs to know which of the two problems applied.
    """
    record = _metrics().get(TRUNCATED_BUDGET_KEY)
    assert isinstance(record, dict), (
        f"{TRUNCATED_BUDGET_KEY} is missing from the committed metrics JSON. train_real.py carries "
        f"every superseded_* record across a re-run so a chain cannot lose its middle link."
    )
    assert record["co_bps"]["pooled"]["train_null"] == TRUNCATED_BUDGET_CO_BPS
    assert record["config"]["epochs"] == 12
    note = record["note"]
    assert isinstance(note, str) and "must not be quoted" in note.lower(), (
        "the superseded record must carry the warning that says how it may be used"
    )


def test_every_superseded_record_says_what_replaced_it() -> None:
    """A labeled dead end is only useful if it points at the live number."""
    for key, record in _metrics().items():
        if not key.startswith("superseded_"):
            continue
        pointer = record.get("superseded_by")
        assert isinstance(pointer, str) and pointer, (
            f"{key} records numbers but does not say what supersedes them"
        )


def test_margin_is_not_the_superseded_rule_stopped_constant() -> None:
    """The margin is not the one derived from a run a stopping rule ended at its own floor."""
    assert CO_BPS_MARGIN != RULE_STOPPED_MARGIN, (
        f"CO_BPS_MARGIN is still {RULE_STOPPED_MARGIN}, the Plan 09-06c constant derived from an "
        f"observed {RULE_STOPPED_CO_BPS:.4f} measured at 12 epochs, where the pre-registered "
        f"stopping rule fired at MIN_EPOCHS rather than on a flat curve. Plan 09-06d removed the "
        f"stopping rule and trained to a 200-epoch cap; the margin must follow the new observation."
    )


def test_the_rule_stopped_numbers_are_preserved_and_labeled() -> None:
    """The third link. Its objective was correct, so the note has to say what actually replaced it.

    A reader who finds 0.0713 quoted elsewhere needs to learn that the problem was neither the
    objective nor the numerics guard but the BUDGET the stopping rule cut short, and that the run
    also lost a LOSO fold to a forward-pass overflow the clip could not reach.
    """
    record = _metrics().get(RULE_STOPPED_KEY)
    assert isinstance(record, dict), (
        f"{RULE_STOPPED_KEY} is missing from the committed metrics JSON. train_real.py carries "
        f"every superseded_* record across a re-run so a chain cannot lose a link."
    )
    assert record["co_bps"]["pooled"]["train_null"] == RULE_STOPPED_CO_BPS
    assert record["config"]["epochs_run"] == 12
    note = record["note"]
    assert isinstance(note, str) and "must not be quoted" in note.lower(), (
        "the superseded record must carry the warning that says how it may be used"
    )


def test_the_chain_has_all_four_links() -> None:
    """Four measurements, four labels, none deleted, and the live number is not one of them."""
    metrics = _metrics()
    for key in (SUPERSEDED_KEY, TRUNCATED_BUDGET_KEY, RULE_STOPPED_KEY):
        assert key in metrics, f"{key} was dropped from the supersession chain"
    live = metrics["co_bps"]["pooled"]["train_null"]
    for superseded in (VISIBLE_INPUT_CO_BPS, TRUNCATED_BUDGET_CO_BPS, RULE_STOPPED_CO_BPS):
        assert live != superseded, (
            f"the published pooled co-bps is {live}, which is a superseded value; a re-run must "
            f"replace the top-level measurement, not restore an old one"
        )
