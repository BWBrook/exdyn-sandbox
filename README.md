# exdyn-sandbox
Synthetic extinction-dynamics sandbox that couples a lattice-based population simulator with observation models, discriminative summaries, and classifier tooling. The project is an R package organised around the `targets` pipeline so that single runs, experiment grids, and identifiability studies are fully reproducible.

## Quick Start
- `make init` — restore the `renv` library, regenerate documentation, and snapshot the lockfile.
- `make run` — execute the baseline pipeline (`config/default.yaml`) and materialise the default outputs in `outputs/`.
- `make exp` — build the branched experiment grid (≥54 runs) and train both driver-aware and response-only classifiers.
- `make test` — run the `testthat` suite under `tests/testthat`.
- `make report` — render `reports/sandbox.qmd` after the baseline targets exist.
- `make report-id` — render the identifiability report (`reports/identifiability.qmd`).
- `make report-leak` — render the leakage/ablation report (`reports/leakage_and_ablation.qmd`).

## Repository Layout
- `R/` — package sources grouped by responsibility:
  - `params.R` archetype priors and helper transforms.
  - `fields.R` driver field constructors with predation arrival maps (`T_P`), distance rasters (`D`), and habitat ramps; enforces scenario isolation.
  - `simulate.R` density-dependent update with optional dispersal via FFT convolution (`conv2.R`).
  - `observe.R` presence-only and “fossil” samplers with configurable effort bias.
  - `summaries.R` discriminative metrics (convexity, range area, Moran’s I, arrival–extirpation coupling, anisotropy, response-only edge/front signals).
  - `experiments.R` Latin hypercube sampling, grid construction, and per-run execution helpers.
  - `classify.R` balanced `ranger` + CV `glmnet` learners, leakage-safe feature sets, confusion/importance utilities.
  - `utils.R` YAML ingestion (`exdyn_config`), archetype wiring, and common helpers.
- `_targets.R` — orchestrates baseline runs, experiment grids, power experiments, leakage audit, diagnostics, and report-ready artefacts under `outputs/`.
- `config/` — YAML configuration:
  - `default.yaml` single-run settings (50×50 grid, 150 years, predation front).
  - `experiments.yaml` grid + Latin hypercube ranges covering archetypes, scenarios, predation types, dispersal, habitat erosion, climate drift, observation bias, and replicate counts.
- `tests/testthat/` — suite safeguarding simulator fidelity (`test_sim.R`), grid expansion and summaries (`test_experiments.R`), driver isolation/front metrics (`test_front_signatures.R`), and leakage/response-only guards (`test_leakage_and_front.R`).
- `reports/` — Quarto sources (`sandbox.qmd`, `identifiability.qmd`, `leakage_and_ablation.qmd`).
- `outputs/` — tar targets persist CSV/RDS bundles, confusion matrices, feature importances, diagnostic rasters/PNGs, and design guidance text.
- `logs/bootstrap.log` — action log from the initial bootstrap.

## Simulation & Observation Modules
`exdyn_simulate()` integrates logistic growth with Allee effects, habitat erosion, and predation mortality, optionally blending dispersal via `exdyn_conv2()`. Driver fields are produced by `exdyn_make_fields()`, which records predation arrival (`T_P`) and coast-weighted habitat erosion while ensuring mutually exclusive scenarios. Observation models live in `observe.R` and emit presence-only samples with configurable effort gradients plus fossil-like detections with dating noise.

## Summary Feature Sets
`summaries.R` exposes two complementary feature regimes:
- **Driver-aware** summaries combine latent state (`N`) with driver rasters to compute arrival–extirpation coupling, distance-to-front regressions, cross-correlations with P/H, range dynamics, Moran’s I, convexity, centroid drift, and more.
- **Response-only** summaries restrict to information derivable from `N`/occupancy alone: edge speed/orientation, front-plane regressions, boundary coherence, range curvature, Moran’s I, centroid path linearity, and total-abundance slopes. Helper `exdyn_feature_sets()` returns vetted column lists to prevent leakage into response-only classifiers.

## Targets Pipeline Highlights
The pipeline (see `_targets.R`) includes:
- Baseline targets (`cfg`, `default_fields`, `default_N`, `default_summs`, `default_outputs`).
- Experiment grid (`exp_grid`, `runs`, `results`) covering archetype × scenario × predation type × replicate combinations with Latin hypercube perturbations.
- Leakage audit and classifier selection (`feature_sets`, `clf_driver_aware`, `clf_response_only`, `confusion_*`, `feature_importance_*`).
- Diagnostics (`diagnostic_rasters`, `front_scatter`, `design_guidance`) saving PNGs and summaries to `outputs/diagnostics/`.
- Power experiment / ablations (`power_grid`, `power_results`, `power_curve`) quantifying response-only macro-F1 as observation bias and dispersal vary.
- Report helpers (`report_inputs_*`) cached for Quarto rendering.

## Configuring Experiments
Edit `config/default.yaml` for single-run adjustments (grid size, years, threat scenario, observation settings). Broader sweeps live in `config/experiments.yaml`; key fields include `grid` (factorial combos of species, scenario, predation type), `defaults` (baseline lattice, dispersal, predation, habitat, observation controls), and `replicates`. Latin hypercube ranges feed `exdyn_experiment_grid()`; tweak ranges/rep counts and rerun `make exp`.

## Testing & Quality Gates
`make test` runs the complete `testthat` suite in under a minute. Tests assert:
- Logistic equilibrium and predation impacts (`test_sim.R`).
- Experiment grid size, summary completeness, classifier wiring (`test_experiments.R`).
- Scenario isolation and front diagnostics (`test_front_signatures.R`).
- Leakage guards and response-only front sanity checks (`test_leakage_and_front.R`).
Extend coverage by mirroring module names (e.g., `test_<module>.R`) and keeping scenarios deterministic for thresholds.

## Reports & Artefacts
After `tar_make()`:
- `reports/sandbox.html` — baseline abundance trajectory and sample counts.
- `reports/identifiability.html` — scenario recoverability, feature importance, diagnostic rasters.
- `reports/leakage_and_ablation.html` — driver-aware vs response-only confusion matrices, front metric diagnostics, power curves.
Outputs land in `outputs/`: baseline bundles (`N.rds`, `presence_only.csv`, `fossils.csv`, `total_abundance.csv`), experiment summaries (`experiment_results.csv`), confusion matrices (`confusion_driver_aware_*`, `confusion_response_only_*`), feature importances, design guidance (`design_guidance.txt`), diagnostic PNGs (`outputs/diagnostics/*.png`), and power experiment artefacts (`power_curve_response_only.csv`, `power_curve.png`).

## Development Workflow
Use conventional commits (`feat:`, `fix:`, `chore:`). Before committing, ensure `make test` passes and regenerate documentation (`devtools::document()`) if roxygen blocks change. Avoid committing `_targets/` cache; published artefacts belong in `outputs/` and rendered reports in `reports/`.
