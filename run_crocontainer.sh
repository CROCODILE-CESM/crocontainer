#!/bin/bash

conda run -n CrocoDash python /workspace/inside_container_create_case.py
conda deactivate 2>/dev/null || true
conda activate cesm_build
cd /workspace/case
./xmlchange NTASKS=1
./case.build
./case.submit --no-batch