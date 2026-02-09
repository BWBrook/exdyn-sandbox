test_that("orientation metrics match reference implementation", {
  orientation_ref <- function(T_X) {
    if (is.null(T_X)) {
      return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = 0))
    }
    nx <- nrow(T_X); ny <- ncol(T_X)
    if (nx < 3 || ny < 3) {
      return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = 0))
    }
    sobel_x <- matrix(c(1, 0, -1, 2, 0, -2, 1, 0, -1), nrow = 3, byrow = TRUE)
    sobel_y <- matrix(c(1, 2, 1, 0, 0, 0, -1, -2, -1), nrow = 3, byrow = TRUE)
    grads <- matrix(NA_real_, nrow = nx * ny, ncol = 2)
    idx <- 0L
    for (i in 2:(nx - 1)) {
      for (j in 2:(ny - 1)) {
        window <- T_X[(i - 1):(i + 1), (j - 1):(j + 1)]
        if (anyNA(window)) next
        gx <- sum(window * sobel_x)
        gy <- sum(window * sobel_y)
        idx <- idx + 1L
        grads[idx, ] <- c(gx, gy)
      }
    }
    if (idx == 0L) {
      return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = 0))
    }
    grads <- grads[seq_len(idx), , drop = FALSE]
    mags <- sqrt(grads[, 1]^2 + grads[, 2]^2)
    positive <- mags > 0
    if (!any(positive)) {
      return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = idx))
    }
    unit_vecs <- grads[positive, , drop = FALSE] / mags[positive]
    sum_unit <- colSums(unit_vecs)
    R <- sqrt(sum_unit[1]^2 + sum_unit[2]^2) / nrow(unit_vecs)
    dominant <- colSums(grads)
    dom_mag <- sqrt(sum(dominant^2))
    if (dom_mag > 0) {
      dominant <- dominant / dom_mag
    } else if (sqrt(sum(sum_unit^2)) > 0) {
      dominant <- sum_unit / sqrt(sum(sum_unit^2))
    } else {
      dominant <- c(NA_real_, NA_real_)
    }
    list(R = R, dominant = dominant, count = nrow(unit_vecs))
  }

  set.seed(101)
  T_X <- matrix(stats::rnorm(120), nrow = 10, ncol = 12)
  T_X[sample(length(T_X), size = 12)] <- NA_real_
  ref <- orientation_ref(T_X)
  vec <- exdyn.sandbox:::exdyn_orientation_metrics(T_X)
  expect_equal(vec$count, ref$count)
  expect_equal(vec$R, ref$R, tolerance = 1e-10)
  expect_equal(vec$dominant, ref$dominant, tolerance = 1e-10)

  T_na <- matrix(NA_real_, nrow = 4, ncol = 4)
  res_na <- exdyn.sandbox:::exdyn_orientation_metrics(T_na)
  expect_true(is.na(res_na$R))
  expect_equal(res_na$count, 0)

  T_const <- matrix(5, nrow = 5, ncol = 5)
  res_const <- exdyn.sandbox:::exdyn_orientation_metrics(T_const)
  expect_true(is.na(res_const$R))
  expect_equal(res_const$count, (5 - 2) * (5 - 2))
})

test_that("analytic summaries match lm-based r2 and slope", {
  set.seed(202)
  T_P <- matrix(stats::rnorm(100), nrow = 10)
  TX <- T_P * 1.5 + stats::rnorm(100, sd = 0.5)
  TX[sample(length(TX), size = 5)] <- NA_real_
  T_P[sample(length(T_P), size = 5)] <- NA_real_
  finite <- is.finite(TX) & is.finite(T_P)
  fit <- stats::lm(TX[finite] ~ T_P[finite])
  r2_lm <- summary(fit)$r.squared
  summs <- exdyn_summary_tx_response(TX, T_P)
  expect_equal(summs[["r2_arrival"]], r2_lm, tolerance = 1e-8)

  TX_obs <- TX
  TX_sim <- TX + 1
  compat <- list(min_r2_arrival = 0, lag_range = c(-Inf, Inf), min_coverage = 0)
  score <- exdyn_score(TX_obs, T_P, TX_sim, compat)
  expect_equal(score$r2_arrival, r2_lm, tolerance = 1e-8)
  expect_equal(score$r2_arrival_obs, r2_lm, tolerance = 1e-8)

  T_P_const <- matrix(1, nrow = 5, ncol = 5)
  TX_var <- matrix(stats::rnorm(25), nrow = 5, ncol = 5)
  sum_const <- exdyn_summary_tx_response(TX_var, T_P_const)
  expect_equal(sum_const[["r2_arrival"]], 0)

  nx <- 8; ny <- 8
  T_X <- matrix(rep(seq_len(nx), ny), nrow = nx, ncol = ny)
  dir_vec <- c(1, 0)
  speed <- exdyn.sandbox:::exdyn_front_speed_estimate(T_X, dir_vec)
  idx <- which(!is.na(T_X), arr.ind = TRUE)
  proj <- idx[, 1] * dir_vec[1] + idx[, 2] * dir_vec[2]
  fit2 <- stats::lm(T_X[idx] ~ proj)
  expect_equal(speed$slope, unname(stats::coef(fit2)[2]), tolerance = 1e-10)
  expect_equal(speed$r2, summary(fit2)$r.squared, tolerance = 1e-10)
})
