#' Synthetic fields S (suitability), P (predation), H (habitat)
#' @export
exdyn_make_fields <- function(nx, ny, years, scenario, ramp_start, ramp_end) {
  S <- array(NA_real_, c(nx,ny,years))
  P <- array(0, c(nx,ny,years))
  H <- array(0, c(nx,ny,years))
  # S: smooth spatial gradient north->south
  baseS <- outer(seq(0.2,0.9,length.out=nx), seq(0.3,0.8,length.out=ny), function(a,b) (a+b)/2)
  for (t in 1:years) S[,,t] <- baseS
  # P: predation front from west & east coasts
  if (scenario %in% c("predation_front","both")) {
    for (t in 1:years) {
      front_w <- pmin(1, pmax(0, (t-1)/20))
      front_e <- pmin(1, pmax(0, (t-1)/20))
      P[,,t] <- pmax( baseS*0,  pmax( outer(seq_len(nx), 0, function(i,.) front_w*(i/nx)),
                                      outer(0, seq_len(ny), function(.,j) front_e*((ny-j+1)/ny)) ) )
    }
  }
  # H: habitat erosion ramp everywhere, stronger near coast proxies
  if (scenario %in% c("habitat_erosion","both")) {
    coast <- outer(seq(0,1,length.out=nx), seq(0,1,length.out=ny), function(i,j) pmin(i,1-i,j,1-j))
    coast <- 1 - (coast / max(coast))
    for (t in 1:years) {
      f <- if (t < ramp_start) 0 else if (t > ramp_end) 1 else (t - ramp_start)/(ramp_end - ramp_start)
      H[,,t] <- f * coast
    }
  }
  list(S=S,P=P,H=H)
}
