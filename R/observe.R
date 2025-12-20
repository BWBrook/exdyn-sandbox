#' Presence-only sampling with effort surface
#' @export
exdyn_presence_only <- function(N, rate=0.002, effort_strength = 1) {
  yrs <- dim(N)[3]
  pts <- data.table::data.table()
  # simple accessibility: more effort near edges
  nx <- dim(N)[1]; ny <- dim(N)[2]
  access <- outer(seq(0,1,length.out=nx), seq(0,1,length.out=ny),
                  function(i,j) 1 - pmin(i,1-i,j,1-j))
  access <- access^effort_strength
  access <- access / mean(access)
  for (t in 1:yrs) {
    lam <- N[,,t]*access*rate
    n <- rpois(1, sum(lam))
    if (n>0) {
      idx <- sample.int(length(lam), size=n, replace=TRUE, prob=lam)
      x <- ((idx-1) %% nx) + 1; y <- ((idx-1) %/% nx) + 1
      pts <- rbind(pts, data.table::data.table(x=x,y=y,t=t))
    }
  }
  pts
}

#' Presence-only sampling with effort surface (cell-year counts)
#' @export
exdyn_presence_only_counts <- function(N, years_seq, grid_info, rate = 0.002, effort_strength = 1, mask = NULL) {
  stopifnot(length(dim(N)) == 3L)
  yrs <- dim(N)[3]
  if (is.null(years_seq)) {
    years_seq <- seq_len(yrs)
  }
  nx <- dim(N)[1]
  ny <- dim(N)[2]
  access <- outer(seq(0, 1, length.out = nx), seq(0, 1, length.out = ny),
                  function(i, j) 1 - pmin(i, 1 - i, j, 1 - j))
  access <- access^effort_strength
  access <- access / mean(access)
  lookup <- grid_info$lookup
  cell_idx <- cbind(lookup$row_idx, lookup$col_idx)
  n_cells <- nrow(lookup)
  counts_mat <- matrix(0L, nrow = n_cells, ncol = yrs)
  for (t in seq_len(yrs)) {
    lam <- N[, , t] * access * rate
    lam[!is.finite(lam)] <- 0
    lam <- pmax(lam, 0)
    if (!is.null(mask)) {
      lam[!mask] <- 0
    }
    counts <- stats::rpois(length(lam), lam)
    counts <- matrix(counts, nrow = nx, ncol = ny)
    counts_mat[, t] <- counts[cell_idx]
  }
  list(
    counts_mat = counts_mat,
    effort_mat = counts_mat,
    years = years_seq,
    cells = lookup
  )
}
#' Fossil-like samples with dating uncertainty
#' @export
exdyn_fossils <- function(N, n_sites=40, date_sd=30) {
  nx <- dim(N)[1]; ny <- dim(N)[2]; yrs <- dim(N)[3]
  cells <- sample.int(nx*ny, n_sites)
  x <- ((cells-1) %% nx) + 1; y <- ((cells-1) %/% nx) + 1
  # pick the last time abundance was > small threshold
  thresh <- max(1, quantile(c(N), 0.1, na.rm=TRUE))
  t_last <- vapply(seq_along(x), function(i){
    v <- N[x[i], y[i], ]
    idx <- which(v > thresh)
    if (!length(idx)) {
      NA_integer_
    } else {
      max(idx)
    }
  }, 1L)
  data.table::data.table(x=x,y=y,t_obs = pmax(1, round(t_last + rnorm(length(t_last),0,date_sd))))
}
