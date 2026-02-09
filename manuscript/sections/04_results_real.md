## Real-data information audit and representation triage

The real-data workflow begins with an information audit (`WP-0.4.0`) and
representation audit (`WP-0.4.1`) before full constrained inference. This
prevents over-interpreting runs with inadequate overlap between reconstructed
`TX_obs` and finite predator-arrival support.

For the selected representation (`grid_all`), the audit indicates:

- `n_units = 3621`
- `n_TX_obs = 569` (`coverage_obs ≈ 0.157`)
- `n_TP_finite = 7`
- `n_pairs = 1` (`TX_obs` and `T_P` jointly finite)

So the unit-count gate passes, but arrival/response overlap is extremely sparse.

## Constrained inference and ablation

The constrained real run (`WP-0.4.3`) combines screen, ABC, and posterior
predictive checks, with ablation diagnostics (`WP-0.4.2`) used to decide
whether optional random-effects structure materially improves fit.

The ablation showed no practical gain from adding `pred_scale` random effects:
both `delta_only` and `delta_plus_re` produced zero compatible draws at the
tested budget, with near-identical median loss and coverage.

## Case-study verdict

Gate outcomes for the constrained run were uniformly negative (`best_r2 = NA`,
`best_lag = NA`, `best_coverage ≈ 2.8e-4`, `abc_accept_rate = 0`), and no ABC
posterior was retained under the configured thresholds.

The corresponding verdict is therefore **data-limited/mechanism-incomplete at
this representation**, not a positive confirmation of predation-only
sufficiency. This negative result is still informative because it is grounded in
explicit audits, gates, and canonical artefacts rather than post hoc
rationalisation.
