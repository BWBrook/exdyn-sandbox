test_that("graph dispersal matches FFT convolution on full grid", {
  skip_if_not_installed("Matrix")
  grid <- exdyn_perf_make_grid(7, 7, seed = 1)
  grid_info <- grid$grid_info
  nx <- grid_info$nx
  ny <- grid_info$ny
  mask <- matrix(TRUE, nrow = nx, ncol = ny)

  graph <- exdyn_land_graph_plan(grid_info, mask = mask, radius = 5L, include_self = TRUE)
  W <- exdyn_land_graph_weights(graph, mean_cells = 2)

  set.seed(42)
  local <- matrix(stats::runif(nx * ny), nrow = nx, ncol = ny)
  ker <- exdyn_kernel(mean_cells = 2, radius = 5L)
  conv_plan <- exdyn_conv2_plan(nx, ny, ker)
  moved_fft <- exdyn_conv2_apply(local, conv_plan)

  local_vec <- local[cbind(graph$rows, graph$cols)]
  moved_vec <- as.numeric(W %*% local_vec)
  moved_graph <- matrix(NA_real_, nrow = nx, ncol = ny)
  moved_graph[cbind(graph$rows, graph$cols)] <- moved_vec

  expect_equal(moved_graph, moved_fft, tolerance = 1e-8)
})

test_that("graph plan respects mask size", {
  skip_if_not_installed("Matrix")
  grid <- exdyn_perf_make_grid(6, 6, seed = 2)
  grid_info <- grid$grid_info
  mask <- matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  mask[1:2, ] <- FALSE
  graph <- exdyn_land_graph_plan(grid_info, mask = mask, radius = 3L, include_self = TRUE)
  expect_equal(graph$n, sum(mask))
})
