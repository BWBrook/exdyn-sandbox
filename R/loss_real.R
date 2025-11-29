#' Loss components for the real-data pilot
#'
#' Aggregates cell-level matrices to analysis units and computes the mixed
#' response-only loss used during the screen/ABC stages.
#'
#' @param TX_obs Matrix of observed extirpation years (cells).
#' @param T_P Matrix of arrival years (cells).
#' @param TX_sim Matrix of simulated extirpations (cells).
#' @param unit_lookup Tibble with `row_idx`, `col_idx`, `unit_id`.
#' @param coverage_breaks Numeric vector of year thresholds for coverage curves.
#' @param compat_cfg Compatibility configuration (lag range etc.).
#' @param delta_lookup Named numeric vector of delta values.
#' @param delta_adj Adjacency tibble for delta units.
#' @param delta_penalty_cfg List with `lambda_mag` and `lambda_tv`.
#'
#' @return List with metrics, per-term losses, and coverage curves.
#' @export
exdyn_loss_real <- function(TX_obs, T_P, TX_sim,
                            unit_lookup,
                            coverage_breaks,
                            compat_cfg,
                            delta_lookup = NULL,
                            delta_adj = NULL,
                            delta_penalty_cfg = list(lambda_mag = 0, lambda_tv = 0)) {
  required_cols <- c("row_idx", "col_idx", "unit_id")
  if (!all(required_cols %in% names(unit_lookup))) {
    stop("unit_lookup must contain row_idx, col_idx, unit_id")
  }

  agg_values <- function(mat) {
    vals <- tibble::tibble(
      row_idx = rep(seq_len(nrow(mat)), times = ncol(mat)),
      col_idx = rep(seq_len(ncol(mat)), each = nrow(mat)),
      value = as.vector(mat)
    ) %>%
      dplyr::left_join(unit_lookup, by = c("row_idx", "col_idx")) %>%
      dplyr::filter(!is.na(.data$unit_id)) %>%
      dplyr::group_by(.data$unit_id) %>%
      dplyr::summarise(value = suppressWarnings(min(.data$value, na.rm = TRUE)), .groups = "drop")
    if (!nrow(vals)) {
      return(tibble::tibble(unit_id = character(), value = numeric()))
    }
    vals$value[!is.finite(vals$value)] <- NA_real_
    vals
  }

  obs_units <- agg_values(TX_obs)
  sim_units <- agg_values(TX_sim)
  arrival_units <- agg_values(T_P)

  units_joined <- obs_units %>%
    dplyr::rename(tx_obs = value) %>%
    dplyr::full_join(sim_units %>% dplyr::rename(tx_sim = value), by = "unit_id") %>%
    dplyr::left_join(arrival_units %>% dplyr::rename(tp = value), by = "unit_id")

  valid_idx <- with(units_joined, is.finite(tx_obs) & is.finite(tp))
  coverage <- mean(valid_idx)
  r2 <- NA_real_
  lag_mean <- NA_real_
  if (sum(valid_idx) >= 3) {
    fit <- stats::lm(tx_obs ~ tp, data = units_joined[valid_idx, ])
    r2 <- max(0, min(1, summary(fit)$r.squared))
    lag_mean <- mean(units_joined$tx_obs[valid_idx] - units_joined$tp[valid_idx])
  }

  coverage_norm <- min(coverage, 0.3) / 0.3
  lag_range <- compat_cfg$lag_range %||% c(0, Inf)
  if (!is.finite(lag_mean)) {
    lag_pen <- 1
  } else if (lag_mean < lag_range[1]) {
    lag_pen <- (lag_range[1] - lag_mean) / max(1, diff(lag_range))
  } else if (lag_mean > lag_range[2]) {
    lag_pen <- (lag_mean - lag_range[2]) / max(1, diff(lag_range))
  } else {
    lag_pen <- 0
  }

  cov_curve_obs <- exdyn_coverage_curve(TX_obs, T_P, coverage_breaks)
  cov_curve_sim <- exdyn_coverage_curve(TX_sim, T_P, coverage_breaks)
  curve_rmse <- if (length(cov_curve_obs) && length(cov_curve_sim)) {
    sqrt(mean((cov_curve_obs - cov_curve_sim)^2, na.rm = TRUE))
  } else {
    NA_real_
  }

  orient_obs <- tryCatch(exdyn_orientation_metrics(TX_obs), error = function(...) list(R = NA_real_))
  orient_sim <- tryCatch(exdyn_orientation_metrics(TX_sim), error = function(...) list(R = NA_real_))
  anis_gap <- if (is.finite(orient_obs$R %||% NA_real_) && is.finite(orient_sim$R %||% NA_real_)) {
    abs((orient_obs$R %||% NA_real_) - (orient_sim$R %||% NA_real_))
  } else {
    NA_real_
  }

  lambda_mag <- delta_penalty_cfg$lambda_mag %||% 0
  lambda_tv <- delta_penalty_cfg$lambda_tv %||% 0
  pen_delta <- exdyn_delta_penalty(delta_lookup, delta_adj, lambda_mag, lambda_tv)

  L_r2 <- 0.4 * ifelse(is.finite(r2), 1 - r2, 1)
  L_lag <- 0.2 * lag_pen
  L_cov <- 0.15 * (1 - coverage_norm)
  L_aniso <- 0.1 * ifelse(is.finite(anis_gap), anis_gap, 1)
  L_curve <- 0.1 * ifelse(is.finite(curve_rmse), curve_rmse, 1)
  L_delta <- 0.05 * pen_delta

  loss <- L_r2 + L_lag + L_cov + L_aniso + L_curve + L_delta

  list(
    r2_arrival = r2,
    lag_mean = lag_mean,
    coverage = coverage,
    anisotropy_obs = orient_obs$R %||% NA_real_,
    anisotropy_sim = orient_sim$R %||% NA_real_,
    anisotropy_gap = anis_gap,
    coverage_curve_rmse = curve_rmse,
    delta_penalty = pen_delta,
    loss = loss,
    loss_terms = c(r2 = L_r2, lag = L_lag, coverage = L_cov, anis = L_aniso, curve = L_curve, delta = L_delta),
    coverage_curve_obs = cov_curve_obs,
    coverage_curve_sim = cov_curve_sim,
    units_joined = units_joined
  )
}
