test_that("segment tx aggregates component counts", {
  cfg <- list(
    smooth_window = 3,
    min_years_active = 2,
    baseline_window = 3,
    drop_fraction = 0.5,
    hold_years = 2,
    normalize_by = "none"
  )
  years <- c(2000L, 2005L)
  cells <- tibble::tibble(
    cell_id = c(1L, 1L, 2L, 2L, 3L, 3L),
    row = c(1L, 1L, 1L, 1L, 2L, 2L),
    col = c(1L, 1L, 2L, 2L, 1L, 1L),
    year = c(2000L, 2001L, 2000L, 2004L, 2000L, 2005L)
  )
  comp_lookup <- tibble::tibble(
    cell_id = c(1L, 2L, 3L),
    comp_id = c(1L, 1L, 2L),
    n_cells_comp = c(2L, 2L, 1L)
  )
  seg <- exdyn_segment_tx(cells, comp_lookup, years, cfg, normalize_by = "none")
  expect_equal(sort(unique(seg$comp_id)), c(1L, 2L))
  expect_true(all(c("tx_obs", "reason", "threshold_mode") %in% names(seg)))
})
