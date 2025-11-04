#' Critical kill rate required to offset intrinsic growth
#'
#' Computes the per-capita predation multiplier (c*) that reduces the net
#' demographic update to zero given baseline abundance. Assumes P = 1 and
#' constant suitability / habitat erosion (S = 1, H = 0).
#'
#' @param K0 Carrying capacity (numeric scalar or matrix).
#' @param rmax Maximum intrinsic growth rate.
#' @param h Half-saturation parameter for the type-II functional response.
#' @param N0_frac Fraction of K0 used as the evaluation abundance (default 0.1).
#' @param S0 Baseline suitability value (default 1).
#' @param d Background mortality (default 0.03).
#'
#' @return Numeric matrix of the same dimensions as K0 (or scalar if inputs are
#'   scalar).
#' @export
exdyn_c_critical <- function(K0, rmax, h, N0_frac = 0.1, S0 = 1, d = 0.03) {
  K0 <- as.matrix(K0)
  rmax <- as.matrix(rmax)
  h <- as.matrix(h)
  if (!all(dim(rmax) %in% c(1, dim(K0)))) {
    rmax <- matrix(rmax, nrow = nrow(K0), ncol = ncol(K0), byrow = TRUE)
  }
  if (!all(dim(h) %in% c(1, dim(K0)))) {
    h <- matrix(h, nrow = nrow(K0), ncol = ncol(K0), byrow = TRUE)
  }
  N0 <- K0 * N0_frac
  r_eff <- rmax * exdyn_fS(S0)
  num <- r_eff * (1 - N0 / K0) - d
  p <- N0 / (h + N0)
  out <- num / p
  out[!is.finite(out)] <- NA_real_
  pmax(0, out)
}
