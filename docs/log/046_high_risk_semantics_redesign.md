# 046 — High-Risk Semantics Redesign

Date: 2026-03-08

## What changed

- Made synthetic benchmark semantics config-authoritative:
  - `benchmark.core_params` now controls overall benchmark pass/fail.
  - `benchmark.stance`, `weak_id_parameters`, and gate thresholds are resolved explicitly from config.
  - Added per-mode `benchmark_summary.csv` output and manifest provenance for benchmark/gate settings.
- Redesigned synthetic ABC missing-summary handling:
  - required summary metrics must remain finite,
  - optional missing metrics incur an explicit additive penalty,
  - per-draw diagnostics now record `distance_core`, `distance_optional_penalty`, and validity flags.
- Replaced the mixed-scale real-data loss with a unit-consistent loss:
  - build one canonical unit timing table from `T_P`, `TX_obs`, and `TX_sim`,
  - aggregate unit timing with median finite cell timing,
  - compute coverage, lag, arrival fit, coverage curves, and anisotropy from that table only.
- Added explicit TX threshold semantics:
  - `threshold_mode = auto | count_floor | relative_baseline`,
  - `auto` resolves to `count_floor` for raw series and `relative_baseline` for normalized series,
  - `baseline`, `tau`, `threshold_mode`, and `reason` now survive into exported tables/QC outputs.

## Sanity checks

- Focused tests passed after each slice:
  - synthetic semantics + ABC: `PASS 33`
  - real loss + threshold plumbing: `PASS 55`
- Added/updated characterization tests for:
  - benchmark summary and weak-ID status,
  - ABC required-vs-optional missing metrics,
  - pilot gate threshold overrides,
  - median unit aggregation and centroid-sensitive real-loss geometry,
  - threshold-mode semantics in TX estimation,
  - fast/slow TX-map parity for threshold metadata.

## Interpretation

- This is a deliberate semantic break, not just cleanup; historical outputs under schema `0.3.3` should be treated as legacy.
- The real-data pilot now reports simulated compatibility metrics with a coherent unit definition, so draw ranking should be more interpretable.
- The synthetic benchmark is now easier to audit because benchmark pass/fail no longer depends on hidden fallback logic.

## Next follow-up

- Run full `make test`.
- Render synthetic and pilot reports against the new semantics.
- Decide whether to regenerate smoke/canonical artefacts under schema `0.4.0`.
