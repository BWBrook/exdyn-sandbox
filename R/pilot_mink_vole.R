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
  if (!is.null(cfg_screen$pred_scale_re_sigma)) {
    param_names <- c(param_names, "pred_scale_re_sigma")
  }
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
  if (!is.null(cfg_screen$pred_scale_re_sigma)) {
    tib$pred_scale_re_sigma <- scalers(lhs[, which(param_names == "pred_scale_re_sigma")], cfg_screen$pred_scale_re_sigma)
  }
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
  bounds$cell_km <- cell_km
  if (!is.null(cfg_screen$delta_region)) {
    for (nm in names(cfg_screen$delta_region)) {
      bounds[[paste0("delta_", nm)]] <- cfg_screen$delta_region[[nm]]
    }
  }
  bounds
}

#' Jitter helper for parameter draws
#'
#' @keywords internal
#' @export
exdyn_theta_jitter <- function(theta, bounds, jitter_sd = 0.05) {
  if (is.null(theta)) return(theta)
  # expose delta_* entries for jittering
  if (!is.null(theta$delta_region)) {
    for (nm in names(theta$delta_region)) {
      theta[[paste0("delta_", nm)]] <- theta$delta_region[[nm]]
    }
  }
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
  delta_cols <- grep("^delta_", names(bounds), value = TRUE)
  if (length(delta_cols)) {
    delta_vals <- numeric(0)
    for (col in delta_cols) {
      short <- sub("^delta_", "", col)
      if (!is.null(theta[[col]])) {
        delta_vals[short] <- theta[[col]]
      }
    }
    if (length(delta_vals)) theta$delta_region <- delta_vals
  }
  theta
}

#' Wrapper around extirpation time helper (alias)
#' @export
exdyn_tx_first_passage <- function(N, K0, frac = 0.02, adaptive = TRUE, rel0 = 0.5) {
  exdyn_extirpation_time(N, K0 = K0, frac = frac, adaptive = adaptive, rel0 = rel0)
}

#' Score simulated extirpations against observed data
#'
#' @param TX_obs Matrix of observed extirpation times.
#' @param T_P Predation arrival matrix.
#' @param TX_sim Matrix of simulated extirpation times.
#' @param compat_cfg Compatibility thresholds.
#' @param coverage_breaks Optional numeric vector of year thresholds used
#'   to compare cumulative coverage between observed and simulated maps.
#' @param mask Optional logical matrix specifying the analysis domain.
#' @return Tibble (one row) with metrics and loss.
#' @export
exdyn_score <- function(TX_obs, T_P, TX_sim, compat_cfg, coverage_breaks = NULL, mask = NULL) {
  counts_obs <- exdyn_summary_counts(TX_obs, T_P, mask = mask)
  counts_sim <- exdyn_summary_counts(TX_sim, T_P, mask = mask)
  mask_use <- .exdyn_prepare_mask(mask, dim(T_P))
  TX_obs_use <- TX_obs
  TX_sim_use <- TX_sim
  T_P_use <- T_P
  TX_obs_use[!mask_use] <- NA_real_
  TX_sim_use[!mask_use] <- NA_real_
  T_P_use[!mask_use] <- NA_real_

  obs_stats <- .exdyn_vector_pair_stats(as.vector(TX_obs_use), as.vector(T_P_use))
  sim_stats <- .exdyn_vector_pair_stats(as.vector(TX_sim_use), as.vector(T_P_use))

  coverage_obs <- obs_stats$coverage
  coverage_sim <- sim_stats$coverage
  r2_obs <- obs_stats$r2
  r2_sim <- sim_stats$r2
  lag_obs <- obs_stats$lag_mean
  lag_sim <- sim_stats$lag_mean

  orient_obs <- tryCatch(exdyn_orientation_metrics(TX_obs_use), error = function(...) list(R = NA_real_))
  orient_sim <- tryCatch(exdyn_orientation_metrics(TX_sim_use), error = function(...) list(R = NA_real_))
  R_obs <- orient_obs$R %||% NA_real_
  R_sim <- orient_sim$R %||% NA_real_
  anis_gap <- .exdyn_anis_gap(R_obs, R_sim)
  curve_obs <- exdyn_coverage_curve(TX_obs_use, T_P_use, coverage_breaks, mask = mask_use)
  curve_sim <- exdyn_coverage_curve(TX_sim_use, T_P_use, coverage_breaks, mask = mask_use)
  curve_rmse <- .exdyn_curve_rmse(curve_obs, curve_sim)
  lag_range <- compat_cfg$lag_range %||% c(0, Inf)
  score <- .exdyn_weighted_gap_score(
    obs_stats = obs_stats,
    sim_stats = sim_stats,
    lag_range = lag_range,
    anis_gap = anis_gap,
    curve_rmse = curve_rmse,
    weights = list(r2 = 0.4, lag = 0.2, coverage = 0.2, anis = 0.1, curve = 0.1)
  )
  compatible <- TRUE
  compatible <- compatible && is.finite(r2_sim) && r2_sim >= (compat_cfg$min_r2_arrival %||% 0)
  compatible <- compatible && is.finite(lag_sim) &&
    lag_sim >= lag_range[1] && lag_sim <= lag_range[2]
  compatible <- compatible && coverage_sim >= (compat_cfg$min_coverage %||% 0)

  tibble::tibble(
    n_mask = counts_obs[["n_mask"]],
    n_TP_finite = counts_obs[["n_TP_finite"]],
    n_TX_obs = counts_obs[["n_TX_finite"]],
    n_TX_sim = counts_sim[["n_TX_finite"]],
    n_pairs_obs = counts_obs[["n_pairs"]],
    n_pairs_sim = counts_sim[["n_pairs"]],
    r2_arrival = r2_sim,
    lag_mean = lag_sim,
    coverage = coverage_sim,
    r2_arrival_obs = r2_obs,
    lag_mean_obs = lag_obs,
    coverage_obs = coverage_obs,
    anisotropy_obs = R_obs,
    anisotropy_sim = R_sim,
    anisotropy_gap = score$anis_term,
    coverage_curve_rmse = curve_rmse,
    loss = score$loss,
    compatible = compatible
  )
}
