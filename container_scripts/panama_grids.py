"""Write the Panama demo's grid files: 3x3 degrees at 0.05 degrees, GEBCO
bathymetry and 75 hyperbolic levels.

    python panama_grids.py OUTPUT_DIR

It writes ocean_hgrid.nc, ocean_topog.nc and ocean_vgrid.nc, which
panama_case_config.yaml names. For your own domain, edit a copy of this script
and mount it at /workspace/grids.py: run_case.sh runs it with OUTPUT_DIR
/workspace/grids before it creates the case.
"""

import sys
from pathlib import Path

from CrocoDash.grid import Grid
from CrocoDash.topo import Topo
from CrocoDash.vgrid import VGrid

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

grid = Grid(
    resolution=0.05, xstart=278.0, lenx=3.0, ystart=7.0, leny=3.0, name="panama1"
)
grid.write_supergrid(out / "ocean_hgrid.nc")

topo = Topo(grid, min_depth=9.5)
# panama_demo_setup.sh downloads this GEBCO subset. For your own domain, mount
# a bathymetry file and read it here instead, or use topo.set_flat(depth).
topo.set_from_dataset(
    bathymetry_path="/tmp/gebco.nc",
    longitude_coordinate_name="lon",
    latitude_coordinate_name="lat",
    vertical_coordinate_name="elevation",
)
topo.write_topo(out / "ocean_topog.nc")

VGrid.hyperbolic(nk=75, depth=topo.max_depth, ratio=20.0).write(
    out / "ocean_vgrid.nc"
)
