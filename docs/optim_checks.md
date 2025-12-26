# Optimisation Checks (for PI review)

Date: 2025-12-21

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
- `outputs/perf/preflight/medium/preflight_medium_comparison.csv`
- `outputs/perf/preflight/gb/preflight_gb_comparison.csv`

### 3) I/O discipline (reference‑rep only)
Heavy artefacts are limited to reference outputs in synthetic runs. Per‑rep
heavy outputs are skipped where not scientifically useful.

### 4) Summary hot‑path trimming
- `exdyn_orientation_metrics()` now uses a fully vectorised Sobel gradient.
- `lm()` calls in summary/score hot paths replaced with analytic r² and slope.
- Behaviour verified against the previous implementations on toy tests.

### 5) Streaming counts‑mode truth generation
- Counts‑mode synthetic truth generation now streams N and counts per year.
- No `N[x,y,t]` or `P[x,y,t]` arrays are constructed in counts mode.
- Explicit check: **No 3‑D P/N arrays are created in counts‑mode synthetic truth generation.**

---

## Current budgets (for WP‑0.3.5 gate)

**Canonical preflight (old points‑mode pipeline, includes screen/ABC/report):**
- GB realistic preflight: **~43:30** wall, **~41.7 GB RSS**
- Recorded in `outputs/perf/preflight/gb/preflight_gb_summary.csv` and canonical manifest.

**Updated counts‑mode preflights (direct sim+obs+TX estimator only):**
- GB counts: **~5.2 min**, **~6.35 GB RSS**

**Full‑pipeline counts preflight (screen + ABC + report, pilot grid):**
- wall time ≈ **3:01** (181 s), max RSS ≈ **1,205,900 kB** (~1.15 GB).
- `_targets/objects` delta: **-12 kB** (stable).
- canonical folder size: **192 kB**.
- run id: `preflight_full_counts_20251221_142443`
- files:
  - `outputs/perf/preflight/gb/full_counts/preflight_gb_full_counts_time.txt`
  - `outputs/perf/preflight/gb/full_counts/preflight_gb_full_counts_sizes.csv`
  - canonical: `outputs/canonical/0.3/WP-0.3.4b/preflight_full_counts_20251221_142443/`

**Interpretation:**
Counts‑only observation and streaming counts remove the dominant cost. The
end‑to‑end pipeline (screen + ABC + report) now runs in minutes at pilot‑grid
size with peak RSS ~1.2 GB, which is compatible with WP‑0.3.5 provided ABC
draw counts remain bounded.

**Post‑hardening counts‑mode preflight (streaming counts, no 3‑D arrays):**
- GB counts: **~42.5 s**, **~1.00 GB RSS** (pilot grid, pilot years)
- Files:
  - `outputs/perf/preflight/gb/preflight_gb_counts_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_counts_summary.csv`
  - `outputs/perf/preflight/gb/preflight_gb_counts_runtime.csv`

**Before/after (counts mode, direct preflight):**
- **5.2 min → 42.5 s** (~**7.3×** faster)
- **6.35 GB → 1.00 GB** (~**6×** lower RSS)

---

## Sanity checks in place

- Perf guardrail test (CI‑safe): `tests/testthat/test_perf_guardrails.R`
- Artefact review cycle logged in `docs/log/030_synthetic_benchmark.md`
- Budget decisions locked in `docs/decisions.md`

---

## Remaining opportunities (not yet executed)

These are **optional** and should be pursued only if the full‑pipeline
preflight is still too slow for WP‑0.3.5 at the intended draw counts:

1) **Domain cropping** (tight bounding box of active cells) to avoid FFT over
   ocean/NA grid cells. (Implemented; enable via `EXDYN_SYNTHETIC_CROP=1`.)
2) **Graph/segment representation** for riparian systems (structural speedup).
3) **Points‑mode truth generation still uses 3‑D N[x,y,t] arrays** (acceptable
   for toy runs; should stay off for GB runs).
4) **Selective output saving** for screen/ABC stages (already partially done).

---

## Recommended next checks

1) Decide whether WP‑0.3.5 is green‑lit given the 3‑minute full‑pipeline
   preflight and the planned ABC draw counts.
2) If WP‑0.3.5 is still too slow at the planned scale, proceed to structural
   options (crop defaults, or segment/graph state).

---

## File locations (for verification)

- Preflight logs:
  - `outputs/perf/preflight/medium/preflight_medium_counts_time.txt`
  - `outputs/perf/preflight/medium/preflight_medium_points_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_counts_time.txt`
  - `outputs/perf/preflight/gb/preflight_gb_points_time.txt`
- Comparison tables:
  - `outputs/perf/preflight/medium/preflight_medium_comparison.csv`
  - `outputs/perf/preflight/gb/preflight_gb_comparison.csv`
- Streaming preflight summaries:
  - `outputs/perf/preflight/gb/preflight_gb_counts_summary.csv`
  - `outputs/perf/preflight/gb/preflight_gb_counts_runtime.csv`
- Canonical GB preflight manifest:
  - `outputs/canonical/0.3/WP-0.3.4b/syn_20251220_164636_0099/manifest.yaml`
  - `outputs/canonical/0.3/WP-0.3.4b/preflight_full_counts_20251221_142443/manifest.yaml`
