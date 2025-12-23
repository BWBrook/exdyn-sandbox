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

- **Date:** 2025-12-20  
- **Decision:** Record measured preflight budgets for medium and GB‑scale realistic runs (WP‑0.3.4b).  
- **Rationale:**  
  - Preflight runs expose true wall‑clock and RSS costs before WP‑0.3.5.  
  - GB realistic mode includes the expensive observation pipeline and must be budgeted explicitly.  
- **Implications:**  
  - **Medium preflight (toy 70×70, 1950–2020, realistic, 1 rep)**:  
    - wall time ≈ **62.2 s**, max RSS ≈ **834,156 kB** (~0.8 GB).  
  - **GB preflight (pilot grid, realistic, 1 rep, minimal ABC)**:  
    - wall time ≈ **43:30** (≈2610.6 s), max RSS ≈ **43,677,192 kB** (~41.7 GB).  
  - WP‑0.3.5 must assume **≥43 min per replicate** at current settings unless optimised.  
- **Alternatives considered:**  
  - Proceeding without a GB preflight (rejected: unacceptable risk of runaway runtime/memory).

---

- **Date:** 2025-12-20  
- **Decision:** Default synthetic observation generation to **cell‑year counts** (no point‑level PO samples) and treat GB preflight budgets as hard gates for any full‑scale recovery runs.  
- **Rationale:**  
  - Point‑level synthetic observations add heavy overhead without changing the grid‑scale inference target.  
  - Preflight budgets imply full GB benchmarks require batching/HPC planning before WP‑0.3.5.  
- **Implications:**  
  - `noise.obs_mode` defaults to `counts` in synthetic/perf configs; points are debug‑only.  
  - Full GB recovery runs must be scheduled with batching/HPC assumptions; no un‑budgeted “overnight” runs.  
- **Alternatives considered:**  
  - Continuing point‑level PO for synthetic benchmarks (rejected: unnecessary overhead).

---

- **Date:** 2025-12-20  
- **Decision:** Hard‑enforce performance hygiene in synthetic runs: vectorised
  orientation metrics, analytic r²/slope formulas, and **streaming counts‑mode
  truth generation** (no 3‑D N/P arrays).  
- **Rationale:**  
  - Profiling showed summary statistics and 3‑D arrays dominate GB‑scale cost.  
  - Replacing per‑cell loops and `lm()` calls removes avoidable overhead while
    preserving statistical meaning.  
  - Streaming counts eliminates the biggest memory sink in counts‑mode truth
    generation.  
- **Implications:**  
  - Counts‑mode synthetic truth no longer constructs `N[x,y,t]` or `P[x,y,t]`
    arrays.  
  - Summary/score hot paths no longer call `lm()` per draw.  
  - GB counts preflight budgets must be re‑measured against the new path.  
- **Alternatives considered:**  
  - Keeping the existing loop/`lm()` implementations (rejected: unnecessary
    compute tax at GB scale).

---

- **Date:** 2025-12-21  
- **Decision:** Add optional **domain cropping** (mask bounding box + padding)
  for TX‑only and counts‑stream simulations, enabled via synthetic config or
  `EXDYN_SYNTHETIC_CROP=1`.  
- **Rationale:**  
  - Avoids FFT work over ocean/NA cells without changing scientific meaning.  
  - Keeps outputs on the full grid while reducing compute for masked domains.  
- **Implications:**  
  - Cropping is **opt‑in**; default behaviour is unchanged.  
  - Performance preflights may enable crop for GB‑scale runs.  
- **Alternatives considered:**  
  - Hard‑cropping outputs to the sub‑grid (rejected: breaks downstream plots).  

---

- **Date:** 2025-12-21  
- **Decision:** Record a **full‑pipeline GB counts preflight** (screen + ABC +
  report, pilot grid) with true RSS and storage deltas.  
- **Rationale:**  
  - WP‑0.3.5 budgets must reflect the **end‑to‑end** pipeline, not just
    sim+obs stages.  
  - Counts‑mode + streaming counts reduced core costs; this confirms the
    pipeline is now minutes‑scale at pilot grid size.  
- **Implications:**  
  - **Full‑pipeline counts preflight** (pilot grid, minimal ABC, crop=TRUE):  
    - wall time ≈ **3:01** (181 s), max RSS ≈ **1,205,900 kB** (~1.15 GB).  
    - canonical size ≈ **192 kB**, `_targets/objects` delta ≈ **-12 kB**.  
  - Canonical run:  
    - `outputs/canonical/0.3/WP-0.3.4b/preflight_full_counts_20251221_142443/`  
  - WP‑0.3.5 can proceed **only if** ABC draw counts remain bounded and
    projected wall time stays within acceptable limits.  
- **Alternatives considered:**  
  - Proceeding to WP‑0.3.5 without a full‑pipeline preflight (rejected).  

---

- **Date:** 2025-12-21  
- **Decision:** Enforce **mask‑consistent summary denominators** and add explicit
  count fields (`n_mask`, `n_TP_finite`, `n_pairs`, `n_TX_*`) to synthetic
  summary outputs; bump schema to **0.3.3**.  
- **Rationale:**  
  - Prior pilot runs compared masked simulated summaries against unmasked
    observed summaries, producing artificially low coverage and NA geometry.  
  - Explicit counts make denominator mismatches visible and auditable in
    recovery outputs.  
- **Implications:**  
  - `summary_obs.csv`, `screen_results.csv`, and `replicate_metrics.csv` now
    include mask‑aware count fields.  
  - Mask is applied consistently in `exdyn_summary_tx_response` and
    `exdyn_score`.  
  - Schema version is now **0.3.3** (see `docs/schema.md`).  
- **Alternatives considered:**  
  - Leaving summaries unmasked and manually adjusting denominators in reports
    (rejected: too error‑prone and not enforceable by tests).

---

- **Date:** 2025-12-21  
- **Decision:** Add `arrival_source` override for synthetic pilot runs with options
  `real`, `synthetic_plane`, `synthetic_gradient`, plus arrival diagnostics
  reporting finite coverage overall and within mask.  
- **Rationale:**  
  - Pilot failures may be driven by sparse arrival coverage; overrides provide a
    controlled way to separate arrival sparsity from simulator behaviour.  
  - Diagnostics make coverage gaps explicit before running recovery.  
- **Implications:**  
  - Synthetic pipeline can swap arrival surfaces without altering real-data
    construction.  
  - `outputs/synthetic/pilot_diagnostics.csv` and arrival plots document coverage
    by source.  
- **Alternatives considered:**  
  - Manually editing arrival matrices for diagnostics (rejected: not reproducible).

---

- **Date:** 2025-12-21  
- **Decision:** Set synthetic truth thresholds to **truth_frac = 0.16** and
  **truth_rel0 = 1.8** (pilot grid, arrival_source = synthetic_plane, mask = all).  
- **Rationale:**  
  - Viability sweep over `(truth_frac, truth_rel0)` at `pred_scale=3.0`,
    `pred_c=2.4` showed:  
    - `(0.12, 1.5–2.0)` → ~5 extirpations (coverage ~0.001)  
    - `(0.16, 1.8–2.0)` → **~90 extirpations** (coverage ~0.025)  
    - `(0.20, 1.8–2.0)` → full extirpation (coverage = 1).  
  - The selected values are the smallest thresholds that clear the
    **n_TX_true ≥ 50** gate without saturating the grid.  
- **Implications:**  
  - Synthetic pilot runs should use `truth_frac=0.16`, `truth_rel0=1.8` while
    keeping predation parameters unchanged.  
  - Viability artefacts: `outputs/synthetic/viability_sweep.csv` and
    `outputs/synthetic/viability_sweep_plot.png`.  
- **Alternatives considered:**  
  - Increasing predation strength alone (insufficient signal under pilot grid).  
  - Higher thresholds (`truth_frac ≥ 0.20`, `truth_rel0 ≥ 2.0`) (rejected: full
    extirpation saturation).

---

- **Date:** 2025-12-22  
- **Decision:** Update synthetic `theta_star` to **pred_scale = 0.6** and
  **pred_c = 0.6**, reverting truth thresholds to **truth_frac = 0.02** and
  **truth_rel0 = 0.5**, for pilot‑grid identifiability.  
- **Rationale:**  
  - Pilot viability sweep with `truth_frac=0.02`, `truth_rel0=0.5` showed:
    - `(pred_scale=0.6, pred_c=0.6)` → **coverage ≈ 0.289** (n_TX_true ≈ 1058),
      satisfying Gate G2 without saturation.  
    - Lower predation (`pred_scale≤0.6`, `pred_c=0.3`) yielded zero extirpations;
      higher predation (`pred_scale=1.2`, `pred_c=0.6`) saturated coverage (=1).  
  - Adjusting predation parameters is the minimal change to achieve
    non‑degenerate TX patterns under the pilot grid.  
- **Implications:**  
  - Pilot synthetic runs use the updated `theta_star` (predation strength tuned).
  - Viability artefacts updated: `outputs/synthetic/viability_sweep.csv` and
    `outputs/synthetic/viability_sweep_plot.png`.  
- **Alternatives considered:**  
  - Raising truth thresholds (led to saturation under the pilot grid).  
  - Keeping strong predation (produced full extirpation).

---

- **Date:** 2025-12-23  
- **Decision:** Use **TX-quantile coverage breaks** for synthetic pilot summaries
  (`coverage_breaks.strategy = "tx_quantile"`).  
- **Rationale:**  
  - Fixed year-based breaks sat below the TX_true window, causing the
    coverage-curve gate (G4) to fail even when extirpations were informative.  
  - Quantile breaks keep the coverage curve informative while preserving
    consistent breaks between observed and simulated summaries within a mode.  
- **Implications:**  
  - Synthetic summaries now compute coverage-curve breakpoints from TX_use
    quantiles when enough points exist; otherwise they fall back to
    year-based breaks.  
  - Pilot gates become sensitive to coverage shape rather than being dominated
    by an arbitrary year range.  
- **Alternatives considered:**  
  - Shifting the pilot year range (rejected: ad hoc and inconsistent with real data).  
  - Relaxing G4 (rejected: would mask a real loss of summary information).  

---

- **Date:** 2025-12-23  
- **Decision:** Enable **mode-specific ABC eps thresholds** for pilot gates
  (`abc.eps_by_mode: realistic=15, ideal=23`).  
- **Rationale:**  
  - Distance scales differ between ideal and realistic modes; a single eps
    either rejected all ideal samples or over-accepted realistic samples.  
  - Mode-specific eps yields non-vacuous ABC acceptance (<0.2) in both modes.  
- **Implications:**  
  - Pilot gate G5 is now evaluated with mode-appropriate eps settings.  
  - ABC refinement remains optional (kept off for pilot speed).  
- **Alternatives considered:**  
  - Inflating a single eps (rejected: violates acceptance-rate gate).  
  - Dropping ABC for ideal mode (rejected: loses recovery diagnostics).  

---

- **Date:** 2025-12-23  
- **Decision:** Pilot observation/compat tuning set to
  `po_rate=0.01`, `drop_fraction=0.3`, `normalize_by="none"`, and
  `compat.min_r2_arrival=0`, `compat.lag_range=[0,40]`.  
- **Rationale:**  
  - Pilot TX_obs needed sufficient signal to pass identifiability gates.  
  - Looser compat thresholds prevent early rejection while the pilot is still
    being stabilized.  
- **Implications:**  
  - These settings are **pilot-only** defaults; full GB runs may need tighter
    thresholds once recovery is stable.  
- **Alternatives considered:**  
  - Increasing predation strength further (rejected: saturates coverage).  
  - Forcing normalize-by-effort (rejected: collapsed counts to near-binary).

---

- **Date:** 2025-12-23  
- **Decision:** Split synthetic pipeline into **truth generation** (`synthetic_truths`)
  and **mode recovery** (`synthetic_mode_runs`), with `synthetic_runs` as a
  lightweight aggregator.  
- **Rationale:**  
  - Avoid re-running the expensive synthetic truth simulation when only
    screen/ABC settings change.  
  - Improves iteration speed for WP‑0.3.5 and later benchmarks.  
- **Implications:**  
  - Changing `compat`/`abc` now re-runs only `synthetic_mode_runs` and
    downstream targets.  
  - Truth regeneration is triggered only by changes to inputs that genuinely
    affect the synthetic data (theta_star, noise, arrivals, grid, years, mask).  
- **Alternatives considered:**  
  - Keeping monolithic `synthetic_runs` (rejected: unnecessary recomputation).  
  - Splitting per-replicate targets (deferred: more complex than needed now).  
