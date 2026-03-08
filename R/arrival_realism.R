# Arrival realism comparison utilities (internal)

exdyn_arrival_realism_summary_rate <- function(summary_obs, key_metrics = NULL) {
  if (is.null(summary_obs)) {
    return(NA_real_)
  }
  key_metrics <- key_metrics %||% c(
    "coverage",
    "lag_mean",
    "lag_sd",
    "r2_arrival",
    "grad_mag",
    "orient_R",
    "speed_cells_per_year",
    "speed_r2",
    "tx_mean",
    "tx_sd",
    "cov_curve_1",
    "cov_curve_2",
    "cov_curve_3",
    "cov_curve_4"
  )
  vals <- vapply(
    key_metrics,
    function(key) {
      if (!is.null(names(summary_obs)) && key %in% names(summary_obs)) {
        return(summary_obs[[key]])
      }
      NA_real_
    },
    numeric(1)
  )
  mean(is.finite(vals))
}

exdyn_arrival_realism_apply_overrides <- function(base_cfg, overrides = NULL) {
  if (is.null(overrides)) {
    return(base_cfg)
  }
  utils::modifyList(base_cfg, overrides)
}

exdyn_arrival_realism_comparison <- function(arrivals_real,
                                             grid_info,
                                             years_vec,
                                             mask,
                                             theta_star,
                                             noise_cfg,
                                             tx_cfg,
                                             screen_cfg,
                                             compat_cfg,
                                             abc_cfg,
                                             coverage_breaks,
                                             recovery_cfg,
                                             cfg) {
  cfg <- cfg %||% list()
  if (!isTRUE(cfg$enabled)) {
    return(tibble::tibble())
  }
  sources <- cfg$sources %||% c("real", "synthetic_plane")
  modes <- cfg$modes %||% c("ideal", "realistic")
  reps <- cfg$reps %||% 10L
  seed_base <- cfg$seed %||% recovery_cfg$seed %||% 1234L
  screen_cfg_use <- exdyn_arrival_realism_apply_overrides(screen_cfg, cfg$screen)
  abc_cfg_use <- exdyn_arrival_realism_apply_overrides(abc_cfg, cfg$abc)

  if (!is.null(screen_cfg_use$n_draws)) {
    screen_cfg_use$n_draws <- max(1L, as.integer(screen_cfg_use$n_draws))
  }
  if (!is.null(abc_cfg_use$n_sims)) {
    abc_cfg_use$n_sims <- max(1L, as.integer(abc_cfg_use$n_sims))
  }
  if (!is.null(abc_cfg_use$lhs$n)) {
    abc_cfg_use$lhs$n <- max(0L, as.integer(abc_cfg_use$lhs$n))
  }
  if (!is.null(abc_cfg_use$lhs$keep)) {
    abc_cfg_use$lhs$keep <- max(0L, as.integer(abc_cfg_use$lhs$keep))
  }
  if (!is.null(abc_cfg_use$lhs$n) && !is.null(abc_cfg_use$lhs$keep)) {
    if (abc_cfg_use$lhs$keep > abc_cfg_use$lhs$n) {
      abc_cfg_use$lhs$keep <- abc_cfg_use$lhs$n
    }
  }

  dispersal_mode <- tolower(screen_cfg_use$dispersal_mode %||% "fft")
  graph_plan <- NULL
  if (identical(dispersal_mode, "graph")) {
    graph_cfg <- cfg$graph %||% list()
    graph_plan <- exdyn_land_graph_plan(
      grid_info = grid_info,
      mask = mask,
      radius = graph_cfg$radius %||% 5L,
      include_self = graph_cfg$include_self %||% TRUE
    )
    screen_cfg_use$graph <- graph_plan
  }

  noise_cfg_use <- noise_cfg
  if (identical(dispersal_mode, "graph")) {
    noise_cfg_use$dispersal_mode <- "graph"
    noise_cfg_use$graph <- graph_plan
  }

  cell_km <- grid_info$cell_km %||% 10
  theta_tbl <- exdyn_param_lhs(
    screen_cfg_use,
    n = screen_cfg_use$n_draws %||% 1L,
    cell_km = cell_km,
    seed = screen_cfg_use$seed %||% 123
  )
  truth_row <- tibble::tibble(
    draw = 0L,
    alpha = theta_star$alpha,
    disp_mean_km = theta_star$disp_mean_km,
    disp_mean_cells = theta_star$disp_mean_km / cell_km,
    A_over_K = theta_star$A_over_K,
    pred_c = theta_star$pred_c,
    pred_h = theta_star$pred_h,
    ramp_years = theta_star$ramp_years,
    pred_scale = theta_star$pred_scale,
    gamma = theta_star$gamma,
    rmax = theta_star$rmax,
    K0 = screen_cfg_use$K0 %||% 120
  )
  delta_lookup <- theta_star$delta_region %||% list()
  if (length(delta_lookup)) {
    for (nm in names(delta_lookup)) {
      truth_row[[paste0("delta_", nm)]] <- delta_lookup[[nm]]
    }
  }
  theta_tbl <- dplyr::bind_rows(truth_row, theta_tbl)

  summary_rows <- vector("list", length(sources))

  for (src_idx in seq_along(sources)) {
    src <- sources[[src_idx]]
    arrivals_tbl <- exdyn_synthetic_arrival_table(
      arrivals = arrivals_real,
      grid_info = grid_info,
      years = years_vec,
      source = src,
      seed = seed_base
    )
    T_P <- exdyn_arrival_matrix(
      arrivals = arrivals_tbl,
      grid_info = grid_info,
      years = years_vec,
      delta_region = NULL
    )
    arrival_stats <- exdyn_arrival_coverage_stats(T_P, mask = mask)
    mode_runs <- list()
    run_rows <- list()

    for (replicate_id in seq_len(reps)) {
      seed <- seed_base + src_idx * 1000L + replicate_id
      set.seed(seed)
      truth <- exdyn_make_synthetic(
        theta_star = theta_star,
        noise_cfg = noise_cfg_use,
        arrivals = arrivals_tbl,
        grid_info = grid_info,
        years = years_vec,
        tx_cfg = tx_cfg,
        K0 = screen_cfg_use$K0 %||% 120,
        mask = mask
      )
      truth$replicate <- replicate_id
      truth$seed <- seed
      for (mode in modes) {
        res <- exdyn_synthetic_mode_run(
          truth = truth,
          mode = mode,
          grid_info = grid_info,
          years_vec = years_vec,
          mask = mask,
          theta_tbl = theta_tbl,
          screen_cfg = screen_cfg_use,
          compat_cfg = compat_cfg,
          abc_cfg = abc_cfg_use,
          coverage_breaks = coverage_breaks,
          keep_best_tx = FALSE,
          enforce_gates = FALSE
        )
        res$replicate <- replicate_id
        res$seed <- seed
        mode_runs[[length(mode_runs) + 1L]] <- res
        counts <- res$summary_counts %||% list()
        run_rows[[length(run_rows) + 1L]] <- tibble::tibble(
          mode = mode,
          replicate = replicate_id,
          summary_finite_rate = exdyn_arrival_realism_summary_rate(res$summary_obs),
          n_pairs = counts[["n_pairs"]] %||% NA_real_,
          n_TX_true = counts[["n_TX_true"]] %||% NA_real_,
          n_TX_obs = counts[["n_TX_obs"]] %||% NA_real_,
          n_TP_finite = counts[["n_TP_finite"]] %||% NA_real_
        )
      }
      gc()
    }

    run_tbl <- dplyr::bind_rows(run_rows)
    run_summary <- run_tbl %>%
      dplyr::group_by(.data$mode) %>%
      dplyr::summarise(
        n_reps = dplyr::n(),
        mean_n_pairs = mean(.data$n_pairs, na.rm = TRUE),
        mean_n_TX_true = mean(.data$n_TX_true, na.rm = TRUE),
        mean_n_TX_obs = mean(.data$n_TX_obs, na.rm = TRUE),
        summary_finite_rate_mean = mean(.data$summary_finite_rate, na.rm = TRUE),
        summary_finite_rate_min = min(.data$summary_finite_rate, na.rm = TRUE),
        .groups = "drop"
      )

    param_tbl <- exdyn_recovery_param_table(mode_runs, screen_cfg_use, abc_cfg_use)
    param_summary <- param_tbl %>%
      dplyr::group_by(.data$mode) %>%
      dplyr::summarise(
        param_abs_bias_mean = mean(.data$abs_bias, na.rm = TRUE),
        param_coverage80_mean = mean(.data$coverage_80, na.rm = TRUE),
        param_coverage95_mean = mean(.data$coverage_95, na.rm = TRUE),
        .groups = "drop"
      )

    summary_rows[[src_idx]] <- run_summary %>%
      dplyr::left_join(param_summary, by = "mode") %>%
      dplyr::mutate(
        arrival_source = src,
        n_mask = arrival_stats$n_mask,
        n_TP_finite = arrival_stats$n_finite_mask,
        frac_finite_TP_in_mask = arrival_stats$frac_finite_mask
      )
  }

  dplyr::bind_rows(summary_rows) %>%
    dplyr::select(
      "arrival_source",
      "mode",
      "n_reps",
      "n_mask",
      "n_TP_finite",
      "frac_finite_TP_in_mask",
      "mean_n_pairs",
      "mean_n_TX_true",
      "mean_n_TX_obs",
      "summary_finite_rate_mean",
      "summary_finite_rate_min",
      "param_abs_bias_mean",
      "param_coverage80_mean",
      "param_coverage95_mean"
    )
}
