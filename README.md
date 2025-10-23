# exdyn-sandbox
Process-explicit extinction dynamics sandbox with simulation, observation models, and scenario identification tooling built on `targets`.

## Quick Start
- `make init` — restore the `renv` library, regenerate documentation, and snapshot the lockfile.
- `make run` — execute the baseline `targets` pipeline defined in `_targets.R` (single configuration from `config/default.yaml`).
- `make exp` — run the full branched experiment grid (54 runs by default) and train classifiers.
- `make test` — run the `testthat` suite under `tests/testthat`.
- `make report` / `make report-id` — render `reports/sandbox.qmd` and `reports/identifiability.qmd` once the corresponding targets exist.

## Project Layout
- `R/` — package source with modular responsibilities:
  - `params.R` archetype priors, `simulate.R` population update loop, `conv2.R` dispersal kernel, `fields.R` scenario-specific driver fields, `observe.R` presence-only and fossil samplers.
  - `summaries.R` discriminative metrics (convexity, range dynamics, Moran’s I, arrival–extirpation coupling, anisotropy).
  - `experiments.R` Latin-hypercube sampling, grid assembly, and per-run execution.
  - `classify.R` balanced `ranger` and cross-validated `glmnet` classifiers plus confusion helpers.
  - `utils.R` configuration ingestion and helper utilities.
- `_targets.R` — orchestrates baseline runs, experiment branching, classifier selection, diagnostic rasters, and artefact persistence under `outputs/`.
- `config/` — YAML parameter files:
  - `default.yaml` single-run settings (50×50 grid, 150 years, predation front archetype B).
  - `experiments.yaml` factorial grid (species × scenario × predation type × replicate) with Latin-hypercube ranges for dispersal, predation speed, habitat erosion, climate drift, and observation bias.
- `tests/testthat/` — unit and integration coverage:
  - `test_sim.R` core simulator behaviour and observation sampling.
  - `test_experiments.R` grid expansion, summary sanity checks, classifier plumbing.
  - `test_front_signatures.R` scenario isolation (P vs H) and front-specific diagnostic thresholds.
- `reports/` — Quarto sources for sandbox overview and identifiability study; rendered HTML saved alongside inputs in `outputs/`.
- `outputs/` — cached artefacts (`N.rds`, presence/fossil CSVs, experiment summaries, confusion matrices, feature importance, design guidance, diagnostic PNGs).
- `logs/bootstrap.log` — action log for initial project bootstrapping.

## Configuration & Scenarios
`exdyn_config()` (see `R/utils.R`) loads YAML, injects archetype priors, and exposes predation front speed/seed coordinates, habitat ramps, climate drift, and observation bias. `exdyn_make_fields()` enforces driver isolation: `predation_front` zeroes habitat erosion while recording arrival times (`T_P`) and distance-to-front rasters (`D`); `habitat_erosion` sets predation to zero; `both` enables both drivers.

## Targets Pipeline Highlights
- Baseline targets (`cfg`, `default_fields`, `default_N`, `default_summs`) provide a reproducible single run.
- Experiment branching (`exp_grid`, `exp_summaries`) covers ≥54 combinations with Latin-hypercube draws per row and stores both driver-aware and response-only metrics.
- Classifier targets (`feature_sets`, `clf_driver_aware`, `clf_response_only`) compare balanced `ranger` vs CV `glmnet`, persisting confusion matrices, selected model details, and feature importances for both feature regimes.
- Diagnostic targets save arrival (`T_P`), extirpation (`T_X`), distance (`D`), scatter overlays, and plane-residual rasters for representative runs, alongside textual design guidance summarising predation-front recall and key metrics.
- Power-analysis targets (`power_grid`, `power_cv`, `save_power_outputs`) quantify response-only macro-F1 across observation bias and dispersal settings, emitting CSV+PNG artefacts.

## Testing & Quality Gates
The `testthat` suite runs in <1 minute on the default grid, guarding simulator equilibria, scenario isolation, front-signature strength (`r2_arrival`, `r2_dist`), summary completeness, and classifier outputs. Add new tests mirroring the module name under `tests/testthat/test_<module>.R`.

## Reports & Outputs
Running `tar_make()` followed by the report targets generates:
- `reports/sandbox.html` — baseline totals, sample counts.
- `reports/identifiability.html` — scenario recoverability, diagnostic panels, and feature importance comparisons.
- `reports/leakage_and_ablation.html` — leakage audit, response-only ablations, front-metric debugging, and power-curve diagnostics.
- CSV/RDS artefacts under `outputs/` (e.g., `experiment_results.csv`, `confusion_driver_aware.csv`, `confusion_response_only.csv`, `feature_importance_driver_aware.csv`, `feature_importance_response_only.csv`, `design_guidance.txt`, `power_curve_response_only.csv`) plus diagnostic PNGs in `outputs/diagnostics/`.

## Contributing
Follow the standards encapsulated in the code, keep commits in conventional format (e.g., `feat: ...`), and ensure `make test` and `make exp` are clean before opening a PR.
