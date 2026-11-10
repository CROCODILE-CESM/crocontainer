# Developing crocontainer

How to use the images: [`README.md`](README.md).

## Files

| File | What it does |
|---|---|
| [`Dockerfile`](Dockerfile) | All four images, as targets: `slim`; `slim-intel` (slim plus [`install_intel_toolchain.sh`](container_scripts/install_intel_toolchain.sh): oneAPI compilers and MPI, and netcdf-fortran, PnetCDF and ESMF built with them); `full` on either (`--build-arg FULL_BASE=slim-intel`), which adds CESM and CrocoDash with its env |
| [`container_scripts/cime/`](container_scripts/cime/config_machines.xml) | The CIME machine `ubuntu-latest` (paths, per-compiler settings, MPI launch) and its compiler macros, installed in `/root/.cime`, where it replaces CESM's own |
| [`container_scripts/apptainer_env.sh`](container_scripts/apptainer_env.sh) | Under Apptainer, keeps the host's `HOME` and `NCAR_HOST` out of the container |
| [`container_scripts/crocodash`](container_scripts/crocodash) | `crocodash` in the full images: runs the CLI in its env, so the env stays out of `case.build` |
| [`container_scripts/run_case.sh`](container_scripts/run_case.sh) | The one-command run in the full images; [`panama_demo_setup.sh`](container_scripts/panama_demo_setup.sh) makes its demo case |
| [`scripts/download_nyf_inputdata.sh`](scripts/download_nyf_inputdata.sh) | Fetches the input data a `DATM%NYF` case needs ([`nyf_inputdata_list.txt`](scripts/nyf_inputdata_list.txt)) |

## Building

```bash
podman build --target slim -t crocontainer:slim .
podman build --target slim-intel -t crocontainer:slim-intel .
podman build --target full -t crocontainer:latest .
podman build --target full --build-arg FULL_BASE=slim-intel -t crocontainer:latest-intel .
```

The full images copy the `CrocoDash` submodule; to build against CrocoDash `main`, as CI does, first run `git submodule update --init --remote CrocoDash && git -C CrocoDash submodule update --init --recursive`.

## CI

- [`build.yml`](.github/workflows/build.yml) builds every image weekly and on manual dispatch, and pushes per-commit `sha-<commit>-<image>` tags. Only runs on `main` move `slim`, `slim-intel`, `latest` and `latest-intel` (and the `-amd64`/`-arm64` tags behind the multi-arch ones), so a run dispatched on a branch makes images to test without replacing the ones people pull.
- [`container-test.yml`](.github/workflows/container-test.yml) runs a smoke test of the published image on every push and PR, and weekly runs the Panama demo end to end in `latest` (1 task) and `latest-intel` (4 tasks).

## Things to know

- **Apptainer passes the host's environment in,** and a Docker `ENV` only applies when the host doesn't set the variable. Put settings the build must have (compilers, MPI, ESMF) in the CIME machine's `<environment_variables>`, which win, not in `ENV`.
- **Intel libraries reach `cesm.exe` only through the machine's `LD_LIBRARY_PATH`, never `ldconfig`:** several share sonames with Ubuntu's (`libnetcdff.so.7`, `libpnetcdf.so.7`, ...), and the loader cache would hand the Intel ones to a gfortran build.
- **The machine must turn on ESMF's timing profile** (`ESMF_RUNTIME_PROFILE`). Without the timing file, CIME's timing step fails after the run when GitPython is importable, and `case.submit` errors on a run that succeeded.
- **`case.submit` reports success even when the run fails** on a machine with no batch system; check `CaseStatus` for `case.run success`, as `run_case.sh` does.
