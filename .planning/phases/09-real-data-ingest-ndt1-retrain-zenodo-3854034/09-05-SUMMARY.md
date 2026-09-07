---
status: PARTIAL
agent: donny-executor
phase: 09-real-data-ingest-ndt1-retrain-zenodo-3854034
plan: 05
subsystem: data-ingest
tags: [zenodo, indy, sha256, md5, integrity, negative-controls, rd-01, evidence]

# Dependency graph
requires:
  - phase: 09-01
    provides: "the corrected four-session manifest, the size/md5/magic pre-checks in download_indy.py, and the pre-filled indy_20160630_01 sha256 reference"
provides:
  - "1,767,820,363 bytes of real Indy M1 spike data materialized under the gitignored Decoder/data/"
  - "Four 64-hex sha256 pins in indy_sessions.json, zero PENDING"
  - "09-ingest-evidence.md: the RD-01 provenance record with five verbatim negative-control transcripts"
  - "Locally measured per-session durations and 20 ms bin counts (285,359 total) confirming the 09-RESEARCH remote header probe"
affects: [09-06 loader/kinematics on real sessions, 09-07 retrain, 09-08 LOSO, 09-09 decoder-policy.sh pin enforcement, 09-10 evidence]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A pre-filled reference checksum kept in the manifest so the first real run VERIFIES a known-good value rather than only writing new ones"
    - "Layered integrity controls tested one layer at a time: when the outer transport check fires first, neutralize it honestly (re-derive it from the corrupted bytes) to reach the inner gate, rather than concluding the inner gate works"
    - "Negative controls on a mktemp scratch copy with a session-scoped --manifest/--out, so the real dataset is never placed in a corrupted state"

key-files:
  created:
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/09-ingest-evidence.md
    - .planning/phases/09-real-data-ingest-ndt1-retrain-zenodo-3854034/deferred-items-09-05.md
  modified:
    - Decoder/manifests/indy_sessions.json

key-decisions:
  - "Split the plan's Control 1 into 1a and 1b. A single flipped byte trips the md5 transport pre-check first, so Control 1 as written could never exercise the sha256 pin on real bytes. 1b re-derives size_bytes and zenodo_md5 from the corrupted file so both transport checks pass, isolating the T-04-02-01 gate."
  - "Measured durations and 20 ms bin counts from the fetched files with h5py rather than transcribing them from 09-RESEARCH; they reproduce the remote probe exactly and 285,359 total bins now rests on local measurement"
  - "Kept the six non-ASCII characters that appear inside the transcript blocks (the downloader's own em dash and its truncation ellipsis). Editing them to satisfy the ASCII prose rule would falsify verbatim evidence; all prose outside the fenced blocks is ASCII"
  - "Logged the cosmetic doubled-session-id stderr formatting to deferred-items-09-05.md rather than fixing it, since download_indy.py is outside this plan's declared files_modified and was owned by a concurrent wave"

patterns-established:
  - "A published byte count or checksum needs no device annotation, and the evidence artifact says so explicitly rather than leaving the omission unexplained"

requirements-completed: [RD-01]

# Metrics
duration: 15min
completed: 2026-08-31
---

# Phase 9 Plan 05: Verified Indy ingest and SHA-256 pinning Summary

**The repository now holds 1.77 GB of real primate M1 spike recordings whose every byte is pinned by a committed SHA-256, and the integrity gate that guards those pins was proven to refuse a one-bit corruption, a 127-byte truncation and an HTML error page on a real fetched file while still passing the pristine one.**

## Performance

- **Duration:** ~15 min (924 s wall, of which roughly 8 min was the 1.38 GB transfer)
- **Started:** 2026-08-31T05:20Z
- **Completed:** 2026-08-31T05:35Z
- **Tasks:** 2/2
- **Files:** 1 modified, 2 created

## Accomplishments

### Task 1 - Four sessions materialized, three pins filled, one verified (commit `ca6e1bb`)

Disk was checked first: 112 GB free against the plan's 3 GB floor. The pre-fetched
`indy_20160630_01.mat` was moved (not copied) out of the research scratchpad into `Decoder/data/`,
and hashed to `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8`, matching the pin
Plan 09-01 had committed. The remaining three were fetched from Zenodo record 3854034.

The run printed exactly what the plan required it to print:

```
indy_20160624_03: fetched, sha256 filled (65937e0cea18…)
indy_20160627_01: fetched, sha256 filled (b1a2404f2510…)
indy_20160630_01: verified (2ca8f6b7fcfc…)
indy_20160915_01: fetched, sha256 filled (76175e5bf851…)
manifest updated with filled checksums
```

`indy_20160630_01` says `verified`, not `filled`. Its pre-filled pin was checked against the bytes on
disk and left untouched, which is what makes the three newly-computed pins credible: the same code
path that wrote them was simultaneously shown to reproduce a known-good reference value.

The four files total **1,767,820,363 bytes**, matching the manifest `size_bytes` sum exactly, and all
four locally-computed md5 values match the Zenodo-published checksums. The manifest carries four
64-hex pins and zero `"PENDING"`.

**Idempotence was proven against the committed manifest**, not against the working tree. Running the
downloader before committing would have shown a non-empty `git diff` for Task 1's own change and
proven nothing. The manifest was committed first, then the downloader re-run: exit 0, four `verified`
lines, zero `manifest updated` lines, and `git diff --stat Decoder/manifests/indy_sessions.json`
empty.

### Task 2 - Five negative controls on a real fetched file (commit `d92e849`)

All controls ran against a copy of the smallest session (106,555,127 bytes) in a `mktemp -d` scratch
tree with a session-scoped `--manifest` and `--out`. `Decoder/data/` was never placed in a corrupted
state, and the tree was re-verified afterwards.

| Control | Mutation | Layer that caught it | Exit |
|---|---|---|---|
| 1a | one bit flipped at offset 60,000,000 | `zenodo_md5` transport pre-check | 1 |
| 1b | the same corruption, transport checks made to pass | the committed `sha256` pin (T-04-02-01) | 1 |
| 2 | truncated to 106,555,000 bytes (127 short) | `size_bytes` | 1 |
| 3 | overwritten with a 46-byte HTML body | `MATLAB 7.3 MAT-f` magic bytes | 1 |
| 4 | none (positive control) | nothing; printed `verified` | 0 |

Control 4 is what makes the other four mean something: without it they would prove only that the
script can fail, not that it discriminates. It also confirmed no manifest writeback occurred on a
verified-not-filled path.

`09-ingest-evidence.md` (253 lines) carries the environment table, the four-session table with full
checksums, the locally-measured durations and bin counts, the dropped-session rationale, the mc_rtt
correction, all five verbatim transcripts, and a reproduce section.

## Verification

Every command in the plan's `<verification>` block was run and exited 0:

| Command | Result |
|---------|--------|
| `uv sync --project Decoder --extra dev` | 0 |
| `uv run --project Decoder python Decoder/scripts/download_indy.py` | 0, four `verified` lines |
| `grep -c '"PENDING"' Decoder/manifests/indy_sessions.json` | 0 |
| `uv run --project Decoder pytest Decoder/tests -m "not slow" -q` | 0, 97 passed, 9 deselected |
| `git status --porcelain Decoder/data \| wc -l` | 0 |

Both tasks' `<automated>` verification blocks passed verbatim, including the byte-total assertion
(`all four sessions verified, 1767820363 bytes`) and the evidence-artifact token scan
(`evidence artifact OK`). Every acceptance criterion across both tasks matched, including
`grep -cE 'co-bps|co_bps|R2|p99'` returning 0 (no decoder metric leaked into the ingest artifact) and
`git ls-files '*.mat'` returning only `Decoder/tests/fixtures/tiny_v73.mat`.

The quick suite's one pre-existing skip (`test_data.py`, "no real .mat present") is gone: with the
dataset materialized that test now executes against a real session. The plan flagged this as the
regression signal for Plan 09-04's `available_sessions` repair; the suite passes rather than erroring,
so nothing regressed. Note that 09-04 ran concurrently in a separate worktree, so this result reflects
the main tree without its merge.

All five plan success criteria are met.

## Deviations from Plan

### Auto-fixed issues

**1. [Rule 2 - Missing critical functionality] Control 1 as written could not test the sha256 gate**

- **Found during:** Task 2
- **Issue:** the plan's Control 1 flips a byte and expects `checksum mismatch for indy_20160915_01`.
  It cannot produce that message. `_check_payload` runs the md5 transport check before any sha256 is
  computed, so a flipped byte always trips md5 first. The plan half-anticipated this ("record whichever
  message appears and say which layer caught it"), but its own acceptance criterion requires
  `checksum mismatch` in the evidence file. Run as written, the T-04-02-01 gate that guards every
  committed pin would have gone untested on real bytes, which is the one thing this task exists to test.
- **Fix:** split into two controls against the same genuinely corrupted file. 1a uses the honest
  manifest and records that the md5 layer bites first (defense in depth working as designed). 1b
  re-derives `size_bytes` and `zenodo_md5` from the corrupted bytes so both transport checks pass,
  leaving the committed `sha256` as the only remaining gate; it raises
  `checksum mismatch for indy_20160915_01`. Both transcripts are committed and the artifact states
  plainly which layer caught which, and why 1b's manifest was mutated.
- **Files modified:** `09-ingest-evidence.md`
- **Commit:** `d92e849`

**2. [Rule 3 - Blocking] Idempotence check was unsatisfiable in the plan's stated order**

- **Found during:** Task 1
- **Issue:** step 1d requires `git diff --stat Decoder/manifests/indy_sessions.json` to be empty after
  the second run, but step 1c fills three pins and the commit is only described afterwards. Against
  `HEAD` the diff necessarily showed Task 1's own three-line change, so the check as ordered could
  never pass and would have been either falsely reported or silently skipped.
- **Fix:** committed the manifest first, then re-ran the downloader. The diff is then empty against
  the commit, which is the stronger claim the check was reaching for: the second run changed nothing
  relative to what was pinned. Both the pre-commit run (four `verified`, no `manifest updated`) and
  the post-commit run (empty diff) are recorded.
- **Files modified:** none beyond the commit ordering
- **Commit:** `ca6e1bb`

### Deliberate departures from a stated style rule

**3. Six non-ASCII characters remain in `09-ingest-evidence.md`**

The project prose rule is ASCII-only, no em dashes. Six lines break it, and all six are inside fenced
transcript blocks: the downloader's own error string contains an em dash, and its progress lines use a
truncation ellipsis. Rewriting them would make the transcripts non-verbatim, which defeats the purpose
of an evidence artifact whose whole claim is that the output is real. All prose outside the fenced
blocks is ASCII-clean, verified by `LC_ALL=C grep -c '[^ -~]'` returning matches on transcript lines
only.

### Out-of-scope discovery (logged, not fixed)

`download_indy.py` prints the session id twice on every failure line
(`indy_20160915_01: indy_20160915_01: size mismatch ...`), because `main()` prefixes the id onto
messages that already begin with it. Purely cosmetic; every gate, exit code and diagnostic value is
correct. Not fixed because that file is outside this plan's declared `files_modified` and was owned by
a concurrently-running wave. Logged to `deferred-items-09-05.md` with the caveat that
`test_download_integrity.py` asserts on message substrings, so the id must survive in exactly one
place.

## Known Stubs

None. Plan 09-01's three `"PENDING"` sha256 entries were the outstanding stub in this subsystem and
this plan removed all three by fetching and hashing real bytes. No placeholder value, mock payload or
unwired path was introduced.

Every checksum in the manifest and in the evidence artifact was computed by `shasum -a 256` or by
`hashlib.sha256` from bytes physically present under `Decoder/data/`. None was copied from another
document, inferred, or guessed. The one pin this plan did not compute, `indy_20160630_01`, was
independently recomputed from disk and found equal to the committed value.

## Threat Flags

None. The work stays inside the plan's threat register and closes the four `mitigate` dispositions:
T-09-05-01 (corrupted payload pinned as canonical) is refuted by Controls 1a/1b/2/3 plus the
idempotent re-verification; T-09-05-02 (partial transfer hashed as-is) is exercised directly by
Control 2's `truncate`; T-09-05-03 (untraceable published number) is closed by all four sha256 values
appearing in both the manifest and the evidence artifact; T-09-05-04 (dataset committed to git) is
held by `git status --porcelain Decoder/data` returning 0 lines and `git ls-files '*.mat'` returning
only the tracked fixture. T-09-05-05 (controls corrupting the real dataset) is held by the scratch-tree
discipline and the post-control re-verification.

No new network endpoint, auth path, or trust boundary was introduced. The only remote fetch is the
same direct Zenodo file URL the manifest already declared, over HTTPS, with the `/api/` refusal
already built into `_download`.

## Commits

| Task | Commit | Message |
|------|--------|---------|
| 1 | `ca6e1bb` | feat(09-05): fill the three PENDING sha256 pins from verified fetched bytes |
| 2 | `d92e849` | docs(09-05): record the RD-01 ingest with five negative-control transcripts |

## Status rationale

`PARTIAL` rather than `PASS` on a strict reading of the contract: one deferred item was logged. Every
must-have, every acceptance criterion, every task verification block and every command in the plan's
verification section is green, and no work was left unfinished. The single gap is the cosmetic stderr
formatting note above, which lives in a file this plan was not permitted to touch.

## Self-Check: PASSED

- `Decoder/manifests/indy_sessions.json` present, 4 filled pins, 0 `"PENDING"`
- `.planning/phases/09-.../09-ingest-evidence.md` present, 253 lines (min 90)
- `.planning/phases/09-.../deferred-items-09-05.md` present
- `Decoder/data/*.mat` present, 4 files, 1,767,820,363 bytes, all four digests re-verified from disk
- Commits `ca6e1bb` and `d92e849` both present in `git log`
- No `.mat` staged or tracked beyond `Decoder/tests/fixtures/tiny_v73.mat`
- `.planning/STATE.md`, `.planning/ROADMAP.md` and `.planning/config.json` left modified-but-unstaged, as the orchestrator owns them
