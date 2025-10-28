#' Grid construction and arrival-time derivation
#'
#' Utilities to build a country grid, place occurrences into cells, and compute
#' arrival years with neighbourhood-based smoothing and QC summaries.
#'
#' @name grid_and_arrival
NULL

#' Build an equal-sized grid over a country polygon
#'
#' @param country_code ISO3 code (e.g. \code{"GB"}).
#' @param cell_km Cell size in kilometres.
#' @param crs_out Output CRS (default EPSG:27700 for GB).
#'
#' @return An \code{sf} object with columns \code{cell_id,row,col,centroid_x,centroid_y}.
#' @export
exdyn_make_grid <- function(country_code = "GB", cell_km = 10, crs_out = "EPSG:27700") {
  cntry <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") %>%
    dplyr::filter(.data$adm0_a3 == country_code | .data$iso_a2 == country_code)
  if (!nrow(cntry)) stop("No country polygon found for code: ", country_code)

  cntry <- sf::st_transform(cntry, crs = crs_out)
  cell_m <- cell_km * 1000
  grid_geom <- sf::st_make_grid(cntry, cellsize = cell_m, square = TRUE, what = "polygons")

  cent_full <- sf::st_centroid(sf::st_sf(geometry = grid_geom))
  coords_full <- sf::st_coordinates(cent_full)
  x_levels <- sort(unique(round(coords_full[, 1], 6)))
  y_levels <- sort(unique(round(coords_full[, 2], 6)))

  grid_sf <- sf::st_sf(
    cell_id = seq_along(grid_geom),
    geometry = grid_geom
  )

  grid_sf$cell_km <- cell_km

  grid_sf$col <- match(round(coords_full[, 1], 6), x_levels)
  row_match <- match(round(coords_full[, 2], 6), y_levels)
  grid_sf$row <- length(y_levels) - row_match + 1

  grid_sf <- sf::st_filter(grid_sf, cntry)
  grid_sf$geometry <- sf::st_intersection(grid_sf$geometry, sf::st_geometry(cntry))
  grid_sf <- grid_sf[!sf::st_is_empty(grid_sf), ]
  cent <- sf::st_centroid(grid_sf)
  coords <- sf::st_coordinates(cent)
  grid_sf$centroid_x <- coords[, 1]
  grid_sf$centroid_y <- coords[, 2]
  grid_sf
}

#' Assign occurrences to grid cells
#'
#' @param df_pts Tibble with columns \code{lon, lat, year}.
#' @param grid_sf Grid produced by \code{exdyn_make_grid()}.
#' @param crs_in CRS of the incoming coordinates (default WGS84).
#'
#' @return Tibble with columns \code{cell_id,row,col,year}.
#' @export
exdyn_points_to_grid <- function(df_pts, grid_sf, crs_in = "EPSG:4326") {
  if (!nrow(df_pts)) return(tibble::tibble())
  pts <- sf::st_as_sf(df_pts, coords = c("lon", "lat"), crs = crs_in)
  pts <- sf::st_transform(pts, sf::st_crs(grid_sf))
  joined <- sf::st_join(
    pts,
    grid_sf[, c("cell_id", "row", "col")],
    join = sf::st_within,
    left = FALSE
  )
  if (!nrow(joined)) return(tibble::tibble())
  joined <- sf::st_drop_geometry(joined)
  tibble::tibble(
    cell_id = joined$cell_id,
    row = joined$row,
    col = joined$col,
    year = joined$year
  )
}

# Internal helper to build adjacency list -------------------------------------
.build_adjacency <- function(meta, radius) {
  if (radius <= 0) {
    return(setNames(vector("list", nrow(meta)), meta$cell_id))
  }
  purrr::map2(meta$row, meta$col, function(r, c) {
    idx <- which(abs(meta$row - r) + abs(meta$col - c) <= radius &
                   !(meta$row == r & meta$col == c))
    meta$cell_id[idx]
  }) %>%
    stats::setNames(meta$cell_id)
}

#' Derive arrival years for each grid cell
#'
#' @param cells_df Tibble with columns \code{cell_id,row,col,year}.
#' @param years Length-2 vector (min, max year).
#' @param params List with keys matching \code{config/realdata.yaml$arrival}.
#'
#' @return Tibble with columns \code{cell_id,row,col,arrival_year_raw}.
#' @export
exdyn_arrival_from_cells <- function(cells_df, years, params) {
  if (!nrow(cells_df)) {
    return(tibble::tibble(cell_id = integer(), row = integer(), col = integer(), arrival_year_raw = integer()))
  }
  yr_min <- years[1]; yr_max <- years[2]
  window <- params$window_years %||% 5
  min_events <- params$min_events_cell %||% 2
  neigh_radius <- params$neigh_radius_cells %||% 1
  min_support <- params$min_support_neigh %||% 3
  outlier_gap <- params$outlier_iso_years %||% 8

  counts <- cells_df %>%
    dplyr::group_by(cell_id, row, col, year) %>%
    dplyr::summarise(n_events = dplyr::n(), .groups = "drop_last") %>%
    dplyr::group_by(cell_id, row, col) %>%
    tidyr::complete(year = seq(yr_min, yr_max), fill = list(n_events = 0)) %>%
    dplyr::ungroup()

  meta <- counts %>% dplyr::distinct(cell_id, row, col)
  adjacency <- .build_adjacency(meta, neigh_radius)
  counts_split <- split(counts, counts$cell_id)

  compute_arrival <- function(cell_id, row, col) {
    cell_counts <- counts_split[[as.character(cell_id)]]
    if (is.null(cell_counts)) return(NA_integer_)
    neigh_ids <- adjacency[[as.character(cell_id)]]
    neigh_counts <- if (length(neigh_ids)) {
      purrr::map_dfr(neigh_ids, ~ counts_split[[as.character(.x)]], .id = NULL)
    } else {
      tibble::tibble(cell_id = integer(), year = integer(), n_events = integer())
    }
    event_years <- cell_counts$year[cell_counts$n_events > 0]
    if (!length(event_years)) {
      return(NA_integer_)
    }
    candidate <- NA_integer_
    for (y in sort(unique(event_years))) {
      y_max <- min(y + window, yr_max)
      cell_support <- sum(cell_counts$n_events[cell_counts$year >= y & cell_counts$year <= y_max], na.rm = TRUE)
      neigh_support <- if (nrow(neigh_counts)) {
        sum(neigh_counts$n_events[neigh_counts$year >= y & neigh_counts$year <= y_max], na.rm = TRUE)
      } else {
        0
      }
      if (cell_support >= min_events || neigh_support >= min_support) {
        candidate <- y
        break
      }
    }
    if (is.na(candidate)) {
      return(NA_integer_)
    }
    if (!nrow(neigh_counts)) {
      return(candidate)
    }
    earliest_neigh <- min(neigh_counts$year[neigh_counts$n_events > 0], na.rm = TRUE)
    if (is.finite(earliest_neigh) && earliest_neigh - candidate <= outlier_gap) {
      candidate
    } else {
      NA_integer_
    }
  }

  arrivals <- meta %>%
    dplyr::mutate(
      arrival_year_raw = purrr::pmap_int(
        list(cell_id = .data$cell_id, row = .data$row, col = .data$col),
        compute_arrival
      )
    )

  arrivals
}

#' Smooth arrival years spatially
#'
#' @param arrivals Tibble from \code{exdyn_arrival_from_cells()}.
#' @param grid_sf Grid with row/col information.
#'
#' @return Tibble with \code{cell_id,arrival_year_raw,arrival_year_smooth}.
#' @export
exdyn_arrival_smooth <- function(arrivals, grid_sf) {
  grid_meta <- grid_sf %>%
    sf::st_drop_geometry() %>%
    dplyr::select(cell_id, row, col)
  df <- grid_meta %>%
    dplyr::left_join(arrivals, by = c("cell_id", "row", "col"))
  adjacency <- .build_adjacency(grid_meta, radius = 1)
  df$arrival_year_smooth <- df$arrival_year_raw

  for (iter in seq_len(3)) {
    missing_idx <- which(is.na(df$arrival_year_smooth))
    if (!length(missing_idx)) break
    updated <- FALSE
    for (i in missing_idx) {
      neigh_ids <- adjacency[[as.character(df$cell_id[i])]]
      if (!length(neigh_ids)) next
      neigh_vals <- df$arrival_year_smooth[df$cell_id %in% neigh_ids]
      neigh_vals <- neigh_vals[is.finite(neigh_vals)]
      if (length(neigh_vals) >= 2) {
        df$arrival_year_smooth[i] <- max(neigh_vals) + 1
        updated <- TRUE
      }
    }
    if (!updated) break
  }

  df %>%
    dplyr::select(cell_id, arrival_year_raw, arrival_year_smooth)
}

#' Summaries for arrival QC
#'
#' @param arrivals Tibble with raw/smoothed arrivals.
#' @param years Range of years (length two).
#'
#' @return Named list with QC statistics.
#' @export
exdyn_arrival_qc <- function(arrivals, years) {
  total_cells <- nrow(arrivals)
  coverage <- if (total_cells) {
    mean(!is.na(arrivals$arrival_year_smooth))
  } else 0
  valid <- arrivals$arrival_year_smooth
  stats <- valid[is.finite(valid)]
  list(
    total_cells = total_cells,
    coverage = coverage,
    earliest = if (length(stats)) min(stats) else NA_real_,
    median = if (length(stats)) stats::median(stats) else NA_real_,
    latest = if (length(stats)) max(stats) else NA_real_,
    early_fraction = if (length(stats)) {
      mean(stats < (years[1] + 5))
    } else NA_real_
  )
}
