test_that("replicate grid respects recovery config", {
  grid <- exdyn_synthetic_rep_grid(list(n_reps = 3, seed = 42))
  expect_equal(nrow(grid), 3)
  expect_true(all(c("replicate", "seed") %in% names(grid)))
})

test_that("recovery tables expose required columns", {
  theta_star <- list(alpha = 0.15, disp_mean_km = 10, A_over_K = 0.05, pred_c = 1,
                     pred_h = 20, ramp_years = 6, pred_scale = 1, gamma = 1, rmax = 0.4)
  samples <- tibble::tibble(
    alpha = c(0.1, 0.2),
    disp_mean_km = c(10, 11),
    A_over_K = c(0.05, 0.06),
    pred_c = c(1, 1.2),
    pred_h = c(20, 25),
    ramp_years = c(5, 6),
    pred_scale = c(1, 1.1),
    gamma = c(1, 1.2),
    rmax = c(0.3, 0.35)
  )
  mode_run <- list(
    mode = "ideal",
    replicate = 1,
    seed = 11,
    screen_results = tibble::tibble(loss = 1, r2_arrival = 0.5, lag_mean = 3, coverage = 0.4),
    abc = list(
      samples = samples,
      summaries = tibble::tibble(lag_mean = c(3, 4), coverage = c(0.4, 0.5), r2_arrival = c(0.5, 0.6)),
      distances = c(0.2, 0.3),
      eps = 0.5
    ),
    abc_summary = exdyn_abc_summary_table(samples, theta_star)
  )
  screen_cfg <- list(
    alpha = c(0, 1),
    disp_mean_km = c(5, 15),
    A_over_K = c(0.01, 0.2),
    pred_c = c(0.5, 3),
    pred_h = c(10, 40),
    ramp_years = c(3, 10),
    pred_scale = c(0.5, 2),
    gamma = c(1, 2),
    rmax = c(0.2, 0.6)
  )
  abc_cfg <- list(prior = screen_cfg)
  tables <- exdyn_synthetic_recovery_tables(list(mode_run), screen_cfg, abc_cfg)
  expect_true(all(c("mode", "replicate", "seed", "n_accept") %in% names(tables$replicate_metrics)))
  expect_true(all(c("mode", "param", "truth", "coverage_80", "shrinkage_ratio") %in% names(tables$parameter_recovery)))
})
