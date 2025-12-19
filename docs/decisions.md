# Decisions log (irreversible or high-impact choices)

This file records decisions that materially affect interpretation, reproducibility, or future work.
If you change your mind, add a new entry explaining why.

Format for entries:

- **Date:** YYYY-MM-DD
- **Decision:** one sentence
- **Rationale:** 2–6 bullets
- **Implications:** what changes in code/interpretation
- **Alternatives considered:** brief

---

## Inherited decisions (already encoded in the repo)

- **Date:** inherited
- **Decision:** Use `targets` as the execution harness for all heavy workflows.
- **Rationale:**
  - Ensures reproducibility and dependency tracking
  - Enables per-draw isolation and caching
- **Implications:**
  - New workflows should be added via `pipelines/*.R` and `_targets.R`
- **Alternatives considered:** ad-hoc scripts (rejected)

---

- **Date:** inherited
- **Decision:** Use `renv` for dependency management.
- **Rationale:**
  - Reproducible package versions and Quarto rendering
- **Implications:**
  - Always run under `renv::restore()` and keep `renv.lock` updated
- **Alternatives considered:** system library installs (rejected)

---

- **Date:** inherited
- **Decision:** Use a streaming TX-only simulator for large screens.
- **Rationale:**
  - Avoids memory blow-ups from storing 3D abundance cubes
  - Matches the actual inference target (extirpation time surface)
- **Implications:**
  - `exdyn_simulate_tx_only()` is the default for screening and inference
- **Alternatives considered:** full 3D state simulation (allowed only for small toy cases)

---

- **Date:** inherited
- **Decision:** Define extirpation timing as a first-passage event (with hold/threshold rules).
- **Rationale:**
  - Avoids “extinct from day one” artefacts
  - Robust to single-year dips in noisy presence-only indices
- **Implications:**
  - All TX estimation and synthetic twin observation layers must use this definition
- **Alternatives considered:** naive threshold crossing (rejected)

---

- **Date:** inherited
- **Decision:** Pattern-oriented calibration using response-only summaries is the primary inference strategy.
- **Rationale:**
  - Predator/habitat data are often missing or unreliable in real systems
  - We want inference that can run on prey extirpations alone
- **Implications:**
  - Maintain leakage-safe feature sets; do not smuggle drivers into response-only inference
- **Alternatives considered:** direct fitting to abundance/counts (not used)

---

- **Date:** inherited
- **Decision:** Allow δ offsets on predator arrival time but constrain them (bounds + penalties).
- **Rationale:**
  - Detection lags exist; δ is a practical correction
  - Unconstrained δ destroys identifiability by flattening spatial structure
- **Implications:**
  - δ must be bounded and regularised; report δ behaviour explicitly
- **Alternatives considered:** no δ (too rigid); free δ (too flexible)

---

## Pending decisions (must be resolved during Phase 020)
- Final choice of analysis units for real mink→vole (coarse grid vs segments) based on “enough TX_obs units” gate.
- Whether to add an explicit habitat field H(x,t) for real mink→vole if predation-only cannot pass gates.

---

## Performance budgets (Phase 020)

- **Date:** 2025-12-19  
- **Decision:** Establish explicit runtime/memory budgets for synthetic‑twin smoke/medium/full profiles and enforce toy‑profile usage for WP‑0.3.1/0.3.2.  
- **Rationale:**  
  - Smoke runs should validate plumbing in minutes, not hours.  
  - ABC recovery is only defensible if per‑simulation cost is known and bounded.  
  - Profiling shows observation/TX estimation dominates toy runtime; budgets must account for that.  
- **Implications:**  
  - **Toy smoke**: <10 min end‑to‑end on standard workstation.  
  - **Medium**: <1 hr per end‑to‑end run; not used in CI.  
  - **Full GB**: labelled **overnight/HPC**; per‑simulation budget to be reported before WP‑0.3.5.  
  - WP‑0.3.1/0.3.2 must run **toy or medium** only.  
- **Alternatives considered:**  
  - Proceeding with full GB smoke (rejected: unbounded runtime).
