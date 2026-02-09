# WP-0.5.x Manuscript package and reproducibility freeze (WP-0.5.1 to WP-0.5.5)

Date: 2026-02-09

## Scope completed

- WP-0.5.1 — manuscript scaffold + manifest
- WP-0.5.2 — methods text drafted from implemented workflow
- WP-0.5.3 — synthetic results narrative linked to canonical artefacts
- WP-0.5.4 — real results narrative linked to canonical artefacts
- WP-0.5.5 — reproducibility checklist + render/test verification

## Manuscript scaffold and content

Created/updated:

- `manuscript/mink_vole_manuscript.qmd`
- `manuscript/sections/00_abstract.md`
- `manuscript/sections/01_introduction.md`
- `manuscript/sections/02_methods.md`
- `manuscript/sections/03_results_synthetic.md`
- `manuscript/sections/04_results_real.md`
- `manuscript/sections/05_discussion.md`
- `manuscript/sections/06_reproducibility.md`
- `manuscript/figure_table_manifest.csv`
- `manuscript/reproducibility_freeze.md`
- `manuscript/README.md`

## Canonical linkage checks

- Synthetic items linked to:
  - `outputs/canonical/0.3/WP-0.3.5b/syn_20260209_134622_035b_full_r20/`
  - `outputs/canonical/0.3/WP-0.3.6/syn_20260209_154821_0099/`
- Real items linked to:
  - `outputs/canonical/0.4/WP-0.4.3/real_20260209_171134_7350/`

All manifest rows are now `status = locked` (no remaining
`pending_real_canonical` placeholders).

## Reproducibility checks run

- `make test`
- `make manuscript`

Both commands completed successfully in the current environment.

## Interpretation notes carried into manuscript

- Synthetic benchmark remains useful for calibrated weak-ID interpretation.
- Stress sweep explicitly maps identifiability failure regimes.
- Real-case run is presented as a quantified negative result with gate evidence,
  not over-claimed as explanatory success.

## Handoff status

Manuscript package is now execution-linked to canonical outputs and can be
rendered end-to-end from the repository.
