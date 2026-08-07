#!/bin/bash
# Built-in Panama demo case, used automatically by run_case.sh when neither
# /workspace/case_config.yaml nor /workspace/bundle is mounted.
#
# Stages pre-fetched GEBCO bathymetry and GLORYS OBC/IC test data from AWS S3
# -- crocontainer's own CI/demo environments have no live Copernicus Marine
# access -- then builds the case via the crocodash CLI. To run your own case
# instead, mount a YAML case config at /workspace/case_config.yaml (see the
# README's Quick Start); panama_case_config.yaml is a ready-to-use template.
set -euo pipefail

CONFIG_PATH=/workspace/panama_case_config.yaml
S3_BASE="https://crocodile-cesm.s3.us-east-1.amazonaws.com/CrocoDash/data/testing_data"
RAW_DATA_DIR=/workspace/inputdir/extract_forcings/raw_data

# GEBCO bathymetry covering the Panama domain -- must exist before
# `crocodash create` builds the Topo from it (path matches
# panama_case_config.yaml's topo.source.bathymetry_path).
mkdir -p /tmp
wget -q -O /tmp/gebco.nc "${S3_BASE}/gebco_2026_n20.0_s0.0_w-90.0_e-70.0.nc"

# Build the grid/topo/vgrid/case and run configure_forcings, but stop short
# of process_forcings -- pre-fetched GLORYS raw data must be staged into the
# case's extract_forcings/raw_data dir first (below).
crocodash create --config "${CONFIG_PATH}" --override --configure-only

mkdir -p "${RAW_DATA_DIR}"
for fname in \
    east_unprocessed.20200101_20200105.nc \
    ic_unprocessed.nc \
    north_unprocessed.20200101_20200105.nc \
    south_unprocessed.20200101_20200105.nc \
    west_unprocessed.20200101_20200105.nc
do
    wget -q -O "${RAW_DATA_DIR}/${fname}" "${S3_BASE}/${fname}"
done

# Regrid OBC/IC data to the Panama grid -> writes to INPUTDIR/ocean/
crocodash process --caseroot /workspace/case --all
