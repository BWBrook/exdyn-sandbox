test_that("abc cfg by mode applies mode-specific eps settings", {
  cfg <- list(
    eps = 1,
    eps_tight = 0.5,
    eps_by_mode = list(ideal = 5),
    eps_tight_by_mode = list(ideal = 2)
  )
  ideal_cfg <- exdyn_abc_cfg_by_mode(cfg, "ideal")
  expect_equal(ideal_cfg$eps, 5)
  expect_equal(ideal_cfg$eps_tight, 2)

  real_cfg <- exdyn_abc_cfg_by_mode(cfg, "realistic")
  expect_equal(real_cfg$eps, 1)
  expect_equal(real_cfg$eps_tight, 0.5)
})
