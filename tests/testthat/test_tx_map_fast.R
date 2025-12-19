test_that("fast TX map matches slow path on toy data", {
  grid_df <- tidyr::expand_grid(row = 1:4, col = 1:4) %>%
    dplyr::mutate(cell_id = dplyr::row_number(), riparian = TRUE)
  grid_sf <- sf::st_as_sf(grid_df, coords = c("col", "row"), remove = FALSE)
  grid_info <- exdyn_grid_lookup(grid_sf)

  set.seed(42)
  cells_df <- tibble::tibble(
    cell_id = sample(grid_df$cell_id, 40, replace = TRUE),
    year = sample(2000:2005, 40, replace = TRUE)
  ) %>%
    dplyr::left_join(grid_df %>% dplyr::select(cell_id, row, col), by = "cell_id")
  effort_df <- tibble::tibble(
    cell_id = sample(grid_df$cell_id, 60, replace = TRUE),
    year = sample(2000:2005, 60, replace = TRUE)
  ) %>%
    dplyr::left_join(grid_df %>% dplyr::select(cell_id, row, col), by = "cell_id")
  cfg <- list(
    smooth_window = 3,
    min_years_active = 2,
    baseline_window = 3,
    drop_fraction = 0.2,
    hold_years = 2,
    normalize_by = "mammal"
  )

  slow <- exdyn_tx_map(cells_df, c(2000, 2005), cfg, grid_info, effort_cells = effort_df, fast = FALSE)
  fast <- exdyn_tx_map(cells_df, c(2000, 2005), cfg, grid_info, effort_cells = effort_df, fast = TRUE)

  expect_equal(fast$matrix, slow$matrix)
  fast_tbl <- fast$table %>% dplyr::arrange(cell_id)
  slow_tbl <- slow$table %>% dplyr::arrange(cell_id)
  expect_equal(fast_tbl$tx_obs, slow_tbl$tx_obs)
  expect_equal(fast_tbl$last_presence, slow_tbl$last_presence)
})
