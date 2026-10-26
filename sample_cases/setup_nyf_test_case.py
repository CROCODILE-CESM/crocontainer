"""
Minimal NYF test case setup for crocontainer reference run.

Writes the grid files nyf_test_case_config.yaml (a CrocoDash YAML case
config) names, then builds the case it describes — a 10x10 degree flat-bottom
regional ocean case using NYF (Normal Year Forcing) — to capture the Buildconf
input_data_list.

Run with:
    conda run -n CrocoDash python setup_nyf_test_case.py

Once the grid files exist, equivalently:
    conda run -n CrocoDash crocodash create --config nyf_test_case_config.yaml --override
"""

from pathlib import Path

from CrocoDash.grid import Grid
from CrocoDash.recipe import load_config, create_case_from_yaml
from CrocoDash.topo import Topo
from CrocoDash.vgrid import VGrid

CONFIG_PATH = Path(__file__).parent / "nyf_test_case_config.yaml"

config = load_config(CONFIG_PATH)
files = config["case"]
Path(files["ocn_grid"]).parent.mkdir(parents=True, exist_ok=True)
grid = Grid(
    resolution=1.0, xstart=-60.0, lenx=10.0, ystart=30.0, leny=10.0, name="nyf_test"
)
grid.write_supergrid(files["ocn_grid"])
topo = Topo(grid, min_depth=10.0)
topo.set_flat(1000.0)
topo.write_topo(files["ocn_topo"])
VGrid.uniform(nk=10, depth=1000.0).write(files["ocn_vgrid"])

case = create_case_from_yaml(config, override=True)

print(f"Grid:  {case.ocn_grid.nx}x{case.ocn_grid.ny} cells at 1 degree resolution")
print(f"Topo:  flat 1000 m")
print(
    f"VGrid: {case.ocn_vgrid.nk} uniform levels, total depth {case.ocn_vgrid.depth} m"
)
print(f"\nCase created at: {case.caseroot}")
print("Next step: cd to caseroot and run ./case.build")
