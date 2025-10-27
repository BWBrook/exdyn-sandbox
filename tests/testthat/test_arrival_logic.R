skip_if_not_installed("sf")

arrival_params <- list(
  min_events_cell = 2,
  window_years = 1,
  neigh_radius_cells = 1,
  min_support_neigh = 1,
  outlier_iso_years = 5
)

cells_df <- tibble::tibble(
  cell_id = c(1,1,1, 2,2,2, 3,3, 4,4),
  row = c(1,1,1, 2,2,2, 3,3, 3,3),
  col = c(1,1,1, 1,1,1, 1,1, 2,2),
  year = c(2000,2000,2001, 2000,2001,2002, 2015,2016, 2005,2005)
)

arrivals <- exdyn_arrival_from_cells(cells_df, c(1999, 2018), arrival_params)

test_that("arrival logic captures earliest supported year", {
  expect_equal(arrivals$arrival_year_raw[arrivals$cell_id == 1], 2000)
  expect_equal(arrivals$arrival_year_raw[arrivals$cell_id == 2], 2000)
})

test_that("outlier gap removes isolated early hits", {
  expect_true(is.na(arrivals$arrival_year_raw[arrivals$cell_id == 4]))
})

# smoothing test with synthetic grid
smooth_grid <- sf::st_make_grid(sf::st_as_sfc(sf::st_bbox(c(xmin = 0, xmax = 2, ymin = 0, ymax = 2))), n = c(2, 2))
smooth_grid <- sf::st_sf(cell_id = 1:4, row = c(1,1,2,2), col = c(1,2,1,2), geometry = smooth_grid)
arrivals_for_smooth <- tibble::tibble(
  cell_id = 1:4,
  row = c(1,1,2,2),
  col = c(1,2,1,2),
  arrival_year_raw = c(2000, 2001, 2002, NA_integer_)
)

arrivals_smoothed <- exdyn_arrival_smooth(arrivals_for_smooth, smooth_grid)

test_that("smoothing fills small holes", {
  expect_equal(arrivals_smoothed$arrival_year_smooth[arrivals_smoothed$cell_id == 4], 2003)
})
