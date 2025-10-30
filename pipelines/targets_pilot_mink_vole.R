targets_pilot_mink_vole <- function(cfg_path = "config/realdata.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  pilot_theta_rows_target <- tar_target(
    pilot_theta_rows,
    purrr::transpose(pilot_theta),
    iteration = "list"
  )
  pilot_draw_result_target <- tar_target(
    pilot_draw_result,
    {
      theta <- pilot_theta_rows
      draw <- theta$draw[[1]]
      log_mem_flag <- pilot_cfg$pilot$screen$log_mem %||% TRUE
      tx_path <- file.path(pilot_tx_dir, sprintf("tx_%03d.rds", draw))
      dir.create(dirname(tx_path), recursive = TRUE, showWarnings = FALSE)
      TX <- exdyn_simulate_tx_only(
        grid_info = pilot_grid_info,
        years = pilot_years,
        T_P = pilot_mink_field_default$T_P,
        ramp_years = theta$ramp_years[[1]],
        pars = list(
          rmax = theta$rmax[[1]],
          A_frac = theta$A_over_K[[1]] * theta$K0[[1]],
          beta_H = 0,
          d = 0.03
        ),
        K0 = theta$K0[[1]],
        alpha = theta$alpha[[1]],
        disp_mean_cells = theta$disp_mean_cells[[1]],
        pred = list(type = "II", c = theta$pred_c[[1]], h = theta$pred_h[[1]]),
        pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
        log_mem = isTRUE(log_mem_flag),
        log_tag = sprintf("draw %03d", draw)
      )
      saveRDS(TX, tx_path)
      score <- exdyn_score(
        pilot_vole_tx$matrix,
        pilot_mink_field_default$T_P,
        TX,
        pilot_cfg$pilot$compat
      )
      result <- dplyr::bind_cols(
        tibble::tibble(
          draw = draw,
          tx_path = tx_path,
          alpha = theta$alpha[[1]],
          disp_mean_km = theta$disp_mean_km[[1]],
          disp_mean_cells = theta$disp_mean_cells[[1]],
          A_over_K = theta$A_over_K[[1]],
          pred_c = theta$pred_c[[1]],
          pred_h = theta$pred_h[[1]],
          ramp_years = theta$ramp_years[[1]],
          rmax = theta$rmax[[1]],
          K0 = theta$K0[[1]]
        ),
        score
      )
      base::gc()
      result
    },
    pattern = map(pilot_theta_rows),
    iteration = "list"
  )
  list(
    tar_target_raw("pilot_cfg", rlang::expr(yaml::read_yaml(!!cfg_path))),
    tar_target(pilot_years, seq.int(pilot_cfg$pilot$years[1], pilot_cfg$pilot$years[2])),
    tar_target(pilot_grid, exdyn_make_grid(
      country_code = pilot_cfg$gbif$country,
      cell_km = pilot_cfg$pilot$grid_cell_km,
      crs_out = pilot_cfg$pilot$crs_out
    ), deployment = "main"),
    tar_target(pilot_grid_info, exdyn_grid_lookup(pilot_grid)),
    tar_target(pilot_mink_arrivals, real_arrivals_smooth),
    tar_target(pilot_vole_gbif, exdyn_gbif_species(
      sci = pilot_cfg$species$vole$scientific_name,
      rank = pilot_cfg$species$vole$gbif_rank,
      country = pilot_cfg$gbif$country,
      years = pilot_cfg$pilot$years,
      cache_dir = "data/raw/gbif",
      max_records = pilot_cfg$cache$max_records,
      force = isTRUE(pilot_cfg$cache$force_redownload)
    )),
    tar_target(pilot_vole_cells, exdyn_points_to_grid(pilot_vole_gbif, pilot_grid), deployment = "main"),
    tar_target(pilot_vole_tx, exdyn_tx_map(
      pilot_vole_cells, pilot_cfg$pilot$years, pilot_cfg$pilot$vole, pilot_grid_info
    )),
    tar_target(pilot_mink_field_default, exdyn_fields_from_mink(
      pilot_mink_arrivals, pilot_grid_info, pilot_years,
      ramp_years = pilot_cfg$pilot$mink_P$ramp_years,
      pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak
    )),
    tar_target(pilot_theta, exdyn_param_lhs(
      pilot_cfg$pilot$screen,
      n = pilot_cfg$pilot$screen$n_draws,
      cell_km = pilot_cfg$pilot$grid_cell_km,
      seed = 42
    )),
    tar_target(pilot_output_dir, {
      dir <- file.path("outputs", "realdata", "pilot_mink_vole")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }),
    tar_target(pilot_tx_dir, {
      dir <- file.path(pilot_output_dir, "tx_sim")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }),
    pilot_theta_rows_target,
    pilot_draw_result_target,
    tar_target(pilot_screen, {
      rows <- Filter(Negate(is.null), pilot_draw_result)
      if (!length(rows)) {
        tibble::tibble()
      } else {
        df <- dplyr::bind_rows(rows)
        if (!nrow(df)) df else df %>% dplyr::arrange(loss) %>% dplyr::mutate(rank = dplyr::row_number())
      }
    }),
    tar_target(pilot_scores, pilot_screen),
    tar_target(pilot_tables_written, {
      dir.create(pilot_output_dir, recursive = TRUE, showWarnings = FALSE)
      readr::write_csv(pilot_vole_tx$table, file.path(pilot_output_dir, "vole_tx_obs.csv"))
      readr::write_csv(pilot_theta, file.path(pilot_output_dir, "params_lhs.csv"))
      readr::write_csv(pilot_screen, file.path(pilot_output_dir, "compatibility_ranked.csv"))
      file.path(pilot_output_dir, c("vole_tx_obs.csv", "params_lhs.csv", "compatibility_ranked.csv"))
    }),
    tar_target(pilot_maps_written, exdyn_write_best_maps(
      tx_obs_mat = pilot_vole_tx$matrix,
      tx_sources = pilot_screen$tx_path,
      scores = pilot_screen,
      grid_info = pilot_grid_info,
      out_dir = pilot_output_dir,
      top_k = 3
    )),
    tar_target(pilot_scatter_path, {
      scatter <- exdyn_plot_tx_scatter(pilot_vole_tx$matrix, pilot_mink_field_default$T_P)
      path <- file.path(pilot_output_dir, "TX_obs_vs_TP.png")
      ggplot2::ggsave(path, scatter, width = 6, height = 5, dpi = 150)
      path
    }),
    tar_target(pilot_report, {
      pilot_scores
      pilot_theta
      pilot_grid
      pilot_grid_info
      pilot_vole_tx
      pilot_mink_field_default
      pilot_output_dir
      pilot_tables_written
      pilot_maps_written
      pilot_scatter_path
      quarto::quarto_render("reports/pilot_mink_vole.qmd")
    })
  )
}
