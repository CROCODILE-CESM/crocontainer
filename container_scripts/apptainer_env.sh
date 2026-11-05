# Apptainer runs this at every exec, shell and run (the Dockerfile puts it in
# /.singularity.d/env). Apptainer brings the host's environment in; Podman and
# Docker don't, and have HOME=/root already.
#
# CIME reads the container's machine from ~/.cime (/root/.cime), whatever CESM
# the case uses, so ~ must be the container's.
export HOME=/root
# On NCAR systems CIME refuses a case whose machine isn't the one NCAR_HOST names.
export NCAR_HOST=
