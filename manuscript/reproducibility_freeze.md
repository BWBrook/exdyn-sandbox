# Reproducibility Freeze Checklist (WP-0.5.5)

Date: 2026-02-09

## Environment and code

- [x] `git status` clean (except intentionally ignored runtime artefacts).
- [x] `renv.lock` reflects current package state.
- [x] `make test` passes.

## Synthetic benchmark artefacts

- [x] Canonical `WP-0.3.5a` bundle exists and includes report + manifest.
- [x] Canonical `WP-0.3.5b` bundle exists and includes report + manifest.
- [x] Canonical `WP-0.3.6` stress bundle exists and includes stress tables/plot.

## Real-data case-study artefacts

- [x] Canonical `WP-0.4.3` bundle exists and includes:
  - [x] pilot report HTML/PDF
  - [x] information/representation audits
  - [x] ablation outputs
  - [x] posterior predictive outputs
  - [x] gate evaluation tables

## Manuscript linkage

- [x] `manuscript/figure_table_manifest.csv` canonical paths resolve.
- [x] `quarto render manuscript/mink_vole_manuscript.qmd` succeeds for HTML.
- [x] `quarto render manuscript/mink_vole_manuscript.qmd` succeeds for PDF.

## Archive and handoff

- [x] `docs/log/` entries updated for all completed WPs.
- [x] `docs/interpretation_notes.md` includes synthetic and real verdict bullets.
- [x] `docs/plan.md` next-step queue reflects current truth.
- [ ] Final commit message and SHA recorded in roadmap completion records.
