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
