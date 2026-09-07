---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 01
subsystem: data-ingest
tags: [zenodo, manifest, sha256, md5, integrity, pytest, indy, ndt1]

# Dependency graph
requires:
  - phase: 04-decoder-training
    provides: "download_indy.py, indy_sessions.json and ndt1.data.load_session (the 96-channel gate)"
provides:
  - "A corrected four-session manifest naming only confirmed 96-channel M1-only Indy sessions"
  - "size_bytes + zenodo_md5 on every session as publisher-side transport cross-checks"
  - "dropped_sessions recording why the two 192-channel M1+S1 April sessions were excluded"
  - "Magic-byte / size / md5 pre-checks in _process_session, all before any sha256 is taken"
  - "8 hermetic integrity tests plus 5 manifest-contract tests, no network and no dataset"
affects: [09-05 verified fetch, 09-02 loader fixture work, 09-09 decoder-policy gate, 09-10 evidence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Publisher-independent transport cross-check (Zenodo md5) verified BEFORE our own sha256 pin is trusted"
    - "Hermetic downloader tests: write the payload into tmp_path so dest exists and the network is never reached"
    - "Every refusal paired with a positive control, so a gate is proven to discriminate rather than always fail"

key-files:
  created:
    - Decoder/tests/test_download_integrity.py
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items.md
  modified:
    - Decoder/manifests/indy_sessions.json
    - Decoder/scripts/download_indy.py
    - Decoder/tests/test_manifest.py

key-decisions:
  - "Kept the plan's verbatim note text even though it makes the '192-channel M1+S1' grep return 3 lines instead of the acceptance criterion's 2; the verbatim mandate is the stronger instruction and both dropped sessions still record the reason"
  - "Factored the three pre-checks into a separate _check_payload helper rather than inlining them in _process_session, keeping that function readable at ~25 lines"
  - "Typed session dicts dict[str, Any] instead of dict[str, str]; size_bytes is an int, so the old annotation became false the moment the manifest contract changed"
  - "md5 is called with usedforsecurity=False and labelled a transport cross-check in source, in the manifest note and in the test docstrings, so it can never be read as an integrity control"

patterns-established:
  - "Pre-check ordering: cheapest and most diagnostic first (16 bytes read), then a stat, then a full streamed hash"
  - "A missing manifest contract key is a hard error, not a skipped check - absent cross-checks must not silently degrade to trust"

requirements-completed: [RD-01]

# Metrics
duration: 11min
completed: 2026-08-31
---

# Phase 9 Plan 01: Manifest Correction and Download Hardening Summary

**The Indy manifest now names only the four sessions that are actually 96-channel M1-only, and `download_indy.py` refuses an HTML error page, a truncated transfer or a mis-md5 payload before it can write that payload's checksum back as canonical.**

## Performance

- **Duration:** ~11 min
- **Started:** 2026-08-31T04:57Z
- **Completed:** 2026-08-31T05:09Z
- **Tasks:** 3/3
- **Files modified:** 3 modified, 2 created

## Accomplishments

### Task 1 - Manifest corrected to the four Option B sessions (commit `8fa4e72`)

`indy_20160407_02` and `indy_20160411_01` are 192-channel M1+S1 recordings that
`ndt1.data.load_session` is designed to reject, so two of the four previously-manifested sessions
could never have been ingested. They are replaced by `indy_20160624_03` and `indy_20160915_01`, and
recorded with their reason in a new top-level `dropped_sessions` key.

Every session now declares `size_bytes` and `zenodo_md5` alongside `sha256`. The four declared sizes
sum to 1,767,820,363 bytes, matching the plan's stated 1.77 GB exactly. `indy_20160630_01` carries
its already-verified sha256 (`2ca8f6b7...03ef6a8`), so Plan 09-05 will VERIFY that entry rather than
fill it; the other three remain `PENDING`.

The `note` no longer claims `indy_20160630_01` is the NLB'21 `mc_rtt` benchmark session (C-03:
`mc_rtt` is `indy_20170202_02` and is absent from Zenodo record 3854034). No replacement
session-identity claim was substituted.

### Task 2 - Three pre-checks before any checksum (commits `98ca301` RED, `926e630` GREEN)

Executed as TDD. RED committed a failing suite first: 3 failed (the new magic/size/md5 gates), 3
passed (the pre-existing sha256 pin and its matching-payload discriminator) - which shows the suite
discriminates rather than always failing.

GREEN added `_MAT73_MAGIC`, `_first_bytes`, `_md5_of` and a `_check_payload` helper called after the
possible download and before `_sha256_of`, in the order magic bytes, then size, then md5. A missing
`size_bytes` or `zenodo_md5` is itself a `ValueError`, since the manifest contract now requires both.
`hashlib.md5` is called with `usedforsecurity=False` and its docstring states plainly that md5 is a
publisher-side transport cross-check with no collision resistance (ASVS V6), never a security
control; the sha256 pin remains the integrity control. No refactor commit was needed - the code was
already factored into helpers.

`main()` was not touched: its existing explicit `except (OSError, urllib.error.URLError)` and
`except ValueError` clauses already carry the new failures, and no bare or blind `except` was
introduced anywhere (ruff `BLE` gate clean).

### Task 3 - Manifest and integrity contract pinned (commit `e81d5d8`)

`test_manifest.py` gained five additive tests (all existing tests kept): `size_bytes`/`zenodo_md5`
shape, the four selected ids in order, both dropped sessions with a `192-channel` reason, the absence
of any `mc_rtt` claim, and `sha256` being `PENDING` or 64 lowercase hex.
`test_download_integrity.py` reached 8 hermetic tests including the two missing-contract-key
refusals. None are marked `slow`; all run in the quick gate.

## Verification

Every command in the plan's `<verification>` block was run and exited 0, on a checkout with an empty
`Decoder/data/` (`ls Decoder/data/*.mat` matched nothing throughout):

| Command | Result |
|---------|--------|
| `uv sync --project Decoder --extra dev` | 0 |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 0 - 85 passed, 1 skipped, 9 deselected |
| `uv run --project Decoder ruff check Decoder` | 0 - all checks passed |
| manifest id list | `['indy_20160624_03', 'indy_20160627_01', 'indy_20160630_01', 'indy_20160915_01']` |

The one skip is pre-existing (`test_data.py:147`, "no real .mat present (dataset is gitignored)") and
is expected until Plan 09-05 fetches the data.

Success criteria: all five met. The four sessions carry the Zenodo-published `size_bytes` and
`zenodo_md5`; both dropped sessions are recorded with their reason and nothing is asserted about
`mc_rtt`; `_process_session` raises on a non-MATLAB payload, a size mismatch, an md5 mismatch and a
sha256 mismatch, and returns cleanly on a fully matching payload.

## Scope note on RD-01

This plan delivers the manifest-truth and integrity-gate half of RD-01. RD-01's "downloaded and
SHA-256-pinned, zero PENDING" half is Plan 09-05's verified fetch, enforced by `decoder-policy.sh`
in Plan 09-09. Three `PENDING` entries here are correct, not an omission.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 1 - Bug] `_process_session` session-dict type annotation was falsified by the new contract**

- **Found during:** Task 2
- **Issue:** the signature declared `session: dict[str, str]`, but this task adds `size_bytes`, an
  `int`. The annotation would have been a lie about the very field the new size check reads.
- **Fix:** changed to `dict[str, Any]` (matching how the test module already types it) and added the
  `typing.Any` import. `_check_payload` uses the same annotation.
- **Files modified:** `Decoder/scripts/download_indy.py`
- **Commit:** `926e630`

### Acceptance criterion superseded by the plan's own verbatim text

**2. `grep -F '192-channel M1+S1' Decoder/manifests/indy_sessions.json` returns 3 lines, not 2**

Task 1's acceptance criteria say this grep "matches twice", but Task 1 also mandates the `note`
field "exactly this text", and that mandated text itself contains the phrase ("Two previously-listed
April 2016 sessions were dropped as 192-channel M1+S1 (see dropped_sessions)"). The two requirements
cannot both hold. The verbatim-text instruction is the more explicit of the two, and the underlying
must-have - that the manifest records why each session was dropped - is satisfied: both
`dropped_sessions` entries carry the reason, which is what `test_manifest_records_dropped_sessions`
pins. The note was kept verbatim and the count is 3 (1 in `note`, 2 in `dropped_sessions`).

All other acceptance criteria across the three tasks matched exactly, including the counts that
distinguish this plan's work: `"id"` = 6, `"PENDING"` = 3, `mc_rtt` = 0, `20160407|20160411` = 2
lines (both inside `dropped_sessions`, none in `note`), and 8 `def test_` in the integrity module.

### Out-of-scope discovery (logged, not fixed)

`Decoder/tests/test_ane_compute_plan.py`'s `slow` tests are flaky: two consecutive runs each failed a
different test, and a third run passed 3/3 with no code change between them. Suspected cause is reuse
of the shared `Decoder/checkpoints/` build directory across CoreML compiles. These tests import only
`ndt1.*` and touch nothing this plan changed, and they are deselected from the quick gate this plan
verifies. Logged to `deferred-items.md` with a note that it deserves attention on its own merits,
since that module is the evidence gate behind the DEC-06 ANE-eligibility claim and a gate that
returns different verdicts on identical inputs cannot support a published number.

## Known stubs

| Stub | File | Reason |
|------|------|--------|
| Three `"sha256": "PENDING"` entries (`indy_20160624_03`, `indy_20160627_01`, `indy_20160915_01`) | `Decoder/manifests/indy_sessions.json` | Intentional and specified by the plan. A sha256 may only be written by a verified fetch, never guessed; Plan 09-05 fills them and Plan 09-09's `decoder-policy.sh` enforces zero-PENDING. `test_sha256_is_pending_or_64_hex` deliberately allows `PENDING` at this stage. |

No placeholder text, empty-value stubs, or unwired data paths were introduced. No number is published
by this plan: the `size_bytes` and `zenodo_md5` values are transcribed from the Zenodo API as recorded
in `09-RESEARCH.md`, and the one committed sha256 is the verified value from that same document.

## Threat flags

None. The change stays inside the plan's existing threat register: `T-09-01-01` (the three pre-checks)
and `T-09-01-03` (md5 labelled a transport cross-check) are implemented and each is pinned by a test;
`T-09-01-02` (the false `mc_rtt` claim) is removed from the manifest and pinned by
`test_manifest_note_makes_no_mc_rtt_claim`. No new network endpoint, auth path, or trust boundary was
introduced - `_first_bytes` and `_md5_of` only read a local file that `_process_session` already
opened.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | `8fa4e72` | fix(09-01): correct indy_sessions.json to the four confirmed M1-only sessions |
| 2 (RED) | `98ca301` | test(09-01): add failing magic-byte, size and md5 gates for download_indy |
| 2 (GREEN) | `926e630` | feat(09-01): refuse a non-MATLAB, mis-sized or mis-md5 payload before checksumming |
| 3 | `e81d5d8` | test(09-01): pin the manifest contract and the missing-key refusals |

## Self-Check: PASSED
