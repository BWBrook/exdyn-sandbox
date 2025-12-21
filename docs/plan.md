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

| Phase | Name                                     | Goal                                                          | Key deliverables                   | Status  |
| ----: | ---------------------------------------- | ------------------------------------------------------------- | ---------------------------------- | ------- |
|   000 | Takeover + harness                       | Add AI-for-Science harness; standardise logs/entrypoints      | AGENTS + docs + log                | pending |
|   010 | Synthetic recovery benchmark (WO-SYN-01) | Replicated parameter recovery; ideal vs realistic modes       | recovery tables + updated report   | pending |
|   020 | Real mink→vole triage + constrained fits | Choose units/resolution; run screen+ABC with δ regularisation | updated pilot report + verdict     | pending |
|   040 | Manuscript packaging                     | Draft paper with figures/tables from code                     | `manuscript/` + reproduce commands | pending |

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
- Phase 030 — Synthetic benchmark lock‑down (WP‑0.3.x)

### Recently completed
- Phase 000 — Takeover + harness (docs + README + Makefile refresh).
- Completed perf profiling + scaling + guardrails + optimisation (WP‑0.2.x).
- Completed WP‑0.3.1 → WP‑0.3.4b (canonical schema, modes, replicated recovery, alignment tests, GB preflight budgets).
- Completed WP‑0.3.4.1 (mask‑consistent summaries with explicit count fields + tests).
- Performance hardening: vectorised orientation metrics, analytic r²/slope, streaming counts‑mode truth generation.
- Re‑measured GB counts preflight (streaming counts): ~42.5 s wall, ~1.0 GB RSS (pilot grid, direct sim+obs+TX).
- Full‑pipeline counts preflight (screen + ABC + report, pilot grid, crop enabled): ~3:01 wall, ~1.2 GB RSS; canonical size ~192 kB.
- WP‑0.3.5 pilot‑scale run (3 reps, ideal+realistic, counts, pilot grid): ~1h14m wall, ~1.3 GB RSS; coverage metrics degenerate due to sparse TX.

### Next steps (short queue)
- Decide whether WP‑0.3.5 is green‑lit given the pilot‑scale WP‑0.3.5 run and planned ABC draw counts.
- Run WP‑0.3.4.2 arrival‑surface diagnostics + override switch (pilot grid).
- Run WP‑0.3.4.3 truth viability sweep to tune `theta_star` coverage on pilot grid.
- Run WP‑0.3.4.4 pilot recovery with identifiability gates before resuming WP‑0.3.5.
