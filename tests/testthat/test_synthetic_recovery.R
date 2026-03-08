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
  benchmark_cfg <- list(
    stance = "weak_id",
    core_params = c("alpha", "disp_mean_km"),
    gate_abs_rel_bias = 0.2,
    gate_coverage80 = 0.6,
    weak_id_parameters = c("alpha")
  )
  tables <- exdyn_synthetic_recovery_tables(list(mode_run), screen_cfg, abc_cfg, benchmark_cfg = benchmark_cfg)
  expect_true(all(c("mode", "replicate", "seed", "n_accept") %in% names(tables$replicate_metrics)))
  expect_true(all(c("mode", "param", "truth", "coverage_80", "shrinkage_ratio",
                    "abs_rel_bias_median", "identifiability_status", "gate_pass") %in%
                    names(tables$parameter_recovery)))
  expect_true(all(c("mode", "overall_benchmark_pass", "n_core_params_expected") %in%
                    names(tables$benchmark_summary)))
})

test_that("identifiability status respects weak-id declaration", {
  status_recoverable <- exdyn_identifiability_status(
    abs_rel_bias = 0.1,
    coverage_80 = 0.8,
    param = "disp_mean_km",
    benchmark_cfg = list(
      stance = "weak_id",
      gate_abs_rel_bias = 0.2,
      gate_coverage80 = 0.6,
      weak_id_parameters = "alpha"
    )
  )
  status_weak <- exdyn_identifiability_status(
    abs_rel_bias = 0.4,
    coverage_80 = 0.7,
    param = "alpha",
    benchmark_cfg = list(
      stance = "weak_id",
      gate_abs_rel_bias = 0.2,
      gate_coverage80 = 0.6,
      weak_id_parameters = "alpha"
    )
  )
  status_partial <- exdyn_identifiability_status(
    abs_rel_bias = 0.3,
    coverage_80 = 0.6,
    param = "disp_mean_km",
    benchmark_cfg = list(
      stance = "weak_id",
      gate_abs_rel_bias = 0.2,
      gate_coverage80 = 0.6,
      weak_id_parameters = "alpha"
    )
  )
  expect_identical(status_recoverable, "recoverable")
  expect_identical(status_weak, "weakly_identifiable")
  expect_identical(status_partial, "not_recoverable")
})

test_that("benchmark summary depends only on configured core params", {
  param_tbl <- tibble::tibble(
    mode = c("ideal", "ideal", "ideal"),
    param = c("alpha", "disp_mean_km", "pred_c"),
    core_param = c(TRUE, TRUE, FALSE),
    identifiability_status = c("weakly_identifiable", "recoverable", "not_recoverable"),
    gate_pass = c(FALSE, TRUE, FALSE)
  )
  summ <- exdyn_benchmark_summary(
    param_tbl,
    benchmark_cfg = list(
      stance = "weak_id",
      core_params = c("alpha", "disp_mean_km"),
      weak_id_parameters = "alpha"
    )
  )
  expect_true(summ$overall_benchmark_pass[[1]])
  expect_equal(summ$n_core_not_recoverable[[1]], 0)
})

test_that("replicate metrics respect coverage-aware best_index", {
  mode_run <- list(
    mode = "realistic",
    replicate = 1,
    seed = 99,
    best_index = 2,
    screen_results = tibble::tibble(
      loss = c(0.1, 0.2),
      r2_arrival = c(0.9, 0.4),
      lag_mean = c(5, 10),
      coverage = c(1.0, 0.35),
      compatible = c(TRUE, TRUE)
    ),
    abc = list(
      samples = tibble::tibble(alpha = c(0.1)),
      summaries = tibble::tibble(lag_mean = 10, coverage = 0.35, r2_arrival = 0.4),
      distances = c(1),
      eps = 0.5
    ),
    summary_counts = list(n_mask = 10, n_TP_finite = 10, n_TX_true = 4, n_TX_obs = 4, n_pairs = 4),
    abc_summary = tibble::tibble(param = "alpha", median = 0.1, truth = 0.1, p250 = 0.1, p750 = 0.1,
                                 p100 = 0.1, p900 = 0.1, p025 = 0.1, p975 = 0.1, mean = 0.1, sd = 0.01)
  )
  tables <- exdyn_synthetic_recovery_tables(
    list(mode_run),
    screen_cfg = list(alpha = c(0, 1), disp_mean_km = c(5, 15), A_over_K = c(0.01, 0.2),
                      pred_c = c(0.5, 3), pred_h = c(10, 40), ramp_years = c(3, 10),
                      pred_scale = c(0.5, 2), gamma = c(1, 2), rmax = c(0.2, 0.6)),
    abc_cfg = list(prior = list(alpha = c(0, 1), disp_mean_km = c(5, 15), A_over_K = c(0.01, 0.2),
                                pred_c = c(0.5, 3), pred_h = c(10, 40), ramp_years = c(3, 10),
                                pred_scale = c(0.5, 2), gamma = c(1, 2), rmax = c(0.2, 0.6)))
  )
  expect_equal(tables$replicate_metrics$screen_best_loss[[1]], 0.2)
  expect_equal(tables$replicate_metrics$screen_best_coverage[[1]], 0.35)
})
