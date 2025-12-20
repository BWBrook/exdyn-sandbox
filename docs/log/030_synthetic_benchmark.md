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
  - `outputs/perf/preflight_medium_time.txt`
  - `outputs/perf/preflight_medium_summary.csv`
- GB realistic preflight (pilot grid, 1 replicate, minimal ABC):
  - wall time ≈ **43:30** (≈2610.6 s), max RSS ≈ **43,677,192 kB**.
  - `outputs/perf/preflight_gb_time.txt`
  - `outputs/perf/preflight_gb_summary.csv`
  - Metrics recorded in the canonical manifest for WP‑0.3.4b.

## Sanity checks (artefact review)
- Reviewed TX_true/TX_obs/TX_best maps (toy canonical runs): coherent front gradients, non‑blank, spatial ordering preserved.
- Recovery tables present for WP‑0.3.3 with non‑zero acceptance and parameter summaries.
- GB preflight generated TX maps and report; no 3‑D `N[x,y,t]` arrays written to canonical outputs.

## Notes & issues
- ABC acceptance was initially zero with tight scaling; raised `ABC_EPS` for toy recovery to produce accepted draws (see WP‑0.3.3 manifest). This is a toy‑run scaling issue to revisit for full benchmark.
- ABC distance now ignores non-finite summary components (e.g., orientation on tiny grids) to avoid zero-acceptance in small smoke tests.
- GB preflight confirms observation pipeline dominates runtime/memory; WP‑0.3.5 needs batching/HPC or further optimisation.

## Next steps
- Use WP‑0.3.4b budgets to gate WP‑0.3.5.
- Revisit summary scaling before full benchmark (to avoid extreme eps values).
