test_that("convolution reuse buffer matches baseline output", {
  mat <- matrix(stats::rnorm(25), nrow = 5, ncol = 5)
  ker <- exdyn_kernel(mean_cells = 1, radius = 1L)
  plan_base <- exdyn_conv2_plan(5, 5, ker, reuse_buffer = FALSE)
  plan_reuse <- exdyn_conv2_plan(5, 5, ker, reuse_buffer = TRUE)
  out_base <- exdyn_conv2_apply(mat, plan_base)
  out_reuse <- exdyn_conv2_apply(mat, plan_reuse)
  expect_equal(out_base, out_reuse, tolerance = 1e-8)
})
