test_that("ABC rejection recovers simple lag parameter", {
  skip_on_cran()
  T_P <- matrix(seq(1950, 1953), nrow = 2)
  lag_true <- 5
  TX_true <- T_P + lag_true
  S_obs <- suppressWarnings(exdyn_summary_tx_response(TX_true, T_P))
  prior_fun <- exdyn_prior_sampler_syn(list(lag = c(2, 8)))
  simulate_fn <- function(theta) {
    lag <- theta$lag
    TX_sim <- T_P + lag
    list(TX_sim = TX_sim, T_P = T_P)
  }
  summary_fn <- function(sim) suppressWarnings(exdyn_summary_tx_response(sim$TX_sim, sim$T_P))
  abc <- exdyn_abc_rejection(
    S_obs = S_obs,
    prior_sampler = prior_fun,
    simulator = simulate_fn,
    summary_fn = summary_fn,
    n_sims = 200,
    eps = 0.6,
    scale = rep(5, length(S_obs)),
    progress = FALSE
  )
  expect_gt(nrow(abc$samples), 0)
  expect_true(abs(mean(abc$samples$lag) - lag_true) < 1.5)
})

test_that("coverage curve summaries are emitted when breaks provided", {
  T_P <- matrix(rep(1950:1951, each = 2), nrow = 2)
  TX <- T_P + matrix(c(0, 5, 10, 15), nrow = 2)
  breaks <- c(1955, 1960)
  S <- exdyn_summary_tx_response(TX, T_P, coverage_breaks = breaks)
  expect_true(all(c("cov_curve_1", "cov_curve_2") %in% names(S)))
  expect_true(S["cov_curve_2"] >= S["cov_curve_1"])
})
