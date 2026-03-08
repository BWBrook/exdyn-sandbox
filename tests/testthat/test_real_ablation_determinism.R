test_that("real ablation screen is deterministic across core counts", {
  skip_on_os("windows")

  grid <- exdyn.sandbox:::exdyn_perf_make_grid(
    nx = 4,
    ny = 4,
    cell_km = 10,
    riparian_frac = 1,
    region_n = 2,
    seed = 11
  )
  years_vec <- 2000:2004
  arrivals <- exdyn.sandbox:::exdyn_perf_arrival_table(
    grid_info = grid$grid_info,
    years = years_vec,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 1,
    seed = 19
  )
  T_P_base <- exdyn.sandbox:::exdyn_arrival_matrix(
    arrivals = arrivals,
    grid_info = grid$grid_info,
    years = years_vec,
    delta_region = NULL
  )
  TX_obs <- T_P_base + 2
  lookup_df <- grid$grid_info$lookup
  unit_lookup <- tibble::tibble(
    row_idx = lookup_df$row_idx,
    col_idx = lookup_df$col_idx,
    unit_id = as.character(lookup_df$cell_id)
  )
  unit_info <- list(
    lookup = unit_lookup,
    mask = grid$grid_info$riparian_matrix,
    adjacency = tibble::tibble(from = character(), to = character()),
    region_lookup = tibble::tibble(),
    coverage_breaks = c(2001, 2002, 2003)
  )
  theta_tbl <- tibble::tibble(
    draw = 1:2,
    alpha = c(0.1, 0.2),
    disp_mean_cells = c(0.5, 1.0),
    A_over_K = c(0.05, 0.08),
    pred_c = c(0.8, 1.0),
    pred_h = c(20, 25),
    ramp_years = c(4, 5),
    rmax = c(0.4, 0.45),
    K0 = c(80, 80),
    pred_scale = c(1, 1.1),
    gamma = c(1, 1),
    pred_scale_re_sigma = c(0, 0)
  )
  compat_cfg <- list(min_r2_arrival = 0, lag_range = c(-Inf, Inf), min_coverage = 0)

  serial <- suppressWarnings(exdyn.sandbox:::exdyn_real_ablation_screen(
    theta_tbl = theta_tbl,
    use_re = TRUE,
    grid_info = grid$grid_info,
    years_vec = years_vec,
    T_P_base = T_P_base,
    TX_obs = TX_obs,
    unit_info = unit_info,
    mink_cfg = list(pre_arrival_leak = 0),
    compat_cfg = compat_cfg,
    n_cores = 1,
    seed_base = 500
  ))
  parallel <- suppressWarnings(exdyn.sandbox:::exdyn_real_ablation_screen(
    theta_tbl = theta_tbl,
    use_re = TRUE,
    grid_info = grid$grid_info,
    years_vec = years_vec,
    T_P_base = T_P_base,
    TX_obs = TX_obs,
    unit_info = unit_info,
    mink_cfg = list(pre_arrival_leak = 0),
    compat_cfg = compat_cfg,
    n_cores = 2,
    seed_base = 500
  ))

  expect_equal(serial[order(serial$draw), ], parallel[order(parallel$draw), ])
})
