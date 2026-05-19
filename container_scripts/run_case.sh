#!/bin/bash

# Activate the Conda Environmen
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash

# Unset a CIME Variable
unset NCAR_HOST

# Read the case bundle and create a new case
cd /workspace
python create_case_from_bundle.py

# Make sure DIN_LOC_ROOT is set
export DIN_LOC_ROOT=/root/cesm/inputdata

# Finish CrocoDash Part
conda deactivate

# Go to case
cd /workspace/case

# For case.submit --no-batch we use 1 task
./xmlchange NTASKS=1
./case.setup --reset

# Ensure DIN_LOC_ROOT
./xmlchange DIN_LOC_ROOT=/root/cesm/inputdata

# Ensure ESMFMKFile
export ESMFMKFILE=$(find ${ESMF_INSTALL_PREFIX}/lib -name "esmf.mk" | head -1)

# Ensure GNU
export OMPI_CC=gcc
export OMPI_FC=gfortran
export OMPI_CXX=g++

# Ensure NCAR_HOST
unset NCAR_HOST

# Build
./case.build

# Make sure datm is aligned (not necessary but kinda nice)
cp CaseDocs/datm.streams.xml .
sed -i 's/<year_align>1<\/year_align>/<year_align>1958<\/year_align>/g' datm.streams.xml

# Submit
./case.submit --no-batch