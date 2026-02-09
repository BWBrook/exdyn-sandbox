# WP-0.3.4.6 — Masking philosophy gate (hard vs soft)

Date: 2025-12-30

## What ran
- Target: `synthetic_mask_philosophy_outputs` (pilot grid; dispersal_mode=graph).
- Note: the pilot grid is the GB+IE 10 km domain, so this comparison also serves as the GB sanity run.
- Config: `mask_philosophy` enabled, arrival_source = `synthetic_gradient`, reps = 3 (chosen for visual sanity).
- Hard mask = riparian binary mask (`mask_philosophy.hard_mask = riparian`).
- Soft mask = land mask + suitability scaling from `river_km` (range 0.5–1.5, log1p).
- Global synthetic config now uses `mask = all` with `suitability.enabled = true` so the\n  pipeline adopts soft weighting beyond this gate.
- Years: 1980–2005.

## Outputs
- `outputs/synthetic/mask_philosophy_compare.csv`
- `outputs/synthetic/TX_true_hard_mask.png`
- `outputs/synthetic/TX_true_soft_mask.png`
- `outputs/synthetic/suitability_scale_soft.png`
- `outputs/synthetic/mask_cells_hard.png`
- `outputs/synthetic/arrival_plane_mask_philosophy.png`
- Canonical (smoke): `outputs/canonical/0.3/WP-0.3.4.6/syn_20251230_174534_0099/`\n  (smoke settings, viability/arrival-realism disabled for runtime)

## Key metrics (mean over reps)
- Hard mask:
  - n_mask = 19, n_TP_finite = 19
  - n_TX_true = 0, coverage_true = 0
  - geometry summaries NA (no informative extirpation pattern)
- Soft suitability:
  - n_mask = 3664, n_TP_finite = 3664
  - n_TX_true ≈ 1215, coverage_true ≈ 0.332
  - lag_mean ≈ 17.5 years, r2_arrival ≈ 0.99
  - summary_finite_rate ≈ 0.71
  - scale range = [0.5, 1.5], mean ≈ 0.51

## Sanity checks
- Visual: hard mask TX_true plot shows effectively no extirpations.
- Visual: soft mask TX_true plot shows spatially coherent extirpation wave.
- Warning: repeated many-to-many join warnings during run (likely from spatial join in arrivals); no downstream failure but flagged for later cleanup.

## Interpretation
- The hard riparian mask is far too restrictive at 10 km resolution (only 19 active cells), yielding degenerate TX_true and non-informative summaries.
- Soft suitability weighting yields an informative extirpation pattern and finite geometry summaries under the same theta_star.\n+- Switched arrival source to synthetic_gradient for clearer visual inspection; the masking decision is unchanged.
- This supports switching to soft suitability weighting for subsequent synthetic and pilot runs.
