# Performance Ladder Plan (Toy → Small → Medium)

This checklist drives the modular performance profiling ladder. Each box should be ticked only after the runtime and RSS numbers are recorded in the lab notes, with artefacts saved to `outputs/perf/ladder/`.

## Stage A — Core TX-only simulation (no obs, no summaries)
- [x] Toy (15×15, 2000–2020, reps 1–3)
- [x] Small (30×30, 2000–2019, reps 1–3)
- [x] Medium (60×60, 2000–2019, reps 1–3)
- [x] Parallel throughput check (toy, reps 3, 3 cores)
- [x] Parallel throughput check (toy, reps 25, 25 cores + RSS sampler)
- [x] Parallel throughput check (small, reps 25, 25 cores + PSS sampler)

## Stage B — Observation layer only (counts vs points)
- [x] Toy: counts only
- [x] Toy: points only
- [x] Small: counts only
- [x] Small: points only
- [x] Medium: counts only
- [x] Medium: points only

## Stage C — Summaries only (single run, no screen/ABC)
- [x] Toy
- [x] Small
- [x] Medium

## Stage D — Screening loop only (minimal n_draws)
- [x] Toy (n_draws 8–16)
- [x] Small (n_draws 8–16)
- [x] Medium (n_draws 8–16)

## Stage E — ABC loop only (minimal n_sims)
- [x] Toy (n_sims 100–200, single mode)
- [x] Small (n_sims 100–200, single mode)
- [x] Medium (n_sims 100–200, single mode)

## Stage F — Full end-to-end pipeline (toy + small + medium)
- [x] Toy (counts + summary + screen + ABC)
- [x] Small (counts + summary + screen + ABC)
- [x] Medium (counts + summary + screen + ABC)

## Required logging for every step
- [ ] `/usr/bin/time -v` wall time + max RSS recorded
- [ ] `outputs/perf/ladder/` contains CSV row for the step
- [ ] Lab notes updated in `docs/log/031_perf_ladder.md`

---

## Temporal scaling (60-year span, 2000–2059)
- [x] Toy 15×15 — Stage A–F (single rep)
- [x] Small 30×30 — Stage A–F (single rep)
- [x] Medium 60×60 — Stage A–F (single rep)

---

## GB+IE pilot grid (cropped to riparian mask, 1950–2024)
- [x] Stage A (TX-only, cropped)
- [x] Stage B1 (counts-only obs, cropped)
- [x] Stage B2 (points-only obs, cropped)
- [x] Stage C (summaries only, cropped)
- [x] Stage D (screen only, cropped)
- [x] Stage E (ABC only, cropped)
- [x] Stage F (full pipeline, cropped)

---

## GB+IE pilot grid (land mask + soft suitability, full land crop)
- [x] Stage A (TX-only, land mask + soft suitability)
- [x] Stage B1 (counts-only obs, land mask + soft suitability)
- [x] Stage B2 (points-only obs, land mask + soft suitability)
- [x] Stage C (summaries only, land mask + soft suitability)
- [x] Stage D (screen only, land mask + soft suitability)
- [ ] Stage E (ABC only, land mask + soft suitability)
- [ ] Stage F (full pipeline, land mask + soft suitability)

---

## GB+IE pilot grid (land mask + soft suitability, tight crop)
- [x] Stage A (TX-only, tight crop)
- [x] Stage B1 (counts-only obs, tight crop)
- [x] Stage B2 (points-only obs, tight crop)
- [x] Stage C (summaries only, tight crop)
- [x] Stage D (screen only, tight crop)

---

## GB+IE pilot grid (land-cell graph dispersal prototype)
- [x] Stage A (TX-only, graph)
- [x] Stage B1 (counts-only obs, graph)
- [x] Stage B2 (points-only obs; 3‑D arrays)
- [x] Stage C (summaries only, graph)
- [x] Stage D (screen only, graph)
- [x] Stage E (ABC only, graph)
- [x] Stage F (full pipeline, graph)

---

## Graph parallel runner (optional, screen + ABC)
- [x] Parallel runner script created
- [x] Example run logged (workers=8, draws=64, sims=200)
