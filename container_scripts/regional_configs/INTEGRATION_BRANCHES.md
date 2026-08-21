# Temporary integration branches

CI here runs against unmerged work in other repos. Rather than wait on merges,
the submodule pointer targets a throwaway branch that combines what is needed.
This file records what those branches are and when each can be retired, so a
"why is the pointer on a weird branch" question has an answer.

None of these branches is intended to merge anywhere.

## `CROCODILE-CESM/CrocoDash` @ `ci-integration-domain-sweep`

Pointed at by this repo's `CrocoDash` submodule. Contents:

| source | why it is needed |
|---|---|
| `refactor-obc-ic` (#265) | `REFERENCE_OCEAN` — deterministic synthetic forcing, no network or credentials |
| `fix-custom-compset-multi-modifier` (#272) | custom multi-modifier compsets, e.g. `MOM6%REGIONAL%MARBL-BIO` |
| REFERENCE_OCEAN MARBL tracers (#273) | MARBL tracers in the synthetic product, for when BGC returns |
| `domain-test-matrix` (#274) | the domain catalog and `recipe.py`'s `grid.type` dispatch |

#272 and #273 arrived via the earlier `tmp-ci-validation-bgc` branch, which this
one supersedes.

#274 is what the `domain-sweep` job needs, and it needs *both* halves:

- `tests/fixtures/domains.py` — the `DomainSpec` catalog `run_domain_sweep.py`
  imports rather than duplicates.
- `CrocoDash/recipe.py` — the `grid.type` dispatch. Without it
  `Grid.from_projection` and `Grid.from_center` are unreachable from a config,
  so the polar caps and rotated grids cannot be expressed as YAML at all and
  the sweep would cover only the rectangular half of the catalog.

The submodule is injected whole -- mounted at `/workspace/crocodash_src` and
put ahead of the image's copy on `PYTHONPATH` -- rather than having individual
files mounted over the image's install. Cherry-picking does not work: the image
is rebuilt weekly from `main`, so its baked CrocoDash is at some older commit,
and mounting half of a refactor over the other half fails. `PYTHONPATH` must
include `CrocoDash/visualCaseGen` as well as the checkout root and
`CrocoDash/rm6`, because `visualCaseGen` and `ProConPy` are imported as
top-level packages and would otherwise resolve to the image's older copies.

**Retire when** #274 and its base #265 have merged and `build.yml` has
republished `latest-amd64` -- at which point the injection, the
`CROCODASH_ROOT` override and the `PYTHONPATH` entries all come out. The guard
in `discover-domains` emits an empty matrix with a message naming the pointer
if it ever regresses below #274, so a regression is loud rather than silent.

## `NCAR/mom6_forge` @ `ci-integration-metrics`

Not currently pointed at by anything here — it exists so CrocoDash's domain
matrix can be validated against both open metric fixes at once:

| source | fix |
|---|---|
| `fix-polar-dx-antimeridian-wrap` (#113) | `dx`/`dy` sign and antimeridian wrap in `_calc_dx_dy` |
| `fix-tarea-quadrant-sum` (#126) | `tarea` double-counting one supergrid quadrant and omitting another |

The merge needed one trivial conflict resolution: both sides had added to the
same two import lines in `_supergrid.py`, so the union was taken.

CrocoDash's domain tests were checked against this branch and against the
mom6_forge its own submodule chain pins. They pass both ways — the xfails for
those two bugs are decided by a runtime capability probe rather than pinned to
one side, so bumping the mom6_forge pointer is a no-op for that suite:

| mom6_forge | result |
|---|---|
| as pinned by CrocoDash | 222 passed, 6 skipped, 28 xfailed |
| `ci-integration-metrics` | 229 passed, 6 skipped, 7 xfailed |

(The `ci-integration-metrics` row was measured before the
`equator_prime_meridian` domain was added, so its totals are one domain
behind; the point it makes -- that the probes make the pointer a no-op -- is
unaffected.)

One caveat worth knowing: **#113 does not fix the inflated bounding box** on a
rotated domain crossing the antimeridian. It widens any raw longitude span over
180 degrees to the full range on purpose — that stops `lon_max` landing exactly
on `180.0` and being collapsed to `-180.0` by downstream normalization — so a
few-hundred-km domain still reports a near-global span. Narrowing it properly
needs the bounding box to carry a wrapped range (`lon_min > lon_max`), which
every consumer of `get_bounding_boxes` would have to understand. That domain
therefore stays an expected failure in CrocoDash's suite under both branches.

**Retire when** #113 and #126 have both landed on `main`.
