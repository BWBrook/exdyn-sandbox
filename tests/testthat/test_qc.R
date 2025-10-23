test_that("predation front monotonicity is enforced", {
  P <- array(rep(seq(0, 1, length.out = 4), each = 9), dim = c(3, 3, 4))
  fields <- list(P = P)
  expect_equal(exdyn.sandbox:::exdyn_qc_monotone_P(fields), 1)

  P_bad <- P
  P_bad[1, 1, 3] <- 0.1
  fields_bad <- list(P = P_bad)
  expect_lt(exdyn.sandbox:::exdyn_qc_monotone_P(fields_bad), 1)
})

test_that("early extirpation QC tracks small initial fractions", {
  N <- array(10, dim = c(4, 4, 5))
  N[, , 5] <- 0.5
  N[1, 1, 1] <- 0.4
  N[1, 1, 2] <- 6
  qc <- exdyn.sandbox:::exdyn_qc_early_extirpation(N, K0 = 100, frac = 0.02, adaptive = TRUE, rel0 = 0.5)
  expect_lt(qc$initial_below_frac, 0.1)
  expect_lt(qc$non_first_passage_frac, 0.1)
})

test_that("presence-only counts correlate with total abundance", {
  yrs <- 6
  totals <- seq(20, 70, length.out = yrs)
  N <- array(rep(totals, each = 9), dim = c(3, 3, yrs))
  po <- data.frame(t = rep(seq_len(yrs), times = seq_len(yrs)))
  qc <- exdyn.sandbox:::exdyn_qc_po_sanity(N, po)
  expect_gt(qc$correlation, 0.7)
})

test_that("arrival lag QC reports positive lag when T_X exceeds T_P", {
  T_P <- matrix(rep(1:4, each = 4), nrow = 4, ncol = 4)
  offsets <- matrix(
    c(
      0.2, 0.3, 0.25, 0.28,
      0.35, 0.4, 0.33, 0.31,
      0.5, 0.55, 0.52, 0.56,
      0.6, 0.65, 0.68, 0.62
    ),
    nrow = 4, byrow = TRUE
  )
  T_X <- T_P + offsets
  res <- exdyn.sandbox:::exdyn_qc_tp_tx_lag(T_P, T_X)
  expect_equal(res$coverage, 1)
  expect_gt(res$lag_arrival_mean, 0)
})
