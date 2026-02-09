test_that("arrival override sources produce full coverage", {
  grid <- exdyn_perf_make_grid(nx = 6, ny = 6, seed = 1)
  years <- 2000:2005
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 2
  )
  arrivals$arrival_year[1:5] <- NA_real_

  real_tbl <- exdyn_synthetic_arrival_table(arrivals, grid$grid_info, years, source = "real")
  plane_tbl <- exdyn_synthetic_arrival_table(arrivals, grid$grid_info, years, source = "synthetic_plane")
  grad_tbl <- exdyn_synthetic_arrival_table(arrivals, grid$grid_info, years, source = "synthetic_gradient")

  expect_false(any(duplicated(real_tbl$cell_id)))
  expect_false(any(duplicated(plane_tbl$cell_id)))
  expect_false(any(duplicated(grad_tbl$cell_id)))

  T_P_real <- exdyn_arrival_matrix(real_tbl, grid$grid_info, years)
  T_P_plane <- exdyn_arrival_matrix(plane_tbl, grid$grid_info, years)
  T_P_grad <- exdyn_arrival_matrix(grad_tbl, grid$grid_info, years)

  expect_true(any(!is.finite(T_P_real)))
  expect_true(all(is.finite(T_P_plane)))
  expect_true(all(is.finite(T_P_grad)))

  stats_plane <- exdyn_arrival_coverage_stats(T_P_plane, mask = grid$grid_info$riparian_matrix)
  expect_true(stats_plane$frac_finite_mask >= 0.9)
})
