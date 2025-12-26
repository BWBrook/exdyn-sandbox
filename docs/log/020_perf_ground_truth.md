# Phase 020 — Performance & scaling ground truth (WP‑0.2.x)

Date: 2025-12-19

## Scope
- Created a **toy performance profile** and profiling harness for the synthetic twin.
- Added **stage-level timing** + memory snapshots for smoke runs.
- Ran a **scaling sweep** across grid size × years × replicates with dispersal on/off.
- Added **optimization comparison** for fast observation TX mapping (matrix-based counts).

## What ran (artefacts)
- Smoke profile: `outputs/perf/profiling/toy_smoke/`
- Stage profile: `outputs/perf/profiling/stage_profile_smoke.csv`
- Scaling sweep: `outputs/perf/scaling/scaling_sweep.csv`
- Scaling plots: `outputs/perf/scaling/plots/`
- Optimisation compare: `outputs/perf/optimisation/optimisation_before_after.csv`

## Quick sanity outcomes
- Smoke TX_true map shows a coherent gradient (front advances across toy grid).
- TX_obs map shows expected thinning/noise vs TX_true, but preserves broad structure.
- Coverage now complete for TX_true in smoke (coverage=1.0), and partial for TX_obs.
- Early toy configs were too weak (degenerate TX_true); updated perf params to yield a usable front.

## Timing/memory highlights (smoke)
- Dominant stage in smoke is **observation_tx_map**, not the simulator core (but now faster).
- Peak RSS reported by `/proc/self/status` stays ~3.5 MB in this toy run
  (note: RSS estimates in this environment are likely under-reporting; treat as a lower bound).

## Optimisation note
- Optimised the observation TX mapping path (`exdyn_tx_map_fast`) using matrix-based counts.
- Before/after (3 reps, same seed) shows **~4.2× speedup** for TX mapping:
  - slow: ~7.07 s; fast: ~1.67 s (`outputs/perf/optimisation/optimisation_before_after.csv`).

## Next steps
- Review scaling plots for non‑linearities and confirm budgets still reasonable.
- Resume WP‑0.3.x using toy/medium profiles only until full GB run is budgeted.
