## Canonical artefact policy

Primary manuscript claims must link to canonical bundles under
`outputs/canonical/`, with run manifests carrying commit SHA, configuration
snapshots, and seeds.

For this draft, synthetic claims are pinned to:

- `outputs/canonical/0.3/WP-0.3.5b/syn_20260209_134622_035b_full_r20/`
- `outputs/canonical/0.3/WP-0.3.6/syn_20260209_154821_0099/`

Real-case claims are pinned to:

- `outputs/canonical/0.4/WP-0.4.3/real_20260209_171134_7350/`

## Build commands

- Synthetic benchmark/report: `make synthetic`
- Real pilot/report: `make pilot`
- Test suite: `make test`
- Manuscript render: `quarto render manuscript/mink_vole_manuscript.qmd`

## Figure and table manifest

See `manuscript/figure_table_manifest.csv` for explicit pointers from manuscript
items to canonical artefacts.

## Freeze checklist

Release-freeze and handoff checks are tracked in
`manuscript/reproducibility_freeze.md`.
