"""Per-trial drift table for the synced-grid pane, plus the box sizes that would align.

Phases a 30x30 Webgrid so the first target of the figure's excerpt window (trials 29-42) sits
exactly at a cell centre, then prints, for every trial in that window, how far its target has
drifted off its own cell centre and whether the acceptance disc still fits inside the cell. It ends
with the box sides that WOULD divide the 15 mm target pitch evenly, and the actual cursor-derived
side that does not.

WHAT THIS NUMBER IS NOT. It is a property of two lattices, not of a decoder. No spikes are read and
no decoded trajectory is involved.

    uv run --project Decoder python Decoder/scripts/grid_sync_drift.py
"""

from __future__ import annotations

import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
_REPO = Path(__file__).resolve().parents[2]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

# ruff: noqa: E402  -- sys.path must be extended above before this resolves.
from webgrid_ceiling import load_tracks, square_box, trial_bounds

target, cursor = load_tracks(_REPO / "Decoder/data/indy_20160630_01.mat")
ws = square_box(cursor)
cell = ws["cell_mm"]
r = ws["acq_radius_mm"]
b = trial_bounds(target)
s0, s1 = 29, 43

# Phase the 30x30 grid so the FIRST target of the window sits exactly at a cell centre.
t0 = target[:, int(b[s0])]
gx0 = t0[0] - cell/2.0      # a cell EDGE, so t0 is the centre of that cell
gy0 = t0[1] - cell/2.0
print(f"grid synced to first target ({t0[0]:.3f}, {t0[1]:.3f}); cell {cell:.6f} mm, r {r:.6f} mm\n")
print(
    f"{'trial':>6} {'target x':>10} {'target y':>10} "
    f"{'dx off-centre':>14} {'dy off-centre':>14} {'disc fits cell?':>16}"
)
tol = cell/2 - r            # 0 exactly: the disc fills the cell, so any offset spills
for i in range(s0, s1):
    t = target[:, int(b[i])]
    fx = ((t[0]-gx0)/cell) % 1.0
    fy = ((t[1]-gy0)/cell) % 1.0
    dx = (fx-0.5)*cell
    dy = (fy-0.5)*cell
    fits = "YES" if (abs(dx) <= tol+1e-9 and abs(dy) <= tol+1e-9) else "no"
    print(f"{i:>6} {t[0]:>10.3f} {t[1]:>10.3f} {dx:>+13.3f}mm {dy:>+13.3f}mm {fits:>16}")

print("\n--- what box size WOULD align a 30x30 grid to a 15 mm target pitch? ---")
print("need 15 = k * (side/30)  ->  side = 450/k")
for k in (2, 3, 4, 5):
    side = 450/k
    print(f"  k={k}: side {side:7.2f} mm -> cell {side/30:6.3f} mm, r {side/60:6.3f} mm")
print(f"\nactual box side = {ws['side_mm']:.5f} mm  ->  15/cell = {15/cell:.6f} (not an integer)")
print(
    "the box is CURSOR-derived (recorded excursion), not target-derived, "
    "which is why it does not divide 15."
)
