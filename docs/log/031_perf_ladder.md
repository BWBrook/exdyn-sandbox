# Performance Ladder Lab Notes

Date: 2025-12-24

## Toy scenario (for Stage A starting point)

**Plain-English description**

We start with a **tiny toy grid** that is small enough to run in seconds but still has spatial structure. The grid is 15×15 cells, each 10 km across, with a synthetic “riparian” mask that keeps about 60% of cells active (think of a simplified river network running down the middle of the grid). We assign three coarse “regions” as horizontal bands (north/mid/south) only to mirror the regional parameter structure used elsewhere. Mink arrival is a smooth gradient from northwest to southeast with a bit of noise, spanning the years 2000–2020. Cells outside the riparian mask are treated as NA (inactive).

This toy setup is **not meant to be realistic**; it is purely to give us a clear, visualizable baseline for timing and memory, and to allow clean, incremental scaling. Importantly, we treat the HSI surface as **continuous permeability**: the dynamics can move across the full grid (no hard 0/1 blocking), and the binary mask is only a convenience for analysis/cropping.

**Toy parameters (Stage A baseline)**

- Grid: 15 × 15, 10 km cell size  
- Riparian fraction: ~0.60 (mask)  
- Regions: 3 horizontal bands  
- Years: 2000–2020 (21 years)  
- Arrival pattern: gradient + noise (`span_frac=0.75`, `noise_sd=1.5`)  
- Mask: riparian only (non-riparian set to NA)  

**Toy arrival map (masked)**  

![](../../outputs/perf/ladder/toy/assets/toy_arrival_map.png)

**Toy habitat suitability (HSI) surface**  

This is the continuous “permeability” surface: all cells exist, but river‑adjacent cells are higher suitability. The binary mask used for some steps is the top ~60% of this surface (a convenience for cropping/analysis, not a statement that other cells are impossible).

![](../../outputs/perf/ladder/toy/assets/toy_hsi_suitability.png)

**Toy riparian mask (derived from HSI)**  

![](../../outputs/perf/ladder/toy/assets/toy_riparian_mask.png)

**Toy arrival table (masked)**  

- `outputs/perf/ladder/toy/assets/toy_arrival_table.csv`

---

## Stage A — Core TX-only simulation (toy)

**Definition:** TX-only simulator, no observation model, no summaries, no screen, no ABC.

**Expected output:** runtime + max RSS only.

**Run record (fill after execution)**

| Date | Stage | Grid | Years | Reps | Obs | Summaries | Screen | ABC | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2025-12-24 | A | 15×15 | 2000–2020 | 1 | none | no | no | no | 3.27 | 3.5 | soft mask (HSI-scaled predation) |
| 2025-12-24 | A | 15×15 | 2000–2020 | 3 | none | no | no | no | 8.75 | 3.5 | soft mask (HSI-scaled predation), explicit 3‑rep loop |
| 2025-12-24 | A | 15×15 | 2000–2020 | 3 | none | no | no | no | 5.65 | 3.5 | parallel (3 cores), soft mask |
| 2025-12-24 | A | 15×15 | 2000–2020 | 25 | none | no | no | no | 8.29 | 3.5 | parallel (25 cores), soft mask; `/usr/bin/time -v` max RSS ≈ 596,940 kB |
| 2025-12-24 | A | 15×15 | 2000–2020 | 25 | none | no | no | no | 8.24 | 3.5 | parallel (25 cores), soft mask; sampled RSS sum peak ≈ 14,190,468 kB (parent ≈ 592,684 kB; children sum ≈ 13,600,012 kB; shared pages mean this is an upper bound) |
| 2025-12-24 | A | 15×15 | 2000–2020 | 25 | none | no | no | no | 8.14 | 3.5 | parallel (25 cores), soft mask; PSS sampler peak ≈ 12,067,454 kB (parent ≈ 576,334 kB; children ≈ 11,571,828 kB; closer to physical footprint) |
| 2025-12-24 | B1 | 15×15 | 2000–2020 | 1 | counts | no | no | no | 5.46 | 3.5 | counts‑only observation (soft mask) |
| 2025-12-24 | B2 | 15×15 | 2000–2020 | 1 | points | no | no | no | 5.89 | 3.5 | points‑only observation (soft mask) |
| 2025-12-24 | C | 15×15 | 2000–2020 | 1 | none | yes | no | no | 3.02 | 3.5 | summaries only (soft mask) |
| 2025-12-24 | D | 15×15 | 2000–2020 | 1 | counts | no | yes | no | 8.91 | 3.5 | screening only (8 draws; soft mask) |
| 2025-12-24 | E | 15×15 | 2000–2020 | 1 | counts | no | no | yes | 5.94 | 3.5 | ABC-only (150 sims; soft mask; accepts=119) |
| 2025-12-24 | F | 15×15 | 2000–2020 | 1 | counts | yes | yes | yes | 13.06 | 3.5 | full pipeline (counts + summary + screen + ABC; accepts=120) |

---

## Small scenario (spatial scaling only)

**Plain-English description**

We double spatial resolution to a **30×30 grid** (still 10 km cells) while **holding time constant at 2000–2019 (20 years)**. The same soft HSI/permeability surface is used, so this is a purely spatial scaling step with no added temporal length.

## Stage A–F — Small grid results (30×30, 2000–2019)

| Date | Stage | Grid | Years | Reps | Obs | Summaries | Screen | ABC | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2025-12-24 | A | 30×30 | 2000–2019 | 1 | none | no | no | no | 3.07 | 3.5 | soft mask (HSI-scaled predation) |
| 2025-12-24 | A | 30×30 | 2000–2019 | 3 | none | no | no | no | 19.83 | 3.5 | soft mask (HSI-scaled predation), explicit 3‑rep loop |
| 2025-12-24 | B1 | 30×30 | 2000–2019 | 1 | counts | no | no | no | 6.51 | 3.5 | counts‑only observation (soft mask) |
| 2025-12-24 | B2 | 30×30 | 2000–2019 | 1 | points | no | no | no | 6.78 | 3.5 | points‑only observation (soft mask) |
| 2025-12-24 | C | 30×30 | 2000–2019 | 1 | none | yes | no | no | 3.05 | 3.5 | summaries only (soft mask) |
| 2025-12-24 | D | 30×30 | 2000–2019 | 1 | counts | no | yes | no | 9.60 | 3.5 | screening only (8 draws; soft mask) |
| 2025-12-24 | E | 30×30 | 2000–2019 | 1 | counts | no | no | yes | 7.25 | 3.5 | ABC-only (150 sims; soft mask; accepts=90) |
| 2025-12-24 | F | 30×30 | 2000–2019 | 1 | counts | yes | yes | yes | 14.96 | 3.5 | full pipeline (counts + summary + screen + ABC; accepts=88) |

**Parallel PSS (Stage A, 25 reps)**  
R‑reported max RSS is ≈ 3.5 MB (not representative under forked workers), but PSS sampling shows **peak ≈ 12,070,941 kB** (parent ≈ 578,740 kB; children ≈ 11,574,456 kB; 25 workers). This is a closer estimate of physical footprint for parallel runs.

---

## Medium scenario (spatial scaling only)

**Plain-English description**

We double spatial resolution again to a **60×60 grid** (10 km cells) while **holding time constant at 2000–2019 (20 years)**. This isolates spatial scaling effects without confounding by longer time series.

## Stage A–F — Medium grid results (60×60, 2000–2019)

| Date | Stage | Grid | Years | Reps | Obs | Summaries | Screen | ABC | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2025-12-24 | A | 60×60 | 2000–2019 | 1 | none | no | no | no | 3.23 | 3.5 | soft mask (HSI-scaled predation) |
| 2025-12-24 | A | 60×60 | 2000–2019 | 3 | none | no | no | no | 19.74 | 3.5 | soft mask (HSI-scaled predation), explicit 3‑rep loop |
| 2025-12-24 | B1 | 60×60 | 2000–2019 | 1 | counts | no | no | no | 9.75 | 3.5 | counts‑only observation (soft mask) |
| 2025-12-24 | B2 | 60×60 | 2000–2019 | 1 | points | no | no | no | 11.52 | 3.5 | points‑only observation (soft mask) |
| 2025-12-24 | C | 60×60 | 2000–2019 | 1 | none | yes | no | no | 3.38 | 3.5 | summaries only (soft mask) |
| 2025-12-24 | D | 60×60 | 2000–2019 | 1 | counts | no | yes | no | 13.62 | 3.5 | screening only (8 draws; soft mask) |
| 2025-12-24 | E | 60×60 | 2000–2019 | 1 | counts | no | no | yes | 19.85 | 3.5 | ABC-only (150 sims; soft mask; accepts=61) |
| 2025-12-24 | F | 60×60 | 2000–2019 | 1 | counts | yes | yes | yes | 25.85 | 3.5 | full pipeline (counts + summary + screen + ABC; accepts=74) |

**Parallel PSS (Stage A, 25 reps)**  
PSS sampling shows **peak ≈ 13,609,376 kB** (parent ≈ 628,882 kB; children ≈ 13,058,913 kB; 25 workers).

---

## Temporal scaling (60‑year span, 2000–2059)

We repeat the ladder on the same three grids with **tripled time span** (60 years vs 20 years) to isolate temporal scaling.

---

## Grid orientation + IE coverage fix (2025-12-25)

- Added config-file tracking for realdata, pilot, and synthetic targets so GB+IE changes in `config/realdata.yaml` or `config/synthetic.yaml` invalidate cached grids and arrival tables.
- Updated `exdyn_plot_surface()` to plot using centroids when available (north-up, true coordinates), avoiding vertical flip confusion in synthetic maps.

### Toy 15×15 (2000–2059)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 3.04 | 3.5 | core TX-only |
| B1 | 5.89 | 3.5 | counts‑only obs |
| B2 | 6.39 | 3.5 | points‑only obs |
| C | 3.25 | 3.5 | summaries |
| D | 9.65 | 3.5 | screen (8 draws) |
| E | 13.14 | 3.5 | ABC (150 sims; accepts=147) |
| F | 20.30 | 3.5 | full pipeline (accepts=148) |

### Small 30×30 (2000–2059)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 3.35 | 3.5 | core TX-only |
| B1 | 7.24 | 3.5 | counts‑only obs |
| B2 | 8.23 | 3.5 | points‑only obs |
| C | 3.47 | 3.5 | summaries |
| D | 11.02 | 3.5 | screen (8 draws) |
| E | 19.38 | 3.5 | ABC (150 sims; accepts=150) |
| F | 26.77 | 3.5 | full pipeline (accepts=149) |

### Medium 60×60 (2000–2059)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 3.30 | 3.5 | core TX-only |
| B1 | 12.45 | 3.5 | counts‑only obs |
| B2 | 14.97 | 3.5 | points‑only obs |
| C | 3.43 | 3.5 | summaries |
| D | 16.29 | 3.5 | screen (8 draws) |
| E | 40.13 | 3.5 | ABC (150 sims; accepts=146) |
| F | 48.87 | 3.5 | full pipeline (accepts=149) |

---

## GB+IE pilot grid (cropped to riparian mask)

**Plain-English description**

We run the same A–F ladder on the **pilot GB+IE grid** (real mink arrivals) but **crop to the riparian mask bounds** (pad = 5 cells). The full grid is 1203×1190, but the riparian mask is extremely sparse (19 cells), so the cropped subgrid is tiny. This gives a sanity check of the full pipeline on the “real” grid object while keeping the compute realistic.

**Crop metadata (from `outputs/perf/ladder/gb_crop/crop_meta.csv`)**

- Full grid: 1203 × 1190  
- Land cells: 3,664  
- Riparian cells: 19  
- Crop bounds: 54 rows × 159 cols  
- Cropped grid: 8 × 21

### Stage A–F — GB crop results (1950–2024)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 3.36 | 3.5 | core TX-only (cropped) |
| B1 | 5.92 | 3.5 | counts‑only obs (cropped) |
| B2 | 6.41 | 3.5 | points‑only obs (cropped) |
| C | 3.36 | 3.5 | summaries (cropped) |
| D | 9.06 | 3.5 | screen (8 draws; cropped) |
| E | 13.47 | 3.5 | ABC (150 sims; accepts=118) |
| F | 21.93 | 3.5 | full pipeline (accepts=45) |

**Overall wall time + RSS (`/usr/bin/time -v`, full A–F script):**  
Wall time ≈ **1:54.51**, max RSS ≈ **761,872 kB (~744 MB)**.

**Notes**
- The cropped subgrid is tiny because the riparian mask has only 19 TRUE cells; this is likely why timings are similar to (or faster than) the 60×60 medium grid despite the large full grid dimensions.
- The run logged several `summary.lm` “essentially perfect fit” warnings; this is consistent with a tiny, near‑collinear mask.

**Artefacts**
- Stage outputs: `outputs/perf/ladder/gb_crop/stage/{A,B1,B2,C,D,E,F}/`
- Crop metadata: `outputs/perf/ladder/gb_crop/crop_meta.csv`
- Runtime report: `outputs/perf/ladder/gb_crop/time.txt`

---

## GB+IE pilot grid — land mask + soft suitability (full land crop)

**Plain-English description**

We re-run the GB pilot ladder with **all land cells active** (land mask) and apply a **soft suitability bias** derived from `river_km` (scaled to 0.2–1.0) as a predation scale matrix. This matches the “riparian as attractant, not guardrail” concept. The crop is based on the land mask bounds.

**Crop metadata (from `outputs/perf/ladder/gb_land/crop_meta.csv`)**

- Full grid: 1203 × 1190  
- Land cells: 3,664  
- Crop bounds: 1203 rows × 1190 cols  
- Cropped grid: 1203 × 1190 (no reduction)  
- Suitability range (land): 0.2–1.0

### Stage A–D — GB land+soft results (1950–2024)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 169.48 | 3.5 | core TX-only (land mask + soft suitability) |
| B1 | 341.46 | 3.5 | counts‑only obs (land mask + soft suitability) |
| B2 | 512.30 | 3.5 | points‑only obs (land mask + soft suitability) |
| C | 145.80 | 3.5 | summaries (land mask + soft suitability) |
| D | 1312.82 | 3.5 | screen (8 draws; land mask + soft suitability) |

**Stage E/F status**
- **Not completed** within a 1‑hour wall‑time budget; stage D alone is ~22 minutes, implying ABC on the full 1203×1190 grid will take multiple hours (likely 6–8+ hours for 150 sims).
- This confirms that **land‑mask full‑grid runs remain prohibitively expensive** without domain cropping or structural reduction (e.g., land‑only bounding box that is smaller, or graph/segment representation).

**Artefacts**
- Stage outputs (A–D): `outputs/perf/ladder/gb_land/stage/{A,B1,B2,C,D}/`
- Crop metadata: `outputs/perf/ladder/gb_land/crop_meta.csv`

---

## GB+IE pilot grid — land mask + soft suitability (tight crop by sparse‑edge trimming)

**Plain-English description**

We keep **all land cells active** (soft suitability bias), but we **trim very sparse outer rows/cols** to tighten the bounding box. Rows/cols with land fraction below 0.2% are dropped (with a 5‑cell pad), yielding a smaller internal FFT domain while still keeping ~97% of land cells. This is a pragmatic performance crop (not a scientific filter).

**Crop metadata (from `outputs/perf/ladder/gb_land_tight/crop_meta.csv`)**

- Full grid: 1203 × 1190  
- Land cells: 3,664  
- Retained land cells: 3,542 (≈96.7%)  
- Crop bounds: rows 65–1183 (1119 rows), cols 31–1184 (1154 cols)  
- Crop dims: 1119 × 1154 (internal FFT domain)  
- Suitability range (land): 0.2–1.0

### Stage A–D — GB land+soft+**tight crop** results (1950–2024)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 106.83 | 3.5 | core TX-only (tight crop) |
| B1 | 112.07 | 3.5 | counts‑only obs (tight crop) |
| B2 | 443.98 | 3.5 | points‑only obs (tight crop) |
| C | 89.04 | 3.5 | summaries (tight crop) |
| D | 774.64 | 3.5 | screen (8 draws; tight crop) |

**Overall wall time + RSS (`/usr/bin/time -v`, A–D script):**  
Wall time ≈ **26:09**, max RSS ≈ **22,385,536 kB (~21.4 GB)**.

**Speedup vs full land‑mask run (A–D)**

- A: 169.5 → 106.8 s (≈1.6× faster)  
- B1: 341.5 → 112.1 s (≈3.0× faster)  
- B2: 512.3 → 444.0 s (≈1.15× faster)  
- C: 145.8 → 89.0 s (≈1.6× faster)  
- D: 1312.8 → 774.6 s (≈1.7× faster)

**Notes**
- Tight cropping helps, but **screen (D) is still ~13 minutes** at 8 draws. ABC at full scale will still be multi‑hour unless we crop more aggressively or reduce the FFT domain further (graph/segment model, or stronger land‑edge trimming).
- The PSS/true RSS from `/usr/bin/time -v` is far higher than the per‑stage “peak_rss_mb” captured inside R, which undercounts for large allocations.

**Artefacts**
- Stage outputs (A–D): `outputs/perf/ladder/gb_land_tight/stage/{A,B1,B2,C,D}/`
- Crop metadata: `outputs/perf/ladder/gb_land_tight/crop_meta.csv`
- Runtime report: `outputs/perf/ladder/gb_land_tight/time.txt`

---

## GB+IE pilot grid — land‑cell graph dispersal (structural reduction prototype)

**Plain-English description**

We replace the FFT dispersal step with a **land‑cell graph** (nodes = land cells; edges within radius 5, weighted by the same exponential kernel). This removes the ocean‑grid tax entirely while keeping the ecological meaning close to the raster kernel. Soft suitability (river_km scaled 0.2–1.0) is preserved.

**Graph metadata (from `outputs/perf/ladder/gb_land_graph/graph_meta.csv`)**

- Full grid: 1203 × 1190  
- Land cells (nodes): 3,664  
- Graph radius: 5 (matches kernel radius)

### Stage A–D — GB land‑graph results (1950–2024)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| A | 5.05 | 3.5 | core TX-only (graph dispersal) |
| B1 | 13.53 | 3.5 | counts‑only obs (graph dispersal) |
| B2 | 334.04 | 3.5 | points‑only obs (still 3‑D arrays) |
| C | 3.78 | 3.5 | summaries (graph dispersal) |
| D | 23.23 | 3.5 | screen (8 draws; graph dispersal) |

**Overall wall time + RSS (`/usr/bin/time -v`, A–D script):**  
Wall time ≈ **7:03**, max RSS ≈ **19,722,552 kB (~18.8 GB)**.

**Speedup vs tight‑crop raster (A–D)**

- A: 106.8 → 5.05 s (≈21× faster)  
- B1: 112.1 → 13.5 s (≈8× faster)  
- C: 89.0 → 3.78 s (≈24× faster)  
- D: 774.6 → 23.2 s (≈33× faster)

**Notes**
- Stage B2 remains slow because it still constructs full 3‑D abundance arrays (points‑mode). Graph dispersal primarily benefits TX‑only and counts‑mode paths.
- This prototype demonstrates that **graph‑based dispersal eliminates the FFT lattice cost** and makes screening/ABC feasible at GB scale.

**Artefacts**
- Stage outputs (A–D): `outputs/perf/ladder/gb_land_graph/stage/{A,B1,B2,C,D}/`
- Graph metadata: `outputs/perf/ladder/gb_land_graph/graph_meta.csv`
- Runtime report: `outputs/perf/ladder/gb_land_graph/time.txt`

### Stage E–F — GB land‑graph results (1950–2024)

| Stage | Wall time (s) | Max RSS (MB) | Notes |
| --- | --- | --- | --- |
| E | 167.42 | 3.5 | ABC‑only (150 sims; accepts=12) |
| F | 175.99 | 3.5 | full pipeline (counts + summary + screen + ABC; accepts=79) |

**Overall wall time + RSS (`/usr/bin/time -v`, E–F script):**  
Wall time ≈ **6:15**, max RSS ≈ **1,360,192 kB (~1.3 GB)**.

**Artefacts**
- Stage outputs (E–F): `outputs/perf/ladder/gb_land_graph/stage/{E,F}/`
- Runtime report: `outputs/perf/ladder/gb_land_graph/time_ef.txt`

---

## GB+IE pilot grid — graph‑mode parallel runner (screen + ABC)

**Plain-English description**

We added a **parallel runner** for graph‑mode screen and ABC that distributes draws/sims across multiple cores using `future.apply` (multicore). This lets us scale to 50+ cores without changing the model or outputs.

**Example run (workers=8, draws=64, sims=200)**  
Output folder: `outputs/perf/ladder/gb_land_graph/parallel/20251225_161746/`

- Screen parallel wall ≈ **16.4 s**  
- ABC parallel wall ≈ **20.3 s** (accepts 11/200)

**Artefacts**
- Script: `outputs/perf/ladder/gb_land_graph/run_gb_land_graph_parallel_runner.R`
- Output folder example: `outputs/perf/ladder/gb_land_graph/parallel/20251225_161746/`
- Make target: `make graph-parallel` (defaults to 8 workers; override with `EXDYN_WORKERS=50`)
- Targets hook: `config/perf.yaml` → `graph_parallel` (disabled by default; enable to run via `targets`)
