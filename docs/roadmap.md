# Roadmap: ExtDyn Modelling Sandbox (work-queue for autonomous runs)

**Purpose:** This roadmap is the execution contract for autonomous Codex CLI runs. It defines the scientific arc of the paper (methods → validation → case study) and the minimum engineering needed to make that arc reproducible and reviewable.

**Last updated:** 2025-12-21

---

## 1) Opening contract

**When the human says “Follow the roadmap”:**
- Codex must select the **first unchecked Work Package (WP)** in the **Priority Queue** (Section 3) and complete it **end-to-end** (code + tests + docs + artefacts + review notes).
- On completion, Codex must:
  - mark the WP checkbox as **checked** (`[x]`),
  - add a short completion record under that WP’s spec (Section 4) including:
    - date,
    - commit SHA,
    - canonical artefact folder path,
    - a one-paragraph “what changed / what we learned”.

**Reordering / skipping:**
- Reordering priorities is allowed **only** if:
  - a rationale is recorded in `docs/decisions.md`, and
  - a dated log entry is added to `docs/log/`.
- Skipping a WP is allowed **only** if:
  - it is explicitly marked as “SKIPPED” in its completion record,
  - with a rationale recorded in `docs/decisions.md` and `docs/log/`,
  - and the skip does **not** violate milestone gates (Section 5).

**Stopping rule:**
- If the Priority Queue is empty (all WPs are checked), Codex must **stop** and report:  
  “Roadmap complete; more work must be promoted to the Priority Queue.”

**Paper arc (what this roadmap delivers):**
1. A **calibrated synthetic benchmark** proving what parameters can/can’t be recovered under known truth.
2. A **real mink→vole case-study verdict** under a constrained predation-front model.
3. A **manuscript-ready package** (text + figures/tables pinned to canonical artefacts) that is reproducible.

---

## 2) Work Package Definition of Done (WP‑DoD)

A WP is **not done** until all items below are satisfied.

### 2.1 Acceptance criteria met and tested
- All WP acceptance criteria (Section 4) are satisfied.
- `make test` (or the repo’s canonical test command) passes.
- Any new functionality is covered by:
  - unit tests (`testthat`) **and/or**
  - non-interactive sanity checks that fail loudly on regressions.

### 2.2 Docs updated (minimum required)
Each WP must update docs so the repo remains interpretable without oral tradition. At minimum:
- `docs/config_reference.md` (or equivalent) updated to reflect any config keys/meaning changes.
- `docs/interpretation_notes.md` updated with:
  - what the new artefacts say,
  - what could be misleading,
  - what limitations remain.

### 2.3 Artefact Review Cycle completed and logged
Each WP must produce reviewable artefacts and record sanity inspection notes.

**Artefact Review Cycle steps (must be logged in `docs/log/`):**
1. Build artefacts (targets/reports) for the WP.
2. Save a **canonical run folder** (see below).
3. Perform a sanity inspection of the canonical artefacts (plots/tables), writing:
   - what is consistent with expectations,
   - what is suspicious,
   - whether the WP gates pass.
4. Record the result in `docs/log/<date>_<wp_id>_<shortname>.md`.

**Canonical run folder (required for any WP that changes outputs or produces figures/tables):**
- Must be placed under: `outputs/canonical/<milestone>/<wp_id>/<run_id>/`
- Must include at minimum:
  - `manifest.yaml` (commit SHA, schema_version, run timestamp, key config snapshot paths, seeds, core commands used),
  - config snapshot(s) used for the run (exact YAML as executed),
  - `session_info.txt` (R sessionInfo),
  - the primary tables (CSV) and primary figures (PNG/PDF) produced by the WP,
  - rendered report(s) if the WP affects Quarto output.

### 2.4 Schema discipline
If a WP changes a schema, it must also deliver the schema hygiene.

- **If internal schema changes** (e.g., key RDS object structure used across targets):
  - bump `schema_version` (single authoritative location),
  - add a migration path (old → new),
  - add migration tests (old fixtures load and migrate correctly).

- **If output schema changes** (filenames/columns/meaning of outputs):
  - document the change in `docs/schema.md` (or equivalent),
  - add regression/sanity tests to prevent silent breakage.

---

## 3) Priority Queue (strict order)

### Milestone 0.2.x — Performance & scaling ground truth
- [x] **WP‑0.2.1 — Toy benchmark scenario + explicit smoke profiles**
- [x] **WP‑0.2.2 — Timing & memory instrumentation harness**
- [x] **WP‑0.2.3 — Scaling sweep: (grid × years × replicates) performance map**
- [x] **WP‑0.2.4 — Performance budgets + gating thresholds (contract for later WPs)**
- [x] **WP‑0.2.5 — Targeted optimisation of the dominant bottleneck (only one)**
- [x] **WP‑0.2.6 — CI-safe performance guardrails (lightweight)**

### Milestone 0.3.x — Synthetic twin benchmark locked (must pass before any real-data claims)
- [x] **WP‑0.3.1 — Synthetic outputs schema + canonical artefact manifest standard**
- [x] **WP‑0.3.2 — Synthetic: ideal vs realistic modes (TX_true vs TX_obs) wired end‑to‑end**
- [x] **WP‑0.3.3 — Synthetic: replicated recovery harness + parameter recovery metrics**
- [x] **WP‑0.3.4 — Synthetic: summary/loss alignment + regression tests**
- [x] **WP‑0.3.4b — GB‑scale preflight budget check (single‑replicate, realistic mode, real RSS)**
- [x] **WP‑0.3.4.1 — Pilot: mask‑consistent summaries + tests**
- [x] **WP‑0.3.4.2 — Pilot: arrival‑surface diagnostics + override switch**
- [x] **WP‑0.3.4.3 — Pilot: truth viability sweep (TX coverage tuning)**
- [x] **WP‑0.3.4.4 — Pilot: re‑run recovery + enforce identifiability gates**
- [ ] **WP‑0.3.5 (LARGE) — Synthetic: canonical recovery run (R≥20) + benchmark gates**
- [ ] **WP‑0.3.6 — Synthetic: identifiability stress mini‑sweep + failure regime artefacts**

### Milestone 0.4.x — Real mink→vole verdict under constrained predation-front model
- [ ] **WP‑0.4.1 — Real: representation audit + analysis‑unit selection (meets unit-count gate)**
- [ ] **WP‑0.4.2 — Real: δ regularisation + (optional) pred_scale random effects ablation decision**
- [ ] **WP‑0.4.3 (LARGE) — Real: constrained screen + ABC run + posterior predictive checks**
- [ ] **WP‑0.4.4 — Real: verdict write‑up (predation-only sufficient vs data/model-limited)**

### Milestone 0.5.x — Manuscript-ready package (methods + validation + case study)
- [ ] **WP‑0.5.1 — Manuscript scaffold + figure/table manifest pinned to canonical artefacts**
- [ ] **WP‑0.5.2 — Methods text: model, observation layer, TX estimator, inference**
- [ ] **WP‑0.5.3 — Results package: synthetic recovery benchmark (tables/figs + narrative)**
- [ ] **WP‑0.5.4 — Results package: real mink→vole case study verdict (tables/figs + narrative)**
- [ ] **WP‑0.5.5 — Reproducibility + release freeze (paper artefacts reproducible from scratch)**

---

## 4) Detailed WP specifications

### WP‑0.2.1 — Toy benchmark scenario + explicit smoke profiles

**Outcome:** A deliberately tiny “toy” scenario exists (small grid, short time span) plus a controlled ramp-up set, so smoke tests are *fast by definition* and scaling can be explored deliberately.

**Scope (in/out):**

* In: create toy configs; define “smoke”, “medium”, “full” run profiles (years, grid size, replicates); document.
* Out: algorithmic optimisation.

**Acceptance criteria:**

* There is a documented **toy** config and it is the default for smoke tests.
* Smoke run completes end-to-end (sim + summaries + minimal outputs) in **<10 minutes** on the usual machine (CI can be smaller).
* Medium profile exists and is runnable (but not used by CI).
* Full profile corresponds to the British Isles synthetic twin settings (explicitly labelled “overnight/HPC”).

**Artefact evidence:**

* `outputs/perf/toy_smoke/` (or canonical folder) with:

  * manifest (commit, seeds, config snapshot),
  * a runtime + memory record,
  * at least one TX map + one key summary table.

**Stop condition:** Smoke and medium profiles exist, are documented, and smoke completes fast.

**Status:** Complete — see `config/perf.yaml` and `outputs/perf/toy_smoke/` (2025‑12‑19).

---

### WP‑0.2.2 — Timing & memory instrumentation harness

**Outcome:** We can produce a table that says, unambiguously, where time and RAM go (sim loop vs dispersal vs summary vs observation vs I/O).

**Scope:**

* In: instrumentation wrapper(s) that measure wall time and peak memory for named stages.
* Out: speeding anything up yet.

**Acceptance criteria:**

* A single run emits a **stage-level profiling table** with at least:

  * setup time,
  * per-year sim time (aggregated),
  * dispersal time,
  * predation-field regeneration time,
  * summary computation time,
  * observation model time (if invoked),
  * save/serialization time,
  * peak memory estimate.
* Results are saved as a CSV in `outputs/perf/`.

**Artefact evidence:**

* `outputs/perf/stage_profile_smoke.csv`
* One short narrative sanity note in `docs/log/` explaining what dominates and what surprised us.

**Stop condition:** Stage profile exists and is repeatable.

**Status:** Complete — `outputs/perf/stage_profile_smoke.csv` produced (2025‑12‑19).

---

### WP‑0.2.3 — Scaling sweep: (grid × years × replicates) performance map

**Outcome:** A small, systematic scaling experiment exists that shows empirical scaling (time + RAM) as a function of grid size, years, and replicate count.

**Scope:**

* In: run a small factorial grid (not huge) across:

  * grid sizes (e.g., 25×25, 50×50, 100×100 or equivalent cell counts),
  * years (e.g., 30, 80, 150),
  * replicates (e.g., 1, 10),
  * with dispersal on/off as a separate switch.
* Out: tuning ABC.

**Acceptance criteria:**

* The scaling sweep produces a tidy table:

  * `n_cells`, `n_years`, `n_reps`, `dispersal_on`,
  * `wall_time`, `peak_mem`, plus stage breakdown if available.
* At least one plot/summary exists that makes scaling behaviour obvious (even just a simple log-log plot).

**Artefact evidence:**

* `outputs/perf/scaling_sweep.csv`
* `outputs/perf/scaling_plots/` containing at least one figure.

**Stop condition:** We can point to the table and say “doubling cells roughly does X”.

**Status:** Complete — `outputs/perf/scaling_sweep.csv` and plots in `outputs/perf/scaling_plots/` (2025‑12‑19).

---

### WP‑0.2.4 — Performance budgets + gating thresholds (contract for later WPs)

**Outcome:** We write down explicit runtime budgets that later WPs must respect (so no one accidentally turns “smoke” into “inferno”).

**Scope:**

* In: define performance budgets for:

  * toy smoke,
  * medium profile,
  * full GB synthetic twin *per simulation*,
  * and rough projected costs for screens/ABC.
* Out: code optimisation.

**Acceptance criteria:**

* `docs/decisions.md` includes a **Performance Budget** decision:

  * per-simulation time budgets,
  * memory ceiling guidance,
  * what counts as “large run”.
* Roadmap WPs 0.3.x are updated so that:

  * WP‑0.3.1 and WP‑0.3.2 must use the **toy** or **medium** profile only,
  * the first allowed “overnight/full GB” run is WP‑0.3.5 (already marked LARGE).

**Artefact evidence:**

* A budget table in docs (and referenced in roadmap).
* A log entry noting the budgets were derived from WP‑0.2.3 evidence.

**Stop condition:** Budgets exist and are enforceable.

**Status:** Complete — budgets recorded in `docs/decisions.md` (2025‑12‑19).

---

### WP‑0.2.5 — Targeted optimisation of the dominant bottleneck (only one)

**Outcome:** Implement *one* performance improvement that targets the actual hotspot, and demonstrate a measured speed/memory improvement **without changing scientific meaning**.

**Scope:**

* In: one optimisation only (e.g., caching FFT plans, preallocation, reducing copies, avoiding per-year allocations, or making mask operations cheaper).
* Out: refactoring everything.

**Acceptance criteria:**

* A before/after benchmark exists (same configuration, same seed) showing:

  * ≥2× speed improvement **or** ≥30% memory reduction in the dominant stage.
* Regression/sanity tests confirm that:

  * TX outputs are identical (or within documented tolerance if stochastic), and
  * summaries are unchanged except for expected stochastic noise.

**Artefact evidence:**

* `outputs/perf/optimisation_before_after.csv`
* Log note describing what changed and why it’s safe.

**Stop condition:** Measured improvement delivered and validated.

**Status:** Complete — fast TX map path implemented; comparison recorded in `outputs/perf/optimisation_before_after.csv` (2025-12-19).

---

### WP‑0.2.6 — CI-safe performance guardrails (lightweight)

**Outcome:** CI stops silently-increasing runtime/memory regressions from creeping back in.

**Scope:**

* In: CI smoke run uses toy profile and enforces basic constraints.
* Out: strict microsecond-level performance tests (too brittle).

**Acceptance criteria:**

* At least one automated test fails if:

  * smoke runtime exceeds a generous threshold on CI hardware, or
  * memory exceeds an agreed ceiling, or
  * output schema changes without bumping schema_version.
* These guardrails are documented (so people don’t “fix” them by removing them).

**Artefact evidence:**

* CI/test log showing guardrail running.
* A doc note explaining thresholds and why they’re not overly strict.

**Stop condition:** Guardrails exist and won’t be casually deleted.

**Status:** Complete — guardrail test in `tests/testthat/test_perf_guardrails.R` (2025‑12‑19).

---

### Note on WP-0.3.1 to 0.3.4 
* Re-scope WP‑0.3.1 so its smoke artefact is built on the toy/medium profile only.
* Only run British Isles 10‑km full synthetic in **WP‑0.3.5 (LARGE)** when the engine is proven and budgeted.

### WP‑0.3.1 — Synthetic outputs schema + canonical artefact manifest standard

**Outcome (one paragraph):**  
The synthetic twin becomes a benchmarkable “instrument”: outputs are versioned, documented, and always saved into a canonical run folder with a machine-readable manifest. This prevents quiet drift in what outputs mean and enables later manuscript figures/tables to be pinned to specific runs.

**Scope (in/out):**
- **In:** define authoritative `schema_version`; document synthetic output schema; define canonical folder layout + required manifest fields.
- **Out:** changing the core simulator or inference; re-running heavy experiments beyond a smoke check.

**Acceptance criteria (black-and-white):**
- A single authoritative `schema_version` exists (one file; one source of truth).
- `docs/schema.md` exists and documents at least:
  - synthetic twin core outputs (what files exist, what they mean),
  - required columns for recovery summaries,
  - any stable naming conventions.
- Canonical run folder standard is implemented and used by at least one synthetic smoke run.
- At least one automated check/test fails if:
  - schema_version is missing, or
  - required manifest fields are missing in a canonical run folder.

**Artefact evidence (must exist):**
- `docs/schema.md`
- `docs/config_reference.md` updated with any new config keys related to schema/canonical runs
- Example canonical folder from smoke run under:
  - `outputs/canonical/0.3/WP-0.3.1/<run_id>/manifest.yaml`
  - plus `session_info.txt` and at least one synthetic output table/figure

**Stop condition:**
- Acceptance criteria met; Artefact Review Cycle logged; WP checkbox checked; completion record appended below.

**Completion record (append on completion):**
- Completed: 2025-12-20
- Commit: f6c16ae
- Canonical: outputs/canonical/0.3/WP-0.3.1/syn_20251220_180615_0099/
- Notes: Toy-grid canonical smoke run with schema/manifest checks and report output.

---

### WP‑0.3.2 — Synthetic: ideal vs realistic modes (TX_true vs TX_obs) wired end‑to‑end

**Outcome:**  
The synthetic twin pipeline supports two explicit modes that isolate sources of inference error:
- **Ideal mode:** inference on TX_true (algorithm/summary identifiability).
- **Realistic mode:** inference on TX_obs after the observation model + TX estimator (full pipeline distortion).

Both modes produce comparable outputs (posteriors, best-fit TX, summary diagnostics) so we can attribute failure to either algorithmic limits or observation/noise limits.

**Scope:**
- **In:** add mode toggle(s) in config; ensure both modes run end-to-end through screen + ABC; ensure report shows both.
- **Out:** changing the ecological model structure (new mechanisms) beyond what’s needed to define TX_true cleanly.

**Acceptance criteria:**
- Both modes run end-to-end from config to outputs without manual edits.
- For each mode, outputs include at minimum:
  - `theta_star` snapshot used,
  - `screen_results` summary,
  - `abc_posterior` output,
  - TX maps for truth/observed/simulated (as applicable).
- `reports/synthetic_mink_vole.qmd` (or the repo’s synthetic report) contains a clearly labelled section comparing:
  - Ideal vs Realistic recovery behaviour and diagnostics (even if only smoke-run results initially).
- Tests/sanity checks assert:
  - mode selection is respected (ideal mode must not use TX estimator; realistic mode must).

**Artefact evidence:**
- Updated config reference in `docs/config_reference.md` documenting mode key(s).
- Separate output folders or clearly separable outputs per mode (no ambiguity).
- Updated synthetic report rendered in canonical folder for the WP.

**Stop condition:**
- Both modes produce outputs; sanity checks logged; WP marked complete with canonical folder path.

**Completion record (append on completion):**
- Completed: 2025-12-20
- Commit: f6c16ae
- Canonical: outputs/canonical/0.3/WP-0.3.2/syn_20251220_181135_0099/
- Notes: Ideal vs realistic modes wired end-to-end on toy grid with report section.

---

### WP‑0.3.3 — Synthetic: replicated recovery harness + parameter recovery metrics

**Outcome:**  
Synthetic recovery is quantified across replicated synthetic datasets (not a one-off success). The repo produces tables that summarise parameter recovery (bias, MAE, interval coverage) and posterior predictive performance across replicates, separately for ideal and realistic modes.

**Scope:**
- **In:** replicate runner keyed by config; recovery summary tables; minimal plots for recovery; tests for summary shape and NA/degeneracy.
- **Out:** full “power surface” exploration (handled in WP‑0.3.6).

**Acceptance criteria:**
- Config supports a replicate count `R` and seed control for replicates.
- Running the synthetic recovery target(s) produces, for each mode:
  - replicate-level diagnostics table (one row per replicate),
  - parameter recovery table (one row per parameter summarising bias/coverage across replicates).
- Parameter recovery table includes at minimum:
  - bias (absolute and relative where applicable),
  - MAE (or MARE),
  - interval coverage at 50/80/95%,
  - posterior vs prior spread (a shrinkage metric).
- At least one test ensures:
  - required columns exist,
  - there are no all-NA or all-zero summary vectors,
  - replicate count matches config.

**Artefact evidence:**
- `outputs/synthetic/recovery/<mode>/replicate_metrics.csv` (or equivalent)
- `outputs/synthetic/recovery/<mode>/parameter_recovery.csv` (or equivalent)
- Canonical folder containing the above plus a rendered synthetic report section showing recovery summaries.

**Stop condition:**
- Replicated recovery tables exist for both modes; tests pass; review notes logged.

**Completion record (append on completion):**
- Completed: 2025-12-20
- Commit: f6c16ae
- Canonical: outputs/canonical/0.3/WP-0.3.3/syn_20251220_182102_0099/
- Notes: Replicated recovery tables (R=10) with accepted draws and summary plots.

---

### WP‑0.3.4 — Synthetic: summary/loss alignment + regression tests

**Outcome:**  
The synthetic inference summaries and the real-data loss components are aligned (consistent definitions, sign conventions, and breakpoints). Shared helper logic prevents divergence. Regression tests lock in key invariants so later refactors don’t silently change scientific meaning.

**Scope:**
- **In:** unify/align definitions of lag, coverage curve breakpoints, anisotropy/orientation metrics; add regression tests for these invariants.
- **Out:** changing the scientific target itself (e.g., redefining extirpation timing) without a documented decision.

**Acceptance criteria:**
- Synthetic summary vector used for ABC includes the same families of quantities used in real-data scoring:
  - R², lag (same sign convention), coverage, coverage-curve terms, anisotropy/orientation where used.
- Coverage-curve breakpoints are defined in one place and reused (synthetic + real).
- Regression tests exist that:
  - fail if lag sign convention flips,
  - fail if coverage curve breakpoints drift,
  - fail if summary vector changes dimension without schema bump.

**Artefact evidence:**
- Updated `docs/schema.md` documenting summary vector schema (names, meaning, scaling expectations).
- Test output showing new regression tests running in CI/test suite.
- Canonical folder with a smoke-run verifying alignment (tables/plots).

**Stop condition:**
- Alignment achieved, tests in place, and logged sanity inspection notes confirm no unintended flips/drift.

**Completion record (append on completion):**
- Completed: 2025-12-20
- Commit: f6c16ae
- Canonical: outputs/canonical/0.3/WP-0.3.4/syn_20251220_181700_0099/
- Notes: Summary/loss alignment enforced with regression tests and schema doc update.

---

### **WP‑0.3.4b — GB‑scale preflight budget check (single‑replicate, realistic mode, real RSS)**

**Acceptance criteria (black‑and‑white):**

Before Codex is allowed to run WP‑0.3.5 on the British Isles grid:

1. **Run one medium “realistic-mode” synthetic build** (includes observation generation + TX estimator) under `/usr/bin/time -v` (or equivalent) and record *peak RSS* and wall time in a **perf log (not canonical)**.
2. **Prove we are not saving explosive objects** in canonical artefacts:

   * No per-cell-year “counts tables” saved for full runs unless explicitly requested.
   * No full 3‑D `N[x,y,t]` arrays written to disk in canonical output.
3. **Budget sanity:** declare the projected runtime for the full GB run *before* starting it (based on measured medium + cell/year scaling). If the projection is ugly, you don’t run—period.

4. Run **one** GB‑geometry synthetic replicate in **realistic** mode (sim + obs + TX estimator), with canonical output enabled, and measure via `/usr/bin/time -v` (or equivalent):

  * wall clock time,
  * **true peak RSS** (use “Maximum resident set size (KB)”).
  Record these numbers in the **canonical manifest** (e.g., `wall_sec`, `max_rss_kb`).
5. Write the measured budgets into `docs/decisions.md` (Performance Budget) and link the canonical folder.
6. If the single‑replicate runtime implies WP‑0.3.5 will exceed your acceptable walltime (given planned replicates and ABC sims), the roadmap halts and you do *targeted* optimisation (not hand‑waving).

**Completion record (append on completion):**
- Completed: 2025-12-20
- Commit: f6c16ae
- Canonical: outputs/canonical/0.3/WP-0.3.4b/syn_20251220_164636_0099/
- Notes: GB realistic preflight timed with `/usr/bin/time -v`; budgets logged in decisions. Full‑pipeline counts preflight (screen + ABC + report, crop enabled) recorded on 2025‑12‑21: `outputs/canonical/0.3/WP-0.3.4b/preflight_full_counts_20251221_142443/` with wall ≈ 3:01, max RSS ≈ 1.2 GB.

---

### **WP‑0.3.4.1 — Pilot: mask‑consistent summaries + tests**

**Outcome:** Synthetic summaries are computed over a single, consistent analysis
domain (mask applied identically for observed and simulated summaries), and
summary outputs report explicit counts of valid pairs.

**Scope:**
- **In:** apply mask to `T_P` (and any denominator) in all summary/score paths;
  add `n_mask`, `n_TP_finite`, `n_pairs`, `n_TX_true`, `n_TX_obs` to
  `summary_obs.csv`, `screen_results.csv`, and `replicate_metrics.csv`.
- **Out:** changing summary definitions beyond mask/denominator consistency.

**Acceptance criteria:**
- Observed summary and simulated summary agree on denominators under mask.
- Unit test fails if `summary_obs` uses unmasked `T_P` while simulations use
  masked `T_P`.
- Pilot summaries include the new count fields.

**Artefact evidence:**
- Updated `outputs/synthetic/*/summary_obs.csv` with count fields.
- New regression test covering masked/unmasked mismatch.

**Stop condition:**
- Tests pass and pilot summaries no longer show near‑zero coverage due solely to
  denominator mismatch.

**Completion record (append on completion):**
- Completed: 2025-12-21
- Commit: 73bec4f
- Canonical: outputs/canonical/0.3/WP-0.3.4.1/wp0341_manifest_20251221_202507/

---

### **WP‑0.3.4.2 — Pilot: arrival‑surface diagnostics + override switch**

**Outcome:** We can diagnose arrival‑surface sparsity and, for pilot runs,
override arrivals with a complete synthetic surface.

**Scope:**
- **In:** add `arrival_source = real | synthetic_plane | synthetic_gradient` for
  pilot grid; record fraction finite arrivals overall and within mask; save
  arrival plots (real vs override).
- **Out:** modifying the real GB arrival construction itself.

**Acceptance criteria:**
- Diagnostics report `frac_finite_TP` overall and within mask.
- Override modes produce `frac_finite_TP_in_mask ≥ 0.90`.
- Plots of arrival surfaces saved.

**Artefact evidence:**
- `outputs/synthetic/pilot_diagnostics.csv` (or equivalent).
- Arrival plots saved under `outputs/synthetic/`.

**Stop condition:**
- We can attribute pilot coverage failure to arrival sparsity vs other causes.

**Completion record (append on completion):**
- Completed: 2025-12-21
- Commit: 9eb4ae1
- Artefacts: outputs/synthetic/pilot_diagnostics.csv; outputs/synthetic/arrival_real.png; outputs/synthetic/arrival_synthetic_plane.png; outputs/synthetic/arrival_synthetic_gradient.png

---

### **WP‑0.3.4.3 — Pilot: truth viability sweep (TX coverage tuning)**

**Outcome:** `theta_star` is chosen because it yields an informative TX pattern
on the pilot grid, not by guesswork.

**Scope:**
- **In:** small sweep over 1–2 predation strength knobs (e.g., `pred_scale`,
  `pred_c`) using TX‑only streaming; record `coverage_true`, `n_TX_true`,
  temporal spread.
- **Out:** broad multi‑parameter calibration or full ABC sweeps.

**Acceptance criteria:**
- Sweep outputs include coverage and temporal spread metrics.
- Selected `theta_star` yields either `n_TX_true ≥ 50` **or**
  coverage in `[0.10, 0.80]` within mask and finite arrivals.
- Decision recorded in `docs/decisions.md`.

**Artefact evidence:**
- `outputs/synthetic/viability_sweep.csv`
- `outputs/synthetic/viability_sweep_plot.png`

**Stop condition:**
- Pilot truth is demonstrably non‑degenerate.

**Completion record (append on completion):**
- Completed: 2025-12-21
- Commit: TBD
- Artefacts: outputs/synthetic/viability_sweep.csv; outputs/synthetic/viability_sweep_plot.png

---

### **WP‑0.3.4.4 — Pilot: re‑run recovery + enforce identifiability gates**

**Outcome:** Pilot recovery is meaningful and passes explicit gates before any
full GB benchmark run.

**Pilot gates (G1–G5):**
- **G1 Arrival coverage:** `frac_finite_TP_in_mask ≥ 0.90`.
- **G2 TX_true coverage:** `n_TX_true ≥ 50` **or** coverage in `[0.10, 0.80]`.
- **G3 TX_obs signal:** `n_TX_obs ≥ 30` **or** coverage_obs ≥ 0.05; at least
  3 geometry summaries are finite.
- **G4 Coverage curve:** at least 2 breakpoints with coverage strictly between
  0 and 1.
- **G5 Screen/ABC non‑vacuous:** ≥1 compatible draw; ABC acceptance fraction
  < 0.20 unless explicitly relaxed for debugging.

**Acceptance criteria:**
- All gates pass and are reported in the pilot report/log.
- If any gate fails, pipeline stops after diagnostics (no ABC).

**Artefact evidence:**
- Updated pilot report (gates printed explicitly).
- `replicate_metrics.csv` shows finite r²/lag/coverage for both modes.

**Stop condition:**
- Pilot is demonstrably identifiable; WP‑0.3.5 full run is allowed.

**Completion record (append on completion):**
- Completed: 2025-12-23
- Commit: TBD
- Artefacts: outputs/synthetic/recovery/pilot_gates.csv; outputs/synthetic/recovery/realistic/replicate_metrics.csv; outputs/synthetic/recovery/ideal/replicate_metrics.csv; reports/synthetic_mink_vole.{html,pdf}
- Notes: Pilot gates pass for both modes with TX-quantile coverage breaks and mode-specific ABC eps; screen/ABC now non-vacuous.

---

### WP‑0.3.5 (LARGE) — Synthetic: canonical recovery run (R≥20) + benchmark gates

**Outcome:**  
A canonical, replicated benchmark run is produced (ideal + realistic), with explicit gates that must pass before we trust real-data conclusions. If gates fail, the failure is documented and the roadmap must halt for PI review.

**Scope:**
- **In:** run R≥20 replicates per mode; generate canonical artefacts; evaluate benchmark gates; update synthetic report accordingly.
- **Out:** expanding to new mechanisms (habitat, stochastic metapopulation) — not until synthetic benchmark is stable.

**Acceptance criteria (benchmark gates):**
- A canonical run folder exists for the benchmark and contains:
  - all recovery tables,
  - report render,
  - manifest + session info,
  - key figures (TX maps, coverage curves, recovery plots).
- **Ideal mode gates (must pass):**
  - key parameters (at minimum `alpha`, `disp_mean_km`) show:
    - median relative bias |bias| ≤ 0.20, and
    - 80% interval coverage ≥ 0.60 across replicates.
- **Realistic mode gates (must pass):**
  - posterior predictive performance across replicates shows:
    - median lag_mean is positive and within configured plausible bounds, and
    - median R²(TX_sim vs TX_obs) ≥ 0.50 (or a documented, justified alternative threshold).
- If any gate fails:
  - WP is **not** marked complete,
  - Codex must stop and trigger a PI review gate (Section 5) with a failure report.

**Artefact evidence:**
- Canonical benchmark folder:
  - `outputs/canonical/0.3/WP-0.3.5/<run_id>/...`
- Recovery tables for both modes under `outputs/synthetic/recovery/`.

**Pilot run (not a completion):**
- 2025‑12‑21: `outputs/canonical/0.3/WP-0.3.5/wp035_pilot_20251221_161039/`
  (3 reps, draws=16, abc_n=500, crop=TRUE; runtime ~1h14m, RSS ~1.3 GB).
- Synthetic report updated to include:
  - recovery tables,
  - gate results,
  - concise interpretive summary.

**Stop condition:**
- Gates pass and are logged **OR** gates fail and a PI review ZIP is requested (do not proceed).

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.3/WP-0.3.5/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.3.6 — Synthetic: identifiability stress mini‑sweep + failure regime artefacts

**Outcome:**  
We characterise when recovery breaks (failure regimes) under controlled perturbations of observation noise and key ecological parameters. This yields a small but defensible “power/identifiability” figure/table that we can cite when interpreting the real mink→vole failure/success.

**Scope:**
- **In:** a small, explicitly defined stress grid (not huge) over 2–3 key axes (e.g., PO rate / effort bias, dispersal, front strength); recovery summary; plots/tables.
- **Out:** a full-scale global sensitivity analysis (already exists elsewhere; this is synthetic twin–specific).

**Acceptance criteria:**
- Stress grid is documented in `docs/config_reference.md` (exact axes and levels).
- Outputs include:
  - a single tidy table describing each stress scenario and its recovery gate outcomes,
  - at least one figure that makes failure regimes obvious (e.g., heatmap of gate pass rate).
- The synthetic report includes a “Failure regimes” section that states:
  - which axes destroy identifiability,
  - which metrics degrade first (lag, coverage, geometry, etc.).

**Artefact evidence:**
- `outputs/synthetic/stress/` containing:
  - scenario table (CSV),
  - gate pass-rate table (CSV),
  - one or more plots (PNG/PDF).
- Canonical run folder with the above + report render.

**Stop condition:**
- Failure-regime artefacts exist; interpretation notes updated with the key implications for real-data inference.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.3/WP-0.3.6/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.4.1 — Real: representation audit + analysis‑unit selection (meets unit-count gate)

**Outcome:**  
We stop guessing and choose a representation (analysis units + resolution + mask) that yields enough usable units to support inference. The decision is evidence-based and recorded.

**Scope:**
- **In:** audit candidate representations (10 km grid, coarsened grid, segments, different riparian thresholds); compute unit counts and TX_obs availability; select one representation and lock it in config.
- **Out:** running expensive ABC; adding new mechanisms.

**Acceptance criteria:**
- A single “representation audit” table exists comparing candidate representations with at minimum:
  - number of units,
  - number and fraction with TX_obs,
  - effort support proxy (e.g., target-group counts),
  - basic TX_obs plausibility diagnostics (e.g., years spanned).
- Selection gate:
  - chosen representation must have **≥50 usable units** with TX_obs (or a documented alternative threshold with rationale).
- The chosen representation is recorded in:
  - `docs/decisions.md` (with rationale),
  - and `docs/log/`.

**Artefact evidence:**
- `outputs/realdata/representation_audit.csv` (or equivalent)
- At least one map/plot per candidate class (coarse, segment) showing where units exist and where TX_obs exists.
- Canonical folder containing the audit outputs and a brief sanity note.

**Stop condition:**
- One representation selected and documented; audit artefacts exist; WP marked complete.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.4/WP-0.4.1/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.4.2 — Real: δ regularisation + (optional) pred_scale random effects ablation decision

**Outcome:**  
We confirm (and if necessary repair) the constraints that prevent δ from “solving everything” by flattening spatial structure, and we evaluate whether mild spatial random effects on predation scale improve fit without turning the model into a garbage vacuum cleaner.

**Scope:**
- **In:** δ bounds + penalty behaviour verified; ablation comparing (a) no RE vs (b) mild RE; decision recorded.
- **Out:** full constrained inference (handled in WP‑0.4.3).

**Acceptance criteria:**
- δ regularisation is explicitly documented in `docs/config_reference.md` (bounds, penalties, interpretation).
- An ablation artefact exists that compares at minimum:
  - (A) δ regularisation only
  - (B) δ regularisation + mild pred_scale RE
  using the same screen size and the same chosen representation.
- Decision recorded in `docs/decisions.md`:
  - whether pred_scale RE stays enabled for the canonical real-data run.

**Artefact evidence:**
- `outputs/realdata/pilot_mink_vole/ablation_delta_re.csv` (or equivalent)
- One figure showing δ distributions and fit metrics under both ablation conditions.
- Canonical folder with ablation outputs + sanity notes.

**Stop condition:**
- Decision made and documented; ablation artefacts exist.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.4/WP-0.4.2/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.4.3 (LARGE) — Real: constrained screen + ABC run + posterior predictive checks

**Outcome:**  
We execute the best-possible constrained predation-front inference on real mink→vole data under the selected representation, producing a canonical run with posterior predictive checks. Success or failure is decided against explicit gates.

**Scope:**
- **In:** run screen + ABC under chosen representation and chosen δ/RE settings; generate posterior predictive maps and coverage curves; evaluate gates.
- **Out:** adding habitat mechanism or other new processes (that would be a new milestone/roadmap).

**Acceptance criteria (gates):**
- A canonical run folder exists containing:
  - screen results table,
  - ABC posterior samples,
  - posterior predictive TX maps,
  - coverage curves (obs vs posterior envelope),
  - δ diagnostics (values, smoothness/penalty contribution).
- Gate evaluation must be explicit in a table:
  - best draw metrics,
  - and distribution across accepted/posterior draws.
- Minimal performance gates (unless redefined with documented rationale):
  - best draw R² ≥ 0.20,
  - lag_mean within [2, 25] years and positive,
  - coverage_sim ≥ 0.15.
- If gates fail:
  - WP is still “complete” **only** if a structured failure diagnosis is produced (WP‑0.4.4), and the failure is framed as data/model limitation (not hidden).

**Artefact evidence:**
- Canonical folder:
  - `outputs/canonical/0.4/WP-0.4.3/<run_id>/...`
- Updated `reports/pilot_mink_vole.qmd` (or equivalent) rendered into the canonical folder with the new run’s outputs.

**Stop condition:**
- Canonical run and posterior predictive artefacts exist; gates evaluated and logged.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.4/WP-0.4.3/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.4.4 — Real: verdict write‑up (predation-only sufficient vs data/model-limited)

**Outcome:**  
We produce the honest, defensible conclusion for the mink→vole case under the predation-front-only model, grounded in diagnostics and explicitly linked to the synthetic benchmark’s failure regimes.

**Scope:**
- **In:** interpret real-case posterior predictive checks; state verdict; relate to synthetic benchmark limits; document what failure implies (SNR vs missing mechanisms).
- **Out:** implementing new mechanisms (habitat, fires, etc.) — that is future work after review.

**Acceptance criteria:**
- The pilot report contains a “Verdict” section that states, explicitly:
  - whether predation-only passes gates,
  - if not, whether failure is consistent with synthetic failure regimes,
  - what this implies for model adequacy vs data adequacy.
- `docs/interpretation_notes.md` includes:
  - 5–10 blunt bullets summarising what the real-case results mean and do not mean.
- A decision is recorded in `docs/decisions.md` about next scientific stance:
  - either “predation-only supported at this resolution” **or**
  - “predation-only not supported / not identifiable; treat as data-limited or mechanism-incomplete”.

**Artefact evidence:**
- Updated report rendered into canonical folder from WP‑0.4.3.
- Log entry in `docs/log/` referencing key figures/tables used for the verdict.

**Stop condition:**
- Verdict written, documented, and tied to evidence; WP checked.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.4/WP-0.4.4/<run_id>/
- Notes: <1 paragraph>

---

### WP‑0.5.1 — Manuscript scaffold + figure/table manifest pinned to canonical artefacts

**Outcome:**  
A manuscript-ready structure exists in the repo, with a manifest that pins every figure/table to specific canonical run artefacts. This prevents “mystery figures” and forces reproducibility.

**Scope:**
- **In:** create manuscript scaffold; define figure/table list; link each to canonical artefact paths; minimal narrative stubs.
- **Out:** writing full prose (handled in subsequent WPs).

**Acceptance criteria:**
- `manuscript/` exists with a clear structure (text, figures, tables, references).
- A figure/table manifest exists (e.g., `manuscript/figures/manifest.yaml`) listing:
  - figure/table ID,
  - caption stub,
  - canonical artefact source path(s),
  - script/target provenance (high level).
- Manifest includes at minimum:
  - synthetic benchmark key figures,
  - real-case key figures.

**Artefact evidence:**
- Manuscript scaffold committed.
- Manifest file committed and referenced from `README.md` or `docs/plan.md`.

**Stop condition:**
- Scaffold + manifest exist and point to canonical artefacts produced in milestones 0.3 and 0.4.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: (not required; structural WP)
- Notes: <1 paragraph>

---

### WP‑0.5.2 — Methods text: model, observation layer, TX estimator, inference

**Outcome:**  
Methods are written in a form that could go straight into a paper: clear model description, observation model, extirpation estimator definition, summary statistics, and inference approach (screen + ABC), including constraints/regularisation.

**Scope:**
- **In:** methods prose; equations as needed; explicit definitions of TX, TP, P(t), δ, dispersal kernel, and summary vector; reproducibility notes.
- **Out:** speculative discussion or future work.

**Acceptance criteria:**
- Methods text exists in `manuscript/` and covers:
  - process model (demography + dispersal + predation front),
  - observation model + effort normalisation,
  - first-passage TX estimator definition,
  - summary statistics / loss components,
  - inference workflow and regularisation (δ, RE if used),
  - synthetic benchmark design (ideal vs realistic).
- All parameter symbols/units are defined in one place (table or glossary).
- `docs/config_reference.md` updated so config keys map cleanly onto methods terms.

**Artefact evidence:**
- Methods draft file(s) committed.
- A parameter table (CSV/MD) exists in manuscript assets.

**Stop condition:**
- Methods draft complete enough to be reviewed; no dangling “TBD” for core definitions.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: (not required)
- Notes: <1 paragraph>

---

### WP‑0.5.3 — Results package: synthetic recovery benchmark (tables/figs + narrative)

**Outcome:**  
Synthetic benchmark results are presented as a coherent, quantitative story: what recovers, what doesn’t, bias/uncertainty, and failure regimes. This is the credibility engine of the paper.

**Scope:**
- **In:** results text + figures/tables from canonical 0.3 artefacts; explicit gate outcomes; interpretation.
- **Out:** real-case interpretation (handled in WP‑0.5.4).

**Acceptance criteria:**
- Results section includes:
  - recovery summary tables (bias, coverage) for ideal and realistic modes,
  - posterior predictive fit summaries across replicates,
  - failure regime figure/table (from WP‑0.3.6),
  - a short “what this implies for real-data identifiability” paragraph.
- Every figure/table is referenced in the manifest and points to a canonical artefact.

**Artefact evidence:**
- Results text committed.
- Figures/tables copied/linked into manuscript figure/table system with manifest pointers.

**Stop condition:**
- Synthetic results section is internally consistent and fully pinned to canonical artefacts.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.3/...
- Notes: <1 paragraph>

---

### WP‑0.5.4 — Results package: real mink→vole case study verdict (tables/figs + narrative)

**Outcome:**  
Real mink→vole results are written as a clear verdict supported by posterior predictive checks, explicitly conditioned on the synthetic benchmark’s demonstrated capabilities/limits.

**Scope:**
- **In:** real-case results narrative; figures/tables from canonical 0.4 artefacts; honest diagnosis.
- **Out:** adding new mechanisms (habitat etc.) in this paper unless already implemented and justified.

**Acceptance criteria:**
- Results section includes:
  - representation choice and why it meets the unit-count gate,
  - posterior predictive maps and coverage curves,
  - best-fit and posterior distribution metrics (R², lag, coverage),
  - explicit verdict (supported / not identifiable / mechanism incomplete) tied to evidence.
- Every figure/table is referenced in the manifest and points to a canonical artefact.

**Artefact evidence:**
- Results text committed.
- Real-case figures/tables pinned to canonical run artefacts.

**Stop condition:**
- Real-case results section is complete and consistent with WP‑0.4.4 verdict and synthetic benchmark constraints.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.4/...
- Notes: <1 paragraph>

---

### WP‑0.5.5 — Reproducibility + release freeze (paper artefacts reproducible from scratch)

**Outcome:**  
The repo can regenerate the manuscript figures/tables from scratch (within reasonable compute constraints), and the version is frozen with a clear “how to reproduce” contract.

**Scope:**
- **In:** reproducibility entry points; pinned configs; minimal automation; documentation; final checks.
- **Out:** new science.

**Acceptance criteria:**
- A single, documented entry point exists to rebuild:
  - manuscript tables/figures from canonical artefacts, and
  - (where feasible) regenerate those canonical artefacts via targets (or clearly state what is too expensive and how it is cached).
- `README.md` includes a “Reproduce the paper” section with:
  - environment restore,
  - build command(s),
  - where outputs appear.
- A final canonical “release” folder exists:
  - `outputs/canonical/0.5/WP-0.5.5/<run_id>/`
  containing the rendered manuscript (PDF/HTML) and the manifest.

**Artefact evidence:**
- Reproducibility instructions committed.
- Release canonical folder exists and is logged.

**Stop condition:**
- Rebuild succeeds on a clean environment; release artefacts produced; WP checked.

**Completion record (append on completion):**
- Completed: YYYY-MM-DD
- Commit: <sha>
- Canonical: outputs/canonical/0.5/WP-0.5.5/<run_id>/
- Notes: <1 paragraph>

---

## 5) Milestone / review gates (when Codex must stop and request a PI review ZIP)

Codex must stop and request a PI review ZIP in any of the following cases:

1. **After completing Milestone 0.3.x** (all WP‑0.3.* checked):  
   - Stop. Request PI review ZIP. Do not start WP‑0.4.* until reviewed.

2. **After completing Milestone 0.4.x** (all WP‑0.4.* checked):  
   - Stop. Request PI review ZIP. Do not start WP‑0.5.* until reviewed.

3. **Immediately if WP‑0.3.5 benchmark gates fail:**  
   - Stop. Request PI review ZIP with the failure report and canonical artefacts.

4. **After any WP marked (LARGE):**
   - Stop. Request PI review ZIP with canonical artefacts and sanity notes, unless the milestone gate already triggers.

5. **At most every 3 WPs completed (to prevent drift):**
   - If three WPs are completed without a PI review gate being triggered, Codex must stop and request a PI review ZIP anyway.
