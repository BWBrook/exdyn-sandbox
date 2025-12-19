# Getting Started in RStudio: Hands‑On Tour of `exdyn-sandbox`

This walkthrough is written for a new user who has just cloned the repo and opened it in RStudio. It favours short, reproducible snippets you can paste into the R console or an R script. The goal is to gain intuition for what the package does, how the `targets` pipelines run, and where the main artefacts live.

## 0) One‑time setup

```r
# From the repo root (check with getwd())
install.packages("renv")              # if you don't already have it
renv::restore()                       # installs the locked versions
```

After restore, restart your R session (`Session ▸ Restart R`) to pick up the library paths.

## 1) Load the package locally

```r
devtools::load_all(export_all = FALSE) # or pkgload::load_all()
```

This makes all exported functions available without installing a system‑wide package.

## 2) Inspect configuration and key objects

```r
yaml::read_yaml("config/realdata.yaml")$pilot        # real-data pilot knobs
yaml::read_yaml("config/synthetic.yaml")$theta_star  # synthetic truth
```

To see what targets exist and their status:

```r
targets::tar_manifest()             # list of targets
targets::tar_progress()             # progress if a pipeline is running
```

## 3) Quick synthetic “happy path” (fast, no downloads)

This runs a small synthetic twin and produces HTML/PDF reports.

```r
library(future)
future::plan(multicore, workers = 4)         # shared memory; safe on Linux
options(future.globals.maxSize = Inf)

targets::tar_make_future(
  names = c("synthetic_report_html","synthetic_report_pdf",
            "synthetic_recovery_written"),
  workers = 4,
  callr_function = NULL
)
```

Explore the outputs:

```r
tar_read(synthetic_reference_runs)[[1]]$screen_results |>
  dplyr::arrange(loss) |>
  dplyr::slice_head(n = 5)
browseURL(tar_read(synthetic_report_html))   # opens the report in your browser
```

## 4) Minimal real‑data pilot run (mink → vole)

This uses cached GBIF pulls (GB + IE). First, build just the observed vole TX and the mink arrival field to see coverage:

```r
targets::tar_make(
  names = c("pilot_grid", "pilot_riparian_mask",
            "pilot_mink_field_default", "pilot_vole_tx"),
  callr_function = NULL
)

tar_read(pilot_vole_tx$table) |> dplyr::count(!is.na(tx_obs))
exdyn_plot_surface(tar_read(pilot_vole_tx)$matrix, tar_read(pilot_grid_info),
                   title = "Observed vole TX (riparian)")
```

Then run the (throttled) screen + ABC with shared memory:

```r
future::plan(multicore, workers = 4)
options(future.globals.maxSize = Inf)

targets::tar_make_future(
  names = c("pilot_guard_cfg","pilot_theta","pilot_screen",
            "pilot_shortlist","pilot_abc_stage1","pilot_abc_stage2",
            "pilot_report_html","pilot_report_pdf"),
  workers = 4,
  callr_function = NULL
)
```

Peek at best draws and diagnostics:

```r
tar_read(pilot_screen) |> dplyr::arrange(loss) |> dplyr::slice_head(n = 5)
browseURL(tar_read(pilot_report_html))
```

## 5) Explore functions interactively

Single draw simulation (real arrivals, custom parameters):

```r
grid_info <- tar_read(pilot_grid_info)
years     <- tar_read(pilot_years)
T_P       <- tar_read(pilot_mink_field_default)$T_P
mask      <- grid_info$riparian_matrix

theta <- list(alpha = 0.2, disp_mean_cells = 1.2, A_over_K = 0.08,
              pred_c = 1.0, pred_h = 30, ramp_years = 8,
              pred_scale = 2, gamma = 1.3, rmax = 0.45, K0 = 120)

pars <- list(rmax = theta$rmax, A_frac = theta$A_over_K * theta$K0,
             beta_H = 0, d = 0.03)

TX_idx <- exdyn_simulate_tx_only(
  grid_info = grid_info, years = years, T_P = T_P,
  ramp_years = theta$ramp_years, pars = pars, K0 = theta$K0,
  alpha = theta$alpha, disp_mean_cells = theta$disp_mean_cells,
  pred = list(type = "II", c = theta$pred_c, h = theta$pred_h,
              scale = theta$pred_scale, gamma = theta$gamma),
  mask = mask
)
TX_years <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
TX_years[is.finite(TX_idx)] <- years[TX_idx[is.finite(TX_idx)]]

exdyn_plot_surface(TX_years, grid_info, "One-off simulated TX")
```

## 6) Monitoring and troubleshooting

- Progress while a pipeline runs: `targets::tar_progress_branches()`  
- Logs: `tail -f logs/wo10.log` (or `wo9*.log`) in a shell.  
- If memory spikes with `multisession`, switch to `future::plan(multicore, workers = 4)` on Linux (shared memory).

## 7) Where outputs land

- Real pilot: `outputs/realdata/pilot_mink_vole/`
- Synthetic: `outputs/synthetic/`
- Logs: `logs/wo*.log`
- Reports: `reports/pilot_mink_vole.qmd`, `reports/synthetic_mink_vole.qmd` (+ rendered HTML/PDF in the same directory).

## 8) Clean/reset

```r
targets::tar_invalidate(everything())   # mark stale
targets::tar_destroy(destroy = "objects") # remove cached target objects (keeps scripts)
```

## 9) Suggested next explorations

- Tweak `config/synthetic.yaml` truth and rerun the synthetic pipeline to see how recovery changes.
- Adjust `config/realdata.yaml` `analysis_unit` (`segment` vs `grid15`) and rerun `pilot_screen`.
- Use `exdyn_plot_surface()` on intermediate matrices (arrival, TX_obs, TX_sim) to build intuition for spatial patterns. 
