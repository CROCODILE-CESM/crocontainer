# Explicit compilers and MPI for the ubuntu-latest machine in the intel image
# (slim-intel and intel). As in gnu_ubuntu-latest.cmake, absolute paths keep MPI or
# compilers from a bind-mounted host (e.g. /glade) out of the build.
#
# ccs_config's intel.cmake still names ifort, which oneAPI 2025 no longer ships;
# like Derecho's intel_derecho.cmake, use ifx.
set(MPIFC "/opt/intel/oneapi/mpi/latest/bin/mpiifx")
set(MPICC "/opt/intel/oneapi/mpi/latest/bin/mpiicx")
set(MPICXX "/opt/intel/oneapi/mpi/latest/bin/mpiicpx")
set(SFC "/opt/intel/oneapi/compiler/latest/bin/ifx")
set(SCC "/opt/intel/oneapi/compiler/latest/bin/icx")
set(SCXX "/opt/intel/oneapi/compiler/latest/bin/icpx")

# intel.cmake links MKL, which the image leaves out (it adds ~3 GB); BLAS and
# LAPACK come from Ubuntu's reference libraries, as in the gnu image.
string(REPLACE " -mkl=cluster" "" SLIBS "${SLIBS}")
string(REPLACE " -mkl" "" SLIBS "${SLIBS}")

if (DEBUG)
  # As on Derecho: -check uninit errors in glibc with ifx 2025.
  string(APPEND FFLAGS " -check nouninit")
endif()
