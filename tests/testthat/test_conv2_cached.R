set.seed(123)

manual_simulate_array <- function(nx, ny, years, fields, pars, K0, alpha, disp_mean_cells, pred) {
  N <- array(0, c(nx, ny, years))
  N[, , 1] <- pmax(1, round(K0 * fields$S[, , 1] * 0.1))
  ker <- exdyn_kernel(mean_cells = disp_mean_cells, radius = 5L)
  for (t in seq_len(years - 1)) {
    local <- exdyn_update_local(
      N = N[, , t], S = fields$S[, , t], H = fields$H[, , t], P = fields$P[, , t],
      pars = pars, K0 = K0, pred_type = pred$type, pred_c = pred$c, pred_h = pred$h
    )
    moved <- exdyn_conv2(local, ker)
    N[, , t + 1] <- if (alpha > 0) (1 - alpha) * local + alpha * moved else local
    N[, , t + 1] <- pmax(N[, , t + 1], 0)
  }
  N
}

manual_tx_only <- function(grid_info, years, T_P, ramp_years, pars, K0, alpha, disp_mean_cells, pred,
                           frac = 0.02, rel0 = 0.5, pre_leak = 0) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  Tn <- length(years)
  ramp_years <- max(1, ramp_years)
  N <- matrix(pmax(1, round(K0 * 0.1)), nrow = nx, ncol = ny)
  tau <- pmin(frac * K0, rel0 * N)
  TX <- matrix(NA_integer_, nrow = nx, ncol = ny)
  ker <- exdyn_kernel(mean_cells = disp_mean_cells, radius = 5L)
  k <- 6 / ramp_years
  for (tt in seq_len(Tn - 1)) {
    dt <- years[tt] - T_P
    P_t <- ifelse(
      is.na(T_P),
      pre_leak,
      {
        val <- 0.2 + 0.8 / (1 + exp(-k * (dt - ramp_years / 2)))
        val[dt < 0] <- pre_leak
        pmax(pre_leak, pmin(1, val))
      }
    )
    local <- exdyn_update_local(
      N = N,
      S = matrix(1, nx, ny),
      H = matrix(0, nx, ny),
      P = P_t,
      pars = pars,
      K0 = K0,
      pred_type = pred$type,
      pred_c = pred$c,
      pred_h = pred$h
    )
    moved <- exdyn_conv2(local, ker)
    N_next <- if (alpha > 0) (1 - alpha) * local + alpha * moved else local
    crossed <- is.na(TX) & (N > tau) & (N_next <= tau)
    if (any(crossed)) {
      TX[crossed] <- tt + 1L
    }
    N <- pmax(N_next, 0)
  }
  TX
}

test_that("cached conv2 plan matches wrapper", {
  A <- matrix(rnorm(36), 6)
  K <- exdyn_kernel(mean_cells = 1.2, radius = 2L)
  plan <- exdyn_conv2_plan(nrow(A), ncol(A), K)
  expect_equal(
    exdyn_conv2(A, K),
    exdyn_conv2_apply(A, plan),
    tolerance = 1e-8
  )
})

test_that("simulate matches legacy convolution", {
  nx <- 6; ny <- 6; years <- 10
  fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "predation_front",
    habitat_beta = 0.2, ramp_start = 30, ramp_end = 40,
    predation_speed = 0.5, predation_seeds = list(c(1, 3)), climate_drift = 0
  )
  pars <- list(rmax = 0.4, A_frac = 0, beta_H = 0.1, d = 0.02)
  pred <- list(type = "II", c = 0.6, h = 30)
  set.seed(42)
  sim_new <- exdyn_simulate(nx, ny, years, fields, pars, K0 = 80, alpha = 0.1,
                            disp_mean_cells = 1.5, pred = pred)
  set.seed(42)
  sim_old <- manual_simulate_array(nx, ny, years, fields, pars, K0 = 80, alpha = 0.1,
                                   disp_mean_cells = 1.5, pred = pred)
  expect_equal(sim_new, sim_old, tolerance = 1e-8)
})

test_that("tx-only simulate matches legacy convolution", {
  nx <- 8; ny <- 8; years <- seq_len(15)
  T_P <- matrix(sample(years, nx * ny, replace = TRUE), nrow = nx)
  pars <- list(rmax = 0.5, A_frac = 0.05 * 120, beta_H = 0, d = 0.02)
  pred <- list(type = "II", c = 0.7, h = 25)
  set.seed(99)
  tx_new <- exdyn_simulate_tx_only(
    grid_info = list(nx = nx, ny = ny),
    years = years,
    T_P = T_P,
    ramp_years = 6,
    pars = pars,
    K0 = 120,
    alpha = 0.2,
    disp_mean_cells = 1.2,
    pred = pred,
    log_mem = FALSE
  )
  set.seed(99)
  tx_old <- manual_tx_only(
    grid_info = list(nx = nx, ny = ny),
    years = years,
    T_P = T_P,
    ramp_years = 6,
    pars = pars,
    K0 = 120,
    alpha = 0.2,
    disp_mean_cells = 1.2,
    pred = pred
  )
  expect_equal(tx_new, tx_old, tolerance = 1e-8)
})
