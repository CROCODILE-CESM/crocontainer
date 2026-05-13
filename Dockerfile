# --- STEP 1: OS & TOOLCHAIN ---
FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Compilers
    gfortran g++ gcc \
    git cmake wget curl\
    # MPI Implementation
    libopenmpi-dev openmpi-bin \
    # NetCDF and HDF5 (C and Fortran interfaces)
    libnetcdf-dev libnetcdff-dev libpnetcdf-dev \
    libhdf5-dev \
    # Linear Algebra
    libblas-dev liblapack-dev \
    # Required for CIME scripts
    libxml2-utils make ca-certificates\
    # Python dependencies (for CIME and CrocoDash)
    python3-full python3-pip python3-numpy python3-scipy \
    && rm -rf /var/lib/apt/lists/* 

# Dynamic symlinking in Dockerfile for any architecture
RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libnetcdf.so /usr/lib/libnetcdf.so && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libnetcdff.so /usr/lib/libnetcdff.so && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libpnetcdf.a /usr/lib/libpnetcdf.a
# --- STEP 4: ESMF ENVIRONMENT ---
ENV ESMF_DIR=/usr/local/esmf \
    ESMF_INSTALL_PREFIX=/usr/local/esmf/install \
    ESMF_COMM=openmpi \
    ESMF_COMPILER=gfortran \
    ESMF_ABI=64 \
    ESMF_NETCDF="split" \
    ESMF_NETCDF_INCLUDE=/usr/include \
    ESMF_BOPT=O

# --- STEP 5: BUILD ESMF FROM SOURCE ---
RUN mkdir -p ${ESMF_DIR} && \
    cd /usr/local && \
    # Clone specific tag v8.9.1
    git clone --depth 1 --branch v8.9.1 https://github.com/esmf-org/esmf esmf && \
    cd esmf && \
    # Set NetCDF path dynamically based on architecture
    export ESMF_NETCDF_LIBPATH=/usr/lib/$(uname -m)-linux-gnu && \
    make -j$(nproc) && \
    make install && \
    # Clean up to save space
    make clean

# 3. Update the Pointer for CESM

# --- STEP 2: CONDA ---
ENV CONDA_DIR=/opt/conda
ENV PATH=$CONDA_DIR/bin:$PATH

RUN apt-get update && apt-get install -y curl && \
    arch=$(uname -m) && \
    if [ "$arch" = "x86_64" ]; then CONDA_ARCH="x86_64"; \
    elif [ "$arch" = "aarch64" ]; then CONDA_ARCH="aarch64"; \
    fi && \
    curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${CONDA_ARCH}.sh" -o /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p $CONDA_DIR && \
    rm /tmp/miniconda.sh && \
    # USE THE FULL PATH HERE:
    $CONDA_DIR/bin/conda clean -afy && \
    apt-get purge -y --auto-remove curl && \
    rm -rf /var/lib/apt/lists/*

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
RUN . /opt/conda/etc/profile.d/conda.sh

# --- STEP 5: GIT CONFIG ---
RUN git config --global user.email "crotainer@crocodile-cesm.org" && \
    git config --global user.name "Crotainer" && \
    git config --global init.defaultBranch main

# --- STEP 6: ENV VARS ---
ENV NETCDF_PATH=/usr \
    PNETCDF_PATH=/usr \
    CC=mpicc \
    FC=mpifort \
    CXX=mpicxx \
    CIME_MODEL=cesm \
    CIME_DRIVER=nuopc \
    CIME_MACHINE=ubuntu-latest \
    CIME_OUTPUT_ROOT=/root/cesm/scratch \
    USER=root \
    # Use /usr/lib directly because your symlinks in Step 1 handle the arch logic!
    LDFLAGS="-L/usr/lib -lnetcdf -lnetcdff -lpnetcdf -lblas -llapack" \
    PATH=$CONDA_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

RUN ESMFMKFILE=$(find ${ESMF_INSTALL_PREFIX}/lib -name "esmf.mk" | head -1) && \
    echo "export ESMFMKFILE=${ESMFMKFILE}" >> /etc/environment && \
    echo "export ESMFMKFILE=${ESMFMKFILE}" >> ~/.bashrc

ENV OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    # Vader mechanism often fails in virtualized environments like Podman/Docker on Mac
    OMPI_MCA_btl_vader_single_copy_mechanism=none \
    # Force OpenMPI to use basic TCP communication to avoid "No such device" errors
    OMPI_MCA_btl=self,tcp

# --- STEP 7: RUN SCRIPT --
COPY inside_container_create_case.py /workspace/inside_container_create_case.py
COPY run_case.sh /workspace/run_case.sh
RUN chmod +x /workspace/run_case.sh

# Create Mount Points
RUN mkdir -p /glade
RUN mkdir -p /workspace/bundle
RUN mkdir -p /root/cesm/inputdata
RUN mkdir -p /root/cesm/scratch
