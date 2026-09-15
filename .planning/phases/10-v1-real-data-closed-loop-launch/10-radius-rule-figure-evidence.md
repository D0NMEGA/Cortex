# Phase 10 radius-rule figure: provenance and reproduction record

**Date:** 2026-09-15
**Quick task:** `260915-fk9`
**Artifact:** `docs/media/radius-rule.gif` plus two stills
**Generator:** `Decoder/scripts/radius_rule_figure.py`

## What the figure is, and what it is not

The figure replays one excerpt of a recorded session twice, side by side, under two acceptance
rules. Both panes show the **animal's own recorded hand**.
The figure is **not a decoder output**, and neither pane is one.
Nothing in the generator loads a model, and no decoded trajectory appears in any frame.

It is an **open-loop replay of a recorded session; the subject was not in the loop**. Recorded
spikes and a recorded hand cannot react to anything, so the figure says nothing about closed-loop
control at any radius, and may not be cited as closed-loop evidence.

The 951/1025 (92.8%) that the 7.50 mm rule scores is **what the recorded hand achieves**. It is a
control for the acceptance rule, not a decode result, and may not be quoted as one. The repository's
decode-attributable result on this session remains 0 of 1,025.

## Provenance

| Field | Value |
|---|---|
| Session | `indy_20160630_01` |
| Source sha256 | `2ca8f6b7fcfc5837bfbedd5aae16ee599872337fed099d300487d183003ef6a8` |
| Manifest the generator reads it from | `Decoder/manifests/indy_sessions.json` |
| Local path (gitignored, 382,243,800 bytes) | `Decoder/data/indy_20160630_01.mat` |
| Dataset | O'Doherty/Makin Indy M1, Zenodo 3854034 |

The source sha256 is the same value carried by `10-ceiling.json`, so this figure and the
pre-registered recorded-cursor replay name the same bytes.

## The two acceptance radii

| Radius | Where it comes from |
|---|---|
| 2.8613660406415042 mm | Half of the 30x30 Webgrid cell. The grid is sized from the recorded cursor excursion box, side 171.68196243849025 mm, so the cell is 5.7227320812830085 mm and the radius is half of it. Cursor-derived, not target-derived. |
| 7.50 mm | Exactly half the task's own 15 mm target pitch. The generator does not hardcode the relationship; it asserts `abs(R_TASK - PITCH/2) < 1e-9` against the pitch it recovers from the session, so the disc is exactly inscribed in a task cell. |

Note the labelling, because it is easy to get wrong: **5.723 mm is the 30x30 cell and 2.861 mm is
its half-cell**, which is the acceptance radius. The figure's own on-screen arithmetic is
`15 / 5.723 = 2.6211`, the cell that does not divide the target pitch.

## The excerpt-selection rule

No human chose the excerpt. The generator enumerates every contiguous window of 14 trials whose
total duration is at most 24 s, computes for each of the two radii the absolute deviation of the
window hit rate from that radius's full-session hit rate relative to the session rate, takes the
larger of the two deviations, and selects the window that minimises it. The full-session totals are
rendered into every frame alongside the window counters, so the excerpt cannot be read without them.

## Counts printed by this run

| Radius | Window (14 trials) | Full session |
|---|---|---|
| r = 2.8614 mm | 2/14 | 147/1025 |
| r = 7.5000 mm | 13/14 | 951/1025 |

Selected window: contiguous trials 29-42, 21.4 s realtime. Output: 537 frames at 912x532.

Every number above is re-derived from the `.mat` at render time, not transcribed. The generator
asserts its own end state before writing: that the animation's final on-screen counter for each
radius equals the independently recomputed window truth, plus the 8x8 64-target lattice, the 15 mm
pitch uniformity, and `R_TASK == PITCH/2`. The run exited 0, so all of those held.

## Machine and resolved versions

| Field | Value |
|---|---|
| Machine | Apple M5 Pro |
| Architecture | arm64 |
| macOS | 26.5 |
| Python | 3.12.13 (Clang 22.1.3) |
| matplotlib | 3.11.2 |
| pillow | 12.3.0 |
| numpy | 2.4.6 |
| h5py | 3.16.0 |
| gifsicle (measurement only) | 1.96 |

This is a **Mac render, not an iPad-M4 number**, and it carries no performance claim of any kind.
matplotlib and pillow are deliberately unpinned (see D-A below), which is exactly why their resolved
versions are recorded here: if the figure is ever regenerated and the output differs, this file says
what the shipped bytes were rendered with.

## Reproduce

Run from the repository root, with the session `.mat` materialized under `Decoder/data/`:

```bash
uv run --project Decoder --with matplotlib --with pillow \
  python Decoder/scripts/radius_rule_figure.py docs/media/radius-rule.gif
```

The two analysis scripts need neither matplotlib nor pillow:

```bash
uv run --project Decoder python Decoder/scripts/grid_shift_search.py
uv run --project Decoder python Decoder/scripts/grid_sync_drift.py
```

### Reproduction result: byte-identical

The committed generator was rerun on 2026-09-15 after the ruff reformat, writing to a scratch path,
and the result was compared against the shipped bytes:

```
7bab0426ab76e88bdbbf2dcc0a8906cf00998f4766351a29d10155f2e3cfa4a5  regenerated
7bab0426ab76e88bdbbf2dcc0a8906cf00998f4766351a29d10155f2e3cfa4a5  shipped
```

Identical sha256, identical 7,274,376 bytes, both 537 images at 912x532. Byte-identity was not
required, only matching frame count and dimensions; it was achieved and is recorded as observed.
This is what establishes that the reformatted, committed script is the script that produced the
published artifact.

The reformat was additionally checked structurally: an AST comparison of the pre- and post-reformat
revisions yields an identical multiset of string literals, f-string templates and numeric constants,
the only differences being the two cwd-relative `sys.path` strings replaced by `__file__` anchoring
and the data path split across the repo-root join. No printed string, on-figure string, assert
message, colour, font size or figure constant changed.

## Captured stdout

`radius_rule_figure.py` (uv's package-provisioning lines omitted, script output verbatim):

```
window trials 29-42  21.4s realtime
  r=2.8614: window 2/14   session 147/1025
  r=7.5000: window 13/14   session 951/1025
board x[-60.0,60.0] y[0.0,120.0]  view half=73.1 mm
frames=587  realtime 23.5s
wrote <scratch>/radius-rule.gif  7.27 MB  537 frames  (912, 532)
```

`frames=587` is the length of the animation frame list, which includes 50 trailing freeze frames of
the final image; the GIF encoder collapses those, so the written artifact is 537 frames.

`grid_shift_search.py`:

```
30x30 cell = 5.722732 mm ; target pitch = 15.000000 mm
15 / cell  = 2.621126  <- must be an INTEGER for one shift to centre every target

x: best shift      0.0 um -> worst target 0.4317 cells = 2.470 mm off centre
   over EVERY possible shift, the best worst-case is 0.4317 cells = 2.470 mm
y: best shift   4159.0 um -> worst target 0.4317 cells = 2.470 mm off centre
   over EVERY possible shift, the best worst-case is 0.4317 cells = 2.470 mm

max x-columns centrable by one shift: 1 of 8
max y-rows    centrable by one shift: 1 of 8
=> max targets centred by any global shift: 1 of 64
```

`grid_sync_drift.py`:

```
grid synced to first target (-7.500, 22.500); cell 5.722732 mm, r 2.861366 mm

 trial   target x   target y  dx off-centre  dy off-centre  disc fits cell?
    29     -7.500     22.500        +0.000mm        -0.000mm              YES
    30     22.500     37.500        +1.386mm        -2.168mm               no
    31    -52.500     82.500        +0.782mm        +2.773mm               no
    32    -22.500     97.500        +2.168mm        +0.604mm               no
    33    -37.500     82.500        -1.386mm        +2.773mm               no
    34     22.500     97.500        +1.386mm        +0.604mm               no
    35     -7.500    112.500        +0.000mm        -1.564mm               no
    36      7.500      7.500        -2.168mm        +2.168mm               no
    37    -52.500     97.500        +0.782mm        +0.604mm               no
    38    -22.500     67.500        +2.168mm        -0.782mm               no
    39    -37.500     37.500        -1.386mm        -2.168mm               no
    40     22.500     82.500        +1.386mm        +2.773mm               no
    41    -37.500     22.500        -1.386mm        -0.000mm               no
    42     -7.500     37.500        +0.000mm        -2.168mm               no

--- what box size WOULD align a 30x30 grid to a 15 mm target pitch? ---
need 15 = k * (side/30)  ->  side = 450/k
  k=2: side  225.00 mm -> cell  7.500 mm, r  3.750 mm
  k=3: side  150.00 mm -> cell  5.000 mm, r  2.500 mm
  k=4: side  112.50 mm -> cell  3.750 mm, r  1.875 mm
  k=5: side   90.00 mm -> cell  3.000 mm, r  1.500 mm

actual box side = 171.68196 mm  ->  15/cell = 2.621126 (not an integer)
the box is CURSOR-derived (recorded excursion), not target-derived, which is why it does not divide 15.
```

Only one of the 64 targets can be centred by any global shift of the 30x30 grid, and only trial 29,
the one the grid is synced to, keeps its disc inside its cell. That is the drift the figure animates.

## Shipped artifact hashes

| File | bytes | sha256 |
|---|---|---|
| `docs/media/radius-rule.gif` | 7,274,376 | `7bab0426ab76e88bdbbf2dcc0a8906cf00998f4766351a29d10155f2e3cfa4a5` |
| `docs/media/radius-rule-synced-first-target.png` | 53,752 | `0bad28339f884b668a3279a126e24fe773d350c69f2dbd441b3170541aa353de` |
| `docs/media/radius-rule-drifted.png` | 57,026 | `d8f12feb87e2b5209f4063745d633520e168faa059f702cfc4838d685284416a` |

A committed binary is invisible in a diff, so these are the reference a later silent swap is
detectable against.

## D-A: no new Python dependency

matplotlib and pillow are supplied per-invocation with `--with matplotlib --with pillow` rather than
declared in `Decoder/pyproject.toml`. `Decoder/pyproject.toml` and `Decoder/uv.lock` are unchanged by
this task.

Two reasons. The generator can never run in CI: `ci.yml:726-729` asserts `Decoder/data` is empty on a
CI checkout and fails the build if it is not, and this script reads the 382 MB gitignored session
`.mat`. And a `figures` extra would re-resolve `Decoder/uv.lock`, which CI cache-keys and prints as
its pinned versions and which `Tools/scripts/toolchain-policy.sh` reasons about; the pinned surface
moves only when a shipped artifact needs it, and a figure does not.

The cost is that the two libraries are unpinned, mitigated by recording the resolved versions above.

## D-B: the GIF ships as rendered

Re-measured on this machine with gifsicle 1.96, on the actual artifact:

| variant | bytes | verdict |
|---|---|---|
| as rendered (PIL, 72-colour adaptive palette, `optimize=True`) | 7,274,376 | ships |
| `gifsicle -O3 --lossy=60` | 6,848,392 | rejected: 5.9% saving, not worth any artifact risk |
| `gifsicle -O3 --lossy=100 --colors 48` | 3,419,086 | rejected, see below |

The artifact's load-bearing content is small monospace text: the per-pane readout
(`off cell centre +x.xxx, +y.yyy mm` / `disc FITS its cell`) at 8.4 pt, and the two footers carrying
the full-session totals, the excerpt-selection rule, the realtime marker and the session sha256
prefix at 8.6 to 9.4 pt. Lossy GIF dithering degrades exactly that content first, and only the
aggressive setting saves anything meaningful. Trading the legibility of the honesty labels for
3.8 MB is the wrong trade in a repository whose discipline is that every published number stays
traceable and legible. The figure is also not cropped or rescaled, for the same reason: the
selection rule and the session totals are rendered into the frame.

The absolute cost is accepted as a one-shot: the artifact does not churn, the repository is private,
and no CI step fetches media. The standing consequence is that **no further animated variants ship**.
One GIF plus two stills is the budget; a second variant is a new decision, not a free addition.
