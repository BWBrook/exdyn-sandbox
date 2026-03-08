# Real-data ablation helpers (internal)

exdyn_real_simulate_tx <- function(theta,
                                   grid_info,
                                   years_vec,
                                   T_P_base,
                                   unit_lookup,
                                   unit_mask,
                                   mink_cfg,
                                   sigma_override = NULL,
                                   seed = NULL,
                                   log_mem = FALSE,
                                   log_tag = NULL) {
  delta_cols <- grep("^delta_", names(theta), value = TRUE)
  delta_lookup_region <- NULL
  if (length(delta_cols)) {
    delta_lookup_region <- purrr::map_dbl(delta_cols, ~ theta[[.x]][[1]])
    names(delta_lookup_region) <- gsub("^delta_", "", delta_cols)
  }
  T_P_adj <- exdyn_adjust_arrival_matrix(T_P_base, grid_info, delta_lookup_region, years_vec)
  if (any(!unit_mask)) {
    T_P_adj[!unit_mask] <- NA_real_
  }
  sigma_draw <- theta$pred_scale_re_sigma[[1]] %||% 0
  sigma_use <- sigma_override %||% sigma_draw
  unit_ids <- unique(unit_lookup$unit_id)
  unit_effects <- exdyn_sample_pred_scale_re(
    unit_ids,
    sigma = sigma_use,
    seed = seed
  )
  scale_matrix <- exdyn_scale_matrix_from_units(grid_info, unit_lookup, unit_effects)
  pars <- list(
    rmax = theta$rmax[[1]],
    A_frac = theta$A_over_K[[1]] * theta$K0[[1]],
    beta_H = 0,
    d = 0.03
  )
  TX_idx <- exdyn_simulate_tx_only(
    grid_info = grid_info,
    years = years_vec,
    T_P = T_P_adj,
    ramp_years = theta$ramp_years[[1]],
    pars = pars,
    K0 = theta$K0[[1]],
    alpha = theta$alpha[[1]],
    disp_mean_cells = theta$disp_mean_cells[[1]],
    pred = list(
      type = "II",
      c = theta$pred_c[[1]],
      h = theta$pred_h[[1]],
      scale = theta$pred_scale[[1]] %||% 1,
      gamma = theta$gamma[[1]] %||% 1,
      scale_matrix = scale_matrix
    ),
    pre_leak = mink_cfg$pre_arrival_leak %||% 0,
    log_mem = isTRUE(log_mem),
    log_tag = log_tag %||% "",
    mask = unit_mask
  )
  TX_idx[!unit_mask] <- NA_integer_
  TX_sim <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  idx_valid <- is.finite(TX_idx)
  if (any(idx_valid)) {
    TX_sim[idx_valid] <- years_vec[TX_idx[idx_valid]]
  }
  TX_sim[!unit_mask] <- NA_real_
  list(
    TX_sim = TX_sim,
    T_P_adj = T_P_adj,
    delta_lookup_region = delta_lookup_region,
    sigma_draw = sigma_draw,
    sigma_use = sigma_use
  )
}

exdyn_real_ablation_screen <- function(theta_tbl,
                                       use_re = TRUE,
                                       grid_info,
                                       years_vec,
                                       T_P_base,
                                       TX_obs,
                                       unit_info,
                                       mink_cfg,
                                       compat_cfg,
                                       delta_penalty_cfg = list(lambda_mag = 0, lambda_tv = 0),
                                       unit_timing_stat = "median",
                                       n_cores = 1L,
                                       seed_base = 3201L,
                                       log_mem = FALSE) {
  theta_tbl <- tibble::as_tibble(theta_tbl)
  if (!nrow(theta_tbl)) {
    return(tibble::tibble())
  }
  unit_lookup <- unit_info$lookup
  unit_mask <- unit_info$mask %||% matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  adjacency <- unit_info$adjacency
  region_lookup <- unit_info$region_lookup %||% tibble::tibble()
  run_draw <- function(i) {
    theta <- theta_tbl[i, , drop = FALSE]
    draw <- theta$draw[[1]] %||% i
    sim <- exdyn_real_simulate_tx(
      theta = theta,
      grid_info = grid_info,
      years_vec = years_vec,
      T_P_base = T_P_base,
      unit_lookup = unit_lookup,
      unit_mask = unit_mask,
      mink_cfg = mink_cfg,
      sigma_override = if (isTRUE(use_re)) NULL else 0,
      seed = seed_base + as.integer(draw),
      log_mem = log_mem,
      log_tag = sprintf("ablation draw %03d", draw)
    )
    TX_sim <- sim$TX_sim
    T_P_adj <- sim$T_P_adj
    delta_lookup_region <- sim$delta_lookup_region
    sigma_draw <- sim$sigma_draw
    sigma_use <- sim$sigma_use

    delta_unit_values <- NULL
    if (!is.null(delta_lookup_region) && nrow(region_lookup)) {
      delta_unit_values <- region_lookup %>%
        dplyr::mutate(delta = delta_lookup_region[.data$region]) %>%
        dplyr::mutate(delta = dplyr::coalesce(.data$delta, 0)) %>%
        {stats::setNames(.$delta, .$unit_id)}
    }
    score <- exdyn_loss_real(
      TX_obs = TX_obs,
      T_P = T_P_adj,
      TX_sim = TX_sim,
      unit_lookup = unit_lookup,
      coverage_breaks = unit_info$coverage_breaks,
      compat_cfg = compat_cfg,
      delta_lookup = delta_unit_values,
      delta_adj = adjacency,
      delta_penalty_cfg = delta_penalty_cfg,
      unit_timing_stat = unit_timing_stat
    )

    lag_range <- compat_cfg$lag_range %||% c(-Inf, Inf)
    compatible <- isTRUE(is.finite(score$r2_arrival) && score$r2_arrival >= (compat_cfg$min_r2_arrival %||% -Inf)) &&
      isTRUE(is.finite(score$lag_mean) &&
        score$lag_mean >= lag_range[1] &&
        score$lag_mean <= lag_range[2]) &&
      isTRUE(score$coverage >= (compat_cfg$min_coverage %||% 0))

    tibble::tibble(
      draw = draw,
      model = if (isTRUE(use_re)) "delta_plus_re" else "delta_only",
      pred_scale_re_sigma_draw = sigma_draw,
      pred_scale_re_sigma_used = sigma_use,
      r2_arrival = score$r2_arrival,
      lag_mean = score$lag_mean,
      coverage = score$coverage,
      coverage_curve_rmse = score$coverage_curve_rmse,
      anisotropy_gap = score$anisotropy_gap,
      delta_penalty = score$delta_penalty,
      unit_timing_stat = score$unit_timing_stat,
      loss = score$loss,
      compatible = compatible
    )
  }

  n_cores <- max(1L, as.integer(n_cores %||% 1L))
  n_cores <- min(n_cores, nrow(theta_tbl))
  idx <- seq_len(nrow(theta_tbl))
  rows <- if (n_cores > 1L && .Platform$OS.type != "windows") {
    parallel::mclapply(idx, run_draw, mc.cores = n_cores, mc.set.seed = FALSE)
  } else {
    lapply(idx, run_draw)
  }
  dplyr::bind_rows(rows)
}

exdyn_real_ablation_summary <- function(ablation_tbl) {
  if (!nrow(ablation_tbl)) {
    return(tibble::tibble())
  }
  ablation_tbl %>%
    dplyr::group_by(.data$model) %>%
    dplyr::summarise(
      n_draws = dplyr::n(),
      compatible_rate = mean(.data$compatible, na.rm = TRUE),
      median_loss = stats::median(.data$loss, na.rm = TRUE),
      median_r2 = stats::median(.data$r2_arrival, na.rm = TRUE),
      median_lag = stats::median(.data$lag_mean, na.rm = TRUE),
      median_coverage = stats::median(.data$coverage, na.rm = TRUE),
      median_delta_penalty = stats::median(.data$delta_penalty, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$model)
}
