#' One-year update without dispersal
#' @keywords internal
#' @export
exdyn_update_local <- function(N, S, H, P, pars, K0, pred_type=c("II","III"), pred_c, pred_h) {
  pred_type <- match.arg(pred_type)
  K <- pmax(1e-9, K0 * (1 - pars$beta_H * H))
  r_eff <- pars$rmax * exdyn_fS(S)
  A <- pars$A_frac
  allee <- (1 - A/(pmax(N,0)+A))
  # predation mortality per capita:
  if (pred_type == "II") {
    M <- pred_c * (P * N)/(pred_h + N)
  } else {
    M <- pred_c * (P * N^2)/(pred_h^2 + N^2)
  }
  growth <- r_eff * allee * (1 - N/K) - M - pars$d
  N * exp(growth)
}
#' Full simulation with dispersal
#' @export
exdyn_simulate <- function(nx, ny, years, fields, pars, K0=100, alpha=0.2, disp_mean_cells=1.0,
                           pred=list(type="II",c=0.6,h=30)) {
  N <- array(0, c(nx,ny,years))
  N[,,1] <- pmax(1, round(K0 * fields$S[,,1] * 0.1))
  ker <- exdyn_kernel(mean_cells=disp_mean_cells, radius=5L)
  for (t in 1:(years-1)) {
    local <- exdyn_update_local(
      N = N[,,t], S = fields$S[,,t], H = fields$H[,,t], P = fields$P[,,t],
      pars = pars, K0 = K0, pred_type = pred$type, pred_c = pred$c, pred_h = pred$h
    )
    if (alpha > 0) {
      moved <- exdyn_conv2(local, ker)
      N[,,t+1] <- (1-alpha)*local + alpha*moved
    } else {
      N[,,t+1] <- local
    }
    N[,,t+1] <- pmax(N[,,t+1], 0)
  }
  N
}
