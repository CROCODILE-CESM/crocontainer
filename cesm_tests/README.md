# CrocoDash runs of the MOM_interface regional tests

This checks that the current CrocoDash sets up the regional coupled compsets so that they actually run.

**What gets tested is not defined here.** It comes from MOM_interface's `testlist_mom.xml` in the CESM checkout. `run_mom_tests.py` selects every regional (`grid="USER_RES"`) `SMS` test for the machine and compiler. It keeps only the test's compset and options (`_D`, `_Ld2`, `_P<n>`) and rebuilds the case with CrocoDash on our domain (`config.yaml`) instead of the test's Panama testmods. It then runs the case and records each phase in a CIME `TestStatus` file.

- **Restart and other multi-run tests** (ERS etc.) are skipped. CESM's own `create_test` runs those with the Panama testmods, and they don't depend on CrocoDash output.
- **To cover a new compset,** add the test to `testlist_mom.xml` in MOM_interface. It is picked up here automatically.

## Run

Needs a checkout of `CROCODILE-CESM/CESM` branch `crocodash`, and a conda env with the CrocoDash you want to test.

```bash
git clone -b crocodash https://github.com/CROCODILE-CESM/CESM ~/CESM_crocodash
(cd ~/CESM_crocodash && ./bin/git-fleximod update)

cd cesm_tests
qsub -v CESMROOT=$HOME/CESM_crocodash,CONDA_ENV=CrocoDash run_mom_tests.pbs
# from Casper: qsub -q develop@desched1 ...
```

`python run_mom_tests.py --cesmroot ~/CESM_crocodash --test-root /tmp/x --dry-run` lists the tests that would run.

## Results

Each test gets its own directory under `$TESTROOT`:

```
SMS_D_Ld2.USER_RES.CR1850MARBL_JRA_GLOFAS.derecho_intel.crocodash.<testid>/
  TestStatus              CIME format: CREATE_NEWCASE, XML, SETUP, ..., RUN
  croc_test.log           output of every command
  crocodash_config.yaml   the exact config passed to `crocodash create`
  <same name as the test dir>/   the case (unique name, so each test gets its own CIME build/run dir)
  inputdir/
```

Check the results with CIME's own tool:

```bash
$TESTROOT/cs.status.<testid>
```

| Phase | What it covers |
|---|---|
| `CREATE_NEWCASE` | `crocodash create`, including configuring and processing forcings |
| `XML` | applying the test options, plus `NTASKS=--ntasks` (4) on every component, launched with `mpiexec -n` so parallel tests don't share cores |
| `SETUP` | `case.setup --reset` (crocodash create already ran case.setup) |
| `SHAREDLIB_BUILD` / `MODEL_BUILD` | `case.build` |
| `SUBMIT` / `RUN` | `case.submit --no-batch`; RUN passes only if `CaseStatus` records `case.run success` |

## Domain and forcing (`config.yaml`)

- **Domain:** a 20x16, 1/4° box over the Labrador coast, with GEBCO bathymetry and 10 uniform levels. It is far enough north that CICE has ice, and the coastline gives the GLOFAS runoff map rivers to map.
- **Ocean, ice and wave forcing:** the synthetic `reference_*` products, so nothing is downloaded.
- **Runoff, river nutrients and the MARBL IC:** real files on GLADE.
- **How forcing args are selected:** they are grouped by compset component, and each test gets only the groups its compset uses.
