"""
Minimal NYF test case setup for crocontainer reference run.

Creates a 10x10 degree flat-bottom regional ocean case using NYF
(Normal Year Forcing) to capture the Buildconf input_data_list.

Run with:
    conda run -n CrocoDash python setup_nyf_test_case.py
"""

import numpy as np
from pathlib import Path

from mom6_forge.grid import Grid
from mom6_forge.topo import Topo
from mom6_forge.vgrid import VGrid
from CrocoDash.case import Case

CESMROOT = Path("~/work/installs/CROCESM_workshop_2025").expanduser()
CASEROOT = Path("~/croc_cases/nyf_test_case").expanduser()
INPUTDIR = Path("/glade/u/home/manishrv/scratch/croc_input/nyf_test_case")

# Small 10x10 degree box in the North Atlantic (open ocean, away from coasts)
grid = Grid(
    lenx=10.0,
    leny=10.0,
    resolution=1.0,
    xstart=-60.0,
    ystart=30.0,
    name="nyf_test",
)

# Flat 1000 m bathymetry — no topo processing needed
topo = Topo(grid, min_depth=10.0, git=False)
topo.set_flat(1000.0)

# 10 uniform z-levels — basic and fast
vgrid = VGrid.uniform(nk=10, depth=1000.0, name="nyf_test")

print(f"Grid:  {grid.nx}x{grid.ny} cells at 1 degree resolution")
print(f"Topo:  flat 1000 m")
print(f"VGrid: {vgrid.nk} uniform levels, total depth {vgrid.depth} m")

case = Case(
    cesmroot=CESMROOT,
    caseroot=CASEROOT,
    inputdir=INPUTDIR,
    compset="1850_DATM%NYF_SLND_SICE_MOM6%REGIONAL_SROF_SGLC_SWAV",
    ocn_grid=grid,
    ocn_topo=topo,
    ocn_vgrid=vgrid,
    atm_grid_name="T62",
    machine="derecho",
    project="ncgd0011",
    override=True,
)

print(f"\nCase created at: {CASEROOT}")
print("Next step: cd to caseroot and run ./case.build")
