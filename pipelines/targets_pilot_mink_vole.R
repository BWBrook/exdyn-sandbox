targets_pilot_mink_vole <- function(cfg_path = "config/realdata.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  wo8_log_start_target <- tar_target(
    wo8_log_start,
    {
      dir.create("logs", showWarnings = FALSE)
      msg <- sprintf("[%s] WO9b pilot start", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      cat(msg, "\n", file = file.path("logs", "wo8.log"), append = TRUE)
      cat(msg, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(msg, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      msg
    },
    cue = tar_cue("always"),
    deployment = "main"
  )
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
      delta_cols <- grep("^delta_", names(theta), value = TRUE)
      delta_lookup <- NULL
      if (length(delta_cols)) {
        delta_lookup <- purrr::map_dbl(delta_cols, ~ theta[[.x]][[1]])
        names(delta_lookup) <- gsub("^delta_", "", delta_cols)
      }
      T_P_base <- pilot_mink_field_default[["T_P"]]
      T_P_adj <- exdyn_adjust_arrival_matrix(T_P_base, pilot_grid_info, delta_lookup, pilot_years)
      riparian_mask <- pilot_grid_info[["riparian_matrix"]] %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      T_P_adj[!riparian_mask] <- NA_real_
      TX <- exdyn_simulate_tx_only(
        grid_info = pilot_grid_info,
        years = pilot_years,
        T_P = T_P_adj,
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
        pred = list(
          type = "II",
          c = theta$pred_c[[1]],
          h = theta$pred_h[[1]],
          scale = theta$pred_scale[[1]] %||% 1,
          gamma = theta$gamma[[1]] %||% 1
        ),
        pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
        log_mem = isTRUE(log_mem_flag),
        log_tag = sprintf("draw %03d", draw),
        mask = riparian_mask
      )
      TX[!riparian_mask] <- NA_real_
      saveRDS(TX, tx_path)
      score <- exdyn_score(
        pilot_vole_tx[["matrix"]],
        T_P_adj,
        TX,
        pilot_cfg$pilot$compat
      )
      delta_row <- if (length(delta_cols)) {
        tibble::as_tibble_row(setNames(delta_lookup, delta_cols))
      } else {
        tibble::tibble()
      }
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
          K0 = theta$K0[[1]],
          pred_scale = theta$pred_scale[[1]],
          gamma = theta$gamma[[1]]
        ),
        delta_row,
        score
      )
      coverage_sim <- if (any(riparian_mask, na.rm = TRUE)) {
        mean(is.finite(TX[riparian_mask]), na.rm = TRUE)
      } else {
        NA_real_
      }
      meta_path <- file.path(pilot_tx_meta_dir, sprintf("tx_%03d.json", draw))
      jsonlite::write_json(
        list(
          draw = draw,
          params = result %>%
            dplyr::select(tidyselect::any_of(c(
              "alpha", "disp_mean_km", "disp_mean_cells", "A_over_K",
              "pred_c", "pred_h", "pred_scale", "gamma",
              delta_cols,
              "ramp_years", "rmax", "K0"
            ))) %>%
            dplyr::slice(1) %>%
            as.list(),
          loss = result$loss,
          coverage = coverage_sim,
          delta_region = delta_lookup,
          tx_path = tx_path
        ),
        meta_path,
        auto_unbox = TRUE,
        pretty = TRUE
      )
      base::gc()
      result %>% dplyr::mutate(
        coverage_sim = coverage_sim,
        tx_meta = meta_path
      )
    },
    pattern = map(pilot_theta_rows),
    iteration = "list"
  )
  list(
    wo8_log_start_target,
    tar_target_raw(
      "pilot_cfg",
      rlang::expr({
        wo8_log_start
        yaml::read_yaml(!!cfg_path)
      })
    ),
    tar_target(pilot_years, seq.int(pilot_cfg$pilot$years[1], pilot_cfg$pilot$years[2])),
    tar_target(pilot_grid, exdyn_make_grid(
      country_code = pilot_cfg$gbif$country,
      cell_km = pilot_cfg$pilot$grid_cell_km,
      crs_out = pilot_cfg$pilot$crs_out
    ), deployment = "main"),
    tar_target(pilot_rivers, {
      try_osm <- try(
        exdyn_fetch_rivers_osm(pilot_grid, pilot_cfg$pilot$crs_out),
        silent = TRUE
      )
      if (!inherits(try_osm, "try-error") && nrow(try_osm)) {
        try_osm
      } else {
        exdyn_fetch_rivers_ne(pilot_cfg$gbif$country, pilot_cfg$pilot$crs_out)
      }
    }, deployment = "main"),
    tar_target(pilot_riparian_mask, {
      mask <- exdyn_make_riparian_mask(
        pilot_grid,
        pilot_rivers,
        tau_km = pilot_cfg$pilot$vole$riparian_tau_km %||% 5
      )
      out_dir <- file.path("outputs", "realdata", "pilot_mink_vole")
      dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
      sf::st_write(mask, file.path(out_dir, "riparian_mask.gpkg"), delete_dsn = TRUE, quiet = TRUE)
      mask
    }, deployment = "main"),
    tar_target(pilot_grid_riparian, {
      mask_tbl <- pilot_riparian_mask |>
        sf::st_drop_geometry() |>
        dplyr::select(cell_id, river_km, riparian, region)
      pilot_grid |>
        dplyr::left_join(mask_tbl, by = "cell_id")
    }, deployment = "main"),
    tar_target(pilot_riparian_table, pilot_grid_riparian |>
                 sf::st_drop_geometry() |>
                 dplyr::select(cell_id, riparian, river_km, region)),
    tar_target(pilot_grid_info, exdyn_grid_lookup(pilot_grid_riparian)),
    tar_target(pilot_riparian_components, exdyn_riparian_components(
      pilot_grid_info[["riparian_matrix"]],
      pilot_grid_info
    )),
    tar_target(pilot_triage_dir, {
      dir <- file.path("outputs", "realdata", "pilot_mink_vole")
      dir.create(dir, recursive = TRUE, showWarnings = FALSE)
      dir
    }, deployment = "main"),
    tar_target(pilot_mask_sweep, {
      taus <- c(1, 2, 5, 10)
      mask_list <- list()
      result_list <- list()
      summary <- purrr::map_dfr(taus, function(tau) {
        mask_sf <- exdyn_make_riparian_mask(pilot_grid, pilot_rivers, tau_km = tau)
        lookup <- pilot_grid_info$lookup |>
          dplyr::select(cell_id, row_idx, col_idx)
        mask_vec <- mask_sf |>
          sf::st_drop_geometry() |>
          dplyr::select(cell_id, riparian)
        mask_lookup <- lookup |>
          dplyr::left_join(mask_vec, by = "cell_id") |>
          dplyr::mutate(riparian = dplyr::coalesce(.data$riparian, FALSE)) |>
          dplyr::filter(!is.na(.data$row_idx), !is.na(.data$col_idx))
        mask_mat <- matrix(FALSE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- cbind(mask_lookup$row_idx, mask_lookup$col_idx)
        mask_mat[idx] <- mask_lookup$riparian
        mask_list[[as.character(tau)]] <<- mask_mat
        cfg_local <- pilot_cfg$pilot$vole
        res <- exdyn_tx_apply_cfg(
          pilot_vole_cells,
          pilot_cfg$pilot$years,
          cfg_local,
          pilot_grid_info,
          effort_cells = pilot_mammal_cells,
          normalize_by = cfg_local$normalize_by %||% "mammal",
          mask = mask_mat
        )
        result_list[[as.character(tau)]] <<- res
        tibble::tibble(
          tau_km = tau,
          n_cells_riparian = sum(mask_mat, na.rm = TRUE),
          n_tx_obs = sum(is.na(res$results$reason)),
          coverage = ifelse(
            sum(mask_mat, na.rm = TRUE) > 0,
            sum(is.na(res$results$reason)) / sum(mask_mat, na.rm = TRUE),
            NA_real_
          )
        )
      })
      readr::write_csv(summary, file.path(pilot_triage_dir, "riparian_mask_sweep.csv"))
      list(summary = summary, matrices = mask_list, results = result_list)
    }, deployment = "main"),
    tar_target(pilot_mask_summary, pilot_mask_sweep$summary),
    tar_target(pilot_mask_matrices, pilot_mask_sweep$matrices),
    tar_target(pilot_mask_results, pilot_mask_sweep$results),
    tar_target(pilot_mask_results_csv, {
      res_tbl <- purrr::imap_dfr(pilot_mask_results, function(res, tau) {
        res$results |>
          dplyr::mutate(tau_km = as.numeric(tau))
      })
      readr::write_csv(res_tbl, file.path(pilot_triage_dir, "mask_tau_results.csv"))
      res_tbl
    }),
    tar_target(pilot_mink_arrivals, real_arrivals_smooth),
    tar_target(pilot_effort_taxa, pilot_cfg$pilot$vole$normalize_taxa %||% list()),
    tar_target(pilot_effort_years, pilot_cfg$pilot$vole$normalize_years %||% pilot_cfg$pilot$years),
    tar_target(pilot_effort_max_records, pilot_cfg$pilot$vole$normalize_max_records %||% pilot_cfg$cache$max_records),
    tar_target(pilot_mammal_gbif, exdyn_gbif_target_group(
      taxa = pilot_effort_taxa,
      group = "Mammalia",
      rank = "CLASS",
      country = pilot_cfg$gbif$country,
      years = pilot_effort_years,
      cache_dir = "data/raw/gbif",
      max_records = pilot_effort_max_records,
      force = isTRUE(pilot_cfg$cache$force_redownload)
    )),
    tar_target(pilot_mammal_cells, {
      cells <- exdyn_points_to_grid(pilot_mammal_gbif, pilot_grid_riparian)
      riparian_ids <- pilot_riparian_table$cell_id[pilot_riparian_table$riparian]
      dplyr::semi_join(cells, tibble::tibble(cell_id = riparian_ids), by = "cell_id")
    }, deployment = "main"),
    tar_target(pilot_vole_gbif, exdyn_gbif_species(
      sci = pilot_cfg$species$vole$scientific_name,
      rank = pilot_cfg$species$vole$gbif_rank,
      country = pilot_cfg$gbif$country,
      years = pilot_cfg$pilot$years,
      cache_dir = "data/raw/gbif",
      max_records = pilot_cfg$cache$max_records,
      force = isTRUE(pilot_cfg$cache$force_redownload)
    )),
    tar_target(pilot_vole_cells, {
      cells <- exdyn_points_to_grid(pilot_vole_gbif, pilot_grid_riparian)
      riparian_ids <- pilot_riparian_table$cell_id[pilot_riparian_table$riparian]
      dplyr::semi_join(cells, tibble::tibble(cell_id = riparian_ids), by = "cell_id")
    }, deployment = "main"),
    tar_target(pilot_vole_tx, exdyn_tx_map(
      pilot_vole_cells,
      pilot_cfg$pilot$years,
      pilot_cfg$pilot$vole,
      pilot_grid_info,
      effort_cells = pilot_mammal_cells,
      mask = pilot_grid_info[["riparian_matrix"]]
    )),
    tar_target(pilot_vole_tx_qc, {
      counts <- pilot_vole_tx$counts
      if (!nrow(counts)) {
        return(list(correlation = NA_real_, n_changed = 0L, changed = tibble::tibble()))
      }
      mammal_counts <- counts %>% dplyr::filter(.data$n_mammal > 0)
      cor_val <- if (nrow(mammal_counts) >= 10) {
        suppressWarnings(stats::cor(
          mammal_counts$n_obs,
          mammal_counts$norm_mammal,
          use = "complete.obs",
          method = "spearman"
        ))
      } else {
        NA_real_
      }
      cfg_vol <- pilot_cfg$pilot$vole
      nested <- counts %>%
        dplyr::group_by(cell_id, row, col, row_idx, col_idx) %>%
        tidyr::nest(counts = c(year, n_obs, n_mammal, norm_mammal)) %>%
        dplyr::ungroup()
      tx_norm <- purrr::map_int(
        nested$counts,
        ~ exdyn_tx_from_po(.x, pilot_cfg$pilot$years, cfg_vol, normalize_by = cfg_vol$normalize_by %||% NULL)$tx %||% NA_integer_
      )
      tx_raw <- purrr::map_int(
        nested$counts,
        ~ exdyn_tx_from_po(.x, pilot_cfg$pilot$years, cfg_vol, normalize_by = NULL)$tx %||% NA_integer_
      )
      changed_idx <- which(!(tx_norm == tx_raw | (is.na(tx_norm) & is.na(tx_raw))))
      changed_tbl <- if (length(changed_idx)) {
        nested[changed_idx, c("cell_id", "row", "col")] %>%
          dplyr::mutate(tx_norm = tx_norm[changed_idx], tx_raw = tx_raw[changed_idx])
      } else {
        tibble::tibble()
      }
      dir.create("logs", showWarnings = FALSE)
      mode_label <- cfg_vol$normalize_by %||% "none"
      taxa_n <- length(cfg_vol$normalize_taxa %||% list())
      log_line <- sprintf(
        "[%s] Vole TX normalisation mode=%s taxa=%d: spearman=%.3f changed_cells=%d",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        mode_label,
        taxa_n,
        ifelse(is.finite(cor_val), cor_val, NA_real_),
        nrow(changed_tbl)
      )
      cat(log_line, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      list(correlation = cor_val, n_changed = nrow(changed_tbl), changed = changed_tbl)
    }, deployment = "main"),
    tar_target(pilot_tx_hyper_grid, exdyn_tx_hyper_grid(
      baseline_window = c(6, 8, 10),
      hold_years = c(2, 3, 5),
      drop_fraction = c(0.2, 0.3, 0.4)
    )),
    tar_target(pilot_tx_sweep, {
      mask_tau2 <- pilot_mask_matrices[[as.character(2)]]
      hyper <- pilot_tx_hyper_grid
      res_list <- vector("list", nrow(hyper))
      funnel_list <- vector("list", nrow(hyper))
      for (i in seq_len(nrow(hyper))) {
        cfg_local <- pilot_cfg$pilot$vole
        cfg_local$baseline_window <- hyper$baseline_window[i]
        cfg_local$hold_years <- hyper$hold_years[i]
        cfg_local$drop_fraction <- hyper$drop_fraction[i]
        res <- exdyn_tx_apply_cfg(
          pilot_vole_cells,
          pilot_cfg$pilot$years,
          cfg_local,
          pilot_grid_info,
          effort_cells = pilot_mammal_cells,
          normalize_by = cfg_local$normalize_by %||% "mammal",
          mask = mask_tau2
        )
        res_tbl <- res$results |>
          dplyr::mutate(
            baseline_window = hyper$baseline_window[i],
            hold_years = hyper$hold_years[i],
            drop_fraction = hyper$drop_fraction[i]
          )
        res_list[[i]] <- res_tbl
        funnel_list[[i]] <- res$funnel |>
          dplyr::mutate(
            baseline_window = hyper$baseline_window[i],
            hold_years = hyper$hold_years[i],
            drop_fraction = hyper$drop_fraction[i]
          )
      }
      results <- dplyr::bind_rows(res_list)
      funnels <- dplyr::bind_rows(funnel_list)
      readr::write_csv(results, file.path(pilot_triage_dir, "tx_hyper_results.csv"))
      readr::write_csv(funnels, file.path(pilot_triage_dir, "tx_hyper_funnel.csv"))
      list(results = results, funnels = funnels)
    }, deployment = "main"),
    tar_target(pilot_tx_hyper_summary, exdyn_funnel_summary(pilot_tx_sweep$results)),
    tar_target(pilot_baseline_funnel, {
      res <- exdyn_tx_apply_cfg(
        pilot_vole_cells,
        pilot_cfg$pilot$years,
        pilot_cfg$pilot$vole,
        pilot_grid_info,
        effort_cells = pilot_mammal_cells,
        normalize_by = pilot_cfg$pilot$vole$normalize_by %||% "mammal",
        mask = pilot_grid_info[["riparian_matrix"]]
      )
      readr::write_csv(res$funnel, file.path(pilot_triage_dir, "funnel_baseline.csv"))
      res$funnel
    }, deployment = "main"),
    tar_target(pilot_resolution_sweep, {
      resolutions <- c(15, 20)
      res_tables <- list()
      summary <- purrr::map_dfr(resolutions, function(res_km) {
        agg <- exdyn_aggregate_grid(pilot_grid, res_km)
        grid_new <- agg$grid
        map <- agg$mapping_tbl

        vole_rebin <- exdyn_rebin_cells(pilot_vole_cells, map, grid_new)
        mammal_rebin <- exdyn_rebin_cells(pilot_mammal_cells, map, grid_new)

        river_agg <- pilot_riparian_table |>
          dplyr::left_join(map, by = c("cell_id" = "cell_id_old")) |>
          dplyr::filter(!is.na(.data$cell_id_new)) |>
          dplyr::group_by(cell_id_new) |>
          dplyr::summarise(
            river_km = sum(.data$river_km, na.rm = TRUE),
            region = {
              vals <- .data$region[!is.na(.data$region)]
              if (length(vals)) as.character(vals[1]) else NA_character_
            },
            .groups = "drop"
          )

        grid_new <- grid_new |>
          dplyr::left_join(river_agg, by = c("cell_id" = "cell_id_new")) |>
          dplyr::mutate(
            river_km = dplyr::coalesce(.data$river_km, 0),
            region = dplyr::coalesce(.data$region, "UNKNOWN"),
            riparian = .data$river_km >= 2
          )

        grid_info_new <- exdyn_grid_lookup(grid_new)

        arrival_lookup <- pilot_grid_info$lookup |>
          dplyr::mutate(T_P = pilot_mink_field_default$T_P[cbind(.data$row_idx, .data$col_idx)]) |>
          dplyr::left_join(map, by = c("cell_id" = "cell_id_old")) |>
          dplyr::filter(!is.na(.data$cell_id_new)) |>
          dplyr::group_by(cell_id_new) |>
          dplyr::summarise(T_P = mean(.data$T_P, na.rm = TRUE), .groups = "drop") |>
          dplyr::rename(cell_id = cell_id_new)

        cfg_res <- pilot_cfg$pilot$vole
        cfg_res$baseline_window <- 8
        cfg_res$hold_years <- 3
        cfg_res$drop_fraction <- 0.3
        cfg_res$normalize_by <- cfg_res$normalize_by %||% "mammal"

        res <- exdyn_tx_apply_cfg(
          vole_rebin,
          pilot_cfg$pilot$years,
          cfg_res,
          grid_info_new,
          effort_cells = mammal_rebin,
          normalize_by = cfg_res$normalize_by,
          mask = grid_info_new[["riparian_matrix"]]
        )

        detail <- res$results |>
          dplyr::left_join(arrival_lookup, by = "cell_id") |>
          dplyr::mutate(resolution_km = res_km)

        res_tables[[as.character(res_km)]] <<- detail

        valid <- detail |>
          dplyr::filter(is.finite(.data$tx_obs), is.finite(.data$T_P))

        r2_val <- if (nrow(valid) >= 3) {
          summary(stats::lm(tx_obs ~ T_P, data = valid))$r.squared
        } else {
          NA_real_
        }
        lag_val <- if (nrow(valid)) mean(valid$tx_obs - valid$T_P) else NA_real_

        tibble::tibble(
          resolution_km = res_km,
          n_units = res$funnel$n_units[res$funnel$stage == "mask"],
          n_tx_obs = sum(is.na(detail$reason)),
          coverage = ifelse(
            res$funnel$n_units[res$funnel$stage == "mask"] > 0,
            sum(is.na(detail$reason)) / res$funnel$n_units[res$funnel$stage == "mask"],
            NA_real_
          ),
          r2_arrival = r2_val,
          lag_mean = lag_val
        )
      })

      readr::write_csv(summary, file.path(pilot_triage_dir, "resolution_sweep_summary.csv"))
      readr::write_csv(
        dplyr::bind_rows(res_tables),
        file.path(pilot_triage_dir, "resolution_sweep_results.csv")
      )
      list(summary = summary, details = res_tables)
    }, deployment = "main"),
    tar_target(pilot_segment_tx, {
      comp_lookup <- pilot_riparian_components$table |>
        dplyr::filter(!is.na(.data$cell_id)) |>
        dplyr::select(cell_id, comp_id, n_cells_comp)
      exdyn_segment_tx(
        pilot_vole_cells,
        comp_lookup,
        pilot_cfg$pilot$years,
        pilot_cfg$pilot$vole,
        normalize_by = pilot_cfg$pilot$vole$normalize_by %||% "mammal",
        effort_cells = pilot_mammal_cells
      )
    }),
    tar_target(pilot_segment_cell_tx, {
      comp_lookup <- pilot_riparian_components$table |>
        dplyr::filter(!is.na(.data$cell_id)) |>
        dplyr::select(cell_id, comp_id)
      comp_lookup |>
        dplyr::left_join(pilot_segment_tx, by = "comp_id")
    }),
    tar_target(pilot_segment_tx_csv, {
      readr::write_csv(pilot_segment_tx, file.path(pilot_triage_dir, "segment_tx.csv"))
      pilot_segment_tx
    }),
    tar_target(pilot_mink_field_default, {
      delta_cfg <- pilot_cfg$pilot$mink_P$delta_region %||% list()
      delta_defaults <- if (length(delta_cfg)) {
        purrr::map_dbl(delta_cfg, ~ mean(.x))
      } else {
        NULL
      }
      exdyn_fields_from_mink(
        pilot_mink_arrivals,
        pilot_grid_info,
        pilot_years,
        ramp_years = pilot_cfg$pilot$mink_P$ramp_years,
        pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
        scale = pilot_cfg$pilot$mink_P$scale %||% 1,
        gamma = pilot_cfg$pilot$mink_P$gamma %||% 1,
        delta_region = delta_defaults
      )
    }),
    tar_target(pilot_c_star_summary, {
      screen_cfg <- pilot_cfg$pilot$screen
      nx <- pilot_grid_info$nx
      ny <- pilot_grid_info$ny
      K0_mat <- matrix(screen_cfg$K0, nrow = nx, ncol = ny)
      rmax_mid <- mean(screen_cfg$rmax)
      h_med <- stats::median(screen_cfg$pred_h)
      c_star <- exdyn_c_critical(K0_mat, rmax_mid, h_med)
      arrivals_mask <- is.finite(pilot_mink_field_default$T_P)
      vals <- c_star[arrivals_mask]
      vals <- vals[is.finite(vals)]
      if (!length(vals)) {
        vals <- c_star[is.finite(c_star)]
      }
      if (length(vals) > 5000) {
        set.seed(123)
        vals <- sample(vals, size = 5000)
      }
      quant <- if (length(vals)) stats::quantile(vals, probs = c(0.25, 0.5, 0.75, 0.9), na.rm = TRUE) else {
        stats::setNames(rep(NA_real_, 4), c("25%", "50%", "75%", "90%"))
      }
      bounds <- if (length(vals)) {
        lower <- max(0.2, 0.6 * quant["50%"])
        upper <- max(lower + 1e-3, min(3.0, 3.0 * quant["90%"]))
        c(lower, upper)
      } else {
        screen_cfg$pred_c
      }
      dir.create("logs", showWarnings = FALSE)
      log_line <- sprintf(
        "[%s] c* quantiles p25=%.3f p50=%.3f p75=%.3f p90=%.3f; pred_c bounds=[%.3f, %.3f]",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        quant["25%"], quant["50%"], quant["75%"], quant["90%"],
        bounds[1], bounds[2]
      )
      cat(log_line, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      list(values = c_star, quantiles = quant, bounds = bounds)
    }, deployment = "main"),
    tar_target(pilot_screen_cfg, {
      cfg <- pilot_cfg$pilot$screen
      if (isTRUE(cfg$adapt_c)) {
        bounds <- pilot_c_star_summary$bounds
        if (length(bounds) == 2 && all(is.finite(bounds))) {
          cfg$pred_c <- bounds
        }
      }
      cfg
    }),
    tar_target(pilot_guard_cfg, {
      cfg <- pilot_screen_cfg
      guard_draws <- min(12L, cfg$n_draws %||% 12L)
      if (guard_draws <= 0L) {
        return(list(cfg = cfg, attempts = list()))
      }
      run_guard <- function(cfg_local, attempt) {
        theta_guard <- exdyn_param_lhs(
          cfg_local,
          n = guard_draws,
          cell_km = pilot_cfg$pilot$grid_cell_km,
          seed = 900 + attempt
        )
        coverage <- numeric(nrow(theta_guard))
        riparian_mask <- pilot_grid_info[["riparian_matrix"]] %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        for (i in seq_len(nrow(theta_guard))) {
          pars <- list(
            rmax = theta_guard$rmax[i],
            A_frac = theta_guard$A_over_K[i] * theta_guard$K0[i],
            beta_H = 0,
            d = 0.03
          )
          delta_cols_guard <- grep("^delta_", names(theta_guard), value = TRUE)
          delta_lookup_guard <- NULL
          if (length(delta_cols_guard)) {
            delta_lookup_guard <- setNames(as.numeric(theta_guard[i, delta_cols_guard, drop = TRUE]), gsub("^delta_", "", delta_cols_guard))
          }
          T_P_adj_guard <- exdyn_adjust_arrival_matrix(pilot_mink_field_default$T_P, pilot_grid_info, delta_lookup_guard, pilot_years)
          T_P_adj_guard[!riparian_mask] <- NA_real_
          TX_guard <- exdyn_simulate_tx_only(
            grid_info = pilot_grid_info,
            years = pilot_years,
            T_P = T_P_adj_guard,
            ramp_years = theta_guard$ramp_years[i],
            pars = pars,
            K0 = theta_guard$K0[i],
            alpha = theta_guard$alpha[i],
            disp_mean_cells = theta_guard$disp_mean_cells[i],
            pred = list(
              type = "II",
              c = theta_guard$pred_c[i],
              h = theta_guard$pred_h[i],
              scale = theta_guard$pred_scale[i],
              gamma = theta_guard$gamma[i]
            ),
            pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak %||% 0,
            log_mem = FALSE,
            mask = riparian_mask
          )
          TX_guard[!riparian_mask] <- NA_real_
          coverage[i] <- if (any(riparian_mask, na.rm = TRUE)) mean(is.finite(TX_guard[riparian_mask]), na.rm = TRUE) else NA_real_
        }
        list(
          cfg = cfg_local,
          theta = theta_guard,
          coverage = coverage,
          mean_cov = mean(coverage),
          attempt = attempt
        )
      }
      dir.create("logs", showWarnings = FALSE)
      guard1 <- run_guard(cfg, attempt = 1)
      cat(
        sprintf(
          "[%s] Guard attempt 1 coverage=%.4f",
          format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          guard1$mean_cov
        ),
        "\n",
        file = file.path("logs", "wo9.log"),
        append = TRUE
      )
      cat(
        sprintf(
          "[%s] Guard attempt 1 coverage=%.4f",
          format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          guard1$mean_cov
        ),
        "\n",
        file = file.path("logs", "wo9b.log"),
        append = TRUE
      )
      attempts <- list(guard1)
      final_cfg <- cfg
      if (is.finite(guard1$mean_cov) && guard1$mean_cov < 0.01) {
        widened <- cfg
        widened$pred_scale[2] <- widened$pred_scale[2] * 2
        upper_c <- pilot_c_star_summary$bounds[2] %||% widened$pred_c[2]
        widened$pred_c[2] <- max(widened$pred_c[1] + 1e-3, min(5, upper_c * 1.5))
        guard2 <- run_guard(widened, attempt = 2)
        cat(
          sprintf(
            "[%s] Guard attempt 2 coverage=%.4f (pred_scale_max=%.3f pred_c_max=%.3f)",
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            guard2$mean_cov,
            widened$pred_scale[2],
            widened$pred_c[2]
          ),
          "\n",
          file = file.path("logs", "wo9.log"),
          append = TRUE
        )
        cat(
          sprintf(
            "[%s] Guard attempt 2 coverage=%.4f (pred_scale_max=%.3f pred_c_max=%.3f)",
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            guard2$mean_cov,
            widened$pred_scale[2],
            widened$pred_c[2]
          ),
          "\n",
          file = file.path("logs", "wo9b.log"),
          append = TRUE
        )
        attempts <- c(attempts, list(guard2))
        if (is.finite(guard2$mean_cov) && guard2$mean_cov > guard1$mean_cov) {
          cat(
            sprintf(
              "[%s] Guard accepted widened bounds (coverage %.4f → %.4f)",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              guard1$mean_cov,
              guard2$mean_cov
            ),
            "\n",
            file = file.path("logs", "wo9.log"),
            append = TRUE
          )
          cat(
            sprintf(
              "[%s] Guard accepted widened bounds (coverage %.4f → %.4f)",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              guard1$mean_cov,
              guard2$mean_cov
            ),
            "\n",
            file = file.path("logs", "wo9b.log"),
            append = TRUE
          )
          final_cfg <- guard2$cfg
        } else {
          cat(
            sprintf(
              "[%s] Guard coverage did not improve; retaining original bounds",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")
            ),
            "\n",
            file = file.path("logs", "wo9.log"),
            append = TRUE
          )
          cat(
            sprintf(
              "[%s] Guard coverage did not improve; retaining original bounds",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")
            ),
            "\n",
            file = file.path("logs", "wo9b.log"),
            append = TRUE
          )
        }
      }
      list(cfg = final_cfg, attempts = attempts)
    }, deployment = "main"),
    tar_target(pilot_theta, exdyn_param_lhs(
      pilot_guard_cfg$cfg,
      n = pilot_guard_cfg$cfg$n_draws,
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
    tar_target(pilot_tx_meta_dir, {
      dir <- file.path(pilot_tx_dir, "meta")
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
      vole_table <- pilot_vole_tx$table %>%
        dplyr::mutate(
          crs = pilot_cfg$pilot$crs_out,
          cell_km = pilot_cfg$pilot$grid_cell_km
        )
      params_table <- pilot_theta %>%
        dplyr::mutate(
          crs = pilot_cfg$pilot$crs_out,
          cell_km = pilot_cfg$pilot$grid_cell_km
        )
      compat_table <- pilot_screen %>%
        dplyr::mutate(
          crs = pilot_cfg$pilot$crs_out,
          cell_km = pilot_cfg$pilot$grid_cell_km
        )
      readr::write_csv(vole_table, file.path(pilot_output_dir, "vole_tx_obs_riparian.csv"))
      readr::write_csv(params_table, file.path(pilot_output_dir, "params_lhs.csv"))
      readr::write_csv(compat_table, file.path(pilot_output_dir, "compatibility_ranked_riparian.csv"))
      changes_path <- file.path(pilot_output_dir, "vole_tx_normalisation_changes.csv")
      if (nrow(pilot_vole_tx_qc$changed)) {
        readr::write_csv(pilot_vole_tx_qc$changed, changes_path)
      } else {
        readr::write_csv(tibble::tibble(), changes_path)
      }
      file.path(
        pilot_output_dir,
        c("vole_tx_obs_riparian.csv", "params_lhs.csv", "compatibility_ranked_riparian.csv", "vole_tx_normalisation_changes.csv")
      )
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
    tar_target(pilot_report_html, {
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
      quarto::quarto_render("reports/pilot_mink_vole.qmd", output_format = "html")
    }, format = "file"),
    tar_target(pilot_report_pdf, {
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
      quarto::quarto_render("reports/pilot_mink_vole.qmd", output_format = "pdf")
    }, format = "file"),
    tar_target(pilot_summary, {
      best <- dplyr::arrange(pilot_screen, .data$rank) %>% dplyr::slice_head(n = 1)
      n_mink_cells <- sum(!is.na(as.vector(pilot_mink_field_default$T_P)))
      n_vole_cells <- sum(!is.na(as.vector(pilot_vole_tx$matrix)))
      baseline_units <- nrow(pilot_vole_tx$table)
      baseline_tx <- sum(!is.na(pilot_vole_tx$table$tx_obs))
      summary <- if (!nrow(best)) {
        "WO9b summary: no compatible parameter sets"
      } else {
        png_dir <- file.path("outputs", "realdata", "pilot_mink_vole")
        png_paths <- file.path(
          png_dir,
          c("TX_obs_riparian_map.png", "TX_sim_rank01.png", "TX_diff_rank01.png", "TX_sim_rank02.png", "TX_sim_rank03.png")
        )
        sprintf(
          "WO9b summary: n_mink_cells=%d n_vole_cells=%d baseline_units=%d baseline_tx=%d r2=%.3f lag=%.2f coverage=%.3f best_draw=%s PNGs=%s",
          n_mink_cells,
          n_vole_cells,
          baseline_units,
          baseline_tx,
          best$r2_arrival,
          best$lag_mean,
          best$coverage,
          best$draw,
          paste(png_paths, collapse = ";")
        )
      }
      cat(summary, "\n")
      dir.create("logs", showWarnings = FALSE)
      log_line <- sprintf("[%s] %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), summary)
      cat(log_line, "\n", file = file.path("logs", "wo8.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      summary
    }, deployment = "main")
  )
}
