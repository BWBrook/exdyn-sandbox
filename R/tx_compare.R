# Shared TX/T_P comparison helpers (internal)

.exdyn_vector_pair_stats <- function(tx_vals, tp_vals) {
  tp_finite <- is.finite(tp_vals)
  paired <- tp_finite & is.finite(tx_vals)

  coverage <- if (sum(tp_finite) > 0) sum(paired) / sum(tp_finite) else 0
  r2 <- NA_real_
  lag_mean <- NA_real_

  if (sum(paired) >= 3) {
    tx_ok <- tx_vals[paired]
    tp_ok <- tp_vals[paired]
    var_tp <- stats::var(tp_ok)
    var_tx <- stats::var(tx_ok)
    if (!is.finite(var_tp) || var_tp <= 0 || !is.finite(var_tx) || var_tx <= 0) {
      r2 <- 0
    } else {
      r <- suppressWarnings(stats::cor(tx_ok, tp_ok, use = "complete.obs"))
      r2 <- if (is.finite(r)) max(0, min(1, r^2)) else NA_real_
    }
    lag_mean <- mean(tx_ok - tp_ok, na.rm = TRUE)
  } else if (sum(paired) > 0) {
    lag_mean <- mean(tx_vals[paired] - tp_vals[paired], na.rm = TRUE)
  }

  list(
    coverage = coverage,
    r2 = r2,
    lag_mean = lag_mean,
    n_pairs = sum(paired),
    n_tp_finite = sum(tp_finite),
    n_tx_finite = sum(is.finite(tx_vals))
  )
}

.exdyn_vector_coverage_curve <- function(tx_vals, tp_vals, breaks) {
  if (is.null(breaks) || !length(breaks)) {
    return(numeric())
  }
  tp_finite <- is.finite(tp_vals)
  denom <- sum(tp_finite)
  if (!denom) {
    return(rep(NA_real_, length(breaks)))
  }
  purrr::map_dbl(breaks, function(brk) {
    sum(tp_finite & is.finite(tx_vals) & tx_vals <= brk) / denom
  })
}

.exdyn_curve_rmse <- function(curve_obs, curve_sim) {
  if (!length(curve_obs) || !length(curve_sim)) {
    return(NA_real_)
  }
  sqrt(mean((curve_obs - curve_sim)^2, na.rm = TRUE))
}

.exdyn_anis_gap <- function(R_obs, R_sim) {
  if (is.finite(R_obs) && is.finite(R_sim)) {
    abs(R_obs - R_sim)
  } else {
    NA_real_
  }
}

.exdyn_lag_penalty <- function(lag_sim, lag_range) {
  lag_range <- lag_range %||% c(0, Inf)
  if (!is.finite(lag_sim)) {
    return(1)
  }
  if (lag_sim < lag_range[1]) {
    return((lag_range[1] - lag_sim) / max(1, diff(lag_range)))
  }
  if (lag_sim > lag_range[2]) {
    return((lag_sim - lag_range[2]) / max(1, diff(lag_range)))
  }
  0
}

.exdyn_weighted_gap_score <- function(obs_stats,
                                      sim_stats,
                                      lag_range,
                                      anis_gap,
                                      curve_rmse,
                                      weights,
                                      delta_penalty = 0) {
  weights <- utils::modifyList(
    list(r2 = 0.4, lag = 0.2, coverage = 0.2, anis = 0.1, curve = 0.1, delta = 0),
    weights %||% list()
  )

  r2_term <- if (is.finite(obs_stats$r2) && is.finite(sim_stats$r2)) {
    abs(obs_stats$r2 - sim_stats$r2)
  } else {
    1
  }
  coverage_term <- if (is.finite(obs_stats$coverage) && is.finite(sim_stats$coverage)) {
    abs(obs_stats$coverage - sim_stats$coverage)
  } else {
    1
  }
  lag_term <- .exdyn_lag_penalty(sim_stats$lag_mean, lag_range)
  anis_term <- ifelse(is.finite(anis_gap), anis_gap, 1)
  curve_term <- ifelse(is.finite(curve_rmse), curve_rmse, 1)

  loss_terms <- c(
    r2 = weights$r2 * r2_term,
    lag = weights$lag * lag_term,
    coverage = weights$coverage * coverage_term,
    anis = weights$anis * anis_term,
    curve = weights$curve * curve_term,
    delta = weights$delta * (delta_penalty %||% 0)
  )

  list(
    r2_term = r2_term,
    coverage_term = coverage_term,
    lag_penalty = lag_term,
    anis_term = anis_term,
    curve_term = curve_term,
    loss_terms = loss_terms,
    loss = sum(loss_terms, na.rm = TRUE)
  )
}
