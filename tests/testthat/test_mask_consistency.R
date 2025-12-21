test_that("summary and score use mask consistently", {
  TX <- matrix(c(2005, NA, 2006, NA), nrow = 2, byrow = TRUE)
  T_P <- matrix(c(2000, 2001, 2002, 2003), nrow = 2, byrow = TRUE)
  mask <- matrix(c(TRUE, FALSE, TRUE, FALSE), nrow = 2, byrow = TRUE)
  breaks <- c(2005)

  summary_masked <- exdyn_summary_tx_response(TX, T_P, coverage_breaks = breaks, mask = mask)
  summary_unmasked <- exdyn_summary_tx_response(TX, T_P, coverage_breaks = breaks)
  score_masked <- exdyn_score(
    TX_obs = TX,
    T_P = T_P,
    TX_sim = TX,
    compat_cfg = list(min_r2_arrival = 0, lag_range = c(-Inf, Inf), min_coverage = 0),
    coverage_breaks = breaks,
    mask = mask
  )

  expect_equal(summary_masked[["coverage"]], 1)
  expect_equal(summary_unmasked[["coverage"]], 0.5)
  expect_equal(summary_masked[["coverage"]], score_masked$coverage)

  counts <- exdyn_summary_counts(TX, T_P, mask = mask)
  expect_equal(counts[["n_mask"]], 2)
  expect_equal(counts[["n_TP_finite"]], 2)
  expect_equal(counts[["n_TX_finite"]], 2)
  expect_equal(counts[["n_pairs"]], 2)
})
