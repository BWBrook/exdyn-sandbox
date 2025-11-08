test_that("synthetic twin generation yields plausible outputs", {
  skip_on_cran()
  library(sf)
  poly <- sf::st_as_sfc(sf::st_bbox(c(xmin = 0, xmax = 30000, ymin = 0, ymax = 30000)), crs = 27700)
  grid_sf <- sf::st_make_grid(poly, n = c(3, 3), what = "polygons")
  grid_sf <- sf::st_sf(cell_id = seq_along(grid_sf), geometry = grid_sf)
  grid_sf$row <- rep(3:1, each = 3)
  grid_sf$col <- rep(1:3, times = 3)
  grid_info <- exdyn_grid_lookup(grid_sf)
  arrivals <- tibble::tibble(
    cell_id = grid_sf$cell_id,
    arrival_year = 1960 + seq_along(cell_id)
  )
  theta <- list(
    rmax = 0.3,
    A_over_K = 0.05,
    alpha = 0,
    disp_mean_km = 1,
    pred_scale = 10,
    pred_c = 10,
    pred_h = 5,
    gamma = 1.5,
    delta_region = list(A = 2, B = 1, C = 0),
    ramp_years = 4,
    truth_frac = 0.1,
    truth_rel0 = 0.5
  )
  noise <- list(
    po_rate = 0.01,
    effort_strength = 1.2,
    missing_years_prob = 0,
    random_tx_dropout = 0.1
  )
  tx_cfg <- list(
    smooth_window = 3,
    min_years_active = 3,
    baseline_window = 5,
    drop_fraction = 0.2,
    hold_years = 2,
    normalize_by = "mammal"
  )
  mask <- matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  syn <- exdyn_make_synthetic(
    theta_star = theta,
    noise_cfg = noise,
    arrivals = arrivals,
    grid_info = grid_info,
    years = c(1950, 1980),
    tx_cfg = tx_cfg,
    K0 = 80,
    mask = mask
  )
  expect_true(any(is.finite(syn$TX_true)))
  expect_true(all(dim(syn$TX_obs) == c(grid_info$nx, grid_info$ny)))
  expect_s3_class(syn$po_points, "tbl_df")
  expect_gt(nrow(syn$po_points), 0)
  expect_type(syn$N_true, "double")
})
