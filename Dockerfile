# --- STEP 1: OS & TOOLCHAIN ---
FROM ubuntu:latest
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make curl build-essential gfortran \
    libopenmpi-dev libnetcdf-dev libnetcdff-dev netcdf-bin \
    ca-certificates && rm -rf /var/lib/apt/lists/*

# --- STEP 2: CONDA ---
ENV CONDA_DIR=/opt/conda
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p $CONDA_DIR && rm /tmp/miniconda.sh
ENV PATH=$CONDA_DIR/bin:$PATH

# --- STEP 3: CESM (Bake this in once) ---
ENV WORKDIR=/workspace
ENV CESMROOT=/workspace/CESM
WORKDIR ${WORKDIR}
RUN git clone https://github.com/CROCODILE-CESM/CESM ${CESMROOT} -b workshop_2025 && \
    cd ${CESMROOT} && ./bin/git-fleximod update

# --- STEP 4: CREATE THE ENVIRONMENT ---
# We still need the environment.yml to build the conda env
# Copy JUST the yml so we can build the env layer once
COPY CrocoDash/ /workspace/CrocoDash/
RUN conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda env create -f /workspace/CrocoDash/environment.yml -y


# Setup paths
RUN mkdir -p /root/.cime
ENV PATH=$CONDA_DIR/envs/CrocoDash/bin:$PATH
RUN echo "conda activate CrocoDash" >> ~/.bashrc


# --- STEP 5: RUN SCRIPT ---
COPY run_crotainer.sh /workspace/run_crotainer.sh
RUN chmod +x /workspace/run_crotainer.sh
RUN mkdir -p /root/.cime

CMD ["/workspace/run_crotainer.sh"]