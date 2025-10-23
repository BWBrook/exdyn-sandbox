test_that("front diagnostics capture arrival-extirpation coupling", {
  nx <- 20; ny <- 20; years <- 80; K0 <- 120
  seeds <- list(c(1, 10), c(20, 10))
  fields_front <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "predation_front",
    habitat_beta = 0.1, ramp_start = 70, ramp_end = 75,
    predation_speed = 0.9, predation_seeds = seeds,
    climate_drift = 0
  )
  pars <- list(rmax = 0.3, A_frac = 0, beta_H = 0, d = 0.05)
  pred <- list(type = "II", c = 1.5, h = 8)
  N_front <- exdyn_simulate(nx, ny, years, fields_front, pars,
                             K0 = K0, alpha = 0, disp_mean_cells = 1,
                             pred = pred)
  summs_front <- exdyn_summaries(N_front, fields_front, K0 = K0)
  expect_gt(summs_front$r2_arrival, 0.7)
  expect_gt(summs_front$r2_dist, 0.6)
  expect_gt(summs_front$lag_arrival_mean, 0)
  expect_gt(summs_front$arrival_coverage, 0.3)
})

test_that("habitat erosion lacks front signature", {
  nx <- 20; ny <- 20; years <- 80; K0 <- 120
  seeds <- list(c(1, 10), c(20, 10))
  fields_hab <- exdyn_make_fields(
    nx = nx, ny = ny, years = years, scenario = "habitat_erosion",
    habitat_beta = 0.55, ramp_start = 35, ramp_end = 65,
    predation_speed = 0.9, predation_seeds = seeds,
    climate_drift = 0
  )
  pars_hab <- list(rmax = 0.45, A_frac = 0, beta_H = 0.45, d = 0.03)
  pred_null <- list(type = "II", c = 0, h = 30)
  N_hab <- exdyn_simulate(nx, ny, years, fields_hab, pars_hab,
                          K0 = K0, alpha = 0, disp_mean_cells = 1,
                          pred = pred_null)
  summs_hab <- exdyn_summaries(N_hab, fields_hab, K0 = K0)
  expect_true(is.na(summs_hab$r2_arrival) || summs_hab$r2_arrival < 0.2)
  expect_true(is.na(summs_hab$r2_dist) || summs_hab$r2_dist < 0.2)
  expect_true(is.na(summs_hab$arrival_coverage) || summs_hab$arrival_coverage < 0.05)
})

test_that("response-only feature set avoids leakage", {
  grid <- exdyn_experiment_grid("config/experiments.yaml")
  subset_rows <- grid |> dplyr::group_by(scenario) |> dplyr::slice_head(n = 2) |> dplyr::ungroup()
  runs <- lapply(seq_len(nrow(subset_rows)), function(i) exdyn_run_once(subset_rows[i, ]))
  results <- dplyr::bind_rows(runs)
  feature_sets <- exdyn_feature_sets(results)
  expect_gt(length(feature_sets$response_only), 0)
  expect_true(all(c(
    "resp_edge_speed_mean", "resp_edge_dir_R", "resp_orient_R", "resp_speed_r2"
  ) %in% feature_sets$response_only))
  expect_false(any(grepl("(P|H|arrival|xcorr_)", feature_sets$response_only)))
  expect_true(any(grepl("(P|H|arrival|xcorr_)", feature_sets$driver_aware)))
})
