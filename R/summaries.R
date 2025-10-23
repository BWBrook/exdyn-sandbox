#' Occupancy array
#' @keywords internal
exdyn_occupancy <- function(N, thresh = 1) {
  N > thresh
}

#' Occupancy centroid by year
#' @keywords internal
exdyn_centroid <- function(occ) {
  nx <- dim(occ)[1]; ny <- dim(occ)[2]; years <- dim(occ)[3]
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
  years <- dim(occ)[3]
  areas <- rep(NA_real_, years)
  for (t in seq_len(years)) {
    mask <- occ[,,t]
    if (sum(mask) < 3) next
    coords <- which(mask, arr.ind = TRUE)
    hull_idx <- grDevices::chull(coords[,1], coords[,2])
    hull <- coords[hull_idx, , drop = FALSE]
    x <- hull[,1]; y <- hull[,2]
    areas[t] <- 0.5 * abs(sum(x * c(y[-1], y[1])) - sum(y * c(x[-1], x[1])))
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

#' Extirpation time map
#' @keywords internal
exdyn_extirpation_time <- function(N, K0, frac = 0.02) {
  threshold <- K0 * frac
  apply(N, c(1, 2), function(ts) {
    idx <- which(ts <= threshold)
    if (length(idx)) idx[1] else NA_real_
  })
}

#' Arrival–extirpation coupling diagnostics
#' @keywords internal
#' @export
exdyn_arrival_coupling <- function(T_X, T_P, D = NULL) {
  if (is.null(T_P)) {
    return(list(
      r_arrival_pearson = NA_real_,
      r_arrival_spearman = NA_real_,
      r2_arrival = NA_real_,
      lag_arrival_mean = NA_real_,
      r2_dist = NA_real_,
      coverage = 0
    ))
  }
  valid <- !is.na(T_X) & !is.na(T_P)
  coverage <- if (length(valid)) mean(valid) else 0
  if (!any(valid)) {
    return(list(
      r_arrival_pearson = NA_real_,
      r_arrival_spearman = NA_real_,
      r2_arrival = NA_real_,
      lag_arrival_mean = NA_real_,
      r2_dist = NA_real_,
      coverage = coverage
    ))
  }
  tx <- T_X[valid]
  tp <- T_P[valid]
  r_arrival_pearson <- suppressWarnings(stats::cor(tx, tp, method = "pearson"))
  r_arrival_spearman <- suppressWarnings(stats::cor(tx, tp, method = "spearman"))
  model <- stats::lm(tx ~ tp)
  r2_arrival <- summary(model)$r.squared
  lag_arrival_mean <- mean(tx - tp, na.rm = TRUE)
  r2_dist <- NA_real_
  if (!is.null(D)) {
    dist_vals <- D[valid]
    dist_model <- stats::lm(tx ~ dist_vals)
    r2_dist <- summary(dist_model)$r.squared
  }
  list(
    r_arrival_pearson = r_arrival_pearson,
    r_arrival_spearman = r_arrival_spearman,
    r2_arrival = r2_arrival,
    lag_arrival_mean = lag_arrival_mean,
    r2_dist = r2_dist,
    coverage = coverage
  )
}

#' Centroid path diagnostics
#' @keywords internal
exdyn_centroid_metrics <- function(centroid) {
  valid <- which(rowSums(is.na(centroid)) == 0)
  if (length(valid) < 2) {
    return(list(disp_per_year = NA_real_, r2_centroid_line = NA_real_))
  }
  cx <- centroid[valid,1]
  cy <- centroid[valid,2]
  t_valid <- valid
  diffs <- sqrt(diff(cx)^2 + diff(cy)^2)
  disp_per_year <- mean(diffs, na.rm = TRUE)
  lm_x <- stats::lm(cx ~ t_valid)
  lm_y <- stats::lm(cy ~ t_valid)
  r2_x <- suppressWarnings(summary(lm_x)$r.squared)
  r2_y <- suppressWarnings(summary(lm_y)$r.squared)
  r2_centroid_line <- mean(c(r2_x, r2_y), na.rm = TRUE)
  list(disp_per_year = disp_per_year, r2_centroid_line = r2_centroid_line)
}

#' Plane fit diagnostics for front directionality
#' @keywords internal
#' @export
exdyn_front_plane <- function(T_X) {
  idx <- which(!is.na(T_X), arr.ind = TRUE)
  if (nrow(idx) < 3) {
    return(list(grad_mag = NA_real_, r2_plane = NA_real_, pc_ratio = NA_real_))
  }
  vals <- T_X[idx]
  df <- data.frame(t = vals, x = idx[,1], y = idx[,2])
  fit <- stats::lm(t ~ x + y, data = df)
  coefs <- stats::coef(fit)
  grad_mag <- sqrt(coefs["x"]^2 + coefs["y"]^2)
  r2_plane <- summary(fit)$r.squared
  weights <- vals - min(vals) + 1
  covmat <- tryCatch(stats::cov.wt(df[,c("x","y")], wt = weights, method = "ML")$cov,
                     error = function(...) NA)
  pc_ratio <- NA_real_
  if (all(is.finite(covmat))) {
    eig <- eigen(covmat, symmetric = TRUE, only.values = TRUE)$values
    eig <- sort(eig, decreasing = TRUE)
    if (length(eig) >= 2 && eig[2] > 0) {
      pc_ratio <- eig[1] / eig[2]
    }
  }
  list(grad_mag = grad_mag, r2_plane = r2_plane, pc_ratio = pc_ratio)
}

#' Discriminative summaries for a run
#' @export
exdyn_summaries <- function(N, fields, K0, arrival_threshold_frac = 0.02, occ_thresh = 1) {
  yrs <- dim(N)[3]
  total <- apply(N, 3, sum)
  t <- seq_len(yrs)
  fit <- stats::lm(total ~ stats::poly(t, 2, raw = TRUE))
  convexity <- stats::coef(fit)[3]

  occ <- exdyn_occupancy(N, thresh = occ_thresh)
  centroid <- exdyn_centroid(occ)
  centroid_shift <- if (any(is.na(centroid[c(1, yrs), ]))) NA_real_ else 
    sqrt(sum((centroid[yrs,] - centroid[1,])^2))
  centroid_diag <- exdyn_centroid_metrics(centroid)

  hull <- exdyn_hull_area(occ)
  range_area <- exdyn_range_area(occ)
  perim_ratio <- exdyn_perimeter_ratio(occ)
  moran <- exdyn_moran_range(occ)

  mean_P <- apply(fields$P, 3, mean)
  mean_H <- apply(fields$H, 3, mean)
  xcorr_P_vals <- exdyn_xcorr(total, mean_P, max_lag = 10)
  xcorr_H_vals <- exdyn_xcorr(total, mean_H, max_lag = 10)

  T_X <- exdyn_extirpation_time(N, K0, frac = arrival_threshold_frac)
  T_P <- fields$T_P
  coupling <- exdyn_arrival_coupling(T_X, T_P, fields$D)
  plane_metrics <- exdyn_front_plane(T_X)

  tibble::tibble(
    convexity = convexity,
    centroid_shift = centroid_shift,
    centroid_cx_final = centroid[yrs,1],
    centroid_cy_final = centroid[yrs,2],
    centroid_disp_per_year = centroid_diag$disp_per_year,
    r2_centroid_line = centroid_diag$r2_centroid_line,
    hull_area_mean = mean(hull, na.rm = TRUE),
    hull_area_final = hull[yrs],
    range_area_mean = mean(range_area, na.rm = TRUE),
    range_area_final = range_area[yrs],
    perimeter_ratio_mean = mean(perim_ratio, na.rm = TRUE),
    moran_median = moran$median,
    moran_first_gt_0_3 = moran$first_gt_0_3,
    xcorr_P = xcorr_P_vals$corr,
    xcorr_P_lag = xcorr_P_vals$lag,
    xcorr_H = xcorr_H_vals$corr,
    xcorr_H_lag = xcorr_H_vals$lag,
    r_arrival_pearson = coupling$r_arrival_pearson,
    r_arrival_spearman = coupling$r_arrival_spearman,
    r2_arrival = coupling$r2_arrival,
    lag_arrival_mean = coupling$lag_arrival_mean,
    r2_dist = coupling$r2_dist,
    arrival_coverage = coupling$coverage,
    grad_mag = plane_metrics$grad_mag,
    r2_plane = plane_metrics$r2_plane,
    pc_ratio = plane_metrics$pc_ratio
  )
}

#' Response-only summaries derived from abundance trajectories
#' @export
exdyn_summaries_response_only <- function(N, K0, arrival_threshold_frac = 0.02, occ_thresh = 1) {
  yrs <- dim(N)[3]
  total <- apply(N, 3, sum)
  t <- seq_len(yrs)
  fit <- stats::lm(total ~ stats::poly(t, 2, raw = TRUE))
  convexity <- stats::coef(fit)[3]

  occ <- exdyn_occupancy(N, thresh = occ_thresh)
  centroid <- exdyn_centroid(occ)
  centroid_shift <- if (any(is.na(centroid[c(1, yrs), ]))) NA_real_ else
    sqrt(sum((centroid[yrs,] - centroid[1,])^2))
  centroid_diag <- exdyn_centroid_metrics(centroid)

  hull <- exdyn_hull_area(occ)
  range_area <- exdyn_range_area(occ)
  perim_ratio <- exdyn_perimeter_ratio(occ)
  moran <- exdyn_moran_range(occ)

  range_fit <- tryCatch(stats::lm(range_area ~ t), error = function(...) NULL)
  range_slope <- if (is.null(range_fit)) NA_real_ else stats::coef(range_fit)[2]

  total_fit <- tryCatch(stats::lm(total ~ t), error = function(...) NULL)
  total_slope <- if (is.null(total_fit)) NA_real_ else stats::coef(total_fit)[2]

  T_X <- exdyn_extirpation_time(N, K0, frac = arrival_threshold_frac)
  finite_tx <- is.finite(T_X)
  tx_mean <- if (any(finite_tx)) mean(T_X[finite_tx]) else NA_real_
  tx_sd <- if (any(finite_tx)) stats::sd(T_X[finite_tx]) else NA_real_
  tx_coverage <- mean(finite_tx)
  plane_metrics <- exdyn_front_plane(T_X)

  tibble::tibble(
    resp_convexity = convexity,
    resp_total_mean = mean(total),
    resp_total_sd = stats::sd(total),
    resp_total_final = total[yrs],
    resp_total_ratio_final = if (!is.na(total[1]) && total[1] > 0) total[yrs] / total[1] else NA_real_,
    resp_total_slope = total_slope,
    resp_centroid_shift = centroid_shift,
    resp_centroid_disp_per_year = centroid_diag$disp_per_year,
    resp_r2_centroid_line = centroid_diag$r2_centroid_line,
    resp_hull_area_mean = mean(hull, na.rm = TRUE),
    resp_hull_area_final = hull[yrs],
    resp_range_area_mean = mean(range_area, na.rm = TRUE),
    resp_range_area_final = range_area[yrs],
    resp_range_area_slope = range_slope,
    resp_perimeter_ratio_mean = mean(perim_ratio, na.rm = TRUE),
    resp_moran_median = moran$median,
    resp_moran_first_gt_0_3 = moran$first_gt_0_3,
    resp_grad_mag = plane_metrics$grad_mag,
    resp_r2_plane = plane_metrics$r2_plane,
    resp_pc_ratio = plane_metrics$pc_ratio,
    resp_tx_mean = tx_mean,
    resp_tx_sd = tx_sd,
    resp_tx_coverage = tx_coverage
  )
}
