"""
Reference case setup for the crocontainer environment.

This example uses NYF (Normal Year Forcing) — a small fixed dataset good for
testing. Edit the domain, resolution, vertical grid, or compset to configure
your own case, then mount this file as /workspace/case_setup.py:

    docker run ... \
      -v /path/to/this/file:/workspace/case_setup.py \
      ghcr.io/crocodile-cesm/crocontainer:latest \
      /bin/bash /workspace/run_case.sh
"""
import os
from pathlib import Path

from mom6_forge.grid import Grid
from mom6_forge.topo import Topo
from mom6_forge.vgrid import VGrid
from CrocoDash.case import Case

os.environ.setdefault("USER", "root")

CESMROOT = Path("/workspace/CESM")
CASEROOT = Path("/workspace/case")
INPUTDIR = Path("/workspace/inputdir")

grid = Grid(lenx=10.0, leny=10.0, resolution=1.0, xstart=-60.0, ystart=30.0, name="nyf_case")
topo = Topo(grid, min_depth=10.0, git=False)
topo.set_flat(1000.0)
vgrid = VGrid.uniform(nk=10, depth=1000.0, name="nyf_case")

print(f"Grid:  {grid.nx}x{grid.ny} cells at 1° resolution")
print(f"Topo:  flat 1000 m")
print(f"VGrid: {vgrid.nk} uniform levels")

case = Case(
    cesmroot=CESMROOT,
    caseroot=CASEROOT,
    inputdir=INPUTDIR,
    compset="1850_DATM%NYF_SLND_SICE_MOM6%REGIONAL_SROF_SGLC_SWAV",
    ocn_grid=grid,
    ocn_topo=topo,
    ocn_vgrid=vgrid,
    atm_grid_name="T62",
    machine="ubuntu-latest",
    project="PROJ123",
    override=True,
)

print(f"Case setup complete: {CASEROOT}")
