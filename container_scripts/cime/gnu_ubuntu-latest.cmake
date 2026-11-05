# Explicit MPI and compiler paths for the ubuntu-latest container machine.
#
# When /glade is bind-mounted (e.g. on NCAR Derecho/Casper), HPC MPI libraries
# loaded on the host can appear on PATH and get picked up by cmake's FindMPI,
# causing test-compilation failures with libraries that are not present inside
# the container.  Hardcoding /usr/bin paths here ensures the container's own
# openmpi is always used regardless of the host environment.
set(MPIFC "/usr/bin/mpifort")
set(MPICC "/usr/bin/mpicc")
set(MPICXX "/usr/bin/mpicxx")
set(SFC "/usr/bin/gfortran")
set(SCC "/usr/bin/gcc")
set(SCXX "/usr/bin/g++")
