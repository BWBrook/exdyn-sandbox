## Synthetic benchmark lock-down

The synthetic benchmark was completed in two canonical stages:

- pilot-grid benchmark (`WP-0.3.5a`),
- GB-grid benchmark (`WP-0.3.5b`, graph mode).

Both runs include ideal and realistic modes with replicated recovery metrics and
posterior predictive checks.

The GB-scale canonical run (`WP-0.3.5b`) passed all configured benchmark gates
across replicates (`G1`–`G5`). In realistic mode, predictive summaries remained
above gate thresholds, while core front parameters (`alpha`, `disp_mean_km`)
were retained as weakly identifiable under the declared benchmark stance.

## Stress regimes and identifiability limits

`WP-0.3.6` adds a compact stress grid over arrival realism, observation
intensity, and predation strength multipliers. The resulting heatmap and gate
tables identify where recovery collapses, with failures concentrated in arrival
coverage and screen/ABC compatibility gates.

The stress sweep showed a sharp regime split: scenarios using `arrival_source =
real` failed all-gate criteria (pass rate 0), while `arrival_source =
synthetic_plane` with moderate observation intensity remained identifiable.
This provides an explicit “information-limited failure map” for interpreting
real-data outcomes.

## Synthetic interpretation stance

The synthetic package is used as an identifiability map: it distinguishes
recoverable from weakly identified parameters and sets expectations for
real-data transfer under sparse arrival coverage.
