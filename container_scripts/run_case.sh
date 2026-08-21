#!/bin/bash
set -euo pipefail

source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash

export USER=root
export DIN_LOC_ROOT=/root/cesm/inputdata
unset NCAR_HOST

# Case setup -- two modes, checked in order:
#   1. Mount a CrocoDash YAML case config as /workspace/case_config.yaml to
#      build any case directly via the CLI (general-purpose mode). Its
#      case.caseroot/inputdir must be /workspace/case and /workspace/inputdir
#      to match the paths this script uses below.
#        docker run -v /path/to/your_config.yaml:/workspace/case_config.yaml ...
#   2. Mount a `crocodash bundle` output directory as /workspace/bundle to
#      reconstruct a case shared from another machine/user.
# One of the two must be mounted -- there's no built-in demo case fallback;
# see container_scripts/regional_configs/*.yaml + run_regional_test.py for a
# CI-validated, ready-to-run regional case definition instead.
if [[ -f /workspace/case_config.yaml ]]; then
    crocodash create --config /workspace/case_config.yaml --override
elif [[ -f /workspace/bundle/crocodash_case.yaml ]]; then
    crocodash fork \
        --bundle /workspace/bundle \
        --caseroot /workspace/case \
        --inputdir /workspace/inputdir \
        --cesmroot "${CESMROOT}" \
        --machine ubuntu-latest \
        --project PROJ123 \
        --plan '{"xml_files": true, "user_nl": true, "source_mods": true, "xmlchanges": false}'
else
    echo "Mount a CrocoDash YAML case config at /workspace/case_config.yaml, or a" >&2
    echo "\`crocodash bundle\` output directory at /workspace/bundle. See the README." >&2
    exit 1
fi

conda deactivate

cd /workspace/case

./xmlchange NTASKS=1
./case.setup --reset
./xmlchange DOUT_S=False
./xmlchange DIN_LOC_ROOT=/root/cesm/inputdata

# Inject compiler macros that hardcode the container's MPI paths.
# Prevents HPC MPI libraries (e.g. from a bind-mounted /glade on Derecho)
# from leaking into the cmake build via PATH.
cp /workspace/cmake_macros/gnu_ubuntu-latest.cmake cmake_macros/

export ESMFMKFILE=$(find ${ESMF_INSTALL_PREFIX}/lib -name "esmf.mk" | head -1)
export OMPI_CC=gcc
export OMPI_FC=gfortran
export OMPI_CXX=g++
unset NCAR_HOST

# Limit JRA55 files to only the years needed by this run (skip for NYF)
DATM_MODE=$(./xmlquery DATM_MODE --value 2>/dev/null || echo "")
if [[ "$DATM_MODE" == *"JRA"* ]]; then
    YR_START=$(./xmlquery DATM_YR_START --value)
    YR_END=$(./xmlquery DATM_YR_END --value)
    YR_PREV=$((YR_START - 1))
    BASE="/root/cesm/inputdata/ocn/jra55/v1.3_noleap/JRA.v1.3"

    cat >> user_nl_datm_streams << EOF
CORE_IAF_JRA.PREC:year_first = ${YR_PREV}
CORE_IAF_JRA.PREC:year_last = ${YR_END}
CORE_IAF_JRA.PREC:year_align = ${YR_PREV}
CORE_IAF_JRA.PREC:datafiles = ${BASE}.prec.TL319.${YR_PREV}.171019.nc,${BASE}.prec.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.LWDN:year_first = ${YR_PREV}
CORE_IAF_JRA.LWDN:year_last = ${YR_END}
CORE_IAF_JRA.LWDN:year_align = ${YR_PREV}
CORE_IAF_JRA.LWDN:datafiles = ${BASE}.lwdn.TL319.${YR_PREV}.171019.nc,${BASE}.lwdn.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.SWDN:year_first = ${YR_PREV}
CORE_IAF_JRA.SWDN:year_last = ${YR_END}
CORE_IAF_JRA.SWDN:year_align = ${YR_PREV}
CORE_IAF_JRA.SWDN:datafiles = ${BASE}.swdn.TL319.${YR_PREV}.171019.nc,${BASE}.swdn.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.Q_10:year_first = ${YR_PREV}
CORE_IAF_JRA.Q_10:year_last = ${YR_END}
CORE_IAF_JRA.Q_10:year_align = ${YR_PREV}
CORE_IAF_JRA.Q_10:datafiles = ${BASE}.q_10.TL319.${YR_PREV}.171019.nc,${BASE}.q_10.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.SLP_:year_first = ${YR_PREV}
CORE_IAF_JRA.SLP_:year_last = ${YR_END}
CORE_IAF_JRA.SLP_:year_align = ${YR_PREV}
CORE_IAF_JRA.SLP_:datafiles = ${BASE}.slp.TL319.${YR_PREV}.171019.nc,${BASE}.slp.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.T_10:year_first = ${YR_PREV}
CORE_IAF_JRA.T_10:year_last = ${YR_END}
CORE_IAF_JRA.T_10:year_align = ${YR_PREV}
CORE_IAF_JRA.T_10:datafiles = ${BASE}.t_10.TL319.${YR_PREV}.171019.nc,${BASE}.t_10.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.U_10:year_first = ${YR_PREV}
CORE_IAF_JRA.U_10:year_last = ${YR_END}
CORE_IAF_JRA.U_10:year_align = ${YR_PREV}
CORE_IAF_JRA.U_10:datafiles = ${BASE}.u_10.TL319.${YR_PREV}.171019.nc,${BASE}.u_10.TL319.${YR_END}.171019.nc
CORE_IAF_JRA.V_10:year_first = ${YR_PREV}
CORE_IAF_JRA.V_10:year_last = ${YR_END}
CORE_IAF_JRA.V_10:year_align = ${YR_PREV}
CORE_IAF_JRA.V_10:datafiles = ${BASE}.v_10.TL319.${YR_PREV}.171019.nc,${BASE}.v_10.TL319.${YR_END}.171019.nc
EOF
fi

# Optional build sharing, for CI. MOM6's executable does not depend on the
# domain: CrocoDash always sets MOM6_MEMORY_MODE=dynamic_symmetric, so
# NIGLOBAL/NJGLOBAL are read from MOM_input at runtime rather than compiled in.
# One build therefore serves every grid using the same compset, machine and
# compiler, which is what lets several domains share a single compile.
#
#   CROC_BUILD_ONLY=1        build, save the build tree to $CROC_BUILD_ARCHIVE, stop
#   CROC_BUILD_ARCHIVE=path  with CROC_BUILD_ONLY, where to write it;
#                            otherwise, a build tree to restore instead of compiling
#
# Neither is set in normal use, so the default path is unchanged: build, run.
if [[ -n "${CROC_BUILD_ONLY:-}" ]]; then
    ./case.build
    EXEROOT=$(./xmlquery EXEROOT --value)
    SHAREDLIBROOT=$(./xmlquery SHAREDLIBROOT --value)
    # Absolute paths, restored to the same locations on the other side --
    # workable only because every case here lives at /workspace/case in this
    # same image, so EXEROOT is identical across jobs.
    tar czf "${CROC_BUILD_ARCHIVE:-/workspace/build.tgz}" \
        -C / "${EXEROOT#/}" "${SHAREDLIBROOT#/}"
    echo "Saved build tree to ${CROC_BUILD_ARCHIVE:-/workspace/build.tgz}"
    exit 0
fi

if [[ -n "${CROC_BUILD_ARCHIVE:-}" ]]; then
    # Restored after case creation, not before: crocodash create --override
    # rebuilds the case directory, and EXEROOT may sit beneath it.
    tar xzf "${CROC_BUILD_ARCHIVE}" -C /
    ./xmlchange BUILD_COMPLETE=TRUE
    echo "Restored prebuilt MOM6 from ${CROC_BUILD_ARCHIVE}; skipping case.build"
else
    ./case.build
fi

# Optionally keep what the run produced. CI uploads this as an artifact, so a
# failed run is inspectable after the fact instead of only through whatever
# reached stdout -- MOM6's own diagnosis usually lands in ocn.log/cesm.log
# rather than on the console.
#
#   CROC_RUN_ARCHIVE=path    tar RUNDIR (plus a few caseroot files) here
#
# Written whether the run succeeds or fails, and the run's exit status is
# preserved, because the failing case is the one worth looking at.
if [[ -n "${CROC_RUN_ARCHIVE:-}" ]]; then
    rc=0
    ./case.submit --no-batch || rc=$?

    RUNDIR=$(./xmlquery RUNDIR --value)
    STAGE=$(mktemp -d)
    mkdir -p "${STAGE}/rundir" "${STAGE}/caseroot"
    cp -a "${RUNDIR}/." "${STAGE}/rundir/" 2>/dev/null || true
    # The case-side files needed to make sense of the logs: what MOM6 was
    # actually told to do, and how far the case got.
    for f in user_nl_mom CaseStatus CaseDocs/MOM_input CaseDocs/MOM_override; do
        [[ -e "$f" ]] && cp -a "$f" "${STAGE}/caseroot/" 2>/dev/null || true
    done
    tar czf "${CROC_RUN_ARCHIVE}" -C "${STAGE}" . || true
    rm -rf "${STAGE}"
    echo "Saved run output to ${CROC_RUN_ARCHIVE} (exit ${rc})"
    exit $rc
fi

./case.submit --no-batch
