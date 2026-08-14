#!/bin/bash
# Regenerates a regional test's CrocoDash input data, then runs it via CIME's
# create_test -- testlist_mom.xml/testmods_dirs are used entirely unmodified,
# stock SMS/ERS, no custom SystemTests. See discover_regional_tests.py for
# how the container CI enumerates which tests to run this way, and
# regional_configs/*.yaml for the CrocoDash config schema.
#
# Usage: run_test_suite.sh <full-test-name>
#   e.g. run_test_suite.sh \
#     SMS_D_Ld2.USER_RES.CR_JRA_GLOFAS.ubuntu-latest_gnu.mom-regional-base--mom-regional-container_smoke
#
# The test name's testmods component (its last dot-separated field) selects
# which container_scripts/regional_configs/ CrocoDash config to regenerate
# from -- everything up to the first "--" (the container-only PE-layout
# override appended by discover_regional_tests.py is stripped, since it
# carries no data implications). Onboard a new regional test by adding a
# %REGIONAL-compset entry to testlist_mom.xml plus a matching config file
# here; discover_regional_tests.py picks it up automatically, no CI changes
# needed.
set -euo pipefail

TEST_NAME="$1"
TESTMODS="${TEST_NAME##*.}"
CONFIG_KEY="${TESTMODS%%--*}"
CONFIG="/workspace/regional_configs/${CONFIG_KEY}.yaml"

if [[ ! -f "$CONFIG" ]]; then
    echo "No CrocoDash config found for testmods '${CONFIG_KEY}' at ${CONFIG}" >&2
    echo "Add one under container_scripts/regional_configs/ to onboard this test." >&2
    exit 1
fi

# testlist_mom.xml's regional test entries (external MOM_interface repo) are
# all registered against real-JRA55/GLOFAS compsets (CR_JRA_GLOFAS etc) --
# there's no NYF regional compset registered there today. Rather than wait
# on that repo, swap the compset in the *test name we actually run* for
# whatever compset_override this config declares (CIME resolves a compset
# field by either alias or full long name, so this is a legal substitution,
# not a hack -- see CIME/XML/compsets.py::get_compset_match). This lets a
# CrocoDash config target a cheaper compset (no real DATM%JRA download, no
# real DROF%GLOFAS runoff-mapping file) than the one testlist_mom.xml
# registers, entirely on the crocontainer side -- testlist_mom.xml stays
# the source of truth for *which* tests exist, just not for which exact
# compset variant each one actually runs against in this container.
COMPSET_OVERRIDE=$(grep -E '^compset_override:' "$CONFIG" | sed -E 's/^compset_override:\s*//' | tr -d "\"'" || true)
TEST_NAME_TO_RUN="$TEST_NAME"
if [[ -n "$COMPSET_OVERRIDE" ]]; then
    IFS='.' read -r -a NAME_FIELDS <<< "$TEST_NAME"
    NAME_FIELDS[2]="$COMPSET_OVERRIDE"
    IFS='.'
    TEST_NAME_TO_RUN="${NAME_FIELDS[*]}"
    unset IFS
    echo "Overriding compset for this run: ${NAME_FIELDS[2]} (testlist_mom.xml still lists this test under its original compset)"
fi

source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash
export USER=root
export DIN_LOC_ROOT=/root/cesm/inputdata
unset NCAR_HOST

python /workspace/regenerate_regional_testdata.py "$CONFIG"
conda deactivate

# Same MPI/cmake isolation run_case.sh already applies for ad hoc cases --
# prevents HPC MPI libraries (e.g. from a bind-mounted /glade on Derecho)
# from leaking into the cmake build via PATH.
export ESMFMKFILE=$(find "${ESMF_INSTALL_PREFIX}/lib" -name "esmf.mk" | head -1)
export OMPI_CC=gcc
export OMPI_FC=gfortran
export OMPI_CXX=g++
unset NCAR_HOST

cd /workspace/CESM/cime/scripts
./create_test "${TEST_NAME_TO_RUN}" \
    --test-root /root/cesm/scratch/tests/regional \
    -o
