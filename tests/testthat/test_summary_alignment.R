test_that("coverage breakpoints are stable", {
  breaks <- exdyn_coverage_breaks(2000:2010)
  expect_equal(breaks, c(2002, 2004, 2006, 2008))
})

test_that("summary schema matches output names", {
  T_P <- matrix(1950, nrow = 2, ncol = 2)
  TX <- T_P + 5
  breaks <- exdyn_coverage_breaks(1950:1960)
  S <- suppressWarnings(exdyn_summary_tx_response(TX, T_P, years = 1950:1960, coverage_breaks = breaks))
  expect_identical(names(S), exdyn_summary_schema()$summary_names)
})

test_that("lag sign convention is TX minus T_P", {
  T_P <- matrix(1950, nrow = 2, ncol = 2)
  TX <- T_P + 7
  S <- suppressWarnings(exdyn_summary_tx_response(TX, T_P, coverage_breaks = c(1955, 1960)))
  expect_gt(S["lag_mean"], 0)
})
