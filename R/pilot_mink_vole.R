#' Mink → water vole pilot utilities
#'
#' Functions to sample parameter sets, run simulations, score them against
#' observed vole extirpations, and emit diagnostic artefacts.
#'
#' @name pilot_mink_vole
NULL

#' Latin-hypercube parameter draws for the pilot
#'
#' @param cfg_screen List of parameter ranges (see \code{config/realdata.yaml}).
#' @param n Number of draws.
#' @param cell_km Grid cell size in kilometres.
#' @param seed Random seed.
#'
#' @return Tibble of sampled parameters.
#' @export
exdyn_param_lhs <- function(cfg_screen, n = NULL, cell_km = 10, seed = 123) {
  n <- n %||% cfg_screen$n_draws %||% 100
  set.seed(seed)
  delta_cfg <- cfg_screen$delta_region %||% list()
  delta_names <- names(delta_cfg)
  param_names <- c(
    "alpha", "disp_mean_km", "A_over_K",
    "pred_c", "pred_h", "ramp_years",
    "pred_scale", "gamma",
    paste0("delta_", delta_names)
  )
  param_names <- param_names[!duplicated(param_names)]
  lhs <- lhs::randomLHS(n, length(param_names))
  scalers <- function(vals, range) {
    range[1] + vals * (range[2] - range[1])
  }
  tib <- tibble::tibble(
    draw = seq_len(n),
    alpha = scalers(lhs[, which(param_names == "alpha")], cfg_screen$alpha),
    disp_mean_km = scalers(lhs[, which(param_names == "disp_mean_km")], cfg_screen$disp_mean_km),
    A_over_K = scalers(lhs[, which(param_names == "A_over_K")], cfg_screen$A_over_K),
    pred_c = scalers(lhs[, which(param_names == "pred_c")], cfg_screen$pred_c),
    pred_h = scalers(lhs[, which(param_names == "pred_h")], cfg_screen$pred_h),
    ramp_years = round(scalers(lhs[, which(param_names == "ramp_years")], cfg_screen$ramp_years)),
    pred_scale = scalers(lhs[, which(param_names == "pred_scale")], cfg_screen$pred_scale),
    gamma = scalers(lhs[, which(param_names == "gamma")], cfg_screen$gamma),
    rmax = runif(n, cfg_screen$rmax[1], cfg_screen$rmax[2]),
    K0 = cfg_screen$K0,
    disp_mean_cells = disp_mean_km / cell_km
  )
  if (length(delta_names)) {
    for (i in seq_along(delta_names)) {
      col_name <- paste0("delta_", delta_names[i])
      bounds <- delta_cfg[[delta_names[i]]]
      lhs_col <- lhs[, which(param_names == col_name)]
      tib[[col_name]] <- scalers(lhs_col, bounds)
    }
  }
  tib
}

#' Parameter bounds helper for LHS and ABC samplers
#'
#' @param cfg_screen Screen configuration list.
#' @param cell_km Grid cell size (km).
#'
#' @return Named list of parameter bounds plus \code{cell_km}.
#' @export
exdyn_param_bounds <- function(cfg_screen, cell_km = 10) {
  bounds <- list(
    alpha = cfg_screen$alpha,
    disp_mean_km = cfg_screen$disp_mean_km,
    A_over_K = cfg_screen$A_over_K,
    pred_c = cfg_screen$pred_c,
    pred_h = cfg_screen$pred_h,
    ramp_years = cfg_screen$ramp_years,
    pred_scale = cfg_screen$pred_scale,
    gamma = cfg_screen$gamma,
    rmax = cfg_screen$rmax
  )
  bounds$disp_mean_cells <- bounds$disp_mean_km / cell_km
  bounds$cell_km <- cell_km
  if (!is.null(cfg_screen$delta_region)) {
    for (nm in names(cfg_screen$delta_region)) {
      bounds[[paste0("delta_", nm)]] <- cfg_screen$delta_region[[nm]]
    }
  }
  bounds
}

#' @keywords internal
exdyn_theta_jitter <- function(theta, bounds, jitter_sd = 0.05) {
  if (is.null(theta)) return(theta)
  jitter_one <- function(value, lims) {
    if (length(lims) < 2 || !all(is.finite(lims))) return(value)
    range <- lims[2] - lims[1]
    sd_val <- if (range > 0) jitter_sd * range else jitter_sd
    proposal <- stats::rnorm(1, mean = value, sd = sd_val)
    proposal <- min(proposal, lims[2])
    proposal <- max(proposal, lims[1])
    proposal
  }
  for (nm in names(bounds)) {
    if (nm == "cell_km") next
    if (!is.null(theta[[nm]])) {
      theta[[nm]] <- jitter_one(theta[[nm]], bounds[[nm]])
    }
  }
  cell_km <- bounds$cell_km %||% 10
  if (!is.null(theta$disp_mean_km)) {
    theta$disp_mean_cells <- theta$disp_mean_km / cell_km
  }
  theta
}

#' Wrapper around extirpation time helper (alias)
#' @export
exdyn_tx_first_passage <- function(N, K0, frac = 0.02, adaptive = TRUE, rel0 = 0.5) {
  exdyn_extirpation_time(N, K0 = K0, frac = frac, adaptive = adaptive, rel0 = rel0)
}

#' Simulate vole dynamics for a parameter draw
#'
#' @param theta_row Single-row tibble of parameters.
#' @param fields List from \code{exdyn_fields_from_mink()}.
#' @param K0 Carrying capacity per cell.
#'
#' @return Abundance array \code{N[x,y,t]}.
#' @export
exdyn_simulate_params <- function(theta_row, fields, K0) {
  .Deprecated("exdyn_simulate_tx_only")
  theta <- as.list(theta_row)
  pars <- list(
    rmax = theta$rmax,
    A_frac = theta$A_over_K * K0,
    beta_H = 0,
    d = 0.03
  )
  exdyn_simulate_tx_only(
    grid_info = fields$grid_info,
    years = fields$years,
    T_P = fields$T_P,
    ramp_years = theta$ramp_years,
    pars = pars,
    K0 = K0,
    alpha = theta$alpha,
    disp_mean_cells = theta$disp_mean_cells,
    pred = list(
      type = "II",
      c = theta$pred_c,
      h = theta$pred_h,
      scale = theta$pred_scale %||% 1,
      gamma = theta$gamma %||% 1
    ),
    pre_leak = fields$pre_leak %||% 0,
    log_mem = FALSE
  )
}

#' Score simulated extirpations against observed data
#'
#' @param TX_obs Matrix of observed extirpation times.
#' @param T_P Predation arrival matrix.
#' @param TX_sim Matrix of simulated extirpation times.
#' @param compat_cfg Compatibility thresholds.
#' @param coverage_breaks Optional numeric vector of year thresholds used
#'   to compare cumulative coverage between observed and simulated maps.
#' @return Tibble (one row) with metrics and loss.
#' @export
exdyn_score <- function(TX_obs, T_P, TX_sim, compat_cfg, coverage_breaks = NULL) {
  idx <- which(is.finite(TX_obs) & is.finite(T_P))
  denom <- sum(is.finite(T_P))
  coverage <- if (length(idx) && denom > 0) length(idx) / denom else 0
  if (length(idx) >= 3) {
    fit <- stats::lm(TX_obs[idx] ~ T_P[idx])
    r2 <- max(0, min(1, summary(fit)$r.squared))
  } else {
    r2 <- NA_real_
  }
  lag_mean <- if (length(idx)) mean(TX_obs[idx] - T_P[idx]) else NA_real_
  orient_obs <- tryCatch(exdyn_orientation_metrics(TX_obs), error = function(...) list(R = NA_real_))
  orient_sim <- tryCatch(exdyn_orientation_metrics(TX_sim), error = function(...) list(R = NA_real_))
  R_obs <- orient_obs$R %||% NA_real_
  R_sim <- orient_sim$R %||% NA_real_
  anis_gap <- if (is.finite(R_obs) && is.finite(R_sim)) abs(R_obs - R_sim) else NA_real_
  curve_obs <- exdyn_coverage_curve(TX_obs, T_P, coverage_breaks)
  curve_sim <- exdyn_coverage_curve(TX_sim, T_P, coverage_breaks)
  curve_rmse <- if (length(curve_obs) && length(curve_sim)) {
    sqrt(mean((curve_obs - curve_sim)^2, na.rm = TRUE))
  } else {
    NA_real_
  }
  w1 <- 0.4; w2 <- 0.2; w3 <- 0.2; w4 <- 0.1; w5 <- 0.1
  r2_term <- ifelse(is.finite(r2), 1 - r2, 1)
  coverage_term <- 1 - coverage
  lag_range <- compat_cfg$lag_range %||% c(0, Inf)
  lag_pen <- if (is.finite(lag_mean)) {
    if (lag_mean < lag_range[1]) (lag_range[1] - lag_mean) / max(1, diff(lag_range))
    else if (lag_mean > lag_range[2]) (lag_mean - lag_range[2]) / max(1, diff(lag_range))
    else 0
  } else 1
  anis_term <- ifelse(is.finite(anis_gap), anis_gap, 1)
  curve_term <- ifelse(is.finite(curve_rmse), curve_rmse, 1)
  loss <- w1 * r2_term + w2 * lag_pen + w3 * coverage_term + w4 * anis_term + w5 * curve_term
  compatible <- TRUE
  compatible <- compatible && is.finite(r2) && r2 >= (compat_cfg$min_r2_arrival %||% 0)
  compatible <- compatible && is.finite(lag_mean) &&
    lag_mean >= lag_range[1] && lag_mean <= lag_range[2]
  compatible <- compatible && coverage >= (compat_cfg$min_coverage %||% 0)

  tibble::tibble(
    r2_arrival = r2,
    lag_mean = lag_mean,
    coverage = coverage,
    anisotropy_obs = R_obs,
    anisotropy_sim = R_sim,
    anisotropy_gap = anis_term,
    coverage_curve_rmse = curve_rmse,
    loss = loss,
    compatible = compatible
  )
}

#' Run parameter screen and rank outputs
#'
#' @param theta Tibble of parameter draws.
#' @param arrivals Mink arrivals tibble.
#' @param grid_info Grid lookup.
#' @param years Year vector.
#' @param TX_obs Matrix of observed extirpations.
#' @param cfg_screen Screen configuration.
#' @param cfg_mink Mink predation config (ramp/leak).
#' @param compat_cfg Compatibility thresholds.
#'
#' @return List with \code{results} tibble and \code{tx_sim} list.
#' @export
exdyn_screen_and_rank <- function(theta, grid_info, years, T_P,
                                  TX_obs, cfg_screen, cfg_mink, compat_cfg,
                                  coverage_breaks = NULL,
                                  log_mem = FALSE) {
  results <- vector("list", nrow(theta))
  tx_sims <- vector("list", nrow(theta))
  for (i in seq_len(nrow(theta))) {
    pars <- list(
      rmax = theta$rmax[i],
      A_frac = theta$A_over_K[i] * theta$K0[i],
      beta_H = 0,
      d = 0.03
    )
    TX_sim <- exdyn_simulate_tx_only(
      grid_info = grid_info,
      years = years,
      T_P = T_P,
      ramp_years = theta$ramp_years[i],
      pars = pars,
      K0 = theta$K0[i],
      alpha = theta$alpha[i],
      disp_mean_cells = theta$disp_mean_cells[i],
      pred = list(
        type = "II",
        c = theta$pred_c[i],
        h = theta$pred_h[i],
        scale = theta$pred_scale[i] %||% 1,
        gamma = theta$gamma[i] %||% 1
      ),
      pre_leak = cfg_mink$pre_arrival_leak %||% 0,
      log_mem = log_mem,
      log_tag = sprintf(
        "draw %03d",
        if ("draw" %in% names(theta)) theta$draw[i] else i
      )
    )
    metrics <- exdyn_score(TX_obs, T_P, TX_sim, compat_cfg, coverage_breaks = coverage_breaks)
    results[[i]] <- dplyr::bind_cols(theta[i, ], metrics)
    tx_sims[[i]] <- TX_sim
    gc()
  }
  res_df <- dplyr::bind_rows(results) %>%
    dplyr::arrange(loss) %>%
    dplyr::mutate(rank = dplyr::row_number())
  list(results = res_df, tx_sim = tx_sims)
}

#' Convert matrix to long tibble for plotting
#'
#' @param mat Matrix (rows = row_levels, cols = col_levels).
#' @param grid_info Grid lookup.
#' @param value_name Column name for value.
#'
#' @return Tibble with columns \code{row,col,value}.
#' @export
exdyn_matrix_to_df <- function(mat, grid_info, value_name = "value") {
  vals <- mat[cbind(grid_info$lookup$row_idx, grid_info$lookup$col_idx)]
  tibble::tibble(
    cell_id = grid_info$lookup$cell_id,
    row = grid_info$lookup$row,
    col = grid_info$lookup$col,
    !!value_name := vals
  )
}

#' Plot raster-like matrix as ggplot tile
#'
#' @param mat Matrix to visualise.
#' @param grid_info Grid lookup.
#' @param title Plot title.
#' @param fill_label Legend title.
#'
#' @return ggplot object.
#' @export
exdyn_plot_surface <- function(mat, grid_info, title, fill_label = "Year") {
  df <- exdyn_matrix_to_df(mat, grid_info, "value")
  ggplot2::ggplot(df, ggplot2::aes(x = col, y = row, fill = value)) +
    ggplot2::geom_tile(color = NA) +
    ggplot2::scale_y_reverse() +
    ggplot2::scale_fill_viridis_c(option = "magma", na.value = "grey90") +
    ggplot2::coord_equal() +
    ggplot2::labs(title = title, fill = fill_label, x = "Column", y = "Row") +
    ggplot2::theme_minimal()
}

#' Scatter plot of observed vs predator arrival times
#'
#' @param TX_obs Matrix of observed extirpations.
#' @param T_P Matrix of predator arrival times.
#'
#' @return ggplot object.
#' @export
exdyn_plot_tx_scatter <- function(TX_obs, T_P) {
  idx <- which(is.finite(TX_obs) & is.finite(T_P))
  df <- tibble::tibble(
    T_P = T_P[idx],
    T_X = TX_obs[idx]
  )
  if (!nrow(df)) {
    return(ggplot2::ggplot() + ggplot2::labs(title = "No overlapping cells"))
  }
  fit <- tryCatch(stats::lm(T_X ~ T_P, data = df), error = function(...) NULL)
  r2 <- if (!is.null(fit)) round(summary(fit)$r.squared, 3) else NA_real_
  lag <- if (nrow(df)) round(mean(df$T_X - df$T_P), 2) else NA_real_
  ggplot2::ggplot(df, ggplot2::aes(x = T_P, y = T_X)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, colour = "grey70", linetype = "dashed") +
    ggplot2::geom_point(alpha = 0.3, size = 1.2) +
    ggplot2::labs(
      title = "Observed vole extirpation vs mink arrival",
      subtitle = sprintf("r² = %s, mean lag = %s yrs", r2, lag),
      x = "Mink arrival year",
      y = "Observed vole extirpation year"
    ) +
    ggplot2::theme_minimal()
}

#' Write diagnostic PNGs for top parameter sets
#'
#' @param tx_obs_mat Observed extirpation matrix.
#' @param tx_sources Optional list of simulated matrices or character vector of
#'   file paths (one per row of \code{scores}). When omitted, the function will
#'   look for a \code{tx_path} column in \code{scores}.
#' @param scores Ranked tibble with `rank` column.
#' @param grid_info Grid lookup.
#' @param out_dir Output directory.
#' @param top_k Number of best simulations to export.
#'
#' @return Vector of written file paths.
#' @export
exdyn_write_best_maps <- function(tx_obs_mat, tx_sources = NULL, scores, grid_info, out_dir, top_k = 3) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c()
  obs_plot <- exdyn_plot_surface(tx_obs_mat, grid_info, "Observed vole extirpation (TX_obs)")
  obs_path <- file.path(out_dir, "TX_obs_riparian_map.png")
  ggplot2::ggsave(obs_path, obs_plot, width = 7, height = 7, dpi = 150)
  paths <- c(paths, obs_path)
  top_ids <- scores %>% dplyr::arrange(loss) %>% dplyr::slice_head(n = top_k)
  for (i in seq_len(nrow(top_ids))) {
    rank_i <- top_ids$rank[i]
    idx <- which(scores$rank == rank_i)
    if (!length(idx)) next
    mat <- NULL
    if (!is.null(tx_sources)) {
      if (is.character(tx_sources)) {
        candidate <- tx_sources[idx]
        if (length(candidate) && !is.na(candidate) && file.exists(candidate)) {
          mat <- readRDS(candidate)
        }
      } else if (is.list(tx_sources)) {
        mat <- tx_sources[[idx]]
      }
    }
    if (is.null(mat) && "tx_path" %in% names(scores)) {
      candidate <- scores$tx_path[idx]
      if (length(candidate) && !is.na(candidate) && file.exists(candidate)) {
        mat <- readRDS(candidate)
      }
    }
    if (is.null(mat)) next
    sim_plot <- exdyn_plot_surface(mat, grid_info, sprintf("Simulated TX (rank %d)", rank_i))
    path <- file.path(out_dir, sprintf("TX_sim_rank%02d.png", rank_i))
    ggplot2::ggsave(path, sim_plot, width = 7, height = 7, dpi = 150)
    paths <- c(paths, path)
    diff_mat <- tx_obs_mat - mat
    diff_plot <- exdyn_plot_surface(diff_mat, grid_info, sprintf("Observed - simulated TX (rank %d)", rank_i))
    diff_path <- file.path(out_dir, sprintf("TX_diff_rank%02d.png", rank_i))
    ggplot2::ggsave(diff_path, diff_plot, width = 7, height = 7, dpi = 150)
    paths <- c(paths, diff_path)
  }
  paths
}
