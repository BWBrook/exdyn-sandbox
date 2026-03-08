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

### `coverage_breaks`
Coverage-curve breakpoint configuration for synthetic summaries.
- `strategy`: `"years"` (fixed breaks over the full year range) or
  `"tx_quantile"` (breaks from TX quantiles in the current mode).
- `n_breaks`: number of interior breakpoints (default 4).
- `min_points`: minimum finite TX points required to use quantiles
  (otherwise falls back to `"years"`).

### `modes`
Vector of synthetic inference modes:
- `ideal`: inference on `TX_true` (algorithmic identifiability).
- `realistic`: inference on `TX_obs` after observation model + TX estimator.

### `recovery`
Replicated recovery harness settings:
- `n_reps`: number of replicated synthetic datasets.
- `seed`: RNG seed for replicate seeds.
- `reference_rep`: which replicate is used for maps/plots in the report.
- `n_cores`: optional parallel workers for recovery replicates (Linux/macOS only).

### `benchmark`
Benchmark stance and parameter-recovery gate metadata for canonical runs.
- `stance`: `"strict"` or `"weak_id"` (weak-identifiability declaration mode).
- `core_params`: parameters that define the core recovery gate
  (typically `alpha`, `disp_mean_km`).
- `gate_abs_rel_bias`: absolute relative-bias threshold for core gates.
- `gate_coverage80`: 80% interval-coverage threshold for core gates.
- `weak_id_parameters`: parameters explicitly allowed to be marked
  `weakly_identifiable` under `stance: weak_id`.

### `pilot_gates`
Identifiability gate configuration for pilot synthetic runs. When enabled,
the pipeline stops before ABC if core signal checks fail (arrival coverage,
TX coverage, coverage-curve informativeness, and screen compatibility).
- `enabled`: boolean.
- `thresholds`: resolved gate thresholds recorded in the manifest/report.
  Keys:
  - `arrival_frac_finite_min`
  - `tx_true_min`
  - `tx_true_coverage_min`
  - `tx_true_coverage_max`
  - `tx_obs_min`
  - `tx_obs_coverage_min`
  - `geom_finite_min`
  - `cov_curve_mid_min`
  - `screen_compatible_min`
  - `accept_rate_min`
  - `accept_rate_max`

### `arrival_realism`
Arrival-surface realism gate (WP-0.3.4.5). Runs matched synthetic recovery
comparisons under `arrival_source = real` vs synthetic overrides to test
identifiability sensitivity.
- `enabled`: boolean.
- `sources`: vector of arrival sources (e.g., `real`, `synthetic_plane`).
- `modes`: modes to compare (typically `ideal`, `realistic`).
- `reps`: number of replicated datasets (>=10 recommended).
- `seed`: RNG seed for comparison replicates.
- `screen`: optional overrides for the screen stage (e.g., `n_draws`,
  `crop`, `dispersal_mode`).
- `abc`: optional overrides for ABC (e.g., `n_sims`, `lhs.n`, `lhs.keep`).
- `graph`: graph-mode settings (`radius`, `include_self`) when
  `dispersal_mode = graph` is used.

### `mask_philosophy`
Masking philosophy gate (WP-0.3.4.6). Compares hard masking versus a soft
suitability weighting to assess connectivity and TX coverage.
- `enabled`: boolean.
- `arrival_source`: which arrival surface to use (`real` or synthetic override).
- `hard_mask`: which hard mask to compare (`riparian` or `all`); defaults to
  the synthetic mask if omitted.
- `scenarios`: vector of mask scenarios (`hard`, `soft`).
- `reps`: number of replicates per scenario.
- `seed`: RNG seed.
- `dispersal_mode`: `"fft"` or `"graph"` (graph recommended for GB).
- `graph`: graph settings (`radius`, `include_self`).
- `soft`: soft‑mask settings:
  - `method`: `river_km` or `riparian`.
  - `range`: scaling range applied to suitability weights.
  - `transform`: `log1p` (default) or `none`.

### `ceiling`
Information‑rich synthetic ceiling run (WP‑0.3.4.7). Runs a baseline vs
high‑information observation contrast on the pilot grid.
- `enabled`: boolean.
- `arrival_source`: arrival override used for both baseline and ceiling.
- `reps`: number of replicated datasets.
- `seed`: RNG seed for replicated datasets.
- `noise`: observation overrides for the ceiling run (baseline uses the main
  `noise` block).
- `screen`: optional overrides for the screen stage (e.g., `n_draws`).
- `abc`: optional overrides for ABC (e.g., `n_sims`, `lhs.n`, `lhs.keep`).

### `stress`
Identifiability stress mini‑sweep (WP‑0.3.6). Runs a small factorial over
information and process-strength axes and reports gate pass-rates.
- `enabled`: boolean.
- `mode`: synthetic mode used for stress runs (`realistic` default).
- `reps`: replicated datasets per stress scenario.
- `seed`: RNG seed for scenario/replicate generation.
- `n_cores`: optional multicore workers for scenario execution.
- `arrival_sources`: arrival variants to compare (typically `synthetic_plane`,
  `real`).
- `obs_multiplier`: multipliers applied to `noise.po_rate`.
- `pred_scale_multiplier`: multipliers applied to `theta_star.pred_scale`.
- `dropout_add`: additive increase to `noise.random_tx_dropout`.
- `screen`: optional screen overrides (e.g., `n_draws`, `crop`,
  `dispersal_mode`).
- `abc`: optional ABC overrides (`n_sims`, `eps`, `eps_tight`,
  `lhs.n`, `lhs.keep`, `refine`).
- `compat`: optional compatibility-threshold overrides.

### `viability`
Truth-viability sweep configuration used to tune `theta_star` for
informative synthetic extirpation patterns.
- `enabled`: boolean.
- `seed`: RNG seed.
- `pred_scale`, `pred_c`, `truth_frac`, `truth_rel0`: sweep grids.
- `crop`: whether to use cropped grid for the sweep.

### `noise`
Observation noise and TX estimator distortion controls.
Fields include: `po_rate`, `effort_strength`, `missing_years_prob`,
`random_tx_dropout`, `obs_mode` (`counts` or `points`), and
`keep_counts` (retain count tables in memory). Optional internal fields:
- `dispersal_mode`: `"fft"` (default) or `"graph"` (land-graph dispersal).
- `graph`: precomputed graph plan (injected programmatically, not YAML).
- `scale_matrix`: optional suitability multiplier matrix (injected for soft
  mask comparisons or global suitability weighting; not a YAML field).

### `suitability`
Optional global suitability weighting (soft mask) applied via
`noise.scale_matrix`.
- `enabled`: boolean.
- `method`: `river_km` or `riparian`.
- `range`: scaling range applied to suitability weights.
- `transform`: `log1p` (default) or `none`.

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
- optional `eps_by_mode` / `eps_tight_by_mode` named lists (keys `ideal`,
  `realistic`) to set mode-specific acceptance thresholds.
- `scale`: named vector of summary scales
- `required_metrics`: summary names that must stay finite for a draw to be valid
- `optional_missing_penalty`: additive standardized penalty per missing optional metric
- `prior`: bounds mirroring `screen`
- `lhs`: optional seeding via Latin hypercube (`n`, `keep`, `seed`,
  `jitter_sd`, `seed_prob`)

### `tx_cfg`
First-passage TX estimator settings (`smooth_window`, `min_years_active`,
`baseline_window`, `drop_fraction`, `hold_years`, `normalize_by`,
`threshold_mode`).
- `threshold_mode`:
  - `auto`: raw counts use `count_floor`; normalized series use `relative_baseline`
  - `count_floor`: `tau = max(1, floor(drop_fraction * baseline))`
  - `relative_baseline`: `tau = drop_fraction * baseline`

### `canonical`
Controls canonical artefact output (WP-0.3.1+).
- `enabled`: boolean
- `root`: base folder (default `outputs/canonical`)
- `milestone`: milestone label (e.g., `0.3`)
- `wp_id`: work-package ID
- `run_id`: optional explicit run identifier
- `commands`: list of core commands used (recorded in manifest)

Canonical `manifest.yaml` also records benchmark metadata:
- `benchmark.stance`
- `benchmark.core_params`
- `benchmark.weak_id_parameters_declared`
- `benchmark.weak_id_parameters_observed`
- `benchmark.gate_abs_rel_bias`, `benchmark.gate_coverage80`
- `benchmark.per_mode`
- `pilot_gates.enabled`, `pilot_gates.thresholds`

Environment overrides (optional, for reproducible smoke/canonical runs):
- `EXDYN_CANONICAL_ENABLED`, `EXDYN_CANONICAL_WP`,
  `EXDYN_CANONICAL_RUN_ID`, `EXDYN_CANONICAL_MILESTONE`,
  `EXDYN_CANONICAL_ROOT`
- `EXDYN_SYNTHETIC_MODES` (comma-separated, e.g. `ideal,realistic`).
- `EXDYN_SYNTHETIC_YEARS` (`"pilot"` or `start,end`).
- `EXDYN_SYNTHETIC_GRID_TYPE` (`pilot` or `toy`).
- `EXDYN_SYNTHETIC_ARRIVAL_REALISM=0/1` toggles the arrival realism gate.
- `EXDYN_SYNTHETIC_STRESS=0/1` toggles the WP‑0.3.6 stress mini-sweep.
- `EXDYN_SYNTHETIC_GRID_NX`, `EXDYN_SYNTHETIC_GRID_NY`,
  `EXDYN_SYNTHETIC_GRID_CELL_KM`, `EXDYN_SYNTHETIC_GRID_RIPARIAN_FRAC`,
  `EXDYN_SYNTHETIC_GRID_REGION_N`,
  `EXDYN_SYNTHETIC_GRID_REGION_LABELS` (comma-separated).
- `EXDYN_SYNTHETIC_OBS_MODE` (`counts` or `points`).
- `EXDYN_SYNTHETIC_MASK` (`all` or `riparian`).
- `EXDYN_SYNTHETIC_CROP=1` enables domain cropping for synthetic runs.
- `EXDYN_SYNTHETIC_SMOKE=1` caps draw counts and simulation sizes.
- `EXDYN_SYNTHETIC_REPS=<int>` overrides `recovery.n_reps`.
- `EXDYN_SYNTHETIC_CORES=<int>` overrides `recovery.n_cores`.
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
- `pilot.analysis_unit`: representation choice (`segment`, `grid_riparian`, `grid_all`)
- `pilot.unit_min_tx_obs`: minimum TX_obs units required for the representation gate
- `pilot.years`: start/end year range
- `pilot.mink_P`: arrival field controls (ramp, scale, gamma, delta bounds)
- `pilot.vole`: TX estimator settings and effort normalisation, including
  `threshold_mode` (`auto`, `count_floor`, `relative_baseline`)
- `pilot.loss`: loss aggregation settings; currently `unit_timing_stat: "median"`
- `pilot.screen` / `pilot.abc`: screen + ABC settings
- `pilot.ablation`: WP‑0.4.2 settings for δ‑only vs δ+RE comparison
  (`enabled`, `n_draws`, `n_cores`, `seed`)
  - Runtime overrides:
    - `EXDYN_ABLATION_CORES=<int>` caps ablation worker count without editing YAML.
    - `EXDYN_ABLATION_DRAWS=<int>` caps ablation draw count without editing YAML.
- `pilot.ppc`: posterior predictive check settings (`n_draws`, `seed`)
- `pilot.canonical`: canonical bundle controls for WP‑0.4.3+
  (`enabled`, `root`, `milestone`, `wp_id`, `run_id`, `commands`)

(See `config/realdata.yaml` for full parameter lists.)
