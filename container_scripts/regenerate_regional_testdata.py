#!/usr/bin/env python
"""Regenerate a regional test's input data via CrocoDash and stage it under
DIN_LOC_ROOT at the fixed path/filenames that test's CIME testmods already
reference (see container_scripts/regional_configs/*.yaml for the config
schema, and run_test_suite.sh for how this fits into a create_test run).

Usage: regenerate_regional_testdata.py <config.yaml>
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


def stage_bathymetry(cfg):
    bathy_path = cfg["crocodash"]["topo"]["source"].get("bathymetry_path")
    bathy_url = cfg.get("bathymetry_url")
    if bathy_path and bathy_url and not Path(bathy_path).exists():
        Path(bathy_path).parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["wget", "-q", "-O", bathy_path, bathy_url], check=True)


def stage_raw_data(cfg, raw_data_dir):
    raw_cfg = cfg.get("raw_data_staging") or {}
    s3_base = raw_cfg.get("s3_base")
    if not s3_base:
        print(
            "regenerate_regional_testdata: no raw_data_staging.s3_base "
            f"configured -- skipping raw data fetch. `crocodash process` "
            f"will fail unless raw data is already present at {raw_data_dir}",
            file=sys.stderr,
        )
        return
    raw_data_dir.mkdir(parents=True, exist_ok=True)
    for fname in raw_cfg.get("files", []):
        subprocess.run(
            ["wget", "-q", "-O", str(raw_data_dir / fname), f"{s3_base}/{fname}"],
            check=True,
        )


def stage_additional_inputdata(cfg):
    din_loc_root = Path(os.environ["DIN_LOC_ROOT"])
    for entry in cfg.get("additional_inputdata_staging") or []:
        url_base = entry.get("url_base")
        if not url_base:
            print(
                "regenerate_regional_testdata: skipping an "
                "additional_inputdata_staging entry with no url_base set",
                file=sys.stderr,
            )
            continue
        dest_dir = din_loc_root / entry["dest_subdir"]
        dest_dir.mkdir(parents=True, exist_ok=True)
        for fname in entry.get("files", []):
            dest = dest_dir / fname
            if dest.exists():
                continue
            subprocess.run(
                ["wget", "-q", "-O", str(dest), f"{url_base}/{fname}"], check=True
            )


def stage_output(cfg, inputdir):
    staging = cfg["staging"]
    dest_dir = Path(os.environ["DIN_LOC_ROOT"]) / staging["din_loc_root_subdir"]
    dest_dir.mkdir(parents=True, exist_ok=True)
    inputdir = Path(inputdir)

    # CrocoDash's output subdirectory name has moved between branches/versions
    # ("ocnice" vs "ocean") -- search recursively under inputdir rather than
    # assuming one, so this doesn't silently break again on the next rename.
    def find(glob):
        matches = sorted(inputdir.rglob(glob))
        return matches

    for entry in staging.get("rename_globs", []):
        matches = find(entry["glob"])
        if not matches:
            raise FileNotFoundError(
                f"No files matched {entry['glob']!r} anywhere under {inputdir} "
                "-- check the CrocoDash run actually produced this output."
            )
        shutil.copy(matches[-1], dest_dir / entry["dest"])

    for fname in staging.get("copy_as_is", []):
        matches = find(fname)
        if not matches:
            raise FileNotFoundError(
                f"No file named {fname!r} found anywhere under {inputdir}."
            )
        shutil.copy(matches[0], dest_dir / fname)

    print(f"Staged regenerated data under {dest_dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", help="Path to a regional_configs/*.yaml file")
    args = parser.parse_args()

    with open(args.config) as f:
        cfg = yaml.safe_load(f)

    case_cfg = cfg["crocodash"]["case"]
    caseroot = Path(case_cfg["caseroot"])
    inputdir = Path(case_cfg["inputdir"])
    raw_data_dir = inputdir / "extract_forcings" / "raw_data"

    stage_bathymetry(cfg)
    stage_additional_inputdata(cfg)

    tmp_config = Path("/tmp/regional_test_crocodash_config.yaml")
    with open(tmp_config, "w") as f:
        yaml.safe_dump(cfg["crocodash"], f)

    subprocess.run(
        [
            "crocodash",
            "create",
            "--config",
            str(tmp_config),
            "--override",
            "--configure-only",
        ],
        check=True,
    )

    stage_raw_data(cfg, raw_data_dir)

    subprocess.run(
        ["crocodash", "process", "--caseroot", str(caseroot), "--all"],
        check=True,
    )

    stage_output(cfg, inputdir)


if __name__ == "__main__":
    main()
