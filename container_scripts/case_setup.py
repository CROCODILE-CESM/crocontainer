"""
Reference case setup for the crocontainer environment — Panama domain.

Builds the case from panama_case_config.yaml (a CrocoDash YAML case config)
using CrocoDash.recipe, then stages pre-staged GLORYS OBC/IC data from AWS S3
before running the forcing regrid, so CI can run end-to-end without live
Copernicus Marine credentials.

Mount both files as /workspace/case_setup.py and /workspace/panama_case_config.yaml:

    docker run ... \
      -v /path/to/case_setup.py:/workspace/case_setup.py \
      -v /path/to/panama_case_config.yaml:/workspace/panama_case_config.yaml \
      ghcr.io/crocodile-cesm/crocontainer:latest \
      /bin/bash /workspace/run_case.sh

To change the domain, resolution, vertical grid, or compset, edit
panama_case_config.yaml — not this file.
"""

import os
import subprocess
from pathlib import Path

from CrocoDash.recipe import load_config, create_case_from_yaml

os.environ.setdefault("USER", "root")

CONFIG_PATH = Path(
    os.environ.get(
        "CASE_CONFIG_PATH", Path(__file__).resolve().parent / "panama_case_config.yaml"
    )
)

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


config = load_config(CONFIG_PATH)

# GEBCO bathymetry covering the Panama domain — must exist before
# create_case_from_yaml builds the Topo from it.
GEBCO_PATH = Path(config["topo"]["source"]["bathymetry_path"])
s3_get("gebco_2026_n20.0_s0.0_w-90.0_e-70.0.nc", GEBCO_PATH)

# Build the grid/topo/vgrid/case and run configure_forcings, but stop short
# of process_forcings — we need to stage pre-downloaded GLORYS raw data into
# the case's extract_forcings/raw_data dir first (below).
case = create_case_from_yaml(config, override=True, configure_only=True)

print(
    f"Grid:  {case.ocn_grid.nx}x{case.ocn_grid.ny} cells at "
    f"{config['grid']['resolution']}° (Panama domain)"
)
print(f"Topo:  GEBCO, max depth {case.ocn_topo.max_depth:.0f} m")
print(f"VGrid: {case.ocn_vgrid.nk} hyperbolic levels")

# Download pre-staged raw GLORYS data from S3 into the location the driver
# expects. Filenames match the regex the driver uses to detect existing data
# and skip the live download step.
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

print(f"Case setup complete: {case.caseroot}")
