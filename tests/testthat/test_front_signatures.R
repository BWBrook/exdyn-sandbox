test_that("scenario fields isolate drivers", {
  nx <- 20; ny <- 20; years <- 60
  seeds <- list(c(1,10), c(20,10))
  pred_fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "predation_front",
    habitat_beta = 0.5, ramp_start = 40, ramp_end = 55,
    predation_speed = 0.6, predation_seeds = seeds,
    climate_drift = 0
  )
  expect_equal(sum(pred_fields$H), 0)
  expect_gt(sum(pred_fields$P), 0)
  expect_false(is.null(pred_fields$T_P))

  hab_fields <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "habitat_erosion",
    habitat_beta = 0.5, ramp_start = 40, ramp_end = 55,
    predation_speed = 0.6, predation_seeds = seeds,
    climate_drift = 0
  )
  expect_equal(sum(hab_fields$P), 0)
  expect_gt(sum(hab_fields$H), 0)
  expect_null(hab_fields$T_P)
})

test_that("front signatures highlight arrival-distance coupling", {
  nx <- 20; ny <- 20; years <- 90; K0 <- 100
  seeds <- list(c(1,10), c(20,10))
  pars <- list(rmax = 0.35, A_frac = 0, beta_H = 0, d = 0.05)
  pred <- list(type = "II", c = 1.1, h = 15)

  fields_front <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "predation_front",
    habitat_beta = 0.4, ramp_start = 50, ramp_end = 70,
    predation_speed = 0.7, predation_seeds = seeds,
    climate_drift = 0
  )
  N_front <- exdyn_simulate(nx, ny, years, fields_front, pars, K0 = K0,
                            alpha = 0, disp_mean_cells = 1,
                            pred = pred)
  summs_front <- exdyn_summaries(N_front, fields_front, K0 = K0)
  expect_gt(summs_front$r2_arrival, 0.3)
  expect_gt(summs_front$r2_dist, 0.3)

  fields_hab <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "habitat_erosion",
    habitat_beta = 0.5, ramp_start = 50, ramp_end = 80,
    predation_speed = 0.7, predation_seeds = seeds,
    climate_drift = 0
  )
  pars_hab <- modifyList(pars, list(beta_H = 0.35))
  pred_null <- list(type = "II", c = 0, h = 25)
  N_hab <- exdyn_simulate(nx, ny, years, fields_hab, pars_hab, K0 = K0,
                          alpha = 0, disp_mean_cells = 1,
                          pred = pred_null)
  summs_hab <- exdyn_summaries(N_hab, fields_hab, K0 = K0)
  expect_true(is.na(summs_hab$r2_arrival) || summs_hab$r2_arrival < 0.2)
  expect_true(is.na(summs_hab$r2_dist) || summs_hab$r2_dist < 0.2)
})
