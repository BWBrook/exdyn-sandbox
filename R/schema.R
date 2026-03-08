# Schema helpers (internal)

exdyn_schema_version <- function() {
  "0.4.0"
}

exdyn_summary_schema <- function() {
  coverage_breaks_n <- 4L
  base_names <- c(
    "grad_mag",
    "pc_ratio",
    "coverage",
    "lag_mean",
    "lag_sd",
    "r2_arrival",
    "orient_R",
    "speed_cells_per_year",
    "speed_r2",
    "tx_mean",
    "tx_sd"
  )
  list(
    version = exdyn_schema_version(),
    coverage_breaks_n = coverage_breaks_n,
    summary_names = c(base_names, paste0("cov_curve_", seq_len(coverage_breaks_n)))
  )
}
