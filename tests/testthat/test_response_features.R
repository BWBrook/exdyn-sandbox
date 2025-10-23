test_that("response-only edge metrics detect predation front", {
  set.seed(42)
  nx <- 20; ny <- 20; years <- 60
  seeds <- list(c(1, 10), c(20, 10))
  fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years,
    scenario = "predation_front",
    habitat_beta = 0.4, ramp_start = 999, ramp_end = 1000,
    predation_speed = 0.8, predation_seeds = seeds,
    climate_drift = 0
  )
  pars <- exdyn_archetype("B")
  pars$A_frac <- 0.05
  pars$d <- 0.05
  pars$beta_H <- 0
  N <- exdyn_simulate(
    nx = nx, ny = ny, years = years,
    fields = fields, pars = pars, K0 = 100,
    alpha = 0, disp_mean_cells = 1,
    pred = list(type = "II", c = 1.2, h = 10)
  )
  summs <- exdyn_summaries_response_only(N, K0 = 100)
  expect_true(!is.na(summs$resp_orient_R) && summs$resp_orient_R >= 0.6)
  expect_true(!is.na(summs$resp_edge_dir_R) && summs$resp_edge_dir_R >= 0.6)
  expect_false(is.na(summs$resp_speed_r2))
  expect_false(is.na(summs$resp_speed_cells_per_year))
})

test_that("response-only edge metrics stay low for habitat erosion", {
  set.seed(44)
  nx <- 20; ny <- 20; years <- 60
  fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years,
    scenario = "habitat_erosion",
    habitat_beta = 0.5, ramp_start = 20, ramp_end = 50,
    predation_speed = 0.5, predation_seeds = list(),
    climate_drift = 0
  )
  pars <- exdyn_archetype("B")
  pars$A_frac <- 0.02
  pars$d <- 0.02
  pars$beta_H <- 0.5
  N <- exdyn_simulate(
    nx = nx, ny = ny, years = years,
    fields = fields, pars = pars, K0 = 100,
    alpha = 0, disp_mean_cells = 1,
    pred = list(type = "II", c = 0, h = 25)
  )
  summs <- exdyn_summaries_response_only(N, K0 = 100)
  expect_true(is.na(summs$resp_orient_R) || summs$resp_orient_R <= 0.4)
  expect_true(is.na(summs$resp_edge_speed_mean) || summs$resp_edge_speed_mean < 0.05)
})

test_that("orientation metrics are approximately rotation invariant", {
  set.seed(46)
  nx <- 20; ny <- 20; years <- 60
  fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years,
    scenario = "predation_front",
    habitat_beta = 0.4, ramp_start = 999, ramp_end = 1000,
    predation_speed = 0.8, predation_seeds = list(c(1, 10), c(20, 10)),
    climate_drift = 0
  )
  pars <- exdyn_archetype("B")
  pars$A_frac <- 0.05
  pars$d <- 0.05
  pars$beta_H <- 0
  N <- exdyn_simulate(
    nx = nx, ny = ny, years = years,
    fields = fields, pars = pars, K0 = 100,
    alpha = 0, disp_mean_cells = 1,
    pred = list(type = "II", c = 1.2, h = 10)
  )
  T_X <- exdyn.sandbox:::exdyn_extirpation_time(N, K0 = 100, frac = 0.02)
  orient <- exdyn.sandbox:::exdyn_orientation_metrics(T_X)
  speed <- exdyn.sandbox:::exdyn_front_speed_estimate(T_X, orient$dominant)

  rotate90 <- function(mat) {
    t(apply(mat, 2, rev))
  }
  T_rot <- rotate90(T_X)
  orient_rot <- exdyn.sandbox:::exdyn_orientation_metrics(T_rot)
  speed_rot <- exdyn.sandbox:::exdyn_front_speed_estimate(T_rot, orient_rot$dominant)

  expect_lte(abs(orient$R - orient_rot$R), 0.05)
  if (!is.na(speed$speed) && !is.na(speed_rot$speed)) {
    expect_lte(abs(abs(speed$speed) - abs(speed_rot$speed)) / abs(speed$speed), 0.10)
  }
})
