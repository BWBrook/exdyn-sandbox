skip_if_not_installed("zoo")

grid_info_stub <- list(
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

cfg_vol <- list(
  smooth_window = 1,
  min_years_active = 4,
  baseline_window = 4,
  drop_fraction = 0.2,
  hold_years = 2
)

years <- c(2000, 2010)
base_years <- seq.int(years[1], years[2])

test_that("extirpation requires hold period", {
  counts_vec <- c(rep(5, 4), 1, rep(0, length(base_years) - 5))
  cells <- purrr::map2_dfr(
    base_years, counts_vec,
    ~ if (.y > 0) tibble::tibble(cell_id = 1L, row = 1L, col = 1L, year = rep(.x, .y)) else tibble::tibble()
  )
  counts <- exdyn_cell_timeseries(cells, years, grid_info_stub)
  res <- exdyn_tx_map(cells, years, cfg_vol, grid_info_stub)
  expect_equal(res$matrix[1, 1], 2004)
})

test_that("insufficient history returns NA", {
  cells <- tibble::tibble(
    cell_id = 1L,
    row = 1L,
    col = 1L,
    year = base_years[1:3],
    n = c(3, 0, 0)
  )
  res <- exdyn_tx_map(cells, years, cfg_vol, grid_info_stub)
  expect_true(is.na(res$matrix[1, 1]))
})

test_that("smoother preserves length", {
  vec <- c(0, 1, 3, 2, 0)
  sm <- exdyn_ts_smooth(vec, 3)
  expect_length(sm, length(vec))
  expect_true(all(!is.na(sm)))
})
