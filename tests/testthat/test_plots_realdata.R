skip_if_not_installed("sf")

poly <- sf::st_make_grid(sf::st_as_sfc(sf::st_bbox(c(xmin = 0, xmax = 2, ymin = 0, ymax = 2))), n = c(2, 2))
plot_grid <- sf::st_sf(cell_id = 1:4, geometry = poly)
plot_grid$row <- rep(2:1, each = 2)
plot_grid$col <- rep(1:2, times = 2)
arrivals <- tibble::tibble(cell_id = 1:4, arrival_year_raw = c(2000, 2001, 2002, NA), arrival_year_smooth = c(2000, 2001, 2002, 2003))
counts <- tibble::tibble(cell_id = c(1,1,2,3,3,4), row = NA_integer_, col = NA_integer_, year = c(2000, 2001, 2000, 1999, 2000, 2001))


test_that("arrival map returns ggplot", {
  p <- exdyn_plot_arrival_map(plot_grid, arrivals, "Test map")
  expect_s3_class(p, "ggplot")
})


test_that("density map returns ggplot", {
  p <- exdyn_occ_density_map(plot_grid, counts, "Density")
  expect_s3_class(p, "ggplot")
})

test_that("surface and scatter helpers return ggplot objects", {
  grid_info <- exdyn_grid_lookup(plot_grid)
  mat <- matrix(c(2000, 2001, 2002, NA_real_), nrow = 2)
  p_surface <- exdyn_plot_surface(mat, grid_info, "Surface")
  p_scatter <- exdyn_plot_tx_scatter(mat, matrix(c(1998, 2000, 2003, 2001), nrow = 2))
  expect_s3_class(p_surface, "ggplot")
  expect_s3_class(p_scatter, "ggplot")
})
