skip_if_not_installed("sf")

poly <- sf::st_make_grid(sf::st_as_sfc(sf::st_bbox(c(xmin = 0, xmax = 2, ymin = 0, ymax = 2))), n = c(2, 2))
plot_grid <- sf::st_sf(cell_id = 1:4, geometry = poly)
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
