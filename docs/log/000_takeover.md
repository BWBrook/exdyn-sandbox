# Phase 000 — Takeover log (Codex / AI postdoc)

**Date:** 2025-12-17  
**Repo:** `exdyn-sandbox` (R package + `targets` pipelines)  
**Purpose of this log:** establish an accurate baseline of what the repo currently is, what works, what is missing, and the Phase 000–040 roadmap we will follow to advance the project.

---

## 1) What this repo is (current truth)

This repository is a modelling + inference sandbox for **pattern-oriented spatial extinction/extirpation dynamics**, currently focused on the **mink → water vole** system in Great Britain (BNG / EPSG:27700). The intended workflow is:

1. Build / ingest a predator arrival-time surface `T_P(x)` (mink) from presence data.
2. Reconstruct prey extirpation timing `T_X_obs(x)` (water vole) from presence-only sightings using a **first-passage** estimator.
3. Use a streaming simulator (`TX`-only) to generate simulated extirpation surfaces `T_X_sim(x)` under a mink-front model.
4. Perform **response-only** calibration (screen + ABC) against summaries of `T_X_obs(x)` (and against `T_X_true(x)` in synthetic benchmarking).

The *non-negotiable* near-term objective is to lock down the **synthetic mink→vole twin** as a calibrated benchmark (replicated recovery; ideal vs realistic separation) before making real-data claims.

---

## 2) Repository structure (orientation)

Top-level layout (high-signal folders/files):

- `R/` — core package functions (simulation, observation models, TX estimator, scoring, plotting, helpers).
- `pipelines/` — `targets` target lists, including:
  - real-data GBIF ingestion / arrival surfaces,
  - pilot real mink→vole inference,
  - synthetic mink→vole twin.
- `_targets.R` — the umbrella pipeline that sources the pipeline modules and defines targets.
- `config/` — YAML configs (defaults, experiments, real-data, synthetic).
- `reports/` — Quarto reports (pilot, synthetic, QA/sensitivity).
- `tests/testthat/` — unit tests (`testthat`).
- `outputs/` — persisted artefacts (tables, maps, diagnostics, TX draws).
- `logs/` — runtime logs (WO-style run logs).
- `docs/` — the “AI-for-Science harness” (plan, decisions, roadmap, workflow, interpretation notes).

---

## 3) What currently works (credible / already present)

### Core modelling + inference components
- **Streaming TX-only simulation** exists (preferred for large screens; avoids 3D abundance arrays).
- **First-passage definition of extirpation timing** is treated as the standard, both for estimation and synthetic observation layers.
- A **scoring / summary** workflow exists for comparing `T_X` surfaces (geometry + coverage-type diagnostics).
- δ (arrival-time offsets) are supported conceptually and in codepaths, with the project stance that δ must be constrained/regularised.

### Pipelines & reports
- `targets` pipelines exist for:
  - a **real-data pilot** (mink→vole),
  - a **synthetic mink→vole twin** (truth → observation → inference),
  - plus inherited sandbox/experiments tooling.
- Quarto reports exist for:
  - synthetic twin (`reports/synthetic_mink_vole.qmd`),
  - pilot mink→vole (`reports/pilot_mink_vole.qmd`),
  - QA/sensitivity style reports.

### Engineering discipline
- The repo is structured as an R package with `renv` locked dependencies.
- A non-trivial `testthat` suite exists (broadly guarding simulator, summaries, and pipeline invariants).

---

## 4) What is missing / not yet “Phase 010 ready”

### Harness gaps (administrative but important)
- `docs/log/` did not exist initially; Phase 000 requires narrative logs under `docs/log/` (this file begins that series).

### Synthetic benchmark not yet locked (scientific gap)
The synthetic twin demonstrates a plausible “single-run” success case, but **does not yet satisfy benchmark standards**:
- No explicit **ideal vs realistic** mode separation wired end-to-end and tested (TX_true inference vs TX_obs inference).
- No replicated recovery harness (≥10 replicates) with recovery metrics (bias/MAE/coverage/shrinkage).
- No canonical benchmark run (R≥20) with pass/fail gates and failure-regime artefacts.

### Reproducible artefact discipline (roadmap gap)
Roadmap Milestone 0.3.x requires:
- a documented **output schema** (`docs/schema.md`),
- a **config reference** (`docs/config_reference.md`),
- and canonical run folders under `outputs/canonical/...` with a machine-readable `manifest.yaml`.

These are not yet implemented, so later manuscript figures/tables cannot be pinned to an auditable run lineage.

---

## 5) Phase roadmap (000 → 040)

### Phase 000 — Takeover + harness (now)
Goal: ensure the repo is easy to rerun, and that there is an audit trail for subsequent scientific work.

Minimum outputs:
- `docs/log/000_takeover.md` (this file) + ongoing `docs/log/` entries
- README/Make targets aligned with reality
- `make test` passing after changes

### Phase 010 — Synthetic twin recovery benchmark (WO‑SYN‑01)
Goal: lock down what the inference can/cannot learn under known truth.

Deliverables:
- Ideal vs realistic synthetic modes (TX_true vs TX_obs) wired through screen + ABC + reporting
- Replicated recovery (≥10) with bias/coverage/shrinkage summaries
- Posterior predictive checks on geometry + coverage curves
- Clear documentation of weakly identified parameters and failure regimes

### Phase 020 — Real mink→vole triage + constrained fits
Goal: choose a defensible representation (units/resolution) and run constrained inference.

Deliverables:
- Representation audit + analysis-unit selection based on “enough TX_obs units” gate
- δ regularisation (bounds + penalties) + optional mild random effects ablations
- Screen + ABC + posterior predictive checks
- A verdict: predation-only sufficient vs data/model-limited (failure is allowed and must be documented honestly)

### Phase 040 — Manuscript packaging
Goal: make the project “paper-shaped”: reproducible figures/tables/narrative pinned to canonical artefacts.

Deliverables:
- `manuscript/` scaffold
- manuscript-ready methods + results text
- reproducibility checklist / freeze and from-scratch rerun instructions

---

## 6) Immediate next actions (Phase 000 completion)

1. Refresh README so it mentions the mink→vole pilot pipeline and the synthetic twin (without deleting the legacy sandbox description).
2. Add Makefile shortcuts for synthetic twin runs (minimal `make synthetic` target).
3. Run `make test` and fix any breakages.
4. Commit Phase 000 as a single conventional-commit unit, then proceed to Roadmap WP‑0.3.1.

