# Benchmark synthetic_screen-like workload at different parallel widths
lib_user <- file.path("~", "R", paste0(R.version$platform, "-library"), paste0(R.version$major, ".", R.version$minor))
.libPaths(c(normalizePath(lib_user, mustWork = FALSE), .libPaths()))
options(future.globals.maxSize = 2e9)
suppressPackageStartupMessages({
  library(pkgload)
  library(targets)
  library(future.apply)
  library(dplyr)
})
pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)

# number of draws for the micro-benchmark
n_draws_bench <- 20
workers_set <- c(`1core` = 1, `4cores` = 4, `50cores` = 50)

# Load cached objects (assumes synthetic_truth already built)
pilot_grid_info <- tar_read(pilot_grid_info)
pilot_years <- tar_read(pilot_years)
synthetic_screen_cfg <- tar_read(synthetic_screen_cfg)
synthetic_truth <- tar_read(synthetic_truth)
synthetic_mask <- tar_read(synthetic_mask)
synthetic_compat_cfg <- tar_read(synthetic_compat_cfg)
theta_tbl <- tar_read(synthetic_theta_all) %>%
  dplyr::filter(draw > 0) %>%
  dplyr::slice_head(n = n_draws_bench)
delta_cols <- names(theta_tbl)[grepl("^delta_", names(theta_tbl))]

bench_once <- function(workers) {
  plan(multisession, workers = workers)
  t0 <- proc.time()
  res <- future_lapply(seq_len(nrow(theta_tbl)), function(i) {
    theta_row <- theta_tbl[i, ]
    delta_lookup <- NULL
    if (length(delta_cols)) {
      delta_lookup <- purrr::map_dbl(delta_cols, ~ theta_row[[.x]])
      names(delta_lookup) <- gsub("^delta_", "", delta_cols)
    }
    T_P_adj <- exdyn_adjust_arrival_matrix(
      synthetic_truth$T_P,
      pilot_grid_info,
      delta_lookup,
      pilot_years
    )
    if (any(!synthetic_mask)) T_P_adj[!synthetic_mask] <- NA_real_
    pars <- list(
      rmax = theta_row$rmax,
      A_frac = theta_row$A_over_K * synthetic_screen_cfg$K0,
      beta_H = 0,
      d = 0.02
    )
    TX_idx <- exdyn_simulate_tx_only(
      grid_info = pilot_grid_info,
      years = pilot_years,
      T_P = T_P_adj,
      ramp_years = round(theta_row$ramp_years),
      pars = pars,
      K0 = synthetic_screen_cfg$K0,
      alpha = theta_row$alpha,
      disp_mean_cells = theta_row$disp_mean_cells,
      pred = list(
        type = "II",
        c = theta_row$pred_c,
        h = theta_row$pred_h,
        scale = theta_row$pred_scale,
        gamma = theta_row$gamma
      ),
      pre_leak = 0,
      mask = synthetic_mask
    )
    TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
    idx <- is.finite(TX_idx)
    if (any(idx)) {
      TX_years[idx] <- pilot_years[TX_idx[idx]]
    }
    TX_years[!synthetic_mask] <- NA_real_
    exdyn_score(
      synthetic_truth$TX_obs,
      T_P_adj,
      TX_years,
      synthetic_compat_cfg
    ) %>% mutate(draw = theta_row$draw)
  })
  elapsed <- (proc.time() - t0)[["elapsed"]]
  list(elapsed = elapsed, res = res)
}

results <- lapply(workers_set, bench_once)

print(vapply(results, function(x) x$elapsed, numeric(1)))
