#' Plotting helpers for real data products
#'
#' @name plots_realdata
NULL

#' Arrival map (categorical years)
#'
#' @param grid_sf Grid with geometry and \code{cell_id}.
#' @param arrivals Tibble with arrival years.
#' @param title Plot title.
#'
#' @return ggplot object.
#' @export
exdyn_plot_arrival_map <- function(grid_sf, arrivals, title = "Arrival year") {
  plot_data <- grid_sf %>%
    dplyr::left_join(arrivals, by = "cell_id")
  ggplot2::ggplot(plot_data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = arrival_year_smooth),
      colour = NA
    ) +
    ggplot2::scale_fill_viridis_c(option = "B", na.value = "grey90") +
    ggplot2::labs(fill = "Year", title = title) +
    ggplot2::theme_minimal()
}

#' Occurrence density map
#'
#' @param grid_sf Grid with geometry and \code{cell_id}.
#' @param cells_df Tibble with \code{cell_id} occurrences.
#' @param title Plot title.
#'
#' @return ggplot object.
#' @export
exdyn_occ_density_map <- function(grid_sf, cells_df, title = "Occurrence density") {
  counts <- cells_df %>%
    dplyr::count(cell_id, name = "n_events")
  plot_data <- grid_sf %>%
    dplyr::left_join(counts, by = "cell_id") %>%
    dplyr::mutate(log_events = log10(n_events + 1))
  ggplot2::ggplot(plot_data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = log_events),
      colour = NA
    ) +
    ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey90") +
    ggplot2::labs(fill = "log10(count+1)", title = title) +
    ggplot2::theme_minimal()
}

#' Convert matrix to long tibble for plotting
#'
#' @param mat Matrix (rows = row_levels, cols = col_levels).
#' @param grid_info Grid lookup.
#' @param value_name Column name for value.
#'
#' @return Tibble with columns \code{row,col,value}.
#' @export
exdyn_matrix_to_df <- function(mat, grid_info, value_name = "value") {
  lookup <- grid_info$lookup
  vals <- mat[cbind(lookup$row_idx, lookup$col_idx)]
  df <- tibble::tibble(
    cell_id = grid_info$lookup$cell_id,
    row = lookup$row,
    col = lookup$col,
    !!value_name := vals
  )
  if (all(c("centroid_x", "centroid_y") %in% names(lookup))) {
    df$centroid_x <- lookup$centroid_x
    df$centroid_y <- lookup$centroid_y
  }
  df
}

#' Plot raster-like matrix as ggplot tile
#'
#' @param mat Matrix to visualise.
#' @param grid_info Grid lookup.
#' @param title Plot title.
#' @param fill_label Legend title.
#'
#' @return ggplot object.
#' @export
exdyn_plot_surface <- function(mat, grid_info, title, fill_label = "Year") {
  df <- exdyn_matrix_to_df(mat, grid_info, "value")
  if (all(c("centroid_x", "centroid_y") %in% names(df))) {
    cell_km <- grid_info$cell_km %||% NA_real_
    cell_m <- if (is.finite(cell_km)) cell_km * 1000 else NA_real_
    if (!is.finite(cell_m)) {
      dx <- diff(sort(unique(df$centroid_x)))
      dy <- diff(sort(unique(df$centroid_y)))
      cell_m <- stats::median(c(dx[dx > 0], dy[dy > 0]), na.rm = TRUE)
    }
    if (!is.finite(cell_m)) cell_m <- 1
    ggplot2::ggplot(df, ggplot2::aes(x = centroid_x, y = centroid_y, fill = value)) +
      ggplot2::geom_tile(color = NA, width = cell_m, height = cell_m) +
      ggplot2::scale_fill_viridis_c(option = "magma", na.value = "grey90") +
      ggplot2::coord_equal() +
      ggplot2::labs(title = title, fill = fill_label, x = "Easting", y = "Northing") +
      ggplot2::theme_minimal()
  } else {
    ggplot2::ggplot(df, ggplot2::aes(x = col, y = row, fill = value)) +
      ggplot2::geom_tile(color = NA) +
      ggplot2::scale_y_reverse() +
      ggplot2::scale_fill_viridis_c(option = "magma", na.value = "grey90") +
      ggplot2::coord_equal() +
      ggplot2::labs(title = title, fill = fill_label, x = "Column", y = "Row") +
      ggplot2::theme_minimal()
  }
}

#' Scatter plot of observed vs predator arrival times
#'
#' @param TX_obs Matrix of observed extirpations.
#' @param T_P Matrix of predator arrival times.
#'
#' @return ggplot object.
#' @export
exdyn_plot_tx_scatter <- function(TX_obs, T_P) {
  idx <- which(is.finite(TX_obs) & is.finite(T_P))
  df <- tibble::tibble(
    T_P = T_P[idx],
    T_X = TX_obs[idx]
  )
  if (!nrow(df)) {
    return(ggplot2::ggplot() + ggplot2::labs(title = "No overlapping cells"))
  }
  fit <- tryCatch(stats::lm(T_X ~ T_P, data = df), error = function(...) NULL)
  r2 <- if (!is.null(fit)) round(summary(fit)$r.squared, 3) else NA_real_
  lag <- if (nrow(df)) round(mean(df$T_X - df$T_P), 2) else NA_real_
  ggplot2::ggplot(df, ggplot2::aes(x = T_P, y = T_X)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, colour = "grey70", linetype = "dashed") +
    ggplot2::geom_point(alpha = 0.3, size = 1.2) +
    ggplot2::labs(
      title = "Observed vole extirpation vs mink arrival",
      subtitle = sprintf("r² = %s, mean lag = %s yrs", r2, lag),
      x = "Mink arrival year",
      y = "Observed vole extirpation year"
    ) +
    ggplot2::theme_minimal()
}

#' Write diagnostic PNGs for top parameter sets
#'
#' @param tx_obs_mat Observed extirpation matrix.
#' @param tx_sources Optional list of simulated matrices or character vector of
#'   file paths (one per row of \code{scores}). When omitted, the function will
#'   look for a \code{tx_path} column in \code{scores}.
#' @param scores Ranked tibble with `rank` column.
#' @param grid_info Grid lookup.
#' @param out_dir Output directory.
#' @param top_k Number of best simulations to export.
#'
#' @return Vector of written file paths.
#' @export
exdyn_write_best_maps <- function(tx_obs_mat, tx_sources = NULL, scores, grid_info, out_dir, top_k = 3) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- c()
  obs_plot <- exdyn_plot_surface(tx_obs_mat, grid_info, "Observed vole extirpation (TX_obs)")
  obs_path <- file.path(out_dir, "TX_obs_riparian_map.png")
  ggplot2::ggsave(obs_path, obs_plot, width = 7, height = 7, dpi = 150)
  paths <- c(paths, obs_path)
  top_ids <- scores %>% dplyr::arrange(loss) %>% dplyr::slice_head(n = top_k)
  for (i in seq_len(nrow(top_ids))) {
    rank_i <- top_ids$rank[i]
    idx <- which(scores$rank == rank_i)
    if (!length(idx)) next
    mat <- NULL
    if (!is.null(tx_sources)) {
      if (is.character(tx_sources)) {
        candidate <- tx_sources[idx]
        if (length(candidate) && !is.na(candidate) && file.exists(candidate)) {
          mat <- readRDS(candidate)
        }
      } else if (is.list(tx_sources)) {
        mat <- tx_sources[[idx]]
      }
    }
    if (is.null(mat) && "tx_path" %in% names(scores)) {
      candidate <- scores$tx_path[idx]
      if (length(candidate) && !is.na(candidate) && file.exists(candidate)) {
        mat <- readRDS(candidate)
      }
    }
    if (is.null(mat)) next
    sim_plot <- exdyn_plot_surface(mat, grid_info, sprintf("Simulated TX (rank %d)", rank_i))
    path <- file.path(out_dir, sprintf("TX_sim_rank%02d.png", rank_i))
    ggplot2::ggsave(path, sim_plot, width = 7, height = 7, dpi = 150)
    paths <- c(paths, path)
    diff_mat <- tx_obs_mat - mat
    diff_plot <- exdyn_plot_surface(diff_mat, grid_info, sprintf("Observed - simulated TX (rank %d)", rank_i))
    diff_path <- file.path(out_dir, sprintf("TX_diff_rank%02d.png", rank_i))
    ggplot2::ggsave(diff_path, diff_plot, width = 7, height = 7, dpi = 150)
    paths <- c(paths, diff_path)
  }
  paths
}
