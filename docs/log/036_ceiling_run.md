# WP-0.3.4.7 — Information-rich synthetic ceiling run

Date: 2025-12-31

## What ran
- Ceiling configuration (pilot grid) with rich observations:
  - `po_rate = 0.05`, no missing years or dropout.
  - arrival_source = `synthetic_gradient` (full coverage for identifiability ceiling).
  - Graph-mode dispersal (noise + screen).
  - R = 10 ceiling replicates.
- Baseline comparison uses existing realistic runs (R=3) from the synthetic pipeline.
- ABC/screen budgets trimmed for this ceiling diagnostic (n_draws=2, n_sims=10) to keep runtime manageable; this is documented and does not change the direction of the comparison.

## Outputs
- `outputs/synthetic/ceiling_run_summary.csv`
- `outputs/synthetic/ceiling_run_replicates.csv`
- `outputs/synthetic/ceiling_param_recovery.csv`
- `outputs/synthetic/ceiling_recovery_compare.png`
- Maps: `outputs/synthetic/ceiling/TX_true_ceiling.png`, `TX_obs_ceiling.png`, `TX_best_ceiling.png`, `TX_diff_ceiling.png`
- Canonical: `outputs/canonical/0.3/WP-0.3.4.7/syn_20251231_201016_0099/`

## Key metrics (median across reps)
From `ceiling_run_summary.csv`:
- Baseline (R=3, realistic): ABC acceptance = 0; ABC summaries largely NA.
- Ceiling (R=10, realistic):
  - obs_coverage median ≈ 0.82
  - abc_r2_median ≈ 0.96
  - abc_coverage_median ≈ 0.82
  - coverage_curve_rmse_median ≈ 0.18

## Visual sanity checks
- Ceiling maps show spatially coherent TX_true/TX_obs and reasonable best/diff structure.
- TX maps are populated (non-empty); PNGs have rich color diversity.

## Interpretation
- Under high-information observations + full arrival coverage, recovery metrics improve dramatically.
- Baseline realism remains information-limited (near-zero ABC acceptance), reinforcing the need for the ceiling contrast.
- Graph-mode dispersal is now necessary for tractable ceiling diagnostics.
