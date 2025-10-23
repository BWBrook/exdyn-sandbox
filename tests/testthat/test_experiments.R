test_that("experiment grid expands to expected combinations", {
  grid <- exdyn_experiment_grid("config/experiments.yaml")
  expect_equal(nrow(grid), 54)
  expect_true(all(c("exp_id","params") %in% names(grid)))
})

test_that("summaries return finite metrics", {
  set.seed(4)
  fields <- exdyn_make_fields(
    nx = 20, ny = 20, years = 50, scenario = "none",
    habitat_beta = 0.3, ramp_start = 25, ramp_end = 40,
    predation_speed = 0, predation_seeds = list(), climate_drift = 0
  )
  pars <- list(rmax = 0.5, A_frac = 0, beta_H = 0.1, d = 0.02)
  N <- exdyn_simulate(20, 20, 50, fields, pars, K0 = 100, alpha = 0,
                      disp_mean_cells = 1, pred = list(type = "II", c = 0, h = 30))
  summs <- exdyn_summaries(N, fields, K0 = 100)
  expect_false(any(is.na(summs$convexity)))
  expect_true(summs$range_area_final > 0)
})

test_that("classifier pipeline yields confusion outputs", {
  grid <- exdyn_experiment_grid("config/experiments.yaml")
  subset_rows <- grid %>%
    dplyr::group_by(scenario, predation_type) %>%
    dplyr::slice_head(n = 3) %>%
    dplyr::ungroup()
  set.seed(42)
  runs <- lapply(seq_len(nrow(subset_rows)), function(i) exdyn_run_once(subset_rows[i, ]))
  results <- dplyr::bind_rows(runs)
  feature_sets <- exdyn_feature_sets(results)
  clf <- exdyn_fit_and_eval(results, feature_sets$driver_aware, seed = 99)
  conf <- clf$primary$confusion
  expect_s3_class(conf$confusion, "tbl_df")
  expect_equal(names(conf$confusion), c("truth","estimate","n"))
  expect_false(any(is.na(conf$confusion$n)))
  expect_false(any(is.na(conf$per_class$recall)))
  expect_gt(conf$overall$estimate, 0)
})
