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
    sf::st_drop_geometry() %>%
    dplyr::select(cell_id, row, col)
  meta <- meta %>% dplyr::filter(!is.na(row), !is.na(col))
  row_levels <- sort(unique(meta$row))
  col_levels <- sort(unique(meta$col))
  meta$row_idx <- match(meta$row, row_levels)
  meta$col_idx <- match(meta$col, col_levels)
  list(
    lookup = meta,
    row_levels = row_levels,
    col_levels = col_levels,
    nx = length(row_levels),
    ny = length(col_levels)
  )
}

#' Predation array from arrival years
#'
#' @param arrivals Tibble with \code{cell_id} and arrival year column (raw/smooth).
#' @param grid_info Output of \code{exdyn_grid_lookup()}.
#' @param years Vector of simulation years (ascending).
#' @param ramp_years Number of years to ramp from 0.2 to 1.0 after arrival.
#' @param pre_leak Pre-arrival baseline (default 0).
#'
#' @return List with elements \code{P} (array), \code{T_P} (matrix).
#' @export
exdyn_P_from_arrival <- function(arrivals, grid_info, years, ramp_years, pre_leak = 0) {
  stopifnot(!is.null(grid_info))
  ramp_years <- max(1, ramp_years)
  k <- 6 / ramp_years
  T_len <- length(years)
  P_arr <- array(pre_leak, dim = c(grid_info$nx, grid_info$ny, T_len))
  T_P <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)

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
    T_P[r, c] <- arr
    diffs <- years - arr
    logistic_component <- 1 / (1 + exp(-k * (diffs - ramp_years / 2)))
    ramp_vals <- 0.2 + 0.8 * logistic_component
    ramp_vals[diffs < 0] <- pre_leak
    ramp_vals <- pmax(pre_leak, pmin(1, ramp_vals))
    P_arr[r, c, ] <- ramp_vals
  }
  list(P = P_arr, T_P = T_P, years = years, grid_info = grid_info)
}

#' Construct simulation fields from mink arrivals
#'
#' @param arrivals Tibble with mink arrival years.
#' @param grid_info Grid lookup.
#' @param years Simulation years.
#' @param ramp_years Ramp duration.
#' @param pre_leak Pre-arrival predation level.
#'
#' @return List with \code{S}, \code{P}, \code{H}, \code{T_P}, \code{grid_info}, \code{years}.
#' @export
exdyn_fields_from_mink <- function(arrivals, grid_info, years, ramp_years, pre_leak = 0) {
  P_info <- exdyn_P_from_arrival(arrivals, grid_info, years, ramp_years, pre_leak)
  nx <- grid_info$nx; ny <- grid_info$ny; T_len <- length(years)
  S <- array(1, dim = c(nx, ny, T_len))
  H <- array(0, dim = c(nx, ny, T_len))
  list(
    S = S,
    P = P_info$P,
    H = H,
    T_P = P_info$T_P,
    grid_info = grid_info,
    years = years
  )
}
