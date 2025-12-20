#' Mink arrival to predation field
#'
#' Utilities to convert mink arrival-year rasters into time-varying predation
#' fields for simulation.
#'
#' @name mink_predation_field
NULL

#' Build lookup metadata for a grid
#'
#' @param grid_sf sf object with columns \code{cell_id,row,col}.
#'
#' @return List with entries \code{lookup}, \code{row_levels}, \code{col_levels},
#'   \code{nx}, and \code{ny}.
#' @export
exdyn_grid_lookup <- function(grid_sf) {
  meta <- grid_sf %>%
    sf::st_drop_geometry()
  required_cols <- c("cell_id", "row", "col")
  if (!all(required_cols %in% names(meta))) {
    stop("Grid must contain columns: ", paste(required_cols, collapse = ", "))
  }
  optional_cols <- intersect(c("river_km", "riparian", "region"), names(meta))
  select_cols <- c(required_cols, optional_cols)
  meta <- meta %>%
    dplyr::select(dplyr::all_of(select_cols)) %>%
    dplyr::mutate(
      row = as.integer(round(.data$row)),
      col = as.integer(round(.data$col))
    ) %>%
    dplyr::filter(!is.na(.data$row), !is.na(.data$col))
  row_levels <- sort(unique(meta$row))
  col_levels <- sort(unique(meta$col))
  meta$row_idx <- match(meta$row, row_levels)
  meta$col_idx <- match(meta$col, col_levels)
  cell_km <- if ("cell_km" %in% names(grid_sf)) {
    unique(grid_sf$cell_km)[1]
  } else {
    NA_real_
  }
  extra <- meta %>%
    dplyr::select(dplyr::all_of(c("cell_id", optional_cols)))
  riparian_vec <- if ("riparian" %in% names(extra)) {
    as.logical(extra$riparian)
  } else {
    rep(TRUE, nrow(meta))
  }
  river_vec <- if ("river_km" %in% names(extra)) {
    as.numeric(extra$river_km)
  } else {
    rep(NA_real_, nrow(meta))
  }
  region_vec <- if ("region" %in% names(extra)) {
    as.character(extra$region)
  } else {
    rep(NA_character_, nrow(meta))
  }
  riparian_matrix <- matrix(FALSE, nrow = length(row_levels), ncol = length(col_levels))
  region_matrix <- matrix(NA_character_, nrow = length(row_levels), ncol = length(col_levels))
  idx <- cbind(meta$row_idx, meta$col_idx)
  riparian_matrix[idx] <- riparian_vec
  region_matrix[idx] <- region_vec
  list(
    lookup = meta,
    row_levels = row_levels,
    col_levels = col_levels,
    nx = length(row_levels),
    ny = length(col_levels),
    cell_km = cell_km,
    river_km = setNames(river_vec, meta$cell_id),
    riparian = setNames(riparian_vec, meta$cell_id),
    riparian_matrix = riparian_matrix,
    region = setNames(region_vec, meta$cell_id),
    region_matrix = region_matrix
  )
}

#' Arrival-year matrix from arrivals table
#' @keywords internal
exdyn_arrival_matrix <- function(arrivals, grid_info, years, delta_region = NULL) {
  stopifnot(!is.null(grid_info))
  coalesce_cols <- intersect(
    c("arrival_year_smooth", "arrival_year_raw", "arrival_year", "arrival"),
    names(arrivals)
  )
  if (!length(coalesce_cols)) {
    return(matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny))
  }
  arrivals_tbl <- arrivals %>%
    dplyr::select(cell_id, dplyr::all_of(coalesce_cols)) %>%
    dplyr::mutate(
      arrival_year = dplyr::coalesce(!!!rlang::syms(coalesce_cols), NA_real_)
    ) %>%
    dplyr::select(cell_id, arrival_year)
  lookup <- grid_info$lookup
  mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  idx <- match(lookup$cell_id, arrivals_tbl$cell_id)
  vals <- arrivals_tbl$arrival_year[idx]
  mat[cbind(lookup$row_idx, lookup$col_idx)] <- vals
  if (!is.null(delta_region)) {
    delta_region <- unlist(delta_region)
    if (!length(delta_region)) {
      delta_region <- NULL
    }
  }
  if (!is.null(delta_region)) {
    mat <- exdyn_adjust_arrival_matrix(mat, grid_info, delta_region, years)
  } else {
    min_year <- min(years)
    max_year <- max(years)
    mat <- pmax(min_year, pmin(max_year, mat))
  }
  dim(mat) <- c(grid_info$nx, grid_info$ny)
  mat
}

#' Predation array from arrival years
#'
#' @param arrivals Tibble with \code{cell_id} and arrival year column (raw/smooth).
#' @param grid_info Output of \code{exdyn_grid_lookup()}.
#' @param years Vector of simulation years (ascending).
#' @param ramp_years Number of years to ramp from 0.2 to 1.0 after arrival.
#' @param pre_leak Pre-arrival baseline (default 0).
#' @param scale Post-ramp amplitude multiplier (default 1).
#' @param gamma Shape parameter (>1 steepens the ramp).
#'
#' @return List with elements \code{P} (array), \code{T_P} (matrix).
#' @export
exdyn_P_from_arrival <- function(arrivals, grid_info, years, ramp_years,
                                 pre_leak = 0, scale = 1, gamma = 1,
                                 delta_region = NULL, region_lookup = NULL) {
  stopifnot(!is.null(grid_info))
  ramp_years <- max(1, ramp_years)
  k <- 6 / ramp_years
  T_len <- length(years)
  P_arr <- array(pre_leak, dim = c(grid_info$nx, grid_info$ny, T_len))
  T_P <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  region_matrix <- grid_info[["region_matrix"]] %||% matrix(NA_character_, nrow = grid_info$nx, ncol = grid_info$ny)
  delta_lookup <- delta_region
  if (!is.null(delta_lookup) && is.null(names(delta_lookup))) {
    stop("delta_region must be a named numeric vector.")
  }

  coalesce_cols <- intersect(
    c("arrival_year_smooth", "arrival_year_raw", "arrival_year"),
    names(arrivals)
  )
  arrivals_tbl <- if (length(coalesce_cols)) {
    arrivals %>%
      dplyr::select(cell_id, dplyr::all_of(coalesce_cols)) %>%
      dplyr::mutate(
        arrival_year = dplyr::coalesce(!!!rlang::syms(coalesce_cols), NA_real_)
      ) %>%
      dplyr::select(cell_id, arrival_year)
  } else {
    tibble::tibble(cell_id = arrivals$cell_id, arrival_year = NA_real_)
  }

  for (i in seq_len(nrow(grid_info$lookup))) {
    cell_id <- grid_info$lookup$cell_id[i]
    r <- grid_info$lookup$row_idx[i]
    c <- grid_info$lookup$col_idx[i]
    arr <- arrivals_tbl$arrival_year[arrivals_tbl$cell_id == cell_id]
    if (!length(arr) || is.na(arr)) {
      if (pre_leak == 0) {
        P_arr[r, c, ] <- 0
      }
      next
    }
    arr <- arr[1]
    region_id <- NA_character_
    if (!is.null(region_lookup)) {
      region_id <- region_lookup[[as.character(cell_id)]]
    } else {
      region_id <- region_matrix[r, c]
    }
    delta_val <- 0
    if (!is.null(delta_lookup) && !is.na(region_id) && region_id %in% names(delta_lookup)) {
      delta_val <- delta_lookup[[region_id]]
    }
    arr_adj <- arr - delta_val
    arr_adj <- max(min(years), arr_adj)
    arr_adj <- min(max(years), arr_adj)
    T_P[r, c] <- arr_adj
    diffs <- years - arr_adj
    logistic_component <- 1 / (1 + exp(-k * (diffs - ramp_years / 2)))
    ramp_vals <- 0.2 + 0.8 * logistic_component
    ramp_vals[diffs < 0] <- pre_leak
    ramp_vals <- pmax(pre_leak, pmin(1, ramp_vals))
    ramp_vals <- (ramp_vals ^ gamma) * scale
    P_arr[r, c, ] <- ramp_vals
  }
  valid_cells <- which(is.finite(T_P), arr.ind = TRUE)
  stats_offset <- function(offset, label) {
    if (!nrow(valid_cells)) return(NULL)
    target_years <- T_P[valid_cells] + offset
    idx <- match(target_years, years)
    keep <- which(!is.na(idx))
    if (!length(keep)) return(NULL)
    mat_idx <- cbind(valid_cells[keep, , drop = FALSE], idx[keep])
    vals <- P_arr[mat_idx]
    if (!length(vals)) return(NULL)
    sprintf("%s min=%.3f median=%.3f max=%.3f", label, min(vals), stats::median(vals), max(vals))
  }
  msgs <- c(
    sprintf("[pred_field] scale=%.3f gamma=%.3f", scale, gamma),
    stats_offset(0, "P(arrival)"),
    stats_offset(ramp_years, sprintf("P(arrival+%d)", ramp_years)),
    stats_offset(10, "P(arrival+10)")
  )
  purrr::walk(msgs[!is.na(msgs)], message)
  out <- list(P = P_arr, T_P = T_P, years = years, grid_info = grid_info)
  attr(out, "scale") <- scale
  attr(out, "gamma") <- gamma
  attr(out, "delta_region") <- delta_region
  out
}

#' Construct simulation fields from mink arrivals
#'
#' @param arrivals Tibble with mink arrival years.
#' @param grid_info Grid lookup.
#' @param years Simulation years.
#' @param ramp_years Ramp duration.
#' @param pre_leak Pre-arrival predation level.
#' @param scale Amplitude multiplier applied post-ramp.
#' @param gamma Ramp shape parameter.
#'
#' @return List with \code{S}, \code{P}, \code{H}, \code{T_P}, \code{grid_info}, \code{years}.
#' @export
exdyn_fields_from_mink <- function(arrivals, grid_info, years, ramp_years,
                                   pre_leak = 0, scale = 1, gamma = 1,
                                   delta_region = NULL) {
  P_info <- exdyn_P_from_arrival(
    arrivals = arrivals,
    grid_info = grid_info,
    years = years,
    ramp_years = ramp_years,
    pre_leak = pre_leak,
    scale = scale,
    gamma = gamma,
    delta_region = delta_region,
    region_lookup = grid_info["region"][[1]]
  )
  nx <- grid_info$nx; ny <- grid_info$ny; T_len <- length(years)
  S <- array(1, dim = c(nx, ny, T_len))
  H <- array(0, dim = c(nx, ny, T_len))
  riparian_matrix <- grid_info[["riparian_matrix"]] %||% matrix(TRUE, nrow = nx, ncol = ny)
  if (!is.null(riparian_matrix)) {
    for (tt in seq_len(dim(P_info$P)[3])) {
      slice <- P_info$P[, , tt]
      slice[!riparian_matrix] <- 0
      P_info$P[, , tt] <- slice
    }
    P_info$T_P[!riparian_matrix] <- NA_real_
  }
  list(
    S = S,
    P = P_info$P,
    H = H,
    T_P = P_info$T_P,
    grid_info = grid_info,
    years = years,
    pre_leak = pre_leak,
    scale = scale,
    gamma = gamma,
    delta_region = delta_region
  )
}

#' Adjust arrival matrix by region-specific deltas
#'
#' @param T_P Matrix of arrival years.
#' @param grid_info Output of [exdyn_grid_lookup()].
#' @param delta_region Named numeric vector of delta years per region.
#' @param years Simulation year range.
#'
#' @return Matrix with deltas applied (clamped to minimum year).
#' @export
exdyn_adjust_arrival_matrix <- function(T_P, grid_info, delta_region, years) {
  if (is.null(delta_region)) return(T_P)
  region_matrix <- grid_info[["region_matrix"]] %||% matrix(NA_character_, nrow = nrow(T_P), ncol = ncol(T_P))
  delta_mat <- matrix(0, nrow = nrow(T_P), ncol = ncol(T_P))
  idx <- !is.na(region_matrix) & region_matrix %in% names(delta_region)
  if (any(idx)) {
    delta_mat[idx] <- delta_region[region_matrix[idx]]
  }
  T_adj <- T_P - delta_mat
  T_adj <- pmax(min(years), T_adj)
  T_adj <- pmin(max(years), T_adj)
  T_adj[is.na(T_P)] <- NA
  dim(T_adj) <- dim(T_P)
  T_adj
}
