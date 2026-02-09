test_that("mask philosophy comparison outputs table and plots", {
  grid <- exdyn_perf_make_grid(
    nx = 12,
    ny = 10,
    cell_km = 10,
    riparian_frac = 0.6,
    region_n = 2,
    seed = 7
  )
  years <- 2000:2006
  arrivals <- exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 9
  )
  cfg <- list(
    enabled = TRUE,
    arrival_source = "synthetic_plane",
    scenarios = c("hard", "soft"),
    reps = 1,
    seed = 11,
    dispersal_mode = "fft",
    soft = list(method = "riparian", range = c(0.5, 1.5), transform = "none")
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
  tx_cfg <- list(
    smooth_window = 1,
    min_years_active = 1,
    baseline_window = 2,
    drop_fraction = 0.3,
    hold_years = 1,
    normalize_by = "none"
  )
  out <- exdyn_mask_philosophy_compare(
    arrivals_real = arrivals,
    grid_info = grid$grid_info,
    years_vec = years,
    mask_hard = grid$grid_info$riparian_matrix,
    theta_star = theta_star,
    noise_cfg = noise_cfg,
    tx_cfg = tx_cfg,
    coverage_breaks = exdyn_coverage_breaks(years),
    cfg = cfg,
    output_root = tempdir()
  )
  expect_true(is.data.frame(out$table))
  expect_true(any(out$table$mask_type == "hard"))
  expect_true(any(out$table$mask_type == "soft"))
  soft_mean <- out$table$scale_mean[out$table$mask_type == "soft"][1]
  expect_true(is.finite(soft_mean))
})
