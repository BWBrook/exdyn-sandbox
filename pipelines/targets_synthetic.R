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
    tar_target(synthetic_env, exdyn_synthetic_env_snapshot(), cue = tar_cue("always")),
    tar_target_raw(
      "synthetic_cfg",
      rlang::expr({
        synthetic_log_start
        exdyn_synthetic_cfg_apply_overrides(yaml::read_yaml(!!cfg_path), synthetic_env)
      })
    ),
    tar_target(synthetic_grid_cfg, synthetic_cfg$grid %||% list(type = "pilot")),
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
    tar_target(synthetic_arrivals, synthetic_grid_bundle$arrivals),
    tar_target(synthetic_modes, exdyn_synthetic_modes(synthetic_cfg)),
    tar_target(synthetic_recovery_cfg, synthetic_cfg$recovery %||% list(n_reps = 1L, seed = 1234L, reference_rep = 1L)),
    tar_target(synthetic_theta_star, synthetic_cfg$theta_star),
    tar_target(synthetic_noise_cfg, synthetic_cfg$noise),
    tar_target(synthetic_tx_cfg, synthetic_cfg$tx_cfg),
    tar_target(synthetic_screen_cfg, synthetic_cfg$screen),
    tar_target(synthetic_compat_cfg, synthetic_cfg$compat),
    tar_target(synthetic_abc_cfg, synthetic_cfg$abc),
    tar_target(synthetic_coverage_breaks, {
      exdyn_coverage_breaks(synthetic_years)
    }),
    tar_target(synthetic_mask, {
      mask_cfg <- synthetic_cfg$mask %||% "riparian"
      if (identical(mask_cfg, "all")) {
        matrix(TRUE, nrow = synthetic_grid_info$nx, ncol = synthetic_grid_info$ny)
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
    tar_target(synthetic_runs, {
      rep_grid <- synthetic_rep_grid
      modes <- synthetic_modes
      ref_id <- synthetic_recovery_cfg$reference_rep %||% 1L
      runs <- list()
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
            keep_best_tx = keep_best
          )
          res$replicate <- replicate_id
          res$seed <- seed
          runs[[length(runs) + 1L]] <- res
        }
        gc()
      }
      list(truths = truths, runs = runs)
    }, deployment = "main"),
    tar_target(synthetic_mode_runs, synthetic_runs$runs),
    tar_target(synthetic_reference_truth, {
      ref_id <- synthetic_recovery_cfg$reference_rep %||% 1L
      synthetic_runs$truths[[as.character(ref_id)]]
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
      exdyn_write_synthetic_outputs(synthetic_reference_runs, synthetic_reference_truth, synthetic_grid_info, synthetic_output_root)
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
