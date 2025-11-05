skip_if_not_installed("sf")

library(sf)

test_that("grid aggregation maps cells to coarse lattice", {
  poly <- st_sfc(st_polygon(list(rbind(
    c(0, 0), c(2000, 0), c(2000, 2000), c(0, 2000), c(0, 0)
  ))), crs = 27700)
  grid <- st_make_grid(poly, cellsize = 1000, what = "polygons")
  grid_sf <- st_sf(
    cell_id = seq_along(grid),
    row = rep(2:1, each = 2),
    col = rep(1:2, times = 2),
    geometry = grid
  )
  grid_sf$centroid_x <- st_coordinates(st_centroid(grid_sf))[, 1]
  grid_sf$centroid_y <- st_coordinates(st_centroid(grid_sf))[, 2]
  agg <- exdyn_aggregate_grid(grid_sf, cell_km_new = 2)
  expect_equal(unique(agg$grid$cell_km), 2)
  expect_equal(nrow(agg$grid), 1)
  expect_true(all(agg$mapping$cell_id_new == agg$grid$cell_id[1]))
})

test_that("cell rebin preserves counts", {
  cells <- tibble::tibble(
    cell_id = c(1L, 2L, 3L, 4L),
    row = c(2L, 2L, 1L, 1L),
    col = c(1L, 2L, 1L, 2L),
    year = c(2000L, 2001L, 2002L, 2003L)
  )
  poly <- st_sfc(st_polygon(list(rbind(
    c(0, 0), c(2000, 0), c(2000, 2000), c(0, 2000), c(0, 0)
  ))), crs = 27700)
  grid <- st_make_grid(poly, cellsize = 1000, what = "polygons")
  grid_sf <- st_sf(
    cell_id = seq_along(grid),
    row = rep(2:1, each = 2),
    col = rep(1:2, times = 2),
    geometry = grid
  )
  grid_sf$centroid_x <- st_coordinates(st_centroid(grid_sf))[, 1]
  grid_sf$centroid_y <- st_coordinates(st_centroid(grid_sf))[, 2]
  agg <- exdyn_aggregate_grid(grid_sf, cell_km_new = 2)
  rebinned <- exdyn_rebin_cells(cells, agg$mapping, agg$grid)
  expect_equal(nrow(rebinned), nrow(cells))
  expect_true(all(rebinned$cell_id == agg$grid$cell_id[1]))
})
