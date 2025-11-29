#' Delta regularisation helpers
#'
#' Compute penalties on regional/segment timing deltas using magnitude and
#' total-variation terms.
#'
#' @param delta_values Named numeric vector of delta values.
#' @param adjacency Tibble/data.frame with columns `unit_i`, `unit_j` defining
#'   undirected adjacency edges. May be `NULL` to skip the TV term.
#' @param lambda_mag Weight applied to the mean squared magnitude term.
#' @param lambda_tv Weight applied to the mean absolute difference term.
#'
#' @return Numeric penalty value.
#' @export
exdyn_delta_penalty <- function(delta_values, adjacency = NULL,
                                lambda_mag = 0, lambda_tv = 0) {
  if (is.null(delta_values) || !length(delta_values)) {
    return(0)
  }
  dv <- as.numeric(delta_values)
  dv[!is.finite(dv)] <- 0
  pen_mag <- lambda_mag * mean(dv^2)
  pen_tv <- 0
  if (!is.null(adjacency) && nrow(adjacency) && lambda_tv > 0) {
    edges <- adjacency %>%
      dplyr::mutate(
        unit_i = as.character(.data$unit_i),
        unit_j = as.character(.data$unit_j)
      )
    vals_i <- delta_values[edges$unit_i]
    vals_j <- delta_values[edges$unit_j]
    valid <- is.finite(vals_i) & is.finite(vals_j)
    if (any(valid)) {
      diffs <- abs(vals_i[valid] - vals_j[valid])
      pen_tv <- lambda_tv * mean(diffs)
    }
  }
  pen_mag + pen_tv
}
