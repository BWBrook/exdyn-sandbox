# Roadmap suggestions (critical appraisal) — 30 Jan 2025

## 1) Where the roadmap is strong
- The 0.2.x performance ladder and 0.3.x synthetic gates have been essential. We now have real profiling evidence and explicit identifiability criteria before costly runs.
- The milestone gating approach (pilot → medium → GB) prevents long, ambiguous runs and keeps inference honest.
- The current WP‑DoD enforces artefact review and interpretation notes; this is good science hygiene.

## 2) Current bottlenecks and risks (and why they matter)

### A) Identifiability under sparse information
Even with fast simulation, inference fails if TX_true/TX_obs are sparse or if observation information collapses (NA/zero summaries). This is not a compute problem; it’s an information problem.

**Symptoms observed:**
- `n_TX_true` can be zero under weak predation.
- TX_obs can be populated even when TX_true is empty (observation model artefact), which misleads screens/ABC.
- coverage metrics can be trivially low/high depending on arrival sparsity and masking.

**Risk:** We could spend days on GB‑scale runs that are intrinsically unidentifiable, producing a false sense of “model failure” when it’s actually “data inadequacy”.

### B) Arrival surface sparsity (real data) vs synthetic overrides
Pilot runs using real arrival surfaces can have large NA regions; predation never “turns on” there, and extirpation never happens. Synthetic arrival overrides (plane/gradient) fix this for debugging, but may inflate identifiability relative to real data.

**Risk:** The synthetic benchmark might overstate recoverability if the real arrival surface is too sparse.

### C) Resolution vs ecology mismatch
At 10 km resolution, “riparian‑only” binary masks can artificially block spread; the true ecology is better approximated by a continuous suitability surface.

**Risk:** Hard 0/1 masks can create artificially isolated cells and distort dynamics, both in synthetic and real data.

### D) Residual pipeline fragility
- Many‑to‑many join warning remains; could be harmless or a duplication bug in arrivals/lookup joins.
- Some outputs (e.g., viability sweep CSV) can be stale unless rebuilt; the guardrails should ensure output freshness.

## 3) Suggested roadmap revisions (concrete)

### Add a short “0.3.4.x+” mini‑block before WP‑0.3.5 (LARGE)
Purpose: ensure synthetic identifiability is robust *under realistic arrival surfaces* and that graph mode is canonical.

**Proposed WPs:**
1. **WP‑0.3.4.5 — Arrival surface realism gate**
   - Require `frac_finite_TP >= 0.9` within mask *or* formally document how we impute/smooth arrival (plane/gradient) for pilot synthetic.
   - Compare synthetic recovery using (a) plane/gradient arrival vs (b) real arrival.
   - Gate: if real arrival yields degenerate TX_true while plane works, proceed only after documenting the mismatch and its implications.

2. **WP‑0.3.4.6 — Soft mask / suitability surface trial**
   - Replace binary riparian mask with a continuous suitability bias (e.g., weighted scale_matrix). This is closer to ecology and reduces artificial isolation.
   - Compare identifiability metrics under binary vs soft mask.

3. **WP‑0.3.4.7 — Data‑rich synthetic stress test**
   - Run a synthetic mode with intentionally richer observations (higher po_rate, lower dropout) to create a “best possible” identifiability bound.
   - This gives a ceiling on what inference *could* do with high information content.

These are light‑weight and would solidify confidence before running the large GB benchmark.

### Re‑scope WP‑0.3.5 (LARGE) into staged sub‑runs
Instead of one monolithic GB run:
- **WP‑0.3.5a (pilot‑scale canonical)**: Graph mode + synthetic_plane arrival + tuned theta_star, R≥20. Purpose: lock identifiability with known‑good information.
- **WP‑0.3.5b (GB‑scale canonical)**: Graph mode + real arrival surface + tuned theta_star. Purpose: realistic recoverability.

This keeps the benchmark honest and interpretable.

### Introduce a “Real‑data readiness gate” before WP‑0.4.x
Add a pre‑real‑data WP to quantify whether the real dataset even meets minimum information thresholds.

**Suggested WP‑0.4.0 — Real data information audit:**
- Count usable TX_obs cells after effort normalisation.
- Quantify arrival coverage (finite T_P fraction) and spatial overlap with TX_obs.
- If coverage is <~5–10% or n_pairs is too small, formally document that inference will be underpowered.

## 4) Potential solution directions (if gates fail)

### A) Improve information content
- Increase observation density in synthetic experiments (debugging mode only).
- For real data, consider coarser spatial aggregation or longer temporal windows to increase usable TX_obs counts.

### B) Arrival surface imputation / smoothing
- If real arrival is too sparse, apply a smoothing plane/kriging to infer arrivals where NA.
- Document this as a modelling assumption; quantify impact via sensitivity run.

### C) Structural model simplification
- If identifiability is weak, reduce the number of parameters being inferred (fix less‑identifiable ones at plausible values).
- Alternatively, enforce tighter priors on poorly identified parameters (e.g., pred_c, pred_scale).

### D) Suitability bias rather than binary mask
- Switch from hard 0/1 riparian mask to continuous weighting in predation or carrying capacity (scale_matrix). This matches ecological reality at 10 km resolution.

## 5) Where PI second opinion would be most valuable
- **Arrival surface strategy:** Is it defensible to impute arrivals (plane/gradient) for the pilot and/or real data? What is the acceptable trade‑off between realism and identifiability?
- **Masking philosophy:** Should we fully abandon binary riparian masks at 10 km resolution in favour of suitability weights?
- **Real‑data thresholds:** What minimum TX_obs density or coverage is required to make real‑data inference worthwhile (and publishable)?
- **Parameter fixation:** Which parameters should be fixed vs inferred if identifiability remains weak?

## 6) Bottom line recommendation
Before a large GB synthetic benchmark (WP‑0.3.5), insert a brief gate for arrival realism, suitability bias, and information‑rich stress testing. Then run a staged 0.3.5a/0.3.5b sequence to avoid another expensive “garbage‑in/garbage‑out” outcome. Keep the roadmap’s strong performance discipline but add explicit data‑information gates for real‑world readiness.

