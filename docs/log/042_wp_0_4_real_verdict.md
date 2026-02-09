# WP-0.4.x Real-data verdict bundle (WP-0.4.0 to WP-0.4.4)

Date: 2026-02-09

## Scope completed

- WP-0.4.0 — information audit gate
- WP-0.4.1 — representation audit + selection
- WP-0.4.2 — delta vs delta+RE ablation
- WP-0.4.3 — constrained screen + ABC + PPC + canonical package
- WP-0.4.4 — verdict write-up in report/docs

## Commands executed

- `EXDYN_ABLATION_CORES=2 EXDYN_ABLATION_DRAWS=20 make pilot`
- Re-render retries after report hardening (same command) to complete
  `pilot_report_html`, `pilot_report_pdf`, and canonical packaging.
- `R --vanilla -e 'source("renv/activate.R"); targets::tar_make(names=c("pilot_canonical_manifest"))'`
  to refresh manifest after final output list/path fixes.

## Runtime/resource summary

- Full constrained `make pilot` pass (with bounded budgets) completed in about
  **1h19m** wall time.
- Longest stages were `pilot_draw_result` (~30 min), ablation (~14 min), and
  `pilot_abc_stage1` (~19 min).
- Observed memory remained stable during monitoring (single heavy worker;
  no swap pressure, no runaway growth).

## Key outputs and sanity checks

### Information and representation audits

- `outputs/realdata/information_audit.csv`
  - `n_units = 3621`, `n_TX_obs = 569`, `coverage_obs ≈ 0.157`
  - `n_TP_finite = 7`, `n_pairs = 1`
- `outputs/realdata/representation_audit.csv`
  - `grid_all` selected (`preferred = TRUE`, meets gate by unit count).
  - `grid_riparian` and `segment` fail minimum unit gate.

Interpretation: the case has enough response units but almost no overlap between
finite arrival and observed TX, so inferential signal is highly constrained.

### Ablation (delta-only vs delta+RE)

- `outputs/realdata/pilot_mink_vole/ablation_delta_re.csv`
- `outputs/realdata/pilot_mink_vole/ablation_delta_re_summary.csv`
- `outputs/realdata/pilot_mink_vole/ablation_delta_re.png`

Findings:

- Both variants produced `compatible_rate = 0` at the tested budget.
- Median losses were near-identical (`~0.977`).
- No evidence that adding RE improves fit under current information constraints.

### Constrained run + PPC

- `outputs/realdata/pilot_mink_vole/compatibility_ranked_riparian.csv`
- `outputs/realdata/pilot_mink_vole/gate_evaluation.csv`
- `outputs/realdata/pilot_mink_vole/posterior_metrics.csv`
- `outputs/realdata/pilot_mink_vole/posterior_predictive_coverage.csv`
- `outputs/realdata/pilot_mink_vole/posterior_predictive_coverage.png`
- `outputs/realdata/pilot_mink_vole/posterior_predictive_summaries.csv`
- `reports/pilot_mink_vole.html`, `reports/pilot_mink_vole.pdf`

Gate outcomes:

- `best_r2`: NA (FAIL)
- `best_lag`: NA (FAIL)
- `best_coverage`: `2.76e-4` vs threshold `>=0.15` (FAIL)
- `abc_accept_rate`: `0` (FAIL)

PPC note:

- No accepted ABC draws; pipeline now writes explicit placeholder PPC outputs
  instead of silently omitting files.

### Visual artefact review (manual sanity)

- `TX_obs_riparian_map.png`: broad but sparse observed TX distribution across GB/IE.
- `TX_sim_rank01.png`: extremely sparse simulated extirpations (few cells).
- `posterior_predictive_coverage.png`: clear "no accepted ABC draws" diagnostic panel.

Interpretation: visual diagnostics are consistent with the gate table and
support a data-limited verdict at this representation.

## Canonical package

- `outputs/canonical/0.4/WP-0.4.3/real_20260209_171134_7350/`

Contains:

- report HTML/PDF
- config snapshot + session info + manifest
- audit tables, ablation outputs, gate outputs, PPC outputs, and map tables

## Pipeline robustness fixes completed during this WP block

- Report setup now uses safe target reads for optional triage targets.
- Type-stable joins in report (`cell_id` coerced consistently).
- Report mask-map chunk handles empty mask sweep gracefully.
- `pilot_report_html` and `pilot_report_pdf` return explicit `reports/...` paths
  so canonical copying is reliable.
- PPC writer always emits coverage/summaries/plot even when ABC accepts zero draws.

## Verdict

Predation-only constrained inference does not pass real-data gates at the
selected representation. Result is treated as data-limited and/or
mechanism-incomplete, not as evidence of successful explanatory sufficiency.
