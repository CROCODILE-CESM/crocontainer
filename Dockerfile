# crocontainer's images, each a --target of this file (see build.yml):
#   slim        what CESM needs to build and run a case: Ubuntu, gfortran,
#               OpenMPI, netCDF, ESMF, the container's CIME machine, and a
#               small Python for CIME. You bring CESM and a CrocoDash env.
#   slim-intel  slim plus Intel's compilers and MPI: MOM6 runs on more than
#               one task (it can't with gfortran; see install_intel_toolchain.sh).
#   full        slim, or slim-intel with --build-arg FULL_BASE=slim-intel,
#               plus CESM, CrocoDash and its conda env: nothing to bring.
ARG FULL_BASE=slim

# ============================== slim ==============================
FROM ubuntu:latest AS slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Compilers
    gfortran g++ gcc make \
    # MPI Implementation
    libopenmpi-dev openmpi-bin \
    # NetCDF and HDF5 (C and Fortran interfaces), and ncdump for archiving
    libnetcdf-dev libnetcdff-dev libpnetcdf-dev netcdf-bin libhdf5-dev \
    # Linear Algebra
    libblas-dev liblapack-dev \
    # CIME (xmllint, git describe), downloads
    libxml2-utils git wget curl bzip2 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Dynamic symlinking in Dockerfile for any architecture
RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libnetcdf.so /usr/lib/libnetcdf.so && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libnetcdff.so /usr/lib/libnetcdff.so && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libpnetcdf.a /usr/lib/libpnetcdf.a

# --- Python for CIME, and cmake < 4 ---
# micromamba keeps /opt/conda to a small base env: Python with PyYAML (MOM6's
# namelist generation needs it) and cmake < 4 (ESMF's build needs a cmake, and
# cmake 4, Ubuntu's, breaks the CDEPS build: FindMPI fails before project()).
# It also builds conda envs: CrocoDash's in the full image, or your own in slim.
ENV MAMBA_ROOT_PREFIX=/opt/conda \
    PATH=/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN case $(uname -m) in x86_64) platform=linux-64;; aarch64) platform=linux-aarch64;; esac && \
    curl -fsSL https://micro.mamba.pm/api/micromamba/${platform}/latest | tar -xj -C /usr/local bin/micromamba && \
    micromamba install -y -n base -c conda-forge python=3.12 pyyaml "cmake<4" && \
    micromamba clean -afy

# --- ESMF, built from source (the source tree is not kept) ---
ENV ESMF_INSTALL_PREFIX=/usr/local/esmf/install
RUN git clone --depth 1 --branch v8.9.1 https://github.com/esmf-org/esmf /tmp/esmf && \
    cd /tmp/esmf && \
    export ESMF_DIR=/tmp/esmf ESMF_COMM=openmpi ESMF_COMPILER=gfortran ESMF_ABI=64 \
        ESMF_NETCDF=split ESMF_NETCDF_INCLUDE=/usr/include \
        ESMF_NETCDF_LIBPATH=/usr/lib/$(uname -m)-linux-gnu ESMF_BOPT=O && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /tmp/esmf && \
    test -f ${ESMF_INSTALL_PREFIX}/lib/libO/Linux.gfortran.64.openmpi.default/esmf.mk

# --- GIT CONFIG ---
RUN git config --global user.email "crotainer@crocodile-cesm.org" && \
    git config --global user.name "Crotainer" && \
    git config --global init.defaultBranch main

# --- ENV VARS ---
# Build settings (compilers, netcdf, ESMF) are in the CIME machine instead,
# per compiler and out of reach of a host's environment.
ENV CIME_MODEL=cesm \
    CIME_DRIVER=nuopc \
    CIME_MACHINE=ubuntu-latest \
    USER=root \
    PATH=/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    # Vader mechanism often fails in virtualized environments like Podman/Docker on Mac
    OMPI_MCA_btl_vader_single_copy_mechanism=none \
    # Force OpenMPI to use basic TCP communication to avoid "No such device" errors
    OMPI_MCA_btl=self,tcp

# The container's CIME machine (container_scripts/cime/config_machines.xml) and
# its cmake macros, in CIME's per-user config: ~/.cime/ubuntu-latest replaces
# CESM's own ubuntu-latest for any CESM, the full image's or one you mount.
COPY container_scripts/cime/config_machines.xml /root/.cime/ubuntu-latest/config_machines.xml
COPY container_scripts/cime/*.cmake /root/.cime/
# Under Apptainer, which brings the host's HOME and NCAR_HOST in.
COPY container_scripts/apptainer_env.sh /.singularity.d/env/91-crocontainer.sh

# Mount points
RUN mkdir -p /glade /root/cesm/inputdata /root/cesm/scratch

# =========================== slim-intel ===========================
FROM slim AS slim-intel

COPY container_scripts/install_intel_toolchain.sh /tmp/install_intel_toolchain.sh
RUN bash /tmp/install_intel_toolchain.sh && rm /tmp/install_intel_toolchain.sh

# The compilers and mpiexec on PATH for interactive use. Case builds and runs
# get their settings, LD_LIBRARY_PATH included, from the CIME machine.
ENV PATH=/opt/intel/oneapi/mpi/latest/bin:/opt/intel/oneapi/compiler/latest/bin:${PATH} \
    I_MPI_ROOT=/opt/intel/oneapi/mpi/latest

# ============================== full ==============================
FROM ${FULL_BASE} AS full

# --- CESM ---
ARG CESM_BRANCH=crocodash
# Resolved by build.yml via git ls-remote. Changing it invalidates this layer, so
# the image picks up new commits on CESM_BRANCH instead of reusing a stale clone.
ARG CESM_SHA=unknown
ARG CROCODASH_SHA=unknown
LABEL org.crocodile-cesm.cesm-branch=${CESM_BRANCH} \
      org.crocodile-cesm.cesm-sha=${CESM_SHA} \
      org.crocodile-cesm.crocodash-sha=${CROCODASH_SHA}
ENV CESMROOT=/workspace/CESM
WORKDIR /workspace
RUN echo "CESM ${CESM_BRANCH}@${CESM_SHA}" && git clone --depth 1 https://github.com/CROCODILE-CESM/CESM ${CESMROOT} -b ${CESM_BRANCH} && \
    cd ${CESMROOT} && ./bin/git-fleximod update

# --- CROCODASH AND ITS ENV ---
COPY CrocoDash/ /workspace/CrocoDash/
RUN printf "Metadata-Version: 2.1\nName: rm6\nVersion: 0.1.0\n" > /workspace/CrocoDash/CrocoDash/rm6/PKG-INFO
RUN cd /workspace/CrocoDash && \
    micromamba create -y -n CrocoDash -f environment.yml && \
    micromamba clean -afy

#  Copy Scripts
COPY container_scripts/crocodash /usr/local/bin/crocodash
COPY container_scripts/run_case.sh /workspace/run_case.sh
COPY container_scripts/panama_demo_setup.sh /workspace/panama_demo_setup.sh
COPY container_scripts/panama_case_config.yaml /workspace/panama_case_config.yaml
RUN chmod +x /workspace/run_case.sh /workspace/panama_demo_setup.sh && \
    mkdir -p /workspace/bundle
