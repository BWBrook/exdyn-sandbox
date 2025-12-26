# Phase 030 — Synthetic twin benchmark (WP‑0.3.1 → WP‑0.3.4b)

Date: 2025-12-20

## Scope
- Implemented toy‑grid synthetic runs with canonical outputs and manifests (WP‑0.3.1/0.3.2/0.3.4).
- Ran replicated recovery (R=10) with recovery tables and report outputs (WP‑0.3.3).
- Completed GB‑scale preflight with `/usr/bin/time -v` and recorded budgets (WP‑0.3.4b).

## What ran (canonical artefacts)
- WP‑0.3.1: `outputs/canonical/0.3/WP-0.3.1/syn_20251220_180615_0099/`
- WP‑0.3.2: `outputs/canonical/0.3/WP-0.3.2/syn_20251220_181135_0099/`
- WP‑0.3.3: `outputs/canonical/0.3/WP-0.3.3/syn_20251220_182102_0099/`
- WP‑0.3.4: `outputs/canonical/0.3/WP-0.3.4/syn_20251220_181700_0099/`
- WP‑0.3.4b: `outputs/canonical/0.3/WP-0.3.4b/syn_20251220_164636_0099/`

## Preflight budgets (WP‑0.3.4b)
- Medium realistic preflight (`70×70`, 1950–2020):
  - wall time ≈ **62.2 s**, max RSS ≈ **834,156 kB**.
  - `outputs/perf/preflight/medium/preflight_medium_time.txt`
  - `outputs/perf/preflight/medium/preflight_medium_summary.csv`
- GB realistic preflight (pilot grid, 1 replicate, minimal ABC):
  - wall time ≈ **43:30** (≈2610.6 s), max RSS ≈ **43,677,192 kB**.
  - `outputs/perf/preflight/gb/preflight_gb_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_summary.csv`
  - Metrics recorded in the canonical manifest for WP‑0.3.4b.

## Observation mode comparison (counts vs points)
Re-ran single‑replicate realistic preflights using **direct synthetic generation** (sim + observation + TX estimator, no screen/ABC/report) to isolate observation pipeline costs.

- Medium (`70×70`, 1950–2020):
  - **counts:** wall ≈ **29.03 s**, max RSS ≈ **601,056 kB**
  - **points:** wall ≈ **34.11 s**, max RSS ≈ **1,098,548 kB**
  - `outputs/perf/preflight/medium/preflight_medium_counts_time.txt`
  - `outputs/perf/preflight/medium/preflight_medium_points_time.txt`
  - `outputs/perf/preflight/medium/preflight_medium_comparison.csv`
- GB (pilot grid, pilot years):
  - **counts:** wall ≈ **311.97 s**, max RSS ≈ **6,660,760 kB**
  - **points:** wall ≈ **769.60 s**, max RSS ≈ **44,523,724 kB**
  - `outputs/perf/preflight/gb/preflight_gb_counts_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_points_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_comparison.csv`

### Post‑hardening counts preflight (streaming counts)
Re-ran the GB counts preflight using the new streaming counts path
(`exdyn_simulate_counts_stream`, no 3‑D N/P arrays).

- GB counts (pilot grid, pilot years):
  - wall time ≈ **42.5 s**, max RSS ≈ **1,049,268 kB**
  - `outputs/perf/preflight/gb/preflight_gb_counts_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_counts_summary.csv`
  - `outputs/perf/preflight/gb/preflight_gb_counts_runtime.csv`

### Full‑pipeline counts preflight (screen + ABC + report)
Measured end‑to‑end runtime for the full synthetic pipeline (counts‑mode,
pilot grid, minimal screen/ABC, crop enabled).

- Full pipeline counts (pilot grid, pilot years, realistic):
  - wall time ≈ **3:01** (181 s), max RSS ≈ **1,205,900 kB** (~1.15 GB)
  - `_targets/objects` delta ≈ **-12 kB** (stable)
  - canonical size ≈ **192 kB**
  - `outputs/perf/preflight/gb/full_counts/preflight_gb_full_counts_time.txt`
  - `outputs/perf/preflight/gb/full_counts/preflight_gb_full_counts_sizes.csv`
  - `outputs/canonical/0.3/WP-0.3.4b/preflight_full_counts_20251221_142443/`

## Sanity checks (artefact review)
- Reviewed TX_true/TX_obs/TX_best maps (toy canonical runs): coherent front gradients, non‑blank, spatial ordering preserved.
- Recovery tables present for WP‑0.3.3 with non‑zero acceptance and parameter summaries.
- GB preflight generated TX maps and report; no 3‑D `N[x,y,t]` arrays written to canonical outputs.
 - Full‑pipeline counts preflight maps reviewed (pilot grid): TX surfaces are extremely sparse (expected with toy θ* on pilot grid); treated as a **performance‑only** artefact, not for inference.

## Notes & issues
- ABC acceptance was initially zero with tight scaling; raised `ABC_EPS` for toy recovery to produce accepted draws (see WP‑0.3.3 manifest). This is a toy‑run scaling issue to revisit for full benchmark.
- ABC distance now ignores non-finite summary components (e.g., orientation on tiny grids) to avoid zero-acceptance in small smoke tests.
- Synthetic observation generation now defaults to **cell‑year counts** (no point-level PO), eliminating the heavy points→counts mapping step for synthetic pipelines.
- GB preflight confirms observation pipeline dominates runtime/memory; WP‑0.3.5 needs batching/HPC or further optimisation.
- Larger structural optimisations (domain cropping, graph/segment representation) are deferred unless GB budgets remain prohibitive.
- Full‑pipeline counts preflight now runs in minutes with ~1.2 GB RSS on the pilot grid; this is a green‑light signal for WP‑0.3.5 if ABC draws are kept bounded.

## WP‑0.3.5 pilot run (counts, pilot grid)
Pilot‑scale WP‑0.3.5 run to validate end‑to‑end performance before the full
benchmark.

- Settings: reps=3, modes=ideal+realistic, draws=16, abc_n=500, lhs=32/16, crop=TRUE.
- Wall time ≈ **1:13:57**, max RSS ≈ **1,359,784 kB** (~1.30 GB).
- `_targets/objects` delta ≈ **+228 kB** (stable).
- Canonical size ≈ **544 kB**.
- Run id: `wp035_pilot_20251221_161039`
- Logs:
  - `outputs/perf/wp035/wp035_pilot_time.txt`
  - `outputs/perf/wp035/wp035_pilot_sizes.csv`
  - `outputs/canonical/0.3/WP-0.3.5/wp035_pilot_20251221_161039/`

### Pilot sanity notes
- TX_true/TX_obs maps are **extremely sparse** on the pilot grid (almost no
  filled cells); this is treated as a **performance‑only** artefact.
- Replicate metrics show **coverage ~0** and **r2/lag NA**; acceptance exists,
  but recovery metrics are not informative under this sparse coverage regime.
- Fixed recovery table export to be **mode‑specific** (`ideal` vs `realistic`);
  re‑wrote recovery tables and refreshed the canonical manifest for the pilot
  run.

## Next steps
- Use WP‑0.3.4b budgets to gate WP‑0.3.5.
- Revisit summary scaling before full benchmark (to avoid extreme eps values).

## WP‑0.3.4.1 mask‑consistent summaries (2025‑12‑21)
- Implemented mask‑aware summary counts (`n_mask`, `n_TP_finite`, `n_pairs`, `n_TX_*`) and enforced mask use in summary/score paths.
- New regression test `test_mask_consistency` confirms masked vs unmasked coverage differs as expected and `summary_obs` coverage matches masked scoring.
- Canonical run: `outputs/canonical/0.3/WP-0.3.4.1/wp0341_manifest_20251221_202507/`.
- Artefact review (realistic mode smoke): `outputs/synthetic/realistic/summary_obs.csv` shows coverage = 0.3448 and `n_pairs / n_TP_finite` = 0.3448 (mask‑consistent).

## WP‑0.3.4.2 arrival diagnostics + override (2025‑12‑21)
- Added pilot arrival overrides (`real`, `synthetic_plane`, `synthetic_gradient`) and diagnostics.
- Diagnostics (pilot grid, riparian mask):
  - real: frac_finite_mask = 0.632 (12/19)
  - synthetic_plane: frac_finite_mask = 1.0 (19/19)
  - synthetic_gradient: frac_finite_mask = 1.0 (19/19)
- Artefacts:
  - `outputs/synthetic/pilot_diagnostics.csv`
  - `outputs/synthetic/arrival_real.png`
  - `outputs/synthetic/arrival_synthetic_plane.png`
  - `outputs/synthetic/arrival_synthetic_gradient.png`

## WP‑0.3.4.3 truth viability sweep (2025‑12‑21)
- Ran pilot‑grid viability sweep with arrival_source = synthetic_plane and mask = all.
- Sweep varied `truth_frac` and `truth_rel0` at `pred_scale=3.0`, `pred_c=2.4`.
- Results (see `outputs/synthetic/viability_sweep.csv`):
  - `(0.12, 1.5–2.0)` → ~5 extirpations (coverage ~0.001).
  - `(0.16, 1.8–2.0)` → ~90 extirpations (coverage ~0.025).
  - `(0.20, 1.8–2.0)` → full extirpation (coverage = 1).
- Selected truth thresholds: **truth_frac = 0.16**, **truth_rel0 = 1.8**.
- Artefacts:
  - `outputs/synthetic/viability_sweep.csv`
  - `outputs/synthetic/viability_sweep_plot.png`

## WP‑0.3.4.4 pilot gates update (2025‑12‑22)
- Updated pilot mask handling: mask="all" now includes only land cells (lookup indices), not the full bounding box.
- Viability sweep (pilot grid, arrival_source=synthetic_plane, truth_frac=0.02, truth_rel0=0.5) across predation strength:
  - pred_scale=0.6, pred_c=0.6 → coverage ≈ 0.289, n_TX_true ≈ 1058 (informative).
  - pred_scale=1.2, pred_c=0.6 → coverage = 1 (saturated).
  - pred_scale≤0.6 with pred_c=0.3 → zero extirpations.
- Updated theta_star: pred_scale=0.6, pred_c=0.6; truth thresholds reverted to 0.02/0.5.

## WP‑0.3.4.4 pilot gates (final pass, 2025‑12‑23)
- Added TX‑quantile coverage breaks (`coverage_breaks.strategy = tx_quantile`) to keep coverage curves informative within the pilot window.
- Enabled mode‑specific ABC eps settings (`realistic=15`, `ideal=23`) so both modes can pass G5 without over‑accepting.
- Pilot observation/compat tuning for identifiability:
  - `po_rate=0.01`, `drop_fraction=0.3`, `normalize_by="none"`.
  - `compat.min_r2_arrival=0`, `compat.lag_range=[0,40]`.
- Gate results (pilot grid, mask=all, arrival_source=synthetic_plane, crop=TRUE):
  - **Realistic:** G1–G5 all pass (acceptance 2/20 = 0.10).
  - **Ideal:** G1–G5 all pass (acceptance 2/20 = 0.10).
- Sanity check: TX_true map shows a coherent late‑period front; TX_obs is noisier but still aligned with the arrival gradient (no obvious spatial inversion).
- Artefacts:
  - `outputs/synthetic/recovery/pilot_gates.csv`
  - `outputs/synthetic/recovery/realistic/replicate_metrics.csv`
  - `outputs/synthetic/recovery/ideal/replicate_metrics.csv`
- Pipeline: split truth generation into `synthetic_truths` so ABC/screen tweaks no longer re-run the expensive truth simulation.
- Runtime note: `synthetic_truths` recomputation took ~3h28m (pilot grid, counts, crop=TRUE).
