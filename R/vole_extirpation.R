#' Vole extirpation utilities
#'
#' Helpers to derive per-cell response-only extirpation years from
#' presence-only occurrence counts.
#'
#' @name vole_extirpation
NULL

#' Build per-cell annual time series of occurrence counts
#'
#' @param cells_df Tibble with columns \code{cell_id,row,col,year}.
#' @param years Integer vector of length 2 giving min/max year.
#' @param grid_info Optional lookup as returned by \code{exdyn_grid_lookup()}.
#' @param effort_cells Optional tibble of effort occurrences with
#'   \code{cell_id,row,col,year} columns for normalisation.
#'
#' @return Tibble with columns \code{cell_id,row,col,year,n_obs,n_mammal,norm_mammal,row_idx,col_idx}.
#' @export
exdyn_cell_timeseries <- function(cells_df, years, grid_info = NULL, effort_cells = NULL) {
  if (!nrow(cells_df)) {
    return(tibble::tibble(
      cell_id = integer(),
      row = integer(),
      col = integer(),
      year = integer(),
      n_obs = integer(),
      n_mammal = integer(),
      norm_mammal = numeric(),
      row_idx = integer(),
      col_idx = integer()
    ))
  }
  yrs <- seq.int(years[1], years[2])
  counts <- cells_df %>%
    dplyr::mutate(year = as.integer(year)) %>%
    dplyr::count(cell_id, row, col, year, name = "n_obs") %>%
    dplyr::group_by(cell_id, row, col) %>%
    tidyr::complete(year = yrs, fill = list(n_obs = 0L)) %>%
    dplyr::ungroup()

  if (!is.null(effort_cells) && nrow(effort_cells)) {
    effort_counts <- effort_cells %>%
      dplyr::mutate(year = as.integer(year)) %>%
      dplyr::count(cell_id, row, col, year, name = "n_mammal") %>%
      dplyr::group_by(cell_id, row, col) %>%
      tidyr::complete(year = yrs, fill = list(n_mammal = 0L)) %>%
      dplyr::ungroup()
    counts <- counts %>%
      dplyr::left_join(effort_counts, by = c("cell_id", "row", "col", "year")) %>%
      dplyr::mutate(
        n_mammal = dplyr::coalesce(.data$n_mammal, 0L),
        norm_mammal = dplyr::if_else(
          .data$n_mammal > 0L,
          .data$n_obs / pmax(1, .data$n_mammal),
          as.numeric(.data$n_obs)
        )
      )
  } else {
    counts <- counts %>%
      dplyr::mutate(
        n_mammal = 0L,
        norm_mammal = as.numeric(.data$n_obs)
      )
  }
  if (!is.null(grid_info)) {
    counts <- counts %>%
      dplyr::mutate(
        row_idx = match(.data$row, grid_info$row_levels),
        col_idx = match(.data$col, grid_info$col_levels)
      )
  } else {
    counts <- counts %>%
      dplyr::mutate(
        row_idx = NA_integer_,
        col_idx = NA_integer_
      )
  }
  if (nrow(counts) > 5L * dplyr::n_distinct(counts$cell_id) * length(yrs)) {
    warning("exdyn_cell_timeseries: unusually large table; check grouping logic.", call. = FALSE)
  }
  counts
}

#' Centred moving average smoother
#'
#' @param counts Numeric vector.
#' @param k Window size (odd integer preferred).
#'
#' @return Numeric vector of same length.
#' @export
exdyn_ts_smooth <- function(counts, k = 5) {
  if (length(counts) == 0) return(counts)
  k <- max(1L, as.integer(k))
  if (k == 1L) return(counts)
  zoo::rollapply(
    data = counts,
    width = k,
    FUN = mean,
    fill = NA_real_,
    align = "center",
    partial = TRUE
  )
}

# Internal helper -------------------------------------------------------------
.exdyn_resolve_threshold_mode <- function(cfg, normalize_by = NULL) {
  requested <- cfg$threshold_mode %||% "auto"
  requested <- match.arg(requested, c("auto", "count_floor", "relative_baseline"))
  norm_mode <- if (is.null(normalize_by)) "none" else match.arg(normalize_by, c("none", "mammal", "taxa"))
  if (identical(requested, "auto")) {
    if (identical(norm_mode, "none")) "count_floor" else "relative_baseline"
  } else {
    requested
  }
}

.exdyn_threshold_tau <- function(baseline, cfg, threshold_mode) {
  threshold_mode <- match.arg(threshold_mode, c("count_floor", "relative_baseline"))
  raw_tau <- (cfg$drop_fraction %||% 0) * baseline
  if (identical(threshold_mode, "count_floor")) {
    return(max(1, floor(raw_tau)))
  }
  raw_tau
}

.exdyn_first_passage_hold <- function(smooth_vals, years, cfg, normalize_by = NULL) {
  threshold_mode <- .exdyn_resolve_threshold_mode(cfg, normalize_by = normalize_by)
  detections <- which(smooth_vals > 0 & is.finite(smooth_vals))
  if (!length(detections)) {
    return(list(
      tx = NA_integer_,
      last_presence = NA_integer_,
      baseline = NA_real_,
      tau = NA_real_,
      threshold_mode = threshold_mode,
      reason = "no_records"
    ))
  }
  y0_idx <- detections[1]
  y0 <- years[y0_idx]
  active_years <- length(detections)
  if (active_years < cfg$min_years_active) {
    last_presence <- years[max(detections)]
    return(list(
      tx = NA_integer_,
      last_presence = last_presence,
      baseline = NA_real_,
      tau = NA_real_,
      threshold_mode = threshold_mode,
      reason = "too_few_years"
    ))
  }
  baseline_idx <- which(years >= y0 & years <= y0 + cfg$baseline_window - 1L)
  baseline_idx <- baseline_idx[baseline_idx <= length(smooth_vals)]
  baseline_vals <- smooth_vals[baseline_idx]
  B <- suppressWarnings(stats::median(baseline_vals, na.rm = TRUE))
  if (!is.finite(B) || B <= 0) {
    return(list(
      tx = NA_integer_,
      last_presence = years[max(detections)],
      baseline = B,
      tau = NA_real_,
      threshold_mode = threshold_mode,
      reason = "no_baseline"
    ))
  }
  tau <- .exdyn_threshold_tau(B, cfg, threshold_mode = threshold_mode)
  hold <- max(1L, cfg$hold_years)
  last_presence <- years[max(detections)]
  for (idx in seq_len(length(years))) {
    if (years[idx] <= y0) next
    if (idx + hold - 1 > length(years)) break
    window_vals <- smooth_vals[idx:(idx + hold - 1)]
    if (all(is.finite(window_vals) & window_vals <= tau)) {
      prev_vals <- smooth_vals[seq_len(idx - 1)]
      if (any(is.finite(prev_vals) & prev_vals > tau)) {
        future_start <- idx + hold
        if (future_start <= length(years)) {
          future_vals <- smooth_vals[future_start:length(years)]
          if (any(is.finite(future_vals) & future_vals > tau)) {
            next
          }
        }
        return(list(
          tx = years[idx],
          last_presence = last_presence,
          baseline = B,
          tau = tau,
          threshold_mode = threshold_mode,
          reason = NA_character_
        ))
      }
    }
  }
  list(
    tx = NA_integer_,
    last_presence = last_presence,
    baseline = B,
    tau = tau,
    threshold_mode = threshold_mode,
    reason = "no_hold_crossing"
  )
}

#' Infer observed extirpation years from presence-only counts
#'
#' @param counts_by_cell Output of \code{exdyn_cell_timeseries()} for one cell.
#' @param years Integer vector of length 2.
#' @param cfg List of thresholds (see \code{config/realdata.yaml$pilot$vole}).
#'
#' @return List with elements \code{tx_obs} and \code{last_presence}.
#' @export
exdyn_tx_from_po <- function(counts_by_cell, years, cfg, normalize_by = NULL) {
  yrs <- seq.int(years[1], years[2])
  raw_counts <- counts_by_cell$n_obs
  norm_mode <- if (is.null(normalize_by)) "none" else match.arg(normalize_by, c("none", "mammal", "taxa"))
  series <- raw_counts
  if (norm_mode %in% c("mammal", "taxa")) {
    if ("norm_mammal" %in% names(counts_by_cell)) {
      series <- counts_by_cell$norm_mammal
    } else if ("n_mammal" %in% names(counts_by_cell)) {
      series <- raw_counts / pmax(1, counts_by_cell$n_mammal)
    }
  }
  series[!is.finite(series)] <- 0
  smooth_vals <- exdyn_ts_smooth(series, cfg$smooth_window %||% 5)
  if (!any(is.finite(smooth_vals))) smooth_vals <- series
  res <- .exdyn_first_passage_hold(smooth_vals, yrs, cfg, normalize_by = norm_mode)
  res$series <- series
  res$series_raw <- raw_counts
  res$baseline <- res$baseline %||% NA_real_
  res$tau <- res$tau %||% NA_real_
  res$threshold_mode <- res$threshold_mode %||% .exdyn_resolve_threshold_mode(cfg, normalize_by = norm_mode)
  res$reason <- res$reason %||% NA_character_
  res
}

#' Map extirpation results across all cells
#'
#' @param cells_df Tibble with columns \code{cell_id,row,col,year}.
#' @param years Integer range.
#' @param cfg Vole extirpation configuration.
#' @param grid_info Grid lookup (from \code{exdyn_grid_lookup()}).
#'
#' @param mask Optional logical matrix (same dimensions as grid) specifying
#'   cells to retain (e.g. riparian areas).
#'
#' @return List with \code{table} (tibble), \code{matrix} (tx_obs),
#'   \code{last_presence} (matrix), the supplied \code{grid_info}, and the
#'   per-cell \code{counts}.
#' @export
exdyn_tx_map <- function(cells_df, years, cfg, grid_info,
                         effort_cells = NULL, mask = NULL,
                         fast = TRUE) {
  stopifnot(!is.null(grid_info))
  if (isTRUE(fast)) {
    return(exdyn_tx_map_fast(cells_df, years, cfg, grid_info, effort_cells, mask))
  }
  counts <- exdyn_cell_timeseries(cells_df, years, grid_info, effort_cells)
  if (!nrow(counts)) {
    mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    return(list(
      table = tibble::tibble(
        cell_id = integer(),
        row = integer(),
        col = integer(),
        tx_obs = integer(),
        last_presence = integer(),
        baseline = numeric(),
        tau = numeric(),
        threshold_mode = character(),
        reason = character()
      ),
      matrix = mat,
      last_presence = mat,
      grid_info = grid_info
    ))
  }
  norm_mode <- cfg$normalize_by %||% NULL
  per_cell <- counts %>%
    dplyr::group_by(cell_id, row, col, row_idx, col_idx) %>%
    tidyr::nest(counts = c(year, n_obs, n_mammal, norm_mammal)) %>%
    dplyr::mutate(
      res = purrr::map(counts, ~ exdyn_tx_from_po(.x, years, cfg, normalize_by = norm_mode)),
      tx_obs = purrr::map_int(res, ~ .x$tx %||% NA_integer_),
      last_presence = purrr::map_int(res, ~ .x$last_presence %||% NA_integer_),
      baseline = purrr::map_dbl(res, ~ .x$baseline %||% NA_real_),
      tau = purrr::map_dbl(res, ~ .x$tau %||% NA_real_),
      threshold_mode = purrr::map_chr(res, ~ .x$threshold_mode %||% NA_character_),
      reason = purrr::map_chr(res, ~ .x$reason %||% NA_character_)
    ) %>%
    dplyr::ungroup()

  tx_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  lp_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  valid_idx <- stats::complete.cases(per_cell$row_idx, per_cell$col_idx)
  if (any(valid_idx)) {
    matrix_index <- cbind(per_cell$row_idx[valid_idx], per_cell$col_idx[valid_idx])
    tx_mat[matrix_index] <- per_cell$tx_obs[valid_idx]
    lp_mat[matrix_index] <- per_cell$last_presence[valid_idx]
  }
  if (!is.null(mask)) {
    tx_mat[!mask] <- NA_real_
    lp_mat[!mask] <- NA_real_
  }
  lookup_extra <- grid_info$lookup %>%
    dplyr::select(cell_id, dplyr::any_of(c("river_km", "riparian", "region")))
  per_cell <- per_cell %>%
    dplyr::left_join(lookup_extra, by = "cell_id")

  list(
    table = per_cell %>% dplyr::select(cell_id, row, col, tx_obs, last_presence, baseline, tau, threshold_mode, reason,
                                       dplyr::any_of(c("river_km", "riparian", "region"))),
    matrix = tx_mat,
    last_presence = lp_mat,
    grid_info = grid_info,
    years = years,
    counts = counts
  )
}

#' Map extirpation results from pre-aggregated count matrices
#'
#' @param counts_mat Matrix of counts with dimensions n_cells x n_years,
#'   aligned to \code{grid_info$lookup} row order.
#' @param years Integer range for the time series.
#' @param cfg Vole extirpation configuration.
#' @param grid_info Grid lookup (from \code{exdyn_grid_lookup()}).
#' @param effort_mat Optional matrix of effort counts, same dimensions as
#'   \code{counts_mat}.
#' @param mask Optional logical matrix specifying cells to retain.
#' @param cells_dt Optional lookup table aligned with \code{counts_mat}
#'   containing \code{cell_id,row,col,row_idx,col_idx}.
#' @param return_counts If TRUE, returns a long counts table; otherwise
#'   returns an empty tibble to avoid heavy I/O.
#'
#' @return List with \code{table}, \code{matrix}, \code{last_presence},
#'   \code{grid_info}, \code{years}, and \code{counts}.
#' @export
exdyn_tx_map_counts <- function(counts_mat, years, cfg, grid_info,
                                effort_mat = NULL, mask = NULL,
                                cells_dt = NULL, return_counts = TRUE) {
  stopifnot(!is.null(grid_info), is.matrix(counts_mat))
  years_vec <- seq.int(years[1], years[2])
  n_years <- length(years_vec)
  if (ncol(counts_mat) != n_years) {
    stop("counts_mat columns must match length of years.")
  }
  if (is.null(cells_dt)) {
    cells_dt <- grid_info$lookup %>%
      dplyr::select(cell_id, row, col, row_idx, col_idx)
  }
  n_cells <- nrow(cells_dt)
  cells_dt <- cells_dt %>%
    dplyr::mutate(cell_idx = seq_len(n_cells))
  if (nrow(counts_mat) != n_cells) {
    stop("counts_mat rows must match grid lookup size.")
  }
  series_mat <- counts_mat
  norm_mode <- cfg$normalize_by %||% NULL
  if (!is.null(norm_mode) && norm_mode %in% c("mammal", "taxa") && !is.null(effort_mat)) {
    denom <- pmax(1, effort_mat)
    series_mat <- counts_mat / denom
  }
  tx_obs <- rep(NA_integer_, n_cells)
  last_presence <- rep(NA_integer_, n_cells)
  baseline <- rep(NA_real_, n_cells)
  tau <- rep(NA_real_, n_cells)
  threshold_mode <- rep(NA_character_, n_cells)
  reason <- rep(NA_character_, n_cells)
  for (i in seq_len(n_cells)) {
    series <- series_mat[i, ]
    raw_counts <- counts_mat[i, ]
    series[!is.finite(series)] <- 0
    smooth_vals <- exdyn_ts_smooth(series, cfg$smooth_window %||% 5)
    if (!any(is.finite(smooth_vals))) smooth_vals <- series
    res <- .exdyn_first_passage_hold(smooth_vals, years_vec, cfg, normalize_by = norm_mode)
    tx_obs[i] <- res$tx %||% NA_integer_
    last_presence[i] <- res$last_presence %||% NA_integer_
    baseline[i] <- res$baseline %||% NA_real_
    tau[i] <- res$tau %||% NA_real_
    threshold_mode[i] <- res$threshold_mode %||% NA_character_
    reason[i] <- res$reason %||% NA_character_
  }
  per_cell <- tibble::tibble(
    cell_id = cells_dt$cell_id,
    row = cells_dt$row,
    col = cells_dt$col,
    row_idx = cells_dt$row_idx,
    col_idx = cells_dt$col_idx,
    tx_obs = tx_obs,
    last_presence = last_presence,
    baseline = baseline,
    tau = tau,
    threshold_mode = threshold_mode,
    reason = reason
  )
  tx_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  lp_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  valid_idx <- stats::complete.cases(per_cell$row_idx, per_cell$col_idx)
  if (any(valid_idx)) {
    matrix_index <- cbind(per_cell$row_idx[valid_idx], per_cell$col_idx[valid_idx])
    tx_mat[matrix_index] <- per_cell$tx_obs[valid_idx]
    lp_mat[matrix_index] <- per_cell$last_presence[valid_idx]
  }
  if (!is.null(mask)) {
    tx_mat[!mask] <- NA_real_
    lp_mat[!mask] <- NA_real_
  }
  lookup_extra <- grid_info$lookup %>%
    dplyr::select(cell_id, dplyr::any_of(c("river_km", "riparian", "region")))
  per_cell <- per_cell %>%
    dplyr::left_join(lookup_extra, by = "cell_id")
  counts_tbl <- tibble::tibble()
  if (isTRUE(return_counts)) {
    counts_tbl <- data.table::CJ(cell_idx = seq_len(n_cells), year_idx = seq_len(n_years))
    counts_tbl$n_obs <- as.integer(counts_mat[cbind(counts_tbl$cell_idx, counts_tbl$year_idx)])
    if (!is.null(effort_mat)) {
      counts_tbl$n_mammal <- as.integer(effort_mat[cbind(counts_tbl$cell_idx, counts_tbl$year_idx)])
      counts_tbl$norm_mammal <- ifelse(counts_tbl$n_mammal > 0L,
                                       counts_tbl$n_obs / pmax(1, counts_tbl$n_mammal),
                                       as.numeric(counts_tbl$n_obs))
    } else {
      counts_tbl$n_mammal <- 0L
      counts_tbl$norm_mammal <- as.numeric(counts_tbl$n_obs)
    }
    counts_tbl$year <- years_vec[counts_tbl$year_idx]
    counts_tbl <- merge(counts_tbl, cells_dt[, c("cell_idx", "cell_id", "row", "col")], by = "cell_idx", all.x = TRUE)
    counts_tbl <- counts_tbl %>%
      dplyr::mutate(
        row_idx = match(.data$row, grid_info$row_levels),
        col_idx = match(.data$col, grid_info$col_levels)
      )
    counts_tbl <- tibble::as_tibble(counts_tbl)
  }
  list(
    table = per_cell %>% dplyr::select(cell_id, row, col, tx_obs, last_presence, baseline, tau, threshold_mode, reason,
                                       dplyr::any_of(c("river_km", "riparian", "region"))),
    matrix = tx_mat,
    last_presence = lp_mat,
    grid_info = grid_info,
    years = years,
    counts = counts_tbl
  )
}

#' Fast extirpation map using matrix-based counts
#' @keywords internal
exdyn_tx_map_fast <- function(cells_df, years, cfg, grid_info,
                              effort_cells = NULL, mask = NULL) {
  stopifnot(!is.null(grid_info))
  if (!nrow(cells_df)) {
    mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    return(list(
      table = tibble::tibble(
        cell_id = integer(),
        row = integer(),
        col = integer(),
        tx_obs = integer(),
        last_presence = integer(),
        baseline = numeric(),
        tau = numeric(),
        threshold_mode = character(),
        reason = character()
      ),
      matrix = mat,
      last_presence = mat,
      grid_info = grid_info
    ))
  }
  years_vec <- seq.int(years[1], years[2])
  n_years <- length(years_vec)

  cells_dt <- data.table::as.data.table(cells_df[, c("cell_id", "row", "col"), drop = FALSE])
  cells_dt <- unique(cells_dt)
  cells_dt$cell_idx <- seq_len(nrow(cells_dt))
  n_cells <- nrow(cells_dt)

  dt <- data.table::as.data.table(cells_df)
  dt$year <- as.integer(dt$year)
  dt$cell_idx <- match(dt$cell_id, cells_dt$cell_id)
  dt$year_idx <- match(dt$year, years_vec)
  dt <- dt[!is.na(dt$cell_idx) & !is.na(dt$year_idx), ]
  if (!nrow(dt)) {
    mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    return(list(
      table = tibble::tibble(
        cell_id = integer(),
        row = integer(),
        col = integer(),
        tx_obs = integer(),
        last_presence = integer(),
        baseline = numeric(),
        tau = numeric(),
        threshold_mode = character(),
        reason = character()
      ),
      matrix = mat,
      last_presence = mat,
      grid_info = grid_info
    ))
  }
  idx <- (dt$year_idx - 1L) * n_cells + dt$cell_idx
  counts_vec <- tabulate(idx, nbins = n_cells * n_years)
  counts_mat <- matrix(counts_vec, nrow = n_cells, ncol = n_years, byrow = FALSE)

  effort_mat <- NULL
  if (!is.null(effort_cells) && nrow(effort_cells)) {
    ed <- data.table::as.data.table(effort_cells)
    ed$year <- as.integer(ed$year)
    ed$cell_idx <- match(ed$cell_id, cells_dt$cell_id)
    ed$year_idx <- match(ed$year, years_vec)
    ed <- ed[!is.na(ed$cell_idx) & !is.na(ed$year_idx), ]
    if (nrow(ed)) {
      e_idx <- (ed$year_idx - 1L) * n_cells + ed$cell_idx
      e_vec <- tabulate(e_idx, nbins = n_cells * n_years)
      effort_mat <- matrix(e_vec, nrow = n_cells, ncol = n_years, byrow = FALSE)
    }
  }

  norm_mode <- cfg$normalize_by %||% NULL
  series_mat <- counts_mat
  if (!is.null(norm_mode) && norm_mode %in% c("mammal", "taxa") && !is.null(effort_mat)) {
    denom <- pmax(1, effort_mat)
    series_mat <- counts_mat / denom
  }

  tx_obs <- rep(NA_integer_, n_cells)
  last_presence <- rep(NA_integer_, n_cells)
  baseline <- rep(NA_real_, n_cells)
  tau <- rep(NA_real_, n_cells)
  threshold_mode <- rep(NA_character_, n_cells)
  reason <- rep(NA_character_, n_cells)

  for (i in seq_len(n_cells)) {
    series <- series_mat[i, ]
    raw_counts <- counts_mat[i, ]
    series[!is.finite(series)] <- 0
    smooth_vals <- exdyn_ts_smooth(series, cfg$smooth_window %||% 5)
    if (!any(is.finite(smooth_vals))) smooth_vals <- series
    res <- .exdyn_first_passage_hold(smooth_vals, years_vec, cfg, normalize_by = norm_mode)
    tx_obs[i] <- res$tx %||% NA_integer_
    last_presence[i] <- res$last_presence %||% NA_integer_
    baseline[i] <- res$baseline %||% NA_real_
    tau[i] <- res$tau %||% NA_real_
    threshold_mode[i] <- res$threshold_mode %||% NA_character_
    reason[i] <- res$reason %||% NA_character_
  }

  counts_tbl <- data.table::CJ(cell_idx = seq_len(n_cells), year_idx = seq_len(n_years))
  counts_tbl$n_obs <- as.integer(counts_mat[cbind(counts_tbl$cell_idx, counts_tbl$year_idx)])
  if (!is.null(effort_mat)) {
    counts_tbl$n_mammal <- as.integer(effort_mat[cbind(counts_tbl$cell_idx, counts_tbl$year_idx)])
    counts_tbl$norm_mammal <- ifelse(counts_tbl$n_mammal > 0L,
                                     counts_tbl$n_obs / pmax(1, counts_tbl$n_mammal),
                                     as.numeric(counts_tbl$n_obs))
  } else {
    counts_tbl$n_mammal <- 0L
    counts_tbl$norm_mammal <- as.numeric(counts_tbl$n_obs)
  }
  counts_tbl$year <- years_vec[counts_tbl$year_idx]
  counts_tbl <- merge(counts_tbl, cells_dt[, c("cell_idx", "cell_id", "row", "col"), with = FALSE], by = "cell_idx", all.x = TRUE)
  counts_tbl$row_idx <- match(counts_tbl$row, grid_info$row_levels)
  counts_tbl$col_idx <- match(counts_tbl$col, grid_info$col_levels)

  per_cell <- tibble::tibble(
    cell_id = cells_dt$cell_id,
    row = cells_dt$row,
    col = cells_dt$col,
    row_idx = match(cells_dt$row, grid_info$row_levels),
    col_idx = match(cells_dt$col, grid_info$col_levels),
    tx_obs = tx_obs,
    last_presence = last_presence,
    baseline = baseline,
    tau = tau,
    threshold_mode = threshold_mode,
    reason = reason
  )

  tx_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  lp_mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  valid_idx <- stats::complete.cases(per_cell$row_idx, per_cell$col_idx)
  if (any(valid_idx)) {
    matrix_index <- cbind(per_cell$row_idx[valid_idx], per_cell$col_idx[valid_idx])
    tx_mat[matrix_index] <- per_cell$tx_obs[valid_idx]
    lp_mat[matrix_index] <- per_cell$last_presence[valid_idx]
  }
  if (!is.null(mask)) {
    tx_mat[!mask] <- NA_real_
    lp_mat[!mask] <- NA_real_
  }
  lookup_extra <- grid_info$lookup %>%
    dplyr::select(cell_id, dplyr::any_of(c("river_km", "riparian", "region")))
  per_cell <- per_cell %>%
    dplyr::left_join(lookup_extra, by = "cell_id")

  list(
    table = per_cell %>% dplyr::select(cell_id, row, col, tx_obs, last_presence, baseline, tau, threshold_mode, reason,
                                       dplyr::any_of(c("river_km", "riparian", "region"))),
    matrix = tx_mat,
    last_presence = lp_mat,
    grid_info = grid_info,
    years = years,
    counts = tibble::as_tibble(counts_tbl)
  )
}
