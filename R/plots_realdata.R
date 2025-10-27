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
