# ExtDyn Modelling Sandbox — Project Plan (living document)

This plan is maintained as a living research document. It must reflect the *current truth* of the repo: what exists, what is credible, and what is next.

---

## 1) Refined research questions (current scope)

### Q1 — Synthetic twin validation (primary)
Given a known predator arrival geometry and a realistic presence-only observation process, can response-only summaries of prey extirpation timing recover key predator-front parameters (lag, dispersal scale, predation intensity, δ arrival offsets), and with what bias/uncertainty?

### Q2 — Real mink→vole case (secondary)
At the best-supported spatial unit/resolution, is a mink-front-only mechanism sufficient to explain the reconstructed water vole extirpation pattern? If not, is failure due to low signal-to-noise in reconstructed TX patterns or due to missing mechanisms (habitat change / additional threats), or both?

---

## 2) Working hypotheses

- H1 (synthetic): Under realistic observation noise, the pipeline can recover lag and dispersal scale with useful precision and generate posterior predictive TX surfaces that match truth on geometry + coverage curve.
- H2 (synthetic limits): There are identifiable regimes where recovery collapses (e.g., high dispersal, weak predation, extreme observation bias); mapping these regimes is part of validation.
- H3 (real): If real mink→vole fits require implausible δ shifts to pass basic gates, then inference is data-limited and/or predation-only is incomplete at this resolution.

---

## 3) Data sources and artefacts

### 3.1 Data sources
- GBIF occurrences:
  - Mink: *Neovison vison*
  - Water vole: *Arvicola amphibius*
- Rivers/riparian context:
  - OSM rivers (preferred when available) or Natural Earth fallback
- Spatial grid:
  - British National Grid (EPSG:27700), configurable cell size

### 3.2 Key derived artefacts
- `T_P(x)` — predator arrival year surface
- `T_X_obs(x)` — observed extirpation year surface from sightings (first-passage estimator)
- `T_X_true(x)` — latent extirpation year (synthetic twin only)
- Summary vector(s) — response-only front geometry + coverage curve descriptors
- Screen results and ABC posteriors

---

## 4) Current repo status (inherited)

### Strong / credible
- Streaming TX-only simulator exists and is tested.
- TX estimator from presence-only data exists and is tested.
- Targets pipelines for:
  - GBIF arrival maps,
  - real pilot fitting,
  - synthetic mink→vole twin,
  - generic sandbox identifiability experiments.
- Quarto reports exist for synthetic and pilot.
- Test suite is broad and meaningful.

### Known constraints / pain points
- Real mink→vole at `analysis_unit = segment` is currently underpowered (very few usable units/extirpations).
- Synthetic twin currently demonstrates a strong single-case recovery, but lacks replicated recovery quantification and explicit ideal-vs-realistic separation.

---

## 5) Roadmap to “manuscript ready”

| Phase | Name                                     | Goal                                                          | Key deliverables                   | Status    |
| ----: | ---------------------------------------- | ------------------------------------------------------------- | ---------------------------------- | --------- |
|   000 | Takeover + harness                       | Add AI-for-Science harness; standardise logs/entrypoints      | AGENTS + docs + log                | complete  |
|   010 | Synthetic recovery benchmark (WO-SYN-01) | Replicated parameter recovery; ideal vs realistic modes       | recovery tables + updated report   | complete  |
|   020 | Real mink→vole triage + constrained fits | Choose units/resolution; run screen+ABC with δ regularisation | updated pilot report + verdict     | complete* |
|   040 | Manuscript packaging                     | Draft paper with figures/tables from code                     | `manuscript/` + reproduce commands | complete  |

`*` Complete with a data-limited/method-limited verdict under current representation, not a positive predation-only confirmation.

---

## 6) Risks and contingencies (be blunt)

- Real-data inference may remain impossible at current resolution due to low SNR / sparse extirpations.
  - Contingency: publish as “validated method + cautionary case study” and move to Australian systems when curated datasets arrive.
- δ flexibility can “solve everything” by flattening geometry.
  - Contingency: enforce bounds + penalties and treat failure to fit as evidence, not as something to hack around.
- Compute/runtime for replicated ABC may be large.
  - Contingency: keep recovery experiments configurable; run small smoke tests in CI, full runs in batch.

---

## 7) Current status and next steps (to be maintained by Codex)

### Current phase
- Phase 040 — Manuscript-ready package and reproducibility freeze (roadmap closure)

### Recently completed
- 2026-03-08 high-risk semantics redesign: synthetic benchmark/gate semantics are now config-authoritative, ABC requires finite core summaries with explicit optional-metric penalties, the real-data loss is unit-consistent with median timing aggregation, and TX threshold semantics are explicit via `threshold_mode`.
- 2026-03-08 repo hardening + characterization slice: added CI, split bootstrap from maintenance (`make setup` vs `make init`), removed `_targets.R` self-install behavior, replaced live-network GBIF test coverage with fixtures/mocks, added characterization tests for ABC non-finite summaries / real-loss aggregation / parallel determinism, and removed duplicate helper definitions.
- 2026-03-08 reconnaissance + hygiene checkpoint: repo structure revalidated, `main` confirmed aligned with `origin/main` at scout time, and a clean-baseline commit prepared after verification.
- Phase 000 — Takeover + harness (docs + README + Makefile refresh).
- Completed perf profiling + scaling + guardrails + optimisation (WP‑0.2.x).
- Completed WP‑0.3.1 → WP‑0.3.4b (canonical schema, modes, replicated recovery, alignment tests, GB preflight budgets).
- Completed WP‑0.3.4.1 (mask‑consistent summaries with explicit count fields + tests).
- Completed WP‑0.3.4.2 (arrival diagnostics + override switch; pilot arrivals sparse within mask).
- Completed WP‑0.3.4.3 (truth viability sweep; tuned `truth_frac`/`truth_rel0` for pilot grid).
- Completed WP‑0.3.4.4 (pilot recovery gates now pass for ideal+realistic; mode‑specific ABC eps + TX‑quantile coverage breaks).
- Split synthetic pipeline into truth generation (`synthetic_truths`) and mode recovery (`synthetic_mode_runs`) to avoid re-simulating truth when only ABC/screen settings change.
- Performance hardening: vectorised orientation metrics, analytic r²/slope, streaming counts‑mode truth generation.
- Re‑measured GB counts preflight (streaming counts): ~42.5 s wall, ~1.0 GB RSS (pilot grid, direct sim+obs+TX).
- Full‑pipeline counts preflight (screen + ABC + report, pilot grid, crop enabled): ~3:01 wall, ~1.2 GB RSS; canonical size ~192 kB.
- WP‑0.3.5a pilot benchmark (R=20, graph‑mode, synthetic_plane arrivals) completed with canonical artefacts:
  - `outputs/canonical/0.3/WP-0.3.5a/syn_20260208_234611_035a_full_bestfix/`
  - all pilot gates (G1–G5) pass for ideal and realistic modes.
  - realistic predictive medians: `abc_lag_median ≈ 19.19`, `abc_r2_median ≈ 0.633`.
- Added replicate‑level parallelism (`recovery.n_cores`) and improved coverage‑break fallback within TX range.
- Patched `make synthetic` to include `synthetic_canonical_manifest` so canonical packaging is emitted in the default synthetic workflow when enabled.
- WP‑0.3.5b GB benchmark (R=20, graph‑mode, synthetic_plane arrivals) completed with canonical artefacts:
  - `outputs/canonical/0.3/WP-0.3.5b/syn_20260209_134622_035b_full_r20/`
  - all benchmark gates (G1–G5) pass across all replicates for ideal and realistic modes.
  - realistic predictive medians remain above gate thresholds (`abc_lag_median ≈ 19.19`, `abc_r2_median ≈ 0.633`).
  - real-arrival diagnostics retained (`frac_finite_TP_in_mask ≈ 0.41`) for transferability context.
- WP‑0.3.6 stress mini‑sweep completed with canonical artefacts:
  - `outputs/canonical/0.3/WP-0.3.6/syn_20260209_154821_0099/`
  - 12 scenarios (`arrival_source × obs_multiplier × pred_scale_multiplier`, R=10 each).
  - failure regimes are explicit: all `arrival_source=real` scenarios fail all-gate criteria; `G1` and `G5` dominate collapse.
- WP‑0.4.0 → WP‑0.4.4 completed:
  - information/representation audits, ablation, constrained run, posterior predictive outputs, and canonical real-data bundle.
  - canonical run: `outputs/canonical/0.4/WP-0.4.3/real_20260209_171134_7350/`.
  - verdict: constrained predation-only run is data-limited/mechanism-incomplete at current representation.
- WP‑0.5.1 → WP‑0.5.5 completed:
  - manuscript scaffold + section drafts + canonical figure/table manifest linkage.
  - reproducibility checklist and render commands in place.

### Next steps (short queue)
- Next engineering slice should tackle medium-risk boundary cleanup:
  - split `targets_pilot_mink_vole()` into sub-builders,
  - thin report-local analysis code,
  - rationalise shared screen/ABC orchestration between pilot and synthetic paths.
- Regenerate smoke-level synthetic and pilot outputs under schema `0.4.0` before refreshing any canonical benchmark or real-data bundles.
- Decide whether historical canonical runs should remain frozen as pre-0.4 references or be superseded by new semantic-baseline runs.
- Keep visual sanity review as a hard gate for any new canonical run (maps and key summary tables).
