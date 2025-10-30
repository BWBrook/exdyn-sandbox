# Quick comparison of tx-only simulation with and without cached convolution.

if (!requireNamespace("exdyn.sandbox", quietly = TRUE)) {
  stop("Package exdyn.sandbox not installed; run inside project with renv activated.")
}

library(exdyn.sandbox)

benchmark_run <- function(use_plan = TRUE, steps = 50L) {
  nx <- 50L
  ny <- 50L
  years <- steps + 1L
  grid_info <- list(nx = nx, ny = ny)
  years_vec <- seq_len(years)

  params <- list(
    rmax = 0.4,
    A_frac = 0.05 * 120,
    beta_H = 0,
    d = 0.02
  )
  T_P <- matrix(sample(1:years, nx * ny, replace = TRUE), nrow = nx)
  pred <- list(type = "II", c = 0.8, h = 30)

  alpha <- 0.2
  disp_mean_cells <- 1.5

  if (!use_plan) {
    original_sim <- function() {
      # copy of exdyn_simulate_tx_only using per-step conv2
      nx <- grid_info$nx
      ny <- grid_info$ny
      Tn <- length(years_vec)
      N <- matrix(pmax(1, round(120 * 0.1)), nrow = nx, ncol = ny)
      tau <- pmin(0.02 * 120, 0.5 * N)
      TX <- matrix(NA_integer_, nrow = nx, ncol = ny)
      ker <- exdyn_kernel(mean_cells = disp_mean_cells, radius = 5L)
      for (tt in seq_len(Tn - 1L)) {
        dt <- years_vec[tt] - T_P
        P_t <- ifelse(
          is.na(T_P),
          0,
          {
            val <- 0.2 + 0.8 / (1 + exp(-6 / 8 * (dt - 8 / 2)))
            val[dt < 0] <- 0
            pmax(0, pmin(1, val))
          }
        )
        local <- exdyn_update_local(
          N = N,
          S = matrix(1, nx, ny),
          H = matrix(0, nx, ny),
          P = P_t,
          pars = params,
          K0 = 120,
          pred_type = pred$type,
          pred_c = pred$c,
          pred_h = pred$h
        )
        moved <- exdyn_conv2(local, ker)
        N_next <- (1 - alpha) * local + alpha * moved
        crossed <- is.na(TX) & (N > tau) & (N_next <= tau)
        TX[crossed] <- tt + 1L
        N <- pmax(N_next, 0)
      }
      TX
    }
    return(system.time(original_sim()))
  }

  timed <- system.time(exdyn_simulate_tx_only(
    grid_info = list(
      nx = nx,
      ny = ny,
      cell_km = NA_real_,
      lookup = tibble::tibble()
    ),
    years = years_vec,
    T_P = T_P,
    ramp_years = 8,
    pars = params,
    K0 = 120,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    frac = 0.02,
    rel0 = 0.5,
    pre_leak = 0,
    log_mem = FALSE
  ))
  timed
}

cat("With cached plan:\n")
print(benchmark_run(use_plan = TRUE))
cat("Legacy per-step convolution:\n")
print(benchmark_run(use_plan = FALSE))
