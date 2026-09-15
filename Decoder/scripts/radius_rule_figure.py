"""Radius-rule comparison: the animal's own recorded hand, two acceptance rules.

Renders an animated side-by-side of one recorded excerpt scored twice: on the left the published
2.861 mm radius (the 30x30 Webgrid half-cell, derived from the recorded cursor excursion box), on
the right 7.50 mm (exactly half the task's own 15 mm target pitch). The left grid is phased so the
excerpt's first target is exactly centred, which is what makes the drift visible.

WHAT THIS FIGURE IS NOT. Both panes replay the ANIMAL'S OWN recorded hand, and neither is a decoder
output. Nothing here loads a model, and no decoded trajectory appears in any frame. It is an
open-loop replay of a recorded session in which the subject was not in the loop, so it cannot say
anything about closed-loop control at any radius. The 951/1025 (92.8%) that the right-hand rule
scores is what the RECORDED HAND achieves: a control for the acceptance rule, not a decode result,
and it may not be quoted as one.

Visual language matches Packages/CortexRender/Sources/CortexRender/Webgrid.metal:
near-black field, faint white rules phased onto the targets, near-white ring+dot cursor,
red selection turning green on a committed selection.

The acceptance region is drawn as a CIRCLE because the criterion is Euclidean
(`norm(cursor - target) < radius`); the shipped demo draws a square half-extent, which would
overstate the corner by radius*sqrt(2). Every number is re-derived from the session .mat.

NO DEPENDENCY IS ADDED FOR THIS SCRIPT (quick task 260915-fk9, D-A). matplotlib and pillow are
supplied per-invocation with `--with` rather than declared in `Decoder/pyproject.toml`, for two
reasons. This script can never run in CI: `ci.yml:726-729` asserts `Decoder/data` is empty on a CI
checkout, and this generator reads the 382 MB gitignored `Decoder/data/indy_20160630_01.mat`. And a
`figures` extra would re-resolve `Decoder/uv.lock`, which CI cache-keys and prints as its pinned
versions and which `Tools/scripts/toolchain-policy.sh` reasons about; the pinned surface moves only
when a shipped artifact needs it, and a figure does not. The cost is that matplotlib and pillow are
unpinned here, so the resolved versions are recorded alongside the artifact in
`.planning/phases/10-v1-real-data-closed-loop-launch/10-radius-rule-figure-evidence.md`.

    uv run --project Decoder --with matplotlib --with pillow \
      python Decoder/scripts/radius_rule_figure.py docs/media/radius-rule.gif
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import matplotlib
import numpy as np

matplotlib.use("Agg")

_SCRIPTS = Path(__file__).resolve().parent
_REPO = Path(__file__).resolve().parents[2]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

# ruff: noqa: E402  -- the Agg backend is selected and sys.path extended above before these resolve.
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation, PillowWriter
from matplotlib.patches import Circle, FancyBboxPatch
from PIL import Image
from webgrid_ceiling import _BEHAVIOR_FS_HZ as FS
from webgrid_ceiling import load_tracks, longest_run_inside, square_box, trial_bounds

OUT = Path(sys.argv[1])
SESSION = "indy_20160630_01"
DWELL_S, R_TASK, WIN_N, FPS = 0.30, 7.50, 14, 25
STEP = int(FS // FPS)                      # 10 samples/frame at 25 fps == exact realtime
SHA = next(e["sha256"] for e in json.loads(
    (_REPO / "Decoder/manifests/indy_sessions.json").read_text())["sessions"] if e["id"] == SESSION)

target, cursor = load_tracks(_REPO / "Decoder/data" / f"{SESSION}.mat")
ws = square_box(cursor)
SIDE, R_PUB, CELL30 = ws["side_mm"], ws["acq_radius_mm"], ws["cell_mm"]
d = np.linalg.norm(cursor - target, axis=0)
b = trial_bounds(target)
n_tr = len(b) - 1
need = int(round(DWELL_S * FS))

uniq = np.unique(target.T, axis=0)
tx, ty = np.unique(np.round(uniq[:,0],6)), np.unique(np.round(uniq[:,1],6))
PITCH = float(np.unique(np.round(np.diff(tx),6))[0])
assert uniq.shape[0] == 64 and len(tx) == len(ty) == 8, f"expected 8x8 lattice, got {uniq.shape}"
# so the disc is exactly inscribed in a cell
assert abs(R_TASK - PITCH/2) < 1e-9, "R_TASK is not half the target pitch"

hit = {r: np.array([longest_run_inside(d[b[i]:b[i+1]], r) >= need for i in range(n_tr)])
       for r in (R_PUB, R_TASK)}
sess = {r: int(hit[r].sum()) for r in (R_PUB, R_TASK)}
rates = {r: hit[r].mean() for r in (R_PUB, R_TASK)}
lens = np.diff(b)
cands = [(max(abs(hit[r][s:s+WIN_N].mean()-rates[r])/rates[r] for r in (R_PUB,R_TASK)), s)
         for s in range(0, n_tr-WIN_N+1) if lens[s:s+WIN_N].sum()/FS <= 24]
_, s0 = min(cands)
s1 = s0 + WIN_N
lo, hi = int(b[s0]), int(b[s1])
print(f"window trials {s0}-{s1-1}  {(hi-lo)/FS:.1f}s realtime")
for r in (R_PUB, R_TASK):
    print(f"  r={r:.4f}: window {hit[r][s0:s1].sum()}/{WIN_N}   session {sess[r]}/{n_tr}")


def acq_index(dist, radius):
    run = 0
    for i, v in enumerate(dist < radius):
        run = run + 1 if v else 0
        if run >= need:
            return i
    return None


acq = {r: {i: int(b[i]) + k for i in range(s0, s1)
           if (k := acq_index(d[b[i]:b[i+1]], r)) is not None} for r in (R_PUB, R_TASK)}

BG, FIELD = "#08080c", "#05050a"
GRID, FG, MUTED = "#ffffff", "#e8edf2", "#7d8894"
CUR, RED, GREEN = "#f2faff", "#e62933", "#33e066"

fig = plt.figure(figsize=(12.0, 7.0), dpi=76, facecolor=BG)
fig.suptitle("The animal's own recorded hand, replayed.  "
             "Same track in both panes - only the acceptance rule differs.",
             color=FG, fontsize=13, y=0.973)
fig.text(0.5, 0.923,
         f"{SESSION}  |  open-loop replay of a recorded session; "
         "the subject was not in the loop  |  NOT a decoder output",
         color=MUTED, fontsize=10, ha="center")

bx0, bx1 = float(tx[0]-PITCH/2), float(tx[-1]+PITCH/2)
by0, by1 = float(ty[0]-PITCH/2), float(ty[-1]+PITCH/2)
cw = cursor[:, lo:hi]
vx0, vx1 = min(bx0, cw[0].min()), max(bx1, cw[0].max())
vy0, vy1 = min(by0, cw[1].min()), max(by1, cw[1].max())
MARGIN = 13.0
cx, cy = (vx0+vx1)/2.0, (vy0+vy1)/2.0
half = max(vx1-vx0, vy1-vy0)/2.0 + MARGIN
print(f"board x[{bx0:.1f},{bx1:.1f}] y[{by0:.1f},{by1:.1f}]  view half={half:.1f} mm")
panes = []
X0, Y0 = cx - 0.0, cy - 0.0  # placeholder, real origins computed per pane below
WS_X0, WS_Y0 = ws["centre_x_mm"] - SIDE/2, ws["centre_y_mm"] - SIDE/2
panes = []
BX0, BY0 = float(tx[0]-PITCH/2), float(ty[0]-PITCH/2)
T0 = target[:, lo]                       # the window's FIRST target
SPEC = [
    (R_PUB,  "Published rule - 30x30 Webgrid half-cell", CELL30,
     float(T0[0]-CELL30/2), float(T0[1]-CELL30/2),
     "30x30 grid SYNCED to the first target - watch the rest drift off centre"),
    (R_TASK, "The task's own acceptance zone",           PITCH, BX0, BY0,
     "the task's own 15 mm lattice - every target is centred by construction"),
]
for j, (r, name, rulecell, gx0, gy0, sub) in enumerate(SPEC):
    pitch = rulecell
    ax = fig.add_axes([0.055 + j*0.485, 0.225, 0.41, 0.60])
    ax.set_facecolor(FIELD)
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_aspect("equal")
    for sp in ax.spines.values():
        sp.set_color("#1b2029")
    ax.set_xlim(cx-half, cx+half)
    ax.set_ylim(cy-half, cy+half)
    k0 = int(np.floor((cx-half - gx0)/pitch))
    k1 = int(np.ceil((cx+half - gx0)/pitch))
    for k in range(k0, k1+1):
        ax.axvline(gx0 + k*pitch, color=GRID, lw=0.8, alpha=0.16, zorder=1)
    m0 = int(np.floor((cy-half - gy0)/pitch))
    m1 = int(np.ceil((cy+half - gy0)/pitch))
    for m in range(m0, m1+1):
        ax.axhline(gy0 + m*pitch, color=GRID, lw=0.8, alpha=0.16, zorder=1)
    ax.set_title(f"{name}\nr = {r:.4f} mm   dwell {DWELL_S:.2f} s", color=FG, fontsize=11, pad=10)
    ax.text(0.5, -0.018, sub, transform=ax.transAxes, color=MUTED, fontsize=8.2,
            ha="center", va="top")
    hl = FancyBboxPatch((0,0), rulecell, rulecell, boxstyle="round,pad=0,rounding_size=0.6",
                        fc="none", ec=RED, lw=1.8, alpha=0.95, zorder=2)
    ax.add_patch(hl)
    offtxt = ax.text(0.022, 0.975, "", transform=ax.transAxes, color=MUTED, fontsize=8.4,
                     ha="left", va="top", family="monospace")
    disc = Circle((0,0), r, fc=RED, ec=RED, lw=1.6, alpha=0.85, zorder=3)
    ax.add_patch(disc)
    trail, = ax.plot([], [], color=CUR, lw=1.1, alpha=0.38, zorder=4)
    cring = Circle((0,0), 2.0, fill=False, ec=CUR, lw=1.4, alpha=0.95, zorder=5)
    ax.add_patch(cring)
    cdot, = ax.plot([], [], "o", color=CUR, ms=3.0, zorder=6)
    cnt = ax.text(0.5, -0.090, "", transform=ax.transAxes, color=FG, fontsize=14,
                  ha="center", va="top", family="monospace")
    bx, by = cx-half + 6.0, cy-half + 4.5
    ax.plot([bx, bx+10], [by, by], color=MUTED, lw=2.5, zorder=7)
    ax.text(bx+5, by + 2.4, "10 mm", color=MUTED, fontsize=8, ha="center", zorder=7)
    panes.append(dict(r=r, disc=disc, hl=hl, rulecell=rulecell, gx0=gx0, gy0=gy0, offtxt=offtxt,
                      trail=trail, cring=cring, cdot=cdot, cnt=cnt))

foot  = fig.text(0.5, 0.082, "", color=FG,    fontsize=9.4, ha="center", family="monospace")
expl  = fig.text(0.5, 0.046,
                 f"15 / {CELL30:.3f} = {15/CELL30:.4f}, not an integer: "
                 "a grid synced to one target cannot centre the rest.  "
                 "A 150 mm box would give 5 mm cells and align all 64.",
                 color=MUTED, fontsize=8.6, ha="center")
foot2 = fig.text(0.5, 0.014, "", color=MUTED, fontsize=8.6, ha="center", family="monospace")
TRAIL = 90


def draw(i):
    ti = int(np.searchsorted(b, i, side="right") - 1)
    tgx, tgy = float(target[0, i]), float(target[1, i])
    for p in panes:
        r = p["r"]
        got = ti in acq[r] and acq[r][ti] <= i
        col = GREEN if got else RED
        p["disc"].center = (tgx, tgy)
        p["disc"].set_fc(col)
        p["disc"].set_ec(col)
        p["disc"].set_alpha(0.95 if got else (0.85 if d[i] < r else 0.55))
        rc = p["rulecell"]
        hx = p["gx0"] + np.floor((tgx - p["gx0"])/rc)*rc
        hy = p["gy0"] + np.floor((tgy - p["gy0"])/rc)*rc
        p["hl"].set_bounds(hx, hy, rc, rc)
        p["hl"].set_ec(col)
        ox, oy = tgx - (hx + rc/2), tgy - (hy + rc/2)
        fits = abs(ox) <= rc/2 - r + 1e-9 and abs(oy) <= rc/2 - r + 1e-9
        p["offtxt"].set_text(f"off cell centre {ox:+.3f}, {oy:+.3f} mm\n"
                             + ("disc FITS its cell" if fits else "disc SPILLS its cell"))
        p["offtxt"].set_color(GREEN if fits else "#e08a5a")
        a = max(lo, i - TRAIL)
        p["trail"].set_data(cursor[0, a:i+1], cursor[1, a:i+1])
        p["cring"].center = (cursor[0, i], cursor[1, i])
        p["cdot"].set_data([cursor[0, i]], [cursor[1, i]])
        p["cnt"].set_text(
            f"{sum(1 for t,k2 in acq[r].items() if k2 <= i):>2} / {ti-s0+1:<2} acquired"
        )
    foot.set_text(
        f"FULL SESSION, all {n_tr} trials:   {sess[R_PUB]}/{n_tr} ({100*sess[R_PUB]/n_tr:.1f}%)"
        f"   vs   {sess[R_TASK]}/{n_tr} ({100*sess[R_TASK]/n_tr:.1f}%)"
    )
    foot2.set_text(
        f"excerpt: contiguous trials {s0}-{s1-1}, selected to minimise deviation "
        "from the session rate under BOTH rules"
        f"  |  REALTIME 1x  |  sha256 {SHA[:12]}"
    )
    return []


frames = list(range(lo, hi, STEP))
if frames[-1] != hi-1:
    frames.append(hi-1)
frames += [hi-1] * int(2.0*FPS)
for r in (R_PUB, R_TASK):
    shown = sum(1 for t,k in acq[r].items() if k <= hi-1)
    truth = int(hit[r][s0:s1].sum())
    assert shown == truth, f"r={r}: ends at {shown}, window truth {truth}"
print(f"frames={len(frames)}  realtime {len(frames)/FPS:.1f}s")
FuncAnimation(fig, draw, frames=frames, blit=False).save(OUT, writer=PillowWriter(fps=FPS))
im = Image.open(OUT)
fr = []
for k in range(im.n_frames):
    im.seek(k)
    fr.append(im.convert("RGB").convert("P", palette=Image.ADAPTIVE, colors=72))
fr[0].save(OUT, save_all=True, append_images=fr[1:], duration=int(1000/FPS), loop=0, optimize=True)
print(f"wrote {OUT}  {os.path.getsize(OUT)/1e6:.2f} MB  {len(fr)} frames  {fr[0].size}")
