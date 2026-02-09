test_that("scoring captures lag and coverage", {
  TX_obs <- matrix(c(2002, 2004, NA, 2005), nrow = 2)
  T_P <- matrix(c(2000, 2003, 2001, 2004), nrow = 2)
  TX_sim <- matrix(c(2001, 2004, NA, 2006), nrow = 2)
  cfg <- list(
    min_r2_arrival = 0.1,
    lag_range = c(1, 10),
    min_coverage = 0.2
  )
  score <- exdyn_score(TX_obs, T_P, TX_sim, cfg)
  expect_true(score$coverage > 0.4)
  expect_true(score$lag_mean > 0)
  expect_true(score$loss >= 0)
  expect_true("coverage_obs" %in% names(score))
  expect_true("r2_arrival_obs" %in% names(score))
  expect_true("lag_mean_obs" %in% names(score))
})

test_that("compatibility is driven by simulated, not observed, support", {
  T_P <- matrix(c(2000, 2000, 2000, 2000), nrow = 2)
  TX_obs <- matrix(c(2002, 2002, 2002, 2002), nrow = 2)
  TX_sim_sparse <- matrix(c(2002, NA, NA, NA), nrow = 2)
  cfg <- list(
    min_r2_arrival = 0,
    lag_range = c(-Inf, Inf),
    min_coverage = 0.5
  )
  score <- exdyn_score(TX_obs, T_P, TX_sim_sparse, cfg)
  expect_lt(score$coverage, cfg$min_coverage)
  expect_false(score$compatible)
  expect_gt(score$coverage_obs, score$coverage)
})
