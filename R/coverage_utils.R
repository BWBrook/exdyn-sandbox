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
