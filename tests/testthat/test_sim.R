test_that("logistic equilibrium without threats or dispersal", {
  set.seed(1)
  cfg <- list(nx=10, ny=10, years=60, K0=100, alpha=0, disp_mean_cells=1,
              pars=list(rmax=0.5, A_frac=0, beta_H=0, d=0.02),
              pred=list(type="II", c=0, h=30))
  fields <- exdyn_make_fields(
    nx = cfg$nx, ny = cfg$ny, years = cfg$years, scenario = "none",
    habitat_beta = 0, ramp_start = 1, ramp_end = 1,
    predation_speed = 0, predation_seeds = list(), climate_drift = 0
  )
  fields$S[,,] <- 1
  N <- exdyn_simulate(cfg$nx,cfg$ny,cfg$years,fields, cfg$pars, K0=cfg$K0,
                      alpha=cfg$alpha, disp_mean_cells=cfg$disp_mean_cells,
                      pred=cfg$pred)
  kcell <- cfg$K0
  expect_true(mean(N[,,cfg$years]) > 0.8*kcell)
})

test_that("predation front depresses abundance after arrival", {
  set.seed(2)
  cfg <- exdyn_config("config/default.yaml")
  cfg$scenario <- "predation_front"
  cfg$pars$rmax <- 0.5; cfg$pred$c <- 0.8
  fields <- exdyn_make_fields(
    nx = cfg$nx, ny = cfg$ny, years = 80, scenario = cfg$scenario,
    habitat_beta = cfg$habitat_beta,
    ramp_start = 40, ramp_end = 60,
    predation_speed = cfg$pred$speed,
    predation_seeds = cfg$pred$seeds,
    climate_drift = cfg$climate$drift_per_century
  )
  N <- exdyn_simulate(cfg$nx,cfg$ny,80,fields,cfg$pars, K0=cfg$K0,
                      alpha=0, disp_mean_cells=1, pred=cfg$pred)
  cell <- c(5,5)
  before <- N[cell[1],cell[2],20]
  after  <- N[cell[1],cell[2],60]
  expect_true(after < before)
})

test_that("presence-only sampling returns non-empty for non-zero N", {
  set.seed(3)
  fields <- exdyn_make_fields(
    nx = 20, ny = 20, years = 20, scenario = "none",
    habitat_beta = 0, ramp_start = 1, ramp_end = 1,
    predation_speed = 0, predation_seeds = list(), climate_drift = 0
  )
  pars <- list(rmax=0.6, A_frac=0, beta_H=0, d=0.02)
  N <- exdyn_simulate(20,20,20,fields,pars, K0=80, alpha=0, disp_mean_cells=1,
                      pred=list(type="II",c=0,h=30))
  pts <- exdyn_presence_only(N, rate=0.005)
  expect_true(nrow(pts) > 0)
})
