# Synthetic ceiling run helpers (internal)

exdyn_ceiling_runs <- function(cfg,
                               arrivals_real,
                               grid_info,
                               years_vec,
                               mask,
                               theta_star,
                               noise_cfg,
                               tx_cfg,
                               screen_cfg,
                               compat_cfg,
                               abc_cfg,
                               coverage_breaks) {
  cfg <- cfg %||% list(enabled = FALSE)
  if (!isTRUE(cfg$enabled)) {
    return(list(ceiling_runs = list(), arrivals = NULL))
  }
  reps <- cfg$reps %||% 10L
  seed_base <- cfg$seed %||% 2041L
  n_cores <- cfg$n_cores %||% 1L
  arrival_source <- cfg$arrival_source %||% "synthetic_gradient"
  noise_ceiling <- utils::modifyList(noise_cfg, cfg$noise %||% list())
  screen_use <- utils::modifyList(screen_cfg, cfg$screen %||% list())
  abc_use <- utils::modifyList(abc_cfg, cfg$abc %||% list())
  cell_km <- grid_info$cell_km %||% 10
  theta_lhs <- exdyn_param_lhs(
    screen_use,
    n = screen_use$n_draws %||% 4L,
    cell_km = cell_km,
    seed = screen_use$seed %||% seed_base
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
    K0 = screen_use$K0 %||% 120
  )
  delta_lookup <- theta_star$delta_region %||% list()
  if (length(delta_lookup)) {
    for (nm in names(delta_lookup)) {
      truth_row[[paste0("delta_", nm)]] <- delta_lookup[[nm]]
    }
  }
  theta_tbl <- dplyr::bind_rows(truth_row, theta_lhs)

  arrivals_tbl <- exdyn_synthetic_arrival_table(
    arrivals = arrivals_real,
    grid_info = grid_info,
    years = years_vec,
    source = arrival_source,
    seed = seed_base
  )

  run_one <- function(rep_id) {
    seed <- seed_base + rep_id
    set.seed(seed)
    truth_ceiling <- exdyn_make_synthetic(
      theta_star = theta_star,
      noise_cfg = noise_ceiling,
      arrivals = arrivals_tbl,
      grid_info = grid_info,
      years = years_vec,
      tx_cfg = tx_cfg,
      K0 = screen_use$K0 %||% 120,
      mask = mask
    )
    run_ceiling <- exdyn_synthetic_mode_run(
      truth = truth_ceiling,
      mode = "realistic",
      grid_info = grid_info,
      years_vec = years_vec,
      mask = mask,
      theta_tbl = theta_tbl,
      screen_cfg = screen_use,
      compat_cfg = compat_cfg,
      abc_cfg = abc_use,
      coverage_breaks = coverage_breaks,
      keep_best_tx = TRUE,
      enforce_gates = FALSE
    )
    run_ceiling$replicate <- rep_id
    run_ceiling$seed <- seed
    run_ceiling$truth <- truth_ceiling
    run_ceiling
  }
  ceiling_runs <- if (n_cores > 1) {
    parallel::mclapply(seq_len(reps), run_one, mc.cores = n_cores)
  } else {
    lapply(seq_len(reps), run_one)
  }
  list(
    ceiling_runs = ceiling_runs,
    arrivals = arrivals_tbl,
    screen_cfg = screen_use,
    abc_cfg = abc_use
  )
}

exdyn_ceiling_rep_metrics <- function(mode_runs, scenario) {
  if (!length(mode_runs)) {
    return(tibble::tibble())
  }
  rep_tbl <- exdyn_recovery_rep_metrics(mode_runs)
  extra_tbl <- purrr::map_dfr(mode_runs, function(run) {
    summary_obs <- run$summary_obs %||% list()
    obs_r2 <- summary_obs[["r2_arrival"]] %||% NA_real_
    obs_lag <- summary_obs[["lag_mean"]] %||% NA_real_
    obs_coverage <- summary_obs[["coverage"]] %||% NA_real_
    cov_obs <- summary_obs[grepl("^cov_curve_", names(summary_obs))]
    abc_summ <- run$abc$summaries %||% tibble::tibble()
    rmse <- NA_real_
    if (length(cov_obs) && nrow(abc_summ)) {
      cov_cols <- intersect(names(cov_obs), names(abc_summ))
      if (length(cov_cols)) {
        cov_med <- vapply(cov_cols, function(col) stats::median(abc_summ[[col]], na.rm = TRUE), numeric(1))
        rmse <- sqrt(mean((cov_med - unlist(cov_obs[cov_cols]))^2, na.rm = TRUE))
      }
    }
    tibble::tibble(
      replicate = run$replicate %||% NA_integer_,
      obs_r2 = obs_r2,
      obs_lag = obs_lag,
      obs_coverage = obs_coverage,
      coverage_curve_rmse = rmse
    )
  })
  rep_tbl %>%
    dplyr::left_join(extra_tbl, by = "replicate") %>%
    dplyr::mutate(scenario = scenario)
}

exdyn_ceiling_summary_table <- function(rep_tbl) {
  if (!nrow(rep_tbl)) {
    return(tibble::tibble())
  }
  rep_tbl %>%
    dplyr::group_by(.data$scenario) %>%
    dplyr::summarise(
      n_reps = dplyr::n(),
      n_TX_true_mean = mean(.data$n_TX_true, na.rm = TRUE),
      n_TX_obs_mean = mean(.data$n_TX_obs, na.rm = TRUE),
      screen_best_loss_median = stats::median(.data$screen_best_loss, na.rm = TRUE),
      abc_r2_median = stats::median(.data$abc_r2_median, na.rm = TRUE),
      obs_r2_median = stats::median(.data$obs_r2, na.rm = TRUE),
      abc_lag_median = stats::median(.data$abc_lag_median, na.rm = TRUE),
      obs_lag_median = stats::median(.data$obs_lag, na.rm = TRUE),
      abc_coverage_median = stats::median(.data$abc_coverage_median, na.rm = TRUE),
      obs_coverage_median = stats::median(.data$obs_coverage, na.rm = TRUE),
      coverage_curve_rmse_median = stats::median(.data$coverage_curve_rmse, na.rm = TRUE),
      n_accept_median = stats::median(.data$n_accept, na.rm = TRUE),
      .groups = "drop"
    )
}

exdyn_ceiling_param_compare <- function(baseline_runs, ceiling_runs, screen_cfg, abc_cfg) {
  base_tbl <- exdyn_recovery_param_table(baseline_runs, screen_cfg, abc_cfg)
  ceil_tbl <- exdyn_recovery_param_table(ceiling_runs, screen_cfg, abc_cfg)
  if (nrow(base_tbl)) base_tbl$scenario <- "baseline"
  if (nrow(ceil_tbl)) ceil_tbl$scenario <- "ceiling"
  dplyr::bind_rows(base_tbl, ceil_tbl)
}

exdyn_ceiling_plot_compare <- function(rep_tbl, output_root) {
  if (!nrow(rep_tbl)) {
    return(NA_character_)
  }
  plot_tbl <- rep_tbl %>%
    dplyr::select(.data$scenario,
                  abc_r2_median = .data$abc_r2_median,
                  abc_coverage_median = .data$abc_coverage_median,
                  coverage_curve_rmse = .data$coverage_curve_rmse,
                  n_TX_obs = .data$n_TX_obs) %>%
    tidyr::pivot_longer(-.data$scenario, names_to = "metric", values_to = "value")
  p <- ggplot2::ggplot(plot_tbl, ggplot2::aes(x = scenario, y = value, color = scenario)) +
    ggplot2::geom_boxplot(outlier.alpha = 0.3) +
    ggplot2::facet_wrap(~ metric, scales = "free_y") +
    ggplot2::labs(title = "Ceiling vs baseline recovery (pilot grid)", x = NULL, y = NULL) +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "none")
  out_path <- file.path(output_root, "ceiling_recovery_compare.png")
  ggplot2::ggsave(out_path, p, width = 8, height = 5, dpi = 150)
  out_path
}

exdyn_ceiling_write_maps <- function(run, truth, grid_info, output_root) {
  if (is.null(run) || is.null(truth)) {
    return(character())
  }
  out_dir <- file.path(output_root, "ceiling")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  paths <- character()
  plot_and_save <- function(mat, title, filename) {
    if (is.null(mat)) return(NULL)
    p <- exdyn_plot_surface(mat, grid_info, title, fill_label = "Extirpation year")
    ggplot2::ggsave(filename, p, width = 6, height = 7, dpi = 150)
    filename
  }
  paths <- c(paths,
             plot_and_save(truth$TX_true, "Ceiling TX_true", file.path(out_dir, "TX_true_ceiling.png")),
             plot_and_save(truth$TX_obs, "Ceiling TX_obs", file.path(out_dir, "TX_obs_ceiling.png")),
             plot_and_save(run$best_tx, "Ceiling best TX", file.path(out_dir, "TX_best_ceiling.png")))
  if (!is.null(run$best_tx)) {
    diff_mat <- run$best_tx - truth$TX_true
    paths <- c(paths, plot_and_save(diff_mat, "Ceiling best - true (years)", file.path(out_dir, "TX_diff_ceiling.png")))
  }
  paths[!vapply(paths, is.null, logical(1))]
}

exdyn_ceiling_compare <- function(cfg,
                                  arrivals_real,
                                  baseline_runs,
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
                                  output_root) {
  cfg <- cfg %||% list(enabled = FALSE)
  if (!isTRUE(cfg$enabled)) {
    return(list(replicate_metrics = tibble::tibble(), summary = tibble::tibble(),
                param = tibble::tibble(), outputs = character()))
  }
  runs <- exdyn_ceiling_runs(
    cfg = cfg,
    arrivals_real = arrivals_real,
    grid_info = grid_info,
    years_vec = years_vec,
    mask = mask,
    theta_star = theta_star,
    noise_cfg = noise_cfg,
    tx_cfg = tx_cfg,
    screen_cfg = screen_cfg,
    compat_cfg = compat_cfg,
    abc_cfg = abc_cfg,
    coverage_breaks = coverage_breaks
  )
  baseline_runs <- baseline_runs %||% list()
  baseline_runs <- purrr::keep(baseline_runs, ~ identical(.x$mode %||% "realistic", "realistic"))
  rep_base <- exdyn_ceiling_rep_metrics(baseline_runs, "baseline")
  rep_ceil <- exdyn_ceiling_rep_metrics(runs$ceiling_runs, "ceiling")
  rep_tbl <- dplyr::bind_rows(rep_base, rep_ceil)
  summary_tbl <- exdyn_ceiling_summary_table(rep_tbl)
  param_tbl <- exdyn_ceiling_param_compare(baseline_runs, runs$ceiling_runs, runs$screen_cfg, runs$abc_cfg)

  outputs <- character()
  if (!is.null(output_root)) {
    summary_path <- file.path(output_root, "ceiling_run_summary.csv")
    rep_path <- file.path(output_root, "ceiling_run_replicates.csv")
    param_path <- file.path(output_root, "ceiling_param_recovery.csv")
    readr::write_csv(summary_tbl, summary_path)
    readr::write_csv(rep_tbl, rep_path)
    if (nrow(param_tbl)) {
      readr::write_csv(param_tbl, param_path)
    }
    outputs <- c(outputs, summary_path, rep_path, param_path)
    outputs <- c(outputs, exdyn_ceiling_plot_compare(rep_tbl, output_root))

    ref_run <- runs$ceiling_runs[[1]] %||% baseline_runs[[1]]
    ref_truth <- if (!is.null(ref_run)) ref_run$truth %||% NULL else NULL
    outputs <- c(outputs, exdyn_ceiling_write_maps(ref_run, ref_truth, grid_info, output_root))
  }
  list(replicate_metrics = rep_tbl, summary = summary_tbl, param = param_tbl, outputs = outputs)
}
