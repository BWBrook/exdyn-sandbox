# WP-0.3.4.8 — Pipeline hygiene (join warning + freshness guardrails)

Date: 2025-12-31

## What changed
- Deduplicated arrival tables by `cell_id` in `exdyn_prepare_arrivals()` using earliest arrival year.
- Added output freshness guardrails (`exdyn_freshness_guard`) and a synthetic target to enforce that arrival plots/viability plots are newer than the config snapshot.
- Added unit test for freshness guard.

## Evidence
- Many-to-many join warning eliminated by construction (arrival table now unique per cell).
- `synthetic_freshness_guard` now runs in the synthetic pipeline and will fail if stale outputs exist.

## Notes
- Guardrail uses file modification times; any manual edits to outputs will be caught if they precede config edits.
