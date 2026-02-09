# WP-0.3.5b — GB canonical synthetic benchmark (graph mode, R=20)

Date: 2026-02-09
WP: `WP-0.3.5b`
Milestone: `0.3`
Canonical run id: `syn_20260209_134622_035b_full_r20`
Canonical folder: `outputs/canonical/0.3/WP-0.3.5b/syn_20260209_134622_035b_full_r20/`

## Objective
- Execute the first GB-grid canonical synthetic benchmark with:
  - graph-mode dispersal,
  - `R >= 20` replicated recovery,
  - ideal + realistic modes,
  - canonical manifest/report outputs,
  - benchmark gates enforced.

## Commands run
- Pre-run budget estimate (single-replicate, same WP/channel):
  - `EXDYN_CANONICAL_ENABLED=1 EXDYN_CANONICAL_MILESTONE=0.3 EXDYN_CANONICAL_WP=WP-0.3.5b EXDYN_CANONICAL_RUN_ID=syn_20260209_115116_035b_preflight_r1 EXDYN_SYNTHETIC_REPS=1 EXDYN_SYNTHETIC_CORES=1 /usr/bin/time -v R --vanilla -e "source('renv/activate.R'); targets::tar_make(names=c('synthetic_report_html','synthetic_report_pdf','synthetic_recovery_written','synthetic_canonical_manifest'), callr_function = NULL)"`
- Canonical full run (`R=20`):
  - `EXDYN_CANONICAL_ENABLED=1 EXDYN_CANONICAL_MILESTONE=0.3 EXDYN_CANONICAL_WP=WP-0.3.5b EXDYN_CANONICAL_RUN_ID=syn_20260209_134622_035b_full_r20 EXDYN_SYNTHETIC_REPS=20 EXDYN_SYNTHETIC_CORES=50 /usr/bin/time -v R --vanilla -e "source('renv/activate.R'); targets::tar_make(names=c('synthetic_report_html','synthetic_report_pdf','synthetic_recovery_written','synthetic_canonical_manifest'), callr_function = NULL)"`

## Runtime and memory
- Preflight (`R=1`):
  - wall time: `1:19:15`
  - max RSS (`time -v`): `1,356,728 kB` (~1.29 GB)
  - log: `outputs/perf/syn_20260209_115116_035b_preflight_r1_time.log`
- Full canonical (`R=20`):
  - wall time: `1:11:27`
  - target pipeline duration: `1h 11m 9.7s`
  - `synthetic_mode_runs` duration: `1h 8m 51.4s`
  - max RSS from `time -v` (parent): `4,118,688 kB` (~3.93 GB)
  - observed aggregate worker RSS snapshot during parallel phase: `~75.03 GB` (20 workers, plus ~1.9 GB parent)
  - log: `outputs/perf/syn_20260209_134622_035b_full_r20_time.log`

## Gate results
- Source: `outputs/synthetic/recovery/pilot_gates.csv`
- Result: all gates pass for both modes across all 20 replicates (`G1`–`G5` all `TRUE`).
- Key medians (from replicate metrics):
  - ideal: `abc_lag_median ≈ 17.05`, `abc_r2_median ≈ 0.919`, median accept rate `≈ 0.023`
  - realistic: `abc_lag_median ≈ 19.19`, `abc_r2_median ≈ 0.633`, median accept rate `≈ 0.0135`
- Benchmark stance / weak-ID declaration:
  - manifest records `benchmark.stance = weak_id`
  - core params declared: `alpha`, `disp_mean_km`
  - observed weak-ID list present in canonical manifest.

## Arrival-coverage realism check
- Source: `outputs/synthetic/pilot_diagnostics.csv`
- `arrival_source=real` has sparse finite coverage in-mask (`frac_finite_mask ≈ 0.4096`).
- Synthetic overrides (`synthetic_plane`, `synthetic_gradient`) are complete in-mask (`frac_finite_mask = 1.0`).
- Canonical benchmark therefore uses `synthetic_plane` for identifiability benchmarking while preserving real-arrival diagnostics in the bundle.

## Artefact sanity inspection
- Checked map suite:
  - `outputs/synthetic/ideal/TX_true_syn.png`
  - `outputs/synthetic/ideal/TX_obs_syn.png`
  - `outputs/synthetic/ideal/TX_best_syn.png`
  - `outputs/synthetic/ideal/TX_diff_syn.png`
  - analogous realistic-mode maps in `outputs/synthetic/realistic/`
- Sanity outcomes:
  - `TX_true` front is spatially coherent and georeferenced correctly (GB+IE orientation fixed).
  - `TX_obs` is sparse/noisy but covers broad domain (signal retained under observation model).
  - `TX_best` captures broad front geometry but smooths regional structure (consistent with weak-ID stance).
  - `TX_diff` shows structured, spatially coherent biases rather than random noise.

## Canonical artefacts
- Canonical package root:
  - `outputs/canonical/0.3/WP-0.3.5b/syn_20260209_134622_035b_full_r20/`
- Size:
  - `~600K` (`du -sh`)
- Includes:
  - `manifest.yaml`, `session_info.txt`, config snapshot,
  - map/CSV outputs for ideal + realistic modes,
  - recovery tables and gate table.

## Notes
- `make synthetic` in this run path includes `synthetic_canonical_manifest` so canonical packaging is emitted automatically.
- The large parallel phase is CPU-bound and memory-moderate under graph mode; no process instability observed.

## Post-run validation
- Command:
  - `make test`
- Result:
  - PASS (`FAIL 0 | WARN 45 | SKIP 0 | PASS 226`)
  - warnings are existing known warnings (sf/yardstick/tidyselect deprecations), no new test failures.
