# crocontainer

[![CESM runs in container](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml/badge.svg)](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml)

A container with CESM, [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash) and everything they need to build and run a regional MOM6 case, on a laptop (Podman or Docker) or on Derecho (Apptainer). No CESM install, no batch queue: the case builds and runs right where you are.

| Image | Runs on | MPI tasks |
|---|---|---|
| `ghcr.io/crocodile-cesm/crocontainer:latest` | x86-64 and ARM (Apple Silicon) | 1 |
| `ghcr.io/crocodile-cesm/crocontainer:latest-intel` | x86-64 (Derecho, Linux and Windows PCs) | as many as you have cores |

Both have CESM's `crocodash` branch and the latest CrocoDash `main`, rebuilt every week, or [use your own](#using-your-own-cesm-and-crocodash). The `intel` image builds CESM with Intel's compilers, as on Derecho; in the other, built with gfortran, MOM6 crashes on more than one task.

## Running a case

The container's CIME machine is `ubuntu-latest`, and the case is made, built and run with the usual commands. In your CrocoDash YAML config set:

```yaml
case:
  cesmroot: /workspace/CESM
  machine: ubuntu-latest
```

([`container_scripts/panama_case_config.yaml`](container_scripts/panama_case_config.yaml) is a complete example.) Then, in the container:

```bash
crocodash create --config my_case.yaml
cd <caseroot>
./xmlchange NTASKS=8 && ./case.setup --reset   # intel image only; the default is 1
./case.build
./case.submit
```

The run directory is `/root/cesm/scratch/<case>/run`, and with short-term archiving on, the output then moves to `/root/cesm/scratch/archive/<case>`. Mount a host directory at `/root/cesm/scratch` to keep them, and put `caseroot` and `inputdir` under it too (e.g. `/root/cesm/scratch/cases/mycase`). CESM's input data goes at `/root/cesm/inputdata`.

Forcings need their source data: on Derecho, `crocodash create` reads it from GLADE as usual. Elsewhere, see [Input data](#input-data), or make the case where the data is and bring it in as a [bundle](#bringing-in-a-case-from-another-machine).

### On Derecho (Apptainer)

Build a writable sandbox once (about half an hour):

```bash
module load apptainer
qcmd -l select=1:ncpus=8 -l walltime=01:00:00 -- \
  apptainer build --sandbox $SCRATCH/crocontainer docker://ghcr.io/crocodile-cesm/crocontainer:latest-intel
```

Then, in a PBS job with the cores you want (a login node gives you one), e.g. `qinteractive -l select=1:ncpus=8`:

```bash
module load apptainer
apptainer shell --writable --bind /glade \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind $SCRATCH/croc_scratch:/root/cesm/scratch \
  $SCRATCH/crocontainer
```

All of `/glade` is visible at its usual paths, so configs, cases and input directories can live anywhere on it. `HOME` is `/root` inside (CIME reads the container's machine from `~/.cime`); your own home is still at its `/glade` path, so point tools that want a file in `~`, such as `~/.cdsapirc`, at it there (e.g. `CDSAPI_RC`).

### On a laptop (Podman or Docker)

```bash
podman run --rm -it \
  -v ./inputdata:/root/cesm/inputdata \
  -v ./scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest bash
```

(`-v $PWD:/work` adds your configs.) On Windows, run Podman inside WSL2. On a Mac, `podman machine init && podman machine start` first.

### All in one command: `run_case.sh`

`/workspace/run_case.sh` makes a case at `/workspace/case`, builds it and runs it, from the first of: a YAML config mounted at `/workspace/case_config.yaml` (with `caseroot: /workspace/case`, `inputdir: /workspace/inputdir`), a bundle at `/workspace/bundle`, or a built-in Panama demo. `NTASKS` sets the tasks. With nothing mounted but input data, it's a test of the container:

```bash
podman run --rm -e NTASKS=4 \
  -v ./inputdata:/root/cesm/inputdata -v ./scratch:/root/cesm/scratch \
  ghcr.io/crocodile-cesm/crocontainer:latest-intel /workspace/run_case.sh
```

## Using your own CESM and CrocoDash

The image's copies trail the newest work, so you can mount your own checkouts instead:

- **CESM**: mount it anywhere and point `case.cesmroot` at it. On Derecho it's already there, with all of `/glade`. The container's CIME machine lives outside CESM (in `/root/.cime`), so your checkout needs nothing added and is not changed.
- **CrocoDash**: mount a checkout, with its submodules, over `/workspace/CrocoDash` (`-v ~/CrocoDash:/workspace/CrocoDash`, or `--bind` with Apptainer). The conda env has it installed in editable mode, so `crocodash` runs your code.

They must still suit what the image provides: a CESM whose CIME and components build with its ESMF 8.9.1, and a CrocoDash whose dependencies are in its conda env (if yours adds one, `pip install` it in a writable sandbox, or use a newer image).

## Bringing in a case from another machine

`crocodash bundle` packs a case (its config, your changes, its processed forcings) into a directory, and `crocodash create --from` makes it again on the container's machine:

```bash
crocodash bundle --caseroot ~/croc_cases/mycase --output-dir ~/bundles        # on the host
crocodash create --from ~/bundles/mycase_case_bundle --caseroot <caseroot> \
  --inputdir <inputdir> --cesmroot /workspace/CESM --machine ubuntu-latest \
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
| [`Dockerfile`](Dockerfile) | Ubuntu, gfortran, OpenMPI, netCDF, ESMF; the `CrocoDash` conda env; CESM |
| [`Dockerfile.intel`](Dockerfile.intel) | The `intel` image: the amd64 image plus [`install_intel_toolchain.sh`](container_scripts/install_intel_toolchain.sh) (oneAPI compilers and MPI, and netcdf-fortran, PnetCDF and ESMF built with them) |
| [`container_scripts/cime/`](container_scripts/cime/config_machines.xml) | The CIME machine `ubuntu-latest` (paths, per-compiler settings, MPI launch), installed in `/root/.cime` where it replaces CESM's own; [`apptainer_env.sh`](container_scripts/apptainer_env.sh) keeps `HOME` and `NCAR_HOST` from the host out of it |
| [`container_scripts/run_case.sh`](container_scripts/run_case.sh) | The one-command run; [`panama_demo_setup.sh`](container_scripts/panama_demo_setup.sh) makes its demo case |

Build locally:

```bash
podman build -t crocontainer .
podman build -f Dockerfile.intel --build-arg BASE_IMAGE=crocontainer -t crocontainer:intel .
```

To try a CrocoDash checkout of your own, mount it over `/workspace/CrocoDash`; the conda env has it installed in editable mode.

**CI**: [`build.yml`](.github/workflows/build.yml) builds and pushes the images weekly and on manual dispatch (`latest-amd64`, `latest-arm64`, `latest-intel`, per-commit `sha-*` tags, and the multi-arch `latest`). [`container-test.yml`](.github/workflows/container-test.yml) checks the published image on every push, and weekly runs the Panama demo end to end in `latest` (1 task) and `latest-intel` (4 tasks).

### Regional coupled tests on Derecho

Weekly runs of MOM_interface's regional smoke tests on cases built by the latest CrocoDash `main` and CESM `crocodash` (see [`cesm_tests/`](cesm_tests/README.md)):

| Compset | Components | SMS_D_Ld2 |
|---|---|---|
| `CR_JRA_GLOFAS` | MOM6 + GLOFAS runoff | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR_JRA_GLOFAS.json) |
| `CR1850MARBL_JRA_GLOFAS` | + MARBL | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR1850MARBL_JRA_GLOFAS.json) |
| `GR_JRA_GLOFAS` | + CICE | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GR_JRA_GLOFAS.json) |
| `CWR_JRA_GLOFAS` | + WW3 | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CWR_JRA_GLOFAS.json) |
| `GWR1850MARBL_JRA_GLOFAS` | MOM6 + CICE + WW3 + MARBL + GLOFAS | ![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GWR1850MARBL_JRA_GLOFAS.json) |
