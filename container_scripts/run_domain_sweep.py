#!/usr/bin/env python
"""Run CrocoDash's forcing pipeline over the domain catalog, one domain per case.

This is the end-to-end half of CrocoDash's domain test matrix. The pure half
(grid metrics, bounding boxes, convention pairs) lives in CrocoDash's own pytest
suite, which is cheap enough to run anywhere. This half needs a real CESM root
and a machine definition, costs ~30s per domain, and so lives here instead --
the container is the only place both are available without Derecho.

Unlike run_regional_test.py this never touches create_test, testlist_mom.xml or
testmods, and never builds or runs MOM6. It stops at "did CrocoDash produce
plausible forcing for this topology", which is the question the catalog exists
to ask: whether a polar cap, an antimeridian-straddling box or a rotated grid
survives the path from Grid to OBC/IC files.

The catalog itself is CrocoDash's -- tests/fixtures/domains.py, one DomainSpec
per lat/lon topology -- imported rather than duplicated so there is a single
source of truth for what the domains are. DomainSpec.to_grid_config() emits the
`grid:` block directly, which is what CrocoDash's grid.type dispatch made
possible: before it, polar and rotated domains could not be written as a config
at all.

Usage:
  run_domain_sweep.py                          # every supported domain
  run_domain_sweep.py --domains arctic_cap,tiny
  run_domain_sweep.py --tags seam,polar
"""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

import yaml

# Where to read CrocoDash (and hence the catalog) from. Defaults to the
# image's own editable install; CI overrides it to a mounted checkout so the
# submodule's CrocoDash is authoritative rather than the image's baked copy.
CROCODASH_ROOT = Path(os.environ.get("CROCODASH_ROOT", "/workspace/CrocoDash"))
WORK_ROOT = Path("/workspace/domain_sweep")

# Held constant across every domain on purpose: the catalog varies the
# *horizontal* topology and nothing else, so a failure is unambiguously about
# lat/lon rather than about bathymetry or vertical resolution.
TOPO_DEPTH = 1000.0
TOPO_MIN_DEPTH = 9.5
VGRID_NK = 5
DATE_RANGE = ["2020-01-01 00:00:00", "2020-01-03 00:00:00"]

# DATM%NYF + SROF for the same reason as mom-regional-base.yaml: no JRA55
# download, no GLOFAS runoff-mapping file. Nothing here ever runs MOM6, so the
# atm/rof choice only has to be something CIME will resolve.
COMPSET = "1850_DATM%NYF_SLND_SICE_MOM6%REGIONAL_SROF_SGLC_SWAV"

# What a completed run must leave behind. A missing file is a hard failure; a
# file that exists but is entirely NaN is the characteristic symptom of a
# bounding box that missed its source data, which is why it is checked too.
EXPECTED_OUTPUTS = [
    "forcing_obc_segment_001.nc",
    "forcing_obc_segment_002.nc",
    "forcing_obc_segment_003.nc",
    "forcing_obc_segment_004.nc",
    "init_tracers.nc",
    "init_eta.nc",
    "init_vel.nc",
]


CATALOG_RELPATH = "tests/fixtures/domains.py"

# A domain that has not finished in this long is treated as hung and killed.
# Generous next to the ~12s a healthy domain takes, so this can only fire on a
# genuine wedge -- but bounded, because without it one hung domain consumes the
# whole job: CROCODILE-CESM/crocontainer#7's first full run spent 58 of its 60
# minutes stuck on western_hemi_neg and the remaining 12 domains never ran.
DOMAIN_TIMEOUT_S = 600


def load_catalog():
    """Import the DomainSpec catalog out of CrocoDash's own test fixtures.

    Imported rather than duplicated so there is a single source of truth for
    what the domains are. That does couple this script to the CrocoDash
    checkout it is pointed at: the catalog arrives with CROCODILE-CESM/
    CrocoDash#274, so a submodule pointer older than that has a tests/
    directory without it.
    """
    catalog = CROCODASH_ROOT / CATALOG_RELPATH
    if not catalog.exists():
        sys.exit(
            f"No domain catalog at {catalog}.\n"
            "The sweep reads CrocoDash's tests/fixtures/domains.py, which "
            "arrives with CROCODILE-CESM/CrocoDash#274. Point the CrocoDash "
            "submodule at a commit that includes it."
        )

    sys.path.insert(0, str(CROCODASH_ROOT))
    from tests.fixtures.domains import DOMAINS

    return DOMAINS


def select(catalog, keys, tags):
    """Resolve the CLI options into a list of DomainSpecs.

    Domains carrying a DomainSpec.xfail are dropped unless named explicitly:
    those are the ones CrocoDash cannot produce forcing for at all (today, just
    the globally cyclic grid, which Grid.get_bounding_boxes rejects outright).
    They are pinned as expected failures in the pytest suite, and there is
    nothing for a container sweep to add.
    """
    by_key = {d.key: d for d in catalog}

    if keys:
        missing = [k for k in keys if k not in by_key]
        if missing:
            sys.exit(
                f"Unknown domain(s): {', '.join(missing)}\n"
                f"Valid keys: {', '.join(sorted(by_key))}"
            )
        return [by_key[k] for k in keys]

    if tags:
        known = {t for d in catalog for t in d.tags}
        unknown = [t for t in tags if t not in known]
        if unknown:
            sys.exit(
                f"Unknown tag(s): {', '.join(unknown)}\n"
                f"Valid tags: {', '.join(sorted(known))}"
            )
        selected = [d for d in catalog if d.tags & set(tags)]
    else:
        selected = list(catalog)

    return [d for d in selected if not d.xfail]


def build_config(spec, caseroot, inputdir):
    return {
        "grid": spec.to_grid_config(),
        "topo": {
            "min_depth": TOPO_MIN_DEPTH,
            "source": {"type": "flat", "depth": TOPO_DEPTH},
        },
        "vgrid": {"type": "uniform", "nk": VGRID_NK, "depth": TOPO_DEPTH},
        "case": {
            "cesmroot": "/workspace/CESM",
            "caseroot": str(caseroot),
            "inputdir": str(inputdir),
            "compset": COMPSET,
            "atm_grid_name": "T62",
            "machine": "ubuntu-latest",
            "project": "PROJ123",
        },
        "forcings": {
            "date_range": DATE_RANGE,
            "product_name": "reference_ocean",
            "function_name": "get_reference_ocean_data",
        },
    }


def check_outputs(inputdir):
    """Every expected file present, readable, and not entirely NaN.

    Returns a list of complaint strings; empty means the domain passed.
    """
    import numpy as np
    import xarray as xr

    problems = []
    for name in EXPECTED_OUTPUTS:
        matches = sorted(Path(inputdir).rglob(name))
        if not matches:
            problems.append(f"{name}: never produced")
            continue
        try:
            with xr.open_dataset(matches[0], decode_timedelta=False) as ds:
                all_nan = [
                    var
                    for var, da in ds.data_vars.items()
                    if np.issubdtype(da.dtype, np.floating)
                    and bool(np.isnan(da.values).all())
                ]
        except Exception as exc:  # noqa: BLE001 -- report, don't abort the sweep
            problems.append(f"{name}: unreadable ({exc})")
            continue
        if all_nan:
            problems.append(f"{name}: entirely NaN ({', '.join(all_nan)})")
    return problems


def run_domain(spec, keep):
    """Create and process one domain in its own crocodash subprocess.

    A subprocess per domain is not just tidiness. CrocoDash reads ProConPy's
    process-global cvars (CASEROOT, MB_ATTEMPT_ID) during both Case
    construction and configure_forcings, so building a second Case in one
    process silently repoints the first. Process isolation makes that
    structurally impossible.

    `crocodash create` runs the whole pipeline -- Grid/Topo/VGrid, the CESM
    case, configure_forcings and process_forcings -- so no separate `crocodash
    process` call is needed here; REFERENCE_OCEAN synthesizes its data in
    memory, so there is no raw-data fetch step to interleave.
    """
    domain_dir = WORK_ROOT / spec.key
    caseroot = domain_dir / "case"
    inputdir = domain_dir / "inputdir"
    if domain_dir.exists():
        shutil.rmtree(domain_dir)
    domain_dir.mkdir(parents=True)

    config_path = domain_dir / "config.yaml"
    with open(config_path, "w") as f:
        yaml.safe_dump(build_config(spec, caseroot, inputdir), f, sort_keys=False)

    # PYTHONFAULTHANDLER turns the SIGABRT below into a Python traceback from
    # every thread. Without it a hung domain dies mute and all we learn is that
    # it took too long, which is what the first full run of this sweep got.
    env = dict(os.environ, PYTHONFAULTHANDLER="1")
    log_path = domain_dir / "crocodash.log"
    start = time.time()
    with open(log_path, "w") as log:
        proc = subprocess.Popen(
            ["crocodash", "create", "--config", str(config_path), "--override"],
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        try:
            proc.wait(timeout=DOMAIN_TIMEOUT_S)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
            # SIGABRT rather than SIGKILL: with faulthandler armed the process
            # dumps where it is stuck on the way out, which is the only thing
            # that makes a hang diagnosable from CI logs alone.
            proc.send_signal(signal.SIGABRT)
            try:
                proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    elapsed = time.time() - start
    tail = "\n".join(log_path.read_text().splitlines()[-40:])

    # Both the exit code and the outputs are checked, and the outputs matter
    # more: `crocodash create` has been observed to print a "Case Configuration
    # Error" and still exit 0 (e.g. when the caseroot's parent is missing, so
    # create_newcase never runs), leaving configure_forcings' config.json
    # behind but no forcing at all. Trusting the exit code alone would call
    # that a pass.
    if timed_out:
        problems = [
            f"crocodash create still running after {DOMAIN_TIMEOUT_S}s "
            f"-- killed. Stack at the time of the kill:\n{tail}"
        ]
    elif proc.returncode != 0:
        problems = [f"crocodash create exited {proc.returncode}:\n{tail}"]
    else:
        problems = check_outputs(inputdir)

    if not keep:
        shutil.rmtree(domain_dir, ignore_errors=True)

    return {"key": spec.key, "seconds": elapsed, "problems": problems}


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--domains", help="Comma-separated domain keys")
    parser.add_argument("--tags", help="Comma-separated domain tags")
    parser.add_argument(
        "--keep",
        action="store_true",
        help="Keep each domain's caseroot/inputdir instead of deleting it",
    )
    parser.add_argument("--json-summary", help="Write the results here as JSON")
    parser.add_argument(
        "--list-domains",
        action="store_true",
        help="Print the selected domain keys as a JSON array and exit",
    )
    args = parser.parse_args()

    keys = args.domains.split(",") if args.domains else None
    tags = args.tags.split(",") if args.tags else None

    specs = select(load_catalog(), keys, tags)

    # The CI matrix builds itself from this, so the list of jobs and the list
    # of domains a job would sweep come from the same select() call. Emitting
    # the keys any other way (a hardcoded matrix, a second parser) would let
    # the two drift apart the moment a domain is added or xfailed.
    if args.list_domains:
        print(json.dumps([s.key for s in specs]))
        return 0
    WORK_ROOT.mkdir(parents=True, exist_ok=True)
    print(
        f"Sweeping {len(specs)} domains: {', '.join(s.key for s in specs)}\n",
        flush=True,
    )

    results = []
    for i, spec in enumerate(specs, 1):
        print(f"[{i}/{len(specs)}] {spec.key}: {spec.description}", flush=True)
        result = run_domain(spec, args.keep)
        results.append(result)
        if result["problems"]:
            print(f"    FAIL ({result['seconds']:.0f}s)", flush=True)
            for problem in result["problems"]:
                print(f"      {problem}", flush=True)
        else:
            print(f"    ok ({result['seconds']:.0f}s)", flush=True)

        # Rewritten after every domain, not once at the end. A sweep that dies
        # partway -- the CI job hitting its own wall-clock limit, most likely --
        # still leaves a summary for the domains that did run, instead of the
        # nothing-at-all the end-of-run write produced.
        if args.json_summary:
            with open(args.json_summary, "w") as f:
                json.dump(results, f, indent=2)

    failed = [r for r in results if r["problems"]]
    print(f"\n{len(results) - len(failed)}/{len(results)} domains passed")
    if failed:
        print("Failed: " + ", ".join(r["key"] for r in failed))

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
