#!/bin/bash
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash
unset NCAR_HOST

cd /workspace
python inside_container_create_case.py

export DIN_LOC_ROOT=/root/cesm/inputdata


cd /workspace/case
./xmlchange NTASKS=1
./case.setup --reset
./xmlchange DIN_LOC_ROOT=/root/cesm/inputdata
conda deactivate
export ESMFMKFILE=$(find ${ESMF_INSTALL_PREFIX}/lib -name "esmf.mk" | head -1)
export OMPI_CC=gcc
export OMPI_FC=gfortran
export OMPI_CXX=g++
unset NCAR_HOST
./case.build
cp CaseDocs/datm.streams.xml .
sed -i 's/<year_align>1<\/year_align>/<year_align>1958<\/year_align>/g' datm.streams.xml
./case.submit --no-batch