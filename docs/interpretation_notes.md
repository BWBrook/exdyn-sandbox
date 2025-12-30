# Interpretation notes (lab notebook)

This file is a running “what the results are actually saying” notebook.
Write in blunt bullets. This is where we catch ourselves rationalising noise.

---

## A) Synthetic mink→vole twin (Phase 010 target)

### Current inherited observation (from existing runs/logs/reports)
- The synthetic twin pipeline can produce strong single-run recovery:
  - spatial agreement reported around R² ≈ 0.8+
  - positive lag of several years
  - coverage curves can be matched well after ABC refinement
- This is encouraging but not yet a benchmark:
  - a single success can be a lucky draw
  - we don’t yet have replicated recovery, bias, or interval coverage

### What “success” must look like (benchmark criteria)
- Replicated synthetic datasets (>=10) show:
  - stable posterior predictive fit (geometry + coverage curve) across replicates
  - quantified bias and uncertainty per parameter
  - honest “weakly identified” flags for parameters that don’t recover

### Likely weak points to watch
- Dispersal vs predation scale tradeoffs (classic confounding).
- δ offsets flattening structure if too flexible.
- Summary vector scaling choices dominating ABC distance (must be justified).

### Performance & scaling notes (Phase 020)
- Perf smoke: TX_true shows a clean gradient front on the toy grid; TX_obs preserves that ordering while thinning coverage (observation/first‑passage noise behaves as expected).
- Perf smoke: observation/TX estimator is the dominant wall‑time cost at toy scale; core TX‑only simulation is comparatively cheap.
- Scaling sweep: wall time grows with years and grid size; dispersal adds overhead but does not dominate at toy scales.
- Scaling sweep: peak RSS appears unrealistically low in this environment; treat memory numbers as lower bounds only.
- Optimisation: fast TX mapping reduces observation-stage runtime by ~4.2× (7.07 s → 1.67 s in toy bench); fast/slow paths match outputs in tests.
- Toy perf params were strengthened after an early degenerate TX_true map; current smoke artefacts show coherent fronts.
- GB preflight (realistic, 1 rep) is heavy: ~43.5 min wall time and ~42 GB RSS; observation pipeline is the practical bottleneck at scale.

### Synthetic benchmark notes (Phase 030)
- Toy canonical runs show coherent TX_true fronts and noisy TX_obs maps; spatial ordering preserved across modes.
- Replicated recovery (R=10) required a much larger ABC eps in toy mode; current scale settings are too tight for toy summaries.
- Parameter recovery tables populate as expected once acceptance exists; shrinkage ratios highlight weakly identified deltas even on toy.
- Realistic-mode acceptance tends to produce near‑full coverage in toy runs; watch for scale‑dependent saturation.
- Streaming counts‑mode truth generation removes 3‑D N/P arrays without changing TX_obs; this is a safe win.
- GB counts preflight fell from ~5.2 min / 6.35 GB to ~42.5 s / 1.0 GB; the observation pipeline is no longer the dominant sink.
- Summary/score hot‑path changes (vectorised orientation, analytic r²) did not alter outputs on toy tests; these should be treated as performance‑only edits.
- Remaining runtime risk now sits in full pipeline stages (screen/ABC/report), not the core sim or counts observation.
- New preflight numbers imply WP‑0.3.5 is feasible only if screen/ABC costs are managed; we still need a full‑pipeline counts preflight.
- Full‑pipeline counts preflight (pilot grid + crop) runs in ~3 minutes with ~1.2 GB RSS; TX maps are extremely sparse under toy θ* on pilot grid, so treat as **performance‑only** evidence.
- WP‑0.3.5 pilot run (3 reps, counts, pilot grid) confirms end‑to‑end runtime is ~1h14m with ~1.3 GB RSS, but **coverage is near‑zero** and r2/lag metrics are NA; we need non‑degenerate TX coverage for the full benchmark.
- Mask‑consistent summaries now report `n_mask`, `n_TP_finite`, and `n_pairs`; coverage equals `n_pairs / n_TP_finite` in smoke outputs, eliminating denominator mismatch as a failure mode.
- Pilot arrival diagnostics show real arrivals are sparse within the riparian mask (12/19 cells finite), while synthetic plane/gradient overrides give full coverage; arrival sparsity is a plausible driver of pilot coverage failure.
- Viability sweep on the pilot grid shows extirpation thresholds dominate coverage; selected `truth_frac=0.16`, `truth_rel0=1.8` to clear `n_TX_true ≥ 50` without saturating coverage.
- Updated pilot viability sweep (mask=land, arrival_source=synthetic_plane) shows predation strength dominates coverage; selected `pred_scale=0.6`, `pred_c=0.6` with default truth thresholds to avoid saturation.
- Pilot gates now pass for **both** modes after switching to TX‑quantile coverage breaks and mode‑specific ABC eps; this confirms the pilot grid is now informative enough to proceed.
- Coverage‑curve information was previously degenerate because TX_true fell late in the timeline; quantile breaks fix this without changing the rest of the summary vector.
- ABC acceptance is highly sensitive to eps; requiring mode‑specific eps underscores different distance scales between ideal and realistic summaries.
- Realistic TX_obs coverage is now high (~0.83) with the pilot observation tuning; this is useful for identifiability but could be overly optimistic if carried to full GB runs.
- Accepted ABC samples show very high r²/coverage medians (near 1); this may be an artefact of loose thresholds and should be watched in WP‑0.3.5.
- Screen best r² in realistic mode remains very low (~0.01), suggesting arrival‑alignment geometry is still weak despite passing gates.
- Arrival realism gate shows **real arrival coverage ≈0.41** within the mask vs **≈1.0** for synthetic‑plane arrivals on the pilot grid.
- With real arrivals, `n_TX_true` and `n_pairs` drop by ~2× relative to synthetic‑plane, and recovery coverage weakens (coverage_80 ~0.33–0.75).
- Summary finiteness remains stable (~0.79), indicating the **information deficit is spatial coverage**, not summary computation failure.
- Real‑arrival sparsity must be treated as a **data limitation** when interpreting real‑data inference; otherwise we risk attributing failure to the model.

---

## B) Real mink→vole (Phase 020 target)

### Current inherited observation
- At segment-level units, the data representation appears severely underpowered (very few usable units/extirpations).
- When δ is too free, it can “solve everything” by pulling arrivals early and erasing spatial gradients, which kills identifiability.

### Interpretation stance (non-negotiable)
- If the best representation still fails gates without absurd δ, we treat it as evidence:
  - either data are too low SNR at this resolution
  - or predation-only is missing key mechanisms (habitat change, other pressures)
  - or both

---

## C) Iteration queue (keep updated)

### Synthetic twin
- [ ] Implement ideal vs realistic modes (TX_true vs TX_obs inference).
- [ ] Add replicated recovery and compute bias/coverage metrics.
- [ ] Re-evaluate summary vector composition and scaling using recovery evidence.

### Real case
- [ ] Representation selection: choose units/resolution to meet minimum TX_obs unit count.
- [ ] Re-run constrained fits with δ regularisation and mild random effects.
- [ ] Decide whether to add habitat term if predation-only fails gates.

---

## D) Notes to self (don’t get fooled)
- Pretty maps are not evidence.
- If the synthetic benchmark is not locked down, interpretation of real-data fits is not credible.
- Failure to fit real data is a result if we can rule out algorithmic incompetence via the synthetic benchmark.
