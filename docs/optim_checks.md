# Optimisation Checks (for PI review)

Date: 2025-12-20

This note consolidates what we have learned so far about performance, what has
been optimised, and what remains as optional next steps. It is written to
support PI review of the repo and to justify the current runtime budgets and
gates.

---

## Summary diagnosis (root cause of slow runs)

1) The **TX-only simulator is not the bottleneck**. Profiling consistently
   shows the core sim loop is small relative to the observation pipeline.
2) **Observation mapping + I/O were the real culprits**, especially when
   running a non‑toy profile or generating point‑level observations.
3) The earlier 8‑hour “smoke” was not a true smoke test; it triggered a
   full‑scale observation pipeline and heavy I/O.

---

## What was optimised / changed

### 1) Faster TX mapping
- `exdyn_tx_map_fast()` was already in place and used for observation mapping.
- This delivered the previously documented **~4.2× speedup** for the mapping
  stage on toy profiles.

### 2) Counts‑only synthetic observation mode (major win)
Synthetic observation now defaults to **cell‑year counts** (no point‑level PO):
- New functions: `exdyn_presence_only_counts()` and `exdyn_tx_map_counts()`.
- Wired into `exdyn_make_synthetic()` and perf harness.
- Eliminates the “generate points → group_by → reshape” tax.

**Measured effect (direct preflights, sim+obs+TX estimator only):**

Medium (70×70, 1950–2020):
- counts: **29.03 s**, **601,056 kB**
- points: **34.11 s**, **1,098,548 kB**
→ ~**15% faster**, ~**45% lower RSS**

GB (pilot grid, pilot years):
- counts: **311.97 s** (~5.2 min), **6,660,760 kB** (~6.35 GB)
- points: **769.60 s** (~12.8 min), **44,523,724 kB** (~42.5 GB)
→ ~**2.5× faster**, ~**6.7× lower RSS**

These comparisons are recorded in:
- `outputs/perf/preflight_medium_comparison.csv`
- `outputs/perf/preflight_gb_comparison.csv`

### 3) I/O discipline (reference‑rep only)
Heavy artefacts are limited to reference outputs in synthetic runs. Per‑rep
heavy outputs are skipped where not scientifically useful.

---

## Current budgets (for WP‑0.3.5 gate)

**Canonical preflight (old points‑mode pipeline, includes screen/ABC/report):**
- GB realistic preflight: **~43:30** wall, **~41.7 GB RSS**
- Recorded in `outputs/perf/preflight_gb_summary.csv` and canonical manifest.

**Updated counts‑mode preflights (direct sim+obs+TX estimator only):**
- GB counts: **~5.2 min**, **~6.35 GB RSS**

**Interpretation:**
Counts‑only observation removes a major source of cost, but the full synthetic
pipeline (screen/ABC/report) still needs a **new full‑pipeline preflight**
before WP‑0.3.5. We expect a large improvement versus the previous 43:30, but
we have not yet re‑measured it end‑to‑end.

---

## Sanity checks in place

- Perf guardrail test (CI‑safe): `tests/testthat/test_perf_guardrails.R`
- Artefact review cycle logged in `docs/log/030_synthetic_benchmark.md`
- Budget decisions locked in `docs/decisions.md`

---

## Remaining opportunities (not yet executed)

These are **optional** and should be pursued only if the updated full‑pipeline
preflight is still too slow for WP‑0.3.5:

1) **Domain cropping** (tight bounding box of active cells) to avoid FFT over
   ocean/NA grid cells.
2) **Graph/segment representation** for riparian systems (structural speedup).
3) **Avoid storing full 3‑D N[x,y,t] arrays** where not required downstream.
4) **Selective output saving** for screen/ABC stages (already partially done).

---

## Recommended next checks

1) Re‑run **full pipeline** (realistic mode, 1 replicate) with counts‑only
   observation to update the WP‑0.3.5 budget.
2) If that is still too slow, proceed to the structural options above (crop or
   segment graph).

---

## File locations (for verification)

- Preflight logs:
  - `outputs/perf/preflight_medium_counts_time.txt`
  - `outputs/perf/preflight_medium_points_time.txt`
  - `outputs/perf/preflight_gb_counts_time.txt`
  - `outputs/perf/preflight_gb_points_time.txt`
- Comparison tables:
  - `outputs/perf/preflight_medium_comparison.csv`
  - `outputs/perf/preflight_gb_comparison.csv`
- Canonical GB preflight manifest:
  - `outputs/canonical/0.3/WP-0.3.4b/syn_20251220_164636_0099/manifest.yaml`

