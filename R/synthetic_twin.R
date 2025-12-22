#' Synthetic mink→vole twin generator
#'
#' Construct a synthetic mink-driven vole extirpation scenario on the
#' Great Britain 10 km grid using the real arrival surface but controlled
#' demographic and observation parameters. The output mirrors the
#' real-data pipeline products so the screening/ABC stages can be
#' exercised end-to-end under known truth.
#'
#' @param theta_star Named list of generating parameters. Recognised
#'   fields: `rmax`, `A_over_K`, `alpha`, `disp_mean_km`, `pred_scale`,
#'   `pred_c`, `pred_h`, `gamma`, `delta_region`, `ramp_years`,
#'   `pred_type`, `pre_leak`.
#' @param noise_cfg Named list describing observation noise with entries
#'   `po_rate`, `effort_strength`, `missing_years_prob`,
#'   `random_tx_dropout`, and `obs_mode` (`counts` or `points`).
#' @param arrivals Tibble with at least `cell_id` and arrival year column(s).
#' @param grid_info Lookup list from [exdyn_grid_lookup()].
#' @param years Integer vector of length 2 (start/end) or full sequence of
#'   simulation years.
#' @param tx_cfg Configuration list for [exdyn_tx_map()].
#' @param K0 Carrying capacity per cell used for simulation.
#' @param mask Optional logical matrix restricting the simulation to
#'   certain cells (e.g. riparian subset).
#'
#' @return List containing the generating parameters (`theta_star`),
#'   applied noise configuration (`noise_cfg`), yearly sequence (`years`),
#'   adjusted arrival matrix (`T_P`), full simulated abundance array
#'   (`N_true`, `NULL` when counts-only streaming is used), true
#'   extirpation matrix (`TX_true`), noisy observed extirpations (`TX_obs`),
#'   per-cell table (`tx_table`), occurrence counts (`tx_counts`),
#'   presence-only samples (`po_points`), effort samples
#'   (`effort_points`), and the mask used.
#' @export
exdyn_make_synthetic <- function(theta_star,
                                 noise_cfg,
                                 arrivals,
                                 grid_info,
                                 years,
                                 tx_cfg,
                                 K0 = 120,
                                 mask = NULL) {
  stopifnot(!is.null(grid_info))
  base_theta <- list(
    rmax = 0.4,
    A_over_K = 0.1,
    alpha = 0.2,
    disp_mean_km = 10,
    pred_scale = 1,
    pred_c = 0.8,
    pred_h = 30,
    gamma = 1,
    delta_region = NULL,
    ramp_years = 8,
    pred_type = "II",
    pre_leak = 0,
    truth_frac = 0.02,
    truth_rel0 = 0.5
  )
  theta <- utils::modifyList(base_theta, theta_star)
  base_noise <- list(
    po_rate = 0.001,
    effort_strength = 1,
    missing_years_prob = 0,
    random_tx_dropout = 0,
    obs_mode = "counts",
    keep_counts = FALSE,
    crop = FALSE
  )
  noise <- utils::modifyList(base_noise, noise_cfg)
  obs_mode <- noise$obs_mode %||% "counts"
  obs_mode <- tolower(obs_mode)
  if (length(years) == 2L) {
    years_seq <- seq.int(years[1], years[2])
  } else {
    years_seq <- sort(unique(as.integer(years)))
  }
  stopifnot(length(years_seq) >= 2L)
  ramp_years <- theta$ramp_years %||% 8L
  pred_type <- theta$pred_type %||% "II"
  delta_region <- theta$delta_region
  if (!is.null(delta_region)) {
    delta_region <- unlist(delta_region)
  }
  cell_km <- grid_info$cell_km %||% 10
  disp_mean_cells <- theta$disp_mean_km / cell_km

  arrivals_tbl <- exdyn_prepare_arrivals(arrivals)
  if (!is.null(mask)) {
    mask <- as.matrix(mask)
  } else {
    mask <- grid_info$riparian_matrix %||% matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  }
  pars <- list(
    rmax = theta$rmax,
    A_frac = theta$A_over_K * K0,
    beta_H = 0,
    d = 0.02
  )
  pred <- list(
    type = pred_type,
    c = theta$pred_c,
    h = theta$pred_h,
    scale = theta$pred_scale,
    gamma = theta$gamma
  )
  if (identical(obs_mode, "points")) {
    grid_for_fields <- grid_info
    grid_for_fields$riparian_matrix <- matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
    fields <- exdyn_fields_from_mink(
      arrivals = arrivals_tbl,
      grid_info = grid_for_fields,
      years = years_seq,
      ramp_years = ramp_years,
      pre_leak = theta$pre_leak %||% 0,
      scale = theta$pred_scale,
      gamma = theta$gamma,
      delta_region = delta_region
    )
    T_P <- fields$T_P
    N_true <- exdyn_simulate(
      nx = grid_info$nx,
      ny = grid_info$ny,
      years = length(years_seq),
      fields = fields,
      pars = pars,
      K0 = K0,
      alpha = theta$alpha,
      disp_mean_cells = disp_mean_cells,
      pred = pred
    )
    if (any(!mask)) {
      for (tt in seq_len(dim(N_true)[3])) {
        slice <- N_true[,,tt]
        slice[!mask] <- 0
        N_true[,,tt] <- slice
      }
    }
  } else {
    fields <- NULL
    T_P <- exdyn_arrival_matrix(
      arrivals = arrivals_tbl,
      grid_info = grid_info,
      years = years_seq,
      delta_region = delta_region
    )
    N_true <- NULL
  }
  truth_frac <- theta$truth_frac %||% 0.02
  truth_rel0 <- theta$truth_rel0 %||% 0.5
  TX_idx_stream <- exdyn_simulate_tx_only(
    grid_info = grid_info,
    years = years_seq,
    T_P = T_P,
    ramp_years = theta$ramp_years,
    pars = pars,
    K0 = K0,
    alpha = theta$alpha,
    disp_mean_cells = disp_mean_cells,
    pred = list(
      type = pred_type,
      c = theta$pred_c,
      h = theta$pred_h,
      scale = theta$pred_scale,
    gamma = theta$gamma
    ),
    pre_leak = theta$pre_leak %||% 0,
    mask = mask,
    crop = isTRUE(noise$crop),
    frac = truth_frac,
    rel0 = truth_rel0
  )
  TX_true <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  finite_idx <- is.finite(TX_idx_stream)
  if (any(finite_idx)) {
    TX_true[finite_idx] <- years_seq[TX_idx_stream[finite_idx]]
  }
  mask_mat <- mask
  TX_true[!mask_mat] <- NA_real_

  po_points <- NULL
  effort_points <- NULL
  counts_mat <- NULL
  if (identical(obs_mode, "points")) {
    po_points <- exdyn_synthetic_po_points(
      N_true,
      years_seq,
      grid_info,
      rate = noise$po_rate,
      effort_strength = noise$effort_strength
    )
    if (noise$missing_years_prob > 0 && nrow(po_points)) {
      year_keep <- stats::runif(length(unique(po_points$year))) >= noise$missing_years_prob
      keep_years <- unique(po_points$year)[year_keep]
      po_points <- dplyr::filter(po_points, .data$year %in% keep_years)
    }
    effort_points <- po_points
    tx_map <- exdyn_tx_map(
      cells_df = dplyr::select(po_points, cell_id, row, col, year),
      years = range(years_seq),
      cfg = tx_cfg,
      grid_info = grid_info,
      effort_cells = dplyr::select(effort_points, cell_id, row, col, year),
      mask = mask_mat
    )
  } else {
    counts_out <- exdyn_simulate_counts_stream(
      grid_info = grid_info,
      years = years_seq,
      T_P = T_P,
      ramp_years = theta$ramp_years,
      pars = pars,
      K0 = K0,
      alpha = theta$alpha,
      disp_mean_cells = disp_mean_cells,
      pred = pred,
      rate = noise$po_rate,
      effort_strength = noise$effort_strength,
      pre_leak = theta$pre_leak %||% 0,
      mask = mask_mat,
      crop = isTRUE(noise$crop)
    )
    counts_mat <- counts_out$counts_mat
    effort_mat <- counts_out$effort_mat
    if (noise$missing_years_prob > 0) {
      year_keep <- stats::runif(length(years_seq)) >= noise$missing_years_prob
      counts_mat[, !year_keep] <- 0
      effort_mat[, !year_keep] <- 0
    }
    tx_map <- exdyn_tx_map_counts(
      counts_mat = counts_mat,
      years = range(years_seq),
      cfg = tx_cfg,
      grid_info = grid_info,
      effort_mat = effort_mat,
      mask = mask_mat,
    cells_dt = counts_out$cells,
    return_counts = isTRUE(noise$keep_counts)
  )
  }
  if (noise$random_tx_dropout > 0 && nrow(tx_map$table)) {
    drop_mask <- stats::runif(nrow(tx_map$table)) < noise$random_tx_dropout
    if (any(drop_mask)) {
      drop_cells <- tx_map$table$cell_id[drop_mask]
      lookup <- grid_info$lookup
      pos <- lookup[match(drop_cells, lookup$cell_id), c("row_idx", "col_idx")]
      pos <- pos[stats::complete.cases(pos), , drop = FALSE]
      if (nrow(pos)) {
        tx_map$matrix[cbind(pos$row_idx, pos$col_idx)] <- NA_real_
        tx_map$last_presence[cbind(pos$row_idx, pos$col_idx)] <- tx_map$last_presence[cbind(pos$row_idx, pos$col_idx)]
      }
      tx_map$table$tx_obs[drop_mask] <- NA_integer_
    }
  }
  list(
    theta_star = theta,
    noise_cfg = noise,
    years = years_seq,
    T_P = T_P,
    N_true = N_true,
    TX_true = TX_true,
    TX_obs = tx_map$matrix,
    tx_table = tx_map$table,
    tx_counts = tx_map$counts,
    po_points = po_points,
    effort_points = effort_points,
    mask = mask_mat
  )
}

#' @keywords internal
exdyn_prepare_arrivals <- function(arrivals) {
  cols <- intersect(c("arrival_year_smooth", "arrival_year_raw", "arrival_year", "arrival"), names(arrivals))
  if (!length(cols)) {
    return(dplyr::tibble(cell_id = arrivals$cell_id, arrival_year_smooth = NA_real_))
  }
  tibble::as_tibble(arrivals) %>%
    dplyr::mutate(arrival_year = dplyr::coalesce(!!!rlang::syms(cols))) %>%
    dplyr::select(cell_id, arrival_year)
}

#' @keywords internal
exdyn_synthetic_arrival_table <- function(arrivals,
                                          grid_info,
                                          years,
                                          source = "real",
                                          seed = NULL) {
  source <- tolower(source %||% "real")
  source <- match.arg(source, c("real", "synthetic_plane", "synthetic_gradient"))
  years_seq <- if (length(years) == 2L) seq.int(years[1], years[2]) else sort(unique(as.integer(years)))
  if (!is.null(seed)) set.seed(seed)
  if (identical(source, "real")) {
    return(exdyn_prepare_arrivals(arrivals))
  }
  if (identical(source, "synthetic_gradient")) {
    return(exdyn_perf_arrival_table(
      grid_info = grid_info,
      years = years_seq,
      pattern = "gradient",
      noise_sd = 0,
      span_frac = 1,
      seed = seed
    ))
  }
  arrivals_tbl <- exdyn_prepare_arrivals(arrivals)
  lookup <- grid_info$lookup
  df <- dplyr::left_join(lookup, arrivals_tbl, by = "cell_id")
  fit_df <- df[is.finite(df$arrival_year), , drop = FALSE]
  if (nrow(fit_df) < 3) {
    return(exdyn_perf_arrival_table(
      grid_info = grid_info,
      years = years_seq,
      pattern = "gradient",
      noise_sd = 0,
      span_frac = 1,
      seed = seed
    ))
  }
  fit <- stats::lm(arrival_year ~ row_idx + col_idx, data = fit_df)
  pred <- stats::predict(fit, newdata = df)
  pred <- round(pmin(max(years_seq), pmax(min(years_seq), pred)))
  tibble::tibble(cell_id = df$cell_id, arrival_year = pred)
}

#' @keywords internal
exdyn_arrival_coverage_stats <- function(T_P, mask = NULL) {
  stopifnot(length(dim(T_P)) == 2L)
  n_cells <- length(T_P)
  n_finite <- sum(is.finite(T_P))
  frac_finite <- if (n_cells) n_finite / n_cells else NA_real_
  if (is.null(mask)) {
    return(list(
      n_cells = n_cells,
      n_finite = n_finite,
      frac_finite = frac_finite,
      n_mask = n_cells,
      n_finite_mask = n_finite,
      frac_finite_mask = frac_finite
    ))
  }
  mask_use <- as.matrix(mask)
  mask_use[is.na(mask_use)] <- FALSE
  n_mask <- sum(mask_use)
  n_finite_mask <- sum(is.finite(T_P) & mask_use)
  frac_finite_mask <- if (n_mask) n_finite_mask / n_mask else NA_real_
  list(
    n_cells = n_cells,
    n_finite = n_finite,
    frac_finite = frac_finite,
    n_mask = n_mask,
    n_finite_mask = n_finite_mask,
    frac_finite_mask = frac_finite_mask
  )
}

#' @keywords internal
exdyn_viability_sweep <- function(theta_star,
                                  sweep_cfg,
                                  grid_info,
                                  years,
                                  T_P,
                                  mask,
                                  K0 = 120) {
  sweep_cfg <- sweep_cfg %||% list(enabled = FALSE)
  if (!isTRUE(sweep_cfg$enabled)) {
    return(tibble::tibble())
  }
  years_seq <- if (length(years) == 2L) seq.int(years[1], years[2]) else sort(unique(as.integer(years)))
  pred_scale_vals <- sweep_cfg$pred_scale %||% theta_star$pred_scale %||% 1
  pred_c_vals <- sweep_cfg$pred_c %||% theta_star$pred_c %||% 1
  truth_frac_vals <- sweep_cfg$truth_frac %||% theta_star$truth_frac %||% 0.02
  truth_rel0_vals <- sweep_cfg$truth_rel0 %||% theta_star$truth_rel0 %||% 0.5
  seed <- sweep_cfg$seed %||% 1234
  combos <- tidyr::expand_grid(
    pred_scale = pred_scale_vals,
    pred_c = pred_c_vals,
    truth_frac = truth_frac_vals,
    truth_rel0 = truth_rel0_vals
  )
  max_runs <- sweep_cfg$max_runs %||% nrow(combos)
  if (is.finite(max_runs) && max_runs > 0 && nrow(combos) > max_runs) {
    set.seed(seed)
    combos <- combos[sample.int(nrow(combos), size = max_runs), , drop = FALSE]
  }
  cell_km <- grid_info$cell_km %||% 10
  disp_mean_cells <- (theta_star$disp_mean_km %||% 10) / cell_km
  mask_use <- mask %||% grid_info$riparian_matrix %||% matrix(TRUE, nrow = grid_info$nx, ncol = grid_info$ny)
  mask_use <- as.matrix(mask_use)
  mask_use[is.na(mask_use)] <- FALSE

  results <- vector("list", nrow(combos))
  for (i in seq_len(nrow(combos))) {
    set.seed(seed + i)
    pred_scale <- combos$pred_scale[i]
    pred_c <- combos$pred_c[i]
    truth_frac <- combos$truth_frac[i]
    truth_rel0 <- combos$truth_rel0[i]
    pars <- list(
      rmax = theta_star$rmax %||% 0.4,
      A_frac = (theta_star$A_over_K %||% 0.1) * K0,
      beta_H = 0,
      d = 0.02
    )
    TX_idx <- exdyn_simulate_tx_only(
      grid_info = grid_info,
      years = years_seq,
      T_P = T_P,
      ramp_years = theta_star$ramp_years %||% 8,
      pars = pars,
      K0 = K0,
      alpha = theta_star$alpha %||% 0.2,
      disp_mean_cells = disp_mean_cells,
      pred = list(
        type = theta_star$pred_type %||% "II",
        c = pred_c,
        h = theta_star$pred_h %||% 30,
        scale = pred_scale,
        gamma = theta_star$gamma %||% 1
      ),
      pre_leak = theta_star$pre_leak %||% 0,
      mask = mask_use,
      crop = sweep_cfg$crop %||% FALSE,
      frac = truth_frac,
      rel0 = truth_rel0
    )
    TX_true <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    idx <- is.finite(TX_idx)
    if (any(idx)) {
      TX_true[idx] <- years_seq[TX_idx[idx]]
    }
    TX_true[!mask_use] <- NA_real_
    counts <- exdyn_summary_counts(TX_true, T_P, mask = mask_use)
    n_pairs <- counts[["n_pairs"]]
    n_TP_finite <- counts[["n_TP_finite"]]
    coverage_true <- if (n_TP_finite > 0) n_pairs / n_TP_finite else NA_real_
    tx_vals <- TX_true[is.finite(TX_true) & is.finite(T_P) & mask_use]
    lag_vals <- tx_vals - T_P[is.finite(TX_true) & is.finite(T_P) & mask_use]
    tx_range <- if (length(tx_vals) >= 2) max(tx_vals) - min(tx_vals) else NA_real_
    results[[i]] <- tibble::tibble(
      pred_scale = pred_scale,
      pred_c = pred_c,
      truth_frac = truth_frac,
      truth_rel0 = truth_rel0,
      n_pairs = n_pairs,
      n_TP_finite = n_TP_finite,
      n_TX_true = counts[["n_TX_finite"]],
      coverage_true = coverage_true,
      tx_sd = if (length(tx_vals) >= 2) stats::sd(tx_vals) else NA_real_,
      tx_range = tx_range,
      lag_mean = if (length(lag_vals)) mean(lag_vals) else NA_real_
    )
  }
  dplyr::bind_rows(results)
}

#' @keywords internal
exdyn_synthetic_po_points <- function(N, years_seq, grid_info, rate, effort_strength) {
  N_clean <- N
  N_clean[!is.finite(N_clean)] <- 0
  N_clean <- pmax(N_clean, 0)
  po_raw <- exdyn_presence_only(N_clean, rate = rate, effort_strength = effort_strength)
  if (!nrow(po_raw)) {
    return(tibble::tibble(cell_id = integer(), row = integer(), col = integer(), year = integer()))
  }
  nx <- grid_info$nx
  ny <- grid_info$ny
  cell_mat <- matrix(NA_integer_, nrow = nx, ncol = ny)
  row_mat <- matrix(NA_integer_, nrow = nx, ncol = ny)
  col_mat <- matrix(NA_integer_, nrow = nx, ncol = ny)
  lookup <- grid_info$lookup
  cell_mat[cbind(lookup$row_idx, lookup$col_idx)] <- lookup$cell_id
  row_mat[cbind(lookup$row_idx, lookup$col_idx)] <- lookup$row
  col_mat[cbind(lookup$row_idx, lookup$col_idx)] <- lookup$col
  idx <- cbind(po_raw$x, po_raw$y)
  cell_id <- cell_mat[idx]
  keep <- !is.na(cell_id)
  if (!any(keep)) {
    return(tibble::tibble(cell_id = integer(), row = integer(), col = integer(), year = integer()))
  }
  tibble::tibble(
    cell_id = cell_id[keep],
    row = row_mat[idx][keep],
    col = col_mat[idx][keep],
    year = years_seq[po_raw$t[keep]]
  )
}
