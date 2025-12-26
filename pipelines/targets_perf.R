# Performance profiling targets ------------------------------------------------

targets_perf <- function(cfg_path = "config/perf.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  graph_cfg <- tryCatch({
    yaml::read_yaml(cfg_path)$graph_parallel %||% list()
  }, error = function(e) list())
  graph_enabled <- isTRUE(graph_cfg$enabled %||% FALSE)
  list(
    tar_target_raw(
      "perf_cfg_path",
      rlang::expr(!!cfg_path),
      format = "file"
    ),
    tar_target(perf_cfg, yaml::read_yaml(perf_cfg_path)),
    tar_target(perf_profiles, perf_cfg$profiles %||% list()),
    tar_target(perf_smoke_profile, perf_profiles$smoke),
    tar_target(perf_smoke_dir, {
      dir <- file.path("outputs", "perf", "toy_smoke")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }, format = "file"),
    tar_target(perf_smoke_run, {
      exdyn_perf_run_profile(
        profile = perf_smoke_profile,
        perf_cfg = perf_cfg,
        label = "smoke"
      )
    }, deployment = "main"),
    tar_target(perf_smoke_written, {
      exdyn_perf_write_outputs(
        run = perf_smoke_run,
        perf_cfg = perf_cfg,
        out_dir = perf_smoke_dir,
        wp_id = "WP-0.2.1"
      )
    }),
    tar_target(perf_smoke_files, {
      unname(unlist(perf_smoke_written$paths))
    }, format = "file"),
    tar_target(perf_stage_profile_smoke, {
      tbl <- dplyr::bind_rows(
        perf_smoke_run$stage_records,
        perf_smoke_written$stage_record
      )
      out_path <- file.path("outputs", "perf", "stage_profile_smoke.csv")
      data.table::fwrite(tbl, out_path)
      out_path
    }, format = "file"),
    tar_target(perf_scaling_sweep, {
      exdyn_perf_scaling_sweep(perf_cfg$sweep %||% list(), perf_cfg)
    }, deployment = "main"),
    tar_target(perf_scaling_sweep_csv, {
      out_path <- file.path("outputs", "perf", "scaling_sweep.csv")
      dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
      data.table::fwrite(perf_scaling_sweep, out_path)
      out_path
    }, format = "file"),
    tar_target(perf_scaling_plots, {
      exdyn_perf_scaling_plot(perf_scaling_sweep, file.path("outputs", "perf", "scaling_plots"))
    }, format = "file"),
    tar_target(perf_optimisation_profile, {
      prof_id <- perf_cfg$optimisation$profile %||% "medium"
      perf_profiles[[prof_id]]
    }),
    tar_target(perf_optimisation_table, {
      exdyn_perf_optimisation_compare(perf_optimisation_profile, perf_cfg)
    }, deployment = "main"),
    tar_target(perf_optimisation_csv, {
      out_path <- file.path("outputs", "perf", "optimisation_before_after.csv")
      dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
      data.table::fwrite(perf_optimisation_table, out_path)
      out_path
    }, format = "file"),
    if (graph_enabled) {
      tar_target(perf_graph_parallel_dir, {
        res <- exdyn_perf_graph_parallel_run(
          workers = as.integer(Sys.getenv("EXDYN_WORKERS", graph_cfg$workers %||% 8L)),
          n_draws = as.integer(Sys.getenv("EXDYN_DRAWS", graph_cfg$n_draws %||% 64L)),
          n_sims = as.integer(Sys.getenv("EXDYN_SIMS", graph_cfg$n_sims %||% 200L)),
          mode = tolower(Sys.getenv("EXDYN_MODE", graph_cfg$mode %||% "full")),
          seed = as.integer(Sys.getenv("EXDYN_SEED", graph_cfg$seed %||% 1045L))
        )
        res$out_dir
      }, format = "file", deployment = "main")
    } else {
      NULL
    }
  )
}
