# Report to PI — 30 Jan 2025

## Executive summary
We have materially improved runtime and memory performance, primarily by avoiding dense raster convolution on large sparse grids and by moving the dispersal step onto an explicit land‑cell graph. This reduced GB‑scale preflight from multi‑hour / multi‑tens‑of‑GB runs to *seconds/minutes* and ~1–2 GB RSS in the graph/land‑only mode. We also tightened the synthetic pipeline’s sanity checks and domain consistency: mask‑consistent summaries, arrival diagnostics, viability sweeps, and gates. The synthetic example is now actively inspected via dedicated plots (arrival, TX_true/TX_obs, best, diff), and metrics are reported alongside counts so “sparse inference” failure modes are explicit. We can now iterate quickly and deterministically on pilot‑scale synthetic runs.

## Major execution‑speed improvements (what changed and why it matters)

### 1) Graph‑based dispersal (land‑only adjacency)
**Motivation:** The GB+IE grid is extremely sparse (land cells embedded in a huge bounding rectangle). FFT‑based convolution over the full raster paid a huge tax for ocean cells.

**Change:** We implemented/activated a land‑cell graph dispersal path (via `exdyn_land_graph_plan` and weighted adjacency) and switched perf‑ladder runs and synthetic checks to use this mode. This replaces 2‑D FFT convolution over `nx×ny` with sparse matrix operations over **n_land** nodes only.

**Impact:** Dramatic speed and memory reduction for GB‑scale runs in the counts‑only mode.
- GB counts preflight went from “hours + tens of GB” to **~1–2 GB RSS** and **seconds/minutes**.
- Parallel runs now feasible: a 50‑core run fits in RAM without oversubscription.

### 2) Avoided 3‑D state cubes and point‑event churn
- Counts‑only streaming generator used for synthetic truth/observation: no `N[x,y,t]` or `P[x,y,t]` arrays are retained.
- “Points” observation mode (large event tables) is now clearly segregated and used only when intended.

### 3) Elimination of slow stats in hot loops
- `lm()` calls in per‑draw summary/score paths replaced with closed‑form equivalents (`cor^2`, `cov/var`).
- Orientation metrics vectorised (Sobel gradient via slicing, not per‑cell loops).

### 4) Performance‑ladder harness
We added a perf‑ladder with explicit stages (A–F) and multiple grid sizes; all runs logged with wall‑time and RSS. This makes scaling behavior visible and keeps us out of “mystery 26‑hour runs.”

**Key artefacts:**
- `docs/perf_ladder_plan.md` (checkboxes + run sequence)
- `docs/log/*perf*` entries for timings
- `outputs/perf/ladder/*` staging folders (A/B/C/D/E/F, toy→small→medium→GB)

## Synthetic example sanity checking (visual + metric based)

### 1) Mask‑consistent summaries
- All summary and scoring calculations now enforce a consistent analysis mask, preventing denominator mismatches.
- Outputs now include explicit counts: `n_mask`, `n_TP_finite`, `n_pairs`, `n_TX_true`, `n_TX_obs`.

### 2) Arrival‑surface diagnostics + overrides
- Added `arrival_source` modes (`real`, `synthetic_plane`, `synthetic_gradient`) for pilot debugging.
- Plots + diagnostics explicitly report fraction of finite arrival within mask, so coverage failures are attributable.

### 3) Viability sweep (truth tuning)
- A small sweep over predation strength parameters (pred_scale/pred_c) identifies regimes where TX_true coverage is neither trivial nor complete. This prevents “silent no‑extirpation” cases.
- Viability sweep now outputs **coverage_true** and lag summaries, allowing a principled theta_star choice.

### 4) Visual sanity checks
We now routinely inspect:
- Arrival surface plots (real vs synthetic)
- TX_true / TX_obs maps
- Best‑fit TX and Best‑minus‑True maps

These plots catch:
- vertical flipping
- missing ROI (Ireland)
- empty TX_true due to too‑weak predation
- mask/extent mismatches

**Key artefacts:**
- `outputs/synthetic/arrival_*.png`
- `outputs/synthetic/ideal/TX_true_syn.png`, `TX_obs_syn.png`, `TX_best_syn.png`, `TX_diff_syn.png`
- `outputs/synthetic/viability_sweep.csv` + `viability_sweep_plot.png`

## Roadmap progress highlights (since last PI checkpoint)
- **WP‑0.2.x** (perf ground‑truth) complete: toy benchmark, profiling harness, scaling sweep, performance budgets, guardrails.
- **WP‑0.3.1 → 0.3.4b** complete: schema/manifest, ideal vs realistic, replicated recovery, summary alignment + regression tests, GB preflight budgets.
- **WP‑0.3.4.1–0.3.4.4** complete: mask‑consistent summaries, arrival diagnostics/override, viability sweep, pilot gates.
- **Synthetic pipeline now fast enough for iteration**, especially in graph mode.

## Remaining problems (known, but not yet blocking)
- **Many‑to‑many join warning** (row 1444) repeats during synthetic runs; likely a join on arrivals/lookup or region mapping; should be investigated for potential data duplication but not yet breaking.
- **Synthetic config drift vs outputs**: viability sweep file can be stale if not rebuilt; we now force rebuilds but should add guardrails to ensure outputs are current.
- **TX_true empty failures** still possible if theta_star too weak; viability sweep fixes this, but a test should assert `n_TX_true > 0` for pilot override runs.

## Suggested immediate follow‑ups (execution‑ready)
1) Make **graph‑mode default** for large grids (GB/IE) with clear logging of mode and graph size.
2) Add a **cheap sanity test**: fail if `TX_true` has zero finite cells under pilot arrival override.
3) Investigate the many‑to‑many join warning (likely a duplicated key in arrivals or lookup joins).

## Key commands (for reproducibility)
- **Minimal pilot synthetic (ideal mode, synthetic arrivals)**:
  - `EXDYN_SYNTHETIC_GRID_TYPE=pilot EXDYN_SYNTHETIC_ARRIVAL_SOURCE=synthetic_plane EXDYN_SYNTHETIC_MODES=ideal EXDYN_SYNTHETIC_REPS=1 EXDYN_SYNTHETIC_OBS_MODE=counts \
     EXDYN_SYNTHETIC_SCREEN_DRAWS=1 EXDYN_SYNTHETIC_ABC_N=5 EXDYN_SYNTHETIC_ABC_LHS_N=5 EXDYN_SYNTHETIC_ABC_LHS_KEEP=2 \
     Rscript -e "targets::tar_make(names='synthetic_outputs_written')"`
- **Viability sweep (pilot, synthetic arrivals)**:
  - `EXDYN_SYNTHETIC_GRID_TYPE=pilot EXDYN_SYNTHETIC_ARRIVAL_SOURCE=synthetic_plane EXDYN_SYNTHETIC_VIABILITY=1 \
     Rscript -e "targets::tar_make(names='synthetic_viability_sweep_plot')"`

