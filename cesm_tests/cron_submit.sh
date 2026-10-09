#!/bin/bash
# Weekly entry point, run from crontab on cron.hpc.ucar.edu (see README.md).
# The cron host only has 1 GB and no software stack, so this just updates this
# repo and submits run_mom_tests.pbs, which pulls CESM and CrocoDash itself.
#
# CI_ROOT : holds the CESM and CrocoDash clones (default: /glade/work/$USER/croc_ci)
# MAILTO  : where PBS mails when the job ends (default: $USER@ucar.edu)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CI_ROOT=${CI_ROOT:-/glade/work/$USER/croc_ci}

git -C "$HERE" pull -q --ff-only
cd "$HERE"
/opt/pbs/bin/qsub -q main@desched1 -m ae -M "${MAILTO:-$USER@ucar.edu}" \
  -v UPDATE=1,PUBLISH=1,CESMROOT=$CI_ROOT/CESM,CROCODASH_SRC=$CI_ROOT/CrocoDash \
  run_mom_tests.pbs
