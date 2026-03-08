# Repo hardening and characterization slice

Date: 2026-03-08

## Scope

- Harden fresh-checkout reproducibility and dependency truth.
- Clean the warning baseline in the test suite where semantics are unchanged.
- Add characterization tests around current high-risk scientific/engineering behaviours before broader refactors.
- Apply one low-risk internal cleanup (remove a duplicated helper definition).

## What changed

### Reproducibility / workflow

- Added non-mutating `make setup` and split lockfile/document maintenance into explicit `make document` and `make snapshot`.
- Kept `make init` as the full maintainer workflow.
- Removed `_targets.R` self-install behaviour for `qs`; it now fails clearly if the environment is incomplete.
- Added GitHub Actions CI (`.github/workflows/r-ci.yml`) for restore + `make test`.
- Expanded `DESCRIPTION` so operational/runtime dependencies used by package code and repo commands are declared.

### Tests / warning cleanup

- Replaced live-network GBIF target-group test with mocked local coverage.
- Removed current avoidable test warnings from:
  - tidyselect deprecation paths,
  - `sf` centroid/intersection chatter in grid/riparian helpers,
  - expected perfect-fit warnings in characterization tests.
- Added characterization tests for:
  - ABC distance behaviour when some summary dimensions are non-finite,
  - rejection when all summary dimensions are non-finite,
  - real-loss unit aggregation using earliest finite cell value,
  - deterministic ablation results across serial vs multicore execution.

### Internal cleanup

- Removed the duplicate `write_design_guidance()` definition from `R/targets_helpers.R`.

## What I ran

- Targeted verification:
  - `R --vanilla -e 'source("renv/activate.R"); devtools::test(filter = "gbif_helpers|experiments|summary_alignment|perf_hardening|arrival-realism|grid_aggregate|riparian_mask|abc_nonfinite|loss_real|real_ablation_determinism")'`
- Full verification:
  - `make test`

## Outcomes

- Full suite result after this slice:
  - `FAIL 0 | WARN 0 | SKIP 0 | PASS 247`
- No intended public API, YAML schema, target-name, or numerical-semantic changes were made in this slice.

## What remains next

- Medium-risk structural work is now better protected:
  - split the pilot target factory into cohesive sub-builders,
  - move more report-local wrangling into durable helpers/targets,
  - reduce drift between synthetic and real screen/ABC orchestration.
- High-risk science-semantic redesigns remain paused pending explicit approval.
