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

grid_info_multi <- list(
  lookup = tibble::tibble(
    cell_id = c(1L, 2L),
    row = c(1L, 2L),
    col = c(1L, 1L),
    row_idx = c(1L, 2L),
    col_idx = c(1L, 1L)
  ),
  row_levels = c(1L, 2L),
  col_levels = 1L,
  nx = 2L,
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

test_that("extirpation waits until final sustained decline", {
  years_long <- c(2000L, 2015L)
  series_years <- seq.int(years_long[1], years_long[2])
  series <- c(rep(4, 5), rep(0, 3), rep(5, 2), rep(0, length(series_years) - 10))
  cells <- purrr::map2_dfr(
    series_years, series,
    ~ if (.y > 0) tibble::tibble(cell_id = 1L, row = 1L, col = 1L, year = rep(.x, .y)) else tibble::tibble()
  )
  res <- exdyn_tx_map(cells, years_long, cfg_vol, grid_info_stub)
  expect_equal(res$matrix[1, 1], 2010)
})

test_that("insufficient history returns NA", {
  years_subset <- base_years[1:3]
  counts_vec <- c(3, 0, 0)
  cells <- purrr::map2_dfr(
    years_subset, counts_vec,
    ~ if (.y > 0) tibble::tibble(cell_id = 1L, row = 1L, col = 1L, year = rep(.x, .y)) else tibble::tibble()
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

test_that("cell timeseries joins effort counts correctly", {
  cells <- tibble::tibble(
    cell_id = c(1L, 1L, 2L, 2L),
    row = c(1L, 1L, 2L, 2L),
    col = 1L,
    year = c(2000L, 2002L, 2001L, 2003L)
  )
  effort <- tibble::tibble(
    cell_id = c(1L, 2L, 2L),
    row = c(1L, 2L, 2L),
    col = 1L,
    year = c(2000L, 2001L, 2004L)
  )
  counts <- exdyn_cell_timeseries(cells, c(2000L, 2004L), grid_info_multi, effort_cells = effort)
  expect_true(all(c("n_mammal", "norm_mammal") %in% names(counts)))
  expect_equal(dplyr::filter(counts, cell_id == 1L, year == 2000L)$n_mammal, 1L)
  expect_equal(dplyr::filter(counts, cell_id == 1L, year == 2002L)$n_mammal, 0L)
  expect_equal(dplyr::filter(counts, cell_id == 2L, year == 2001L)$n_mammal, 1L)
})

test_that("normalisation can change extirpation detection", {
  cfg_norm <- utils::modifyList(cfg_vol, list(
    smooth_window = 1,
    baseline_window = 3,
    min_years_active = 3,
    hold_years = 1,
    normalize_by = "taxa"
  ))
  years_short <- c(2000L, 2005L)
  series_data <- tibble::tibble(
    year = rep(seq.int(years_short[1], years_short[2]), times = c(5, 5, 5, 1, 1, 1)),
    cell_id = 1L,
    row = 1L,
    col = 1L
  )
  cells <- series_data
  effort <- tibble::tibble(
    cell_id = 1L,
    row = 1L,
    col = 1L,
    year = rep(seq.int(years_short[1], years_short[2]), times = c(5, 5, 5, 10, 10, 10))
  )
  res_norm <- exdyn_tx_map(cells, years_short, cfg_norm, grid_info_stub, effort_cells = effort)
  res_raw <- exdyn_tx_map(cells, years_short, utils::modifyList(cfg_norm, list(normalize_by = NULL)), grid_info_stub)
  expect_true(is.na(res_norm$matrix[1, 1]) || res_norm$matrix[1, 1] >= res_raw$matrix[1, 1])
})

test_that("cell timeseries rows scale with cells not cross-product", {
  df <- tibble::tibble(
    cell_id = c(1L, 2L),
    row = c(1L, 2L),
    col = c(1L, 1L),
    year = c(2000L, 2002L)
  )
  counts <- exdyn_cell_timeseries(df, c(2000L, 2002L), grid_info_multi)
  expect_equal(nrow(counts), 2L * length(2000:2002))
})

test_that("auto threshold mode switches between raw and normalized series", {
  cfg_auto <- utils::modifyList(cfg_vol, list(
    smooth_window = 1,
    min_years_active = 3,
    baseline_window = 3,
    hold_years = 1,
    threshold_mode = "auto"
  ))
  counts_tbl <- tibble::tibble(
    year = 2000:2004,
    n_obs = c(2L, 2L, 2L, 0L, 0L),
    n_mammal = c(1L, 1L, 1L, 10L, 10L),
    norm_mammal = c(2, 2, 2, 0, 0)
  )

  res_raw <- exdyn_tx_from_po(counts_tbl, c(2000L, 2004L), cfg_auto, normalize_by = "none")
  res_norm <- exdyn_tx_from_po(counts_tbl, c(2000L, 2004L), cfg_auto, normalize_by = "mammal")

  expect_identical(res_raw$threshold_mode, "count_floor")
  expect_identical(res_norm$threshold_mode, "relative_baseline")
  expect_equal(res_raw$tau, 1)
  expect_equal(res_norm$tau, 0.4)
})

test_that("explicit threshold mode overrides auto selection", {
  counts_tbl <- tibble::tibble(
    year = 2000:2004,
    n_obs = c(2L, 2L, 2L, 0L, 0L),
    n_mammal = c(1L, 1L, 1L, 10L, 10L),
    norm_mammal = c(2, 2, 2, 0, 0)
  )
  cfg_rel <- utils::modifyList(cfg_vol, list(
    smooth_window = 1,
    min_years_active = 3,
    baseline_window = 3,
    hold_years = 1,
    threshold_mode = "relative_baseline"
  ))
  cfg_floor <- utils::modifyList(cfg_vol, list(
    smooth_window = 1,
    min_years_active = 3,
    baseline_window = 3,
    hold_years = 1,
    threshold_mode = "count_floor"
  ))

  res_rel <- exdyn_tx_from_po(counts_tbl, c(2000L, 2004L), cfg_rel, normalize_by = "none")
  res_floor <- exdyn_tx_from_po(counts_tbl, c(2000L, 2004L), cfg_floor, normalize_by = "mammal")

  expect_identical(res_rel$threshold_mode, "relative_baseline")
  expect_identical(res_floor$threshold_mode, "count_floor")
  expect_equal(res_rel$tau, 0.4)
  expect_equal(res_floor$tau, 1)
})

test_that("tx maps retain threshold diagnostics in exported tables", {
  cfg_norm <- utils::modifyList(cfg_vol, list(
    smooth_window = 1,
    baseline_window = 3,
    min_years_active = 3,
    hold_years = 1,
    normalize_by = "mammal",
    threshold_mode = "auto"
  ))
  years_short <- c(2000L, 2004L)
  cells <- tibble::tibble(
    cell_id = c(rep(1L, 6), rep(1L, 2)),
    row = 1L,
    col = 1L,
    year = c(rep(2000L, 2), rep(2001L, 2), rep(2002L, 2), 2003L, 2004L)
  )
  effort <- tibble::tibble(
    cell_id = rep(1L, 24),
    row = 1L,
    col = 1L,
    year = rep(2000:2004, times = c(4, 4, 4, 6, 6))
  )

  res <- exdyn_tx_map(cells, years_short, cfg_norm, grid_info_stub, effort_cells = effort, fast = FALSE)

  expect_true(all(c("baseline", "tau", "threshold_mode", "reason") %in% names(res$table)))
  expect_identical(res$table$threshold_mode[[1]], "relative_baseline")
})
