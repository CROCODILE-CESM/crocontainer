# CrocoDash Container Commands

## Concepts
# - Podman: Docker-like, writable layers by default. Good for local/Mac use.
# - Apptainer: HPC-focused, read-only by default. Used on Derecho.
# - Bundle: A directory containing all files needed to recreate a CESM case.
# - Sandbox: An unpacked, writable version of an Apptainer .sif image.

---

## Bundle Creation (on Derecho, outside container)
# Packages an existing CESM case into a bundle for use inside the container
crocodash read \
  --caseroot /glade/u/home/manishrv/croc_cases/vcg.xml.4 \
  --output-dir /glade/derecho/scratch/manishrv/crocontainer/bundles \
  --cesmroot /glade/u/home/manishrv/work/installs/CROCESM_workshop_2025 \
  --machine derecho \
  --project ncgd0011

---

## Build Container Images

# Build for local use (Mac)
podman build -t crocontainer:latest .

# Build for Linux/Derecho (amd64 architecture)
podman build --platform linux/amd64 -t crocontainer:amd64 .

# Pull from GitHub registry to Apptainer .sif (run on a compute node, takes ~1hr)
export APPTAINER_TMPDIR=/glade/derecho/scratch/manishrv/crocontainer/tmp
export APPTAINER_CACHEDIR=/glade/derecho/scratch/manishrv/crocontainer/cache
mkdir -p $APPTAINER_TMPDIR $APPTAINER_CACHEDIR
qcmd -l walltime=03:00:00 -- apptainer pull docker://ghcr.io/crocodile-cesm/crocontainer:amd64

---

## Running on Mac (Podman)
# Flags:
#   -it: interactive terminal
#   --rm: delete container after exit
#   -v: bind mount host:container
#   bash: start a bash shell

# Fire and forget
podman run --rm \
  -v ~/my_data:/workspace/inputdata \
  -v ~/my_cases:/workspace/cases \
  crocontainer:latest

# Debugging with bundle
podman run -it --rm \
  -v /Users/manishrv/crocontainer/panama-crocontainer_case_bundle:/workspace/bundle \
  --name crodebug \
  crocontainer:latest bash

---

## Running on Derecho (Apptainer)
# Apptainer .sif images are read-only, so we build a writable sandbox first.
# This only needs to be done once.

# Step 1: Build sandbox from .sif (takes a few minutes, done once)
apptainer build --sandbox workspace_sandbox/ crocontainer_amd64.sif

# Step 2: Shell into sandbox
# Flags:
#   --writable: allows writing to the sandbox directory
#   --bind src:dst: mounts host directory into container
apptainer shell \
  --writable \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind /glade/derecho/scratch/manishrv:/root/cesm/scratch \
  --bind /glade/derecho/scratch/manishrv/crocontainer/bundles/vcg.xml.4_case_bundle:/workspace/bundle \
  workspace_sandbox/

# Step 3: Inside container - activate conda
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash

# Step 4: Inside container - run script
cd /workspace
python inside_container_create_case.py