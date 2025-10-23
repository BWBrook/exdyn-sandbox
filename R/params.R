#' Archetype priors
#' @export
exdyn_archetype <- function(type = c("A","B","C")) {
  type <- match.arg(type)
  switch(type,
    A = list(rmax=runif(1,0.8,1.2), A_frac=runif(1,0,0.05), disp_mean_km=runif(1,10,40), d=0.02),
    B = list(rmax=runif(1,0.3,0.6), A_frac=runif(1,0.05,0.2), disp_mean_km=runif(1,5,20), d=0.03),
    C = list(rmax=runif(1,0.1,0.25), A_frac=runif(1,0.1,0.3), disp_mean_km=runif(1,2,8), d=0.03)
  )
}
# logistic map of suitability to growth multiplier in (0,1]
#' @export
exdyn_fS <- function(S, s0=0.5, k=8) 1/(1+exp(-k*(S - s0)))
