# Manuscript Package

This folder contains the manuscript scaffold and the figure/table manifest
linked to canonical artefacts.

## Files

- `mink_vole_manuscript.qmd`: primary manuscript source.
- `sections/`: section-level narrative text blocks.
- `figure_table_manifest.csv`: item-level mapping from manuscript artefacts to
  canonical output paths.

## Render

```bash
quarto render manuscript/mink_vole_manuscript.qmd
```

## Policy

Any manuscript claim that depends on generated output must reference a canonical
artefact path from `figure_table_manifest.csv`.

