#' Loss components for the real-data pilot
#'
#' Aggregates cell-level matrices to analysis units and computes the
#' unit-consistent response-only loss used during the screen/ABC stages.
#'
#' @param TX_obs Matrix of observed extirpation years (cells).
#' @param T_P Matrix of arrival years (cells).
#' @param TX_sim Matrix of simulated extirpations (cells).
#' @param unit_lookup Tibble with `row_idx`, `col_idx`, and `unit_id`.
#' @param coverage_breaks Numeric vector of year thresholds for coverage curves.
#' @param compat_cfg Compatibility configuration (lag range etc.).
#' @param delta_lookup Named numeric vector of delta values.
#' @param delta_adj Adjacency tibble for delta units.
#' @param delta_penalty_cfg List with `lambda_mag` and `lambda_tv`.
#' @param unit_timing_stat Unit-level aggregation rule for timings.
#'
#' @return List with metrics, per-term losses, and unit timing diagnostics.
#' @export

.exdyn_reduce_unit_time <- function(values, stat = "median") {
  stat <- match.arg(stat, c("median", "mean", "min"))
  vals <- values[is.finite(values)]
  if (!length(vals)) {
    return(NA_real_)
  }
  switch(
    stat,
    median = suppressWarnings(stats::median(vals, na.rm = TRUE)),
    mean = mean(vals, na.rm = TRUE),
    min = suppressWarnings(min(vals, na.rm = TRUE))
  )
}

.exdyn_unit_timing_table <- function(TX_obs, T_P, TX_sim,
                                     unit_lookup,
                                     unit_timing_stat = "median") {
  required_cols <- c("row_idx", "col_idx", "unit_id")
  if (!all(required_cols %in% names(unit_lookup))) {
    stop("unit_lookup must contain row_idx, col_idx, unit_id")
  }
  if (!all(dim(TX_obs) == dim(T_P), dim(T_P) == dim(TX_sim))) {
    stop("TX_obs, T_P, and TX_sim must have matching dimensions.")
  }

  lookup <- unit_lookup %>%
    dplyr::filter(!is.na(.data$unit_id), !is.na(.data$row_idx), !is.na(.data$col_idx)) %>%
    dplyr::distinct(.data$row_idx, .data$col_idx, .data$unit_id, .keep_all = TRUE)

  if (!nrow(lookup)) {
    return(tibble::tibble(
      unit_id = character(),
      region = character(),
      centroid_x = numeric(),
      centroid_y = numeric(),
      n_cells = integer(),
      tp = numeric(),
      tx_obs = numeric(),
      tx_sim = numeric(),
      n_tp_finite = integer(),
      n_tx_obs_finite = integer(),
      n_tx_sim_finite = integer()
    ))
  }

  if (!"region" %in% names(lookup)) {
    lookup$region <- NA_character_
  }
  if (!"centroid_x" %in% names(lookup)) {
    lookup$centroid_x <- lookup$col_idx
  }
  if (!"centroid_y" %in% names(lookup)) {
    lookup$centroid_y <- lookup$row_idx
  }

  if (any(lookup$row_idx < 1L | lookup$row_idx > nrow(T_P) |
          lookup$col_idx < 1L | lookup$col_idx > ncol(T_P))) {
    stop("unit_lookup indices fall outside the supplied matrix dimensions.")
  }

  cell_index <- cbind(lookup$row_idx, lookup$col_idx)
  lookup <- lookup %>%
    dplyr::mutate(
      tp_cell = T_P[cell_index],
      tx_obs_cell = TX_obs[cell_index],
      tx_sim_cell = TX_sim[cell_index]
    )

  lookup %>%
    dplyr::group_by(.data$unit_id) %>%
    dplyr::summarise(
      region = {
        vals <- unique(stats::na.omit(.data$region))
        if (length(vals)) as.character(vals[[1]]) else NA_character_
      },
      centroid_x = {
        vals <- .data$centroid_x[is.finite(.data$centroid_x)]
        if (length(vals)) mean(vals, na.rm = TRUE) else NA_real_
      },
      centroid_y = {
        vals <- .data$centroid_y[is.finite(.data$centroid_y)]
        if (length(vals)) mean(vals, na.rm = TRUE) else NA_real_
      },
      n_cells = dplyr::n(),
      tp = .exdyn_reduce_unit_time(.data$tp_cell, stat = unit_timing_stat),
      tx_obs = .exdyn_reduce_unit_time(.data$tx_obs_cell, stat = unit_timing_stat),
      tx_sim = .exdyn_reduce_unit_time(.data$tx_sim_cell, stat = unit_timing_stat),
      n_tp_finite = sum(is.finite(.data$tp_cell)),
      n_tx_obs_finite = sum(is.finite(.data$tx_obs_cell)),
      n_tx_sim_finite = sum(is.finite(.data$tx_sim_cell)),
      .groups = "drop"
    )
}

.exdyn_unit_paired_stats <- function(unit_tbl, tx_col) {
  .exdyn_vector_pair_stats(unit_tbl[[tx_col]], unit_tbl$tp)
}

.exdyn_unit_coverage_curve <- function(unit_tbl, tx_col, breaks) {
  .exdyn_vector_coverage_curve(unit_tbl[[tx_col]], unit_tbl$tp, breaks)
}

.exdyn_unit_orientation_metrics <- function(unit_tbl, tx_col) {
  df <- unit_tbl %>%
    dplyr::transmute(
      tx = .data[[tx_col]],
      centroid_x = .data$centroid_x,
      centroid_y = .data$centroid_y
    ) %>%
    dplyr::filter(
      is.finite(.data$tx),
      is.finite(.data$centroid_x),
      is.finite(.data$centroid_y)
    )

  if (nrow(df) < 3) {
    return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = 0L))
  }

  centroids <- df %>%
    dplyr::group_by(.data$tx) %>%
    dplyr::summarise(
      centroid_x = mean(.data$centroid_x, na.rm = TRUE),
      centroid_y = mean(.data$centroid_y, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(.data$tx)

  if (nrow(centroids) < 2) {
    return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = 0L))
  }

  dx <- diff(centroids$centroid_x)
  dy <- diff(centroids$centroid_y)
  mags <- sqrt(dx^2 + dy^2)
  positive <- mags > 0
  if (!any(positive)) {
    return(list(R = NA_real_, dominant = c(NA_real_, NA_real_), count = nrow(centroids) - 1L))
  }

  dx <- dx[positive]
  dy <- dy[positive]
  angles <- atan2(dy, dx)
  dominant <- c(sum(dx), sum(dy))
  dom_mag <- sqrt(sum(dominant^2))
  if (dom_mag > 0) {
    dominant <- dominant / dom_mag
  } else {
    dominant <- c(NA_real_, NA_real_)
  }

  list(
    R = sqrt(sum(cos(angles))^2 + sum(sin(angles))^2) / length(angles),
    dominant = dominant,
    count = length(angles)
  )
}

exdyn_loss_real <- function(TX_obs, T_P, TX_sim,
                            unit_lookup,
                            coverage_breaks,
                            compat_cfg,
                            delta_lookup = NULL,
                            delta_adj = NULL,
                            delta_penalty_cfg = list(lambda_mag = 0, lambda_tv = 0),
                            unit_timing_stat = "median") {
  unit_tbl <- .exdyn_unit_timing_table(
    TX_obs = TX_obs,
    T_P = T_P,
    TX_sim = TX_sim,
    unit_lookup = unit_lookup,
    unit_timing_stat = unit_timing_stat
  )

  obs_stats <- .exdyn_unit_paired_stats(unit_tbl, "tx_obs")
  sim_stats <- .exdyn_unit_paired_stats(unit_tbl, "tx_sim")

  coverage_obs <- obs_stats$coverage
  coverage_sim <- sim_stats$coverage
  r2_obs <- obs_stats$r2
  r2_sim <- sim_stats$r2
  lag_obs <- obs_stats$lag_mean
  lag_sim <- sim_stats$lag_mean

  cov_curve_obs <- .exdyn_unit_coverage_curve(unit_tbl, "tx_obs", coverage_breaks)
  cov_curve_sim <- .exdyn_unit_coverage_curve(unit_tbl, "tx_sim", coverage_breaks)
  curve_rmse <- .exdyn_curve_rmse(cov_curve_obs, cov_curve_sim)

  orient_obs <- .exdyn_unit_orientation_metrics(unit_tbl, "tx_obs")
  orient_sim <- .exdyn_unit_orientation_metrics(unit_tbl, "tx_sim")
  anis_gap <- .exdyn_anis_gap(orient_obs$R %||% NA_real_, orient_sim$R %||% NA_real_)

  lag_range <- compat_cfg$lag_range %||% c(0, Inf)
  lambda_mag <- delta_penalty_cfg$lambda_mag %||% 0
  lambda_tv <- delta_penalty_cfg$lambda_tv %||% 0
  pen_delta <- exdyn_delta_penalty(delta_lookup, delta_adj, lambda_mag, lambda_tv)
  score <- .exdyn_weighted_gap_score(
    obs_stats = obs_stats,
    sim_stats = sim_stats,
    lag_range = lag_range,
    anis_gap = anis_gap,
    curve_rmse = curve_rmse,
    weights = list(r2 = 0.4, lag = 0.2, coverage = 0.15, anis = 0.1, curve = 0.1, delta = 0.05),
    delta_penalty = pen_delta
  )

  list(
    r2_arrival = r2_sim,
    lag_mean = lag_sim,
    coverage = coverage_sim,
    r2_arrival_obs = r2_obs,
    lag_mean_obs = lag_obs,
    coverage_obs = coverage_obs,
    anisotropy_obs = orient_obs$R %||% NA_real_,
    anisotropy_sim = orient_sim$R %||% NA_real_,
    anisotropy_gap = anis_gap,
    coverage_curve_rmse = curve_rmse,
    delta_penalty = pen_delta,
    loss = score$loss,
    loss_terms = score$loss_terms,
    coverage_curve_obs = cov_curve_obs,
    coverage_curve_sim = cov_curve_sim,
    units_joined = unit_tbl,
    unit_timing_table = unit_tbl,
    unit_timing_stat = unit_timing_stat
  )
}
