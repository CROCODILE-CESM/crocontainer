# crocontainer

[![CESM runs in container](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml/badge.svg)](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml)

Containers that build and run CESM regional MOM6 cases made with [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash), on a laptop (Podman or Docker) or on Derecho (Apptainer). No CESM machine port, no batch queue: the case builds and runs right where you are.

| Image (`ghcr.io/crocodile-cesm/crocontainer:…`) | What's inside | Runs on | MPI tasks | Download |
|---|---|---|---|---|
| `slim` | compilers, MPI, netCDF, ESMF; **you bring CESM and a CrocoDash env** | x86-64, ARM | 1 | 0.5 GB |
| `slim-intel` | the same with Intel's compilers and MPI | x86-64 | as many as you have cores | 2.1 GB |
| `latest` | `slim` + CESM (`crocodash` branch) + CrocoDash `main` and its env | x86-64, ARM | 1 | 5.0 GB |
| `latest-intel` | `slim-intel` + the same | x86-64 | as many as you have cores | 6.7 GB |

`slim` is for when you keep your own CESM and CrocoDash up to date; `latest` has everything, rebuilt weekly, but trails the newest work. The `intel` images build CESM with Intel's compilers, as on Derecho; built with gfortran, MOM6 crashes on more than one task.

## Running a case

The container's CIME machine is `ubuntu-latest`, so in your CrocoDash YAML config set:

```yaml
case:
  cesmroot: /path/to/CESM     # /workspace/CESM in the latest images
  machine: ubuntu-latest
```

([`container_scripts/panama_case_config.yaml`](container_scripts/panama_case_config.yaml) is a complete example.) Then the usual commands, in the container:

```bash
crocodash create --config my_case.yaml
cd <caseroot>
./xmlchange NTASKS=8 && ./case.setup --reset   # intel images only; the default is 1
./case.build
./case.submit
```

In the `latest` images `crocodash` is ready to use. With `slim`, run it from your own CrocoDash env ([below](#slim-bring-your-own-cesm-and-crocodash)); it can stay active for `case.build`, which uses the container's compilers whatever is on your `PATH`.

The run directory is `/root/cesm/scratch/<case>/run`, and with short-term archiving on, the output then moves to `/root/cesm/scratch/archive/<case>`. Mount a host directory at `/root/cesm/scratch` to keep them, and put `caseroot` and `inputdir` under it too (e.g. `/root/cesm/scratch/cases/mycase`; CrocoDash wants their parent directories to exist). CESM's input data goes at `/root/cesm/inputdata`. Forcings need their source data: on Derecho, `crocodash create` reads it from GLADE as usual; elsewhere, see [Input data](#input-data), or make the case where the data is and bring it in as a [bundle](#bringing-in-a-case-from-another-machine).

### On Derecho (Apptainer)

Build a writable sandbox once:

```bash
module load apptainer
qcmd -l select=1:ncpus=8 -l walltime=01:00:00 -- \
  apptainer build --sandbox $SCRATCH/crocontainer docker://ghcr.io/crocodile-cesm/crocontainer:slim-intel
```

Then, in a PBS job with the cores you want (a login node gives you one), e.g. `qinteractive -l select=1:ncpus=8`:

```bash
module load apptainer
apptainer shell --writable --bind /glade \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind $SCRATCH/croc_scratch:/root/cesm/scratch \
  $SCRATCH/crocontainer
```

All of `/glade` is visible at its usual paths: your CESM, your conda envs, configs and cases. `HOME` is `/root` inside (CIME reads the container's machine from `~/.cime`); your own home is at its `/glade` path, so point tools that want a file in `~`, such as `~/.cdsapirc`, at it there (e.g. `CDSAPI_RC`).

### On a laptop (Podman or Docker)

```bash
podman run --rm -it \
  -v ~/croc:/croc \
  -v ./inputdata:/root/cesm/inputdata \
  -v ./scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:slim bash
```

On Windows, run Podman inside WSL2. On a Mac, `podman machine init && podman machine start` first.

## slim: bring your own CESM and CrocoDash

You need a CESM checkout (`crocodash` branch, or one compatible with the container's ESMF 8.9.1), with its components checked out, and a conda env with CrocoDash.

**On Derecho**, use the ones you have: in the container, `source <your conda>/etc/profile.d/conda.sh && conda activate <your CrocoDash env>`, and point `cesmroot` at your CESM. Derecho's envs run as they are in the container.

**On a laptop**, an env from your Mac or Windows won't run in the (Linux) container, so make both in it once, into the mounted `/croc`, where they last between containers:

```bash
git clone -b crocodash https://github.com/CROCODILE-CESM/CESM /croc/CESM
cd /croc/CESM && ./bin/git-fleximod update
git clone --recurse-submodules https://github.com/CROCODILE-CESM/CrocoDash /croc/CrocoDash
cd /croc/CrocoDash && micromamba create -y -p /croc/env -f environment.yml
```

Then each time: `eval "$(micromamba shell hook -s bash)" && micromamba activate /croc/env`, and `cesmroot: /croc/CESM`.

## The `latest` images

`crocodash` runs CrocoDash `main` from its env (`micromamba run -p /opt/conda/envs/CrocoDash python` for Python), and `cesmroot` is `/workspace/CESM`. To use a CESM or CrocoDash of your own in them anyway, point `cesmroot` at your CESM, or mount a CrocoDash checkout over `/workspace/CrocoDash` (the env has it installed in editable mode).

`/workspace/run_case.sh` makes a case at `/workspace/case`, builds it and runs it, from the first of: a YAML config mounted at `/workspace/case_config.yaml` (with `caseroot: /workspace/case`, `inputdir: /workspace/inputdir`), a bundle at `/workspace/bundle`, or a built-in Panama demo. `NTASKS` sets the tasks. With nothing mounted but input data, it's a test of the container:

```bash
podman run --rm -e NTASKS=4 \
  -v ./inputdata:/root/cesm/inputdata -v ./scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest-intel /workspace/run_case.sh
```

## Bringing in a case from another machine

`crocodash bundle` packs a case (its config, your changes, its processed forcings) into a directory, and `crocodash create --from` makes it again on the container's machine:

```bash
crocodash bundle --caseroot ~/croc_cases/mycase --output-dir ~/bundles        # on the host
crocodash create --from ~/bundles/mycase_case_bundle --caseroot <caseroot> \
  --inputdir <inputdir> --cesmroot <CESM> --machine ubuntu-latest \
  --project none --configure-only                                               # in the container
```

The forcings come with the bundle, so the case needs no data access in the container.

## Input data

On Derecho, mount `/glade/campaign/cesm/cesmdata/inputdata` as above. Elsewhere, [`scripts/download_nyf_inputdata.sh`](scripts/download_nyf_inputdata.sh) fetches what a normal-year-forcing (`DATM%NYF`) case needs, about 6.5 GB:

```bash
bash scripts/download_nyf_inputdata.sh ./inputdata          # from the CESM data server
bash scripts/download_nyf_inputdata.sh ./inputdata --from-glade <you>@derecho.hpc.ucar.edu
```

It resumes where it stopped, and uses `aria2c` when installed.

## Developing

| File | What it does |
|---|---|
| [`Dockerfile`](Dockerfile) | All four images, as targets: `slim`; `slim-intel` (slim plus [`install_intel_toolchain.sh`](container_scripts/install_intel_toolchain.sh): oneAPI compilers and MPI, and netcdf-fortran, PnetCDF and ESMF built with them); `full` on either (`--build-arg FULL_BASE=slim-intel`) |
| [`container_scripts/cime/`](container_scripts/cime/config_machines.xml) | The CIME machine `ubuntu-latest` (paths, per-compiler settings, MPI launch), installed in `/root/.cime` where it replaces CESM's own; [`apptainer_env.sh`](container_scripts/apptainer_env.sh) keeps `HOME` and `NCAR_HOST` from the host out of it |
| [`container_scripts/run_case.sh`](container_scripts/run_case.sh) | The one-command run; [`panama_demo_setup.sh`](container_scripts/panama_demo_setup.sh) makes its demo case |

Build locally:

```bash
podman build --target slim -t crocontainer:slim .
podman build --target full -t crocontainer:latest .
podman build --target full --build-arg FULL_BASE=slim-intel -t crocontainer:latest-intel .
```

**CI**: [`build.yml`](.github/workflows/build.yml) builds every image weekly and on manual dispatch, and pushes per-commit `sha-<commit>-<image>` tags. Only runs on `main` move `slim`, `slim-intel`, `latest` and `latest-intel` (and the `-amd64`/`-arm64` tags behind the multi-arch ones), so a run dispatched on a branch makes images to test without replacing the ones people pull. [`container-test.yml`](.github/workflows/container-test.yml) checks the published image on every push, and weekly runs the Panama demo end to end in `latest` (1 task) and `latest-intel` (4 tasks).

### Regional coupled tests on Derecho

Weekly runs of MOM_interface's regional smoke tests on cases built by the latest CrocoDash `main` and CESM `crocodash` (see [`cesm_tests/`](cesm_tests/README.md)):

| Compset | Components | SMS_D_Ld2 |
|---|---|---|
| `CR_JRA_GLOFAS` | MOM6 + GLOFAS runoff | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR_JRA_GLOFAS.json) |
| `CR1850MARBL_JRA_GLOFAS` | + MARBL | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR1850MARBL_JRA_GLOFAS.json) |
| `GR_JRA_GLOFAS` | + CICE | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GR_JRA_GLOFAS.json) |
| `CWR_JRA_GLOFAS` | + WW3 | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CWR_JRA_GLOFAS.json) |
| `GWR1850MARBL_JRA_GLOFAS` | MOM6 + CICE + WW3 + MARBL + GLOFAS | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GWR1850MARBL_JRA_GLOFAS.json) |
