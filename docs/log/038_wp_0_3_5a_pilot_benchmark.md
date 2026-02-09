# WP‑0.3.5a Pilot Benchmark (graph‑mode, R=20)

**Date:** 2026‑02‑09  
**Status:** Complete (under declared weak-ID benchmark stance).

## Run context
- **Main command:**  
  `EXDYN_CANONICAL_ENABLED=1 EXDYN_CANONICAL_MILESTONE=0.3 EXDYN_CANONICAL_WP=WP-0.3.5a EXDYN_CANONICAL_RUN_ID=syn_20260208_234611_035a_full_bestfix EXDYN_SYNTHETIC_REPS=20 EXDYN_SYNTHETIC_CORES=20 make synthetic`
- **Canonical packaging command:**  
  `EXDYN_CANONICAL_ENABLED=1 EXDYN_CANONICAL_MILESTONE=0.3 EXDYN_CANONICAL_WP=WP-0.3.5a EXDYN_CANONICAL_RUN_ID=syn_20260208_234611_035a_full_bestfix EXDYN_SYNTHETIC_REPS=20 EXDYN_SYNTHETIC_CORES=20 R --vanilla -e 'source("renv/activate.R"); targets::tar_make(names = c("synthetic_canonical_manifest"))'`
- **Key config:**  
  - `grid.type = pilot`, `grid.arrival_source = synthetic_plane`  
  - `noise.obs_mode = counts`, `noise.dispersal_mode = graph`  
  - `screen.dispersal_mode = graph`, `abc.n_sims = 2000`  
  - `recovery.n_reps = 20`, `recovery.n_cores = 20`  
  - `benchmark.stance = weak_id`, `benchmark.core_params = [alpha, disp_mean_km]`
  - `benchmark.weak_id_parameters = [alpha, disp_mean_km]`

## Runtime and resources
- **Total wall time (`make synthetic`):** `1:10:03`
- **Main heavy target:** `synthetic_mode_runs` completed in `1h 7m 19s`
- **Max RSS (driver process, `/usr/bin/time -v`):** `4,175,256 kB` (~4.0 GB)
- **Parallel worker snapshot during run:** ~20 workers at full CPU, ~55–65 GB aggregate RSS.
- Runtime log: `outputs/perf/syn_20260208_234611_035a_full_bestfix_time.log`

## Pilot gates (G1–G5)
Gate pass rates are 1.0 for both modes across replicates:
- `G1_arrival`: pass
- `G2_TX_true`: pass
- `G3_TX_obs`: pass
- `G4_cov_curve`: pass
- `G5_screen_abc`: pass

Evidence: `outputs/synthetic/recovery/pilot_gates.csv`

## Benchmark gates
### Ideal mode (core parameters)
- `alpha`: `identifiability_status = weakly_identifiable`, `coverage_80 = 0.90`, `rel_bias_median ≈ -0.385`
- `disp_mean_km`: `identifiability_status = weakly_identifiable`, `coverage_80 = 1.00`, `rel_bias_median ≈ +0.291`

These do **not** meet strict recoverable bias thresholds, but they are explicitly declared weak-ID in benchmark metadata and observed as such, which satisfies WP‑0.3.5a under the weak-ID stance.

### Realistic mode
- `median abc_lag_median ≈ 19.192` (positive, plausible range)
- `median abc_r2_median ≈ 0.633` (>= 0.50 gate)

Evidence: `outputs/synthetic/recovery/realistic/replicate_metrics.csv`

## Visual sanity checks
- `TX_true`, `TX_obs`, `TX_best`, and `TX_diff` are populated and geographically coherent in both modes.
- Best-map selection is consistent with ranked screen rows after the `best_index`/ranking alignment fix.
- No recurrence of the earlier “tiny 1985 strip” best-map pathology in the current outputs.

## Artefacts
- Live outputs:
  - `outputs/synthetic/ideal/*`
  - `outputs/synthetic/realistic/*`
  - `outputs/synthetic/recovery/*`
- Canonical run:
  - `outputs/canonical/0.3/WP-0.3.5a/syn_20260208_234611_035a_full_bestfix/`

## Notes
- `make synthetic` did not previously force canonical packaging because
  `synthetic_canonical_manifest` was not in the named target set. The Makefile
  target has been patched so canonical output is now emitted by default when
  canonical env flags are enabled.
