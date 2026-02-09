## Process model and extirpation timing

The simulation core is a streaming TX-only engine that avoids storing full
`N[x,y,t]` abundance cubes for large grids. Extirpation time is defined by a
first-passage rule, and this definition is shared between synthetic generation
and inference summaries.

Predator arrival is represented as a year surface `T_P(x)`. Predation intensity
ramps after arrival and combines with local growth and dispersal dynamics to
produce extirpation timing `TX(x)`.

## Observation layer and TX estimator

Synthetic realistic mode converts latent dynamics into observation-limited
signals and reconstructs `TX_obs` using the same first-passage estimator used in
real data. This creates a strict separation between:

- ideal identifiability (`TX_true`),
- realistic identifiability (`TX_obs`).

## Summary-based calibration (screen + ABC)

Inference uses response-oriented summary vectors describing coverage, lag,
geometry, and coverage curves. A screen stage filters parameter draws by loss
and compatibility criteria, then rejection ABC refines around shortlist regions.

## Quality gates and canonical discipline

Every major run is validated with explicit gates and packaged in canonical
artefact folders containing:

- `manifest.yaml` (schema version, commit SHA, config snapshots, seeds),
- rendered reports and primary tables/figures,
- session information.

These gates are treated as scientific safeguards, not only engineering checks.

