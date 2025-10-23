#' Presence-only sampling with effort surface
#' @export
exdyn_presence_only <- function(N, rate=0.002, effort_strength = 1) {
  yrs <- dim(N)[3]
  pts <- data.table::data.table()
  # simple accessibility: more effort near edges
  nx <- dim(N)[1]; ny <- dim(N)[2]
  access <- outer(seq(0,1,length.out=nx), seq(0,1,length.out=ny),
                  function(i,j) 1 - pmin(i,1-i,j,1-j))
  access <- access^effort_strength
  access <- access / mean(access)
  for (t in 1:yrs) {
    lam <- N[,,t]*access*rate
    n <- rpois(1, sum(lam))
    if (n>0) {
      idx <- sample.int(length(lam), size=n, replace=TRUE, prob=lam)
      x <- ((idx-1) %% nx) + 1; y <- ((idx-1) %/% nx) + 1
      pts <- rbind(pts, data.table::data.table(x=x,y=y,t=t))
    }
  }
  pts
}
#' Fossil-like samples with dating uncertainty
#' @export
exdyn_fossils <- function(N, n_sites=40, date_sd=30) {
  nx <- dim(N)[1]; ny <- dim(N)[2]; yrs <- dim(N)[3]
  cells <- sample.int(nx*ny, n_sites)
  x <- ((cells-1) %% nx) + 1; y <- ((cells-1) %/% nx) + 1
  # pick the last time abundance was > small threshold
  thresh <- max(1, quantile(c(N), 0.1, na.rm=TRUE))
  t_last <- vapply(seq_along(x), function(i){
    v <- N[x[i], y[i], ]
    idx <- which(v > thresh)
    if (!length(idx)) {
      NA_integer_
    } else {
      max(idx)
    }
  }, 1L)
  data.table::data.table(x=x,y=y,t_obs = pmax(1, round(t_last + rnorm(length(t_last),0,date_sd))))
}
