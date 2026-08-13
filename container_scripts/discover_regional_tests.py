#!/usr/bin/env python
"""List every testlist_mom.xml test whose compset carries the MOM6%REGIONAL
component tag -- the MOM interface's own testlist/config_compsets.xml are
treated as the source of truth for what's a "regional" test, so onboarding
a new one is just adding a %REGIONAL-compset entry there. Emits each as a
full CIME test name targeting this container's machine, with the
container-specific PE-layout testmods appended (ubuntu-latest caps
MAX_MPITASKS_PER_NODE well below what the Derecho-sized regional testmods
assume). ERS (restart) tests are excluded -- see EXCLUDED_TEST_TYPES.

Usage: discover_regional_tests.py [cesmroot]  (default: /workspace/CESM)

Emits a JSON array on stdout, e.g. for a GitHub Actions matrix:
  ["SMS_D_Ld2.USER_RES.CR_JRA_GLOFAS.ubuntu-latest_gnu.mom-regional-base--mom-regional-container_smoke"]
"""
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

CONTAINER_MACHINE_COMPILER = "ubuntu-latest_gnu"
# Layers ./xmlchange NTASKS=1 on top of whichever base testmods a discovered
# test uses, via CIME's own "--" multi-mods composition (e.g.
# "mom-regional-base--mom-regional-container_smoke") -- overrides the
# Derecho-sized NTASKS_OCN the base regional testmods set, which exceeds
# ubuntu-latest's MAX_MPITASKS_PER_NODE. The matching testmods dir lives in
# this repo at container_scripts/testmods_overrides/mom/regional/
# container_smoke/ and is mounted into the container's CESM checkout by
# container-test.yml at CI runtime -- no change to the external
# CROCODILE-CESM/CESM fork needed.
CONTAINER_PES_TESTMODS = "mom-regional-container_smoke"
REGIONAL_MARKER = "MOM6%REGIONAL"
# Restart (ERS) tests are out of scope for now -- already validated
# separately on Derecho, and not needed to check CrocoDash's forcing
# pipeline, which is this suite's actual goal.
EXCLUDED_TEST_TYPES = ("ERS",)


def load_compset_lnames(path):
    root = ET.parse(path).getroot()
    return {c.findtext("alias"): c.findtext("lname") for c in root.findall("compset")}


def discover(cesmroot):
    testlist_path = (
        cesmroot / "components/mom/cime_config/testdefs/testlist_mom.xml"
    )
    compsets_path = cesmroot / "components/mom/cime_config/config_compsets.xml"

    lnames = load_compset_lnames(compsets_path)
    root = ET.parse(testlist_path).getroot()

    tests = []
    for test in root.findall("test"):
        compset = test.get("compset")
        lname = lnames.get(compset, compset)
        if REGIONAL_MARKER not in lname:
            continue

        name = test.get("name")
        if name.startswith(EXCLUDED_TEST_TYPES):
            continue

        grid = test.get("grid")
        testmods = test.get("testmods")

        # testlist testmods use "/"-separated component/subdir paths (e.g.
        # "mom/regional-base--mom/debug"); CIME test names use "-" in their
        # place (e.g. "mom-regional-base--mom-debug") -- a global replace is
        # safe here since "--" (the multi-mods separator) contains no "/".
        base_testmods = testmods.replace("/", "-") if testmods else None
        full_testmods = (
            f"{base_testmods}--{CONTAINER_PES_TESTMODS}"
            if base_testmods
            else CONTAINER_PES_TESTMODS
        )

        tests.append(
            f"{name}.{grid}.{compset}.{CONTAINER_MACHINE_COMPILER}.{full_testmods}"
        )

    return tests


def main():
    cesmroot = Path(sys.argv[1] if len(sys.argv) > 1 else "/workspace/CESM")
    tests = discover(cesmroot)
    json.dump(tests, sys.stdout)


if __name__ == "__main__":
    main()
