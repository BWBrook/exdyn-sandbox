test_that("coverage breaks quantile uses TX values with enough points", {
  TX <- matrix(seq_len(100), nrow = 10)
  brks <- exdyn_coverage_breaks_quantile(TX, n_breaks = 4, years = 2000:2099, min_points = 20)
  expect_length(brks, 4)
  expect_true(all(brks >= min(TX) & brks <= max(TX)))
})

test_that("coverage breaks quantile stays within TX range when quantiles duplicate", {
  TX <- matrix(rep(c(1, 2), 50), nrow = 10)
  brks <- exdyn_coverage_breaks_quantile(TX, n_breaks = 4, years = 2000:2010, min_points = 5)
  expect_length(brks, 4)
  expect_true(all(brks >= min(TX) & brks <= max(TX)))
})

test_that("coverage breaks quantile falls back to years when sparse", {
  TX <- matrix(c(NA, 1, 1, NA), nrow = 2)
  years <- 2000:2010
  brks <- exdyn_coverage_breaks_quantile(TX, n_breaks = 3, years = years, min_points = 20)
  expect_equal(brks, exdyn_coverage_breaks(years, n_breaks = 3))
})

test_that("coverage breaks resolve respects strategy and fallback", {
  TX <- matrix(seq_len(100), nrow = 10)
  brks <- exdyn_coverage_breaks_resolve(
    list(strategy = "tx_quantile", n_breaks = 3, min_points = 5),
    TX = TX,
    years = 2000:2050
  )
  expect_length(brks, 3)
  brks_years <- exdyn_coverage_breaks_resolve(NULL, TX = TX, years = 2000:2004, n_breaks = 2)
  expect_equal(brks_years, exdyn_coverage_breaks(2000:2004, n_breaks = 2))
})
