# crocontainer

[![CESM runs in container](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml/badge.svg)](https://github.com/CROCODILE-CESM/crocontainer/actions/workflows/container-test.yml)
![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR_JRA_GLOFAS.json)
![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CR1850MARBL_JRA_GLOFAS.json)
![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GR_JRA_GLOFAS.json)
![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.CWR_JRA_GLOFAS.json)
![](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/CROCODILE-CESM/crocontainer/test-results/SMS_D_Ld2.GWR1850MARBL_JRA_GLOFAS.json)

Build and run [CrocoDash](https://github.com/CROCODILE-CESM/CrocoDash) regional MOM6 cases in CESM, with no machine port or batch queue.

| `ghcr.io/crocodile-cesm/crocontainer:` | Has | MPI tasks |
|---|---|---|
| `latest` | CESM (`crocodash`), CrocoDash `main` and its env | 1 |
| `latest-intel` | the same, built with Intel (x86-64 only) | many |
| `slim` | compilers, MPI, netCDF, ESMF; **you bring CESM and CrocoDash** | 1 |
| `slim-intel` | the same, Intel (x86-64 only) | many |

## Start a container

Mount CESM input data at `/root/cesm/inputdata` and a scratch directory at `/root/cesm/scratch`.

**Laptop** (Podman or Docker; input data: `bash scripts/download_nyf_inputdata.sh ./inputdata`):

```bash
podman run --rm -it -v ./inputdata:/root/cesm/inputdata -v ./scratch:/root/cesm/scratch \
  -v ~/croc:/croc ghcr.io/crocodile-cesm/crocontainer:<image> bash    # ~/croc: slim only
```

**Derecho** (Apptainer; build the sandbox once, then start it in a PBS job with the cores you want):

```bash
module load apptainer
qcmd -l select=1:ncpus=8 -l walltime=01:00:00 -- apptainer build --sandbox $SCRATCH/crocontainer docker://ghcr.io/crocodile-cesm/crocontainer:<image>
apptainer shell --writable --bind /glade \
  --bind /glade/campaign/cesm/cesmdata/inputdata:/root/cesm/inputdata \
  --bind $SCRATCH/croc_scratch:/root/cesm/scratch $SCRATCH/crocontainer
```

## Run a case

In your CrocoDash config, set `cesmroot` to the CESM in the container, `machine: ubuntu-latest`, and `caseroot`/`inputdir` under `/root/cesm/scratch` (their parent directories must exist). [`panama_case_config.yaml`](container_scripts/panama_case_config.yaml) is an example. Then:

```bash
crocodash create --config my_case.yaml
cd <caseroot>
./xmlchange NTASKS=8 && ./case.setup --reset    # intel images only
./case.build && ./case.submit
```

### latest, latest-intel

`cesmroot: /workspace/CESM`; `crocodash` is ready. `/workspace/run_case.sh` runs a Panama demo (`NTASKS=4 /workspace/run_case.sh` on `latest-intel`).

### slim, slim-intel

Once, get CESM and CrocoDash and make the env (on Derecho, put `croc` in `/glade/work/$USER`):

```bash
git clone -b crocodash https://github.com/CROCODILE-CESM/CESM ~/croc/CESM
(cd ~/croc/CESM && ./bin/git-fleximod update)
git clone --recurse-submodules https://github.com/CROCODILE-CESM/CrocoDash ~/croc/CrocoDash
cd ~/croc/CrocoDash && conda env create -p ~/croc/env -f environment.yml    # Derecho, on the host
cd /croc/CrocoDash && micromamba create -y -p /croc/env -f environment.yml  # laptop, in the container
```

Then in the container, activate it by full path (`~` is `/root` inside) and set `cesmroot` to your CESM (`/croc/CESM` on a laptop):

```bash
eval "$(micromamba shell hook -s bash)" && micromamba activate /croc/env    # or /glade/work/<you>/croc/env
```

More detail: [Running in a Container](https://crocodile-cesm.github.io/CrocoDash/for_users/container.html) in the CrocoDash docs. Building and CI: [`DEVELOPING.md`](DEVELOPING.md).
