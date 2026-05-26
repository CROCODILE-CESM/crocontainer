# Crocontainer

Crocontainer is a pre-built container image that lets you run a [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash)-configured CESM regional ocean case anywhere — on your laptop or on an HPC system like Derecho — without installing CESM, ESMF, or MPI yourself.

The workflow is:
1. **Create and configure** a regional ocean case with CrocoDash on Derecho.
2. **Bundle** it with `crocodash bundle` — this packages everything the container needs.
3. **Run** the container with your bundle mounted — it rebuilds and executes the case inside.

---

## User Guide

### Prerequisites

- A working CrocoDash installation (`conda activate CrocoDash`) on the system where you created your case.
- Your CESM case already set up and configured via CrocoDash.

### Step 1: Bundle Your Case

Run this on the system where your case lives (e.g., Derecho), outside the container:

```bash
crocodash bundle \
  --caseroot /path/to/your/cesm/case \
  --output-dir /path/to/output/bundles \
  --cesmroot /path/to/cesm/source \
  --machine <machine-name> \
  --project <project-code>
```

| Flag | Description |
|---|---|
| `--caseroot` | Path to your existing CESM case directory |
| `--output-dir` | Directory where the bundle will be written |
| `--cesmroot` | Path to your CESM source checkout |
| `--machine` | CIME machine name (e.g., `derecho`, `ubuntu-latest`) |
| `--project` | HPC project/account code used for the case |

This produces a `<casename>_case_bundle/` directory in your output dir.

### Step 2: Pull the Container

#### On Derecho (Apptainer)

Pull the image as an Apptainer `.sif` file. Run this on a compute node — it takes roughly an hour.

```bash
export APPTAINER_TMPDIR=/glade/derecho/scratch/$USER/crocontainer/tmp
export APPTAINER_CACHEDIR=/glade/derecho/scratch/$USER/crocontainer/cache
mkdir -p $APPTAINER_TMPDIR $APPTAINER_CACHEDIR

qcmd -l walltime=03:00:00 -- apptainer pull docker://ghcr.io/crocodile-cesm/crocontainer:latest-amd64
```

#### On Mac (Podman)

```bash
podman pull ghcr.io/crocodile-cesm/crocontainer:latest
```

### Step 3: Run the Container

Mount three paths into the container:

| Mount target (inside container) | What to bind |
|---|---|
| `/workspace/bundle` | Your `<casename>_case_bundle/` directory from Step 1 |
| `/root/cesm/inputdata` | CESM input data directory |
| `/root/cesm/scratch` | A scratch directory for case output |

#### On Derecho (Apptainer)

Apptainer images are read-only. Build a writable sandbox first (one-time setup):

```bash
apptainer build --sandbox crocontainer_sandbox/ docker://ghcr.io/crocodile-cesm/crocontainer:latest-amd64
```

Then run your case:

```bash
apptainer exec \
  --writable \
  --env OMPI_CC=gcc \
  --env OMPI_FC=gfortran \
  --env OMPI_CXX=g++ \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind /glade/derecho/scratch/$USER:/root/cesm/scratch \
  --bind /path/to/your/<casename>_case_bundle:/workspace/bundle \
  crocontainer_sandbox/ \
  /bin/bash /workspace/run_case.sh
```

To explore interactively instead of running the full script:

```bash
apptainer shell \
  --writable \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind /glade/derecho/scratch/$USER:/root/cesm/scratch \
  --bind /path/to/your/<casename>_case_bundle:/workspace/bundle \
  crocontainer_sandbox/
```

#### On Mac (Podman)

```bash
podman run -it --rm \
  -v /path/to/your/<casename>_case_bundle:/workspace/bundle \
  -v /path/to/inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest bash
```

Then inside the container run `/workspace/run_case.sh`.

---

## Developer Guide

### What's Inside the Container

| Path | Contents |
|---|---|
| `/workspace/CESM` | Full CESM checkout (branch `workshop_2025`) |
| `/workspace/CrocoDash` | CrocoDash installation + conda environment named `CrocoDash` |
| `/workspace/bundle` | Mount point for your case bundle |
| `/root/cesm/inputdata` | Mount point for CESM input data |
| `/root/cesm/scratch` | Mount point for scratch/output |
| `/workspace/create_case_from_bundle.py` | Reconstructs the CESM case from the bundle using CrocoDash |
| `/workspace/run_case.sh` | Orchestrates the full flow: fork bundle → build case → submit |

CESM must be run with the `CrocoDash` conda environment **deactivated**. `run_case.sh` handles this automatically.

### Key Concepts

| Term | Meaning |
|---|---|
| **Podman** | Docker-compatible container runtime. Writable layers by default. Best for local/Mac use. |
| **Apptainer** | HPC-focused container runtime. Images are read-only `.sif` files by default. Used on Derecho. |
| **Sandbox** | An unpacked, writable directory version of an Apptainer `.sif` image. Required for CESM since it writes to its own install tree. |
| **Bundle** | A directory produced by `crocodash bundle` containing all config, namelists, and metadata needed to recreate a CESM case. |

### Dev Environment

To develop or test scripts against the in-repo CrocoDash submodule locally:

```bash
conda env create -f environment.yml
conda activate Crocontainer
```

### Building the Container

```bash
# Local build (Mac, native architecture)
podman build -t crocontainer:latest .

# Cross-compile for Linux/amd64 (for Derecho)
podman build --platform linux/amd64 -t crocontainer:amd64 .

# Tag and push to GitHub Container Registry
podman tag crocontainer:amd64 ghcr.io/crocodile-cesm/crocontainer:amd64
podman push ghcr.io/crocodile-cesm/crocontainer:amd64
```

The first build takes 30–40 minutes (ESMF is compiled from source).

### Dockerfile Overview

The Dockerfile:
1. Installs system compilers, MPI (OpenMPI), NetCDF/HDF5, and Python
2. Builds ESMF v8.9.1 from source
3. Installs Miniconda and creates the `CrocoDash` conda environment
4. Clones CESM and runs `git-fleximod update`
5. Copies `create_case_from_bundle.py` and `run_case.sh` into `/workspace`

### CI/CD

The GitHub Actions workflow (`.github/workflows/build.yml`) builds and pushes multi-arch images automatically:
- **Trigger**: every Monday at 6am UTC, on version tags (`v*.*.*`), or manually via `workflow_dispatch`
- **Architectures**: `linux/amd64` and `linux/arm64` (via QEMU emulation)
- **Registry**: `ghcr.io/crocodile-cesm/crocontainer`
- **Tags**: `latest-amd64`, `latest-arm64`, per-commit `sha-<hash>-<arch>`, and a merged `latest` multi-arch manifest
