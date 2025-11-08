# Synthetic mink → vole twin targets -------------------------------------------------

targets_synthetic_mink_vole <- function(cfg_path = "config/synthetic.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  synthetic_log_start_target <- tar_target(
    synthetic_log_start,
    {
      dir.create("logs", showWarnings = FALSE)
      msg <- sprintf("[%s] WO10 synthetic twin start", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      cat(msg, "\n", file = file.path("logs", "wo10.log"), append = TRUE)
      msg
    },
    cue = tar_cue("always"),
    deployment = "main"
  )

  tar_list <- list(
    synthetic_log_start_target,
    tar_target_raw(
      "synthetic_cfg",
      rlang::expr({
        synthetic_log_start
        yaml::read_yaml(!!cfg_path)
      })
    ),
    tar_target(synthetic_theta_star, synthetic_cfg$theta_star),
    tar_target(synthetic_noise_cfg, synthetic_cfg$noise),
    tar_target(synthetic_tx_cfg, synthetic_cfg$tx_cfg),
    tar_target(synthetic_screen_cfg, synthetic_cfg$screen),
    tar_target(synthetic_compat_cfg, synthetic_cfg$compat),
    tar_target(synthetic_abc_cfg, synthetic_cfg$abc),
    tar_target(synthetic_years, seq.int(pilot_cfg$pilot$years[1], pilot_cfg$pilot$years[2])),
    tar_target(synthetic_coverage_breaks, {
      yrs <- synthetic_years
      if (length(yrs) < 2) {
        numeric()
      } else {
        seq(min(yrs), max(yrs), length.out = 6L)[2:5]
      }
    }),
    tar_target(synthetic_mask, {
      mask_cfg <- synthetic_cfg$mask %||% "riparian"
      if (identical(mask_cfg, "all")) {
        matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      } else if (identical(mask_cfg, "riparian")) {
        pilot_grid_info$riparian_matrix %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      } else {
        stop("synthetic mask must be 'all' or 'riparian'")
      }
    }),
    tar_target(synthetic_truth, {
      exdyn_make_synthetic(
        theta_star = synthetic_theta_star,
        noise_cfg = synthetic_noise_cfg,
        arrivals = pilot_mink_arrivals,
        grid_info = pilot_grid_info,
        years = pilot_cfg$pilot$years,
        tx_cfg = synthetic_tx_cfg,
        K0 = synthetic_screen_cfg$K0,
        mask = synthetic_mask
      )
    }, deployment = "main"),
    tar_target(synthetic_summary_truth, exdyn_summary_tx_response(
      synthetic_truth$TX_obs,
      synthetic_truth$T_P,
      years = synthetic_years,
      coverage_breaks = synthetic_coverage_breaks
    )),
    tar_target(synthetic_output_dir, {
      dir <- file.path("outputs", "synthetic")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }, format = "file"),
    tar_target(synthetic_theta_lhs, {
      cell_km <- pilot_grid_info$cell_km %||% 10
      exdyn_param_lhs(synthetic_screen_cfg, n = synthetic_screen_cfg$n_draws, cell_km = cell_km, seed = synthetic_screen_cfg$seed %||% 123)
    }),
    tar_target(synthetic_theta_all, {
      cell_km <- pilot_grid_info$cell_km %||% 10
      truth_row <- tibble::tibble(
        draw = 0L,
        alpha = synthetic_theta_star$alpha,
        disp_mean_km = synthetic_theta_star$disp_mean_km,
        disp_mean_cells = synthetic_theta_star$disp_mean_km / cell_km,
        A_over_K = synthetic_theta_star$A_over_K,
        pred_c = synthetic_theta_star$pred_c,
        pred_h = synthetic_theta_star$pred_h,
        ramp_years = synthetic_theta_star$ramp_years,
        pred_scale = synthetic_theta_star$pred_scale,
        gamma = synthetic_theta_star$gamma,
        rmax = synthetic_theta_star$rmax,
        K0 = synthetic_screen_cfg$K0
      )
      delta_lookup <- synthetic_theta_star$delta_region %||% list()
      if (length(delta_lookup)) {
        for (nm in names(delta_lookup)) {
          truth_row[[paste0("delta_", nm)]] <- delta_lookup[[nm]]
        }
      }
      dplyr::bind_rows(truth_row, synthetic_theta_lhs)
    }),
    tar_target(synthetic_theta_bounds, exdyn_param_bounds(synthetic_screen_cfg, cell_km = pilot_grid_info$cell_km %||% 10)),
    tar_target(synthetic_screen, {
      theta_tbl <- synthetic_theta_all
      mask <- synthetic_mask
      years_vec <- synthetic_years
      delta_cols <- names(theta_tbl)[grepl("^delta_", names(theta_tbl))]
      results <- vector("list", nrow(theta_tbl))
      tx_list <- vector("list", nrow(theta_tbl))
      cell_km <- pilot_grid_info$cell_km %||% 10
      for (i in seq_len(nrow(theta_tbl))) {
        theta_row <- theta_tbl[i, ]
        delta_lookup <- NULL
        if (length(delta_cols)) {
          delta_lookup <- purrr::map_dbl(delta_cols, ~ theta_row[[.x]])
          names(delta_lookup) <- gsub("^delta_", "", delta_cols)
        }
        T_P_adj <- exdyn_adjust_arrival_matrix(synthetic_truth$T_P, pilot_grid_info, delta_lookup, years_vec)
        if (any(!mask)) {
          T_P_adj[!mask] <- NA_real_
        }
        pars <- list(
          rmax = theta_row$rmax,
          A_frac = theta_row$A_over_K * synthetic_screen_cfg$K0,
          beta_H = 0,
          d = 0.02
        )
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = years_vec,
          T_P = T_P_adj,
          ramp_years = round(theta_row$ramp_years),
          pars = pars,
          K0 = synthetic_screen_cfg$K0,
          alpha = theta_row$alpha,
          disp_mean_cells = theta_row$disp_mean_cells,
          pred = list(
            type = synthetic_theta_star$pred_type %||% "II",
            c = theta_row$pred_c,
            h = theta_row$pred_h,
            scale = theta_row$pred_scale,
            gamma = theta_row$gamma
          ),
          pre_leak = synthetic_theta_star$pre_leak %||% 0,
          mask = mask
        )
        TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) {
          TX_years[idx] <- years_vec[TX_idx[idx]]
        }
        TX_years[!mask] <- NA_real_
        metrics <- exdyn_score(
          synthetic_truth$TX_obs,
          T_P_adj,
          TX_years,
          synthetic_compat_cfg,
          coverage_breaks = synthetic_coverage_breaks
        )
        coverage_sim <- if (any(mask)) mean(is.finite(TX_years[mask]), na.rm = TRUE) else NA_real_
        result_row <- dplyr::bind_cols(theta_row, metrics) %>%
          dplyr::mutate(coverage_sim = coverage_sim)
        results[[i]] <- result_row
        tx_list[[i]] <- TX_years
        gc()
      }
      res_df <- dplyr::bind_rows(results) %>%
        dplyr::arrange(coverage_sim < 0.2, loss, dplyr::desc(coverage_sim)) %>%
        dplyr::mutate(rank = dplyr::row_number())
      list(results = res_df, tx_sim = tx_list)
    }, deployment = "main"),
    tar_target(synthetic_screen_results, synthetic_screen$results),
    tar_target(synthetic_best_index, {
      which.min(synthetic_screen_results$loss)
    }),
    tar_target(synthetic_best_tx, {
      idx <- synthetic_best_index
      if (length(idx) && !is.na(idx)) synthetic_screen$tx_sim[[idx]] else NULL
    }),
    tar_target(synthetic_summary_obs, exdyn_summary_tx_response(
      synthetic_truth$TX_obs,
      synthetic_truth$T_P,
      years = synthetic_years,
      coverage_breaks = synthetic_coverage_breaks
    )),
    tar_target(synthetic_abc_lhs_scan, {
      lhs_n <- synthetic_abc_cfg$lhs$n %||% 0
      if (lhs_n <= 0) {
        return(tibble::tibble())
      }
      cell_km <- pilot_grid_info$cell_km %||% 10
      lhs_draws <- exdyn_param_lhs(
        synthetic_screen_cfg,
        n = lhs_n,
        cell_km = cell_km,
        seed = synthetic_abc_cfg$lhs$seed %||% 2026
      )
      mask <- synthetic_mask
      results <- vector("list", nrow(lhs_draws))
      scale_vec <- synthetic_abc_cfg$scale %||% NULL
      S_obs <- synthetic_summary_obs
      if (!is.null(scale_vec)) {
        scale_vec <- unlist(scale_vec[names(S_obs)], use.names = FALSE)
      } else {
        scale_vec <- pmax(abs(S_obs), 1e-6)
      }
      for (i in seq_len(nrow(lhs_draws))) {
        theta_row <- lhs_draws[i, ]
        delta_cols <- names(theta_row)[grepl("^delta_", names(theta_row))]
        delta_lookup <- NULL
        if (length(delta_cols)) {
          delta_lookup <- purrr::map_dbl(delta_cols, ~ theta_row[[.x]])
          names(delta_lookup) <- gsub("^delta_", "", delta_cols)
        }
        T_P_adj <- exdyn_adjust_arrival_matrix(
          synthetic_truth$T_P,
          pilot_grid_info,
          delta_lookup,
          synthetic_years
        )
        if (any(!mask)) {
          T_P_adj[!mask] <- NA_real_
        }
        pars <- list(
          rmax = theta_row$rmax,
          A_frac = theta_row$A_over_K * synthetic_screen_cfg$K0,
          beta_H = 0,
          d = 0.02
        )
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = synthetic_years,
          T_P = T_P_adj,
          ramp_years = round(theta_row$ramp_years),
          pars = pars,
          K0 = synthetic_screen_cfg$K0,
          alpha = theta_row$alpha,
          disp_mean_cells = theta_row$disp_mean_cells,
          pred = list(
            type = synthetic_theta_star$pred_type %||% "II",
            c = theta_row$pred_c,
            h = theta_row$pred_h,
            scale = theta_row$pred_scale,
            gamma = theta_row$gamma
          ),
          pre_leak = synthetic_theta_star$pre_leak %||% 0,
          mask = mask
        )
        TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) {
          TX_years[idx] <- synthetic_years[TX_idx[idx]]
        }
        TX_years[!mask] <- NA_real_
        S_sim <- exdyn_summary_tx_response(
          TX_years,
          T_P_adj,
          years = synthetic_years,
          coverage_breaks = synthetic_coverage_breaks
        )
        S_sim <- S_sim[names(S_obs)]
        dist <- sqrt(sum(((S_sim - S_obs) / scale_vec)^2))
        results[[i]] <- dplyr::bind_cols(theta_row, tibble::tibble(distance = dist))
      }
      dplyr::bind_rows(results)
    }),
    tar_target(synthetic_abc_seed_bank, {
      scan_tbl <- synthetic_abc_lhs_scan
      keep <- synthetic_abc_cfg$lhs$keep %||% 0
      if (!nrow(scan_tbl) || keep <= 0) {
        tibble::tibble()
      } else {
        scan_tbl %>% dplyr::arrange(distance) %>% dplyr::slice_head(n = min(keep, nrow(scan_tbl)))
      }
    }),
    tar_target(synthetic_prior_sampler, {
      prior_cfg <- synthetic_abc_cfg$prior %||% list()
      delta_bounds <- prior_cfg$delta_region %||% synthetic_screen_cfg$delta_region
      scalar_bounds <- prior_cfg[setdiff(names(prior_cfg), "delta_region")]
      base_sampler <- exdyn_prior_sampler_syn(scalar_bounds, delta_bounds)
      seed_bank <- synthetic_abc_seed_bank
      bounds <- synthetic_theta_bounds
      jitter_sd <- synthetic_abc_cfg$lhs$jitter_sd %||% 0.05
      seed_prob <- synthetic_abc_cfg$lhs$seed_prob %||% 0.5
      param_cols <- names(bounds)
      sampler_from_bank <- function() {
        if (!nrow(seed_bank)) return(NULL)
        row <- seed_bank[sample(nrow(seed_bank), 1), , drop = FALSE]
        theta <- as.list(row[1, param_cols[param_cols %in% names(row)], drop = FALSE])
        if (!length(theta)) return(NULL)
        theta <- exdyn_theta_jitter(theta, bounds, jitter_sd)
        theta
      }
      function() {
        use_seed <- nrow(seed_bank) > 0 && runif(1) < seed_prob
        if (use_seed) {
          theta <- sampler_from_bank()
          if (!is.null(theta)) return(theta)
        }
        base_sampler()
      }
    }),
    tar_target(synthetic_abc, {
      S_obs <- synthetic_summary_obs
      scale_vec <- synthetic_abc_cfg$scale %||% NULL
      if (!is.null(scale_vec)) {
        scale_vec <- unlist(scale_vec[names(S_obs)], use.names = FALSE)
      }
      cell_km <- pilot_grid_info$cell_km %||% 10
      simulate_once <- function(theta) {
        delta_lookup <- theta$delta_region %||% list()
        T_P_adj <- exdyn_adjust_arrival_matrix(synthetic_truth$T_P, pilot_grid_info, delta_lookup, synthetic_years)
        if (any(!synthetic_mask)) {
          T_P_adj[!synthetic_mask] <- NA_real_
        }
        pars <- list(
          rmax = theta$rmax,
          A_frac = theta$A_over_K * synthetic_screen_cfg$K0,
          beta_H = 0,
          d = 0.02
        )
        disp_cells <- theta$disp_mean_km / cell_km
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = synthetic_years,
          T_P = T_P_adj,
          ramp_years = round(theta$ramp_years),
          pars = pars,
          K0 = synthetic_screen_cfg$K0,
          alpha = theta$alpha,
          disp_mean_cells = disp_cells,
          pred = list(
            type = synthetic_theta_star$pred_type %||% "II",
            c = theta$pred_c,
            h = theta$pred_h,
            scale = theta$pred_scale,
            gamma = theta$gamma
          ),
          pre_leak = synthetic_theta_star$pre_leak %||% 0,
          mask = synthetic_mask
        )
        TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) {
          TX_years[idx] <- synthetic_years[TX_idx[idx]]
        }
        TX_years[!synthetic_mask] <- NA_real_
        list(TX_sim = TX_years, T_P = T_P_adj)
      }
      summary_fn <- function(sim) {
        exdyn_summary_tx_response(
          sim$TX_sim,
          sim$T_P,
          years = synthetic_years,
          coverage_breaks = synthetic_coverage_breaks
        )
      }
      exdyn_abc_rejection(
        S_obs = S_obs,
        prior_sampler = synthetic_prior_sampler,
        simulator = simulate_once,
        summary_fn = summary_fn,
        n_sims = synthetic_abc_cfg$n_sims %||% 2000,
        eps = synthetic_abc_cfg$eps %||% 1,
        scale = scale_vec,
        progress = TRUE
      )
    }, deployment = "main"),
    tar_target(synthetic_abc_refined, {
      if (!nrow(synthetic_abc$samples)) {
        return(list(samples = tibble::tibble(), summaries = tibble::tibble(), distances = numeric(), all = tibble::tibble(), eps = synthetic_abc_cfg$eps_tight %||% 0.5, scale = synthetic_abc$scale))
      }
      eps_tight <- synthetic_abc_cfg$eps_tight %||% ((synthetic_abc_cfg$eps %||% 1) * 0.5)
      bounds <- synthetic_theta_bounds
      jitter_sd <- synthetic_abc_cfg$lhs$jitter_sd %||% 0.05
      mix_prob <- synthetic_abc_cfg$lhs$seed_prob %||% 0.65
      particles <- synthetic_abc$samples
      if (!nrow(particles)) return(synthetic_abc)
      base_param_names <- c("alpha","disp_mean_km","A_over_K","pred_c","pred_h","ramp_years","pred_scale","gamma","rmax")
      to_theta <- function(row) {
        theta <- list()
        for (nm in base_param_names) {
          if (nm %in% names(row)) {
            theta[[nm]] <- as.numeric(row[[nm]][1])
          }
        }
        theta$K0 <- synthetic_screen_cfg$K0
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
        synthetic_prior_sampler()
      }
      S_obs <- synthetic_summary_obs
      scale_vec <- synthetic_abc_cfg$scale %||% NULL
      if (!is.null(scale_vec)) {
        scale_vec <- unlist(scale_vec[names(S_obs)], use.names = FALSE)
      }
      cell_km <- pilot_grid_info$cell_km %||% 10
      simulate_once <- function(theta) {
        delta_lookup <- theta$delta_region %||% list()
        T_P_adj <- exdyn_adjust_arrival_matrix(synthetic_truth$T_P, pilot_grid_info, delta_lookup, synthetic_years)
        if (any(!synthetic_mask)) {
          T_P_adj[!synthetic_mask] <- NA_real_
        }
        pars <- list(
          rmax = theta$rmax,
          A_frac = theta$A_over_K * synthetic_screen_cfg$K0,
          beta_H = 0,
          d = 0.02
        )
        disp_cells <- theta$disp_mean_km / cell_km
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = synthetic_years,
          T_P = T_P_adj,
          ramp_years = round(theta$ramp_years),
          pars = pars,
          K0 = synthetic_screen_cfg$K0,
          alpha = theta$alpha,
          disp_mean_cells = disp_cells,
          pred = list(
            type = synthetic_theta_star$pred_type %||% "II",
            c = theta$pred_c,
            h = theta$pred_h,
            scale = theta$pred_scale,
            gamma = theta$gamma
          ),
          pre_leak = synthetic_theta_star$pre_leak %||% 0,
          mask = synthetic_mask
        )
        TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) {
          TX_years[idx] <- synthetic_years[TX_idx[idx]]
        }
        TX_years[!synthetic_mask] <- NA_real_
        list(TX_sim = TX_years, T_P = T_P_adj)
      }
      summary_fn <- function(sim) {
        exdyn_summary_tx_response(
          sim$TX_sim,
          sim$T_P,
          years = synthetic_years,
          coverage_breaks = synthetic_coverage_breaks
        )
      }
      exdyn_abc_rejection(
        S_obs = S_obs,
        prior_sampler = refined_sampler,
        simulator = simulate_once,
        summary_fn = summary_fn,
        n_sims = synthetic_abc_cfg$n_sims %||% 2000,
        eps = eps_tight,
        scale = scale_vec,
        progress = TRUE
      )
    }, deployment = "main"),
    tar_target(synthetic_abc_final, {
      if (nrow(synthetic_abc_refined$samples)) synthetic_abc_refined else synthetic_abc
    }),
    tar_target(synthetic_abc_summary, {
      samples <- synthetic_abc_final$samples
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
            p975 = stats::quantile(.x, 0.975, na.rm = TRUE, names = FALSE),
            mean = mean(.x, na.rm = TRUE),
            sd = stats::sd(.x, na.rm = TRUE)
          )
      )
      truth_vals <- synthetic_theta_star[purrr::map_lgl(synthetic_theta_star, is.numeric)]
      truth_vals <- unlist(truth_vals, use.names = TRUE)
      if (!is.null(synthetic_theta_star$delta_region)) {
        truth_vals <- c(truth_vals, unlist(synthetic_theta_star$delta_region))
      }
      truth_tbl <- tibble::enframe(truth_vals, name = "param", value = "truth")
      dplyr::left_join(stats_tbl, truth_tbl, by = "param")
    }),
    tar_target(synthetic_tables_written, {
      results_path <- file.path(synthetic_output_dir, "screen_results.csv")
      readr::write_csv(synthetic_screen_results, results_path)
      abc_path <- file.path(synthetic_output_dir, "abc_posterior.csv")
      if (nrow(synthetic_abc_final$samples)) {
        readr::write_csv(synthetic_abc_final$samples, abc_path)
      } else {
        readr::write_csv(tibble::tibble(), abc_path)
      }
      truth_path <- file.path(synthetic_output_dir, "theta_star.yaml")
      yaml::write_yaml(synthetic_theta_star, truth_path)
      c(results_path, abc_path, truth_path)
    }),
    tar_target(synthetic_maps_written, {
      obs_df <- exdyn_matrix_to_df(synthetic_truth$TX_obs, pilot_grid_info, "tx_obs")
      true_df <- exdyn_matrix_to_df(synthetic_truth$TX_true, pilot_grid_info, "tx_true")
      best_df <- if (!is.null(synthetic_best_tx)) exdyn_matrix_to_df(synthetic_best_tx, pilot_grid_info, "tx_best") else NULL
      diff_df <- if (!is.null(best_df)) {
        merged <- dplyr::left_join(true_df, best_df, by = c("cell_id", "row", "col"))
        merged$tx_diff <- merged$tx_best - merged$tx_true
        merged
      } else NULL
      obs_path <- file.path(synthetic_output_dir, "TX_obs_syn.png")
      true_path <- file.path(synthetic_output_dir, "TX_true_syn.png")
      best_path <- file.path(synthetic_output_dir, "TX_best_syn.png")
      diff_path <- file.path(synthetic_output_dir, "TX_diff_syn.png")
      plot_tile <- function(df, column, title, path) {
        if (is.null(df)) return(NULL)
        p <- ggplot2::ggplot(df, ggplot2::aes_string(x = "col", y = "row", fill = column)) +
          ggplot2::geom_tile() +
          ggplot2::scale_fill_viridis_c(na.value = "grey90") +
          ggplot2::coord_equal() +
          ggplot2::theme_minimal() +
          ggplot2::labs(title = title, fill = "year")
        ggplot2::ggsave(path, p, width = 6, height = 7, dpi = 150)
        path
      }
      paths <- c(
        plot_tile(obs_df, "tx_obs", "Synthetic TX_obs", obs_path),
        plot_tile(true_df, "tx_true", "Synthetic TX_true", true_path),
        plot_tile(best_df, "tx_best", "Best simulated TX", best_path),
        plot_tile(diff_df, "tx_diff", "Best - true (years)", diff_path)
      )
      paths[!vapply(paths, is.null, logical(1))]
    }, format = "file"),
    tar_target(synthetic_report_html, {
      synthetic_tables_written
      synthetic_maps_written
      synthetic_abc_summary
      quarto::quarto_render("reports/synthetic_mink_vole.qmd", output_format = "html")
    }, format = "file"),
    tar_target(synthetic_report_pdf, {
      synthetic_tables_written
      synthetic_maps_written
      synthetic_abc_summary
      quarto::quarto_render("reports/synthetic_mink_vole.qmd", output_format = "pdf")
    }, format = "file")
  )
  tar_list
}
