targets_realdata_gbif <- function(cfg_path = "config/realdata.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  list(
    tar_target_raw(
      "real_cfg",
      rlang::expr(yaml::read_yaml(!!cfg_path))
    ),
    tar_target(real_mink_key, exdyn_gbif_usage_key(
      real_cfg$species$mink$scientific_name,
      real_cfg$species$mink$gbif_rank
    )),
    tar_target(real_gbif_raw, exdyn_gbif_fetch(
      key = real_mink_key,
      country = real_cfg$gbif$country,
      year_min = real_cfg$gbif$years[1],
      year_max = real_cfg$gbif$years[2],
      cache_dir = "data/raw/gbif",
      max_records = real_cfg$cache$max_records,
      force = isTRUE(real_cfg$cache$force_redownload)
    )),
    tar_target(real_gbif_clean, exdyn_gbif_clean(real_gbif_raw)),
    tar_target(real_grid, exdyn_make_grid(
      country_code = real_cfg$gbif$country,
      cell_km = real_cfg$grid$cell_km,
      crs_out = real_cfg$grid$crs_out
    )),
    tar_target(real_cells, exdyn_points_to_grid(real_gbif_clean, real_grid)),
    tar_target(real_arrivals_raw, exdyn_arrival_from_cells(real_cells, real_cfg$gbif$years, real_cfg$arrival)),
    tar_target(real_arrivals_smooth, exdyn_arrival_smooth(real_arrivals_raw, real_grid)),
    tar_target(real_qc, exdyn_arrival_qc(real_arrivals_smooth, real_cfg$gbif$years)),
    tar_target(real_outputs_written, {
      out_dir <- file.path("outputs", "realdata", real_cfg$species$mink$folder)
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      readr::write_csv(real_gbif_clean, file.path(out_dir, "gbif_clean.csv.gz"))
      sf::write_sf(real_grid, file.path(out_dir, "grid.gpkg"), delete_dsn = TRUE)
      readr::write_csv(real_arrivals_raw, file.path(out_dir, "arrivals_raw.csv"))
      readr::write_csv(real_arrivals_smooth, file.path(out_dir, "arrivals_smooth.csv"))
      yaml::write_yaml(real_qc, file.path(out_dir, "qc_summary.yaml"))
      p_raw <- exdyn_plot_arrival_map(real_grid, dplyr::mutate(real_arrivals_raw, arrival_year_smooth = arrival_year_raw),
                                      "Mink arrival (raw)")
      p_smooth <- exdyn_plot_arrival_map(real_grid, real_arrivals_smooth, "Mink arrival (smoothed)")
      p_density <- exdyn_occ_density_map(real_grid, real_cells, "Mink occurrence density")
      ggplot2::ggsave(file.path(out_dir, "arrival_map_raw.png"), p_raw, width = 7, height = 7, dpi = 150)
      ggplot2::ggsave(file.path(out_dir, "arrival_map_smooth.png"), p_smooth, width = 7, height = 7, dpi = 150)
      ggplot2::ggsave(file.path(out_dir, "occ_density.png"), p_density, width = 7, height = 7, dpi = 150)
      list(
        out_dir = out_dir,
        files = list.files(out_dir, full.names = TRUE)
      )
    }),
    tar_target(real_report, {
      real_arrivals_raw
      real_arrivals_smooth
      real_grid
      real_cells
      real_qc
      real_gbif_clean
      quarto::quarto_render("reports/gbif_arrivals_mink.qmd")
    })
  )
}
