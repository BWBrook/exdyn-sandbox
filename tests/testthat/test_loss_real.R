test_that("real loss aggregates each analysis unit using the earliest finite cell value", {
  TX_obs <- matrix(
    c(2008, 2004,
      2015, 2013,
      2020, NA),
    nrow = 3,
    byrow = TRUE
  )
  TX_sim <- matrix(
    c(2009, 2006,
      2014, 2011,
      2021, 2018),
    nrow = 3,
    byrow = TRUE
  )
  T_P <- matrix(
    c(2001, 2000,
      2006, 2005,
      2012, 2010),
    nrow = 3,
    byrow = TRUE
  )
  unit_lookup <- tibble::tibble(
    row_idx = c(1L, 1L, 2L, 2L, 3L, 3L),
    col_idx = c(1L, 2L, 1L, 2L, 1L, 2L),
    unit_id = c("u1", "u1", "u2", "u2", "u3", "u3")
  )

  res <- exdyn_loss_real(
    TX_obs = TX_obs,
    T_P = T_P,
    TX_sim = TX_sim,
    unit_lookup = unit_lookup,
    coverage_breaks = c(2005, 2010, 2015),
    compat_cfg = list(lag_range = c(0, 40))
  )

  joined <- res$units_joined[order(res$units_joined$unit_id), ]
  expect_equal(joined$tx_obs, c(2004, 2013, 2020))
  expect_equal(joined$tx_sim, c(2006, 2011, 2018))
  expect_equal(joined$tp, c(2000, 2005, 2010))
  expect_true(is.finite(res$loss))
  expect_true(is.finite(res$r2_arrival))
})
