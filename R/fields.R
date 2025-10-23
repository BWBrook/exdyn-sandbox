#' Coastline mask helper
#' @export
exdyn_coast_mask <- function(nx, ny) {
  coast <- outer(seq(0,1,length.out=nx), seq(0,1,length.out=ny), function(i,j) pmin(i,1-i,j,1-j))
  1 - (coast / max(coast))
}

#' Predation front generator
#' @keywords internal
exdyn_pred_front <- function(nx, ny, years, seeds, speed_cells_per_year, slope = 2) {
  seeds <- lapply(seeds, as.numeric)
  seeds <- seeds[vapply(seeds, length, integer(1)) == 2]
  if (!length(seeds)) {
    seeds <- list(c(1, floor(ny/2)))
  }
  coords <- as.matrix(expand.grid(x = seq_len(nx), y = seq_len(ny)))
  dist_vec <- rep(Inf, nrow(coords))
  for (pt in seeds) {
    d <- sqrt((coords[,1] - pt[1])^2 + (coords[,2] - pt[2])^2)
    dist_vec <- pmin(dist_vec, d)
  }
  D <- matrix(dist_vec, nrow = nx, ncol = ny)
  P <- array(0, dim = c(nx, ny, years))
  T_P <- matrix(NA_real_, nrow = nx, ncol = ny)
  for (t in seq_len(years)) {
    radius <- speed_cells_per_year * (t - 1)
    front <- 1 / (1 + exp((D - radius) / slope))
    front <- pmin(1, pmax(0, front))
    P[,,t] <- front
    newly_arrived <- is.na(T_P) & front >= 0.5
    if (any(newly_arrived)) {
      T_P[newly_arrived] <- t
    }
  }
  list(P = P, T_P = T_P, D = D)
}

#' Synthetic fields S (suitability), P (predation), H (habitat)
#' @export
exdyn_make_fields <- function(nx, ny, years, scenario,
                              habitat_beta, ramp_start, ramp_end,
                              predation_speed = 0.5, predation_seeds = list(),
                              climate_drift = 0) {
  dims <- c(nx, ny, years)
  S <- array(NA_real_, dims)
  P <- array(0, dims)
  H <- array(0, dims)
  T_P <- NULL
  D <- NULL

  # suitability gradient with optional drift
  baseS <- outer(seq(0.2,0.9,length.out=nx), seq(0.3,0.8,length.out=ny), function(a,b) (a+b)/2)
  drift_per_year <- climate_drift / 100
  for (t in seq_len(years)) {
    drift <- (t - 1) * drift_per_year
    S[,,t] <- pmin(1, pmax(0, baseS + drift))
  }

  if (scenario %in% c("predation_front", "both")) {
    front <- exdyn_pred_front(nx, ny, years, predation_seeds, predation_speed)
    P <- front$P
    T_P <- front$T_P
    D <- front$D
    if (scenario == "predation_front") {
      H[] <- 0
    }
  }

  if (scenario %in% c("habitat_erosion", "both")) {
    coast <- exdyn_coast_mask(nx, ny)
    coast_log <- 1/(1 + exp(-habitat_beta * (coast - 0.5)))
    for (t in seq_len(years)) {
      prog <- if (t <= ramp_start) 0 else if (t >= ramp_end) 1 else (t - ramp_start)/(ramp_end - ramp_start)
      H[,,t] <- pmin(1, prog * coast_log)
    }
    if (scenario == "habitat_erosion") {
      P[] <- 0
      T_P <- NULL
      D <- NULL
    }
  }

  list(S = S, P = P, H = H, T_P = T_P, D = D)
}
