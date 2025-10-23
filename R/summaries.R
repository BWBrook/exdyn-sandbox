#' Occupancy array
#' @keywords internal
exdyn_occupancy <- function(N, thresh = 1) {
  N > thresh
}

#' Occupancy centroid by year
#' @keywords internal
exdyn_centroid <- function(occ) {
  nx <- dim(occ)[1]; ny <- dim(occ)[2]; years <- dim(occ)[3]
  coords <- expand.grid(x = seq_len(nx), y = seq_len(ny))
  res <- matrix(NA_real_, nrow = years, ncol = 2, dimnames = list(NULL, c("cx","cy")))
  for (t in seq_len(years)) {
    mask <- occ[,,t]
    if (!any(mask)) next
    idx <- which(mask, arr.ind = TRUE)
    res[t,] <- c(mean(idx[,1]), mean(idx[,2]))
  }
  res
}

#' Convex hull area trajectory
#' @keywords internal
exdyn_hull_area <- function(occ) {
  nx <- dim(occ)[1]; ny <- dim(occ)[2]; years <- dim(occ)[3]
  areas <- rep(NA_real_, years)
  for (t in seq_len(years)) {
    mask <- occ[,,t]
    if (sum(mask) < 3) next
    coords <- which(mask, arr.ind = TRUE)
    hull_idx <- grDevices::chull(coords[,1], coords[,2])
    hull <- coords[hull_idx, , drop = FALSE]
    x <- hull[,1]; y <- hull[,2]
    area <- 0.5 * abs(sum(x * c(y[-1], y[1])) - sum(y * c(x[-1], x[1])))
    areas[t] <- area
  }
  areas
}

#' Range area
#' @keywords internal
exdyn_range_area <- function(occ) {
  apply(occ, 3, function(mat) sum(mat, na.rm = TRUE))
}

#' Perimeter to area ratio proxy
#' @keywords internal
exdyn_perimeter_ratio <- function(occ) {
  nx <- dim(occ)[1]; ny <- dim(occ)[2]; years <- dim(occ)[3]
  ratios <- rep(NA_real_, years)
  for (t in seq_len(years)) {
    mat <- occ[,,t]
    area <- sum(mat)
    if (area == 0) {
      ratios[t] <- NA_real_
      next
    }
    pad <- matrix(FALSE, nrow = nx + 2, ncol = ny + 2)
    pad[2:(nx+1), 2:(ny+1)] <- mat
    north <- pad[1:nx, 2:(ny+1)]
    south <- pad[3:(nx+2), 2:(ny+1)]
    east  <- pad[2:(nx+1), 3:(ny+2)]
    west  <- pad[2:(nx+1), 1:ny]
    edges <- mat * ((!north) + (!south) + (!east) + (!west))
    perimeter <- sum(edges)
    ratios[t] <- perimeter / area
  }
  ratios
}

#' Moran's I trajectory summary
#' @keywords internal
exdyn_moran_range <- function(occ) {
  nx <- dim(occ)[1]; ny <- dim(occ)[2]; years <- dim(occ)[3]
  n <- nx * ny
  # Build rook adjacency weights
  idx_matrix <- matrix(seq_len(n), nrow = nx, ncol = ny)
  neighbors <- vector("list", n)
  weights <- vector("list", n)
  for (i in seq_len(nx)) {
    for (j in seq_len(ny)) {
      idx <- idx_matrix[i, j]
      nb <- integer(0)
      if (i > 1) nb <- c(nb, idx_matrix[i-1, j])
      if (i < nx) nb <- c(nb, idx_matrix[i+1, j])
      if (j > 1) nb <- c(nb, idx_matrix[i, j-1])
      if (j < ny) nb <- c(nb, idx_matrix[i, j+1])
      neighbors[[idx]] <- nb
      weights[[idx]] <- rep(1, length(nb))
    }
  }
  W <- sum(vapply(weights, sum, numeric(1)))
  values <- matrix(as.integer(occ), nrow = n, ncol = years)
  I_vals <- rep(NA_real_, years)
  for (t in seq_len(years)) {
    x <- values[,t]
    mean_x <- mean(x)
    dev <- x - mean_x
    denom <- sum(dev^2)
    if (denom == 0) next
    num <- 0
    for (i in seq_len(n)) {
      if (length(neighbors[[i]]) == 0) next
      num <- num + sum(weights[[i]] * dev[i] * dev[neighbors[[i]]])
    }
    I_vals[t] <- (n / W) * (num / denom)
  }
  list(
    series = I_vals,
    median = stats::median(I_vals, na.rm = TRUE),
    first_gt_0_3 = {
      idx <- which(I_vals > 0.3)
      if (length(idx) == 0) NA_integer_ else idx[1]
    }
  )
}

#' Cross-correlation helper
#' @keywords internal
exdyn_xcorr <- function(series, driver, max_lag = 10) {
  stopifnot(length(series) == length(driver))
  n <- length(series)
  best_corr <- NA_real_
  best_lag <- NA_integer_
  for (lag in 0:max_lag) {
    if (lag >= n) break
    x <- series[(lag+1):n]
    y <- driver[1:(n-lag)]
    if (all(is.na(x)) || all(is.na(y))) next
    cc <- suppressWarnings(stats::cor(x, y))
    if (is.na(cc)) next
    if (is.na(best_corr) || abs(cc) > abs(best_corr)) {
      best_corr <- cc
      best_lag <- lag
    }
  }
  list(corr = best_corr, lag = best_lag)
}

#' Discriminative summaries for a run
#' @export
exdyn_summaries <- function(N, fields, thresh = 1) {
  yrs <- dim(N)[3]
  total <- apply(N, 3, sum)
  t <- seq_len(yrs)
  fit <- stats::lm(total ~ stats::poly(t, 2, raw = TRUE))
  convexity <- stats::coef(fit)[3]
  occ <- exdyn_occupancy(N, thresh = thresh)
  centroid <- exdyn_centroid(occ)
  centroid_shift <- NA_real_
  if (!any(is.na(centroid[c(1, yrs), ]))) {
    centroid_shift <- sqrt(sum((centroid[yrs,] - centroid[1,])^2))
  }
  hull <- exdyn_hull_area(occ)
  range_area <- exdyn_range_area(occ)
  perim_ratio <- exdyn_perimeter_ratio(occ)
  moran <- exdyn_moran_range(occ)
  mean_P <- apply(fields$P, 3, mean)
  mean_H <- apply(fields$H, 3, mean)
  xcorr_P_vals <- exdyn_xcorr(total, mean_P, max_lag = 10)
  xcorr_H_vals <- exdyn_xcorr(total, mean_H, max_lag = 10)
  xcorr_P_corr <- xcorr_P_vals$corr
  xcorr_P_lag <- xcorr_P_vals$lag
  xcorr_H_corr <- xcorr_H_vals$corr
  xcorr_H_lag <- xcorr_H_vals$lag
  if (is.null(xcorr_P_corr)) xcorr_P_corr <- NA_real_
  if (is.null(xcorr_P_lag)) xcorr_P_lag <- NA_integer_
  if (is.null(xcorr_H_corr)) xcorr_H_corr <- NA_real_
  if (is.null(xcorr_H_lag)) xcorr_H_lag <- NA_integer_
  tibble::tibble(
    convexity = convexity,
    centroid_shift = centroid_shift,
    centroid_cx_final = centroid[yrs,1],
    centroid_cy_final = centroid[yrs,2],
    hull_area_mean = mean(hull, na.rm = TRUE),
    hull_area_final = hull[yrs],
    range_area_mean = mean(range_area, na.rm = TRUE),
    range_area_final = range_area[yrs],
    perimeter_ratio_mean = mean(perim_ratio, na.rm = TRUE),
    moran_median = moran$median,
    moran_first_gt_0_3 = moran$first_gt_0_3,
    xcorr_P = xcorr_P_corr,
    xcorr_P_lag = xcorr_P_lag,
    xcorr_H = xcorr_H_corr,
    xcorr_H_lag = xcorr_H_lag
  )
}
