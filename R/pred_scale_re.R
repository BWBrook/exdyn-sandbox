#' Predation scale random effects utilities
#'
#' @param unit_ids Character vector of unit identifiers.
#' @param sigma Standard deviation of the log-scale random effect.
#' @param seed Optional seed for reproducibility.
#'
#' @return Tibble with columns `unit_id` and `multiplier`.
#' @export
exdyn_sample_pred_scale_re <- function(unit_ids, sigma, seed = NULL) {
  if (!length(unit_ids) || sigma <= 0) {
    return(tibble::tibble(unit_id = unit_ids, multiplier = rep(1, length(unit_ids))))
  }
  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    } else {
      on.exit(rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
  }
  effects <- stats::rnorm(length(unit_ids), mean = 0, sd = sigma)
  tibble::tibble(unit_id = unit_ids, multiplier = exp(effects))
}

#' Build a predation-scale matrix from unit multipliers
#'
#' @param grid_info Lookup from [exdyn_grid_lookup()].
#' @param unit_lookup Tibble with columns `row_idx`, `col_idx`, `unit_id`.
#' @param unit_effects Tibble with columns `unit_id`, `multiplier`.
#'
#' @return Matrix of scale multipliers aligned with the grid.
#' @export
exdyn_scale_matrix_from_units <- function(grid_info, unit_lookup, unit_effects) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  scale_mat <- matrix(1, nrow = nx, ncol = ny)
  if (!nrow(unit_lookup) || !nrow(unit_effects)) {
    return(scale_mat)
  }
  merged <- unit_lookup %>%
    dplyr::left_join(unit_effects, by = "unit_id") %>%
    dplyr::mutate(multiplier = dplyr::coalesce(multiplier, 1))
  idx <- cbind(merged$row_idx, merged$col_idx)
  scale_mat[idx] <- merged$multiplier
  scale_mat
}
