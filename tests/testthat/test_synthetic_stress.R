test_that("stress scenario grid expands configured axes", {
  cfg <- list(
    enabled = TRUE,
    arrival_sources = c("synthetic_plane", "real"),
    obs_multiplier = c(0.5, 1.5),
    pred_scale_multiplier = c(0.7, 1.0, 1.3),
    dropout_add = c(0, 0.1)
  )
  tbl <- exdyn_stress_scenario_grid(cfg)
  expect_true(is.data.frame(tbl))
  expect_equal(nrow(tbl), 2 * 2 * 3 * 2)
  expect_true(all(c(
    "scenario_id",
    "arrival_source",
    "obs_multiplier",
    "pred_scale_multiplier",
    "dropout_add"
  ) %in% names(tbl)))
})

test_that("stress sweep writes scenario and gate artefacts", {
  grid <- exdyn_perf_make_grid(
    nx = 10,
    ny = 8,
    cell_km = 10,
    riparian_frac = 0.7,
    region_n = 2,
    seed = 41
  )
  years <- 2000:2008
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 9
  )
  theta_star <- list(
    rmax = 0.4,
    A_over_K = 0.08,
    alpha = 0.15,
    disp_mean_km = 10,
    pred_scale = 0.9,
    pred_c = 1.1,
    pred_h = 20,
    gamma = 1.2,
    delta_region = list(R1 = 2, R2 = 1),
    ramp_years = 5,
    pred_type = "II",
    pre_leak = 0
  )
  noise_cfg <- list(
    obs_mode = "counts",
    po_rate = 0.02,
    effort_strength = 1,
    missing_years_prob = 0,
    random_tx_dropout = 0,
    keep_counts = FALSE,
    frac = 0.02,
    rel0 = 0.5,
    adaptive_threshold = TRUE
  )
  tx_cfg <- list(
    smooth_window = 1,
    min_years_active = 1,
    baseline_window = 2,
    drop_fraction = 0.3,
    hold_years = 1,
    normalize_by = "none"
  )
  screen_cfg <- list(
    n_draws = 2,
    seed = 1201,
    K0 = 120,
    dispersal_mode = "fft",
    alpha = c(0.05, 0.35),
    disp_mean_km = c(6, 16),
    A_over_K = c(0.03, 0.12),
    pred_c = c(0.8, 2.0),
    pred_h = c(15, 40),
    ramp_years = c(4, 8),
    pred_scale = c(0.8, 1.8),
    gamma = c(1.0, 1.8),
    rmax = c(0.3, 0.5),
    delta_region = list(R1 = c(0, 4), R2 = c(0, 4))
  )
  abc_cfg <- list(
    n_sims = 10,
    eps = 50,
    eps_tight = 25,
    refine = FALSE,
    prior = list(
      alpha = c(0.05, 0.35),
      disp_mean_km = c(6, 16),
      A_over_K = c(0.03, 0.12),
      pred_c = c(0.8, 2.0),
      pred_h = c(15, 40),
      ramp_years = c(4, 8),
      pred_scale = c(0.8, 1.8),
      gamma = c(1.0, 1.8),
      rmax = c(0.3, 0.5),
      delta_region = list(R1 = c(0, 4), R2 = c(0, 4))
    ),
    lhs = list(n = 4, keep = 2, seed = 1503, jitter_sd = 0.05, seed_prob = 0.5)
  )
  stress_cfg <- list(
    enabled = TRUE,
    mode = "realistic",
    reps = 1,
    seed = 777,
    n_cores = 1,
    arrival_sources = c("synthetic_plane"),
    obs_multiplier = c(1.0, 1.5),
    pred_scale_multiplier = c(0.8, 1.2),
    dropout_add = c(0),
    screen = list(n_draws = 1, dispersal_mode = "fft", crop = FALSE),
    abc = list(n_sims = 4, eps = 75, eps_tight = 40, refine = FALSE, lhs = list(n = 2, keep = 1))
  )
  out <- exdyn_synthetic_stress_sweep(
    cfg = stress_cfg,
    arrivals_real = arrivals,
    grid_info = grid$grid_info,
    years_vec = years,
    theta_star = theta_star,
    noise_cfg = noise_cfg,
    tx_cfg = tx_cfg,
    screen_cfg = screen_cfg,
    compat_cfg = list(min_r2_arrival = 0, lag_range = c(0, 40), min_coverage = 0.05),
    abc_cfg = abc_cfg,
    coverage_breaks = exdyn_coverage_breaks(years),
    mask = exdyn_land_mask_from_lookup(grid$grid_info),
    output_root = tempdir()
  )
  expect_true(nrow(out$scenarios) > 0)
  expect_true(nrow(out$gate_table) > 0)
  expect_true(nrow(out$scenario_pass) > 0)
  expect_true(any(grepl("failure_regimes_heatmap", out$outputs)))
  expect_true(all(file.exists(out$outputs)))
})
