# exdyn-sandbox
Synthetic extinction-dynamics sandbox that couples a lattice-based population simulator with observation models, discriminative summaries, and classifier tooling. The project is an R package organised around the `targets` pipeline so that single runs, experiment grids, and identifiability studies are fully reproducible.

## Quick Start
- `make init` — restore the `renv` library, regenerate documentation, and snapshot the lockfile.
- `make test` — run the `testthat` suite under `tests/testthat`.
- `make run` — execute the full `targets` pipeline defined in `_targets.R` (can be expensive).
- `make exp` — build the branched experiment grid (≥54 runs) and train both driver-aware and response-only classifiers.
- `make pilot` — run the real-data mink → water vole pilot (build TX surfaces + screen/ABC + report).
- `make synthetic` — run the synthetic mink → vole twin (screen + ABC + report).
- `make report` — render `reports/sandbox.qmd` after the baseline targets exist.
- `make report-id` — render the identifiability report (`reports/identifiability.qmd`).
- `make report-leak` — render the leakage/ablation report (`reports/leakage_and_ablation.qmd`).

### Mink → water vole (GB): quick commands
The repo now includes two case-study pipelines alongside the legacy sandbox experiments:

- **Real-data pilot (mink → water vole):** `make pilot`  
  Produces mink arrival `T_P(x)` and observed vole extirpation timing `T_X_obs(x)` (first-passage), then runs a constrained screen/ABC and renders the pilot report.
- **Synthetic twin (mink → water vole):** `make synthetic`  
  Generates `T_X_true(x)` and `T_X_obs(x)` under a known truth, then runs the same screen/ABC + renders the synthetic report for recovery benchmarking.

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
- Mink → vole case-study configs:
  - `realdata.yaml` real-data pilot knobs (analysis units, effort normalisation, TX estimator controls, screening/ABC settings).
  - `synthetic.yaml` synthetic twin truth + noise settings and recovery run controls.
- `tests/testthat/` — suite safeguarding simulator fidelity (`test_sim.R`), grid expansion and summaries (`test_experiments.R`), driver isolation/front metrics (`test_front_signatures.R`), and leakage/response-only guards (`test_leakage_and_front.R`).
- `reports/` — Quarto sources:
  - legacy sandbox reports (`sandbox.qmd`, `identifiability.qmd`, `leakage_and_ablation.qmd`),
  - mink → vole reports (`pilot_mink_vole.qmd`, `synthetic_mink_vole.qmd`).
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
- Mink → vole case-study targets (real + synthetic), sourced via `pipelines/targets_pilot_mink_vole.R` and `pipelines/targets_synthetic.R`.

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
For the mink → vole pipelines:
- `reports/pilot_mink_vole.html` — real-data pilot (arrival + TX_obs reconstruction + constrained screen/ABC diagnostics).
- `reports/synthetic_mink_vole.html` — synthetic twin (truth vs observed TX + recovery diagnostics).
Outputs land in `outputs/` with a simple hierarchy: baseline bundles in `outputs/baseline/` (`N.rds`, `presence_only.csv`, `fossils.csv`, `total_abundance.csv`, `default_summary.rds`), experiment summaries + confusion matrices + feature importances + design guidance in `outputs/experiments/`, QA tables in `outputs/qa/`, diagnostic PNGs in `outputs/diagnostics/`, sensitivity sweeps in `outputs/sensitivity/`, and power experiment artefacts in `outputs/power/`.

## Development Workflow
Use conventional commits (`feat:`, `fix:`, `chore:`). Before committing, ensure `make test` passes and regenerate documentation (`devtools::document()`) if roxygen blocks change. Avoid committing `_targets/` cache; published artefacts belong in `outputs/` and rendered reports in `reports/`.
