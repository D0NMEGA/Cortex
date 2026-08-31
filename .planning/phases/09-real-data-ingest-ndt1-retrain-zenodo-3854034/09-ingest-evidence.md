# Phase 9 RD-01 evidence: the four Indy M1-only sessions, materialized and pinned

**Date:** 2026-08-31
**Result:** PASS. All four selected sessions from Zenodo record 3854034 are on disk under the
gitignored `Decoder/data/`, totalling **1,767,820,363 bytes**. `Decoder/manifests/indy_sessions.json`
carries **four 64-hex SHA-256 pins and zero `"PENDING"`** entries. The integrity gate was proven to
bite on a real fetched file and to discriminate.

This is the moment the repository stops being a decoder that has only ever seen structured noise.
Every number Phase 9 goes on to publish is traceable to the exact bytes pinned below.

**This artifact contains only byte counts, checksums, and file-header facts.** It publishes no
decoder metric, so no device annotation is required for its numbers. The measurements here were taken
on the machine in the environment table; a checksum is machine-independent by construction, and the
durations and bin counts are properties of the files, not of the host.

---

## Environment

| Field | Value |
|-------|-------|
| **Machine** | Apple M5 Pro (`arm64`), macOS **26.5** (build 25F71, `Darwin 25.5.0`, `xnu-12377.121.6~2`) |
| **Compute** | Not applicable. Nothing here is timed or accelerated; the work is HTTPS transfer plus streamed hashing. |
| **Interpreter** | CPython **3.12.13** (`uv`-managed, `uv 0.11.21`) |
| **numpy** | **2.4.6** |
| **h5py** | **3.16.0** (used only for the header cross-check in the session table) |
| **Fetch tool** | `Decoder/scripts/download_indy.py` at commit `6a3267d` (Plan 09-01), stdlib `urllib.request`, 1 MiB streamed chunks |
| **Source** | Zenodo record 3854034, O'Doherty / Cardoso / Makin / Sabes 2020, CC-BY-4.0. Files immutable since 2020-05-26. |
| **Determinism** | Not seeded and not needed. SHA-256 over fixed bytes is deterministic by construction; the run was repeated and produced identical digests. |

---

## Session set

Byte sizes are `stat` on the fetched files. The md5 column is the checksum Zenodo publishes for each
file, re-derived locally with `md5 -q` and matching in all four cases. The SHA-256 column is the
committed reproducibility pin, computed by `download_indy.py` from the bytes on disk.

| id | size_bytes | zenodo md5 | sha256 |
|---|---|---|---|
| `indy_20160624_03` | 143,970,619 | `9aa921f0788f6ccd32a1b8808c18eabd` | `65937e0cea184b3307a19f84b4d9b44530c95e756e6b42bfad6cc8d55c3bf93f` |
| `indy_20160627_01` | 1,135,050,817 | `de58797d649bdf2bec589c074ee991d2` | `b1a2404f2510475f244077bfc30efbd80148e784ea9263b88f348a8bb15c71e8` |
| `indy_20160630_01` | 382,243,800 | `197413a5339630ea926cbd22b8b43338` | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| `indy_20160915_01` | 106,555,127 | `ef6a95c5a1a8d2126b90f5be0505e398` | `76175e5bf851c123af29178fa7c483588e911a000615438bff97d6f2f2591408` |
| **total** | **1,767,820,363** | | |

`indy_20160630_01`'s pin was pre-filled by Plan 09-01 from an earlier verified fetch. This run
**verified** it rather than writing it: the downloader printed `verified` for that session and
`fetched, sha256 filled` for the other three, and the digest recomputed from the bytes now under
`Decoder/data/` is byte-for-byte the value Plan 09-01 committed. That is the point of keeping one pin
pre-filled. It turns the run into a test of the checksum pipeline against a known-good reference,
which is what makes the three newly-computed values credible.

### Recording length and bin budget

Durations and bin counts below were **measured from the fetched files** in this run (h5py 3.16.0,
`t[-1] - t[0]`), not transcribed. They reproduce the remote header probe recorded in
`09-RESEARCH.md` exactly. `complete 20 ms bins` is `floor(duration / 0.02)`, the count of whole bins,
which is the convention the manifest `note` uses.

| id | `spikes` shape | `chan_names` | duration (s) | complete 20 ms bins |
|---|---|---|---|---|
| `indy_20160624_03` | `(5, 96)` | `(1, 96)` | 499.9960 | 24,999 |
| `indy_20160627_01` | `(5, 96)` | `(1, 96)` | 3362.9440 | 168,147 |
| `indy_20160630_01` | `(5, 96)` | `(1, 96)` | 1463.2320 | 73,161 |
| `indy_20160915_01` | `(5, 96)` | `(1, 96)` | 381.0440 | 19,052 |
| **total** | | | 5707.2160 | **285,359** |

All four are 96-channel, matching `CORTEX_CHANNEL_COUNT`. The calendar span is
**2016-06-24 to 2016-09-15**, 83 days.

---

## Why two sessions were dropped

The manifest as it stood before Plan 09-01 listed `indy_20160407_02` and `indy_20160411_01`. Both are
**192-channel M1+S1** recordings: their `chan_names` run `M1 001` through `S1 096`, so the channel
axis carries two arrays, not one. `ndt1.data.load_session` enforces width equal to
`CORTEX_CHANNEL_COUNT` (96) and raises `ValueError` on such a file. The loader is correct and the old
manifest was wrong, so those two sessions could never have been ingested. They are recorded with
their reason under the manifest's `dropped_sessions` key and replaced by `indy_20160624_03` and
`indy_20160915_01`.

**The M1 subset of a 192-channel M1+S1 session was not sliced out**, and this was a deliberate
choice rather than an oversight. Slicing 96 M1 columns out of a 192-channel recording would mix a
different array configuration into a pool whose whole premise is a stable channel-to-neuron identity
across sessions. That is the "reshape the dataset until it fits" move that decision D-03 forbids.
The available substitute pool was large enough that no such compromise was needed: nine confirmed
96-channel M1-only sessions exist in the record, and four were selected.

---

## What is not claimed

**`indy_20160630_01` is not the NLB'21 `mc_rtt` benchmark session.** That session is
`indy_20170202_02`, and it is not in Zenodo record 3854034 at all. Earlier project documents asserted
the identity; Plan 09-01 removed the claim from the manifest `note` and pinned its absence with a
test. No replacement session-identity claim is substituted here. These are Indy sessions from the
same laboratory and the same paradigm as the benchmark, and nothing more than that.

**`zenodo_md5` is a transport cross-check, never a security control.** md5 has no collision
resistance, so it cannot detect a deliberately crafted substitute. Its value is that it is
independent: it comes from the publisher rather than from our own first fetch, so it catches a
corrupted mirror that a self-computed SHA-256 would happily canonicalize. The committed SHA-256 is
the integrity control. `download_indy.py` calls md5 with `usedforsecurity=False` to make that
explicit in code.

**A checksum says nothing about scientific content.** These pins establish that the bytes analyzed
downstream are the bytes Zenodo published. Whether the recordings support any particular decoding
result is the business of the later plans in this phase, not of this artifact.

---

## Negative controls

Five transcripts, in the `--self-test` tradition the project has used for its policy gates since
Phase 1. Each ran against a copy of the smallest session (`indy_20160915_01.mat`, 106,555,127 bytes)
in a `mktemp -d` scratch tree with a session-scoped `--manifest` and `--out`, so `Decoder/data/` was
never placed in a corrupted state. All output is verbatim.

### Control 1a: one flipped bit, honest manifest (the md5 layer bites first)

One bit was flipped at byte offset 60,000,000, far past the 16-byte header, leaving the file size
unchanged at 106,555,127 bytes and the magic bytes intact (`MATLAB 7.3 MAT-f`).

```
$ uv run --project Decoder python Decoder/scripts/download_indy.py --manifest "$SCRATCH/manifest.json" --out "$SCRATCH"
indy_20160915_01: indy_20160915_01: md5 mismatch vs the Zenodo-published checksum - expected ef6a95c5a1a8d2126b90f5be0505e398, got 0d7d6d47e1ddd305038d9c4d8d083987
exit=1
```

The layer that caught it is the **publisher md5 pre-check**, not the SHA-256 pin, because the
pre-checks deliberately run first so that a bad payload is refused before it can be checksummed as
canonical. Recording which layer fired matters: a single corruption trips the outermost gate, and the
inner gate is left untested by this control. Control 1b tests it directly.

### Control 1b: the same flipped bit, isolated against the committed SHA-256 pin

To reach the inner gate, the scratch manifest's `size_bytes` and `zenodo_md5` were re-derived from
the corrupted file so both transport pre-checks pass, while `sha256` was left at the value committed
in `Decoder/manifests/indy_sessions.json`. The file under test is the same genuinely corrupted
106,555,127-byte payload.

```
$ uv run --project Decoder python Decoder/scripts/download_indy.py --manifest "$SCRATCH/manifest.json" --out "$SCRATCH"
indy_20160915_01: checksum mismatch for indy_20160915_01: expected 76175e5bf851c123af29178fa7c483588e911a000615438bff97d6f2f2591408, got b43d9d78d58915cb23af82069d872b231332dc5570df062782367b3bb39450d1 — the downloaded .mat is corrupt or tampered (integrity gate T-04-02-01)
exit=1
```

This is the T-04-02-01 gate, exercised on real fetched bytes rather than on a hermetic fixture. A
single flipped bit in 106 MB is refused.

### Control 2: truncated transfer against `size_bytes`

The pristine copy was restored and truncated to 106,555,000 bytes, 127 bytes short. The HDF5 header
is untouched, so the magic-byte check still passes and the size check is what fires. This is the
interrupted-transfer case: `_process_session` skips the download when the destination already exists,
so a partial leftover would otherwise be hashed as-is.

```
$ truncate -s 106555000 "$SCRATCH/indy_20160915_01.mat"
$ uv run --project Decoder python Decoder/scripts/download_indy.py --manifest "$SCRATCH/manifest.json" --out "$SCRATCH"
indy_20160915_01: indy_20160915_01: size mismatch - expected 106555127 bytes, got 106555000 (truncated or partially-written transfer)
exit=1
```

### Control 3: an HTML error page against the magic bytes

The copy was overwritten with a 46-byte HTML body, standing in for a Zenodo maintenance or
rate-limit response served with a 200 status.

```
$ printf '<!DOCTYPE html><html>Zenodo maintenance</html>' > "$SCRATCH/indy_20160915_01.mat"
$ uv run --project Decoder python Decoder/scripts/download_indy.py --manifest "$SCRATCH/manifest.json" --out "$SCRATCH"
indy_20160915_01: indy_20160915_01: payload is not a MATLAB v7.3 .mat - first bytes were b'<!DOCTYPE html><', expected b'MATLAB 7.3 MAT-f' (a Zenodo error page or truncated transfer must never be checksummed as canonical)
exit=1
```

### Control 4: the discriminator (positive control)

The pristine copy and the honest manifest were restored and the identical command re-run. Without
this, the three refusals above would prove only that the script can fail, not that it distinguishes a
good payload from a bad one.

```
$ uv run --project Decoder python Decoder/scripts/download_indy.py --manifest "$SCRATCH/manifest.json" --out "$SCRATCH"
indy_20160915_01: verified (76175e5bf851…)
exit=0
$ diff -q "$SCRATCH/manifest.json" "$SCRATCH/manifest-template.json"
identical (no writeback: the pin was verified, not filled)
```

### Post-control state of the real dataset

The scratch tree was removed and the real tree re-verified. Nothing under `Decoder/data/` was
mutated at any point.

```
$ uv run --project Decoder python Decoder/scripts/download_indy.py
indy_20160624_03: verified (65937e0cea18…)
indy_20160627_01: verified (b1a2404f2510…)
indy_20160630_01: verified (2ca8f6b7fcfc…)
indy_20160915_01: verified (76175e5bf851…)
exit=0
$ cat Decoder/data/*.mat | wc -c
 1767820363
$ git status --porcelain Decoder/data | wc -l
       0
```

---

## Reproduce

`Decoder/data/` is gitignored, so a fresh clone starts empty and materializes the dataset from the
committed manifest. Roughly 1.77 GB is transferred on a cold run; budget about 3 GB of free disk.

```bash
uv sync --project Decoder --extra dev
uv run --project Decoder python Decoder/scripts/download_indy.py
```

On a cold run this prints `fetched, sha256 filled` for any session whose pin is still `"PENDING"` and
`verified` for the rest. Against the manifest as committed by this plan, all four pins are filled, so
every session prints `verified` and the manifest is not rewritten.

**A re-run verifies rather than re-fetches.** `_process_session` skips the network entirely when the
destination file already exists, so the second and every later invocation is a pure integrity check
over the bytes on disk. That is why the command is safe to repeat and why it is the right gate to
run before any training job. The corollary is that a partially-written file from an interrupted
transfer is *not* re-fetched either; it is caught by the `size_bytes` check exercised in Control 2.
If a transfer is interrupted, delete the partial file and re-run.

Independent spot-check without the project environment:

```bash
shasum -a 256 Decoder/data/*.mat     # must match the sha256 column above
md5 -q Decoder/data/*.mat            # must match the zenodo md5 column above
cat Decoder/data/*.mat | wc -c       # must be 1767820363
```

Verification run alongside this artifact, all exiting 0:

```bash
uv run --project Decoder pytest Decoder/tests -m "not slow" -q   # 97 passed, 9 deselected
grep -c '"PENDING"' Decoder/manifests/indy_sessions.json         # 0
git status --porcelain Decoder/data | wc -l                      # 0
```

The quick suite previously reported one skip, `test_data.py` "no real .mat present (dataset is
gitignored)". With the dataset materialized that test now executes against a real session instead of
skipping, which is the first direct sign that RD-01 changed what the test suite is actually covering.
