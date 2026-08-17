#!/usr/bin/env python
"""Regenerate a regional test's CrocoDash input data, then run it via CIME's
create_test -- testlist_mom.xml/testmods_dirs are used entirely unmodified,
stock SMS/ERS, no custom SystemTests. See discover_regional_tests.py for how
the container CI enumerates which tests to run this way, and
regional_configs/*.yaml for the CrocoDash config schema.

Usage: run_regional_test.py <full-test-name>
  e.g. run_regional_test.py \\
    SMS_D_Ld2.USER_RES.CR_JRA_GLOFAS.ubuntu-latest_gnu.mom-regional-base--mom-regional-container_smoke

The test name's testmods component (its last dot-separated field) selects
which regional_configs/ CrocoDash config to regenerate from -- everything up
to the first "--" (the container-only PE-layout override appended by
discover_regional_tests.py is stripped, since it carries no data
implications). Onboard a new regional test by adding a %REGIONAL-compset
entry to testlist_mom.xml plus a matching config file here;
discover_regional_tests.py picks it up automatically, no CI changes needed.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

REGIONAL_CONFIGS_DIR = Path("/workspace/regional_configs")
DIN_LOC_ROOT = "/root/cesm/inputdata"
CESM_SCRIPTS_DIR = "/workspace/CESM/cime/scripts"
TEST_ROOT = "/root/cesm/scratch/tests/regional"


def load_config(test_name):
    testmods = test_name.rsplit(".", 1)[-1]
    config_key = testmods.split("--", 1)[0]
    config_path = REGIONAL_CONFIGS_DIR / f"{config_key}.yaml"
    if not config_path.exists():
        sys.exit(
            f"No CrocoDash config found for testmods {config_key!r} at {config_path}\n"
            "Add one under container_scripts/regional_configs/ to onboard this test."
        )
    with open(config_path) as f:
        return yaml.safe_load(f)


def compset_override_name(test_name, cfg):
    # testlist_mom.xml's regional test entries (external MOM_interface repo)
    # are all registered against real-JRA55/GLOFAS compsets (CR_JRA_GLOFAS
    # etc) -- there's no NYF regional compset registered there today. Rather
    # than wait on that repo, swap the compset in the *test name we actually
    # run* for whatever compset_override this config declares (CIME resolves
    # a compset field by either alias or full long name, so this is a legal
    # substitution, not a hack -- see CIME/XML/compsets.py::get_compset_match).
    # This lets a CrocoDash config target a cheaper compset (no real
    # DATM%JRA download, no real DROF%GLOFAS runoff-mapping file) than the
    # one testlist_mom.xml registers, entirely on the crocontainer side --
    # testlist_mom.xml stays the source of truth for *which* tests exist,
    # just not for which exact compset variant each one actually runs
    # against in this container.
    override = cfg.get("compset_override")
    if not override:
        return test_name
    fields = test_name.split(".")
    fields[2] = override
    print(
        f"Overriding compset for this run: {override} "
        "(testlist_mom.xml still lists this test under its original compset)"
    )
    return ".".join(fields)


def stage_output(cfg, inputdir):
    staging = cfg["staging"]
    dest_dir = Path(DIN_LOC_ROOT) / staging["din_loc_root_subdir"]
    dest_dir.mkdir(parents=True, exist_ok=True)
    inputdir = Path(inputdir)

    # CrocoDash's output subdirectory name has moved between branches/versions
    # ("ocnice" vs "ocean") -- search recursively under inputdir rather than
    # assuming one, so this doesn't silently break again on the next rename.
    def find(glob):
        return sorted(inputdir.rglob(glob))

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


def regenerate_data(cfg):
    case_cfg = cfg["crocodash"]["case"]

    tmp_config = Path("/tmp/regional_test_crocodash_config.yaml")
    with open(tmp_config, "w") as f:
        yaml.safe_dump(cfg["crocodash"], f)

    # This whole script runs via `conda run -n CrocoDash python
    # run_regional_test.py ...` (see container-test.yml) so `crocodash` is
    # already on PATH -- no activate/deactivate dance needed here.
    subprocess.run(
        [
            "crocodash", "create",
            "--config", str(tmp_config),
            "--override", "--configure-only",
        ],
        check=True,
    )
    subprocess.run(
        ["crocodash", "process", "--caseroot", case_cfg["caseroot"], "--all"],
        check=True,
    )
    stage_output(cfg, case_cfg["inputdir"])


def run_create_test(test_name_to_run):
    # create_test's cmake build needs the system OpenMPI, not CrocoDash's own
    # conda-env MPI (mpi4py/esmpy) -- run_case.sh achieves this with `conda
    # deactivate` before its own build step; since this whole script runs
    # inside `conda run -n CrocoDash` (needed above for PyYAML/crocodash),
    # reconstruct the same isolation explicitly by stripping the CrocoDash
    # env's own bin dir from PATH for just this one subprocess call.
    #
    # CIME's short-term archiver (case_st_archive.py) shells out to `ncdump`
    # to inspect restart-file time axes -- this container only apt-installs
    # libnetcdf-dev/libnetcdff-dev (headers + shared libs), not the
    # netcdf-bin package, so `ncdump` only exists inside the CrocoDash conda
    # env we're about to strip out. Symlink it (and ncgen/nccopy, same
    # package) into /usr/local/bin, which stays on PATH after the strip
    # below, before doing the strip.
    for tool in ("ncdump", "ncgen", "nccopy"):
        src = shutil.which(tool)
        dest = Path("/usr/local/bin", tool)
        if src and not dest.exists():
            dest.symlink_to(src)

    env = dict(os.environ)
    env["PATH"] = os.pathsep.join(
        p for p in env.get("PATH", "").split(os.pathsep) if "/envs/CrocoDash" not in p
    )
    env["ESMFMKFILE"] = str(
        next(Path(env["ESMF_INSTALL_PREFIX"], "lib").rglob("esmf.mk"))
    )
    env["OMPI_CC"] = "gcc"
    env["OMPI_FC"] = "gfortran"
    env["OMPI_CXX"] = "g++"
    env.pop("NCAR_HOST", None)

    subprocess.run(
        ["./create_test", test_name_to_run, "--test-root", TEST_ROOT, "-o"],
        cwd=CESM_SCRIPTS_DIR,
        check=True,
        env=env,
    )


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("test_name", help="Full CIME test name to run")
    args = parser.parse_args()

    cfg = load_config(args.test_name)
    test_name_to_run = compset_override_name(args.test_name, cfg)

    os.environ["USER"] = "root"
    os.environ["DIN_LOC_ROOT"] = DIN_LOC_ROOT
    os.environ.pop("NCAR_HOST", None)

    regenerate_data(cfg)
    run_create_test(test_name_to_run)


if __name__ == "__main__":
    main()
