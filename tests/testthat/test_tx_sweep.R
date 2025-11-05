test_that("tx sweep funnels capture drop-off reasons", {
  cfg <- list(
    smooth_window = 3,
    min_years_active = 3,
    baseline_window = 4,
    drop_fraction = 0.3,
    hold_years = 2,
    normalize_by = "none"
  )
  years <- c(2000L, 2009L)
  cells <- tibble::tibble(
    cell_id = c(1L, 1L, 1L, 2L, 2L),
    row = c(1L, 1L, 1L, 1L, 1L),
    col = c(1L, 1L, 1L, 2L, 2L),
    year = c(2000L, 2001L, 2002L, 2000L, 2008L)
  )
  grid_sf <- sf::st_sf(
    cell_id = c(1L, 2L),
    row = c(1L, 1L),
    col = c(1L, 2L),
    geometry = sf::st_sfc(
      sf::st_polygon(list(rbind(c(0, 0), c(1, 0), c(1, 1), c(0, 1), c(0, 0)))),
      sf::st_polygon(list(rbind(c(1, 0), c(2, 0), c(2, 1), c(1, 1), c(1, 0))))
    )
  )
  grid_info <- exdyn_grid_lookup(grid_sf)
  res <- exdyn_tx_apply_cfg(cells, years, cfg, grid_info, normalize_by = "none")
  expect_equal(nrow(res$results), 2)
  expect_true("reason" %in% names(res$results))
  expect_equal(res$funnel$n_units[res$funnel$stage == "any_record"], 2)
})
