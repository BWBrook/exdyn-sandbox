# Synthetic benchmark and pilot-gate helpers (internal)

exdyn_benchmark_cfg_resolve <- function(cfg = NULL) {
  cfg <- cfg %||% list()
  stance <- tolower(cfg$stance %||% "strict")
  if (!stance %in% c("strict", "weak_id")) {
    stop("benchmark.stance must be 'strict' or 'weak_id'")
  }
  list(
    stance = stance,
    core_params = sort(unique(as.character(cfg$core_params %||% c("alpha", "disp_mean_km")))),
    gate_abs_rel_bias = cfg$gate_abs_rel_bias %||% 0.20,
    gate_coverage80 = cfg$gate_coverage80 %||% 0.60,
    weak_id_parameters = sort(unique(as.character(cfg$weak_id_parameters %||% character())))
  )
}

exdyn_pilot_gate_cfg_resolve <- function(cfg = NULL) {
  cfg <- cfg %||% list()
  th <- cfg$thresholds %||% list()
  list(
    enabled = isTRUE(cfg$enabled),
    thresholds = list(
      arrival_frac_finite_min = th$arrival_frac_finite_min %||% 0.90,
      tx_true_min = th$tx_true_min %||% 50L,
      tx_true_coverage_min = th$tx_true_coverage_min %||% 0.10,
      tx_true_coverage_max = th$tx_true_coverage_max %||% 0.80,
      tx_obs_min = th$tx_obs_min %||% 30L,
      tx_obs_coverage_min = th$tx_obs_coverage_min %||% 0.05,
      geom_finite_min = th$geom_finite_min %||% 3L,
      cov_curve_mid_min = th$cov_curve_mid_min %||% 2L,
      screen_compatible_min = th$screen_compatible_min %||% 1L,
      accept_rate_min = th$accept_rate_min %||% 0,
      accept_rate_max = th$accept_rate_max %||% 0.20
    )
  )
}

exdyn_pilot_gate_pre <- function(truth, summary_obs, counts, mask, gate_cfg = NULL) {
  gate_cfg <- exdyn_pilot_gate_cfg_resolve(gate_cfg)
  th <- gate_cfg$thresholds
  arrival_stats <- exdyn_arrival_coverage_stats(truth$T_P, mask = mask)
  frac_finite <- arrival_stats$frac_finite_mask %||% NA_real_
  g1_pass <- is.finite(frac_finite) && frac_finite >= th$arrival_frac_finite_min

  n_TP_finite <- counts[["n_TP_finite"]] %||% 0
  n_pairs_true <- counts[["n_pairs_true"]] %||% 0
  n_TX_true <- counts[["n_TX_true"]] %||% 0
  coverage_true <- if (n_TP_finite > 0) n_pairs_true / n_TP_finite else NA_real_
  g2_pass <- (is.finite(n_TX_true) && n_TX_true >= th$tx_true_min) ||
    (is.finite(coverage_true) &&
       coverage_true >= th$tx_true_coverage_min &&
       coverage_true <= th$tx_true_coverage_max)

  coverage_obs <- summary_obs[["coverage"]] %||% NA_real_
  n_TX_obs <- counts[["n_TX_obs"]] %||% 0
  geom_keys <- c("grad_mag", "pc_ratio", "r2_arrival", "orient_R", "speed_cells_per_year", "speed_r2")
  geom_vals <- summary_obs[geom_keys]
  geom_finite <- sum(is.finite(geom_vals))
  g3_signal <- (is.finite(n_TX_obs) && n_TX_obs >= th$tx_obs_min) ||
    (is.finite(coverage_obs) && coverage_obs >= th$tx_obs_coverage_min)
  g3_pass <- g3_signal && geom_finite >= th$geom_finite_min

  cov_vals <- summary_obs[grepl("^cov_curve_", names(summary_obs))]
  cov_mid <- if (length(cov_vals)) sum(cov_vals > 0 & cov_vals < 1, na.rm = TRUE) else 0
  g4_pass <- cov_mid >= th$cov_curve_mid_min

  gate_tbl <- tibble::tibble(
    gate = c("G1_arrival", "G2_TX_true", "G3_TX_obs", "G4_cov_curve"),
    pass = c(g1_pass, g2_pass, g3_pass, g4_pass),
    value = c(frac_finite, coverage_true, coverage_obs, cov_mid),
    threshold = c(
      sprintf(">=%.2f", th$arrival_frac_finite_min),
      sprintf("n_TX_true>=%s or coverage in [%.2f,%.2f]", th$tx_true_min, th$tx_true_coverage_min, th$tx_true_coverage_max),
      sprintf("n_TX_obs>=%s or coverage>=%.2f AND geom>=%s", th$tx_obs_min, th$tx_obs_coverage_min, th$geom_finite_min),
      sprintf(">=%s breakpoints", th$cov_curve_mid_min)
    ),
    detail = c(
      sprintf("n_finite_mask=%s n_mask=%s", arrival_stats$n_finite_mask, arrival_stats$n_mask),
      sprintf("n_TX_true=%s n_pairs_true=%s n_TP_finite=%s", n_TX_true, n_pairs_true, n_TP_finite),
      sprintf("n_TX_obs=%s geom_finite=%s", n_TX_obs, geom_finite),
      sprintf("n_mid_breaks=%s", cov_mid)
    )
  )
  list(table = gate_tbl, pass = all(gate_tbl$pass))
}

exdyn_pilot_gate_post <- function(screen_results, abc, abc_cfg, gate_cfg = NULL, skipped = FALSE) {
  gate_cfg <- exdyn_pilot_gate_cfg_resolve(gate_cfg)
  th <- gate_cfg$thresholds
  n_compatible <- if (is.null(screen_results) || !nrow(screen_results)) 0 else sum(screen_results$compatible %||% FALSE)
  n_accept <- if (!is.null(abc) && !is.null(abc$samples)) nrow(abc$samples) else 0
  n_sims <- abc_cfg$n_sims %||% NA_real_
  accept_rate <- if (is.finite(n_sims) && n_sims > 0) n_accept / n_sims else NA_real_
  g5_pass <- is.finite(n_compatible) && n_compatible >= th$screen_compatible_min &&
    is.finite(accept_rate) &&
    accept_rate > th$accept_rate_min &&
    accept_rate < th$accept_rate_max
  if (isTRUE(skipped)) {
    g5_pass <- FALSE
  }
  tibble::tibble(
    gate = "G5_screen_abc",
    pass = g5_pass,
    value = accept_rate,
    threshold = sprintf("n_compatible>=%s & %.2f<accept_rate<%.2f",
                        th$screen_compatible_min, th$accept_rate_min, th$accept_rate_max),
    detail = sprintf("n_compatible=%s n_accept=%s n_sims=%s%s",
                     n_compatible, n_accept, n_sims,
                     if (isTRUE(skipped)) " (skipped)" else "")
  )
}
