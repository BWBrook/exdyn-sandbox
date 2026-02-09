# Coverage break helpers (internal)

exdyn_coverage_breaks <- function(years, n_breaks = 4L) {
  if (length(years) == 2L) {
    years <- seq.int(years[1], years[2])
  }
  years <- sort(unique(as.integer(years)))
  if (length(years) < 2L) {
    return(numeric())
  }
  n_breaks <- max(1L, as.integer(n_breaks))
  brks <- seq(min(years), max(years), length.out = n_breaks + 2L)
  brks[2:(n_breaks + 1L)]
}

#' Coverage breakpoints from extirpation quantiles
#' @keywords internal
exdyn_coverage_breaks_quantile <- function(TX, n_breaks = 4L, years = NULL, min_points = 20L) {
  vals <- TX[is.finite(TX)]
  if (length(vals) < min_points || length(unique(vals)) < 2L) {
    if (!is.null(years)) {
      return(exdyn_coverage_breaks(years, n_breaks = n_breaks))
    }
    return(numeric())
  }
  n_breaks <- max(1L, as.integer(n_breaks))
  probs <- seq(0, 1, length.out = n_breaks + 2L)
  probs <- probs[2:(n_breaks + 1L)]
  brks <- stats::quantile(vals, probs = probs, na.rm = TRUE, names = FALSE, type = 7)
  brks <- unique(as.numeric(brks))
  if (length(brks) < n_breaks) {
    span <- seq(min(vals), max(vals), length.out = n_breaks + 2L)
    brks <- span[2:(n_breaks + 1L)]
  }
  as.numeric(brks)
}

#' Resolve coverage break strategy
#' @keywords internal
exdyn_coverage_breaks_resolve <- function(breaks, TX = NULL, years = NULL, n_breaks = 4L) {
  if (is.list(breaks) && !is.null(breaks$strategy)) {
    strategy <- tolower(as.character(breaks$strategy))
    n_breaks <- breaks$n_breaks %||% n_breaks
    if (identical(strategy, "tx_quantile")) {
      min_pts <- breaks$min_points %||% 20L
      return(exdyn_coverage_breaks_quantile(TX, n_breaks = n_breaks, years = years, min_points = min_pts))
    }
    if (identical(strategy, "years")) {
      return(exdyn_coverage_breaks(years, n_breaks = n_breaks))
    }
  }
  if (is.null(breaks) || !length(breaks)) {
    return(exdyn_coverage_breaks(years, n_breaks = n_breaks))
  }
  if (is.numeric(breaks)) {
    return(as.numeric(breaks))
  }
  exdyn_coverage_breaks(years, n_breaks = n_breaks)
}
