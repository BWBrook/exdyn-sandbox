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
  # S: smooth spatial gradient north->south with optional drift
  baseS <- outer(seq(0.2,0.9,length.out=nx), seq(0.3,0.8,length.out=ny), function(a,b) (a+b)/2)
  drift_per_year <- climate_drift / 100
  for (t in seq_len(years)) {
    drift <- (t-1) * drift_per_year
    S[,,t] <- pmin(1, pmax(0, baseS + drift))
  }
  # Coordinates for distance computations
  coords <- as.matrix(expand.grid(x = seq_len(nx), y = seq_len(ny)))
  if (scenario %in% c("predation_front","both") && length(predation_seeds) > 0) {
    seeds <- do.call(rbind, lapply(predation_seeds, function(pt) {
      matrix(c(pt[1], pt[2]), nrow = 1, dimnames = list(NULL, c("x","y")))
    }))
    if (is.null(seeds)) {
      seeds <- matrix(c(1, ny%/%2), nrow = 1, dimnames = list(NULL, c("x","y")))
    }
    dist_mat <- matrix(Inf, nrow = nrow(coords), ncol = 1)
    for (j in seq_len(nrow(seeds))) {
      d <- sqrt((coords[,1] - seeds[j,1])^2 + (coords[,2] - seeds[j,2])^2)
      dist_mat <- pmin(dist_mat, d)
    }
    dist_mat <- array(dist_mat, dim = c(nx, ny))
    steep <- 2 # logistic slope
    for (t in seq_len(years)) {
      radius <- predation_speed * (t-1)
      front <- 1/(1 + exp((dist_mat - radius) / steep))
      P[,,t] <- pmin(1, front)
    }
  }
  if (scenario %in% c("habitat_erosion","both")) {
    coast <- outer(seq(0,1,length.out=nx), seq(0,1,length.out=ny), function(i,j) pmin(i,1-i,j,1-j))
    coast <- 1 - (coast / max(coast))
    coast_log <- 1/(1 + exp(-habitat_beta * (coast - 0.5)))
    for (t in seq_len(years)) {
      if (t <= ramp_start) {
        prog <- 0
      } else if (t >= ramp_end) {
        prog <- 1
      } else {
        prog <- (t - ramp_start)/(ramp_end - ramp_start)
      }
      H[,,t] <- pmin(1, prog * coast_log)
    }
  }
  list(S=S,P=P,H=H)
}
