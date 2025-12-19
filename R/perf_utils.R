# Performance utilities for synthetic benchmark profiling

#' Build a toy grid for performance benchmarks
#' @keywords internal
exdyn_perf_make_grid <- function(nx, ny, cell_km = 10, riparian_frac = 0.6, region_n = 3, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  grid <- tidyr::expand_grid(
    row = seq_len(nx),
    col = seq_len(ny)
  ) %>%
    dplyr::mutate(
      cell_id = dplyr::row_number(),
      cell_km = cell_km
    )

  bands <- cut(grid$row,
               breaks = seq(0, nx, length.out = region_n + 1),
               include.lowest = TRUE, labels = FALSE)
  grid$region <- paste0("R", bands)

  center <- (ny + 1) / 2
  score <- abs(grid$col - center) + stats::rnorm(nrow(grid), sd = 0.25)
  threshold <- stats::quantile(score, probs = riparian_frac, na.rm = TRUE)
  grid$riparian <- score <= threshold
  grid$river_km <- ifelse(grid$riparian, stats::runif(nrow(grid), min = 2, max = 15), 0)

  grid_sf <- sf::st_as_sf(grid, coords = c("col", "row"), remove = FALSE)
  grid_info <- exdyn_grid_lookup(grid_sf)
  mask <- grid_info$riparian_matrix
  list(grid_sf = grid_sf, grid_info = grid_info, mask = mask)
}

#' Generate synthetic arrival-year table for a toy grid
#' @keywords internal
exdyn_perf_arrival_table <- function(grid_info, years, pattern = "gradient",
                                     noise_sd = 1, span_frac = 0.8, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  years <- sort(unique(as.integer(years)))
  start <- min(years)
  end <- max(years)
  span <- max(1, round((end - start) * span_frac))
  lookup <- grid_info$lookup
  pattern <- match.arg(pattern, c("gradient", "row", "col"))
  scale_vals <- switch(
    pattern,
    gradient = (lookup$row_idx + lookup$col_idx) / (max(lookup$row_idx) + max(lookup$col_idx)),
    row = lookup$row_idx / max(lookup$row_idx),
    col = lookup$col_idx / max(lookup$col_idx)
  )
  base <- start + span * scale_vals
  arrival <- base + stats::rnorm(length(base), sd = noise_sd)
  arrival <- round(pmin(end, pmax(start, arrival)))
  tibble::tibble(cell_id = lookup$cell_id, arrival_year = arrival)
}

#' Arrival-year matrix from arrival table
#' @keywords internal
exdyn_perf_arrival_matrix <- function(arrivals, grid_info, years, delta_region = NULL) {
  mat <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  lookup <- grid_info$lookup
  idx <- match(lookup$cell_id, arrivals$cell_id)
  vals <- arrivals$arrival_year[idx]
  mat[cbind(lookup$row_idx, lookup$col_idx)] <- vals
  if (!is.null(delta_region)) {
    mat <- exdyn_adjust_arrival_matrix(mat, grid_info, delta_region, years)
  }
  mat <- pmax(min(years), pmin(max(years), mat))
  dim(mat) <- c(grid_info$nx, grid_info$ny)
  mat
}

#' Stage timer for perf runs
#' @keywords internal
exdyn_perf_stage <- function(stage, expr) {
  start <- base::proc.time()[["elapsed"]]
  mem_start <- exdyn_mem_snapshot()
  value <- force(expr)
  end <- base::proc.time()[["elapsed"]]
  mem_end <- exdyn_mem_snapshot()
  record <- tibble::tibble(
    stage = stage,
    wall_sec = as.numeric(end - start),
    rss_mb = mem_end$rss_mb,
    rss_peak_mb = mem_end$rss_peak_mb,
    gc_mb = mem_end$gc_mb
  )
  list(value = value, record = record, mem_start = mem_start, mem_end = mem_end)
}

#' Convert simulation profile to stage records
#' @keywords internal
exdyn_perf_profile_records <- function(profile, prefix = "sim") {
  if (is.null(profile) || !length(profile)) {
    return(tibble::tibble())
  }
  fields <- c("pred_field", "local_update", "dispersal", "threshold", "total")
  available <- intersect(fields, names(profile))
  tibble::tibble(
    stage = paste(prefix, available, sep = "_"),
    wall_sec = unname(unlist(profile[available])),
    rss_mb = NA_real_,
    rss_peak_mb = NA_real_,
    gc_mb = NA_real_
  )
}

#' Run a single performance profile
#' @keywords internal
exdyn_perf_run_profile <- function(profile, perf_cfg, label = "smoke",
                                   pilot_grid_info = NULL, pilot_arrivals = NULL,
                                   pilot_years = NULL,
                                   tx_map_fast = TRUE) {
  stopifnot(!is.null(profile))
  seed <- profile$seed %||% 1L
  if (!is.null(seed)) set.seed(seed)

  sim_cfg <- perf_cfg$sim %||% list()
  obs_cfg <- perf_cfg$obs %||% list()
  tx_cfg <- perf_cfg$tx_cfg %||% list()
  compat_cfg <- perf_cfg$compat %||% list()

  stage_records <- list()

  grid_stage <- exdyn_perf_stage("setup_grid", {
    grid_cfg <- profile$grid %||% list()
    if (identical(grid_cfg$type, "pilot")) {
      if (is.null(pilot_grid_info)) stop("pilot_grid_info required for pilot grid profile")
      list(grid_info = pilot_grid_info, grid_sf = NULL, mask = pilot_grid_info$riparian_matrix)
    } else {
      exdyn_perf_make_grid(
        nx = grid_cfg$nx %||% 25,
        ny = grid_cfg$ny %||% 25,
        cell_km = grid_cfg$cell_km %||% 10,
        riparian_frac = grid_cfg$riparian_frac %||% 0.6,
        region_n = grid_cfg$region_n %||% 3,
        seed = seed
      )
    }
  })
  grid_info <- grid_stage$value$grid_info
  mask <- grid_stage$value$mask
  stage_records <- c(stage_records, list(grid_stage$record))

  years_vec <- if (is.character(profile$years) && identical(profile$years, "pilot")) {
    if (is.null(pilot_years)) stop("pilot_years required for pilot profile")
    seq.int(pilot_years[1], pilot_years[2])
  } else {
    seq.int(profile$years[1], profile$years[2])
  }

  arrivals_stage <- exdyn_perf_stage("setup_arrivals", {
    if (identical(profile$grid$type, "pilot")) {
      if (is.null(pilot_arrivals)) stop("pilot_arrivals required for pilot grid profile")
      exdyn_prepare_arrivals(pilot_arrivals)
    } else {
      arr_cfg <- profile$arrival %||% list()
      exdyn_perf_arrival_table(
        grid_info = grid_info,
        years = years_vec,
        pattern = arr_cfg$pattern %||% "gradient",
        noise_sd = arr_cfg$noise_sd %||% 1,
        span_frac = arr_cfg$span_frac %||% 0.8,
        seed = seed + 11
      )
    }
  })
  arrivals <- arrivals_stage$value
  stage_records <- c(stage_records, list(arrivals_stage$record))

  T_P_stage <- exdyn_perf_stage("setup_arrival_matrix", {
    exdyn_perf_arrival_matrix(
      arrivals = arrivals,
      grid_info = grid_info,
      years = years_vec,
      delta_region = sim_cfg$delta_region %||% NULL
    )
  })
  T_P <- T_P_stage$value
  if (!is.null(mask)) {
    T_P[!mask] <- NA_real_
  }
  stage_records <- c(stage_records, list(T_P_stage$record))

  disp_mean_cells <- sim_cfg$disp_mean_km %||% 10
  if (!is.null(grid_info$cell_km) && is.finite(grid_info$cell_km)) {
    disp_mean_cells <- disp_mean_cells / grid_info$cell_km
  }
  pars <- list(
    rmax = sim_cfg$rmax %||% 0.4,
    A_frac = (sim_cfg$A_over_K %||% 0.1) * (sim_cfg$K0 %||% 120),
    beta_H = 0,
    d = 0.02
  )
  pred <- list(
    type = sim_cfg$pred_type %||% "II",
    c = sim_cfg$pred_c %||% 0.8,
    h = sim_cfg$pred_h %||% 30,
    scale = sim_cfg$pred_scale %||% 1,
    gamma = sim_cfg$gamma %||% 1
  )

  sim_stage <- exdyn_perf_stage("simulate_tx", {
    exdyn_simulate_tx_only(
      grid_info = grid_info,
      years = years_vec,
      T_P = T_P,
      ramp_years = sim_cfg$ramp_years %||% 8,
      pars = pars,
      K0 = sim_cfg$K0 %||% 120,
      alpha = if (isTRUE(profile$dispersal)) sim_cfg$alpha %||% 0.2 else 0,
      disp_mean_cells = disp_mean_cells,
      pred = pred,
      pre_leak = sim_cfg$pre_leak %||% 0,
      mask = mask,
      frac = sim_cfg$truth_frac %||% 0.02,
      rel0 = sim_cfg$truth_rel0 %||% 0.5,
      profile = TRUE,
      conv_reuse = sim_cfg$conv_reuse %||% TRUE
    )
  })
  TX_idx <- sim_stage$value
  stage_records <- c(stage_records, list(sim_stage$record))
  prof_records <- exdyn_perf_profile_records(attr(TX_idx, "profile"), prefix = "sim")
  if (nrow(prof_records)) stage_records <- c(stage_records, list(prof_records))

  TX_true <- matrix(NA_real_, nrow = grid_info$nx, ncol = grid_info$ny)
  finite_idx <- is.finite(TX_idx)
  if (any(finite_idx)) {
    TX_true[finite_idx] <- years_vec[TX_idx[finite_idx]]
  }
  if (!is.null(mask)) {
    TX_true[!mask] <- NA_real_
  }

  coverage_breaks <- exdyn_coverage_breaks(years_vec)
  summary_stage <- exdyn_perf_stage("summary_true", {
    exdyn_summary_tx_response(TX_true, T_P, years = years_vec, coverage_breaks = coverage_breaks)
  })
  summary_true <- summary_stage$value
  stage_records <- c(stage_records, list(summary_stage$record))

  obs_out <- NULL
  if (isTRUE(profile$include_observation)) {
    fields_stage <- exdyn_perf_stage("observation_fields", {
      exdyn_fields_from_mink(
        arrivals = arrivals,
        grid_info = grid_info,
        years = years_vec,
        ramp_years = sim_cfg$ramp_years %||% 8,
        pre_leak = sim_cfg$pre_leak %||% 0,
        scale = sim_cfg$pred_scale %||% 1,
        gamma = sim_cfg$gamma %||% 1,
        delta_region = sim_cfg$delta_region %||% NULL
      )
    })
    fields <- fields_stage$value
    stage_records <- c(stage_records, list(fields_stage$record))

    obs_sim_stage <- exdyn_perf_stage("observation_sim", {
      exdyn_simulate(
        nx = grid_info$nx,
        ny = grid_info$ny,
        years = length(years_vec),
        fields = fields,
        pars = pars,
        K0 = sim_cfg$K0 %||% 120,
        alpha = if (isTRUE(profile$dispersal)) sim_cfg$alpha %||% 0.2 else 0,
        disp_mean_cells = disp_mean_cells,
        pred = pred,
        conv_reuse = sim_cfg$conv_reuse %||% TRUE
      )
    })
    N_true <- obs_sim_stage$value
    stage_records <- c(stage_records, list(obs_sim_stage$record))

    obs_stage <- exdyn_perf_stage("observation_tx_map", {
      po_points <- exdyn_synthetic_po_points(
        N_true,
        years_vec,
        grid_info,
        rate = obs_cfg$po_rate %||% 0.02,
        effort_strength = obs_cfg$effort_strength %||% 1
      )
      if ((obs_cfg$missing_years_prob %||% 0) > 0 && nrow(po_points)) {
        year_keep <- stats::runif(length(unique(po_points$year))) >= (obs_cfg$missing_years_prob %||% 0)
        keep_years <- unique(po_points$year)[year_keep]
        po_points <- dplyr::filter(po_points, .data$year %in% keep_years)
      }
      effort_points <- po_points
      tx_map <- exdyn_tx_map(
        cells_df = dplyr::select(po_points, cell_id, row, col, year),
        years = range(years_vec),
        cfg = tx_cfg,
        grid_info = grid_info,
        effort_cells = dplyr::select(effort_points, cell_id, row, col, year),
        mask = mask,
        fast = tx_map_fast
      )
      if ((obs_cfg$random_tx_dropout %||% 0) > 0 && nrow(tx_map$table)) {
        drop_mask <- stats::runif(nrow(tx_map$table)) < (obs_cfg$random_tx_dropout %||% 0)
        if (any(drop_mask)) {
          drop_cells <- tx_map$table$cell_id[drop_mask]
          lookup <- grid_info$lookup
          pos <- lookup[match(drop_cells, lookup$cell_id), c("row_idx", "col_idx")]
          pos <- pos[stats::complete.cases(pos), , drop = FALSE]
          if (nrow(pos)) {
            tx_map$matrix[cbind(pos$row_idx, pos$col_idx)] <- NA_real_
            tx_map$last_presence[cbind(pos$row_idx, pos$col_idx)] <- tx_map$last_presence[cbind(pos$row_idx, pos$col_idx)]
          }
          tx_map$table$tx_obs[drop_mask] <- NA_integer_
        }
      }
      list(po_points = po_points, effort_points = effort_points, tx_map = tx_map)
    })
    obs_out <- obs_stage$value
    stage_records <- c(stage_records, list(obs_stage$record))

    summary_obs_stage <- exdyn_perf_stage("summary_obs", {
      exdyn_summary_tx_response(obs_out$tx_map$matrix, T_P, years = years_vec, coverage_breaks = coverage_breaks)
    })
    summary_obs <- summary_obs_stage$value
    stage_records <- c(stage_records, list(summary_obs_stage$record))
  } else {
    summary_obs <- NULL
  }

  stage_tbl <- dplyr::bind_rows(stage_records)
  stage_tbl <- stage_tbl %>%
    dplyr::mutate(profile = label)

  list(
    label = label,
    seed = seed,
    grid_info = grid_info,
    mask = mask,
    arrivals = arrivals,
    years = years_vec,
    T_P = T_P,
    TX_true = TX_true,
    TX_obs = obs_out$tx_map$matrix %||% NULL,
    po_points = obs_out$po_points %||% NULL,
    effort_points = obs_out$effort_points %||% NULL,
    summary_true = summary_true,
    summary_obs = summary_obs,
    stage_records = stage_tbl,
    compat_cfg = compat_cfg
  )
}

#' Write perf outputs to disk
#' @keywords internal
exdyn_perf_write_outputs <- function(run, perf_cfg, out_dir, wp_id = "WP-0.2.1") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  stage_record <- exdyn_perf_stage("save_outputs", {
    grid_info <- run$grid_info
    paths <- list()
    tx_plot <- exdyn_plot_surface(run$TX_true, grid_info, "TX_true (perf smoke)")
    tx_path <- file.path(out_dir, "TX_true_map.png")
    ggplot2::ggsave(tx_path, tx_plot, width = 6, height = 5, dpi = 150)
    paths$tx_true <- tx_path

    if (!is.null(run$TX_obs)) {
      obs_plot <- exdyn_plot_surface(run$TX_obs, grid_info, "TX_obs (perf smoke)")
      obs_path <- file.path(out_dir, "TX_obs_map.png")
      ggplot2::ggsave(obs_path, obs_plot, width = 6, height = 5, dpi = 150)
      paths$tx_obs <- obs_path
    }

    summary_tbl <- tibble::as_tibble_row(run$summary_true)
    summary_path <- file.path(out_dir, "summary_true.csv")
    data.table::fwrite(summary_tbl, summary_path)
    paths$summary_true <- summary_path

    if (!is.null(run$summary_obs)) {
      summary_obs_tbl <- tibble::as_tibble_row(run$summary_obs)
      summary_obs_path <- file.path(out_dir, "summary_obs.csv")
      data.table::fwrite(summary_obs_tbl, summary_obs_path)
      paths$summary_obs <- summary_obs_path
    }

    runtime_tbl <- run$stage_records %>%
      dplyr::summarise(
        wall_sec_total = sum(wall_sec, na.rm = TRUE),
        peak_rss_mb = max(rss_peak_mb, rss_mb, na.rm = TRUE)
      )
    runtime_path <- file.path(out_dir, "runtime_summary.csv")
    data.table::fwrite(runtime_tbl, runtime_path)
    paths$runtime <- runtime_path

    config_path <- file.path(out_dir, "config_snapshot.yaml")
    exdyn_write_config_snapshot(perf_cfg, config_path)

    manifest <- list(
      schema_version = exdyn_schema_version(),
      commit_sha = exdyn_git_sha(),
      run_id = exdyn_make_run_id("perf"),
      run_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      milestone = "0.2",
      wp_id = wp_id,
      config_snapshots = list(perf = exdyn_relative_path(config_path, out_dir)),
      seeds = list(profile_seed = run$seed),
      commands = character()
    )
    manifest$outputs <- sort(unique(exdyn_relative_path(unname(unlist(paths)), out_dir)))
    manifest_path <- file.path(out_dir, "manifest.yaml")
    exdyn_write_manifest(manifest, manifest_path)
    paths$manifest <- manifest_path
    paths
  })
  list(paths = stage_record$value, stage_record = stage_record$record)
}

#' Scaling sweep for performance
#' @keywords internal
exdyn_perf_scaling_sweep <- function(sweep_cfg, perf_cfg) {
  stopifnot(!is.null(sweep_cfg))
  set.seed(sweep_cfg$seed %||% 1L)
  grid_sizes <- sweep_cfg$grid_sizes %||% c(25, 50, 100)
  years_list <- sweep_cfg$years %||% c(30, 80, 150)
  reps_list <- sweep_cfg$replicates %||% c(1, 5)
  dispersal_list <- sweep_cfg$dispersal %||% c(TRUE, FALSE)

  sim_cfg <- perf_cfg$sim %||% list()
  results <- list()
  idx <- 1L
  for (n_cells in grid_sizes) {
    for (n_years in years_list) {
      for (n_reps in reps_list) {
        for (disp_on in dispersal_list) {
          run_seed <- sample.int(1e6, 1)
          grid <- exdyn_perf_make_grid(
            nx = n_cells, ny = n_cells,
            cell_km = sweep_cfg$cell_km %||% 10,
            riparian_frac = sweep_cfg$riparian_frac %||% 0.6,
            region_n = sweep_cfg$region_n %||% 4,
            seed = run_seed
          )
          years_vec <- seq.int(2000, 2000 + n_years - 1)
          arr_cfg <- sweep_cfg$arrival %||% list()
          arrivals <- exdyn_perf_arrival_table(
            grid$grid_info,
            years_vec,
            pattern = arr_cfg$pattern %||% "gradient",
            noise_sd = arr_cfg$noise_sd %||% 1,
            span_frac = arr_cfg$span_frac %||% 0.8,
            seed = run_seed + 11
          )
          T_P <- exdyn_perf_arrival_matrix(arrivals, grid$grid_info, years_vec)
          if (!is.null(grid$mask)) {
            T_P[!grid$mask] <- NA_real_
          }
          disp_mean_cells <- sim_cfg$disp_mean_km %||% 10
          if (!is.null(grid$grid_info$cell_km) && is.finite(grid$grid_info$cell_km)) {
            disp_mean_cells <- disp_mean_cells / grid$grid_info$cell_km
          }
          pars <- list(
            rmax = sim_cfg$rmax %||% 0.4,
            A_frac = (sim_cfg$A_over_K %||% 0.1) * (sim_cfg$K0 %||% 120),
            beta_H = 0,
            d = 0.02
          )
          pred <- list(
            type = sim_cfg$pred_type %||% "II",
            c = sim_cfg$pred_c %||% 0.8,
            h = sim_cfg$pred_h %||% 30,
            scale = sim_cfg$pred_scale %||% 1,
            gamma = sim_cfg$gamma %||% 1
          )
          wall_times <- numeric()
          peak_mem <- numeric()
          stage_times <- list()
          for (rep_i in seq_len(n_reps)) {
            set.seed(run_seed + rep_i)
            mem_before <- exdyn_mem_snapshot()
            t0 <- base::proc.time()[["elapsed"]]
            TX_idx <- exdyn_simulate_tx_only(
              grid_info = grid$grid_info,
              years = years_vec,
              T_P = T_P,
              ramp_years = sim_cfg$ramp_years %||% 8,
              pars = pars,
              K0 = sim_cfg$K0 %||% 120,
              alpha = if (isTRUE(disp_on)) sim_cfg$alpha %||% 0.2 else 0,
              disp_mean_cells = disp_mean_cells,
              pred = pred,
              pre_leak = sim_cfg$pre_leak %||% 0,
              mask = grid$mask,
              frac = sim_cfg$truth_frac %||% 0.02,
              rel0 = sim_cfg$truth_rel0 %||% 0.5,
              profile = TRUE,
              conv_reuse = sim_cfg$conv_reuse %||% TRUE
            )
            t1 <- base::proc.time()[["elapsed"]]
            mem_after <- exdyn_mem_snapshot()
            wall_times[rep_i] <- as.numeric(t1 - t0)
            peak_mem[rep_i] <- max(mem_after$rss_peak_mb, mem_after$rss_mb, mem_before$rss_mb, na.rm = TRUE)
            prof <- attr(TX_idx, "profile")
            if (!is.null(prof)) stage_times[[rep_i]] <- prof
            rm(TX_idx)
            gc()
          }
          stage_avg <- list()
          if (length(stage_times)) {
            keys <- unique(unlist(lapply(stage_times, names)))
            for (k in keys) {
              vals <- vapply(stage_times, function(x) x[[k]] %||% NA_real_, numeric(1))
              stage_avg[[k]] <- mean(vals, na.rm = TRUE)
            }
          }
          results[[idx]] <- tibble::tibble(
            n_cells = n_cells * n_cells,
            grid_size = n_cells,
            n_years = n_years,
            n_reps = n_reps,
            dispersal_on = disp_on,
            wall_sec_total = sum(wall_times),
            wall_sec_mean = mean(wall_times),
            peak_mem_mb = max(peak_mem, na.rm = TRUE),
            sim_pred_field = stage_avg$pred_field %||% NA_real_,
            sim_local_update = stage_avg$local_update %||% NA_real_,
            sim_dispersal = stage_avg$dispersal %||% NA_real_,
            sim_threshold = stage_avg$threshold %||% NA_real_,
            sim_total = stage_avg$total %||% NA_real_
          )
          idx <- idx + 1L
        }
      }
    }
  }
  dplyr::bind_rows(results)
}

#' Produce scaling plots
#' @keywords internal
exdyn_perf_scaling_plot <- function(sweep_tbl, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (!nrow(sweep_tbl)) return(character())
  plot_df <- sweep_tbl %>%
    dplyr::mutate(
      cells = n_cells,
      years = n_years,
      dispersal = ifelse(dispersal_on, "on", "off")
    )
  p1 <- ggplot2::ggplot(plot_df, ggplot2::aes(x = cells, y = wall_sec_mean, color = factor(years))) +
    ggplot2::geom_point() +
    ggplot2::geom_line() +
    ggplot2::scale_x_log10() +
    ggplot2::scale_y_log10() +
    ggplot2::facet_wrap(~ dispersal) +
    ggplot2::labs(
      title = "Scaling sweep: mean wall time",
      x = "Cells (n)",
      y = "Wall time (s)",
      color = "Years"
    ) +
    ggplot2::theme_minimal()
  out1 <- file.path(out_dir, "scaling_walltime_loglog.png")
  ggplot2::ggsave(out1, p1, width = 7, height = 4.5, dpi = 150)

  p2 <- ggplot2::ggplot(plot_df, ggplot2::aes(x = cells, y = peak_mem_mb, color = factor(years))) +
    ggplot2::geom_point() +
    ggplot2::geom_line() +
    ggplot2::scale_x_log10() +
    ggplot2::scale_y_log10() +
    ggplot2::facet_wrap(~ dispersal) +
    ggplot2::labs(
      title = "Scaling sweep: peak RSS",
      x = "Cells (n)",
      y = "Peak RSS (MB)",
      color = "Years"
    ) +
    ggplot2::theme_minimal()
  out2 <- file.path(out_dir, "scaling_rss_loglog.png")
  ggplot2::ggsave(out2, p2, width = 7, height = 4.5, dpi = 150)

  c(out1, out2)
}

#' Optimisation comparison run
#' @keywords internal
exdyn_perf_optimisation_compare <- function(profile, perf_cfg, reps = 3) {
  opt_cfg <- perf_cfg$optimisation %||% list()
  target <- opt_cfg$target %||% "tx_map_fast"
  if (!is.null(opt_cfg$reps)) {
    reps <- max(1L, as.integer(opt_cfg$reps))
  }
  out <- list()
  idx <- 1L

  if (identical(target, "tx_map_fast")) {
    flags <- c(FALSE, TRUE)
    for (flag in flags) {
      wall_vals <- numeric(reps)
      peak_vals <- numeric(reps)
      for (rep_i in seq_len(reps)) {
        run <- exdyn_perf_run_profile(
          profile,
          perf_cfg,
          label = ifelse(flag, "txmap_fast_on", "txmap_fast_off"),
          tx_map_fast = flag
        )
        stage <- run$stage_records %>%
          dplyr::filter(.data$stage == "observation_tx_map") %>%
          dplyr::summarise(
            wall_sec = sum(.data$wall_sec, na.rm = TRUE),
            peak_rss_mb = max(.data$rss_peak_mb, .data$rss_mb, na.rm = TRUE)
          )
        wall_vals[rep_i] <- stage$wall_sec
        peak_vals[rep_i] <- stage$peak_rss_mb
      }
      out[[idx]] <- tibble::tibble(
        tx_map_fast = flag,
        wall_sec = mean(wall_vals),
        wall_sd = stats::sd(wall_vals),
        peak_rss_mb = max(peak_vals, na.rm = TRUE),
        reps = reps
      )
      idx <- idx + 1L
    }
  } else if (identical(target, "conv_reuse")) {
    flags <- c(FALSE, TRUE)
    sim_cfg <- perf_cfg$sim %||% list()
    for (flag in flags) {
      sim_cfg$conv_reuse <- flag
      perf_cfg$sim <- sim_cfg
      wall_vals <- numeric(reps)
      peak_vals <- numeric(reps)
      for (rep_i in seq_len(reps)) {
        run <- exdyn_perf_run_profile(profile, perf_cfg, label = ifelse(flag, "reuse_on", "reuse_off"))
        stage <- run$stage_records %>%
          dplyr::filter(.data$stage %in% c("sim_total", "simulate_tx")) %>%
          dplyr::summarise(
            wall_sec = sum(.data$wall_sec, na.rm = TRUE),
            peak_rss_mb = max(.data$rss_peak_mb, .data$rss_mb, na.rm = TRUE)
          )
        wall_vals[rep_i] <- stage$wall_sec
        peak_vals[rep_i] <- stage$peak_rss_mb
      }
      out[[idx]] <- tibble::tibble(
        reuse_buffer = flag,
        wall_sec = mean(wall_vals),
        wall_sd = stats::sd(wall_vals),
        peak_rss_mb = max(peak_vals, na.rm = TRUE),
        reps = reps
      )
      idx <- idx + 1L
    }
  } else {
    stop("Unknown optimisation target: ", target)
  }
  dplyr::bind_rows(out)
}

#' Guardrail run for CI-safe checks
#' @keywords internal
exdyn_perf_guardrail_run <- function() {
  cfg <- list(
    profiles = list(
      smoke = list(
        grid = list(type = "toy", nx = 12, ny = 12, cell_km = 10, riparian_frac = 0.6, region_n = 2),
        years = c(1990, 2000),
        dispersal = TRUE,
        include_observation = FALSE,
        mask = "riparian",
        seed = 77,
        arrival = list(pattern = "gradient", noise_sd = 1, span_frac = 0.7)
      )
    ),
    sim = list(
      K0 = 120,
      rmax = 0.4,
      A_over_K = 0.1,
      alpha = 0.2,
      disp_mean_km = 10,
      pred_c = 0.8,
      pred_h = 30,
      pred_scale = 1,
      gamma = 1,
      ramp_years = 6,
      pred_type = "II",
      pre_leak = 0,
      truth_frac = 0.02,
      truth_rel0 = 0.5,
      conv_reuse = TRUE
    ),
    tx_cfg = list(),
    compat = list()
  )
  run <- exdyn_perf_run_profile(cfg$profiles$smoke, cfg, label = "guardrail")
  runtime <- sum(run$stage_records$wall_sec, na.rm = TRUE)
  peak_rss <- max(run$stage_records$rss_peak_mb, run$stage_records$rss_mb, na.rm = TRUE)
  list(runtime_sec = runtime, peak_rss_mb = peak_rss)
}
