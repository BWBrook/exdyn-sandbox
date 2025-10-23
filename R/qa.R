#' Extirpation threshold helper
#' @keywords internal
exdyn_extirpation_threshold <- function(N, K0, frac = 0.02, adaptive = TRUE, rel0 = 0.5) {
  dims <- dim(N)
  if (length(dims) < 3) stop("N must be a 3D array.")
  nx <- dims[1]; ny <- dims[2]
  tau <- array(K0 * frac, dim = c(nx, ny))
  if (adaptive) {
    init <- N[, , 1, drop = TRUE]
    tau <- pmin(tau, rel0 * init, na.rm = TRUE)
  }
  tau[!is.finite(tau)] <- K0 * frac
  pmax(tau, 0)
}

exdyn_qc_monotone_array <- function(arr, tol = 1e-8) {
  if (is.null(arr)) return(NA_real_)
  dims <- dim(arr)
  if (length(dims) != 3 || dims[3] < 2) return(NA_real_)
  monotone <- apply(arr, c(1, 2), function(series) {
    series <- series[is.finite(series)]
    if (length(series) < 2) return(NA_real_)
    all(diff(series) >= -tol)
  })
  if (all(is.na(monotone))) return(NA_real_)
  mean(monotone, na.rm = TRUE)
}

#' QA: monotonicity check for predation front field
#' @keywords internal
exdyn_qc_monotone_P <- function(fields, tol = 1e-8) {
  if (is.null(fields) || is.null(fields$P)) return(NA_real_)
  exdyn_qc_monotone_array(fields$P, tol = tol)
}

#' QA: monotonicity check for habitat erosion field
#' @keywords internal
exdyn_qc_monotone_H <- function(fields, tol = 1e-8) {
  if (is.null(fields) || is.null(fields$H)) return(NA_real_)
  exdyn_qc_monotone_array(fields$H, tol = tol)
}

#' QA: early extirpation sanity metrics
#' @keywords internal
exdyn_qc_early_extirpation <- function(N, K0, frac = 0.02, adaptive = TRUE, rel0 = 0.5, drop_fraction = NULL) {
  tau <- exdyn_extirpation_threshold(N, K0 = K0, frac = frac, adaptive = adaptive, rel0 = rel0)
  init <- N[, , 1, drop = TRUE]
  initial_below <- init <= tau
  if (all(is.na(initial_below))) {
    initial_below_frac <- NA_real_
  } else {
    initial_below_frac <- mean(initial_below, na.rm = TRUE)
  }
  T_X <- exdyn_extirpation_time(N, K0 = K0, frac = frac, adaptive = adaptive, rel0 = rel0, drop_fraction = drop_fraction)
  dims <- dim(N)
  first_any <- matrix(NA_real_, nrow = dims[1], ncol = dims[2])
  for (i in seq_len(dims[1])) {
    for (j in seq_len(dims[2])) {
      ts <- N[i, j, ]
      th <- tau[i, j]
      if (!any(is.finite(ts))) next
      idx <- which(ts <= th)
      if (length(idx)) first_any[i, j] <- idx[1]
    }
  }
  non_first <- !is.na(T_X) & !is.na(first_any) & (first_any < T_X)
  if (all(is.na(non_first))) {
    non_first_frac <- NA_real_
  } else {
    non_first_frac <- mean(non_first, na.rm = TRUE)
  }
  list(
    initial_below_frac = initial_below_frac,
    non_first_passage_frac = non_first_frac,
    tau = tau,
    T_X = T_X
  )
}

#' QA: presence-only counts vs total abundance
#' @keywords internal
exdyn_qc_po_sanity <- function(N, po) {
  yrs <- dim(N)[3]
  total <- apply(N, 3, sum, na.rm = TRUE)
  po_counts <- rep(0, yrs)
  if (!is.null(po) && nrow(po)) {
    counts <- table(po$t)
    idx <- as.integer(names(counts))
    idx <- idx[idx >= 1 & idx <= yrs]
    if (length(idx)) {
      po_counts[idx] <- as.integer(counts[as.character(idx)])
    }
  }
  if (length(unique(total)) <= 1 || length(unique(po_counts)) <= 1) {
    cor_val <- NA_real_
  } else {
    cor_val <- suppressWarnings(stats::cor(total, po_counts))
  }
  list(correlation = cor_val, total = total, po_counts = po_counts)
}

#' QA: arrival lag summary
#' @keywords internal
exdyn_qc_tp_tx_lag <- function(T_P, T_X, D = NULL) {
  exdyn_arrival_coupling(T_X, T_P, D = D)
}
