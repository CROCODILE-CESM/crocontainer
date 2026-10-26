"""Write the grid files of the domain every test runs on: a 20x16, 1/4 degree
box over the Labrador coast, with GEBCO bathymetry and 10 uniform levels. It is
far enough north that CICE has ice, and the coastline gives the GLOFAS runoff
map rivers to map.

    python labsea_grids.py OUTPUT_DIR

It writes ocean_hgrid.nc, ocean_topog.nc and ocean_vgrid.nc, which
run_mom_tests.py names in each test's config.
"""

import sys
from pathlib import Path

from CrocoDash.grid import Grid
from CrocoDash.topo import Topo
from CrocoDash.vgrid import VGrid

GEBCO = "/glade/campaign/cesm/cesmdata/inputdata/ocn/mom/croc/crocogallerydata/gebco/GEBCO_2024.nc"

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)

grid = Grid(
    resolution=0.25, xstart=299.0, lenx=5.0, ystart=54.0, leny=4.0, name="labsea_test"
)
grid.write_supergrid(out / "ocean_hgrid.nc")

topo = Topo(grid, min_depth=10.0)
topo.set_from_dataset(
    bathymetry_path=GEBCO,
    longitude_coordinate_name="lon",
    latitude_coordinate_name="lat",
    vertical_coordinate_name="elevation",
)
topo.write_topo(out / "ocean_topog.nc")

VGrid.uniform(nk=10, depth=topo.max_depth).write(out / "ocean_vgrid.nc")
