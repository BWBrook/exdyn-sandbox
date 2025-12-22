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
