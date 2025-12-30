# Roadmap: ExtDyn Modelling Sandbox (work-queue for autonomous runs)

**Purpose:** This roadmap is the execution contract for autonomous Codex CLI runs. It defines the scientific arc of the paper (methods → validation → case study) and the minimum engineering needed to make that arc reproducible and reviewable.

**Last updated:** 2025-12-30

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
1. A **calibrated synthetic benchmark** proving what parameters can/can’t be recovered under known truth (and under realistic arrival/observation constraints).
2. A **real mink→vole case-study verdict** under a constrained predation-front model, explicitly conditioned on the synthetic benchmark.
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
- `docs/config_reference.md` updated to reflect any config keys/meaning changes.
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
  - document the change in `docs/schema.md`,
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
- [x] **WP‑0.2.7 — Large-grid dispersal engine: graph-mode land-only execution path + perf ladder**

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
- [x] **WP‑0.3.4.5 — Arrival realism gate: real arrival vs synthetic override identifiability**
- [ ] **WP‑0.3.4.6 — Masking philosophy gate: hard mask vs soft suitability weighting (pilot + GB sanity)**
- [ ] **WP‑0.3.4.7 — Information-rich synthetic ceiling run (upper bound on identifiability)**
- [ ] **WP‑0.3.4.8 — Pipeline hygiene: eliminate/justify many-to-many join + output freshness guardrails**
- [ ] **WP‑0.3.5a — Canonical synthetic benchmark (pilot grid) using graph-mode, R≥20**
- [ ] **WP‑0.3.5b (LARGE) — Canonical synthetic benchmark (GB grid) using graph-mode, R≥20**
- [ ] **WP‑0.3.6 — Synthetic: identifiability stress mini‑sweep + failure regime artefacts**

### Milestone 0.4.x — Real mink→vole verdict under constrained predation-front model
- [ ] **WP‑0.4.0 — Real-data information audit + “is inference worth attempting?” gate**
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

> Note: Completed WPs keep their original definitions but may have brief “Status” lines pointing to the evidence. New WPs are specified fully below.

---

### WP‑0.2.7 — Large-grid dispersal engine: graph-mode land-only execution path + perf ladder

**Outcome:**  
Large sparse grids (GB/IE) no longer pay an ocean-tax. A graph-mode dispersal engine (land-only adjacency) is implemented and used in performance ladders and synthetic pilot workflows. Performance ladder artefacts make scaling predictable.

**Scope (in/out):**
- **In:** graph-mode dispersal plan + execution; logged graph size; perf ladder staging; budgets updated for graph-mode; parity tests on small grids.
- **Out:** changing ecological meaning of dispersal kernels (only implementation changes).

**Acceptance criteria:**
- A graph-mode dispersal engine exists and can be selected explicitly via config/env.
- Large-grid profiles default to graph-mode (or auto-select with explicit log output).
- At least one test verifies FFT-mode and graph-mode agree on a small fully-land grid within tolerance.
- Perf ladder artefacts exist showing wall time and RSS at multiple sizes.

**Artefact evidence:**
- `docs/perf_ladder_plan.md` (or equivalent) and at least one ladder log entry in `docs/log/`.
- `outputs/perf/ladder/` staging folders with timing/RSS tables.
- Canonical folder demonstrating a GB preflight in graph-mode.

**Stop condition:**  
Graph-mode is usable, logged, and tested; perf ladder outputs exist; WPs above can proceed without “mystery runs.”

**Status:** Complete — see `docs/log/*perf*`, `outputs/perf/ladder/*`, and GB preflight artefacts (2025‑12‑30).

---

### WP‑0.3.4.5 — Arrival realism gate: real arrival vs synthetic override identifiability

**Outcome:**  
We explicitly quantify how much synthetic recoverability depends on arrival-surface completeness/realism. This prevents “benchmark optimism” that would not hold under the real mink arrival surface (with NA regions).

**Scope:**
- **In:** run matched synthetic recovery comparisons under:
  - `arrival_source = synthetic_plane` (complete, smooth),
  - `arrival_source = real` (as reconstructed; possibly sparse).
- **Out:** new mechanisms, new data sources.

**Acceptance criteria:**
- For pilot grid (and optionally GB), produce a table comparing at minimum:
  - `frac_finite_TP_in_mask`, `n_pairs`,
  - `n_TX_true`, `n_TX_obs`,
  - key summary finiteness rate,
  - recovery bias/coverage for a small replicated run (R≥10).
- A written conclusion exists in `docs/interpretation_notes.md` stating:
  - whether real-arrival sparsity materially reduces identifiability,
  - and how this constrains interpretation of any future real-data inference.
- If `frac_finite_TP_in_mask < 0.9` under real arrivals:
  - document the imputation/smoothing policy (or the decision not to impute) in `docs/decisions.md`.

**Artefact evidence:**
- `outputs/synthetic/arrival_real.png`, `arrival_synthetic_plane.png`, `arrival_synthetic_gradient.png`
- `outputs/synthetic/arrival_realism_comparison.csv` (new)
- Canonical folder with the comparison run.

**Stop condition:**  
We can state, with evidence, whether “real arrival surface sparsity” is a limiting factor and how we will handle it going forward.

**Status:** Complete — 2025‑12‑30  
**Commit:** `f7408c8`  
**Canonical:** `outputs/canonical/0.3/WP-0.3.4.5/syn_20251230_153246_0099/`  
**What changed / learned:** Produced the arrival realism comparison (real vs synthetic-plane) on the pilot grid (R=10). Real arrivals have ~0.41 finite coverage within mask vs ~1.0 for synthetic-plane, and recovery metrics degrade accordingly; this is now treated as a data limitation (not model failure).

---

### WP‑0.3.4.6 — Masking philosophy gate: hard mask vs soft suitability weighting (pilot + GB sanity)

**Outcome:**  
We decide whether a binary riparian mask is scientifically and computationally appropriate at 10 km resolution. If not, we transition to a soft weighting/suitability surface that reduces artificial isolation and improves ecological realism.

**Scope:**
- **In:** implement and compare:
  - hard mask (0/1),
  - soft suitability weighting (continuous; e.g., scaling K or predation scale by river_km or suitability proxy).
- **Out:** external habitat datasets (this is about representation, not new covariates).

**Acceptance criteria:**
- Provide a comparative run on the pilot grid (and a small GB sanity run) showing:
  - resulting connectivity (effective dispersal), coverage_true, lag, and geometry summaries,
  - whether TX_true becomes less degenerate under the same theta_star.
- Record a decision in `docs/decisions.md`:
  - keep hard mask, or adopt soft weighting,
  - with rationale and implications for real-data interpretation.

**Artefact evidence:**
- `outputs/synthetic/mask_philosophy_compare.csv` (new)
- at least one pair of TX_true plots (hard vs soft) saved to `outputs/synthetic/`.

**Stop condition:**  
A single masking philosophy is chosen and documented; subsequent WPs use it consistently.

---

### WP‑0.3.4.7 — Information-rich synthetic ceiling run (upper bound on identifiability)

**Outcome:**  
We establish an upper bound: what the inference could achieve if observations were not limiting. This creates a reference point when real arrivals/observations produce weak recovery.

**Scope:**
- **In:** run a synthetic scenario with richer observations (higher po_rate / lower dropout / lower noise) while keeping process model unchanged.
- **Out:** changing model structure.

**Acceptance criteria:**
- A “ceiling” configuration is documented and run (pilot grid, R≥10).
- Produce a concise table:
  - recovery bias/coverage under ceiling vs baseline realistic,
  - posterior predictive fit metrics (R², lag, coverage curve RMSE).
- Interpretation note explicitly states:
  - whether the pipeline is algorithmically capable under high information,
  - and therefore whether later failures are information-limited.

**Artefact evidence:**
- `outputs/synthetic/ceiling_run_summary.csv` (new)
- one plot comparing baseline vs ceiling recovery (new)
- canonical folder containing the ceiling run.

**Stop condition:**  
Ceiling results exist and are referenced as the “best possible” bound for later interpretation.

---

### WP‑0.3.4.8 — Pipeline hygiene: eliminate/justify many-to-many join + output freshness guardrails

**Outcome:**  
Residual pipeline fragility is removed so runs are deterministic and warnings are meaningful. Output staleness is prevented for key artefacts (e.g., viability sweep CSVs).

**Scope:**
- **In:** investigate and resolve (or justify) many-to-many join warnings; ensure key outputs are rebuilt when upstream config changes; add guardrails/tests.
- **Out:** broad refactors unrelated to determinism.

**Acceptance criteria:**
- The many-to-many join warning is either:
  - eliminated by fixing duplicated keys, or
  - explicitly justified and silenced with a guard (with a doc note explaining why it is safe).
- Add at least one guardrail that fails if:
  - viability sweep or arrival plots are older than the config snapshot that produced them (or equivalent determinism check).
- Document the final stance in `docs/decisions.md`.

**Artefact evidence:**
- A log entry describing root cause and fix.
- Test(s) that would fail on reintroduction of the issue.

**Stop condition:**  
No recurring join warning in canonical synthetic runs; key outputs are not stale by accident.

---

### WP‑0.3.5a — Canonical synthetic benchmark (pilot grid) using graph-mode, R≥20

**Outcome:**  
A fully canonical, replicated benchmark exists on the pilot grid. This locks down end-to-end recovery (ideal + realistic) under stable, controllable conditions with graph-mode dispersal and the chosen arrival/mask philosophy.

**Scope:**
- **In:** run R≥20 replicates for both ideal and realistic modes; compute recovery bias/coverage; posterior predictive checks; canonical folder.
- **Out:** GB-scale benchmark (next WP).

**Acceptance criteria (benchmark gates):**
- Canonical folder exists containing:
  - parameter recovery tables (bias + interval coverage),
  - replicate-level predictive metrics,
  - key plots: arrival, TX_true/TX_obs, best, diff, coverage curves.
- Ideal mode gates must pass:
  - core parameters (at minimum `alpha`, `disp_mean_km`) have median |relative bias| ≤ 0.20 and 80% interval coverage ≥ 0.60.
- Realistic mode gates must pass:
  - median lag_mean positive and within declared bounds,
  - median R²(TX_sim vs TX_obs) ≥ 0.50 (or a documented threshold with rationale).
- If gates fail:
  - WP is not marked complete; codex stops and requests PI review ZIP.

**Artefact evidence:**
- canonical folder: `outputs/canonical/0.3/WP-0.3.5a/<run_id>/...`
- updated synthetic report referencing this run.

**Stop condition:**  
Pilot benchmark gates pass, or failure is documented and escalated for PI review.

---

### WP‑0.3.5b (LARGE) — Canonical synthetic benchmark (GB grid) using graph-mode, R≥20

**Outcome:**  
A canonical GB-scale benchmark exists with the same reporting and gates, using graph-mode dispersal and the chosen arrival/mask philosophy. This is the principal synthetic validation run we will cite.

**Scope:**
- **In:** GB grid, R≥20 replicates; ideal + realistic modes; canonical artefacts and report.
- **Out:** expanding parameter set or adding new mechanisms.

**Acceptance criteria (hard pre-run budget gate):**
- Before starting:
  - record a budget estimate based on a single-replicate GB preflight under the same settings.
- After run:
  - canonical folder exists with the same outputs as WP‑0.3.5a.
  - If runtime or RSS exceeds declared budgets by >2×, document why and update budgets/decisions.

**Benchmark gates:**
- Same as WP‑0.3.5a, plus:
  - report `frac_finite_TP_in_mask` and `n_pairs` for real arrivals (if used); if insufficient, document and (if appropriate) use imputed arrival for benchmark honesty with a clear decision.

**Artefact evidence:**
- `outputs/canonical/0.3/WP-0.3.5b/<run_id>/...`
- updated synthetic report pinned to this canonical run.

**Stop condition:**  
GB benchmark gates pass, or the failure is documented and escalated for PI review ZIP.

---

### WP‑0.3.6 — Synthetic: identifiability stress mini‑sweep + failure regime artefacts

**Outcome:**  
A small, explicit stress grid shows when recovery breaks (failure regimes) under changes in information content and key dynamics. This becomes the “why real data may fail” figure/table.

**Scope:**
- **In:** a small, named stress grid over 2–3 axes (e.g., observation intensity, arrival sparsity, dispersal scale), with R≥10 per cell if feasible.
- **Out:** a giant global sensitivity analysis.

**Acceptance criteria:**
- Stress grid is documented (exact axes and levels) in `docs/config_reference.md`.
- Outputs include:
  - scenario table (CSV),
  - gate pass-rate table (CSV),
  - one clear plot (e.g., heatmap) showing failure regimes.
- A report section states, plainly:
  - which axes destroy identifiability and which metrics degrade first.

**Artefact evidence:**
- `outputs/synthetic/stress/` with tables and plots
- canonical folder containing run outputs and report render.

**Stop condition:**  
Failure regimes are explicit, reproducible, and interpretable.

---

### WP‑0.4.0 — Real-data information audit + “is inference worth attempting?” gate

**Outcome:**  
Before spending time on real-data inference, we quantify whether the real dataset has enough information content (TX_obs density, arrival coverage, overlap) to support any meaningful inference at the chosen representation.

**Scope:**
- **In:** compute counts and overlaps on real data products already in the repo.
- **Out:** re-running full inference.

**Acceptance criteria:**
- Produce an audit table reporting at minimum:
  - number of analysis units,
  - `n_TX_obs`, `coverage_obs`,
  - `frac_finite_TP_in_mask` (or overlap metric),
  - `n_pairs` (TX_obs finite & TP finite & in mask),
  - basic effort support proxies.
- Record a decision:
  - proceed to real inference, or
  - formally record that inference is underpowered at current representation (and specify what would need to change: coarsen grid, relax mask, etc.).

**Artefact evidence:**
- `outputs/realdata/information_audit.csv`
- a short report section or markdown note summarising conclusions.

**Stop condition:**  
A go/no-go decision exists, grounded in numbers.

---

## 5) Milestone / review gates (when Codex must stop and request a PI review ZIP)

Codex must stop and request a PI review ZIP in any of the following cases:

1. **After completing Milestone 0.3.x** (all WP‑0.3.* checked):  
   - Stop. Request PI review ZIP. Do not start WP‑0.4.* until reviewed.

2. **After completing Milestone 0.4.x** (all WP‑0.4.* checked):  
   - Stop. Request PI review ZIP. Do not start WP‑0.5.* until reviewed.

3. **Immediately if any benchmark gates fail in WP‑0.3.5a or WP‑0.3.5b:**  
   - Stop. Request PI review ZIP with the failure report and canonical artefacts.

4. **After any WP marked (LARGE):**
   - Stop. Request PI review ZIP with canonical artefacts and sanity notes, unless the milestone gate already triggers.

5. **At most every 3 WPs completed (to prevent drift):**
   - If three WPs are completed without a PI review gate being triggered, Codex must stop and request a PI review ZIP anyway.

---

## Appendix: Notes on “why these new WPs exist”

- The graph-mode dispersal path is now the key enabler for GB-scale iteration. The roadmap therefore treats “mode logging + parity tests + perf ladder evidence” as part of scientific reproducibility.
- The new 0.3.4.5–0.3.4.7 gates exist to prevent a known trap: “synthetic optimism” that disappears under sparse real arrival surfaces or overly harsh binary masks.
- The new 0.4.0 audit exists to prevent another trap: spending days on real ABC runs that are intrinsically underpowered due to tiny overlap between TX_obs and TP.
