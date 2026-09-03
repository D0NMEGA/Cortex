"""The committed decoder metrics artifact's contract (RD-03b, RD-04a, RD-04b, RD-05b, D-21).

Quick, offline and dataset-free: this module reads only the two committed JSON files, the phase's
``09-decoder-metrics.json`` and ``Decoder/manifests/indy_sessions.json``. No dataset, no checkpoint,
no training, no CoreML. It passes on a clean checkout with an empty ``Decoder/data/``, which is what
lets it be a blocking CI gate at all (D-18).

What it gates is SHAPE and PROVENANCE, never a measured value. The tier split (D-21, Phase 2 D-18,
Phase 6 D-10) leaves measured numbers to the committed evidence artifacts and the human runbook. A
schema test that also policed a measured value would go red on an honest re-measurement and would
end up tuned or deleted, which is how a gate stops meaning anything. The last test in this module
enforces that rule on this module.

Sibling modules, deliberately not duplicated here: ``test_cobps_margin.py`` owns the assertion
margin and its four superseded predecessors, ``test_manifest.py`` owns the manifest's own structure,
and ``Tools/scripts/decoder-policy.sh`` owns the same checksum agreement as a shell gate for the
non-Python CI path.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

_REPO_ROOT = Path(__file__).resolve().parents[2]
_METRICS_PATH = (
    _REPO_ROOT
    / ".planning"
    / "phases"
    / "09-real-data-ingest-ndt1-retrain-zenodo-3854034"
    / "09-decoder-metrics.json"
)
_MANIFEST_REL = "Decoder/manifests/indy_sessions.json"
_MANIFEST_PATH = _REPO_ROOT / _MANIFEST_REL

#: The palettizer skips any weight tensor with fewer elements than this (09-08).
_WEIGHT_THRESHOLD = 2048
#: The pre-registered one-sided lag sweep is 0..8 bins inclusive (D-08).
_LAG_SWEEP_POINTS = 9
#: The ridge grid is at least this wide before the GCV tie-breaker may fire.
_MIN_LAMBDA_SWEEP_POINTS = 5
#: A device string that names no iPad cannot carry the canonical latency label (D-17).
_CANONICAL_DEVICE_TOKEN = "iPad"
_LATENCY_STATUSES = ("corroborating", "canonical")


def _load(path: Path) -> dict[str, Any]:
    payload: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    return payload


def _metrics() -> dict[str, Any]:
    return _load(_METRICS_PATH)


def _manifest() -> dict[str, Any]:
    return _load(_MANIFEST_PATH)


def _metrics_session_ids(metrics: dict[str, Any]) -> set[str]:
    return {entry["id"] for entry in metrics["sessions"]}


def test_metrics_json_parses_and_declares_provenance() -> None:
    """RD-03c: the artifact parses and says what data and which manifest produced it."""
    metrics = _metrics()
    assert isinstance(metrics["schema_version"], int), (
        "RD-03c: schema_version must be an int so a future shape change is detectable; got "
        f"{type(metrics['schema_version']).__name__}"
    )
    assert metrics["data_source"] == "real", (
        "RD-03c: the committed headline artifact must declare data_source 'real'. A --smoke run "
        f"writes 'real-smoke', and a smoke number must never be published as the headline; got "
        f"{metrics['data_source']!r}"
    )
    assert metrics["manifest_path"] == _MANIFEST_REL, (
        f"RD-03c: manifest_path must name {_MANIFEST_REL}, the reproducibility record the "
        f"checksums below are checked against; got {metrics['manifest_path']!r}"
    )


def test_session_ids_and_checksums_match_the_manifest() -> None:
    """RD-03c: every number is pinned to bytes the manifest recorded, byte for byte."""
    metrics = _metrics()
    manifest = _manifest()
    manifest_sha = {entry["id"]: entry["sha256"] for entry in manifest["sessions"]}
    metrics_sha = {entry["id"]: entry["sha256"] for entry in metrics["sessions"]}

    unknown = sorted(set(metrics_sha) - set(manifest_sha))
    assert not unknown, (
        f"RD-03c: metrics name session(s) the manifest does not list: {unknown}. A number cannot "
        f"be pinned to bytes the reproducibility record never recorded."
    )
    declared_excluded = {entry["id"] for entry in metrics.get("excluded_sessions", [])}
    unaccounted = sorted(set(manifest_sha) - set(metrics_sha) - declared_excluded)
    assert not unaccounted, (
        f"RD-03c: manifest session(s) {unaccounted} appear in neither sessions nor "
        f"excluded_sessions. A session that silently vanished from a run is the difference "
        f"between a pooled number and a smaller one."
    )
    disagreements = {
        session_id: (sha, manifest_sha[session_id])
        for session_id, sha in metrics_sha.items()
        if manifest_sha[session_id] != sha
    }
    assert not disagreements, (
        f"RD-03c: checksum disagreement between the metrics and the manifest, as "
        f"{{session: (metrics, manifest)}}: {disagreements}. The published numbers were measured "
        f"on different bytes than the manifest pins."
    )


def test_per_session_cobps_covers_every_session() -> None:
    """RD-04a: every pooled session gets its own held-out number, not just the pooled one."""
    metrics = _metrics()
    per_session = metrics["co_bps"]["per_session"]
    assert set(per_session) == _metrics_session_ids(metrics), (
        f"RD-04a: co_bps.per_session covers {sorted(per_session)} but the run used "
        f"{sorted(_metrics_session_ids(metrics))}. A pooled number that hides which session "
        f"carried it is the claim this requirement exists to prevent."
    )
    for session_id, entry in sorted(per_session.items()):
        for null_name in ("train_null", "test_mean_null"):
            assert isinstance(entry.get(null_name), float), (
                f"RD-04a: co_bps.per_session[{session_id!r}].{null_name} must be a float, so the "
                f"session is scored against a named null rather than reported bare; got "
                f"{type(entry.get(null_name)).__name__}"
            )


def test_loso_is_a_full_rotation() -> None:
    """RD-04b: the leave-one-session-out rotation is complete and summarized with its spread."""
    metrics = _metrics()
    session_ids = _metrics_session_ids(metrics)
    folds = metrics["loso"]
    assert len(folds) == len(metrics["sessions"]), (
        f"RD-04b: {len(folds)} LOSO fold(s) for {len(metrics['sessions'])} session(s). A partial "
        f"rotation reports the transfer of whichever sessions happened to be held out."
    )
    held_out = [fold["held_out_session"] for fold in folds]
    assert len(set(held_out)) == len(held_out), (
        f"RD-04b: held_out_session repeats across folds: {held_out}. A repeated fold is a session "
        f"scored twice and another never held out at all."
    )
    assert set(held_out) == session_ids, (
        f"RD-04b: the rotation holds out {sorted(set(held_out))} but the run used "
        f"{sorted(session_ids)}; every session must take its turn."
    )
    summary = metrics["loso_summary"]
    for key in ("mean", "std", "min", "max", "folds"):
        assert key in summary, (
            f"RD-04b: loso_summary is missing {key!r}. A rotation reported without its spread "
            f"hides how much the folds disagreed."
        )


def test_config_records_the_training_knobs() -> None:
    """RD-03: the run records every knob needed to reproduce it, on the pinned seed."""
    config = _metrics()["config"]
    for key in (
        "epochs",
        "lr",
        "batch_size",
        "seq_len",
        "seed",
        "mask_ratio",
        "test_frac",
        "bin_ms",
    ):
        assert key in config, (
            f"RD-03: config is missing {key!r}. A published number whose training configuration is "
            f"not recorded cannot be reproduced."
        )
    # The epoch count is deliberately NOT pinned: D-14 permits raising the budget with a documented
    # rationale, and a test that forbade it would make the honest path fail.
    assert config["seed"] == 0, (
        f"RD-03: seed must be the pinned 0 that every committed decoder number was produced under; "
        f"got {config['seed']!r}"
    )


def test_velocity_section_is_complete() -> None:
    """RD-04: the velocity readout records its lag, its ridge selection and its null."""
    velocity = _metrics()["velocity"]
    assert isinstance(velocity["lag_bins"], int), (
        f"RD-04: velocity.lag_bins must be an int bin offset; got "
        f"{type(velocity['lag_bins']).__name__}"
    )
    assert isinstance(velocity["lag_ms"], float), (
        f"RD-04: velocity.lag_ms must state the same lag in milliseconds; got "
        f"{type(velocity['lag_ms']).__name__}"
    )
    assert len(velocity["lag_sweep"]) == _LAG_SWEEP_POINTS, (
        f"RD-04: the pre-registered lag sweep is {_LAG_SWEEP_POINTS} points (D-08); the artifact "
        f"records {len(velocity['lag_sweep'])}. A truncated sweep is a selection nobody can audit."
    )
    assert len(velocity["lambda_sweep"]) >= _MIN_LAMBDA_SWEEP_POINTS, (
        f"RD-04: the ridge grid must be at least {_MIN_LAMBDA_SWEEP_POINTS} points before a "
        f"tie-breaker may fire; the artifact records {len(velocity['lambda_sweep'])}."
    )
    held_out = velocity["heldout_r2"]
    assert {"vx", "vy", "pooled", "n"}.issubset(held_out), (
        f"RD-04: velocity.heldout_r2 must report both axes, the pooled value and the row count; "
        f"got keys {sorted(held_out)}"
    )
    assert set(velocity["per_session"]) == _metrics_session_ids(_metrics()), (
        f"RD-04: velocity.per_session covers {sorted(velocity['per_session'])}, not every session "
        f"in the run. A pooled decode number can be carried by one long session."
    )
    assert "TRAIN" in velocity["null"], (
        f"RD-04: velocity.null must name a TRAIN-split null, so the comparison cannot leak "
        f"held-out information; got {velocity['null']!r}"
    )


def test_palettization_reports_both_models() -> None:
    """RD-05b: both palettized models are reported, each labeled with the model it measures.

    Presence and labeling only. WHICH package ships is an open decision after 09-08's finding, and
    this test deliberately takes no position on it: it asserts that both deltas are on the record
    under their model names, not that either one is acceptable.
    """
    palettization = _metrics()["palettization"]
    reconstruction = palettization["reconstruction_model"]
    shipped = palettization["shipped_model"]

    for label, section, delta_key in (
        ("reconstruction_model", reconstruction, "nll_delta"),
        ("shipped_model", shipped, "r2_delta"),
    ):
        assert isinstance(section.get("model"), str) and section["model"], (
            f"RD-05b: palettization.{label} must carry a non-empty 'model' label. An unlabeled "
            f"delta cannot be attributed to the model it was measured on."
        )
        assert isinstance(section.get(delta_key), float), (
            f"RD-05b: palettization.{label}.{delta_key} must be a float. Both models' "
            f"palettization deltas are reported, not just the flattering one."
        )
        assert section["size_ratio"] > 1.0, (
            f"RD-05b: palettization.{label}.size_ratio is {section['size_ratio']}, so the "
            f"palettized package is not smaller than the fp16 one. That is a broken conversion, "
            f"not a compression result."
        )

    assert palettization["weight_threshold"] == _WEIGHT_THRESHOLD, (
        f"RD-05b: weight_threshold must stay {_WEIGHT_THRESHOLD}, the value the census and the "
        f"velocity-head exemption below were measured under; got "
        f"{palettization['weight_threshold']!r}"
    )
    assert palettization["velocity_head_palettized"] is False, (
        "RD-05b: velocity_head_palettized must be False. The 192-element readout is under the "
        "threshold, so a True here means the census and the delta describe different graphs."
    )


def test_ane_section_records_measurement_not_assumption() -> None:
    """RD-06: the ANE section is a scan of the real-data graph, not an inherited claim."""
    ane = _metrics()["ane"]
    assert ane["n_schedulable"] > 0, (
        f"RD-06: ane.n_schedulable is {ane['n_schedulable']}; a scan that found no schedulable op "
        f"did not read the graph."
    )
    assert isinstance(ane["cpu_only_ops"], int), (
        f"RD-06: ane.cpu_only_ops must be an int count, reported whatever it is; got "
        f"{type(ane['cpu_only_ops']).__name__}"
    )
    assert isinstance(ane["all_eligible"], bool), (
        f"RD-06: ane.all_eligible must be a bool verdict; got "
        f"{type(ane['all_eligible']).__name__}"
    )
    assert "real-data" in ane["provenance"], (
        f"RD-06: ane.provenance must name the real-data checkpoint it was scanned on. Phase 5's "
        f"tally came from a randomly-initialized graph, and the two must not be confusable; got "
        f"{ane['provenance']!r}"
    )


def test_latency_is_device_labeled_and_corroborating() -> None:
    """RD-06: a Mac latency is never presented as the canonical iPad-M4 number (D-17)."""
    latency = _metrics()["latency"]
    device = latency["device"]
    status = latency["status"]
    assert isinstance(device, str) and device, (
        "RD-06: latency.device must name the machine that produced the number. An unlabeled "
        "latency is the exact confusion D-17 exists to prevent."
    )
    assert status in _LATENCY_STATUSES, (
        f"RD-06: latency.status must be one of {list(_LATENCY_STATUSES)}; got {status!r}"
    )
    assert _CANONICAL_DEVICE_TOKEN in latency["canonical"], (
        f"RD-06: latency.canonical must name the {_CANONICAL_DEVICE_TOKEN} capture as the "
        f"canonical measurement, whether or not it has been taken yet; got "
        f"{latency['canonical']!r}"
    )
    if _CANONICAL_DEVICE_TOKEN not in device:
        assert status == "corroborating", (
            f"RD-06: latency was measured on {device!r}, which is not an "
            f"{_CANONICAL_DEVICE_TOKEN}, so its status must be 'corroborating'; got {status!r}. "
            f"A Mac number is not an iPad-M4 number and must never be labeled as one (D-17)."
        )


# Everything ABOVE the marker line below is scanned by the guard test that follows. The guard
# itself is excluded, because it has to name the patterns it forbids in order to forbid them.
# GUARD SPLIT MARKER: do not move or reword this line


def test_no_number_is_a_measured_threshold_assertion() -> None:
    """D-21: this module gates shape and provenance, never a measured value against a bar.

    A source self-check. The forbidden shapes are a co-bps, an R2 or a p99 compared with an
    inequality: those are the three measured quantities this phase publishes, and a CI gate that
    policed any of them would go red on an honest re-measurement and be tuned or deleted.
    """
    forbidden = (r"co_bps.*>", r"r2.*>", r"p99.*<")
    source = Path(__file__).read_text(encoding="utf-8")
    scanned, marker, _guard = source.partition(
        "# GUARD SPLIT MARKER: do not move or reword this line"
    )
    assert marker, "the guard split marker is gone, so this test scanned the whole file or nothing"
    assert "def test_palettization_reports_both_models" in scanned, (
        "the guard split marker moved above the tests it is supposed to scan"
    )

    offenders = [
        (number, line.strip(), pattern)
        for number, line in enumerate(scanned.splitlines(), start=1)
        for pattern in forbidden
        if re.search(pattern, line)
    ]
    assert not offenders, (
        f"D-21: this module compares a measured value against a bar: {offenders}. Schema tests "
        f"gate shape and provenance; measured numbers belong in the committed evidence artifacts "
        f"and the human runbook, where a re-measurement updates them instead of breaking the build."
    )
