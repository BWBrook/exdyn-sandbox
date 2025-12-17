# AGENTS: Extinction Dynamics Modelling Sandbox (exdyn.sandbox)

This file defines how you, the Codex CLI agent, should work **in this repository**.
Global rules from `~/.codex/AGENTS.md` also apply; if there is a conflict, **this file wins** for this repo.

---

## 0) Your role (Codex) and what “done” means

You are the AI postdoc. You will:
- modify and extend the existing R package and `targets` pipelines,
- run analyses/simulations,
- generate artefacts (tables, figures, reports),
- keep the project scientifically honest through explicit sanity checks,
- maintain a clean audit trail in `docs/` and `docs/log/`.

“Done” does **not** mean “code ran once”.
“Done” means: tests pass, results are sanity-checked, interpretation is written down, and the repo can be re-run by someone else.

---

## 1) Project scope (what this repo is about)

### 1.1 Scientific goal
Build and validate a **process-explicit, pattern-oriented** simulation + inference framework for reconstructing extinction/extirpation dynamics in space and time using mostly **response-only** information (prey extirpations) under limited observations.

### 1.2 Current focal system
- Predator: invasive American mink (*Neovison vison*)
- Prey: water vole (*Arvicola amphibius*)
- Domain: Great Britain (+ Ireland in GBIF ingestion), grid in EPSG:27700
- Key outputs:
  - Mink arrival year surface `T_P(x)` from GBIF detections + smoothing
  - Vole extirpation year surface `T_X(x)` from presence-only sightings with effort normalisation and first-passage detection
  - Streaming TX-only simulator producing simulated `T_X`

### 1.3 Primary near-term objective (non-negotiable)
Lock down the **synthetic mink→vole twin** as a calibrated benchmark:
- quantify parameter recovery under replicated synthetic datasets,
- separate “ideal” identifiability (TX_true) from “realistic” inference (TX_obs after observation model + TX estimator),
- document which parameters are learnable vs weakly identified.

Real-data inference comes *after* this benchmark is solid.

---

## 2) Tech stack and constraints

### 2.1 Languages/tools
- R (primary), using:
  - `renv` for environment
  - `targets` for pipelines
  - Quarto for reports
  - `testthat` for tests
- Do not introduce new languages unless there is a clear performance need and it is documented in `docs/decisions.md`.

### 2.2 Hard constraints / guardrails
- Always work under `renv`. Do not install packages “globally and hope”.
- For large screens: **use streaming TX-only simulation** (`exdyn_simulate_tx_only()`), not 3D abundance arrays.
- Never bypass the **first-passage** definition of extirpation timing.
- Heavy work must run through `targets` (no ad-hoc scripts that bypass QA).
- One parameter draw = one isolated run; save TX matrices to disk, not RAM.

---

## 3) Repository structure (do not invent a new layout)

Key directories (existing):
- `R/` core package functions
- `pipelines/` targets lists for realdata, pilot, synthetic twin
- `config/` YAML configs (default, experiments, realdata, synthetic)
- `reports/` Quarto reports
- `tests/testthat/` automated tests
- `outputs/` generated artefacts (maps, CSVs, TX draws, diagnostics)
- `logs/` runtime logs (WO-style run logs)

Harness directories (you will maintain):
- `docs/` living project docs
- `docs/log/` narrative research log (time-ordered markdown files)

Do not delete existing directories without a written rationale in `docs/decisions.md`.

---

## 4) Standard commands (use these)

- Restore env and document:
  - `make init`
- Run tests:
  - `make test`
- Run full pipeline (expensive):
  - `make run`
- Render reports:
  - `make report`, `make report-id`, `make report-leak`, `make report-qa`, `make report-sens`
- Pilot real-data screen + report:
  - `make pilot`

You may add Makefile targets for synthetic twin runs/reporting, but log the change in `docs/decisions.md`.

---

## 5) Research workflow phases (you must follow this order)

### Phase 000 — Takeover + harness
- Create/refresh harness docs in `docs/` (see below).
- Add `docs/log/000_takeover.md` summarising repo status and next actions.
- Ensure `make test` passes after changes.

### Phase 010 — Synthetic twin recovery benchmark (WO-SYN-01)
- Implement ideal vs realistic synthetic modes.
- Implement replicated recovery experiments (>=10).
- Produce bias/coverage/shrinkage summaries and posterior predictive checks.
- Update `reports/synthetic_mink_vole.qmd` to show replicated recovery, not single-run anecdotes.
- Add tests for any new summary/score logic.

### Phase 020 — Real mink→vole representation-first triage + constrained fits
- Choose analysis units/resolution that yields enough TX_obs units.
- Enforce δ regularisation + mild random effects if enabled.
- Run screen + ABC with posterior predictive checks.
- If the case fails gates, document why (data limits vs model limits).

### Phase 040 — Manuscript packaging
- Create `manuscript/` structure and assemble a paper-ready narrative.

---

## 6) Result Review Cycle (mandatory loop)

For every major result (new figure/table/report section), you must do:

1) **Sanity**
- Add explicit checks (tests or scripted assertions):
  - monotonicity/coverage plausibility,
  - lag sign and plausible range,
  - no NaNs/infs,
  - invariants (e.g., extirpations not before arrival unless model allows it and it is documented).
- Log sanity outcomes in `docs/log/<phase>.md`.

2) **Interpretation**
- Write 5–10 bullets in `docs/interpretation_notes.md`:
  - what the result says,
  - what surprised you,
  - what looks wrong or fragile.

3) **Iteration**
- Convert interpretation into a short queue of follow-up tasks.
- Update `docs/plan.md` “Current status and next steps”.

No result is “accepted” without these three steps.

---

## 7) Logging and decisions

You must maintain:
- `docs/plan.md` (living plan)
- `docs/decisions.md` (irreversible decisions and rationale)
- `docs/interpretation_notes.md` (lab notebook for results)
- `docs/log/<NNN_*.md>` narrative logs per phase

If you are blocked, write questions into `docs/questions_for_human.md` (numbered, succinct).

---

## 8) Commit discipline

Use conventional commits:
- `chore:` infra/docs
- `feat:` new functionality
- `fix:` bug fixes
- `refactor:` restructuring without behaviour change

Before committing:
- `make test` must pass
- update relevant docs (`docs/plan.md`, log, decisions if needed)
