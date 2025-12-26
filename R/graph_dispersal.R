# Graph-based dispersal utilities (land-cell graph)

#' Build offset table for a dispersal kernel
#' @keywords internal
exdyn_graph_offsets <- function(radius = 5L, include_self = TRUE) {
  radius <- as.integer(radius)
  offsets <- tidyr::expand_grid(
    dr = seq.int(-radius, radius),
    dc = seq.int(-radius, radius)
  )
  if (!isTRUE(include_self)) {
    offsets <- offsets[!(offsets$dr == 0 & offsets$dc == 0), , drop = FALSE]
  }
  offsets$dist <- sqrt(offsets$dr^2 + offsets$dc^2)
  offsets$offset_id <- seq_len(nrow(offsets))
  offsets
}

#' Build land-cell graph plan (edges + offsets) for graph dispersal
#' @keywords internal
exdyn_land_graph_plan <- function(grid_info, mask = NULL, radius = 5L, include_self = TRUE) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  if (is.null(mask)) {
    mask <- matrix(TRUE, nrow = nx, ncol = ny)
  }
  mask <- as.matrix(mask)
  if (!all(dim(mask) == c(nx, ny))) {
    stop("mask must have dimensions nx × ny")
  }
  coords <- which(mask, arr.ind = TRUE)
  if (!nrow(coords)) {
    stop("mask has no TRUE cells")
  }
  n <- nrow(coords)
  id_map <- matrix(NA_integer_, nrow = nx, ncol = ny)
  id_map[coords] <- seq_len(n)

  offsets <- exdyn_graph_offsets(radius = radius, include_self = include_self)
  edges_i <- integer(0)
  edges_j <- integer(0)
  edges_off <- integer(0)
  for (k in seq_len(nrow(offsets))) {
    dr <- offsets$dr[k]
    dc <- offsets$dc[k]
    r2 <- coords[, 1] + dr
    c2 <- coords[, 2] + dc
    ok <- r2 >= 1 & r2 <= nx & c2 >= 1 & c2 <= ny
    if (!any(ok)) {
      next
    }
    to <- id_map[cbind(r2[ok], c2[ok])]
    ok2 <- !is.na(to)
    if (!any(ok2)) {
      next
    }
    from <- which(ok)[ok2]
    edges_i <- c(edges_i, from)
    edges_j <- c(edges_j, to[ok2])
    edges_off <- c(edges_off, rep.int(k, sum(ok2)))
  }

  lookup_idx <- NULL
  if (!is.null(grid_info$lookup)) {
    lookup <- grid_info$lookup
    lookup_map <- matrix(NA_integer_, nrow = nx, ncol = ny)
    lookup_map[cbind(lookup$row_idx, lookup$col_idx)] <- seq_len(nrow(lookup))
    lookup_idx <- lookup_map[cbind(coords[, 1], coords[, 2])]
  }

  list(
    nx = nx,
    ny = ny,
    n = n,
    rows = coords[, 1],
    cols = coords[, 2],
    offsets = offsets,
    edges = list(i = edges_i, j = edges_j, offset_id = edges_off),
    lookup_idx = lookup_idx,
    radius = radius,
    include_self = include_self
  )
}

#' Convert graph plan to sparse dispersal matrix (kernel weights)
#' @keywords internal
exdyn_land_graph_weights <- function(graph, mean_cells) {
  if (is.null(graph$edges$i) || !length(graph$edges$i)) {
    stop("graph edges missing")
  }
  if (!is.finite(mean_cells) || mean_cells <= 0) {
    stop("mean_cells must be > 0")
  }
  offsets <- graph$offsets
  w_offsets <- exp(-offsets$dist / mean_cells)
  w_offsets <- w_offsets / sum(w_offsets)
  w <- w_offsets[graph$edges$offset_id]
  Matrix::sparseMatrix(
    i = graph$edges$i,
    j = graph$edges$j,
    x = w,
    dims = c(graph$n, graph$n)
  )
}
