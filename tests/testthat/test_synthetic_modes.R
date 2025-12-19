test_that("synthetic mode selection uses TX_true vs TX_obs", {
  truth <- list(
    TX_true = matrix(1, nrow = 2, ncol = 2),
    TX_obs = matrix(2, nrow = 2, ncol = 2),
    T_P = matrix(0, nrow = 2, ncol = 2)
  )
  ideal <- exdyn_synthetic_tx_by_mode(truth, "ideal")
  realistic <- exdyn_synthetic_tx_by_mode(truth, "realistic")
  expect_equal(ideal$TX_use, truth$TX_true)
  expect_equal(realistic$TX_use, truth$TX_obs)
})
