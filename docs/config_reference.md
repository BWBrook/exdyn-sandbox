# Configuration reference

This file documents the key YAML configuration knobs used by the
synthetic and real-data pipelines. Update it whenever new keys are added
or meanings change.

---

## `config/synthetic.yaml` (synthetic mink→vole twin)

### `theta_star`
Generating (truth) parameters for synthetic runs.
Fields include: `rmax`, `A_over_K`, `alpha`, `disp_mean_km`, `pred_scale`,
`pred_c`, `pred_h`, `gamma`, `delta_region`, `ramp_years`, `pred_type`,
`pre_leak`, and (optionally) `truth_frac`, `truth_rel0`.

### `grid`
Controls the spatial grid used for synthetic runs.
- `type`: `"pilot"` (use GB grid) or `"toy"` (synthetic grid).
- For `type: "toy"`:
  - `nx`, `ny`: grid dimensions.
  - `cell_km`: cell size in km.
  - `riparian_frac`: fraction of cells flagged as riparian.
  - `region_n`: number of banded regions.
  - `region_labels`: optional labels for regions (e.g., `SCT`, `N_ENG`).
  - `seed`: RNG seed.
  - `arrival`: `pattern` (`gradient`, `row`, `col`), `noise_sd`, `span_frac`.

### `years`
Simulation years for synthetic runs. Either `[start, end]` or `"pilot"` to
use the pilot year range.

### `modes`
Vector of synthetic inference modes:
- `ideal`: inference on `TX_true` (algorithmic identifiability).
- `realistic`: inference on `TX_obs` after observation model + TX estimator.

### `recovery`
Replicated recovery harness settings:
- `n_reps`: number of replicated synthetic datasets.
- `seed`: RNG seed for replicate seeds.
- `reference_rep`: which replicate is used for maps/plots in the report.

### `noise`
Observation noise and TX estimator distortion controls.
Fields include: `po_rate`, `effort_strength`, `missing_years_prob`,
`random_tx_dropout`, `obs_mode` (`counts` or `points`), and
`keep_counts` (retain count tables in memory).

### `mask`
Spatial mask for synthetic runs: `"all"` or `"riparian"`.

### `screen`
Parameter screen settings and bounds. Must include `n_draws`, `seed`, `K0`,
plus bounds for `alpha`, `disp_mean_km`, `A_over_K`, `pred_c`, `pred_h`,
`ramp_years`, `pred_scale`, `gamma`, `rmax`, and optionally `delta_region`.

### `compat`
Compatibility thresholds for screening (`min_r2_arrival`, `lag_range`,
`min_coverage`).

### `abc`
ABC configuration. Keys include:
- `n_sims`, `eps`, `eps_tight`
- `scale`: named vector of summary scales
- `prior`: bounds mirroring `screen`
- `lhs`: optional seeding via Latin hypercube (`n`, `keep`, `seed`,
  `jitter_sd`, `seed_prob`)

### `tx_cfg`
First-passage TX estimator settings (`smooth_window`, `min_years_active`,
`baseline_window`, `drop_fraction`, `hold_years`, `normalize_by`).

### `canonical`
Controls canonical artefact output (WP-0.3.1+).
- `enabled`: boolean
- `root`: base folder (default `outputs/canonical`)
- `milestone`: milestone label (e.g., `0.3`)
- `wp_id`: work-package ID
- `run_id`: optional explicit run identifier
- `commands`: list of core commands used (recorded in manifest)

Environment overrides (optional, for reproducible smoke/canonical runs):
- `EXDYN_CANONICAL_ENABLED`, `EXDYN_CANONICAL_WP`,
  `EXDYN_CANONICAL_RUN_ID`, `EXDYN_CANONICAL_MILESTONE`,
  `EXDYN_CANONICAL_ROOT`
- `EXDYN_SYNTHETIC_MODES` (comma-separated, e.g. `ideal,realistic`).
- `EXDYN_SYNTHETIC_YEARS` (`"pilot"` or `start,end`).
- `EXDYN_SYNTHETIC_GRID_TYPE` (`pilot` or `toy`).
- `EXDYN_SYNTHETIC_GRID_NX`, `EXDYN_SYNTHETIC_GRID_NY`,
  `EXDYN_SYNTHETIC_GRID_CELL_KM`, `EXDYN_SYNTHETIC_GRID_RIPARIAN_FRAC`,
  `EXDYN_SYNTHETIC_GRID_REGION_N`,
  `EXDYN_SYNTHETIC_GRID_REGION_LABELS` (comma-separated).
- `EXDYN_SYNTHETIC_OBS_MODE` (`counts` or `points`).
- `EXDYN_SYNTHETIC_SMOKE=1` caps draw counts and simulation sizes.
- `EXDYN_SYNTHETIC_REPS=<int>` overrides `recovery.n_reps`.
- `EXDYN_SYNTHETIC_SCREEN_DRAWS=<int>` overrides `screen.n_draws`.
- `EXDYN_SYNTHETIC_ABC_N=<int>` overrides `abc.n_sims`.
- `EXDYN_SYNTHETIC_ABC_EPS=<num>` overrides `abc.eps`.
- `EXDYN_SYNTHETIC_ABC_EPS_TIGHT=<num>` overrides `abc.eps_tight`.
- `EXDYN_SYNTHETIC_ABC_LHS_N=<int>` and `EXDYN_SYNTHETIC_ABC_LHS_KEEP=<int>` override LHS scan sizes.
- `EXDYN_SYNTHETIC_ABC_REFINE=0/1` toggles the refined ABC stage.

---

## `config/perf.yaml` (performance & scaling benchmarks)

Performance profiling configuration for Milestone 0.2.x.

### `profiles`
Named profiles (`smoke`, `medium`, `full`) defining grid size, year range,
and observation inclusion.
Key fields:
- `grid`: `type` (`toy` or `pilot`), plus `nx`, `ny`, `cell_km`,
  `riparian_frac`, `region_n` for toy grids.
- `years`: `[start, end]` or `"pilot"` to use pilot year range.
- `replicates`: integer.
- `dispersal`: boolean flag for alpha on/off.
- `include_observation`: whether to generate `TX_obs` via the observation model.
- `mask`: `"riparian"` or `"all"`.
- `seed`: RNG seed.
- `arrival`: `pattern` (`gradient`, `row`, `col`), `noise_sd`, `span_frac`.

### `sim`
Simulation defaults for perf runs: `K0`, `rmax`, `A_over_K`, `alpha`,
`disp_mean_km`, `pred_c`, `pred_h`, `pred_scale`, `gamma`, `ramp_years`,
`pred_type`, `pre_leak`, `truth_frac`, `truth_rel0`.

### `obs`
Observation noise settings when `include_observation` is true:
`po_rate`, `effort_strength`, `missing_years_prob`, `random_tx_dropout`,
`obs_mode` (`counts` or `points`).

### `tx_cfg`
First-passage TX estimator settings for perf observation runs.

### `sweep`
Scaling sweep parameters: `grid_sizes`, `years`, `replicates`, `dispersal`,
plus `cell_km`, `riparian_frac`, `region_n`, and `arrival` settings.

### `optimisation`
Optimisation comparison configuration: `profile` (e.g., `smoke`),
`reps`, `seed`, and `target` (e.g., `tx_map_fast`).

---

## `config/realdata.yaml` (pilot mink→vole)

Key sections (high level):
- `pilot.analysis_unit`: representation choice (`segment` vs grid options)
- `pilot.years`: start/end year range
- `pilot.mink_P`: arrival field controls (ramp, scale, gamma, delta bounds)
- `pilot.vole`: TX estimator settings and effort normalisation
- `pilot.screen` / `pilot.abc`: screen + ABC settings

(See `config/realdata.yaml` for full parameter lists.)
