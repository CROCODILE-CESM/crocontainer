# --- STEP 1: OS & TOOLCHAIN ---
FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make curl build-essential gfortran \
    libopenmpi-dev libnetcdf-dev libnetcdff-dev netcdf-bin \
    cmake python3 python3-pip \
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
RUN conda init bash && echo "conda activate CrocoDash" >> ~/.bashrc

# --- STEP 5: GIT CONFIG ---
RUN git config --global user.email "crotainer@crocodile-cesm.org" && \
    git config --global user.name "Crotainer" && \
    git config --global init.defaultBranch main

# --- STEP 6: ENV VARS ---
# System MPI/compilers first, then conda — order matters for mpicc resolution
RUN arch=$(uname -m) && echo "ARCH=${arch}"
ENV PATH=/usr/lib/x86_64-linux-gnu/openmpi/bin:/usr/bin:/usr/local/bin:/opt/conda/envs/CrocoDash/bin:/opt/conda/bin
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/openmpi/lib:/usr/lib/x86_64-linux-gnu
ENV CC=mpicc \
    FC=mpifort \
    CXX=mpicxx \
    CIME_MODEL=cesm \
    CIME_DRIVER=nuopc \
    CIME_MACHINE=ubuntu-latest \
    USER=root \
    NETCDF_C_PATH=/usr \
    NETCDF_FORTRAN_PATH=/usr \
    NetCDF_C_PATH=/usr \
    NetCDF_Fortran_PATH=/usr \
    NetCDF_C_LIBRARY=/usr/lib/x86_64-linux-gnu/libnetcdf.so \
    NetCDF_C_INCLUDE_DIR=/usr/include \
    ESMFMKFILE=/opt/conda/envs/CrocoDash/lib/esmf.mk

# --- STEP 7: RUN SCRIPT ---
RUN mkdir -p /root/.cime
COPY inside_container_create_case.py /workspace/inside_container_create_case.py
COPY run_crocontainer.sh /workspace/run_crocontainer.sh
RUN chmod +x /workspace/run_crocontainer.sh

CMD ["/workspace/run_crocontainer.sh"]