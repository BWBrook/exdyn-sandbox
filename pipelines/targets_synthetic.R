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
    tar_target(synthetic_benchmark_cfg, synthetic_cfg$benchmark %||% list()),
    tar_target(synthetic_pilot_gates, {
      cfg <- synthetic_cfg$pilot_gates %||% list()
      if (!is.null(cfg$enabled)) {
        return(isTRUE(cfg$enabled))
      }
      identical(synthetic_grid_cfg$type %||% "pilot", "pilot")
    }),
    tar_target(synthetic_theta_star, synthetic_cfg$theta_star),
    tar_target(synthetic_suitability_cfg, synthetic_cfg$suitability %||% list(enabled = FALSE)),
    tar_target(synthetic_suitability_matrix, {
      cfg <- synthetic_suitability_cfg %||% list()
      if (!isTRUE(cfg$enabled)) {
        return(NULL)
      }
      info <- exdyn_soft_suitability_matrix(
        grid_info = synthetic_grid_info,
        method = cfg$method %||% "river_km",
        range = cfg$range %||% c(0.5, 1.5),
        transform = cfg$transform %||% "log1p"
      )
      info$matrix
    }),
    tar_target(synthetic_noise_cfg, {
      cfg <- synthetic_cfg$noise %||% list()
      if (!is.null(synthetic_suitability_matrix)) {
        cfg$scale_matrix <- synthetic_suitability_matrix
      }
      cfg
    }),
    tar_target(synthetic_tx_cfg, synthetic_cfg$tx_cfg),
    tar_target(synthetic_screen_cfg, {
      cfg <- synthetic_cfg$screen %||% list()
      if (!is.null(synthetic_suitability_matrix)) {
        cfg$scale_matrix <- synthetic_suitability_matrix
      }
      cfg
    }),
    tar_target(synthetic_compat_cfg, synthetic_cfg$compat),
    tar_target(synthetic_abc_cfg, {
      cfg <- synthetic_cfg$abc %||% list()
      if (!is.null(synthetic_suitability_matrix)) {
        cfg$scale_matrix <- synthetic_suitability_matrix
      }
      cfg
    }),
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
    tar_target(synthetic_freshness_guard, {
      out_paths <- c(synthetic_arrival_plots, synthetic_viability_sweep_plot)
      exdyn_freshness_guard(out_paths, synthetic_cfg_file, label = "synthetic output")
    }),
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
        return(character())
      }
      out_path <- file.path(synthetic_output_root, "arrival_realism_comparison.csv")
      readr::write_csv(synthetic_arrival_realism_comparison, out_path)
      out_path
    }, format = "file"),
    tar_target(synthetic_mask_philosophy_cfg, synthetic_cfg$mask_philosophy %||% list(enabled = FALSE)),
    tar_target(synthetic_mask_philosophy_outputs, {
      cfg <- synthetic_mask_philosophy_cfg %||% list()
      if (!isTRUE(cfg$enabled)) {
        return(list(table = tibble::tibble(), outputs = character()))
      }
      mask_hard <- synthetic_mask
      hard_sel <- tolower(cfg$hard_mask %||% "")
      if (identical(hard_sel, "riparian")) {
        mask_hard <- synthetic_grid_info$riparian_matrix %||% synthetic_mask
      } else if (identical(hard_sel, "all")) {
        mask_hard <- exdyn_land_mask_from_lookup(synthetic_grid_info)
      }
      exdyn_mask_philosophy_compare(
        arrivals_real = synthetic_arrivals_real,
        grid_info = synthetic_grid_info,
        years_vec = synthetic_years,
        mask_hard = mask_hard,
        theta_star = synthetic_theta_star,
        noise_cfg = synthetic_noise_cfg,
        tx_cfg = synthetic_tx_cfg,
        coverage_breaks = synthetic_coverage_breaks,
        cfg = cfg,
        output_root = synthetic_output_root
      )
    }),
    tar_target(synthetic_mask_philosophy_csv, {
      outputs <- synthetic_mask_philosophy_outputs
      out_paths <- outputs$outputs %||% character()
      csv <- out_paths[grepl("mask_philosophy_compare.csv$", out_paths)]
      if (!length(csv)) {
        return(character())
      }
      csv[1]
    }, format = "file"),
    tar_target(synthetic_ceiling_cfg, synthetic_cfg$ceiling %||% list(enabled = FALSE)),
    tar_target(synthetic_ceiling_outputs, {
      cfg <- synthetic_ceiling_cfg %||% list()
      if (!isTRUE(cfg$enabled)) {
        return(list(replicate_metrics = tibble::tibble(), summary = tibble::tibble(),
                    param = tibble::tibble(), outputs = character()))
      }
      exdyn_ceiling_compare(
        cfg = cfg,
        arrivals_real = synthetic_arrivals_real,
        baseline_runs = synthetic_mode_runs,
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
        output_root = synthetic_output_root
      )
    }),
    tar_target(synthetic_ceiling_summary_csv, {
      outputs <- synthetic_ceiling_outputs
      out_paths <- outputs$outputs %||% character()
      csv <- out_paths[grepl("ceiling_run_summary.csv$", out_paths)]
      if (!length(csv)) {
        return(character())
      }
      csv[1]
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
      n_cores <- synthetic_recovery_cfg$n_cores %||% 1L
      if (!nrow(rep_grid)) return(list())
      n_cores <- suppressWarnings(as.integer(n_cores))
      if (!is.finite(n_cores) || n_cores < 1L) n_cores <- 1L
      n_cores <- min(n_cores, nrow(rep_grid))

      run_rep <- function(i) {
        replicate_id <- rep_grid$replicate[i]
        truth <- synthetic_truths[[as.character(replicate_id)]]
        if (is.null(truth)) return(list())
        set.seed(truth$seed %||% rep_grid$seed[i])
        rep_runs <- list()
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
          rep_runs[[length(rep_runs) + 1L]] <- res
        }
        gc()
        rep_runs
      }

      res_list <- if (n_cores > 1L && .Platform$OS.type != "windows") {
        parallel::mclapply(seq_len(nrow(rep_grid)), run_rep, mc.cores = n_cores, mc.set.seed = FALSE)
      } else {
        lapply(seq_len(nrow(rep_grid)), run_rep)
      }
      purrr::flatten(res_list)
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
      synthetic_freshness_guard
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
        synthetic_mask_philosophy_csv,
        synthetic_viability_sweep_csv,
        synthetic_viability_sweep_plot
      )
      ceiling_paths <- synthetic_ceiling_outputs$outputs %||% character()
      extra_paths <- c(extra_paths, ceiling_paths)
      extra_paths <- extra_paths[!is.na(extra_paths)]
      c(out_paths, extra_paths)
    }, format = "file"),
    tar_target(synthetic_recovery_tables, {
      exdyn_synthetic_recovery_tables(
        synthetic_mode_runs,
        synthetic_screen_cfg,
        synthetic_abc_cfg,
        benchmark_cfg = synthetic_benchmark_cfg
      )
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
      param_tbl <- synthetic_recovery_tables$parameter_recovery %||% tibble::tibble()
      benchmark_cfg <- synthetic_benchmark_cfg %||% list()
      benchmark_stance <- benchmark_cfg$stance %||% "strict"
      weak_declared <- sort(unique(as.character(benchmark_cfg$weak_id_parameters %||% character())))
      core_params <- sort(unique(as.character(benchmark_cfg$core_params %||% c("alpha", "disp_mean_km"))))
      weak_observed <- if (nrow(param_tbl) &&
                           all(c("mode", "param", "identifiability_status") %in% names(param_tbl))) {
        param_tbl %>%
          dplyr::filter(.data$mode == "ideal", .data$identifiability_status == "weakly_identifiable") %>%
          dplyr::pull(.data$param) %>%
          unique() %>%
          sort()
      } else {
        character()
      }
      status_counts <- if (nrow(param_tbl) && all(c("mode", "identifiability_status") %in% names(param_tbl))) {
        param_tbl %>%
          dplyr::count(.data$mode, .data$identifiability_status, name = "n") %>%
          dplyr::arrange(.data$mode, .data$identifiability_status) %>%
          dplyr::mutate(key = paste(.data$mode, .data$identifiability_status, sep = "::")) %>%
          {stats::setNames(as.list(.$n), .$key)}
      } else {
        list()
      }
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
        benchmark = list(
          stance = benchmark_stance,
          core_params = core_params,
          weak_id_parameters_declared = weak_declared,
          weak_id_parameters_observed = weak_observed,
          gate_abs_rel_bias = benchmark_cfg$gate_abs_rel_bias %||% 0.20,
          gate_coverage80 = benchmark_cfg$gate_coverage80 %||% 0.60
        ),
        recovery_status_counts = status_counts,
        commands = cfg$commands %||% character()
      )
      manifest$outputs <- sort(unique(exdyn_relative_path(copied, canonical_dir)))
      exdyn_write_manifest(manifest, file.path(canonical_dir, "manifest.yaml"))
    }, format = "file")
  )
  tar_list
}
