#!/bin/bash
# Turns the gnu crocontainer image into the intel one (Dockerfile.intel):
#   1. ifx/icx/icpx and Intel MPI from Intel's apt repo;
#   2. the libraries CESM links that carry Fortran modules or MPI, rebuilt with
#      them: netcdf-fortran, PnetCDF and ESMF (netcdf-c and HDF5 stay Ubuntu's);
#   3. intel made the default compiler of the container's CIME machine.
#
# Why: when MOM6 reads its grid, CESM's FMS hands mpp_scatter a buffer that is
# only allocated on the root PE. gfortran segfaults on the other PEs; ifx does
# not (Derecho's intel builds run it on many tasks). So the gnu image runs MOM6
# on one task, and this one runs it on as many as the container has cores.
set -euo pipefail

ONEAPI=2025.3          # the ifx Derecho's intel/2025.3.2 builds CESM with
IMPI=2021.17           # the Intel MPI ifx 2025.3 ships with
NETCDF_FORTRAN=4.6.2
PNETCDF=1.14.1
ESMF=v8.9.1            # same as the gnu image
PREFIX=/opt/intel-libs # netcdf (Fortran built here, C linked in) and PnetCDF
ESMF_PREFIX=/usr/local/esmf-intel
JOBS=${JOBS:-$(nproc)}

# --- 1. oneAPI compilers and Intel MPI ---
apt-get update
apt-get install -y --no-install-recommends gnupg m4
wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
    | gpg --dearmor > /usr/share/keyrings/oneapi-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
    > /etc/apt/sources.list.d/oneAPI.list
apt-get update
apt-get install -y --no-install-recommends \
    intel-oneapi-compiler-fortran-${ONEAPI} \
    intel-oneapi-compiler-dpcpp-cpp-${ONEAPI} \
    intel-oneapi-mpi-devel-${IMPI}
rm -rf /var/lib/apt/lists/*

# Dockerfile.intel's PATH, the CIME machine's settings and the loader paths
# below all go through these `latest` links.
COMPILER_DIR=/opt/intel/oneapi/compiler/latest
MPI_DIR=/opt/intel/oneapi/mpi/latest
ls "${COMPILER_DIR}/bin/ifx" "${MPI_DIR}/bin/mpiifx" "${MPI_DIR}/opt/mpi/libfabric/lib/libfabric.so.1"

# The image's ENV is set up for the gnu build; build with Intel tools only.
unset LDFLAGS CPPFLAGS CFLAGS FFLAGS FCFLAGS CXXFLAGS
unset ESMF_NETCDF_INCLUDE ESMF_NETCDF_LIBPATH
export PATH=${PREFIX}/bin:${MPI_DIR}/bin:${COMPILER_DIR}/bin:${PATH}
export I_MPI_ROOT=${MPI_DIR}

# Intel's runtime libraries, for the builds below. Only here and in intel cases
# (the CIME machine sets the same LD_LIBRARY_PATH): several share their names
# with Ubuntu's (libnetcdff, libpnetcdf, libfabric, libhwloc), so the loader
# cache or a global LD_LIBRARY_PATH would hand them to gfortran and conda builds.
export LD_LIBRARY_PATH=${PREFIX}/lib:${COMPILER_DIR}/lib:${MPI_DIR}/lib:${MPI_DIR}/opt/mpi/libfabric/lib

build=$(mktemp -d)
cd "$build"

# --- 2a. netcdf-fortran, against Ubuntu's netcdf-c ---
wget -q -O nf.tar.gz https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v${NETCDF_FORTRAN}.tar.gz
tar --no-same-owner -xf nf.tar.gz
(
    cd netcdf-fortran-${NETCDF_FORTRAN}
    CC=icx FC=ifx F77=ifx ./configure --prefix=${PREFIX} --disable-static
    make -j"${JOBS}"
    make install
)
# Make PREFIX a whole netcdf install by linking Ubuntu's netcdf-c into it, so
# CESM and ESMF get NETCDF_PATH=PREFIX and never put /usr/include on an ifx
# compile line: the gnu netcdf.mod there is unreadable to ifx.
ln -sf /usr/include/netcdf*.h ${PREFIX}/include/
ln -sf /usr/lib/$(uname -m)-linux-gnu/libnetcdf.so* ${PREFIX}/lib/

# --- 2b. PnetCDF, with Intel MPI ---
wget -q -O pnetcdf.tar.gz https://parallel-netcdf.github.io/Release/pnetcdf-${PNETCDF}.tar.gz
tar --no-same-owner -xf pnetcdf.tar.gz
(
    cd pnetcdf-${PNETCDF}
    ./configure --prefix=${PREFIX} --disable-cxx \
        MPICC=mpiicx MPIF77=mpiifx MPIF90=mpiifx
    make -j"${JOBS}"
    make install
)

# --- 2c. ESMF, with Intel MPI and the netcdf above ---
git clone --depth 1 --branch ${ESMF} https://github.com/esmf-org/esmf esmf
(
    cd esmf
    # ESMF's intelmpi defaults are the ifort/icpc wrappers, gone from oneAPI 2025.
    export ESMF_DIR=$PWD ESMF_INSTALL_PREFIX=${ESMF_PREFIX} \
        ESMF_COMPILER=intel ESMF_COMM=intelmpi \
        ESMF_F90COMPILER=mpiifx ESMF_CXXCOMPILER=mpiicpx ESMF_CCOMPILER=mpiicx \
        ESMF_F90LINKER=mpiifx ESMF_CXXLINKER=mpiicpx ESMF_CLINKER=mpiicx \
        ESMF_NETCDF=split ESMF_NETCDF_INCLUDE=${PREFIX}/include \
        ESMF_NETCDF_LIBPATH=${PREFIX}/lib ESMF_BOPT=O ESMF_ABI=64
    make -j"${JOBS}"
    make install
)

cd /
rm -rf "$build"

# --- 3. intel the ubuntu-latest machine's default compiler ---
# The machine (container_scripts/cime/config_machines.xml) already holds the
# intel settings; listing intel first makes `crocodash create` use it.
machine=/root/.cime/ubuntu-latest/config_machines.xml
sed -i 's|<COMPILERS>gnu</COMPILERS>|<COMPILERS>intel,gnu</COMPILERS>|' "$machine"
grep -q '<COMPILERS>intel,gnu</COMPILERS>' "$machine"
grep -q 'esmf-intel/lib/libO/Linux.intel.64.intelmpi.default/esmf.mk' "$machine"
test -f ${ESMF_PREFIX}/lib/libO/Linux.intel.64.intelmpi.default/esmf.mk
