# Helpers for report rendering (internal)

exdyn_safe_tar_read <- function(name, default) {
  tryCatch(
    targets::tar_read_raw(name),
    error = function(e) default
  )
}

exdyn_effort_taxa_table <- function(normalize_taxa) {
  purrr::map_dfr(normalize_taxa %||% list(), function(x) {
    tibble::tibble(
      name = x$name %||% x[[1]] %||% NA_character_,
      rank = x$rank %||% x[[2]] %||% NA_character_
    )
  })
}

exdyn_metrics_from_tx_df <- function(df) {
  n_units <- nrow(df)
  n_tx <- sum(!is.na(df$tx_obs))
  coverage <- if (n_units > 0) n_tx / n_units else NA_real_
  valid <- df %>% dplyr::filter(is.finite(.data$tx_obs), is.finite(.data$T_P))
  r2 <- if (nrow(valid) >= 3) {
    summary(stats::lm(tx_obs ~ T_P, data = valid))$r.squared
  } else {
    NA_real_
  }
  lag <- if (nrow(valid)) mean(valid$tx_obs - valid$T_P) else NA_real_
  tibble::tibble(
    n_units = n_units,
    n_tx = n_tx,
    coverage = coverage,
    r2_arrival = r2,
    lag_mean = lag
  )
}
