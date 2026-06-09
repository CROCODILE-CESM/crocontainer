#!/bin/bash
set -euo pipefail

source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash

export USER=root
export DIN_LOC_ROOT=/root/cesm/inputdata
unset NCAR_HOST

# Case setup: use case_setup.py if mounted, otherwise reconstruct from bundle.
# Mount your setup script as /workspace/case_setup.py to use direct mode:
#   docker run -v /path/to/your_setup.py:/workspace/case_setup.py ...
if [[ -f /workspace/case_setup.py ]]; then
    python /workspace/case_setup.py
else
    cd /workspace
    python create_case_from_bundle.py
fi

conda deactivate

cd /workspace/case

./xmlchange NTASKS=1
./case.setup --reset
./xmlchange DOUT_S=False
./xmlchange DIN_LOC_ROOT=/root/cesm/inputdata

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

./case.build
./case.submit --no-batch
