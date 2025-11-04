skip_if_not_installed("zoo")

grid_lookup <- expand.grid(row = 1:3, col = 1:3)
grid_lookup$cell_id <- seq_len(nrow(grid_lookup))
grid_lookup$row_idx <- grid_lookup$row
grid_lookup$col_idx <- grid_lookup$col
grid_info_small <- list(
  lookup = tibble::as_tibble(grid_lookup),
  row_levels = 1:3,
  col_levels = 1:3,
  nx = 3L,
  ny = 3L
)

test_that("streaming simulator extirpates under high predation", {
  years <- 2000:2030
  T_P <- matrix(2000L, nrow = grid_info_small$nx, ncol = grid_info_small$ny)
  pars <- list(rmax = 0.4, A_frac = 0, beta_H = 0, d = 0.03)
  TX <- exdyn_simulate_tx_only(
    grid_info = grid_info_small,
    years = years,
    T_P = T_P,
    ramp_years = 1,
    pars = pars,
    K0 = 100,
    alpha = 0,
    disp_mean_cells = 0,
    pred = list(type = "II", c = 3, h = 10, scale = 1, gamma = 1),
    pre_leak = 0,
    log_mem = FALSE
  )
  expect_true(all(is.finite(TX)))
  expect_lte(max(TX, na.rm = TRUE), 15)
})
