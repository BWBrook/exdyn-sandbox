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
    tar_target_raw("synthetic_cfg_file", rlang::expr(!!cfg_path), format = "file"),
    tar_target(synthetic_env, exdyn_synthetic_env_snapshot(), cue = tar_cue("always")),
    tar_target(synthetic_cfg, {
      synthetic_log_start
      exdyn_synthetic_cfg_apply_overrides(yaml::read_yaml(synthetic_cfg_file), synthetic_env)
    }),
    tar_target(synthetic_grid_cfg, synthetic_cfg$grid %||% list(type = "pilot")),
    tar_target(synthetic_arrival_source, {
      tolower(synthetic_grid_cfg$arrival_source %||% "real")
    }),
    tar_target(synthetic_years, {
      years_cfg <- synthetic_cfg$years %||% "pilot"
      if (is.character(years_cfg) && identical(years_cfg, "pilot")) {
        years_cfg <- pilot_cfg$pilot$years
      }
      if (length(years_cfg) == 2L) {
        seq.int(years_cfg[1], years_cfg[2])
      } else {
        sort(unique(as.integer(years_cfg)))
      }
    }),
    tar_target(synthetic_years_range, range(synthetic_years)),
    tar_target(synthetic_grid_bundle, {
      grid_cfg <- synthetic_grid_cfg %||% list(type = "pilot")
      grid_type <- grid_cfg$type %||% "pilot"
      if (identical(grid_type, "pilot")) {
        list(
          grid_info = pilot_grid_info,
          arrivals = pilot_mink_arrivals
        )
      } else if (identical(grid_type, "toy")) {
        arr_cfg <- grid_cfg$arrival %||% list()
        grid <- exdyn_perf_make_grid(
          nx = grid_cfg$nx %||% 25,
          ny = grid_cfg$ny %||% 25,
          cell_km = grid_cfg$cell_km %||% 10,
          riparian_frac = grid_cfg$riparian_frac %||% 0.6,
          region_n = grid_cfg$region_n %||% 3,
          region_labels = grid_cfg$region_labels %||% NULL,
          seed = grid_cfg$seed %||% 101
        )
        arrivals <- exdyn_perf_arrival_table(
          grid_info = grid$grid_info,
          years = synthetic_years,
          pattern = arr_cfg$pattern %||% "gradient",
          noise_sd = arr_cfg$noise_sd %||% 1.5,
          span_frac = arr_cfg$span_frac %||% 0.75,
          seed = (grid_cfg$seed %||% 101) + 11
        )
        list(
          grid_info = grid$grid_info,
          arrivals = arrivals
        )
      } else {
        stop("synthetic grid type must be 'pilot' or 'toy'")
      }
    }),
    tar_target(synthetic_grid_info, synthetic_grid_bundle$grid_info),
    tar_target(synthetic_arrivals_real, synthetic_grid_bundle$arrivals),
    tar_target(synthetic_arrivals, {
      exdyn_synthetic_arrival_table(
        arrivals = synthetic_arrivals_real,
        grid_info = synthetic_grid_info,
        years = synthetic_years,
        source = synthetic_arrival_source,
        seed = synthetic_recovery_cfg$seed %||% 1234
      )
    }),
    tar_target(synthetic_modes, exdyn_synthetic_modes(synthetic_cfg)),
    tar_target(synthetic_recovery_cfg, synthetic_cfg$recovery %||% list(n_reps = 1L, seed = 1234L, reference_rep = 1L)),
    tar_target(synthetic_pilot_gates, {
      cfg <- synthetic_cfg$pilot_gates %||% list()
      if (!is.null(cfg$enabled)) {
        return(isTRUE(cfg$enabled))
      }
      identical(synthetic_grid_cfg$type %||% "pilot", "pilot")
    }),
    tar_target(synthetic_theta_star, synthetic_cfg$theta_star),
    tar_target(synthetic_noise_cfg, synthetic_cfg$noise),
    tar_target(synthetic_tx_cfg, synthetic_cfg$tx_cfg),
    tar_target(synthetic_screen_cfg, synthetic_cfg$screen),
    tar_target(synthetic_compat_cfg, synthetic_cfg$compat),
    tar_target(synthetic_abc_cfg, synthetic_cfg$abc),
    tar_target(synthetic_viability_cfg, synthetic_cfg$viability %||% list(enabled = FALSE)),
    tar_target(synthetic_coverage_breaks, {
      cfg <- synthetic_cfg$coverage_breaks %||% NULL
      if (is.null(cfg)) {
        exdyn_coverage_breaks(synthetic_years)
      } else {
        cfg
      }
    }),
    tar_target(synthetic_mask, {
      mask_cfg <- synthetic_cfg$mask %||% "riparian"
      if (identical(mask_cfg, "all")) {
        mask <- matrix(FALSE, nrow = synthetic_grid_info$nx, ncol = synthetic_grid_info$ny)
        lookup <- synthetic_grid_info$lookup
        idx <- cbind(lookup$row_idx, lookup$col_idx)
        mask[idx] <- TRUE
        mask
      } else if (identical(mask_cfg, "riparian")) {
        synthetic_grid_info$riparian_matrix %||% matrix(TRUE, nrow = synthetic_grid_info$nx, ncol = synthetic_grid_info$ny)
      } else {
        stop("synthetic mask must be 'all' or 'riparian'")
      }
    }),
    tar_target(synthetic_output_root, {
      dir <- file.path("outputs", "synthetic")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }, format = "file"),
    tar_target(synthetic_viability_sweep, {
      if (!isTRUE(synthetic_viability_cfg$enabled)) {
        return(tibble::tibble())
      }
      T_P <- exdyn_arrival_matrix(
        arrivals = synthetic_arrivals,
        grid_info = synthetic_grid_info,
        years = synthetic_years,
        delta_region = synthetic_theta_star$delta_region
      )
      exdyn_viability_sweep(
        theta_star = synthetic_theta_star,
        sweep_cfg = synthetic_viability_cfg,
        grid_info = synthetic_grid_info,
        years = synthetic_years,
        T_P = T_P,
        mask = synthetic_mask,
        K0 = synthetic_screen_cfg$K0
      )
    }),
    tar_target(synthetic_viability_sweep_csv, {
      if (!nrow(synthetic_viability_sweep)) {
        return(character())
      }
      out_path <- file.path(synthetic_output_root, "viability_sweep.csv")
      readr::write_csv(synthetic_viability_sweep, out_path)
      out_path
    }, format = "file"),
    tar_target(synthetic_viability_sweep_plot, {
      if (!nrow(synthetic_viability_sweep)) {
        return(character())
      }
      plot_path <- file.path(synthetic_output_root, "viability_sweep_plot.png")
      plot_df <- synthetic_viability_sweep
      p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = pred_scale, y = pred_c, fill = coverage_true)) +
        ggplot2::geom_tile(color = "white") +
        ggplot2::geom_text(ggplot2::aes(label = n_TX_true), color = "black", size = 3) +
        ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey80") +
        ggplot2::labs(
          title = "Pilot viability sweep: coverage_true (labels = n_TX_true)",
          x = "pred_scale",
          y = "pred_c",
          fill = "Coverage"
        ) +
        ggplot2::theme_minimal()
      ggplot2::ggsave(plot_path, p, width = 6, height = 5, dpi = 150)
      plot_path
    }, format = "file"),
    tar_target(synthetic_arrival_diagnostics, {
      sources <- c("real", "synthetic_plane", "synthetic_gradient")
      diag_tbl <- purrr::map_dfr(sources, function(src) {
        arrivals_tbl <- exdyn_synthetic_arrival_table(
          arrivals = synthetic_arrivals_real,
          grid_info = synthetic_grid_info,
          years = synthetic_years,
          source = src,
          seed = synthetic_recovery_cfg$seed %||% 1234
        )
        T_P <- exdyn_arrival_matrix(
          arrivals = arrivals_tbl,
          grid_info = synthetic_grid_info,
          years = synthetic_years,
          delta_region = NULL
        )
        stats <- exdyn_arrival_coverage_stats(T_P, mask = synthetic_mask)
        tibble::tibble(
          source = src,
          n_cells = stats$n_cells,
          n_finite = stats$n_finite,
          frac_finite = stats$frac_finite,
          n_mask = stats$n_mask,
          n_finite_mask = stats$n_finite_mask,
          frac_finite_mask = stats$frac_finite_mask
        )
      })
      diag_path <- file.path(synthetic_output_root, "pilot_diagnostics.csv")
      readr::write_csv(diag_tbl, diag_path)
      diag_path
    }, format = "file"),
    tar_target(synthetic_arrival_plots, {
      sources <- c("real", "synthetic_plane", "synthetic_gradient")
      out_paths <- purrr::map_chr(sources, function(src) {
        arrivals_tbl <- exdyn_synthetic_arrival_table(
          arrivals = synthetic_arrivals_real,
          grid_info = synthetic_grid_info,
          years = synthetic_years,
          source = src,
          seed = synthetic_recovery_cfg$seed %||% 1234
        )
        T_P <- exdyn_arrival_matrix(
          arrivals = arrivals_tbl,
          grid_info = synthetic_grid_info,
          years = synthetic_years,
          delta_region = NULL
        )
        plot_path <- file.path(synthetic_output_root, sprintf("arrival_%s.png", src))
        p <- exdyn_plot_surface(T_P, synthetic_grid_info, sprintf("Arrival surface (%s)", src))
        ggplot2::ggsave(plot_path, p, width = 6, height = 7, dpi = 150)
        plot_path
      })
      out_paths
    }, format = "file"),
    tar_target(synthetic_arrival_realism_cfg, synthetic_cfg$arrival_realism %||% list(enabled = FALSE)),
    tar_target(synthetic_arrival_realism_comparison, {
      cfg <- synthetic_arrival_realism_cfg %||% list()
      if (!isTRUE(cfg$enabled)) {
        return(tibble::tibble())
      }
      exdyn_arrival_realism_comparison(
        arrivals_real = synthetic_arrivals_real,
        grid_info = synthetic_grid_info,
        years_vec = synthetic_years,
        mask = synthetic_mask,
        theta_star = synthetic_theta_star,
        noise_cfg = synthetic_noise_cfg,
        tx_cfg = synthetic_tx_cfg,
        screen_cfg = synthetic_screen_cfg,
        compat_cfg = synthetic_compat_cfg,
        abc_cfg = synthetic_abc_cfg,
        coverage_breaks = synthetic_coverage_breaks,
        recovery_cfg = synthetic_recovery_cfg,
        cfg = cfg
      )
    }),
    tar_target(synthetic_arrival_realism_comparison_csv, {
      if (!nrow(synthetic_arrival_realism_comparison)) {
        return(NA_character_)
      }
      out_path <- file.path(synthetic_output_root, "arrival_realism_comparison.csv")
      readr::write_csv(synthetic_arrival_realism_comparison, out_path)
      out_path
    }, format = "file"),
    tar_target(synthetic_rep_grid, exdyn_synthetic_rep_grid(synthetic_recovery_cfg)),
    tar_target(synthetic_theta_lhs, {
      cell_km <- synthetic_grid_info$cell_km %||% 10
      exdyn_param_lhs(synthetic_screen_cfg, n = synthetic_screen_cfg$n_draws, cell_km = cell_km, seed = synthetic_screen_cfg$seed %||% 123)
    }),
    tar_target(synthetic_theta_all, {
      cell_km <- synthetic_grid_info$cell_km %||% 10
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
    tar_target(synthetic_theta_bounds, exdyn_param_bounds(synthetic_screen_cfg, cell_km = synthetic_grid_info$cell_km %||% 10)),
    tar_target(synthetic_truths, {
      rep_grid <- synthetic_rep_grid
      truths <- list()
      for (i in seq_len(nrow(rep_grid))) {
        replicate_id <- rep_grid$replicate[i]
        seed <- rep_grid$seed[i]
        set.seed(seed)
        truth <- exdyn_make_synthetic(
          theta_star = synthetic_theta_star,
          noise_cfg = synthetic_noise_cfg,
          arrivals = synthetic_arrivals,
          grid_info = synthetic_grid_info,
          years = synthetic_years_range,
          tx_cfg = synthetic_tx_cfg,
          K0 = synthetic_screen_cfg$K0,
          mask = synthetic_mask
        )
        truth$N_true <- NULL
        truth$tx_counts <- NULL
        truth$tx_table <- NULL
        truth$po_points <- NULL
        truth$effort_points <- NULL
        truth$replicate <- replicate_id
        truth$seed <- seed
        truths[[as.character(replicate_id)]] <- truth
        gc()
      }
      truths
    }, deployment = "main"),
    tar_target(synthetic_mode_runs, {
      rep_grid <- synthetic_rep_grid
      modes <- synthetic_modes
      ref_id <- synthetic_recovery_cfg$reference_rep %||% 1L
      runs <- list()
      for (i in seq_len(nrow(rep_grid))) {
        replicate_id <- rep_grid$replicate[i]
        truth <- synthetic_truths[[as.character(replicate_id)]]
        if (is.null(truth)) next
        for (mode in modes) {
          keep_best <- replicate_id == ref_id
          res <- exdyn_synthetic_mode_run(
            truth = truth,
            mode = mode,
            grid_info = synthetic_grid_info,
            years_vec = synthetic_years,
            mask = synthetic_mask,
            theta_tbl = synthetic_theta_all,
            screen_cfg = synthetic_screen_cfg,
            compat_cfg = synthetic_compat_cfg,
            abc_cfg = synthetic_abc_cfg,
            coverage_breaks = synthetic_coverage_breaks,
            keep_best_tx = keep_best,
            enforce_gates = synthetic_pilot_gates
          )
          res$replicate <- replicate_id
          res$seed <- truth$seed %||% rep_grid$seed[i]
          runs[[length(runs) + 1L]] <- res
        }
        gc()
      }
      runs
    }, deployment = "main"),
    tar_target(synthetic_runs, list(truths = synthetic_truths, runs = synthetic_mode_runs)),
    tar_target(synthetic_reference_truth, {
      ref_id <- synthetic_recovery_cfg$reference_rep %||% 1L
      synthetic_truths[[as.character(ref_id)]]
    }),
    tar_target(synthetic_reference_runs, {
      ref_id <- synthetic_recovery_cfg$reference_rep %||% 1L
      runs <- purrr::keep(synthetic_mode_runs, ~ .x$replicate == ref_id)
      mode_order <- synthetic_modes %||% character()
      if (length(runs) && length(mode_order)) {
        ord <- order(match(purrr::map_chr(runs, "mode"), mode_order))
        runs <- runs[ord]
      }
      runs
    }),
    tar_target(synthetic_outputs_written, {
      out_paths <- exdyn_write_synthetic_outputs(
        synthetic_reference_runs,
        synthetic_reference_truth,
        synthetic_grid_info,
        synthetic_output_root
      )
      extra_paths <- c(
        synthetic_arrival_diagnostics,
        synthetic_arrival_plots,
        synthetic_arrival_realism_comparison_csv,
        synthetic_viability_sweep_csv,
        synthetic_viability_sweep_plot
      )
      extra_paths <- extra_paths[!is.na(extra_paths)]
      c(out_paths, extra_paths)
    }, format = "file"),
    tar_target(synthetic_recovery_tables, {
      exdyn_synthetic_recovery_tables(synthetic_mode_runs, synthetic_screen_cfg, synthetic_abc_cfg)
    }),
    tar_target(synthetic_recovery_written, {
      exdyn_write_synthetic_recovery_tables(synthetic_recovery_tables, synthetic_output_root)
    }, format = "file"),
    tar_target(synthetic_report_html, {
      synthetic_outputs_written
      synthetic_recovery_written
      quarto::quarto_render("reports/synthetic_mink_vole.qmd", output_format = "html")
    }, format = "file"),
    tar_target(synthetic_report_pdf, {
      synthetic_outputs_written
      synthetic_recovery_written
      quarto::quarto_render("reports/synthetic_mink_vole.qmd", output_format = "pdf")
    }, format = "file"),
    tar_target(synthetic_canonical_cfg, {
      synthetic_cfg$canonical %||% list()
    }),
    tar_target(synthetic_canonical_dir, {
      cfg <- synthetic_canonical_cfg
      if (!isTRUE(cfg$enabled)) {
        return(NULL)
      }
      root <- cfg$root %||% file.path("outputs", "canonical")
      milestone <- cfg$milestone %||% "0.3"
      wp_id <- cfg$wp_id %||% "WP-0.3.1"
      run_id <- cfg$run_id %||% exdyn_make_run_id("syn")
      exdyn_canonical_run_dir(root, milestone, wp_id, run_id)
    }),
    tar_target(synthetic_canonical_manifest, {
      cfg <- synthetic_canonical_cfg
      canonical_dir <- synthetic_canonical_dir
      if (is.null(canonical_dir)) {
        return(NULL)
      }
      snapshot_path <- file.path(canonical_dir, "config", "synthetic.yaml")
      exdyn_write_config_snapshot(synthetic_cfg, snapshot_path)
      session_path <- file.path(canonical_dir, "session_info.txt")
      exdyn_write_session_info(session_path)
      outputs <- c(
        synthetic_outputs_written,
        synthetic_recovery_written,
        synthetic_report_html,
        synthetic_report_pdf
      )
      copied <- exdyn_copy_to_canonical(outputs, canonical_dir)
      manifest <- list(
        schema_version = exdyn_schema_version(),
        commit_sha = exdyn_git_sha(),
        run_id = basename(canonical_dir),
        run_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        milestone = cfg$milestone %||% "0.3",
        wp_id = cfg$wp_id %||% "WP-0.3.1",
        config_snapshots = list(synthetic = exdyn_relative_path(snapshot_path, canonical_dir)),
        seeds = list(
          screen_seed = synthetic_screen_cfg$seed %||% NA_integer_,
          recovery_seed = synthetic_recovery_cfg$seed %||% NA_integer_,
          abc_lhs_seed = synthetic_abc_cfg$lhs$seed %||% NA_integer_
        ),
        commands = cfg$commands %||% character()
      )
      manifest$outputs <- sort(unique(exdyn_relative_path(copied, canonical_dir)))
      exdyn_write_manifest(manifest, file.path(canonical_dir, "manifest.yaml"))
    }, format = "file")
  )
  tar_list
}
