"""
Minimal NYF test case setup for crocontainer reference run.

Builds the case described in nyf_test_case_config.yaml (a CrocoDash YAML
case config) — a 10x10 degree flat-bottom regional ocean case using NYF
(Normal Year Forcing) — to capture the Buildconf input_data_list.

Run with:
    conda run -n CrocoDash python setup_nyf_test_case.py

Equivalently, without this script:
    conda run -n CrocoDash crocodash create --config nyf_test_case_config.yaml --override
"""

from pathlib import Path

from CrocoDash.recipe import load_config, create_case_from_yaml

CONFIG_PATH = Path(__file__).parent / "nyf_test_case_config.yaml"

config = load_config(CONFIG_PATH)
case = create_case_from_yaml(config, override=True)

print(f"Grid:  {case.ocn_grid.nx}x{case.ocn_grid.ny} cells at 1 degree resolution")
print(f"Topo:  flat 1000 m")
print(
    f"VGrid: {case.ocn_vgrid.nk} uniform levels, total depth {case.ocn_vgrid.depth} m"
)
print(f"\nCase created at: {case.caseroot}")
print("Next step: cd to caseroot and run ./case.build")
