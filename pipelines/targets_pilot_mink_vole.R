targets_pilot_mink_vole <- function(cfg_path = "config/realdata.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  years_seq_expr <- rlang::expr(seq.int(pilot_cfg$pilot$years[1], pilot_cfg$pilot$years[2]))
  list(
    tar_target_raw("pilot_cfg", rlang::expr(yaml::read_yaml(!!cfg_path))),
    tar_target(pilot_years, seq.int(pilot_cfg$pilot$years[1], pilot_cfg$pilot$years[2])),
    tar_target(pilot_grid, exdyn_make_grid(
      country_code = pilot_cfg$gbif$country,
      cell_km = pilot_cfg$pilot$grid_cell_km,
      crs_out = pilot_cfg$pilot$crs_out
    )),
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
    tar_target(pilot_vole_cells, exdyn_points_to_grid(pilot_vole_gbif, pilot_grid)),
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
    tar_target(pilot_screen, exdyn_screen_and_rank(
      theta = pilot_theta,
      arrivals = pilot_mink_arrivals,
      grid_info = pilot_grid_info,
      years = pilot_years,
      TX_obs = pilot_vole_tx$matrix,
      cfg_screen = pilot_cfg$pilot$screen,
      cfg_mink = pilot_cfg$pilot$mink_P,
      compat_cfg = pilot_cfg$pilot$compat
    )),
    tar_target(pilot_scores, pilot_screen$results),
    tar_target(pilot_tx_sim, pilot_screen$tx_sim),
    tar_target(pilot_output_dir, {
      dir <- file.path("outputs", "realdata", "pilot_mink_vole")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }),
    tar_target(pilot_tables_written, {
      dir.create(pilot_output_dir, recursive = TRUE, showWarnings = FALSE)
      readr::write_csv(pilot_vole_tx$table, file.path(pilot_output_dir, "vole_tx_obs.csv"))
      readr::write_csv(pilot_theta, file.path(pilot_output_dir, "params_lhs.csv"))
      readr::write_csv(pilot_scores, file.path(pilot_output_dir, "compatibility_ranked.csv"))
      file.path(pilot_output_dir, c("vole_tx_obs.csv", "params_lhs.csv", "compatibility_ranked.csv"))
    }),
    tar_target(pilot_maps_written, exdyn_write_best_maps(
      tx_obs_mat = pilot_vole_tx$matrix,
      tx_sim_list = pilot_tx_sim,
      scores = pilot_scores,
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
      pilot_tx_sim
      pilot_mink_field_default
      pilot_output_dir
      pilot_tables_written
      pilot_maps_written
      pilot_scatter_path
      quarto::quarto_render("reports/pilot_mink_vole.qmd")
    })
  )
}
