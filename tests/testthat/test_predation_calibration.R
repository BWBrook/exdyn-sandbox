skip_if_not_installed("lhs")

grid_info_one <- list(
  lookup = tibble::tibble(
    cell_id = 1L,
    row = 1L,
    col = 1L,
    row_idx = 1L,
    col_idx = 1L
  ),
  row_levels = 1L,
  col_levels = 1L,
  nx = 1L,
  ny = 1L
)

test_that("P_from_arrival applies scale and gamma", {
  arrivals <- tibble::tibble(cell_id = 1L, arrival_year = 2000L)
  years <- 1995:2005
  base <- exdyn_P_from_arrival(arrivals, grid_info_one, years, ramp_years = 4, pre_leak = 0, scale = 1, gamma = 1)
  scaled <- exdyn_P_from_arrival(arrivals, grid_info_one, years, ramp_years = 4, pre_leak = 0, scale = 2, gamma = 2)
  arrival_idx <- which(years >= 2000L)
  expect_true(all(scaled$P[1, 1, years < 2000L] == 0))
  expect_equal(
    scaled$P[1, 1, arrival_idx],
    (base$P[1, 1, arrival_idx] ^ 2) * 2,
    tolerance = 1e-8
  )
  expect_equal(attr(scaled, "scale"), 2)
  expect_equal(attr(scaled, "gamma"), 2)
})

test_that("c_critical matches analytic expression", {
  K0 <- 100
  rmax <- 0.4
  h <- 10
  N0 <- K0 * 0.1
  r_eff <- rmax * exdyn_fS(1)
  expected <- ((r_eff * (1 - N0 / K0)) - 0.03) / (N0 / (h + N0))
  crit <- exdyn_c_critical(K0, rmax, h)
  expect_equal(drop(crit), expected)
})

test_that("param_lhs includes predation scale and gamma bounds", {
  cfg <- list(
    n_draws = 5,
    alpha = c(0, 0.5),
    disp_mean_km = c(5, 15),
    A_over_K = c(0, 0.2),
    pred_c = c(0.4, 0.8),
    pred_h = c(10, 20),
    ramp_years = c(4, 10),
    pred_scale = c(0.5, 2),
    gamma = c(1, 2),
    rmax = c(0.3, 0.5),
    K0 = 100
  )
  draws <- exdyn_param_lhs(cfg, n = 20, cell_km = 10, seed = 1)
  expect_true(all(draws$pred_scale >= cfg$pred_scale[1] & draws$pred_scale <= cfg$pred_scale[2]))
  expect_true(all(draws$gamma >= cfg$gamma[1] & draws$gamma <= cfg$gamma[2]))
  expect_true(all(c("pred_scale", "gamma") %in% names(draws)))
})
