# Crocontainer (CrocoDash Container)

## Concepts

- **Podman**: Docker-like, writable layers by default. Good for local/Mac use.
- **Apptainer**: HPC-focused, read-only by default. Used on Derecho.
- **Bundle**: A directory containing all files needed to recreate a CESM case.
- **Sandbox**: An unpacked, writable version of an Apptainer `.sif` image.

## Directions for use:
1. Build the container using podman/docker with available mount points for CESM InputData, the CrocoDash case, and a scratch directory.
2. Publsh to ghcr.io
3. Use the container with those three mount points (See commands for example)

## What's in the container?
1. All the packages necessary to run the CESM and a conda environment to run CrocoDash. To run the CESM, make sure the CrocoDash environment is not activated
2. A CrocoDash environment at /workspace/CrocoDash
3. A CESM checkout at /workspace/CESM
4. A script at /workspace/inside_container_create_case.py that works in the CrocoDash environment to take a bundle at /workspace/bundle to an active CESM case
5. a script at /workspace/run_case.sh that goes through all steps in the process from running the inside_container_create_case.py script to running the CESM case

## Other Files in the Repo
1. A "small_test_case.ipynb" to generate a very small test case
2. A "build.yml" that builds the Dockerfile in amd & arch and publishes to ghcr.io every week.
3. Dockerfile

## Dockerfile
1. Builds ESMF from scratch
2. Installs Conda 
3. Creates the CrocoDash environment
4. Checks out the CESM
5. Copies the necessary scripts
6. Probably takes 30-40 minutes to run the first time (depending on platform)



See below for useful commands
--------------------------------



## Bundle Creation (on Derecho, outside container)

Packages an existing CESM case into a bundle for use inside the container.

```bash
crocodash read \
  --caseroot /glade/u/home/manishrv/croc_cases/vcg.xml.4 \
  --output-dir /glade/derecho/scratch/manishrv/crocontainer/bundles \
  --cesmroot /glade/u/home/manishrv/work/installs/CROCESM_workshop_2025 \
  --machine derecho \
  --project ncgd0011
```

---

## Build Container Images

```bash
# Build for local use (Mac)
podman build -t crocontainer:latest .

# Build for Linux/Derecho (amd64 architecture)
podman build --platform linux/amd64 -t crocontainer:amd64 .
podman tag crocontainer:amd64 ghcr.io/crocodile-cesm/crocontainer:amd64
podman push ghcr.io/crocodile-cesm/crocontainer:amd64

# Pull from GitHub registry to Apptainer .sif (run on a compute node, takes ~1hr)
export APPTAINER_TMPDIR=/glade/derecho/scratch/manishrv/crocontainer/tmp
export APPTAINER_CACHEDIR=/glade/derecho/scratch/manishrv/crocontainer/cache
mkdir -p $APPTAINER_TMPDIR $APPTAINER_CACHEDIR
qcmd -l walltime=03:00:00 -- apptainer pull docker://ghcr.io/crocodile-cesm/crocontainer:amd64
```

---

## Running on Mac (Podman)

```bash
# Fire and forget
podman run --rm \
  -v ~/my_data:/workspace/inputdata \
  -v ~/my_cases:/workspace/cases \
  crocontainer:latest

# Interactive debugging with bundle
podman run -it --rm \
  -v /Users/manishrv/crocontainer/panama-crocontainer_case_bundle:/workspace/bundle \
  --name crodebug \
  crocontainer:latest bash
```

---

## Running on Derecho (Apptainer)

Apptainer `.sif` images are read-only, so build a writable sandbox first. This only needs to be done once.

### Step 1: Build sandbox

```bash
# From a .sif file
apptainer build --sandbox workspace_sandbox/ crocontainer_amd64.sif

# Or directly from the registry
apptainer build --sandbox workspace_sandbox/ docker://ghcr.io/crocodile-cesm/crocontainer:amd64
```

### Step 2: Shell into sandbox

```bash
apptainer shell \
  --writable \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind /glade/derecho/scratch/manishrv:/root/cesm/scratch \
  --bind /glade/derecho/scratch/manishrv/crocontainer/bundles/vcg.xml.4_case_bundle:/workspace/bundle \
  workspace_sandbox/
```

### Step 3: Run the case script

```bash
apptainer exec \
  --writable \
  --env OMPI_CC=gcc \
  --env OMPI_FC=gfortran \
  --env OMPI_CXX=g++ \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind /glade/derecho/scratch/manishrv:/root/cesm/scratch \
  --bind /glade/derecho/scratch/manishrv/crocontainer/bundles/vcg.xml.4_case_bundle:/workspace/bundle \
  workspace_sandbox/ \
  /bin/bash /workspace/run_case.sh
```

### Step 4: Inside the container

```bash
# Activate conda
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash
unset NCAR_HOST

# Set environment variables
export DIN_LOC_ROOT=/root/cesm/inputdata
export ESMFMKFILE=$(find ${ESMF_INSTALL_PREFIX}/lib -name "esmf.mk" | head -1)
export OMPI_CC=gcc
export OMPI_FC=gfortran
export OMPI_CXX=g++

# Configure and run the case
cd /workspace/case
./xmlchange NTASKS=1
./case.setup --reset
./xmlchange DIN_LOC_ROOT=/root/cesm/inputdata

# Run the creation script
cd /workspace
python inside_container_create_case.py
```
