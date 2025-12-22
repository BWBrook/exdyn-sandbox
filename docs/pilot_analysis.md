# Pilot WP‑0.3.5 analysis (coverage failure triage)

Date: 2025-12-21 (updated 2025-12-23)

## Summary of the pilot run
- **Run id:** `wp035_pilot_20251221_161039`
- **Settings:** reps=3, modes=ideal+realistic, screen draws=16, ABC n=500, LHS 32/16,
  counts mode, pilot grid/years, mask=riparian, crop=TRUE.
- **Wall time:** ~1:13:57
- **Peak RSS:** ~1.36 GB
- **Canonical:** `outputs/canonical/0.3/WP-0.3.5/wp035_pilot_20251221_161039/`
- **Perf logs:**
  - `outputs/perf/wp035_pilot_time.txt`
  - `outputs/perf/wp035_pilot_sizes.csv`

## Key symptom
- **TX_true / TX_obs maps are extremely sparse** on the pilot grid (almost no finite
  TX values). As a result:
  - coverage is near‑zero,
  - r2/lag summaries are NA,
  - recovery metrics are not informative.

This makes scaling to the full WP‑0.3.5 run pointless until coverage improves.

## Plausible causes (ranked)
1) **Arrival surface sparsity on pilot grid**
   - Pilot grid uses real mink arrival surface; many cells likely have NA arrival.
   - If T_P is NA for most cells, predation is never triggered → no extirpation.

2) **Mask and grid interaction**
   - `mask = riparian` + pilot grid may drastically reduce active cells.
   - Coverage is computed over mask; if only a tiny subset is active, summary
     stats become unstable or degenerate.

3) **Extirpation threshold too strict for pilot grid**
   - `truth_frac=0.12` and `truth_rel0=1.5` (from config) may be high relative
     to pilot grid dynamics, suppressing first‑passage events.

4) **Observation / TX estimator thresholds too strict**
   - `tx_cfg` parameters (min_years_active, baseline_window, hold_years,
     drop_fraction) may be too conservative for pilot‑grid counts,
     especially if counts are sparse.

5) **Weak predation / ramp timing**
   - Even with counts mode, predation intensity or ramp timing may delay
     extirpation beyond the pilot years, leaving TX undefined.

## Immediate diagnostic checks (low‑effort)
1) **T_P coverage:** fraction of finite arrivals on pilot grid.
2) **TX_true coverage:** fraction of finite TX_true (before observation).
3) **Counts intensity:** mean/median counts per cell‑year under the pilot settings.
4) **Sensitivity to mask:** rerun pilot with `mask = all` to test whether the
   riparian subset is too restrictive.
5) **Sensitivity to thresholds:** reduce `truth_frac`, `truth_rel0`, and/or relax
   `tx_cfg` (min_years_active, hold_years, drop_fraction) to see if coverage
   becomes non‑degenerate.

## Suggested next experiments (to restore coverage)
- **Synthetic arrival override on pilot grid** (e.g., gradient arrivals instead
  of the real GBIF arrival surface). This tests whether the arrival sparsity is
  the primary blocker.
- **Lower extirpation thresholds** (`truth_frac` → 0.02; `truth_rel0` → 0.5)
  to force first‑passage events earlier.
- **Increase predation strength** (pred_scale or pred_c) to drive extirpations
  within the pilot years.
- **Relax TX estimator thresholds** (min_years_active, baseline_window, hold_years)
  for pilot‑grid diagnostics only.

## Lean PI review bundle
The accompanying zip includes:
- key docs and logs,
- pilot run perf logs + canonical manifest,
- pilot recovery tables (mode‑specific),
- pilot TX maps (ideal/realistic),
- core synthetic pipeline code and configs.

This should be enough to diagnose the coverage issue without the full repo.

## Arrival diagnostics update (WP‑0.3.4.2)
Diagnostics now report finite arrival coverage by source (pilot grid, riparian mask):
- **real:** 12/19 finite (frac = 0.632)
- **synthetic_plane:** 19/19 finite (frac = 1.0)
- **synthetic_gradient:** 19/19 finite (frac = 1.0)

Artefacts:
- `outputs/synthetic/pilot_diagnostics.csv`
- `outputs/synthetic/arrival_real.png`
- `outputs/synthetic/arrival_synthetic_plane.png`
- `outputs/synthetic/arrival_synthetic_gradient.png`

## Truth viability update (WP‑0.3.4.3)
Viability sweep (pilot grid, arrival_source=synthetic_plane, mask=all) varied
`truth_frac`/`truth_rel0` at `pred_scale=3.0`, `pred_c=2.4`:
- `(0.12, 1.5–2.0)` → ~5 extirpations (coverage ~0.001)
- `(0.16, 1.8–2.0)` → **~90 extirpations** (coverage ~0.025)
- `(0.20, 1.8–2.0)` → full extirpation (coverage = 1)

Selected truth thresholds for the pilot synthetic:
- `truth_frac = 0.16`
- `truth_rel0 = 1.8`

Artefacts:
- `outputs/synthetic/viability_sweep.csv`
- `outputs/synthetic/viability_sweep_plot.png`

## Pilot gates pass (WP‑0.3.4.4, 2025‑12‑23)
Pilot recovery now passes all identifiability gates for **both** modes using:
- **Coverage breaks:** TX‑quantile breaks (`coverage_breaks.strategy = "tx_quantile"`).
- **Mode‑specific ABC eps:** `realistic=15`, `ideal=23` (acceptance 2/20 in each).
- **Observation/compat tuning:** `po_rate=0.01`, `drop_fraction=0.3`,
  `normalize_by="none"`, `min_r2_arrival=0`, `lag_range=[0,40]`.

Gate results (pilot grid, mask=all, arrival_source=synthetic_plane):
- **Realistic:** G1–G5 all pass (coverage_obs ≈ 0.835; n_TX_obs=3058).
- **Ideal:** G1–G5 all pass (coverage_true ≈ 0.289; n_TX_true=1058).

Key artefacts:
- `outputs/synthetic/recovery/pilot_gates.csv`
- `outputs/synthetic/recovery/realistic/replicate_metrics.csv`
- `outputs/synthetic/recovery/ideal/replicate_metrics.csv`

## Pilot viability update (predation strength sweep)
Using `truth_frac=0.02`, `truth_rel0=0.5` and varying predation strength:
- `pred_scale=0.6`, `pred_c=0.6` → coverage ≈ 0.289 (n_TX_true ≈ 1058)
- `pred_scale=1.2`, `pred_c=0.6` → coverage = 1 (saturated)
- `pred_scale≤0.6`, `pred_c=0.3` → zero extirpations

Selected pilot theta_star update:
- `pred_scale = 0.6`, `pred_c = 0.6`
- `truth_frac = 0.02`, `truth_rel0 = 0.5`

Artefacts:
- `outputs/synthetic/viability_sweep.csv`
- `outputs/synthetic/viability_sweep_plot.png`
