#!/bin/bash
# Makes a case at /workspace/case, then builds and runs it. The case comes from
# the first of:
#   1. a CrocoDash YAML config at /workspace/case_config.yaml (its case.caseroot
#      and case.inputdir must be /workspace/case and /workspace/inputdir);
#   2. a `crocodash bundle` directory at /workspace/bundle;
#   3. the built-in Panama demo.
# NTASKS sets the MPI tasks of every component (default 1; more needs the intel
# image). Output stays in /root/cesm/scratch/case/run.
#
# This is only a shortcut: in the container, `crocodash create` then
# ./case.build and ./case.submit in the case directory do the same.
set -euo pipefail

if [[ -f /workspace/case_config.yaml ]]; then
    crocodash create --config /workspace/case_config.yaml --override
elif [[ -n "$(ls -A /workspace/bundle 2>/dev/null)" ]]; then
    if [[ ! -f /workspace/bundle/bundle.json ]]; then
        echo "/workspace/bundle has no bundle.json: it is a bundle from a CrocoDash" \
            "older than 'crocodash create --from'. Bundle the case again." >&2
        exit 1
    fi
    # The container can't download forcing data: the bundle carries the
    # processed forcings, so they are not processed again (--configure-only).
    crocodash create --from /workspace/bundle --caseroot /workspace/case \
        --inputdir /workspace/inputdir --cesmroot "${CESMROOT}" \
        --machine ubuntu-latest --project PROJ123 --configure-only --no-input
else
    bash /workspace/panama_demo_setup.sh
fi

cd /workspace/case
if [[ -n "${NTASKS:-}" ]]; then
    ./xmlchange NTASKS="${NTASKS}"
    ./case.setup --reset
fi
./xmlchange DOUT_S=FALSE  # leave the output in the run directory
./case.build
./case.submit

# case.submit reports success even when the run fails; CaseStatus does not.
tail -n 20 CaseStatus | grep -q "case.run success" || { echo "case.run failed, see CaseStatus" >&2; exit 1; }
