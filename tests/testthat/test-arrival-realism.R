test_that("arrival realism comparison returns summary table", {
  grid <- exdyn_perf_make_grid(
    nx = 10,
    ny = 8,
    cell_km = 10,
    riparian_frac = 0.8,
    region_n = 2,
    seed = 42
  )
  years <- 2000:2005
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 24
  )
  theta_star <- list(
    rmax = 0.4,
    A_over_K = 0.1,
    alpha = 0.2,
    disp_mean_km = 8,
    pred_scale = 0.9,
    pred_c = 0.9,
    pred_h = 20,
    gamma = 1,
    ramp_years = 6,
    pred_type = "II"
  )
  noise_cfg <- list(obs_mode = "counts", po_rate = 0.01, effort_strength = 1)
  screen_cfg <- list(
    n_draws = 2,
    seed = 99,
    K0 = 60,
    alpha = c(0.1, 0.3),
    disp_mean_km = c(5, 10),
    A_over_K = c(0.05, 0.15),
    pred_c = c(0.6, 1.2),
    pred_h = c(15, 30),
    ramp_years = c(4, 8),
    pred_scale = c(0.7, 1.3),
    gamma = c(0.8, 1.2),
    rmax = c(0.3, 0.5)
  )
  compat_cfg <- list(min_r2_arrival = 0, lag_range = c(0, 40), min_coverage = 0)
  abc_cfg <- list(
    n_sims = 4,
    eps = 10,
    eps_tight = 5,
    prior = list(
      alpha = screen_cfg$alpha,
      disp_mean_km = screen_cfg$disp_mean_km,
      A_over_K = screen_cfg$A_over_K,
      pred_c = screen_cfg$pred_c,
      pred_h = screen_cfg$pred_h,
      ramp_years = screen_cfg$ramp_years,
      pred_scale = screen_cfg$pred_scale,
      gamma = screen_cfg$gamma,
      rmax = screen_cfg$rmax
    ),
    lhs = list(n = 0, keep = 0),
    scale = list()
  )
  cfg <- list(
    enabled = TRUE,
    sources = c("real", "synthetic_plane"),
    modes = c("ideal"),
    reps = 1,
    screen = list(n_draws = 2),
    abc = list(n_sims = 4, lhs = list(n = 0, keep = 0))
  )
  res <- exdyn_arrival_realism_comparison(
    arrivals_real = arrivals,
    grid_info = grid$grid_info,
    years_vec = years,
    mask = grid$grid_info$riparian_matrix,
    theta_star = theta_star,
    noise_cfg = noise_cfg,
    tx_cfg = list(
      smooth_window = 1,
      min_years_active = 1,
      baseline_window = 2,
      drop_fraction = 0.3,
      hold_years = 1,
      normalize_by = "none"
    ),
    screen_cfg = screen_cfg,
    compat_cfg = compat_cfg,
    abc_cfg = abc_cfg,
    coverage_breaks = exdyn_coverage_breaks(years),
    recovery_cfg = list(seed = 1234),
    cfg = cfg
  )
  expect_true(is.data.frame(res))
  expect_true(nrow(res) >= 1)
  expect_true(all(c(
    "arrival_source",
    "mode",
    "n_reps",
    "frac_finite_TP_in_mask",
    "mean_n_TX_true",
    "mean_n_TX_obs",
    "summary_finite_rate_mean",
    "param_coverage80_mean"
  ) %in% names(res)))
})
