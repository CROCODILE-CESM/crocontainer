# Crocontainer

[![CESM runs in container](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml/badge.svg)](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml)

Crocontainer is a pre-built container image that lets you run a [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash)-configured CESM regional ocean case anywhere — on your laptop or on an HPC system like Derecho — without installing CESM, ESMF, or MPI yourself.

The primary workflow is:
1. **Write** a CrocoDash YAML case config to configure your regional ocean domain — see `container_scripts/regional_configs/mom-regional-base.yaml` for a working example (its `case.caseroot`/`case.inputdir` must be `/workspace/case`/`/workspace/inputdir` for your own copy).
2. **Run** the container with your edited YAML config mounted as `/workspace/case_config.yaml` — it builds, configures, and executes the case inside via the `crocodash` CLI. No script to write or mount.

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

Clone this repository (to get a starting template config and helper scripts), create a scratch directory, and run:

```bash
mkdir -p cesm_scratch
cp container_scripts/regional_configs/mom-regional-base.yaml my_case_config.yaml
# edit my_case_config.yaml for your domain (see below) -- set case.caseroot to
# /workspace/case and case.inputdir to /workspace/inputdir, then:

# Linux / macOS / Windows (WSL2)
podman run --rm \
  -v ./cesm_nyf_inputdata:/root/cesm/inputdata \
  -v ./cesm_scratch:/root/cesm/scratch \
  -v ./my_case_config.yaml:/workspace/case_config.yaml \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

> **Windows users:** run this from inside a WSL2 Ubuntu terminal, not from PowerShell. See [On Windows (WSL2)](#on-windows-wsl2) for setup.

A YAML config (or a [bundle](#bundle-mode-when-your-crocodash-is-newer-than-the-container)) must be mounted — see [YAML Config Mode](#yaml-config-mode-default).

---

## User Guide

### YAML Config Mode (default)

The container includes a full CESM checkout at `/workspace/CESM` and the `CrocoDash` conda environment. You configure your case with a CrocoDash YAML case config mounted at `/workspace/case_config.yaml` — `run_case.sh` runs `crocodash create --config /workspace/case_config.yaml --override` directly; there's no script to write or mount. Your config's `case.caseroot`/`case.inputdir` must be `/workspace/case`/`/workspace/inputdir` to match the paths `run_case.sh` uses for the CIME build/submit steps that follow.

One of a YAML config or a [bundle](#bundle-mode-when-your-crocodash-is-newer-than-the-container) must be mounted -- `run_case.sh` exits with an error otherwise.

`container_scripts/regional_configs/mom-regional-base.yaml` is a ready-to-use template in CrocoDash's YAML case config format (see `crocodash create --config` / `CrocoDash.recipe`) for your own case -- it's also the config the container CI itself regenerates and validates weekly (see [CI/CD](#cicd)). Edit a copy of it to configure:

- **Domain**: `grid.xstart`, `grid.ystart`, `grid.lenx`, `grid.leny`
- **Resolution**: `grid.resolution`
- **Vertical grid**: `vgrid.nk`, `vgrid.type`
- **Compset**: `case.compset`

Then run the container with your edited config mounted as `/workspace/case_config.yaml`:

#### On Linux / macOS (Podman)

Podman is the recommended container runtime on Linux and macOS.

**Install** (if not already present):

```bash
# macOS
brew install podman
podman machine init
podman machine start

# Linux (Fedora/RHEL)
sudo dnf install podman

# Linux (Debian/Ubuntu)
sudo apt install podman
```

On macOS, `podman machine init && podman machine start` creates and starts a lightweight Linux VM. `podman pull` automatically selects the correct image for your Mac (arm64 for Apple Silicon, amd64 for Intel).

**Run your case:**

```bash
podman run --rm \
  -v /path/to/cesm_inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  -v /path/to/your_case_config.yaml:/workspace/case_config.yaml \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

**Explore interactively:**

```bash
podman run -it --rm \
  -v /path/to/cesm_inputdata:/root/cesm/inputdata \
  -v /path/to/scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  bash
```

Then run `crocodash create --config /path/to/your_case_config.yaml --override` manually, or invoke `/workspace/run_case.sh` directly.

#### On Windows (WSL2)

CESM and CrocoDash are Linux-only. On Windows, use **WSL2** (Windows Subsystem for Linux) to get a full native Ubuntu environment — then follow the Linux instructions above exactly. There is nothing Windows-specific to learn; once you're inside WSL2 you're on Linux.

##### Install WSL2

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

This installs Ubuntu by default. Restart when prompted, then open the **Ubuntu** app from the Start menu to complete first-time setup (create a username and password).

##### Install Podman inside WSL2

In your Ubuntu terminal:

```bash
sudo apt update && sudo apt install -y podman
```

##### Clone the Repo and Run Your Case

Work directly in your WSL2 home directory — it's faster and avoids path translation issues:

```bash
git clone https://github.com/CROCODILE-CESM/crocontainer ~/crocontainer
cd ~/crocontainer
bash scripts/download_nyf_inputdata.sh ~/cesm_nyf_inputdata
mkdir -p ~/cesm_scratch
cp container_scripts/regional_configs/mom-regional-base.yaml my_case_config.yaml
# edit my_case_config.yaml for your domain (set case.caseroot to /workspace/case
# and case.inputdir to /workspace/inputdir), then:

podman run --rm \
  -v ~/cesm_nyf_inputdata:/root/cesm/inputdata \
  -v ~/cesm_scratch:/root/cesm/scratch \
  -v ~/crocontainer/my_case_config.yaml:/workspace/case_config.yaml \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

If you prefer to keep files on your Windows drive, they are accessible under `/mnt/c/Users/<YourName>/...` inside WSL2:

```bash
podman run --rm \
  -v /mnt/c/Users/<YourName>/cesm_nyf_inputdata:/root/cesm/inputdata \
  -v /mnt/c/Users/<YourName>/cesm_scratch:/root/cesm/scratch \
  -v /mnt/c/Users/<YourName>/crocontainer/my_case_config.yaml:/workspace/case_config.yaml \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  /bin/bash /workspace/run_case.sh
```

##### Explore Interactively

```bash
podman run -it --rm \
  -v ~/cesm_nyf_inputdata:/root/cesm/inputdata \
  -v ~/cesm_scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest \
  bash
```

Inside the container:

```bash
source /opt/conda/etc/profile.d/conda.sh
conda activate CrocoDash
crocodash create --config /workspace/case_config.yaml --override
```

---

### Bundle Mode: When Your CrocoDash Is Newer Than the Container

Use this when either of the following applies:

- **You need a newer CrocoDash**: your case requires features from a version of CrocoDash on Derecho that hasn't been baked into the container image yet.
- **You want a verified configuration**: you've already run the full CrocoDash workflow somewhere and confirmed it works. Bundling captures that exact configuration, so the container reconstructs it directly rather than building a new case from a YAML config — avoiding any errors you might otherwise encounter writing or debugging a case config from scratch.

Bundle mode requires a working CrocoDash installation. Windows users should run `crocodash bundle` from inside their WSL2 Ubuntu environment (see [On Windows (WSL2)](#on-windows-wsl2)).

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

##### On Linux / Mac (Podman)

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
| `/workspace/CESM` | Full CESM checkout (branch `full_regional_cesm_alpha09d`) |
| `/workspace/CrocoDash` | CrocoDash installation + conda environment named `CrocoDash` |
| `/workspace/case_config.yaml` | Mount point for your own YAML case config (YAML config mode) |
| `/workspace/bundle` | Mount point for your case bundle |
| `/root/cesm/inputdata` | Mount point for CESM input data |
| `/root/cesm/scratch` | Mount point for scratch/output |
| `/workspace/run_case.sh` | Orchestrates the full flow: create/fork → build case → submit |

CESM must be run with the `CrocoDash` conda environment **deactivated**. `run_case.sh` handles this automatically.

### Key Concepts

| Term | Meaning |
|---|---|
| **Podman** | Docker-compatible container runtime. Writable layers by default. Recommended for Linux, macOS, and Windows (via WSL2). |
| **WSL2** | Windows Subsystem for Linux 2 — a full Linux kernel running inside Windows. Windows users run all CrocoDash/CESM work here. |
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
5. Copies `run_case.sh` into `/workspace`

### CI/CD

Two GitHub Actions workflows handle CI/CD:

**Build** (`.github/workflows/build.yml`): builds and pushes multi-arch images automatically.
- **Trigger**: every Monday at 6am UTC, on version tags (`v*.*.*`), or manually via `workflow_dispatch`
- **Architectures**: `linux/amd64` and `linux/arm64` (via QEMU emulation)
- **Registry**: `ghcr.io/crocodile-cesm/crocontainer`
- **Tags**: `latest-amd64`, `latest-arm64`, per-commit `sha-<hash>-<arch>`, and a merged `latest` multi-arch manifest

**Container Tests** (`.github/workflows/container-test.yml`): validates the image on every push, weekly, and via manual dispatch. Three jobs, in sequence:
- **`smoke-test`**: pulls the image and verifies CrocoDash imports and CESM files are present
- **`domain-mom6-build`** (scheduled/manual only): builds CESM+MOM6 once per run and uploads it as a run-scoped artifact -- the executable is domain-independent (`MOM6_MEMORY_MODE=dynamic_symmetric`), so every domain job below shares this one compile. Built fresh each run rather than cached, so build regressions still surface
- **`domain-mom6-run`** (scheduled/manual only): one matrix job per selected domain -- restores that build and actually runs MOM6 on the domain, uploading `RUNDIR` as an artifact. Replaced a CIME `create_test` suite that checked the same thing on one hardcoded grid; adding a domain here is a row in CrocoDash's `tests/fixtures/domains.py`, not an upstream `testlist_mom.xml` entry plus testmods dir plus image rebuild
- **`domain-mom6-debug`** (scheduled/manual only): the same, on one domain, built with `DEBUG=TRUE` -- bounds checks and FP traps that the optimised build runs straight past
