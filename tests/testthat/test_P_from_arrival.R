grid_info_two <- list(
  lookup = tibble::tibble(
    cell_id = c(1L, 2L),
    row = c(1L, 1L),
    col = c(1L, 2L),
    row_idx = c(1L, 1L),
    col_idx = c(1L, 2L)
  ),
  row_levels = 1L,
  col_levels = c(1L, 2L),
  nx = 1L,
  ny = 2L
)

years_short <- 2000:2005

test_that("predation field ramps after arrival", {
  arrivals <- tibble::tibble(
    cell_id = c(1L, 2L),
    arrival_year_smooth = c(2001, NA)
  )
  res <- exdyn_P_from_arrival(arrivals, grid_info_two, years_short, ramp_years = 3)
  vals <- res$P[1, 1, ]
  expect_true(all(diff(vals[years_short >= 2001]) >= -1e-6))
  expect_equal(res$T_P[1, 1], 2001)
  expect_true(all(res$P[1, 2, ] == 0))
})
