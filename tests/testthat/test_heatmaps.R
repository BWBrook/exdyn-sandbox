test_that("heatmap binning yields populated cells and honors aliases", {
  set.seed(123)
  levels_all <- c("predation_front", "habitat_erosion", "both")
  oof <- tibble::tibble(
    exp_id = sprintf("exp_%03d", seq_len(240)),
    alpha = runif(240, 0, 0.6),
    dispersal_mean_km = runif(240, 5, 40),
    pred_speed = runif(240, 0.1, 1.5),
    presence_rate = runif(240, 0.0002, 0.004),
    allee_A_over_K = runif(240, 0, 0.3),
    species = sample(c("A", "B", "C"), 240, replace = TRUE),
    scenario = factor(sample(levels_all, 240, replace = TRUE), levels = levels_all),
    truth = factor(sample(levels_all, 240, replace = TRUE), levels = levels_all),
    estimate = factor(sample(levels_all, 240, replace = TRUE), levels = levels_all)
  )

  cells <- suppressWarnings(exdyn_bin_f1(oof, "alpha", "pred_speed", bins = 4, min_n = 3))
  expect_gt(nrow(cells), 0)
  expect_true(any(!is.na(cells$macro_f1)))
  expect_true(all(!is.na(cells$x_mid)))

  alias_cells <- suppressWarnings(exdyn_bin_f1(oof, "mean_km", "presence_only_rate", bins = 4, min_n = 3))
  expect_gt(nrow(alias_cells), 0)

  plt <- exdyn_plot_heatmap(cells, "alpha", "pred speed")
  expect_s3_class(plt, "ggplot")
})
