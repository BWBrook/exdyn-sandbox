test_that("streaming counts match 3D counts on toy grid", {
  skip_on_cran()
  set.seed(123)
  grid <- exdyn.sandbox:::exdyn_perf_make_grid(
    nx = 6,
    ny = 6,
    cell_km = 10,
    riparian_frac = 0.7,
    seed = 123
  )
  grid_info <- grid$grid_info
  mask <- grid$mask
  years <- seq(1950, 1960)
  arrivals <- exdyn.sandbox:::exdyn_perf_arrival_table(
    grid_info = grid_info,
    years = years,
    pattern = "gradient",
    noise_sd = 0,
    span_frac = 0.8,
    seed = 124
  )
  grid_for_fields <- grid_info
  grid_for_fields$riparian_matrix <- matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  ramp_years <- 4
  pre_leak <- 0
  fields <- exdyn_fields_from_mink(
    arrivals = arrivals,
    grid_info = grid_for_fields,
    years = years,
    ramp_years = ramp_years,
    pre_leak = pre_leak,
    scale = 1,
    gamma = 1,
    delta_region = NULL
  )
  T_P <- exdyn.sandbox:::exdyn_arrival_matrix(arrivals, grid_info, years, delta_region = NULL)
  expect_equal(T_P, fields$T_P)
  TX_idx_ref <- exdyn_simulate_tx_only(
    grid_info = grid_info,
    years = years,
    T_P = fields$T_P,
    ramp_years = ramp_years,
    pars = list(rmax = 0.4, A_frac = 0.1 * 80, beta_H = 0, d = 0.02),
    K0 = 80,
    alpha = 0.1,
    disp_mean_cells = 1,
    pred = list(type = "II", c = 0.8, h = 30, scale = 1, gamma = 1),
    pre_leak = pre_leak,
    mask = mask
  )
  TX_idx_new <- exdyn_simulate_tx_only(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = list(rmax = 0.4, A_frac = 0.1 * 80, beta_H = 0, d = 0.02),
    K0 = 80,
    alpha = 0.1,
    disp_mean_cells = 1,
    pred = list(type = "II", c = 0.8, h = 30, scale = 1, gamma = 1),
    pre_leak = pre_leak,
    mask = mask
  )
  expect_equal(TX_idx_new, TX_idx_ref)
  TX_idx_crop <- exdyn_simulate_tx_only(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = list(rmax = 0.4, A_frac = 0.1 * 80, beta_H = 0, d = 0.02),
    K0 = 80,
    alpha = 0.1,
    disp_mean_cells = 1,
    pred = list(type = "II", c = 0.8, h = 30, scale = 1, gamma = 1),
    pre_leak = pre_leak,
    mask = mask,
    crop = TRUE
  )
  expect_equal(TX_idx_crop, TX_idx_ref)
  pars <- list(rmax = 0.4, A_frac = 0.1 * 80, beta_H = 0, d = 0.02)
  pred <- list(type = "II", c = 0.8, h = 30, scale = 1, gamma = 1)
  alpha <- 0.1
  disp_mean_cells <- 1
  N_true <- exdyn_simulate(
    nx = grid_info$nx,
    ny = grid_info$ny,
    years = length(years),
    fields = fields,
    pars = pars,
    K0 = 80,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred
  )
  if (any(!mask)) {
    for (tt in seq_len(dim(N_true)[3])) {
      slice <- N_true[, , tt]
      slice[!mask] <- 0
      N_true[, , tt] <- slice
    }
  }
  rate <- 0.01
  effort_strength <- 1.1
  set.seed(999)
  counts_old <- exdyn_presence_only_counts(
    N_true,
    years,
    grid_info,
    rate = rate,
    effort_strength = effort_strength,
    mask = mask
  )
  set.seed(999)
  counts_new <- exdyn.sandbox:::exdyn_simulate_counts_stream(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = pars,
    K0 = 80,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    rate = rate,
    effort_strength = effort_strength,
    pre_leak = pre_leak,
    mask = mask
  )
  set.seed(999)
  counts_crop <- exdyn.sandbox:::exdyn_simulate_counts_stream(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = pars,
    K0 = 80,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    rate = rate,
    effort_strength = effort_strength,
    pre_leak = pre_leak,
    mask = mask,
    crop = TRUE
  )
  expect_equal(counts_new$counts_mat, counts_old$counts_mat)
  expect_equal(counts_crop$counts_mat, counts_old$counts_mat)
  tx_cfg <- list(
    smooth_window = 3,
    min_years_active = 3,
    baseline_window = 5,
    drop_fraction = 0.2,
    hold_years = 2,
    normalize_by = "mammal"
  )
  tx_old <- exdyn_tx_map_counts(
    counts_mat = counts_old$counts_mat,
    years = range(years),
    cfg = tx_cfg,
    grid_info = grid_info,
    effort_mat = counts_old$effort_mat,
    mask = mask,
    cells_dt = counts_old$cells,
    return_counts = FALSE
  )
  tx_new <- exdyn_tx_map_counts(
    counts_mat = counts_new$counts_mat,
    years = range(years),
    cfg = tx_cfg,
    grid_info = grid_info,
    effort_mat = counts_new$effort_mat,
    mask = mask,
    cells_dt = counts_new$cells,
    return_counts = FALSE
  )
  expect_equal(tx_new$matrix, tx_old$matrix)
})
