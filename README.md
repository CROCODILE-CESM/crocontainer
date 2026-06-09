# Crocontainer

Crocontainer is a pre-built container image that lets you run a [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash)-configured CESM regional ocean case anywhere — on your laptop or on an HPC system like Derecho — without installing CESM, ESMF, or MPI yourself.

The primary workflow is:
1. **Download & Edit** `container_scripts/case_setup.py` to configure your regional ocean domain.
2. **Run** the container with your setup script mounted — it configures, builds, and executes the case inside.

If you need features from a CrocoDash version newer than what's in the container image, see [Bundle Mode](#bundle-mode-when-your-crocodash-is-newer-than-the-container) instead.

---

## NYF Quick Start

NYF (Normal Year Forcing) runs use a small, fixed set of CESM inputdata — 10 files totalling ~6.5 GB. By pre-downloading these once, the container skips all SVN downloads at runtime and starts immediately.

### Step 1: Download the inputdata

The file list is versioned in `scripts/nyf_inputdata_list.txt`. The download script reads it and fetches each file from the CESM SVN HTTP server, preserving the directory tree expected by CESM under `DIN_LOC_ROOT`.

```bash
bash scripts/download_nyf_inputdata.sh ./cesm_nyf_inputdata
```

**Download options:**

| Option | Effect |
|---|---|
| First positional arg | Output directory (default: `./cesm_nyf_inputdata`) |
| Second positional arg (number) | Number of parallel transfers (default: 4) |
| `--from-glade <user@host>` | rsync from GLADE campaign storage instead of SVN — faster if you have GLADE access |

**Speed tips:**
- Install [`aria2c`](https://aria2.github.io/) (`brew install aria2` on Mac) — the script automatically uses it when available, splitting each large file into 4 concurrent chunks. Falls back to `wget` otherwise.
- If you have a GLADE account, `--from-glade` pulls directly from `/glade/campaign/cesm/cesmdata/inputdata/` via rsync, bypassing the SVN server entirely:

```bash
bash scripts/download_nyf_inputdata.sh ./cesm_nyf_inputdata --from-glade <you>@derecho.hpc.ucar.edu
```

The script is **idempotent** — re-running skips any files already present, so it is safe to resume an interrupted download.

### Step 2: Run your case

Clone this repository (to get `case_setup.py` and helper scripts), create a scratch directory, and run:

```bash
mkdir -p cesm_scratch

# Linux / macOS
docker run --rm \
  -v ./cesm_nyf_inputdata:/root/cesm/inputdata \
  -v ./cesm_scratch:/root/cesm/scratch \
  -v ./container_scripts/case_setup.py:/workspace/case_setup.py \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

```powershell
# Windows (PowerShell)
docker run --rm `
  -v C:\path\to\cesm_nyf_inputdata:/root/cesm/inputdata `
  -v C:\path\to\cesm_scratch:/root/cesm/scratch `
  -v C:\path\to\crocontainer\container_scripts\case_setup.py:/workspace/case_setup.py `
  ghcr.io/crocodile-cesm/crocontainer:latest `
  /bin/bash /workspace/run_case.sh
```

Edit `container_scripts/case_setup.py` to change the domain, resolution, or compset before running.

---

## User Guide

### Setup Script Mode (default)

The container includes a full CESM checkout at `/workspace/CESM` and the `CrocoDash` conda environment. You configure your case by mounting a Python setup script at `/workspace/case_setup.py` — `run_case.sh` detects it automatically and uses it; if no script is mounted it falls back to [bundle mode](#bundle-mode-when-your-crocodash-is-newer-than-the-container).

The script `container_scripts/case_setup.py` is a ready-to-use template — it is also used by the CI workflow to validate the container on every platform, so it stays current with the container environment. Edit it to configure:

- **Domain**: `xstart`, `ystart`, `lenx`, `leny`
- **Resolution**: `resolution` in `Grid`
- **Vertical grid**: `nk`, `depth` in `VGrid.uniform`
- **Compset**: `compset` in `Case`

Then run the container with your edited script mounted as `/workspace/case_setup.py`:

```bash
# Linux
docker run --rm \
  -v /path/to/cesm_inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  -v /path/to/your_setup.py:/workspace/case_setup.py \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

#### On Mac (Podman)

Podman is the recommended container runtime on macOS.

##### Prerequisites

Install Podman via Homebrew (one-time):

```bash
brew install podman
podman machine init
podman machine start
```

##### Pull the Image

```bash
podman pull ghcr.io/crocodile-cesm/crocontainer:latest
```

This pulls the multi-arch manifest — Podman automatically selects the correct image for your Mac (arm64 for Apple Silicon, amd64 for Intel).

##### Run Your Case

```bash
podman run --rm \
  -v /path/to/cesm_inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  -v /path/to/your_setup.py:/workspace/case_setup.py \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

##### Explore Interactively

To open a shell inside the container instead of running the full script:

```bash
podman run -it --rm \
  -v /path/to/cesm_inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  bash
```

Then run your setup script manually (`python /path/to/your_setup.py`) or invoke `/workspace/run_case.sh` directly.

#### On Windows (Docker Desktop)

CrocoDash does not run natively on Windows. The container is how Windows users access CrocoDash and CESM — it provides a complete Linux environment with CrocoDash and a full CESM checkout pre-installed, accessible through Docker Desktop.

##### Prerequisites

Download and install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/). During setup, ensure the **WSL2** backend is selected (the default). Switch to **Linux containers** mode if prompted (right-click the Docker Desktop tray icon → "Switch to Linux containers").

##### Pull the Image

```powershell
docker pull ghcr.io/crocodile-cesm/crocontainer:latest
```

##### Run Your Case

Edit `container_scripts\case_setup.py`, then mount it as `/workspace/case_setup.py`:

```powershell
docker run --rm `
  -v C:\path\to\cesm_inputdata:/root/cesm/inputdata `
  -v C:\path\to\scratch:/root/cesm/scratch `
  -v C:\path\to\crocontainer\container_scripts\case_setup.py:/workspace/case_setup.py `
  ghcr.io/crocodile-cesm/crocontainer:latest `
  /bin/bash /workspace/run_case.sh
```

##### Explore Interactively

To open a shell inside the container:

```powershell
docker run -it --rm `
  -v C:\path\to\cesm_inputdata:/root/cesm/inputdata `
  -v C:\path\to\scratch:/root/cesm/scratch `
  -v C:\path\to\your\work:/workspace/work `
  ghcr.io/crocodile-cesm/crocontainer:latest `
  bash
```

Inside the container, activate the CrocoDash environment and run your setup script:

```bash
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash
python /workspace/work/your_setup.py
```

The backtick (`` ` ``) is the PowerShell line-continuation character; replace it with `\` if running from Git Bash or WSL.

---

### Bundle Mode: When Your CrocoDash Is Newer Than the Container

Use this when either of the following applies:

- **You need a newer CrocoDash**: your case requires features from a version of CrocoDash on Derecho that hasn't been baked into the container image yet.
- **You want a verified configuration**: you've already run the full CrocoDash workflow somewhere and confirmed it works. Bundling captures that exact configuration, so the container reconstructs it directly rather than re-running a setup script — avoiding any errors you might otherwise encounter writing or debugging `case_setup.py` from scratch.

Bundle mode is not available on Windows — `crocodash bundle` requires a CrocoDash installation, which does not run natively on Windows.

#### Prerequisites

- A working CrocoDash installation (`conda activate CrocoDash`) on the system where you created your case.
- Your CESM case already set up and configured via CrocoDash.

#### Step 1: Bundle Your Case

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

#### Step 2: Run the Container

Mount three paths into the container:

| Mount target (inside container) | What to bind |
|---|---|
| `/workspace/bundle` | Your `<casename>_case_bundle/` directory from Step 1 |
| `/root/cesm/inputdata` | CESM input data directory |
| `/root/cesm/scratch` | A scratch directory for case output |

##### On Derecho (Apptainer)

Apptainer images are read-only, so build a writable sandbox directly from the registry (one-time setup, takes ~1 hour on a compute node):

```bash
export APPTAINER_TMPDIR=/glade/derecho/scratch/$USER/crocontainer/tmp
export APPTAINER_CACHEDIR=/glade/derecho/scratch/$USER/crocontainer/cache
mkdir -p $APPTAINER_TMPDIR $APPTAINER_CACHEDIR

qcmd -l walltime=03:00:00 -- apptainer build --sandbox crocontainer_sandbox/ \
  docker://ghcr.io/crocodile-cesm/crocontainer:latest-amd64
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

##### On Mac (Podman)

```bash
podman run --rm \
  -v /path/to/your/<casename>_case_bundle:/workspace/bundle \
  -v /path/to/inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

| Flag | Description |
|---|---|
| `--rm` | Remove the container after it exits |
| `-v <host>:<container>` | Bind-mount a host directory into the container |

---

### Limiting DATM Forcing Downloads

By default, CESM's DATM component will try to download the full JRA55 dataset across all years — this can be many hundreds of GB. To limit downloads to only the years your run actually needs, add a `user_nl_datm_streams` file to your case directory. Each entry restricts one stream to a specific year range and file list:

```
CORE_IAF_JRA.PREC:year_first = 2019
CORE_IAF_JRA.PREC:year_last = 2021
CORE_IAF_JRA.PREC:datafiles = /path/to/JRA.v1.3.prec.TL319.2019.nc,/path/to/JRA.v1.3.prec.TL319.2021.nc
```

Because this is a `user_nl` file, it is captured by `crocodash bundle` and carries over automatically when someone forks your bundle — there's nothing extra to do when sharing.

**For JRA cases, `run_case.sh` does this automatically.** It reads `DATM_YR_START` and `DATM_YR_END` from the case XML and writes a `user_nl_datm_streams` file restricting all eight JRA55 streams (precipitation, longwave, shortwave, humidity, sea-level pressure, temperature, and U/V winds) to only the needed years.

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
| `/workspace/run_case.sh` | Orchestrates the full flow: setup/fork → build case → submit |

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
