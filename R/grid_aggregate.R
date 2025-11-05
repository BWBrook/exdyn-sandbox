#' Grid aggregation helpers
#'
#' Utilities to coarsen an existing grid to a larger cell size and remap
#' point-based datasets onto the aggregated lattice.
#'
#' @name grid_aggregate
NULL

#' Aggregate an existing grid to a coarser resolution
#'
#' @param grid_sf Grid with columns `cell_id`, `row`, `col`, `centroid_x`,
#'   `centroid_y`, and `cell_km`.
#' @param cell_km_new Desired cell size in kilometres.
#'
#' @return List with entries `grid` (aggregated grid as `sf`) and `mapping_tbl`
#'   (tibble with `cell_id_old`, `cell_id_new`, `row_new`, `col_new`).
#' @export
exdyn_aggregate_grid <- function(grid_sf, cell_km_new) {
  if (!inherits(grid_sf, "sf")) stop("grid_sf must be an sf object.")
  if (!all(c("cell_id", "row", "col") %in% names(grid_sf))) {
    stop("grid_sf must contain columns cell_id, row, col.")
  }
  cell_km_new <- as.numeric(cell_km_new)
  if (!is.finite(cell_km_new) || cell_km_new <= 0) {
    stop("cell_km_new must be positive.")
  }
  cell_m <- cell_km_new * 1000
  cover <- sf::st_union(sf::st_geometry(grid_sf))
  bbox <- sf::st_bbox(grid_sf)
  offset <- c(bbox["xmin"], bbox["ymin"])
  grid_geom <- sf::st_make_grid(
    cover,
    cellsize = cell_m,
    square = TRUE,
    what = "polygons",
    offset = offset
  )
  grid_new <- sf::st_sf(
    cell_id = seq_along(grid_geom),
    geometry = grid_geom
  )
  grid_new$cell_km <- cell_km_new
  grid_new <- sf::st_filter(grid_new, cover)
  grid_new$geometry <- sf::st_intersection(grid_new$geometry, cover)
  grid_new <- grid_new[!sf::st_is_empty(grid_new), ]
  cent <- sf::st_coordinates(sf::st_centroid(grid_new))
  grid_new$centroid_x <- cent[, 1]
  grid_new$centroid_y <- cent[, 2]
  x_levels <- sort(unique(round(grid_new$centroid_x, 6)))
  y_levels <- sort(unique(round(grid_new$centroid_y, 6)))
  grid_new$col <- match(round(grid_new$centroid_x, 6), x_levels)
  row_match <- match(round(grid_new$centroid_y, 6), y_levels)
  grid_new$row <- length(y_levels) - row_match + 1

  old_cent <- sf::st_centroid(grid_sf)
  joined <- suppressMessages(sf::st_join(
    old_cent["cell_id"],
    grid_new["cell_id"],
    join = sf::st_within,
    left = TRUE
  ))
  if (anyNA(joined$cell_id.y)) {
    nearest <- sf::st_nearest_feature(old_cent[is.na(joined$cell_id.y), ], grid_new)
    joined$cell_id.y[is.na(joined$cell_id.y)] <- grid_new$cell_id[nearest]
  }
  mapping <- dplyr::tibble(
    cell_id_old = grid_sf$cell_id,
    cell_id_new = joined$cell_id.y
  ) %>%
    dplyr::left_join(
      sf::st_drop_geometry(grid_new)[, c("cell_id", "row", "col")],
      by = c("cell_id_new" = "cell_id")
    ) %>%
    dplyr::rename(row_new = row, col_new = col)
  if (anyNA(mapping$cell_id_new)) {
    stop("Failed to map some original cells to the aggregated grid.")
  }
  list(grid = grid_new, mapping_tbl = mapping)
}

#' Rebin per-cell records to an aggregated grid
#'
#' @param cells_df Tibble with columns `cell_id`, `row`, `col`, `year`.
#' @param mapping Output of \code{exdyn_aggregate_grid()}$mapping_tbl.
#' @param grid_new Aggregated grid as returned by \code{exdyn_aggregate_grid()}$grid.
#'
#' @return Tibble with columns `cell_id`, `row`, `col`, `year`.
#' @export
exdyn_rebin_cells <- function(cells_df, mapping, grid_new) {
  if (!nrow(cells_df)) return(tibble::tibble())
  required <- c("cell_id_old", "cell_id_new", "row_new", "col_new")
  if (!all(required %in% names(mapping))) {
    stop("mapping must contain columns: ", paste(required, collapse = ", "))
  }
  lookup_new <- sf::st_drop_geometry(grid_new)[, c("cell_id", "row", "col")]
  out <- cells_df %>%
    dplyr::left_join(mapping, by = c("cell_id" = "cell_id_old")) %>%
    dplyr::filter(!is.na(.data$cell_id_new)) %>%
    dplyr::select(
      cell_id = .data$cell_id_new,
      row = .data$row_new,
      col = .data$col_new,
      year
    )
  out <- out %>%
    dplyr::left_join(
      lookup_new,
      by = "cell_id",
      suffix = c("", ".check")
    ) %>%
    dplyr::mutate(
      row = dplyr::coalesce(.data$row.check, .data$row),
      col = dplyr::coalesce(.data$col.check, .data$col)
    ) %>%
    dplyr::select(-dplyr::ends_with(".check"))
  out
}
