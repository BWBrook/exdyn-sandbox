# Repository Guidelines

## Project Structure & Module Organization
- `R/`: package source files, grouped by responsibility (e.g., `fields.R` for threat fields, `experiments.R` for grid drivers, `classify.R` for modelling).
- `config/`: YAML configurations (`default.yaml`, `experiments.yaml`) that parameterise single runs and experiment grids.
- `_targets.R`: orchestrates the `targets` pipeline; cached data live under `_targets/` after execution.
- `tests/testthat/`: unit and integration tests (`test_sim.R`, `test_experiments.R`).
- `reports/`: Quarto sources and rendered HTML (`sandbox.qmd`, `identifiability.qmd`). Rendered outputs belong here, while CSV/RDS artefacts land in `outputs/`.
- `renv/`, `renv.lock`, `.Rprofile`: reproducible R environment setup — never edit by hand.

## Build, Test, and Development Commands
- `make init` — restore `renv`, rebuild docs, refresh `renv.lock`.
- `make test` — run `devtools::test()` across `tests/testthat`.
- `make run` / `make exp` — execute the `targets` pipeline (baseline vs full experiment grid).
- `make report` — render `reports/sandbox.qmd` after loading cached targets.
- `make report-id` — render the identifiability study (`reports/identifiability.qmd`).

## Coding Style & Naming Conventions
- R code uses two-space indentation, `snake_case` for functions/objects, and descriptive target names (e.g., `exp_grid`, `default_foss`).
- Document exported functions with roxygen2 comments (`#'` blocks) and run `devtools::document()` before committing.
- Prefer tidyverse idioms (`tibble`, `dplyr`, `purrr`); keep side-effectful code inside helper functions or target expressions.

## Testing Guidelines
- Place tests in `tests/testthat`, mirroring the module name (`test_<module>.R`). Use `test_that()` descriptions that read like requirements.
- Run `make test` before commits; for pipeline changes, also run `make exp` to ensure branching targets complete within the expected wall-clock budget.
- Investigate new warnings immediately—`targets` caches failures and may require `tar_make()` reruns after fixes.

## Commit & Pull Request Guidelines
- Follow the existing conventional-commit style (`feat:`, `fix:`, `chore:`). Summaries should describe the outcome, not the process.
- Prior to a commit, ensure `git status` is clean, documentation regenerated, and `renv.lock` updated if dependencies changed.
- PRs should link to relevant issues, list key CLI commands executed (`make test`, `make exp`), and include screenshots or artefact paths when updating reports.

## Pipeline Operations Tips
- When adjusting experiment breadth, edit `config/experiments.yaml` and regenerate with `tar_make()`; monitor runtime to stay ≤40 minutes on defaults.
- Avoid committing large artefacts from `_targets/`; use `outputs/` for published CSV/RDS bundles referenced in reports.
