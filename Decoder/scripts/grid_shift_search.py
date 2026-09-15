"""Exhaustive shift search: no rigid shift centres the 8x8 target lattice in 2.861 mm cells.

The published acceptance radius is half a 30x30 Webgrid cell, and that grid is sized from the
recorded cursor excursion box, so its cell is 2.861 mm. The dataset's own targets sit on a 15 mm
lattice. This script sweeps every rigid shift of the 30x30 grid at 0.2 um resolution and prints the
best achievable worst-case off-centre distance in x and in y, then the largest number of the 64
targets that any single global shift can centre at once.

WHAT THIS NUMBER IS NOT. It is a statement about two geometries, not about a decoder. Nothing here
reads spikes and no decoded trajectory is involved; the only arrays touched are the recorded target
and cursor tracks.

    uv run --project Decoder python Decoder/scripts/grid_shift_search.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

_SCRIPTS = Path(__file__).resolve().parent
_REPO = Path(__file__).resolve().parents[2]
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))

# ruff: noqa: E402  -- sys.path must be extended above before this resolves.
from webgrid_ceiling import load_tracks, square_box

target, cursor = load_tracks(_REPO / "Decoder/data/indy_20160630_01.mat")
ws = square_box(cursor)
cell = ws["cell_mm"]
r = ws["acq_radius_mm"]
uniq = np.unique(target.T, axis=0)
tx = np.unique(np.round(uniq[:,0],6))
ty = np.unique(np.round(uniq[:,1],6))
print(f"30x30 cell = {cell:.6f} mm ; target pitch = 15.000000 mm")
print(f"15 / cell  = {15/cell:.6f}  <- must be an INTEGER for one shift to centre every target\n")
shifts = np.arange(0, cell, 0.0002)          # 0.2 um resolution
for nm, c in (("x", tx), ("y", ty)):
    f = ((c[None,:] - shifts[:,None]) / cell) % 1.0
    off = np.abs(f - 0.5)
    worst = off.max(axis=1)
    k = int(np.argmin(worst))
    print(
        f"{nm}: best shift {shifts[k]*1000:8.1f} um -> worst target "
        f"{worst[k]:.4f} cells = {worst[k]*cell:.3f} mm off centre"
    )
    print(
        "   over EVERY possible shift, the best worst-case is "
        f"{worst.min():.4f} cells = {worst.min()*cell:.3f} mm"
    )
fx = ((tx[None,:] - shifts[:,None])/cell) % 1.0
fy = ((ty[None,:] - shifts[:,None])/cell) % 1.0
okx = (np.abs(fx-0.5) < 0.05).sum(axis=1)
oky = (np.abs(fy-0.5) < 0.05).sum(axis=1)
print(f"\nmax x-columns centrable by one shift: {okx.max()} of 8")
print(f"max y-rows    centrable by one shift: {oky.max()} of 8")
print(f"=> max targets centred by any global shift: {okx.max()*oky.max()} of 64")
