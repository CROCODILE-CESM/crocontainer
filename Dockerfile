# --- STEP 1: OS & TOOLCHAIN ---
FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    git make cmake curl wget \
    build-essential gfortran g++ \
    # XML parsing (CIME reads lots of XML)
    libxml2-dev libxml2-utils \
    # Perl (CESM scripts use it)
    perl \
    # Python
    python3 python3-pip \
    # Misc utilities CIME scripts call
    csh tcsh bash \
    ca-certificates && rm -rf /var/lib/apt/lists/*

# --- STEP 2: CONDA ---
ENV CONDA_DIR=/opt/conda
RUN arch=$(uname -m) && \
    if [ "$arch" = "x86_64" ]; then CONDA_ARCH="x86_64"; \
    elif [ "$arch" = "aarch64" ]; then CONDA_ARCH="aarch64"; fi && \
    curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh" -o /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p $CONDA_DIR && \
    rm /tmp/miniconda.sh
ENV PATH=$CONDA_DIR/bin:$PATH

# --- STEP 3: CESM ---
ENV CESMROOT=/workspace/CESM
WORKDIR /workspace
RUN git clone https://github.com/CROCODILE-CESM/CESM ${CESMROOT} -b workshop_2025 && \
    cd ${CESMROOT} && ./bin/git-fleximod update

# --- STEP 4: CROCODASH ENV ---
COPY CrocoDash/ /workspace/CrocoDash/
RUN printf "Metadata-Version: 2.1\nName: rm6\nVersion: 0.1.0\n" > /workspace/CrocoDash/CrocoDash/rm6/PKG-INFO
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda env create -f /workspace/CrocoDash/environment.yml -y
RUN conda init bash

# --- STEP 5: GIT CONFIG ---
RUN git config --global user.email "crotainer@crocodile-cesm.org" && \
    git config --global user.name "Crotainer" && \
    git config --global init.defaultBranch main

RUN arch=$(uname -m) && \
    if [ "$arch" = "x86_64" ]; then COMPILERS="gcc_linux-64 gxx_linux-64 gfortran_linux-64"; \
    elif [ "$arch" = "aarch64" ]; then COMPILERS="gcc_linux-aarch64 gxx_linux-aarch64 gfortran_linux-aarch64"; fi && \
    conda create -n cesm_build -y -c conda-forge \
    $COMPILERS \
    openmpi \
    libnetcdf \
    netcdf-fortran \
    hdf5 \
    libpnetcdf \
    esmf \
    cmake \
    make \
    perl \
    libblas \
    liblapack

# --- STEP 6: ENV VARS ---
ENV ESMFMKFILE=/opt/conda/envs/cesm_build/lib/esmf.mk \
    CC=mpicc \
    FC=mpifort \
    CXX=mpicxx \
    CIME_MODEL=cesm \
    CIME_DRIVER=nuopc \
    CIME_MACHINE=ubuntu-latest \
    USER=root \
    NETCDF_PATH=/opt/conda/envs/cesm_build \
    PNETCDF_PATH=/opt/conda/envs/cesm_build \
    LDFLAGS="-L/opt/conda/envs/cesm_build/lib -lblas -llapack" \
    PATH=/opt/conda/envs/cesm_build/bin:/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# --- STEP 7: RUN SCRIPT ---
COPY inside_container_create_case.py /workspace/inside_container_create_case.py
COPY fake_datm_files.sh /workspace/fake_datm_files.sh
RUN bash /workspace/fake_datm_files.sh
COPY run_crocontainer.sh /workspace/run_crocontainer.sh
RUN chmod +x /workspace/run_crocontainer.sh

# CMD ["/workspace/run_crocontainer.sh"]

ENV OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    OMPI_MCA_btl_vader_single_copy_mechanism=none