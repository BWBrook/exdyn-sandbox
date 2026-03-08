#' Extirpation estimator sweeps
#'
#' Helper functions to explore alternative masks, hyper-parameters,
#' and aggregations for the vole extirpation estimator.
#'
#' @name tx_sweep
NULL

#' Build a grid of extirpation hyper-parameters
#'
#' @param baseline_window Vector of baseline windows (years).
#' @param hold_years Vector of hold durations (years).
#' @param drop_fraction Vector of drop fractions.
#'
#' @return Tibble of combinations.
#' @export
exdyn_tx_hyper_grid <- function(baseline_window = c(6, 8, 10),
                                hold_years = c(2, 3, 5),
                                drop_fraction = c(0.2, 0.3, 0.4)) {
  tidyr::expand_grid(
    baseline_window = baseline_window,
    hold_years = hold_years,
    drop_fraction = drop_fraction
  )
}

#' Apply the extirpation estimator with bookkeeping
#'
#' @param cells_df Vole occurrence tibble (`cell_id`, `row`, `col`, `year`).
#' @param years Integer vector `[start, end]`.
#' @param cfg_base Baseline configuration list (copied before overrides).
#' @param grid_info Lookup from [exdyn_grid_lookup()].
#' @param effort_cells Optional effort dataframe for normalisation.
#' @param normalize_by Normalisation mode ("mammal", "taxa", or `NULL`).
#' @param mask Optional logical matrix (nx × ny) restricting cells.
#'
#' @return List with `results` tibble, `funnel` tibble, and the applied config.
#' @export
exdyn_tx_apply_cfg <- function(cells_df, years, cfg_base, grid_info,
                               effort_cells = NULL, normalize_by = "mammal",
                               mask = NULL) {
  stopifnot(!is.null(grid_info))
  cfg <- cfg_base
  cfg$normalize_by <- normalize_by
  cells_any <- length(unique(cells_df$cell_id))
  mask_ids <- grid_info$lookup$cell_id
  empty_results <- tibble::tibble(
    cell_id = integer(),
    row = integer(),
    col = integer(),
    row_idx = integer(),
    col_idx = integer(),
    counts = list(),
    res = list(),
    tx_obs = integer(),
    last_presence = integer(),
    baseline = numeric(),
    tau = numeric(),
    threshold_mode = character(),
    reason = character()
  )
  if (!is.null(mask)) {
    mask_mat <- as.matrix(mask)
    if (!all(dim(mask_mat) == c(grid_info$nx, grid_info$ny))) {
      stop("mask must match grid dimensions.")
    }
    mask_ids <- grid_info$lookup$cell_id[c(mask_mat)]
    cells_df <- cells_df |> dplyr::filter(.data$cell_id %in% mask_ids)
    if (!is.null(effort_cells) && nrow(effort_cells)) {
      effort_cells <- effort_cells |> dplyr::filter(.data$cell_id %in% mask_ids)
    }
  }
  cells_mask <- length(unique(cells_df$cell_id))
  if (!cells_mask) {
    funnel <- tibble::tibble(
      stage = c("any_record", "mask", "min_years_active", "baseline_window", "hold_years", "tx_assigned"),
      n_units = c(cells_any, 0, 0, 0, 0, 0)
    )
    return(list(results = empty_results, funnel = funnel, config = cfg))
  }
  counts <- exdyn_cell_timeseries(cells_df, years, grid_info, effort_cells)
  counts <- counts |> dplyr::filter(.data$cell_id %in% mask_ids)
  per_cell <- counts |>
    dplyr::group_by(cell_id, row, col, row_idx, col_idx) |>
    tidyr::nest(counts = c(year, n_obs, n_mammal, norm_mammal)) |>
    dplyr::mutate(
      res = purrr::map(counts, ~ exdyn_tx_from_po(.x, years, cfg, normalize_by = cfg$normalize_by)),
      tx_obs = purrr::map_int(res, ~ .x$tx %||% NA_integer_),
      last_presence = purrr::map_int(res, ~ .x$last_presence %||% NA_integer_),
      baseline = purrr::map_dbl(res, ~ .x$baseline %||% NA_real_),
      tau = purrr::map_dbl(res, ~ .x$tau %||% NA_real_),
      threshold_mode = purrr::map_chr(res, ~ .x$threshold_mode %||% NA_character_),
      reason = purrr::map_chr(res, ~ .x$reason %||% NA_character_)
    ) |>
    dplyr::ungroup()
  lookup_extra <- grid_info$lookup |>
    dplyr::select(cell_id, dplyr::any_of(c("river_km", "riparian", "region")))
  per_cell <- per_cell |>
    dplyr::left_join(lookup_extra, by = "cell_id")

  reason <- per_cell$reason
  n_min_years <- sum(!(reason %in% c("too_few_years", "no_records")), na.rm = TRUE)
  n_baseline <- sum(!(reason %in% c("too_few_years", "no_records", "no_baseline")), na.rm = TRUE)
  n_hold <- sum(!(reason %in% c("too_few_years", "no_records", "no_baseline", "no_hold_crossing")), na.rm = TRUE)
  n_tx <- sum(is.na(reason))

  funnel <- tibble::tibble(
    stage = c("any_record", "mask", "min_years_active", "baseline_window", "hold_years", "tx_assigned"),
    n_units = c(cells_any, cells_mask, n_min_years, n_baseline, n_hold, n_tx)
  )
  list(results = per_cell, funnel = funnel, config = cfg)
}

#' Summarise funnel statistics across parameter sweeps
#'
#' @param tx_results Tibble with columns `cell_id`, `reason`, and hyper-parameter identifiers.
#'
#' @return Tibble summarising counts per `reason`.
#' @export
exdyn_funnel_summary <- function(tx_results) {
  if (!nrow(tx_results)) {
    return(tibble::tibble())
  }
  tx_results |>
    dplyr::group_by(dplyr::across(-c(cell_id, reason, tx_obs, last_presence, baseline, tau, threshold_mode))) |>
    dplyr::summarise(
      n_total = dplyr::n(),
      n_success = sum(is.na(reason)),
      n_too_few_years = sum(reason == "too_few_years", na.rm = TRUE),
      n_no_baseline = sum(reason == "no_baseline", na.rm = TRUE),
      n_no_hold = sum(reason == "no_hold_crossing", na.rm = TRUE),
      .groups = "drop"
    )
}
