"""
Reference case setup for the crocontainer environment — Panama domain.

Uses the Panama domain (3°×3° at 0.05°) with GEBCO bathymetry and
pre-staged GLORYS OBC/IC data from AWS S3, so CI can run end-to-end
without live Copernicus Marine credentials.

Mount this file as /workspace/case_setup.py:

    docker run ... \
      -v /path/to/this/file:/workspace/case_setup.py \
      ghcr.io/crocodile-cesm/crocontainer:latest \
      /bin/bash /workspace/run_case.sh
"""
import os
import subprocess
from pathlib import Path

from mom6_forge.grid import Grid
from mom6_forge.topo import Topo
from mom6_forge.vgrid import VGrid
from CrocoDash.case import Case

os.environ.setdefault("USER", "root")

CESMROOT = Path("/workspace/CESM")
CASEROOT = Path("/workspace/case")
INPUTDIR = Path("/workspace/inputdir")

S3_BASE = (
    "https://crocodile-cesm.s3.us-east-1.amazonaws.com/CrocoDash/data/testing_data"
)


def s3_get(filename, dest):
    dest = Path(dest)
    if not dest.exists():
        print(f"Downloading {filename} ...")
        subprocess.run(
            ["wget", "-q", "-O", str(dest), f"{S3_BASE}/{filename}"],
            check=True,
        )


# Panama domain — matches the pre-staged AWS S3 OBC/IC raw data.
grid = Grid(
    resolution=0.05,
    xstart=278.0,
    lenx=3.0,
    ystart=7.0,
    leny=3.0,
    name="panama1",
)

# GEBCO bathymetry covering the Panama domain.
GEBCO_PATH = Path("/tmp/gebco.nc")
s3_get("gebco_2026_n20.0_s0.0_w-90.0_e-70.0.nc", GEBCO_PATH)

topo = Topo(grid=grid, min_depth=9.5, git=False)
topo.set_from_dataset(
    bathymetry_path=GEBCO_PATH,
    longitude_coordinate_name="lon",
    latitude_coordinate_name="lat",
    vertical_coordinate_name="elevation",
)

vgrid = VGrid.hyperbolic(nk=75, depth=topo.max_depth, ratio=20.0)

print(f"Grid:  {grid.nx}x{grid.ny} cells at 0.05° (Panama domain)")
print(f"Topo:  GEBCO, max depth {topo.max_depth:.0f} m")
print(f"VGrid: {vgrid.nk} hyperbolic levels")

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

# Configure forcings — writes OBC segment parameters to user_nl_mom and
# sets RUN_STARTDATE / STOP_N in the case XML.
case.configure_forcings(
    date_range=["2020-01-01 00:00:00", "2020-01-05 00:00:00"],
    function_name="get_glorys_data_script_for_cli",
)

# Download pre-staged raw GLORYS data from S3 into the location the
# driver expects. Filenames match the regex the driver uses to detect
# existing data and skip the live download step.
raw_data_dir = case.extract_forcings_path / "raw_data"
raw_data_dir.mkdir(parents=True, exist_ok=True)

for fname in [
    "east_unprocessed.20200101_20200105.nc",
    "ic_unprocessed.nc",
    "north_unprocessed.20200101_20200105.nc",
    "south_unprocessed.20200101_20200105.nc",
    "west_unprocessed.20200101_20200105.nc",
]:
    s3_get(fname, raw_data_dir / fname)

# Regrid OBC/IC data to the Panama grid → writes to INPUTDIR/ocnice/
case.process_forcings()

print(f"Case setup complete: {CASEROOT}")
