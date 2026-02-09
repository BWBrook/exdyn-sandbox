# WP-0.3.6 — Synthetic identifiability stress mini-sweep

Date: 2026-02-09

## Scope
- Completed the WP-0.3.6 stress mini-sweep over:
  - `arrival_source`: `real`, `synthetic_plane`
  - `obs_multiplier`: `0.5`, `1.5` (applied to `noise.po_rate`)
  - `pred_scale_multiplier`: `0.7`, `1.0`, `1.3` (applied to `theta_star.pred_scale`)
- Replicates per scenario: `R=10` (12 scenarios, 120 replicate runs).

## Artefacts
- Stress tables and plot:
  - `outputs/synthetic/stress/scenario_table.csv`
  - `outputs/synthetic/stress/gate_table.csv`
  - `outputs/synthetic/stress/gate_pass_rates.csv`
  - `outputs/synthetic/stress/scenario_pass_rates.csv`
  - `outputs/synthetic/stress/replicate_metrics.csv`
  - `outputs/synthetic/stress/failure_regimes_heatmap.png`
- Canonical bundle:
  - `outputs/canonical/0.3/WP-0.3.6/syn_20260209_154821_0099/`

## Sanity checks
- Structural checks:
  - 12 scenarios present, 120 replicate metric rows present.
  - Gate table includes all expected gates (`G1`–`G5`).
- Numerical checks:
  - `G2_TX_true`, `G3_TX_obs`, and `G4_cov_curve` pass-rates are stable (all 1.0 in this sweep).
  - `G1_arrival` and `G5_screen_abc` are the failure-driving gates (vary from 0 to 1).
  - Scenario all-gate pass-rates span `[0, 1]` with clear regime separation.
- Visual checks:
  - `failure_regimes_heatmap.png` is populated and non-empty.

## Interpretation
- Arrival-surface realism is the dominant identifiability stressor:
  - all `arrival_source=real` scenarios have all-gate pass-rate `0.0`.
- Under `arrival_source=synthetic_plane`:
  - low observation intensity (`obs_multiplier=0.5`) passes strongly (`0.9` to `1.0`),
  - high observation intensity (`obs_multiplier=1.5`) fails (`0.0`) under this configuration due to screen/ABC gate behavior.
- This sweep provides an explicit failure-regime map: gate collapse is not random and is attributable to identifiable information axes.

## Follow-up queue
- Carry stress-regime interpretation into the synthetic report narrative as the bridge to real-data limits.
- Keep `G1`/`G5` diagnostics prominent in future synthetic stress extensions.

