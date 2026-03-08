#' Riparian mask utilities
#'
#' Helpers to fetch river geometries, aggregate river length per grid cell,
#' and build a riparian mask for habitat-constrained analyses.
#'
#' @name riparian_mask
NULL

#' Fetch river lines from OpenStreetMap
#'
#' @param grid_sf Grid used to derive the bounding box (typically 10 km).
#' @param crs_out CRS string of the desired output.
#' @param min_length_km Minimum line length (in km) to retain after fetching.
#'
#' @return An `sf` object of river polylines transformed to `crs_out`.
#' @export
exdyn_fetch_rivers_osm <- function(grid_sf, crs_out, min_length_km = 0.1) {
  bbox <- sf::st_bbox(sf::st_transform(grid_sf, 4326))
  query <- osmdata::opq(bbox = bbox) |>
    osmdata::add_osm_feature(
      key = "waterway",
      value = c("river", "stream", "canal")
    )
  osm <- osmdata::osmdata_sf(query)
  rivers <- dplyr::bind_rows(
    osm$osm_lines,
    osm$osm_multilines
  )
  if (is.null(rivers) || !nrow(rivers)) {
    stop("No river features returned from OSM for supplied extent.")
  }
  rivers <- sf::st_transform(rivers, crs_out)
  rivers$length_km <- units::set_units(sf::st_length(rivers), "km")
  rivers <- rivers[suppressWarnings(as.numeric(rivers$length_km)) >= min_length_km, ]
  if (!nrow(rivers)) {
    stop("All OSM river segments were shorter than threshold.")
  }
  sf::st_make_valid(rivers)
}

#' Fetch river lines from Natural Earth as a fallback
#'
#' @param country_code ISO2/ISO3 code or vector (default `"GB"`).
#' @param crs_out CRS string of the desired output.
#'
#' @return An `sf` object of river centerlines.
#' @export
exdyn_fetch_rivers_ne <- function(country_code = "GB", crs_out = "EPSG:27700") {
  country_code <- unique(country_code)
  rivers <- rnaturalearth::ne_download(
    type = "rivers_lake_centerlines",
    category = "physical",
    scale = 50,
    returnclass = "sf"
  )
  if (!nrow(rivers)) {
    stop("Natural Earth rivers download returned empty result.")
  }
  countries <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf")
  mask <- countries |>
    dplyr::filter(.data$adm0_a3 %in% country_code | .data$iso_a2 %in% country_code)
  if (!nrow(mask)) {
    stop("Could not locate Natural Earth polygon for ", country_code)
  }
  mask <- sf::st_transform(mask, crs_out)
  rivers <- sf::st_transform(rivers, crs_out)
  rivers <- sf::st_intersection(rivers, sf::st_geometry(mask))
  sf::st_make_valid(rivers)
}

#' Aggregate river length per grid cell
#'
#' @param rivers_sf River polylines.
#' @param grid_sf Grid with `cell_id`.
#'
#' @return Tibble with columns `cell_id` and `river_km`.
#' @export
exdyn_river_length_by_cell <- function(rivers_sf, grid_sf) {
  if (!nrow(rivers_sf)) {
    stop("No river geometries supplied.")
  }
  if (!"cell_id" %in% names(grid_sf)) {
    stop("grid_sf must contain column `cell_id`.")
  }
  rivers_sf <- sf::st_transform(rivers_sf, sf::st_crs(grid_sf))
  geom_types <- unique(as.character(sf::st_geometry_type(rivers_sf, by_geometry = TRUE)))
  if (any(geom_types %in% c("GEOMETRYCOLLECTION", "MULTILINESTRING"))) {
    rivers_sf <- sf::st_collection_extract(rivers_sf, "LINESTRING", warn = FALSE)
  }
  inter <- suppressWarnings(suppressMessages(sf::st_intersection(
    rivers_sf,
    grid_sf[, "cell_id"]
  )))
  if (!nrow(inter)) {
    tibble::tibble(cell_id = grid_sf$cell_id, river_km = 0)
  } else {
    inter$river_km <- units::set_units(sf::st_length(inter), "km")
    lengths <- inter |>
      sf::st_set_geometry(NULL) |>
      dplyr::group_by(cell_id) |>
      dplyr::summarise(river_km = sum(as.numeric(.data$river_km), na.rm = TRUE), .groups = "drop")
    dplyr::right_join(
      tibble::tibble(cell_id = grid_sf$cell_id),
      lengths,
      by = "cell_id"
    ) |>
      dplyr::mutate(river_km = dplyr::coalesce(.data$river_km, 0))
  }
}

#' Assign simple macro-regions for timing calibration
#'
#' @param grid_sf Grid with geometry.
#'
#' @return Character vector of region IDs aligned with `grid_sf`.
#' @export
exdyn_assign_region <- function(grid_sf) {
  cent <- sf::st_centroid(sf::st_geometry(grid_sf))
  coords <- sf::st_coordinates(sf::st_transform(cent, 4326))
  lat <- coords[, 2]
  dplyr::case_when(
    lat >= 55 ~ "SCT",
    lat >= 53 ~ "N_ENG",
    TRUE ~ "S_ENG_WAL"
  )
}

#' Build riparian mask with river length per cell
#'
#' @param grid_sf Grid.
#' @param rivers_sf River polylines (already intersecting the extent).
#' @param tau_km Threshold (km) to flag cells as riparian.
#'
#' @return `sf` object with columns `cell_id`, `river_km`, `riparian`, and `region`.
#' @export
exdyn_make_riparian_mask <- function(grid_sf, rivers_sf, tau_km = 5) {
  lengths <- exdyn_river_length_by_cell(rivers_sf, grid_sf)
  regions <- exdyn_assign_region(grid_sf)
  mask <- grid_sf |>
    dplyr::left_join(lengths, by = "cell_id") |>
    dplyr::mutate(
      river_km = dplyr::coalesce(.data$river_km, 0),
      riparian = .data$river_km >= tau_km,
      region = regions
    )
  mask
}

#' Identify connected riparian components
#'
#' Given a logical riparian matrix, derive rook-adjacent connected components
#' and return both the component matrix and a per-cell summary.
#'
#' @param riparian_matrix Logical matrix (nx × ny) marking riparian cells.
#' @param grid_info Optional lookup from [exdyn_grid_lookup()] used to attach
#'   `cell_id` and ancillary attributes.
#'
#' @return List with components matrix (`matrix`), tibble (`table`) containing
#'   `row_idx`, `col_idx`, `comp_id`, `n_cells_comp`, and a component summary
#'   tibble (`summary`).
#' @export
exdyn_riparian_components <- function(riparian_matrix, grid_info = NULL) {
  if (is.null(riparian_matrix)) {
    stop("riparian_matrix must be supplied.")
  }
  mat <- as.matrix(riparian_matrix)
  if (!is.logical(mat)) {
    mat <- mat != 0
  }
  if (!all(dim(mat) >= 1)) {
    stop("riparian_matrix must be at least 1x1.")
  }
  nx <- nrow(mat); ny <- ncol(mat)
  comp_mat <- matrix(0L, nrow = nx, ncol = ny)
  comp_id <- 0L
  dirs <- matrix(c(-1, 0,
                   1, 0,
                   0, -1,
                   0, 1), ncol = 2, byrow = TRUE)
  for (r in seq_len(nx)) {
    for (c in seq_len(ny)) {
      if (!mat[r, c] || comp_mat[r, c] != 0L) next
      comp_id <- comp_id + 1L
      queue_r <- r
      queue_c <- c
      head <- 1L
      tail <- 1L
      comp_mat[r, c] <- comp_id
      while (head <= tail) {
        cr <- queue_r[head]
        cc <- queue_c[head]
        head <- head + 1L
        for (k in seq_len(nrow(dirs))) {
          nr <- cr + dirs[k, 1]
          nc <- cc + dirs[k, 2]
          if (nr < 1L || nr > nx || nc < 1L || nc > ny) next
          if (!mat[nr, nc] || comp_mat[nr, nc] != 0L) next
          comp_mat[nr, nc] <- comp_id
          tail <- tail + 1L
          queue_r[tail] <- nr
          queue_c[tail] <- nc
        }
      }
    }
  }
  if (comp_id == 0L) {
    component_summary <- tibble::tibble(comp_id = integer(), n_cells = integer())
    per_cell <- tibble::tibble(
      row_idx = integer(),
      col_idx = integer(),
      comp_id = integer(),
      n_cells_comp = integer()
    )
    return(list(matrix = comp_mat, table = per_cell, summary = component_summary))
  }
  idx <- which(comp_mat > 0L, arr.ind = TRUE)
  comp_counts <- tabulate(comp_mat[comp_mat > 0L], nbins = comp_id)
  component_summary <- tibble::tibble(
    comp_id = seq_len(comp_id),
    n_cells = as.integer(comp_counts)
  )
  per_cell <- tibble::tibble(
    row_idx = idx[, 1],
    col_idx = idx[, 2],
    comp_id = comp_mat[comp_mat > 0L]
  ) %>%
    dplyr::left_join(component_summary, by = "comp_id") %>%
    dplyr::rename(n_cells_comp = n_cells)
  if (!is.null(grid_info) && "lookup" %in% names(grid_info)) {
    lookup <- grid_info$lookup %>%
      dplyr::select(cell_id, row_idx, col_idx, dplyr::any_of(c("river_km", "riparian", "region", "centroid_x", "centroid_y")))
    per_cell <- per_cell %>%
      dplyr::left_join(lookup, by = c("row_idx", "col_idx"))
  }
list(
  matrix = comp_mat,
  table = per_cell,
  summary = component_summary
)
}

#' Build adjacency between connected components
#'
#' @param comp_matrix Integer matrix of component IDs.
#'
#' @return Tibble of undirected edges (`unit_i`, `unit_j`).
#' @export
exdyn_component_adjacency <- function(comp_matrix) {
  if (is.null(comp_matrix)) {
    return(tibble::tibble(unit_i = character(), unit_j = character()))
  }
  mat <- as.matrix(comp_matrix)
  nx <- nrow(mat); ny <- ncol(mat)
  edges <- list()
  idx <- 0L
  for (r in seq_len(nx)) {
    for (c in seq_len(ny)) {
      id <- mat[r, c]
      if (id <= 0L) next
      if (c < ny) {
        id_right <- mat[r, c + 1L]
        if (id_right > 0L && id_right != id) {
          idx <- idx + 1L
          edges[[idx]] <- c(min(id, id_right), max(id, id_right))
        }
      }
      if (r < nx) {
        id_down <- mat[r + 1L, c]
        if (id_down > 0L && id_down != id) {
          idx <- idx + 1L
          edges[[idx]] <- c(min(id, id_down), max(id, id_down))
        }
      }
    }
  }
  if (!length(edges)) {
    return(tibble::tibble(unit_i = character(), unit_j = character()))
  }
  edge_mat <- do.call(rbind, edges)
  edge_df <- unique(data.frame(unit_i = edge_mat[, 1], unit_j = edge_mat[, 2]))
  tibble::tibble(
    unit_i = as.character(edge_df$unit_i),
    unit_j = as.character(edge_df$unit_j)
  )
}
