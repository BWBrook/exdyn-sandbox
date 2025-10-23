#' Basic summaries for pattern-oriented diagnostics
#' @export
exdyn_summaries <- function(N, fields) {
  yrs <- dim(N)[3]
  total <- apply(N, 3, sum)
  # convexity of decline
  t <- 1:yrs; fit <- lm(total ~ poly(t,2,raw=TRUE))
  conv <- coef(fit)[3]
  list(total=total, convexity=conv)
}
