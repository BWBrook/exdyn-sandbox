# Synthetic recovery helpers (internal)

exdyn_flatten_theta <- function(theta) {
  if (is.null(theta)) return(numeric())
  scalar_vals <- theta[purrr::map_lgl(theta, is.numeric)]
  out <- unlist(scalar_vals, use.names = TRUE)
  if (!is.null(theta$delta_region)) {
    delta_vals <- unlist(theta$delta_region)
    names(delta_vals) <- paste0("delta_", names(delta_vals))
    out <- c(out, delta_vals)
  }
  out
}

exdyn_synthetic_modes <- function(cfg) {
  modes <- cfg$modes %||% c("realistic")
  modes <- unique(as.character(modes))
  if (!length(modes)) {
    modes <- "realistic"
  }
  modes[modes %in% c("realistic", "ideal")]
}

exdyn_synthetic_rep_grid <- function(recovery_cfg) {
  n_reps <- recovery_cfg$n_reps %||% 1L
  seed <- recovery_cfg$seed %||% 1234L
  set.seed(seed)
  seeds <- sample.int(1e6, n_reps)
  tibble::tibble(replicate = seq_len(n_reps), seed = seeds)
}

exdyn_abc_cfg_by_mode <- function(abc_cfg, mode) {
  cfg <- abc_cfg %||% list()
  if (!is.null(cfg$eps_by_mode) && !is.null(cfg$eps_by_mode[[mode]])) {
    cfg$eps <- cfg$eps_by_mode[[mode]]
  }
  if (!is.null(cfg$eps_tight_by_mode) && !is.null(cfg$eps_tight_by_mode[[mode]])) {
    cfg$eps_tight <- cfg$eps_tight_by_mode[[mode]]
  }
  cfg
}

exdyn_synthetic_tx_by_mode <- function(truth, mode) {
  mode <- match.arg(mode, c("ideal", "realistic"))
  tx_use <- if (identical(mode, "ideal")) truth$TX_true else truth$TX_obs
  list(
    mode = mode,
    TX_use = tx_use,
    TX_true = truth$TX_true,
    TX_obs = truth$TX_obs,
    T_P = truth$T_P
  )
}

exdyn_abc_empty <- function(abc_cfg) {
  list(
    samples = tibble::tibble(),
    summaries = tibble::tibble(),
    distances = numeric(),
    all = tibble::tibble(),
    eps = abc_cfg$eps %||% NA_real_,
    scale = abc_cfg$scale %||% NULL,
    required_metrics = abc_cfg$required_metrics %||% NULL,
    optional_missing_penalty = abc_cfg$optional_missing_penalty %||% 0
  )
}

exdyn_synthetic_screen_run <- function(theta_tbl,
                                       grid_info,
                                       years_vec,
                                       T_P,
                                       TX_obs,
                                       screen_cfg,
                                       compat_cfg,
                                       coverage_breaks,
                                       mask,
                                       theta_star,
                                       keep_best_tx = FALSE) {
  delta_cols <- names(theta_tbl)[grepl("^delta_", names(theta_tbl))]
  results <- vector("list", nrow(theta_tbl))
  best_key <- c(Inf, Inf, Inf)
  best_row_id <- NA_integer_
  best_tx <- NULL
  key_better <- function(new_key, old_key) {
    for (k in seq_along(new_key)) {
      if (new_key[[k]] < old_key[[k]]) return(TRUE)
      if (new_key[[k]] > old_key[[k]]) return(FALSE)
    }
    FALSE
  }
  cell_km <- grid_info$cell_km %||% 10
  scale_matrix <- screen_cfg$scale_matrix %||% NULL
  dispersal_mode <- screen_cfg$dispersal_mode %||% "fft"
  graph <- screen_cfg$graph %||% NULL
  for (i in seq_len(nrow(theta_tbl))) {
    theta_row <- theta_tbl[i, ]
    delta_lookup <- NULL
    if (length(delta_cols)) {
      delta_lookup <- purrr::map_dbl(delta_cols, ~ theta_row[[.x]])
      names(delta_lookup) <- gsub("^delta_", "", delta_cols)
    }
    T_P_adj <- exdyn_adjust_arrival_matrix(T_P, grid_info, delta_lookup, years_vec)
    if (any(!mask)) {
      T_P_adj[!mask] <- NA_real_
    }
    pars <- list(
      rmax = theta_row$rmax,
      A_frac = theta_row$A_over_K * screen_cfg$K0,
      beta_H = 0,
      d = 0.02
    )
    TX_idx <- exdyn_simulate_tx_only(
      grid_info = grid_info,
      years = years_vec,
      T_P = T_P_adj,
      ramp_years = round(theta_row$ramp_years),
      pars = pars,
      K0 = screen_cfg$K0,
      alpha = theta_row$alpha,
      disp_mean_cells = theta_row$disp_mean_cells %||% (theta_row$disp_mean_km / cell_km),
      pred = list(
        type = theta_star$pred_type %||% "II",
        c = theta_row$pred_c,
        h = theta_row$pred_h,
        scale = theta_row$pred_scale,
        gamma = theta_row$gamma,
        scale_matrix = scale_matrix
      ),
      pre_leak = theta_star$pre_leak %||% 0,
      mask = mask,
      crop = screen_cfg$crop %||% FALSE,
      dispersal_mode = dispersal_mode,
      graph = graph
    )
    TX_years <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    idx <- is.finite(TX_idx)
    if (any(idx)) {
      TX_years[idx] <- years_vec[TX_idx[idx]]
    }
    TX_years[!mask] <- NA_real_
    metrics <- exdyn_score(TX_obs, T_P_adj, TX_years, compat_cfg,
      coverage_breaks = coverage_breaks,
      mask = mask
    )
    coverage_sim <- if (any(mask)) mean(is.finite(TX_years[mask]), na.rm = TRUE) else NA_real_
    cov_flag <- if (is.finite(coverage_sim) && coverage_sim >= 0.2) 0 else 1
    loss_val <- if (is.finite(metrics$loss)) metrics$loss else Inf
    cov_ord <- if (is.finite(coverage_sim)) -coverage_sim else Inf
    key <- c(cov_flag, loss_val, cov_ord)
    result_row <- dplyr::bind_cols(theta_row, metrics) %>%
      dplyr::mutate(
        coverage_sim = coverage_sim,
        .row_id = i
      )
    results[[i]] <- result_row
    if (keep_best_tx && key_better(key, best_key)) {
      best_key <- key
      best_row_id <- i
      best_tx <- TX_years
    }
    gc()
  }
  res_df <- dplyr::bind_rows(results) %>%
    dplyr::arrange(coverage_sim < 0.2, loss, dplyr::desc(coverage_sim)) %>%
    dplyr::mutate(rank = dplyr::row_number())
  best_index <- if (nrow(res_df)) {
    if (is.finite(best_row_id)) match(best_row_id, res_df$.row_id) else 1L
  } else {
    NA_integer_
  }
  res_df <- dplyr::select(res_df, -".row_id")
  list(
    results = res_df,
    best_index = best_index,
    best_tx = best_tx
  )
}

exdyn_synthetic_abc_bundle <- function(summary_obs,
                                       truth,
                                       grid_info,
                                       years_vec,
                                       mask,
                                       screen_cfg,
                                       abc_cfg,
                                       coverage_breaks) {
  lhs_n <- abc_cfg$lhs$n %||% 0
  cell_km <- grid_info$cell_km %||% 10
  scale_default <- pmax(abs(summary_obs), 1e-6)
  scale_vec <- scale_default
  if (!is.null(abc_cfg$scale)) {
    scale_cfg <- unlist(abc_cfg$scale, use.names = TRUE)
    if (length(scale_cfg)) {
      valid_names <- intersect(names(scale_cfg), names(scale_vec))
      scale_vec[valid_names] <- scale_cfg[valid_names]
    }
  }
  required_metrics <- abc_cfg$required_metrics %||% names(summary_obs)
  optional_missing_penalty <- abc_cfg$optional_missing_penalty %||% 0

  simulate_once <- function(theta) {
    delta_lookup <- theta$delta_region %||% list()
    T_P_adj <- exdyn_adjust_arrival_matrix(truth$T_P, grid_info, delta_lookup, years_vec)
    if (any(!mask)) {
      T_P_adj[!mask] <- NA_real_
    }
    pars <- list(
      rmax = theta$rmax,
      A_frac = theta$A_over_K * screen_cfg$K0,
      beta_H = 0,
      d = 0.02
    )
    disp_cells <- theta$disp_mean_km / cell_km
    scale_matrix <- truth$scale_matrix %||% screen_cfg$scale_matrix %||% abc_cfg$scale_matrix %||% NULL
    dispersal_mode <- screen_cfg$dispersal_mode %||% "fft"
    graph <- screen_cfg$graph %||% NULL
    TX_idx <- exdyn_simulate_tx_only(
      grid_info = grid_info,
      years = years_vec,
      T_P = T_P_adj,
      ramp_years = round(theta$ramp_years),
      pars = pars,
      K0 = screen_cfg$K0,
      alpha = theta$alpha,
      disp_mean_cells = disp_cells,
      pred = list(
        type = truth$theta_star$pred_type %||% "II",
        c = theta$pred_c,
        h = theta$pred_h,
        scale = theta$pred_scale,
        gamma = theta$gamma,
        scale_matrix = scale_matrix
      ),
      pre_leak = truth$theta_star$pre_leak %||% 0,
      mask = mask,
      crop = screen_cfg$crop %||% FALSE,
      dispersal_mode = dispersal_mode,
      graph = graph
    )
    TX_years <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
    idx <- is.finite(TX_idx)
    if (any(idx)) {
      TX_years[idx] <- years_vec[TX_idx[idx]]
    }
    TX_years[!mask] <- NA_real_
    list(TX_sim = TX_years, T_P = T_P_adj)
  }

  summary_fn <- function(sim) {
    exdyn_summary_tx_response(
      sim$TX_sim,
      sim$T_P,
      years = years_vec,
      coverage_breaks = coverage_breaks,
      mask = mask
    )
  }

  lhs_scan <- function() {
    if (lhs_n <= 0) return(tibble::tibble())
    lhs_draws <- exdyn_param_lhs(
      screen_cfg,
      n = lhs_n,
      cell_km = cell_km,
      seed = abc_cfg$lhs$seed %||% 2026
    )
    results <- vector("list", nrow(lhs_draws))
    for (i in seq_len(nrow(lhs_draws))) {
      theta_row <- lhs_draws[i, ]
      delta_cols <- names(theta_row)[grepl("^delta_", names(theta_row))]
      delta_lookup <- NULL
      if (length(delta_cols)) {
        delta_lookup <- purrr::map_dbl(delta_cols, ~ theta_row[[.x]])
        names(delta_lookup) <- gsub("^delta_", "", delta_cols)
      }
      T_P_adj <- exdyn_adjust_arrival_matrix(
        truth$T_P,
        grid_info,
        delta_lookup,
        years_vec
      )
      if (any(!mask)) {
        T_P_adj[!mask] <- NA_real_
      }
      pars <- list(
        rmax = theta_row$rmax,
        A_frac = theta_row$A_over_K * screen_cfg$K0,
        beta_H = 0,
        d = 0.02
      )
      scale_matrix <- truth$scale_matrix %||% screen_cfg$scale_matrix %||% abc_cfg$scale_matrix %||% NULL
      dispersal_mode <- screen_cfg$dispersal_mode %||% "fft"
      graph <- screen_cfg$graph %||% NULL
      TX_idx <- exdyn_simulate_tx_only(
        grid_info = grid_info,
        years = years_vec,
        T_P = T_P_adj,
        ramp_years = round(theta_row$ramp_years),
        pars = pars,
        K0 = screen_cfg$K0,
        alpha = theta_row$alpha,
        disp_mean_cells = theta_row$disp_mean_cells,
        pred = list(
          type = truth$theta_star$pred_type %||% "II",
          c = theta_row$pred_c,
          h = theta_row$pred_h,
          scale = theta_row$pred_scale,
          gamma = theta_row$gamma,
          scale_matrix = scale_matrix
        ),
        pre_leak = truth$theta_star$pre_leak %||% 0,
        mask = mask,
        crop = screen_cfg$crop %||% FALSE,
        dispersal_mode = dispersal_mode,
        graph = graph
      )
      TX_years <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
      idx <- is.finite(TX_idx)
      if (any(idx)) {
        TX_years[idx] <- years_vec[TX_idx[idx]]
      }
      TX_years[!mask] <- NA_real_
      S_sim <- exdyn_summary_tx_response(
        TX_years,
        T_P_adj,
        years = years_vec,
        coverage_breaks = coverage_breaks
      )
      S_sim <- S_sim[names(summary_obs)]
      dist_info <- .exdyn_abc_distance_components(
        S_obs = summary_obs,
        S_sim = S_sim,
        scale = scale_vec,
        required_metrics = required_metrics,
        optional_missing_penalty = optional_missing_penalty
      )
      dist <- dist_info$distance_total
      results[[i]] <- dplyr::bind_cols(theta_row, tibble::tibble(distance = dist))
    }
    dplyr::bind_rows(results)
  }

  seed_bank <- function(scan_tbl) {
    keep <- abc_cfg$lhs$keep %||% 0
    if (!nrow(scan_tbl) || keep <= 0) {
      tibble::tibble()
    } else {
      scan_tbl %>% dplyr::arrange(distance) %>% dplyr::slice_head(n = min(keep, nrow(scan_tbl)))
    }
  }

  build_prior_sampler <- function(seed_bank_tbl) {
    prior_cfg <- abc_cfg$prior %||% list()
    delta_bounds <- prior_cfg$delta_region %||% screen_cfg$delta_region
    scalar_bounds <- prior_cfg[setdiff(names(prior_cfg), "delta_region")]
    base_sampler <- exdyn_prior_sampler_syn(scalar_bounds, delta_bounds)
    bounds <- exdyn_param_bounds(screen_cfg, cell_km = cell_km)
    jitter_sd <- abc_cfg$lhs$jitter_sd %||% 0.05
    seed_prob <- abc_cfg$lhs$seed_prob %||% 0.5
    param_cols <- names(bounds)
    sampler_from_bank <- function() {
      if (!nrow(seed_bank_tbl)) return(NULL)
      row <- seed_bank_tbl[sample(nrow(seed_bank_tbl), 1), , drop = FALSE]
      theta <- as.list(row[1, param_cols[param_cols %in% names(row)], drop = FALSE])
      if (!length(theta)) return(NULL)
      theta <- exdyn_theta_jitter(theta, bounds, jitter_sd)
      theta
    }
    function() {
      use_seed <- nrow(seed_bank_tbl) > 0 && runif(1) < seed_prob
      if (use_seed) {
        theta <- sampler_from_bank()
        if (!is.null(theta)) return(theta)
      }
      base_sampler()
    }
  }

  scan_tbl <- lhs_scan()
  seed_tbl <- seed_bank(scan_tbl)
  prior_sampler <- build_prior_sampler(seed_tbl)
  abc <- exdyn_abc_rejection(
    S_obs = summary_obs,
    prior_sampler = prior_sampler,
    simulator = simulate_once,
    summary_fn = summary_fn,
    n_sims = abc_cfg$n_sims %||% 2000,
    eps = abc_cfg$eps %||% 1,
    scale = scale_vec,
    required_metrics = required_metrics,
    optional_missing_penalty = optional_missing_penalty,
    progress = FALSE
  )
  if (nrow(abc$samples)) {
    abc$all <- tibble::tibble()
  }

  if (!isFALSE(abc_cfg$refine) && nrow(abc$samples)) {
    eps_tight <- abc_cfg$eps_tight %||% ((abc_cfg$eps %||% 1) * 0.5)
    bounds <- exdyn_param_bounds(screen_cfg, cell_km = cell_km)
    jitter_sd <- abc_cfg$lhs$jitter_sd %||% 0.05
    mix_prob <- abc_cfg$lhs$seed_prob %||% 0.65
    particles <- abc$samples
    base_param_names <- c("alpha","disp_mean_km","A_over_K","pred_c","pred_h","ramp_years","pred_scale","gamma","rmax")
    to_theta <- function(row) {
      theta <- list()
      for (nm in base_param_names) {
        if (nm %in% names(row)) {
          theta[[nm]] <- as.numeric(row[[nm]][1])
        }
      }
      theta$K0 <- screen_cfg$K0
      delta_cols <- grep("^delta_", names(row), value = TRUE)
      if (length(delta_cols)) {
        vals <- as.numeric(unlist(row[delta_cols]))
        names(vals) <- sub("^delta_", "", delta_cols)
        theta$delta_region <- vals
      }
      theta
    }
    particle_list <- purrr::map(seq_len(nrow(particles)), function(i) to_theta(particles[i, , drop = FALSE]))
    refined_sampler <- function() {
      if (length(particle_list) && runif(1) < mix_prob) {
        theta <- particle_list[[sample(length(particle_list), 1)]]
        theta <- exdyn_theta_jitter(theta, bounds, jitter_sd)
        return(theta)
      }
      prior_sampler()
    }
    abc_refined <- exdyn_abc_rejection(
      S_obs = summary_obs,
      prior_sampler = refined_sampler,
      simulator = simulate_once,
      summary_fn = summary_fn,
      n_sims = abc_cfg$n_sims %||% 2000,
      eps = eps_tight,
      scale = scale_vec,
      required_metrics = required_metrics,
      optional_missing_penalty = optional_missing_penalty,
      progress = FALSE
    )
    if (nrow(abc_refined$samples)) {
      abc_refined$all <- tibble::tibble()
    }
    abc_final <- if (nrow(abc_refined$samples)) abc_refined else abc
  } else {
    abc_final <- abc
  }
  list(
    abc = abc_final,
    abc_summary = exdyn_abc_summary_table(abc_final$samples, truth$theta_star)
  )
}

exdyn_synthetic_mode_run <- function(truth,
                                     mode,
                                     grid_info,
                                     years_vec,
                                     mask,
                                     theta_tbl,
                                     screen_cfg,
                                     compat_cfg,
                                     abc_cfg,
                                     benchmark_cfg = NULL,
                                     gate_cfg = NULL,
                                     coverage_breaks,
                                     keep_best_tx = FALSE,
                                     enforce_gates = FALSE) {
  tx_info <- exdyn_synthetic_tx_by_mode(truth, mode)
  coverage_breaks_use <- exdyn_coverage_breaks_resolve(
    coverage_breaks,
    TX = tx_info$TX_use,
    years = years_vec
  )
  abc_cfg_use <- exdyn_abc_cfg_by_mode(abc_cfg, mode)
  summary_obs <- exdyn_summary_tx_response(
    tx_info$TX_use,
    tx_info$T_P,
    years = years_vec,
    coverage_breaks = coverage_breaks_use,
    mask = mask
  )
  counts_true <- exdyn_summary_counts(truth$TX_true, truth$T_P, mask = mask)
  counts_obs <- exdyn_summary_counts(truth$TX_obs, truth$T_P, mask = mask)
  counts_use <- exdyn_summary_counts(tx_info$TX_use, tx_info$T_P, mask = mask)
  counts <- c(
    n_mask = counts_use[["n_mask"]],
    n_TP_finite = counts_use[["n_TP_finite"]],
    n_pairs = counts_use[["n_pairs"]],
    n_TX_use = counts_use[["n_TX_finite"]],
    n_TX_true = counts_true[["n_TX_finite"]],
    n_TX_obs = counts_obs[["n_TX_finite"]],
    n_pairs_true = counts_true[["n_pairs"]],
    n_pairs_obs = counts_obs[["n_pairs"]]
  )
  gate_pre <- if (isTRUE(enforce_gates)) {
    exdyn_pilot_gate_pre(truth, summary_obs, counts, mask, gate_cfg = gate_cfg)
  } else {
    list(table = tibble::tibble(), pass = TRUE)
  }

  screen <- list(results = tibble::tibble(), best_index = NA_integer_, best_tx = NULL)
  abc_bundle <- list(abc = exdyn_abc_empty(abc_cfg_use), abc_summary = tibble::tibble())
  gate_table <- gate_pre$table

  if (!isTRUE(enforce_gates) || gate_pre$pass) {
    screen <- exdyn_synthetic_screen_run(
      theta_tbl = theta_tbl,
      grid_info = grid_info,
      years_vec = years_vec,
      T_P = tx_info$T_P,
      TX_obs = tx_info$TX_use,
      screen_cfg = screen_cfg,
      compat_cfg = compat_cfg,
      coverage_breaks = coverage_breaks_use,
      mask = mask,
      theta_star = truth$theta_star,
      keep_best_tx = keep_best_tx
    )
    n_compatible <- if (nrow(screen$results)) sum(screen$results$compatible %||% FALSE) else 0
    if (!isTRUE(enforce_gates) || n_compatible >= 1) {
      abc_bundle <- exdyn_synthetic_abc_bundle(
        summary_obs = summary_obs,
          truth = truth,
          grid_info = grid_info,
        years_vec = years_vec,
        mask = mask,
          screen_cfg = screen_cfg,
          abc_cfg = abc_cfg_use,
          coverage_breaks = coverage_breaks_use
        )
      if (isTRUE(enforce_gates)) {
        gate_table <- dplyr::bind_rows(
          gate_table,
          exdyn_pilot_gate_post(screen$results, abc_bundle$abc, abc_cfg_use, gate_cfg = gate_cfg, skipped = FALSE)
        )
      }
    } else if (isTRUE(enforce_gates)) {
      gate_table <- dplyr::bind_rows(
        gate_table,
        exdyn_pilot_gate_post(screen$results, abc_bundle$abc, abc_cfg_use, gate_cfg = gate_cfg, skipped = TRUE)
      )
    }
  } else if (isTRUE(enforce_gates)) {
    gate_table <- dplyr::bind_rows(
      gate_table,
      exdyn_pilot_gate_post(screen$results, abc_bundle$abc, abc_cfg_use, gate_cfg = gate_cfg, skipped = TRUE)
    )
  }

  list(
    mode = mode,
    summary_obs = summary_obs,
    summary_counts = counts,
    pilot_gates = gate_table,
    screen_results = screen$results,
    best_index = screen$best_index,
    best_tx = screen$best_tx,
    abc = abc_bundle$abc,
    abc_summary = abc_bundle$abc_summary
  )
}

exdyn_write_synthetic_outputs <- function(mode_runs, truth, grid_info, output_root) {
  if (is.null(truth) || !length(mode_runs)) {
    return(character())
  }
  out_paths <- character()
  plot_and_save <- function(mat, title, path) {
    if (is.null(mat)) return(NULL)
    p <- exdyn_plot_surface(mat, grid_info, title)
    ggplot2::ggsave(path, p, width = 6, height = 7, dpi = 150)
    path
  }
  for (run in mode_runs) {
    mode <- run$mode %||% "mode"
    mode_dir <- file.path(output_root, mode)
    dir.create(mode_dir, recursive = TRUE, showWarnings = FALSE)
    screen_path <- file.path(mode_dir, "screen_results.csv")
    readr::write_csv(run$screen_results, screen_path)
    out_paths <- c(out_paths, screen_path)
    abc_path <- file.path(mode_dir, "abc_posterior.csv")
    readr::write_csv(run$abc$samples %||% tibble::tibble(), abc_path)
    out_paths <- c(out_paths, abc_path)
    abc_summary_path <- file.path(mode_dir, "abc_summary.csv")
    readr::write_csv(run$abc_summary %||% tibble::tibble(), abc_summary_path)
    out_paths <- c(out_paths, abc_summary_path)
    summary_path <- file.path(mode_dir, "summary_obs.csv")
    summary_vec <- run$summary_obs
    if (!is.null(run$summary_counts)) {
      summary_vec <- c(summary_vec, run$summary_counts)
    }
    readr::write_csv(tibble::enframe(summary_vec, name = "statistic", value = "value"), summary_path)
    out_paths <- c(out_paths, summary_path)
    theta_path <- file.path(mode_dir, "theta_star.yaml")
    yaml::write_yaml(truth$theta_star, theta_path)
    out_paths <- c(out_paths, theta_path)
    obs_path <- file.path(mode_dir, "TX_obs_syn.png")
    true_path <- file.path(mode_dir, "TX_true_syn.png")
    best_path <- file.path(mode_dir, "TX_best_syn.png")
    diff_path <- file.path(mode_dir, "TX_diff_syn.png")
    if (is.null(run$best_tx)) {
      if (file.exists(best_path)) unlink(best_path)
      if (file.exists(diff_path)) unlink(diff_path)
    }
    out_paths <- c(
      out_paths,
      plot_and_save(truth$TX_obs, "Synthetic TX_obs", obs_path),
      plot_and_save(truth$TX_true, "Synthetic TX_true", true_path),
      plot_and_save(run$best_tx, "Best simulated TX", best_path)
    )
    if (!is.null(run$best_tx)) {
      diff_mat <- run$best_tx - truth$TX_true
      out_paths <- c(out_paths, plot_and_save(diff_mat, "Best - true (years)", diff_path))
    }
  }
  out_paths[!vapply(out_paths, is.null, logical(1))]
}
