test_that("pilot gate pre passes with adequate coverage", {
  grid <- exdyn_perf_make_grid(nx = 4, ny = 4, seed = 1)
  years <- 2000:2005
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 2
  )
  T_P <- exdyn_arrival_matrix(arrivals, grid$grid_info, years)

  TX_true <- matrix(NA_real_, nrow = 4, ncol = 4)
  TX_true[1:8] <- years[1:8]
  TX_obs <- matrix(rep(years, length.out = 16), nrow = 4, ncol = 4)

  summary_obs <- exdyn_summary_tx_response(TX_obs, T_P, years = years, coverage_breaks = exdyn_coverage_breaks(years), mask = grid$grid_info$riparian_matrix)
  counts_true <- exdyn_summary_counts(TX_true, T_P, mask = grid$grid_info$riparian_matrix)
  counts_obs <- exdyn_summary_counts(TX_obs, T_P, mask = grid$grid_info$riparian_matrix)
  counts <- c(
    n_mask = counts_obs[["n_mask"]],
    n_TP_finite = counts_obs[["n_TP_finite"]],
    n_pairs = counts_obs[["n_pairs"]],
    n_TX_use = counts_obs[["n_TX_finite"]],
    n_TX_true = counts_true[["n_TX_finite"]],
    n_TX_obs = counts_obs[["n_TX_finite"]],
    n_pairs_true = counts_true[["n_pairs"]],
    n_pairs_obs = counts_obs[["n_pairs"]]
  )

  truth <- list(T_P = T_P)
  gate_pre <- exdyn_pilot_gate_pre(truth, summary_obs, counts, grid$grid_info$riparian_matrix)
  expect_true(gate_pre$pass)
})

test_that("pilot gate pre fails with low arrival coverage", {
  grid <- exdyn_perf_make_grid(nx = 4, ny = 4, seed = 2)
  years <- 2000:2005
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 2
  )
  arrivals$arrival_year[1:10] <- NA_real_
  T_P <- exdyn_arrival_matrix(arrivals, grid$grid_info, years)
  TX <- matrix(NA_real_, nrow = 4, ncol = 4)
  summary_obs <- exdyn_summary_tx_response(TX, T_P, years = years, coverage_breaks = exdyn_coverage_breaks(years), mask = grid$grid_info$riparian_matrix)
  counts <- exdyn_summary_counts(TX, T_P, mask = grid$grid_info$riparian_matrix)
  counts <- c(counts, n_TX_true = 0, n_TX_obs = 0, n_pairs_true = 0, n_pairs_obs = 0, n_TX_use = 0)
  truth <- list(T_P = T_P)
  gate_pre <- exdyn_pilot_gate_pre(truth, summary_obs, counts, grid$grid_info$riparian_matrix)
  expect_false(gate_pre$pass)
})

test_that("pilot gate post checks screen and ABC acceptance", {
  screen <- tibble::tibble(compatible = c(TRUE, FALSE))
  abc <- list(samples = tibble::tibble(a = 1:5))
  abc_cfg <- list(n_sims = 100)
  gate_post <- exdyn_pilot_gate_post(screen, abc, abc_cfg, skipped = FALSE)
  expect_true(gate_post$pass)
})

test_that("pilot gates honor threshold overrides from config", {
  thresholds <- list(
    thresholds = list(
      arrival_frac_finite_min = 0.2,
      tx_true_min = 1,
      tx_true_coverage_min = 0,
      tx_true_coverage_max = 1,
      tx_obs_min = 1,
      tx_obs_coverage_min = 0,
      geom_finite_min = 1,
      cov_curve_mid_min = 1,
      screen_compatible_min = 2,
      accept_rate_min = 0.01,
      accept_rate_max = 0.10
    )
  )
  truth <- list(T_P = matrix(2000, nrow = 2, ncol = 2))
  summary_obs <- c(
    coverage = 0.1,
    lag_mean = 2,
    lag_sd = 1,
    r2_arrival = 0.3,
    grad_mag = 1,
    orient_R = 0.5,
    speed_cells_per_year = 1,
    speed_r2 = 0.4,
    tx_mean = 2005,
    tx_sd = 1,
    cov_curve_1 = 0.5
  )
  counts <- c(
    n_mask = 4,
    n_TP_finite = 4,
    n_pairs = 1,
    n_TX_use = 1,
    n_TX_true = 1,
    n_TX_obs = 1,
    n_pairs_true = 1,
    n_pairs_obs = 1
  )
  gate_pre <- exdyn_pilot_gate_pre(truth, summary_obs, counts, matrix(TRUE, 2, 2), gate_cfg = thresholds)
  expect_true(gate_pre$pass)

  gate_post <- exdyn_pilot_gate_post(
    screen_results = tibble::tibble(compatible = c(TRUE, TRUE, FALSE)),
    abc = list(samples = tibble::tibble(a = 1:5)),
    abc_cfg = list(n_sims = 100),
    gate_cfg = thresholds,
    skipped = FALSE
  )
  expect_true(gate_post$pass)
})
