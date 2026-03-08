test_that("real loss aggregates each analysis unit using the median finite cell value", {
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
    unit_id = c("u1", "u1", "u2", "u2", "u3", "u3"),
    centroid_x = c(0, 1, 0, 1, 0, 1),
    centroid_y = c(2, 2, 1, 1, 0, 0)
  )

  res <- exdyn_loss_real(
    TX_obs = TX_obs,
    T_P = T_P,
    TX_sim = TX_sim,
    unit_lookup = unit_lookup,
    coverage_breaks = c(2005, 2010, 2015),
    compat_cfg = list(lag_range = c(0, 40)),
    unit_timing_stat = "median"
  )

  joined <- res$units_joined[order(res$units_joined$unit_id), ]
  expect_equal(joined$tx_obs, c(2006, 2014, 2020))
  expect_equal(joined$tx_sim, c(2007.5, 2012.5, 2019.5))
  expect_equal(joined$tp, c(2000.5, 2005.5, 2011))
  expect_equal(res$coverage, 1)
  expect_equal(res$coverage_obs, 1)
  expect_equal(res$lag_mean, mean(c(7, 7, 8.5)))
  expect_identical(res$unit_timing_stat, "median")
  expect_true(is.finite(res$loss))
  expect_true(is.finite(res$r2_arrival))
})

test_that("real loss geometry responds to unit centroids rather than grid placement", {
  TX_obs <- matrix(c(2001, 2002, 2003, 2004), nrow = 2)
  TX_sim <- TX_obs
  T_P <- matrix(c(1998, 1999, 2000, 2001), nrow = 2)

  lookup_linear <- tibble::tibble(
    row_idx = c(1L, 1L, 2L, 2L),
    col_idx = c(1L, 2L, 1L, 2L),
    unit_id = paste0("u", 1:4),
    centroid_x = c(0, 1, 2, 3),
    centroid_y = c(0, 0, 0, 0)
  )
  lookup_zigzag <- tibble::tibble(
    row_idx = c(1L, 1L, 2L, 2L),
    col_idx = c(1L, 2L, 1L, 2L),
    unit_id = paste0("u", 1:4),
    centroid_x = c(0, 1, 0, 1),
    centroid_y = c(0, 0, 1, 1)
  )

  linear <- exdyn_loss_real(
    TX_obs = TX_obs,
    T_P = T_P,
    TX_sim = TX_sim,
    unit_lookup = lookup_linear,
    coverage_breaks = c(2002, 2004),
    compat_cfg = list(lag_range = c(0, 40))
  )
  zigzag <- exdyn_loss_real(
    TX_obs = TX_obs,
    T_P = T_P,
    TX_sim = TX_sim,
    unit_lookup = lookup_zigzag,
    coverage_breaks = c(2002, 2004),
    compat_cfg = list(lag_range = c(0, 40))
  )

  expect_true(is.finite(linear$anisotropy_obs))
  expect_true(is.finite(zigzag$anisotropy_obs))
  expect_false(isTRUE(all.equal(linear$anisotropy_obs, zigzag$anisotropy_obs)))
  expect_equal(linear$anisotropy_gap, 0)
  expect_equal(zigzag$anisotropy_gap, 0)
})
