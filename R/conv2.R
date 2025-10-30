#' Precompute FFT plan for 2D convolution
#' @export
exdyn_conv2_plan <- function(nx, ny, kernel) {
  stopifnot(all(dim(kernel) %% 2L == 1L))
  pad <- (dim(kernel) - 1L) / 2L
  big_dim <- c(nx + 2L * pad[1], ny + 2L * pad[2])
  list(
    pad = pad,
    big_dim = big_dim,
    fb = stats::fft(kern_pad(kernel, big_dim)),
    x_idx = (pad[1] + 1L):(pad[1] + nx),
    y_idx = (pad[2] + 1L):(pad[2] + ny)
  )
}

#' Apply cached FFT plan
#' @export
exdyn_conv2_apply <- function(mat, plan) {
  big <- matrix(0, nrow = plan$big_dim[1], ncol = plan$big_dim[2])
  big[plan$x_idx, plan$y_idx] <- mat
  fa <- stats::fft(big)
  Re(stats::fft(fa * plan$fb, inverse = TRUE) / length(fa))[plan$x_idx, plan$y_idx]
}

#' Simple 2D FFT convolution for dispersal (backward-compatible wrapper)
#' @keywords internal
#' @export
exdyn_conv2 <- function(mat, kernel) {
  plan <- exdyn_conv2_plan(nrow(mat), ncol(mat), kernel)
  exdyn_conv2_apply(mat, plan)
}
kern_pad <- function(k, dims) {
  out <- matrix(0, nrow=dims[1], ncol=dims[2])
  kh <- (nrow(k)-1)/2; kw <- (ncol(k)-1)/2
  out[1:(kh+1), 1:(kw+1)] <- k[(kh+1):nrow(k), (kw+1):ncol(k)]
  out[(nrow(out)-kh+1):nrow(out), 1:(kw+1)] <- k[1:kh, (kw+1):ncol(k)]
  out[1:(kh+1), (ncol(out)-kw+1):ncol(out)] <- k[(kh+1):nrow(k), 1:kw]
  out[(nrow(out)-kh+1):nrow(out), (ncol(out)-kw+1):ncol(out)] <- k[1:kh, 1:kw]
  out
}
#' @export
exdyn_kernel <- function(mean_cells=1.0, radius=5L) {
  xs <- -radius:radius; ys <- -radius:radius
  K <- outer(xs, ys, function(i,j) exp(-sqrt(i^2+j^2)/mean_cells))
  K/sum(K)
}
