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

- **Date:** 2026-02-09
- **Decision:** Use bounded, explicitly diagnostic real-data budgets for WP‑0.4.x and enforce memory-safe ablation execution overrides.
- **Rationale:**
  - Full pilot ABC settings (`screen=200`, `ABC=2000+2000`) produced impractically long runs for iterative model diagnosis.
  - Nested parallelism (`tar_make_future` outer workers + ablation inner workers) caused high RSS pressure and swap usage.
  - Real-data information audit already indicates very sparse TP/TX overlap, so expensive inference should be treated as diagnostic rather than high-precision estimation.
- **Implications:**
  - `config/realdata.yaml` pilot defaults now use bounded settings:
    - `pilot.screen.n_draws = 40`
    - `pilot.abc.n_stage1 = 30`, `pilot.abc.n_stage2 = 30`, `pilot.abc.shortlist = 40`
    - `pilot.ablation.n_draws = 40` (with runtime override support)
    - `pilot.ppc.n_draws = 10`
  - Added env overrides in the pilot pipeline:
    - `EXDYN_ABLATION_CORES`
    - `EXDYN_ABLATION_DRAWS`
  - Removed the `wo8_log_start` dependency from `pilot_cfg` so the `always` log target does not invalidate the full pilot graph on each run.
- **Alternatives considered:**
  - Keeping original large budgets (rejected: too slow for iterative R&D at current information content).
  - Running `pilot-future` with unrestricted nested parallelism (rejected: high memory risk).

---

- **Date:** 2025-12-31  
- **Decision:** Update synthetic `theta_star` to **pred_scale = 0.6** and
  **pred_c = 1.2** for pilot-grid synthetic runs with `arrival_source =
  synthetic_plane`.  
- **Rationale:**  
  - Viability sweep on the pilot grid with synthetic-plane arrivals showed
    `(pred_scale=0.6, pred_c=0.6)` yields **zero extirpations** (G2 fails).  
  - `(pred_scale=0.6, pred_c=1.2)` yields coverage ≈ **0.38** and
    `n_TX_true ≈ 1391`, clearing the G2 gate without saturating the grid.  
- **Implications:**  
  - Pilot synthetic runs now use the adjusted predation strength to ensure
    informative TX_true patterns under the complete arrival surface.  
  - Viability artefacts remain in `outputs/synthetic/viability_sweep.csv` and
    `outputs/synthetic/viability_sweep_plot.png`.  
- **Alternatives considered:**  
  - Increasing `pred_scale` alone (similar effect but larger departure from
    previous tuning).  
  - Increasing `truth_frac`/`truth_rel0` (rejected: changes extirpation
    thresholds rather than predation strength).

---

- **Date:** 2025-12-31  
- **Decision:** Parallelize synthetic recovery replicates via
  `recovery.n_cores` (Linux/macOS only) and seed each replicate explicitly.  
- **Rationale:**  
  - WP‑0.3.5a with R≥20 was infeasible when each replicate ran sequentially.  
  - Replicates are independent; controlled seeding preserves determinism
    while enabling multicore execution.  
- **Implications:**  
  - `synthetic_mode_runs` now uses `mclapply` when `n_cores > 1`, defaulting
    to the configured value (currently 8).  
  - Environment override `EXDYN_SYNTHETIC_CORES` is supported for HPC runs.  
- **Alternatives considered:**  
  - Reducing `n_sims` or `n_draws` (rejected: would weaken recovery metrics).  
  - Parallelizing within a replicate only (more invasive refactor).

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

---

- **Date:** 2025-12-25  
- **Decision:** Prototype **land‑cell graph dispersal** as a structural
  reduction for GB‑scale performance, using a sparse kernel‑weighted adjacency
  graph (radius 5) instead of FFT convolution on the full raster.  
- **Rationale:**  
  - FFT runs still pay for a 1203×1190 ocean‑heavy lattice even when only ~3.7k
    land cells are active.  
  - A land‑cell graph preserves the kernel form while eliminating the ocean
    cost and enabling feasible screen/ABC loops.  
  - Empirical tests show order‑of‑magnitude speedups for A–D stages.  
- **Implications:**  
  - New graph utilities (`exdyn_land_graph_plan`, `exdyn_land_graph_weights`) and
    `dispersal_mode = "graph"` option in TX‑only and counts‑stream simulators.  
  - Added Matrix dependency for sparse adjacency.  
  - Graph mode is **optional** and currently used for performance prototyping.  
- **Alternatives considered:**  
  - More aggressive raster cropping (insufficient), river‑segment graph
    (larger model change).  

---

- **Date:** 2025-12-30  
- **Decision:** Treat real-arrival sparsity as a limiting condition rather than
  silently imputing for the arrival realism gate; synthetic-plane arrivals remain
  the completeness baseline for identifiability checks.  
- **Rationale:**  
  - Arrival realism comparison shows `frac_finite_TP_in_mask ≈ 0.41` under real
    arrivals vs `≈1.0` under synthetic_plane on the pilot grid.  
  - Imputing arrivals could mask a real data limitation; we need an explicit
    “real vs override” contrast to interpret identifiability honestly.  
- **Implications:**  
  - WP‑0.3.4.5 reports identifiability under both real and synthetic-plane arrivals.  
  - Real-data inference (Phase 0.4.x) must acknowledge arrival sparsity as a
    potential hard limitation unless a defensible imputation policy is adopted.  
- **Alternatives considered:**  
  - Automatically impute arrivals for all real-data runs (rejected for now; would
    conflate model feasibility with data augmentation).

---

- **Date:** 2025-12-30  
- **Decision:** Adopt **soft suitability weighting** (land mask + river_km‑scaled weights) instead of a hard riparian mask at 10 km resolution for synthetic/pilot runs.  
- **Rationale:**  
  - Hard riparian mask on the pilot grid left only ~19 active cells and produced **zero** extirpations (degenerate TX_true).  
  - Soft suitability on the same grid produced a coherent extirpation pattern (n_TX_true ≈ 1215; coverage_true ≈ 0.33) with finite geometry summaries.  
  - The binary mask is too restrictive and creates artificial isolation at this resolution.  
- **Implications:**  
  - Subsequent synthetic/pilot runs should use **land mask + suitability weighting** (currently scale range 0.5–1.5, log1p).  
  - Hard riparian masks are retained only for diagnostics/toy checks, not for inference‑oriented runs.  
- **Alternatives considered:**  
  - Keep hard mask and accept degeneracy (rejected; non‑informative).  
  - Add external habitat layers (deferred; out of scope for WP‑0.3.4.6).

---

- **Date:** 2025-12-31  
- **Decision:** Default synthetic pipeline to **graph-mode dispersal** (noise + screen) to keep pilot‑grid diagnostics tractable.  
- **Rationale:**  
  - FFT on the full 1203×1190 lattice makes even modest replicated diagnostics too slow.  
  - Graph-mode preserves dispersal mechanics while avoiding ocean-heavy costs; ceiling and benchmark runs complete in minutes.  
- **Implications:**  
  - Synthetic runs now use `dispersal_mode = graph` unless explicitly overridden.  
  - Ceiling and canonical benchmarks are interpreted under graph-mode assumptions.  
- **Alternatives considered:**  
  - Keeping FFT and reducing replicates (rejected; undermines benchmark reliability).  

---

- **Date:** 2025-12-31  
- **Decision:** Use **trimmed ABC/screen budgets** for the ceiling diagnostic (n_draws=2, n_sims=10).  
- **Rationale:**  
  - The ceiling run is an identifiability upper bound, not a final calibration; coarse budgets preserve directionality while keeping runtime feasible.  
- **Implications:**  
  - Ceiling metrics are conservative; full ABC budgets can be restored later if needed.  
- **Alternatives considered:**  
  - Full ABC budgets (rejected for now due to multi‑hour runtime).

---

- **Date:** 2025-12-31  
- **Decision:** Enforce output freshness via a guardrail comparing output mtimes against the synthetic config snapshot.  
- **Rationale:**  
  - Prevents silent reuse of stale arrival/viability plots after config changes.  
- **Implications:**  
  - Synthetic pipeline now fails fast if key outputs are older than the config file.  
- **Alternatives considered:**  
  - Rely on human checks only (rejected; too brittle).

---

- **Date:** 2026-02-09  
- **Decision:** Treat `alpha` and `disp_mean_km` as explicitly **weakly identifiable** core parameters in the WP‑0.3.5a pilot benchmark, and evaluate pass/fail under `benchmark.stance = weak_id`.  
- **Rationale:**  
  - In the R=20 canonical pilot run, strict recoverable bias thresholds are not met for these parameters despite strong interval coverage and stable predictive fit.  
  - The benchmark objective at this stage is to separate recoverable vs weak-ID dimensions honestly, not force strict recovery where information content is limited.  
  - Manifest metadata already supports declared vs observed weak-ID parameter lists, enabling auditable interpretation.  
- **Implications:**  
  - WP‑0.3.5a is considered complete when weak-ID declarations and observed statuses are consistent and realistic predictive gates pass.  
  - Downstream WP‑0.3.5b/0.3.6 should continue to treat these parameters as weak-ID unless stress tests demonstrate otherwise.  
- **Alternatives considered:**  
  - Keeping strict recoverable thresholds for all core parameters (rejected for pilot benchmark: would force repeated tuning without improving scientific honesty).  

---

- **Date:** 2026-02-09  
- **Decision:** Include `synthetic_canonical_manifest` in the default `make synthetic` target.  
- **Rationale:**  
  - The previous target set (`synthetic_report_html`, `synthetic_report_pdf`, `synthetic_recovery_written`) could complete successfully without emitting canonical artefacts.  
  - This created a reproducibility gap where a “finished” synthetic run had no canonical folder unless a second manual command was executed.  
- **Implications:**  
  - Canonical packaging now runs in the default synthetic command path when canonical env flags are enabled.  
  - Reduces operator error and keeps roadmap evidence requirements aligned with standard execution commands.  
- **Alternatives considered:**  
  - Keep canonical packaging as a separate manual step (rejected; too easy to miss during long runs).

---

- **Date:** 2026-02-09  
- **Decision:** For LARGE parallel synthetic runs, treat aggregate worker memory snapshots as the operative RSS budget metric, and use `time -v` RSS as parent-process context only.  
- **Rationale:**  
  - In WP‑0.3.5b (`R=20`, graph mode, 20 active workers), `time -v` reported max RSS ≈ 4.1 GB while concurrent worker snapshots reached ~75 GB aggregate RSS.  
  - Parent-only RSS can materially understate memory pressure for future larger parallel runs.  
  - Runtime/memory planning for HPC scheduling must reflect concurrent worker footprint, not just coordinator process RSS.  
- **Implications:**  
  - LARGE run logs should report both:
    - wall time + `time -v` metrics, and
    - aggregate worker RSS snapshots during peak parallel phase.  
  - Budget comparisons in roadmap reviews should use aggregate worker RSS for pass/fail interpretation.  
- **Alternatives considered:**  
  - Rely only on `time -v` max RSS (rejected: misleading under parallel worker pools).

---

- **Date:** 2026-02-09  
- **Decision:** Switch roadmap governance to **autonomous internal review by default**; external PI review is optional and triggered only by explicit human request.  
- **Rationale:**  
  - The project is moving to a higher-autonomy operating model with in-repo QA as the default control loop.  
  - Mandatory external PI review gates were slowing execution even when internal checks, tests, and artefact audits were sufficient.  
  - External PI review remains valuable for selected checkpoints, but should be invoked deliberately by the human rather than automatically by policy.  
- **Implications:**  
  - `docs/roadmap.md` section 5 now defines internal quality gates/checkpoints rather than mandatory PI-review stops.  
  - LARGE WP completion now requires internal checkpoint artefacts and logs; external PI handoff is optional.  
  - Benchmark failures still block WP completion, but remediation proceeds autonomously unless the human requests a pause/review.  
- **Alternatives considered:**  
  - Keep mandatory PI-review stops at milestones/LARGE WPs (rejected: too rigid for current workflow).  

---

- **Date:** 2026-02-09  
- **Decision:** Use `grid_all` as the real-data representation for constrained inference while treating overlap scarcity as the primary limitation.  
- **Rationale:**  
  - Representation audit shows `grid_all` is the only candidate that meets the unit-count gate (`n_units=3621`, `n_TX_obs=569`).  
  - Segment and riparian-only representations fail minimum unit thresholds in the current data state.  
  - Even under `grid_all`, overlap is critically sparse (`n_TP_finite=7`, `n_pairs=1`), so selection is pragmatic rather than evidentially rich.  
- **Implications:**  
  - Real constrained runs continue with `analysis_unit = grid_all`.  
  - Conclusions must emphasize overlap-limited inference and avoid overclaiming mechanism sufficiency.  
- **Alternatives considered:**  
  - `segment` and `grid_riparian` as primary representations (rejected: underpowered at current thresholds).  

---

- **Date:** 2026-02-09  
- **Decision:** Keep random effects on `pred_scale` disabled for the real constrained baseline and retain `delta_only` as the default interpretive model.  
- **Rationale:**  
  - Ablation (`delta_only` vs `delta_plus_re`) produced zero compatible draws in both settings at matched draw budgets, with near-identical median loss.  
  - Adding RE increased complexity without measurable fit gains under current information constraints.  
- **Implications:**  
  - Real-case interpretation focuses on signal limits and baseline constrained model behavior.  
  - RE can be revisited only if future data/representation choices materially improve overlap.  
- **Alternatives considered:**  
  - Keeping RE enabled by default (rejected: no demonstrated benefit in current run).  

---

- **Date:** 2026-02-09  
- **Decision:** Treat the current real mink→vole result as a documented **data-limited/mechanism-incomplete** verdict, not a positive predation-only confirmation.  
- **Rationale:**  
  - Gate evaluation fails across all key checks (`best_r2`, `best_lag`, `best_coverage`, `abc_accept_rate`).  
  - No ABC posterior samples were accepted at configured thresholds; posterior summary metrics are `NA`.  
  - Visual diagnostics agree with gate outcomes (simulated extirpations are far sparser than observed pattern).  
- **Implications:**  
  - Manuscript and report language must present this as a negative-but-informative finding grounded in explicit diagnostics.  
  - Next scientific progress should target representation/data enrichment rather than tuning the same constrained run harder.  
- **Alternatives considered:**  
  - Relaxing thresholds until acceptance appears (rejected for this milestone: would weaken inferential honesty).  

---

- **Date:** 2026-03-08  
- **Decision:** Separate fresh-checkout bootstrap from maintainer-side environment mutation, and require target execution to use a pre-restored environment rather than self-install missing packages.  
- **Rationale:**  
  - `make init` previously mixed restore, documentation regeneration, and lockfile snapshotting, which made a nominal bootstrap command mutate tracked state.  
  - `_targets.R` previously attempted to install `qs` on the fly, which hid environment drift and weakened reproducibility guarantees.  
  - A clear `make setup` path is safer for contributors and CI.  
- **Implications:**  
  - `make setup` is now the default non-mutating restore path.  
  - `make init` remains available as the explicit maintainer workflow.  
  - `_targets.R` now fails fast if required packages are missing instead of altering the environment.  
- **Alternatives considered:**  
  - Keep bootstrap and maintenance coupled, and keep self-install fallback in `_targets.R` (rejected: too easy to mask environment problems).  

---

- **Date:** 2026-03-08  
- **Decision:** Replace live-network GBIF helper testing with local mocked coverage and require the core suite to run warning-clean.  
- **Rationale:**  
  - Network-dependent tests are nondeterministic and unsuitable as a reliable baseline for CI/refactoring.  
  - Persistent warning noise makes regressions harder to spot during aggressive internal cleanup.  
  - Characterization tests are more valuable than brittle live-service smoke checks for this repo’s current phase.  
- **Implications:**  
  - CI can now rely on the package test suite without internet-sensitive GBIF lookup behaviour.  
  - Expected-warning cases are explicitly suppressed or rewritten so new warnings stand out.  
  - New characterization coverage now protects ABC non-finite-summary behaviour, real-loss aggregation, and multicore determinism.  
- **Alternatives considered:**  
  - Keep live GBIF tests and tolerate warning-heavy output (rejected: poor signal for the refactor phase).  
