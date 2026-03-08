# Output schema (synthetic twin focus)

This document records stable output schemas for synthetic mink→vole runs.
If schemas change, bump `exdyn_schema_version()` in `R/schema.R` and update this file.

---

## Schema version

- **Authoritative source:** `R/schema.R` (`exdyn_schema_version()`).
- **Current version:** 0.4.0

---

## Synthetic twin outputs

### Core synthetic outputs (single-run/reference)

Location: `outputs/synthetic/<mode>/` where `<mode>` is `ideal` or `realistic`.

Files (current stable set):
- `screen_results.csv` — parameter screen results (one row per draw).
  - Required columns (minimum): `draw`, `loss`, `coverage`, `lag_mean`, `r2_arrival`.
  - Required count fields (mask‑aware): `n_mask`, `n_TP_finite`, `n_TX_obs`,
    `n_TX_sim`, `n_pairs_obs`, `n_pairs_sim`.
  - Parameter columns mirror `config/synthetic.yaml` names plus `delta_<REGION>` entries.
- `abc_posterior.csv` — accepted ABC samples (one row per accepted draw).
- `abc_summary.csv` — posterior summary statistics (per parameter).
- `summary_obs.csv` — observed summary vector used in ABC (name/value pairs).
  - Includes count fields appended to the summary vector:
    `n_mask`, `n_TP_finite`, `n_pairs`, `n_TX_use`, `n_TX_true`, `n_TX_obs`,
    `n_pairs_true`, `n_pairs_obs`.
- `theta_star.yaml` — generating parameters (truth).
- `TX_obs_syn.png` — observed/noisy extirpation surface (TX_obs).
- `TX_true_syn.png` — true extirpation surface (TX_true).
- `TX_best_syn.png` — best simulated surface from the screen.
- `TX_diff_syn.png` — TX_best minus TX_true (year differences).

Stable naming conventions:
- Delta parameters are named `delta_<REGION>` (e.g., `delta_SCT`).
- Coverage-curve summaries are named `cov_curve_1`, `cov_curve_2`, …

---

## Recovery summaries (replicated synthetic benchmark)

Location: `outputs/synthetic/recovery/<mode>/`

### `replicate_metrics.csv`
One row per replicate, per mode.

Required columns:
- `mode`, `replicate`, `seed`
- `n_mask`, `n_TP_finite`, `n_TX_true`, `n_TX_obs`, `n_pairs`
- `n_accept`, `eps`
- `screen_best_loss`, `screen_best_r2`, `screen_best_lag`, `screen_best_coverage`
- `abc_distance_median`, `abc_lag_median`, `abc_coverage_median`, `abc_r2_median`

### `parameter_recovery.csv`
One row per parameter, per mode (summarised across replicates).

Required columns:
- `mode`, `param`, `truth`
- `bias`, `abs_bias`, `rel_bias`, `mae`
- `coverage_50`, `coverage_80`, `coverage_95`
- `posterior_sd_median`, `prior_sd`, `shrinkage_ratio`
- `identifiability_status`, `gate_pass`, `core_param`
- `n_reps`

Status taxonomy (0.4.0):
- `recoverable`
- `weakly_identifiable`
- `not_recoverable`
- `unassessed`

### `benchmark_summary.csv`
One row per mode summarising the config-authoritative benchmark verdict.

Required columns:
- `mode`, `stance`
- `n_core_params_expected`, `n_core_params_present`
- `core_params_missing`
- `n_core_recoverable`, `n_core_weak_id`, `n_core_not_recoverable`, `n_core_unassessed`
- `overall_benchmark_pass`

### `pilot_gates.csv`
One row per gate, replicate, and mode.

Required columns:
- `mode`, `replicate`, `gate`, `pass`
- `value`, `threshold`

Resolved pilot-gate thresholds are also recorded in canonical manifests from 0.4.0 onward.

---

## Summary-vector schema (response-only)

The synthetic ABC uses a response-only summary vector. For the default
coverage-curve breakpoints (4), the summary names are:

- `grad_mag`, `pc_ratio`, `coverage`, `lag_mean`, `lag_sd`, `r2_arrival`,
  `orient_R`, `speed_cells_per_year`, `speed_r2`, `tx_mean`, `tx_sd`,
  `cov_curve_1`, `cov_curve_2`, `cov_curve_3`, `cov_curve_4`.

In schema 0.4.0 the summary-vector names are unchanged, but benchmark semantics,
pilot-gate provenance, and recovery status meanings changed materially. Future
changes to summary names, benchmark semantics, or canonical provenance fields
should trigger another schema bump.
