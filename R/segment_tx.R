#' Segment-level extirpation estimates
#'
#' Functions to aggregate riparian cells into connected segments and compute
#' observed extirpation times on those segments.
#'
#' @name segment_tx
NULL

#' Compute extirpation times for riparian segments
#'
#' @param cells_df Vole occurrences (`cell_id`, `row`, `col`, `year`).
#' @param comp_lookup Tibble mapping `cell_id` to `comp_id` and `n_cells_comp`.
#' @param years Integer vector `[start, end]`.
#' @param cfg_base Base configuration list (copied before overrides).
#' @param normalize_by Normalisation mode ("mammal" or `NULL`).
#' @param effort_cells Optional effort dataframe (`cell_id`, `year`).
#'
#' @return Tibble with columns `comp_id`, `tx_obs`, `last_presence`,
#'   `reason`, `baseline`, `tau`, `n_cells`, and `n_years_active`.
#' @export
exdyn_segment_tx <- function(cells_df, comp_lookup, years, cfg_base,
                             normalize_by = "mammal", effort_cells = NULL) {
  if (!nrow(cells_df)) {
    return(tibble::tibble(
      comp_id = integer(),
      tx_obs = integer(),
      last_presence = integer(),
      reason = character(),
      baseline = numeric(),
      tau = numeric(),
      n_cells = integer(),
      n_years_active = integer()
    ))
  }
  required <- c("cell_id", "comp_id", "n_cells_comp")
  if (!all(required %in% names(comp_lookup))) {
    stop("comp_lookup must contain columns: ", paste(required, collapse = ", "))
  }
  cfg <- cfg_base
  cfg$normalize_by <- normalize_by

  counts <- exdyn_cell_timeseries(cells_df, years, grid_info = NULL, effort_cells = effort_cells)
  counts <- counts |>
    dplyr::inner_join(comp_lookup, by = "cell_id")
  if (!nrow(counts)) {
    return(tibble::tibble(
      comp_id = integer(),
      tx_obs = integer(),
      last_presence = integer(),
      reason = character(),
      baseline = numeric(),
      tau = numeric(),
      n_cells = integer(),
      n_years_active = integer()
    ))
  }
  per_segment <- counts |>
    dplyr::group_by(comp_id, year) |>
    dplyr::summarise(
      n_obs = sum(.data$n_obs, na.rm = TRUE),
      n_mammal = sum(.data$n_mammal, na.rm = TRUE),
      .groups = "drop_last"
    ) |>
    dplyr::arrange(year)
  segments <- per_segment |>
    tidyr::nest(data = c(year, n_obs, n_mammal)) |>
    dplyr::mutate(
      res = purrr::map(data, ~ {
        df <- .x
        tib_cell <- tibble::tibble(
          year = df$year,
          n_obs = df$n_obs,
          n_mammal = df$n_mammal,
          norm_mammal = if (normalize_by %in% c("mammal", "taxa")) df$n_obs / pmax(1, df$n_mammal) else df$n_obs
        )
        exdyn_tx_from_po(tib_cell, years, cfg, normalize_by = normalize_by)
      }),
      tx_obs = purrr::map_int(res, ~ .x$tx %||% NA_integer_),
      last_presence = purrr::map_int(res, ~ .x$last_presence %||% NA_integer_),
      reason = purrr::map_chr(res, ~ .x$reason %||% NA_character_),
      baseline = purrr::map_dbl(res, ~ .x$baseline %||% NA_real_),
      tau = purrr::map_dbl(res, ~ .x$tau %||% NA_real_),
      n_years_active = purrr::map_int(data, ~ sum(.x$n_obs > 0, na.rm = TRUE))
    ) |>
    dplyr::left_join(
      comp_lookup |>
        dplyr::distinct(comp_id, n_cells = n_cells_comp),
      by = "comp_id"
    ) |>
    dplyr::select(comp_id, tx_obs, last_presence, reason, baseline, tau, n_cells, n_years_active)
  segments
}
