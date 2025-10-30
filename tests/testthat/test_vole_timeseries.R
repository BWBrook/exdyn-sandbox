test_that("exdyn_cell_timeseries completes within cell", {
  df <- tibble::tibble(
    cell_id = c(1L, 2L),
    row = c(1L, 2L),
    col = c(1L, 2L),
    year = c(2000L, 2002L)
  )
  years <- c(2000L, 2002L)
  grid_info <- list(row_levels = 1:2, col_levels = 1:2)
  res <- exdyn_cell_timeseries(df, years, grid_info)
  expect_equal(nrow(res), 2L * length(seq.int(years[1], years[2])))
  expect_true(all(res$n_obs %in% 0:1))
})
