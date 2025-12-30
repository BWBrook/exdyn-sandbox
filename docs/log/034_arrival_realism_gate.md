# WP‑0.3.4.5 — Arrival realism gate (real vs synthetic-plane)

**Date:** 2025-12-30

## What ran
- Target: `synthetic_arrival_realism_comparison_csv`
- Canonical run: `outputs/canonical/0.3/WP-0.3.4.5/syn_20251230_153246_0099/`
- Grid: pilot (GB/IE)
- Arrival sources: `real` vs `synthetic_plane`
- Reps: 10 per source
- Modes: `ideal`, `realistic`
- Dispersal: graph mode (land‑cell graph, radius 5)

## Key artefacts
- `outputs/synthetic/arrival_realism_comparison.csv`
- `outputs/synthetic/arrival_real.png`
- `outputs/synthetic/arrival_synthetic_plane.png`
- `outputs/synthetic/arrival_synthetic_gradient.png`

## Sanity inspection
- **Arrival coverage (real):** `frac_finite_TP_in_mask ≈ 0.407` (sparse).
- **Arrival coverage (synthetic_plane):** `≈ 1.0` (complete).
- **TX_true counts:**
  - Real arrival: mean `n_TX_true ≈ 530` (ideal), `n_pairs ≈ 525`.
  - Synthetic plane: mean `n_TX_true ≈ 1215` (ideal), `n_pairs ≈ 1215`.
- **Summary finiteness:** stable at ~0.786 across all runs; no NA collapse.
- **Parameter recovery:**
  - Real arrival: modest coverage (coverage_80 ~0.33–0.75).
  - Synthetic plane: higher and more stable coverage (coverage_80 ~0.58 in realistic mode), but ideal mode shows low coverage on some parameters (0.0 in the current sample), indicating remaining identifiability limits.

## Interpretation
- Real arrival sparsity materially reduces identifiability and should be treated as a **hard data limitation**, not an algorithmic failure.
- Synthetic‑plane arrivals serve as the “information‑complete” baseline; the gap to real arrivals quantifies how much information is missing.

## Warnings / issues
- Repeated many‑to‑many join warnings from arrival plotting (row 1444) still present.
- Recorded in WP‑0.3.4.8 as hygiene fix.

## Gate status
- **WP‑0.3.4.5** acceptance criteria satisfied: comparison table produced; arrival coverage and recovery metrics logged; canonical run saved.

