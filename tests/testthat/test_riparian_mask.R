skip_if_not_installed("sf")

library(sf)

test_that("river length aggregates per cell", {
  poly <- st_sfc(st_polygon(list(rbind(c(0, 0), c(1000, 0), c(1000, 1000), c(0, 1000), c(0, 0)))) , crs = 27700)
  grid <- st_sf(cell_id = 1L, row = 1L, col = 1L, geometry = poly)
  line <- st_sfc(st_linestring(matrix(c(0, 500, 1000, 500), ncol = 2, byrow = TRUE)), crs = 27700)
  rivers <- st_sf(id = 1L, geometry = line)
  lengths <- exdyn_river_length_by_cell(rivers, grid)
  expect_equal(lengths$river_km, 1) # 1 km segment
})

test_that("riparian mask flags cells above threshold", {
  poly <- st_sfc(st_polygon(list(rbind(c(0, 0), c(1000, 0), c(1000, 1000), c(0, 1000), c(0, 0)))), crs = 27700)
  grid <- st_sf(cell_id = 1L, row = 1L, col = 1L, geometry = poly)
  line <- st_sfc(st_linestring(matrix(c(0, 500, 1000, 500), ncol = 2, byrow = TRUE)), crs = 27700)
  rivers <- st_sf(id = 1L, geometry = line)
  mask <- exdyn_make_riparian_mask(grid, rivers, tau_km = 0.5)
  expect_true(mask$riparian)
  mask_low <- exdyn_make_riparian_mask(grid, rivers, tau_km = 2)
  expect_false(mask_low$riparian)
})

test_that("arrival adjustment applies regional delta", {
  poly <- st_sfc(st_polygon(list(rbind(c(0, 0), c(1000, 0), c(1000, 1000), c(0, 1000), c(0, 0)))), crs = 27700)
  grid <- st_sf(cell_id = 1L, row = 1L, col = 1L, region = "SCT", geometry = poly)
  grid_info <- exdyn_grid_lookup(grid)
  T_P <- matrix(2000, nrow = grid_info$nx, ncol = grid_info$ny)
  adj <- exdyn_adjust_arrival_matrix(T_P, grid_info, c(SCT = 3), 1975:2024)
  expect_equal(adj[1, 1], 1997)
})
