# Synthetic recovery summary helpers (internal)

exdyn_abc_summary_table <- function(samples, theta_star) {
  if (!nrow(samples)) {
    return(tibble::tibble())
  }
  numeric_cols <- dplyr::select(samples, where(is.numeric))
  stats_tbl <- purrr::imap_dfr(
    numeric_cols,
    ~ tibble::tibble(
      param = .y,
      median = stats::median(.x, na.rm = TRUE),
      p025 = stats::quantile(.x, 0.025, na.rm = TRUE, names = FALSE),
      p100 = stats::quantile(.x, 0.10, na.rm = TRUE, names = FALSE),
      p250 = stats::quantile(.x, 0.25, na.rm = TRUE, names = FALSE),
      p750 = stats::quantile(.x, 0.75, na.rm = TRUE, names = FALSE),
      p900 = stats::quantile(.x, 0.90, na.rm = TRUE, names = FALSE),
      p975 = stats::quantile(.x, 0.975, na.rm = TRUE, names = FALSE),
      mean = mean(.x, na.rm = TRUE),
      sd = stats::sd(.x, na.rm = TRUE)
    )
  )
  truth_vals <- exdyn_flatten_theta(theta_star)
  truth_tbl <- tibble::enframe(truth_vals, name = "param", value = "truth")
  dplyr::left_join(stats_tbl, truth_tbl, by = "param")
}

exdyn_recovery_rep_metrics <- function(mode_runs) {
  if (!length(mode_runs)) {
    return(tibble::tibble())
  }
  scalar_col <- function(tbl, col, default = NA_real_) {
    if (is.null(tbl) || !nrow(tbl) || !(col %in% names(tbl))) {
      return(default)
    }
    val <- tbl[[col]][[1]]
    if (!length(val)) default else val
  }
  purrr::map_dfr(mode_runs, function(run) {
    screen <- run$screen_results %||% tibble::tibble()
    if (nrow(screen)) {
      idx <- run$best_index %||% 1L
      if (!is.finite(idx) || idx < 1 || idx > nrow(screen)) {
        idx <- 1L
      }
      best <- screen[idx, , drop = FALSE]
    } else {
      best <- tibble::tibble()
    }
    summaries <- run$abc$summaries %||% tibble::tibble()
    counts <- run$summary_counts %||% list()
    tibble::tibble(
      mode = run$mode,
      replicate = run$replicate %||% NA_integer_,
      seed = run$seed %||% NA_integer_,
      n_mask = counts[["n_mask"]] %||% NA_real_,
      n_TP_finite = counts[["n_TP_finite"]] %||% NA_real_,
      n_TX_true = counts[["n_TX_true"]] %||% NA_real_,
      n_TX_obs = counts[["n_TX_obs"]] %||% NA_real_,
      n_pairs = counts[["n_pairs"]] %||% NA_real_,
      n_accept = nrow(run$abc$samples %||% tibble::tibble()),
      eps = run$abc$eps %||% NA_real_,
      screen_best_loss = scalar_col(best, "loss"),
      screen_best_r2 = scalar_col(best, "r2_arrival"),
      screen_best_lag = scalar_col(best, "lag_mean"),
      screen_best_coverage = scalar_col(best, "coverage"),
      abc_distance_median = if (length(run$abc$distances)) stats::median(run$abc$distances) else NA_real_,
      abc_lag_median = if (nrow(summaries) && "lag_mean" %in% names(summaries)) stats::median(summaries$lag_mean, na.rm = TRUE) else NA_real_,
      abc_coverage_median = if (nrow(summaries) && "coverage" %in% names(summaries)) stats::median(summaries$coverage, na.rm = TRUE) else NA_real_,
      abc_r2_median = if (nrow(summaries) && "r2_arrival" %in% names(summaries)) stats::median(summaries$r2_arrival, na.rm = TRUE) else NA_real_
    )
  })
}

exdyn_pilot_gate_table <- function(mode_runs) {
  if (!length(mode_runs)) {
    return(tibble::tibble())
  }
  purrr::map_dfr(mode_runs, function(run) {
    gates <- run$pilot_gates %||% tibble::tibble()
    if (!nrow(gates)) return(tibble::tibble())
    gates %>%
      dplyr::mutate(
        mode = run$mode,
        replicate = run$replicate %||% NA_integer_,
        seed = run$seed %||% NA_integer_
      ) %>%
      dplyr::select(.data$mode, .data$replicate, .data$seed, .data$gate,
                    .data$pass, .data$value, .data$threshold, .data$detail)
  })
}

exdyn_prior_sd_table <- function(screen_cfg, abc_cfg) {
  prior_cfg <- abc_cfg$prior %||% list()
  scalar_bounds <- list(
    alpha = prior_cfg$alpha %||% screen_cfg$alpha,
    disp_mean_km = prior_cfg$disp_mean_km %||% screen_cfg$disp_mean_km,
    A_over_K = prior_cfg$A_over_K %||% screen_cfg$A_over_K,
    pred_c = prior_cfg$pred_c %||% screen_cfg$pred_c,
    pred_h = prior_cfg$pred_h %||% screen_cfg$pred_h,
    ramp_years = prior_cfg$ramp_years %||% screen_cfg$ramp_years,
    pred_scale = prior_cfg$pred_scale %||% screen_cfg$pred_scale,
    gamma = prior_cfg$gamma %||% screen_cfg$gamma,
    rmax = prior_cfg$rmax %||% screen_cfg$rmax
  )
  delta_bounds <- prior_cfg$delta_region %||% screen_cfg$delta_region %||% list()
  rows <- purrr::imap_dfr(scalar_bounds, function(bounds, name) {
    if (is.null(bounds) || length(bounds) < 2) return(tibble::tibble())
    tibble::tibble(param = name, prior_sd = diff(bounds) / sqrt(12))
  })
  if (length(delta_bounds)) {
    delta_rows <- purrr::imap_dfr(delta_bounds, function(bounds, name) {
      if (is.null(bounds) || length(bounds) < 2) return(tibble::tibble())
      tibble::tibble(param = paste0("delta_", name), prior_sd = diff(bounds) / sqrt(12))
    })
    rows <- dplyr::bind_rows(rows, delta_rows)
  }
  rows
}

exdyn_identifiability_status <- function(abs_rel_bias,
                                         coverage_80,
                                         param,
                                         benchmark_cfg = NULL) {
  cfg <- exdyn_benchmark_cfg_resolve(benchmark_cfg)
  gate_abs <- cfg$gate_abs_rel_bias
  gate_cov <- cfg$gate_coverage80
  weak_params <- cfg$weak_id_parameters
  if (!is.finite(abs_rel_bias) || !is.finite(coverage_80)) {
    return("unassessed")
  }
  if (abs_rel_bias <= gate_abs && coverage_80 >= gate_cov) {
    return("recoverable")
  }
  if (identical(cfg$stance, "weak_id") && param %in% weak_params) {
    return("weakly_identifiable")
  }
  "not_recoverable"
}

exdyn_benchmark_summary <- function(param_tbl, benchmark_cfg = NULL) {
  cfg <- exdyn_benchmark_cfg_resolve(benchmark_cfg)
  if (!nrow(param_tbl)) {
    return(tibble::tibble())
  }
  allowed_status <- if (identical(cfg$stance, "weak_id")) {
    c("recoverable", "weakly_identifiable")
  } else {
    "recoverable"
  }
  param_tbl %>%
    dplyr::filter(.data$core_param) %>%
    dplyr::group_by(.data$mode) %>%
    dplyr::summarise(
      stance = cfg$stance,
      n_core_params_expected = length(cfg$core_params),
      n_core_params_present = dplyr::n(),
      core_params_missing = paste(setdiff(cfg$core_params, .data$param), collapse = ","),
      n_core_recoverable = sum(.data$identifiability_status == "recoverable", na.rm = TRUE),
      n_core_weak_id = sum(.data$identifiability_status == "weakly_identifiable", na.rm = TRUE),
      n_core_not_recoverable = sum(.data$identifiability_status == "not_recoverable", na.rm = TRUE),
      n_core_unassessed = sum(.data$identifiability_status == "unassessed", na.rm = TRUE),
      overall_benchmark_pass = dplyr::n() == length(cfg$core_params) &&
        all(.data$identifiability_status %in% allowed_status),
      .groups = "drop"
    )
}

exdyn_recovery_param_table <- function(mode_runs, screen_cfg, abc_cfg, benchmark_cfg = NULL) {
  if (!length(mode_runs)) {
    return(tibble::tibble())
  }
  summaries <- purrr::map_dfr(mode_runs, function(run) {
    if (!nrow(run$abc_summary)) return(tibble::tibble())
    run$abc_summary %>%
      dplyr::mutate(
        mode = run$mode,
        replicate = run$replicate %||% NA_integer_
      )
  })
  if (!nrow(summaries)) {
    return(tibble::tibble())
  }
  prior_sd <- exdyn_prior_sd_table(screen_cfg, abc_cfg)
  cfg <- exdyn_benchmark_cfg_resolve(benchmark_cfg)
  gate_abs <- cfg$gate_abs_rel_bias
  gate_cov <- cfg$gate_coverage80
  summaries %>%
    dplyr::group_by(.data$mode, .data$param) %>%
    dplyr::summarise(
      truth = dplyr::first(.data$truth),
      bias = mean(.data$median - .data$truth, na.rm = TRUE),
      abs_bias = mean(abs(.data$median - .data$truth), na.rm = TRUE),
      rel_bias = mean(ifelse(.data$truth == 0, NA_real_, (.data$median - .data$truth) / abs(.data$truth)), na.rm = TRUE),
      rel_bias_median = stats::median(ifelse(.data$truth == 0, NA_real_, (.data$median - .data$truth) / abs(.data$truth)), na.rm = TRUE),
      mae = mean(abs(.data$median - .data$truth), na.rm = TRUE),
      coverage_50 = mean(.data$truth >= .data$p250 & .data$truth <= .data$p750, na.rm = TRUE),
      coverage_80 = mean(.data$truth >= .data$p100 & .data$truth <= .data$p900, na.rm = TRUE),
      coverage_95 = mean(.data$truth >= .data$p025 & .data$truth <= .data$p975, na.rm = TRUE),
      posterior_sd_median = stats::median(.data$sd, na.rm = TRUE),
      n_reps = sum(is.finite(.data$median)),
      .groups = "drop"
    ) %>%
    dplyr::left_join(prior_sd, by = "param") %>%
    dplyr::mutate(
      core_param = .data$param %in% cfg$core_params,
      shrinkage_ratio = .data$posterior_sd_median / .data$prior_sd,
      abs_rel_bias_median = abs(.data$rel_bias_median),
      gate_abs_rel_bias = gate_abs,
      gate_coverage80 = gate_cov,
      identifiability_status = purrr::pmap_chr(
        list(.data$abs_rel_bias_median, .data$coverage_80, .data$param),
        ~ exdyn_identifiability_status(..1, ..2, ..3, benchmark_cfg = cfg)
      ),
      gate_pass = .data$abs_rel_bias_median <= .data$gate_abs_rel_bias &
        .data$coverage_80 >= .data$gate_coverage80
    )
}

exdyn_synthetic_recovery_tables <- function(mode_runs, screen_cfg, abc_cfg, benchmark_cfg = NULL) {
  param_tbl <- exdyn_recovery_param_table(mode_runs, screen_cfg, abc_cfg, benchmark_cfg = benchmark_cfg)
  list(
    replicate_metrics = exdyn_recovery_rep_metrics(mode_runs),
    parameter_recovery = param_tbl,
    benchmark_summary = exdyn_benchmark_summary(param_tbl, benchmark_cfg = benchmark_cfg),
    pilot_gates = exdyn_pilot_gate_table(mode_runs)
  )
}

exdyn_write_synthetic_recovery_tables <- function(recovery_tables, output_root) {
  rep_tbl <- recovery_tables$replicate_metrics %||% tibble::tibble()
  param_tbl <- recovery_tables$parameter_recovery %||% tibble::tibble()
  benchmark_tbl <- recovery_tables$benchmark_summary %||% tibble::tibble()
  gate_tbl <- recovery_tables$pilot_gates %||% tibble::tibble()
  if (!nrow(rep_tbl) && !nrow(param_tbl) && !nrow(benchmark_tbl)) {
    return(character())
  }
  rep_modes <- if ("mode" %in% names(rep_tbl)) rep_tbl$mode else character()
  param_modes <- if ("mode" %in% names(param_tbl)) param_tbl$mode else character()
  benchmark_modes <- if ("mode" %in% names(benchmark_tbl)) benchmark_tbl$mode else character()
  modes <- sort(unique(c(rep_modes, param_modes, benchmark_modes)))
  out_paths <- character()
  for (mode in modes) {
    mode_dir <- file.path(output_root, "recovery", mode)
    dir.create(mode_dir, recursive = TRUE, showWarnings = FALSE)
    rep_path <- file.path(mode_dir, "replicate_metrics.csv")
    param_path <- file.path(mode_dir, "parameter_recovery.csv")
    benchmark_path <- file.path(mode_dir, "benchmark_summary.csv")
    if (nrow(rep_tbl)) {
      readr::write_csv(rep_tbl %>% dplyr::filter(.data$mode == .env$mode), rep_path)
      out_paths <- c(out_paths, rep_path)
    }
    if (nrow(param_tbl)) {
      readr::write_csv(param_tbl %>% dplyr::filter(.data$mode == .env$mode), param_path)
      out_paths <- c(out_paths, param_path)
    }
    if (nrow(benchmark_tbl)) {
      readr::write_csv(benchmark_tbl %>% dplyr::filter(.data$mode == .env$mode), benchmark_path)
      out_paths <- c(out_paths, benchmark_path)
    }
    if (nrow(gate_tbl)) {
      gate_path <- file.path(mode_dir, "pilot_gates.csv")
      readr::write_csv(gate_tbl %>% dplyr::filter(.data$mode == .env$mode), gate_path)
      out_paths <- c(out_paths, gate_path)
    }
  }
  unique(out_paths)
}
