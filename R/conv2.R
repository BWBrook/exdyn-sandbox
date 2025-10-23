#' Simple 2D FFT convolution for dispersal
#' @keywords internal
#' @export
exdyn_conv2 <- function(mat, kernel) {
  stopifnot(all(dim(kernel) %% 2 == 1))
  pad <- (dim(kernel)-1)/2
  big <- matrix(0, nrow = nrow(mat)+2*pad[1], ncol = ncol(mat)+2*pad[2])
  big[ (pad[1]+1):(pad[1]+nrow(mat)), (pad[2]+1):(pad[2]+ncol(mat)) ] <- mat
  fa <- fft(big); fb <- fft(kern_pad(kernel, dim(big)))
  Re(fft(fa*fb, inverse=TRUE)/length(fa))[ (pad[1]+1):(pad[1]+nrow(mat)), (pad[2]+1):(pad[2]+ncol(mat)) ]
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
