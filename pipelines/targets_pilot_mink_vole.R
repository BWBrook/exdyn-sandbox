targets_pilot_mink_vole <- function(cfg_path = "config/realdata.yaml") {
  cfg_path <- normalizePath(cfg_path, mustWork = FALSE)
  wo8_log_start_target <- tar_target(
    wo8_log_start,
    {
      dir.create("logs", showWarnings = FALSE)
      msg <- sprintf("[%s] WO9d pilot start", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
      cat(msg, "\n", file = file.path("logs", "wo8.log"), append = TRUE)
      cat(msg, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(msg, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      cat(msg, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
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
      unit_info <- pilot_unit_structure
      unit_lookup <- unit_info$lookup
      unit_mask <- unit_info$mask %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      coverage_breaks <- unit_info$coverage_breaks
      unit_timing_stat <- unit_info$unit_timing_stat %||% (pilot_cfg$pilot$loss$unit_timing_stat %||% "median")
      adjacency <- unit_info$adjacency
      region_lookup <- unit_info$region_lookup
      delta_cols <- grep("^delta_", names(theta), value = TRUE)
      delta_lookup_region <- NULL
      if (length(delta_cols)) {
        delta_lookup_region <- purrr::map_dbl(delta_cols, ~ theta[[.x]][[1]])
        names(delta_lookup_region) <- gsub("^delta_", "", delta_cols)
      }
      T_P_base <- pilot_mink_field_default[["T_P"]]
      T_P_adj <- exdyn_adjust_arrival_matrix(T_P_base, pilot_grid_info, delta_lookup_region, pilot_years)
      T_P_adj[!unit_mask] <- NA_real_
      sigma_val <- theta$pred_scale_re_sigma[[1]] %||% 0
      unit_ids <- unit_info$unit_ids %||% unique(unit_lookup$unit_id)
      unit_effects <- exdyn_sample_pred_scale_re(unit_ids, sigma = sigma_val, seed = 1500 + draw)
      scale_matrix <- exdyn_scale_matrix_from_units(pilot_grid_info, unit_lookup, unit_effects)
      TX_idx <- exdyn_simulate_tx_only(
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
          gamma = theta$gamma[[1]] %||% 1,
          scale_matrix = scale_matrix
        ),
        pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
        log_mem = isTRUE(log_mem_flag),
        log_tag = sprintf("draw %03d", draw),
        mask = unit_mask
      )
      TX_idx[!unit_mask] <- NA_integer_
      TX_mat <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      idx_valid <- is.finite(TX_idx)
      if (any(idx_valid)) {
        TX_mat[idx_valid] <- pilot_years[TX_idx[idx_valid]]
      }
      TX_mat[!unit_mask] <- NA_real_
      saveRDS(TX_mat, tx_path)
      delta_penalty_cfg <- pilot_cfg$pilot$delta_penalty %||% list(lambda_mag = 0, lambda_tv = 0)
      delta_unit_values <- NULL
      if (!is.null(delta_lookup_region) && nrow(region_lookup)) {
        delta_unit_values <- region_lookup %>%
          dplyr::mutate(delta = delta_lookup_region[.data$region]) %>%
          dplyr::mutate(delta = dplyr::coalesce(.data$delta, 0)) %>%
          { stats::setNames(.$delta, .$unit_id) }
      }
      score <- exdyn_loss_real(
        TX_obs = pilot_vole_tx[["matrix"]],
        T_P = T_P_adj,
        TX_sim = TX_mat,
        unit_lookup = unit_lookup,
        coverage_breaks = coverage_breaks,
        compat_cfg = pilot_cfg$pilot$compat,
        delta_lookup = delta_unit_values,
        delta_adj = adjacency,
        delta_penalty_cfg = delta_penalty_cfg,
        unit_timing_stat = unit_timing_stat
      )
      compat_cfg <- pilot_cfg$pilot$compat
      lag_range <- compat_cfg$lag_range %||% c(-Inf, Inf)
      compatible <- isTRUE(is.finite(score$r2_arrival) && score$r2_arrival >= (compat_cfg$min_r2_arrival %||% -Inf)) &&
        isTRUE(is.finite(score$lag_mean) &&
                 score$lag_mean >= lag_range[1] &&
                 score$lag_mean <= lag_range[2]) &&
        isTRUE(score$coverage >= (compat_cfg$min_coverage %||% 0))
      delta_row <- if (length(delta_cols)) {
        tibble::as_tibble_row(setNames(delta_lookup_region, delta_cols))
      } else {
        tibble::tibble()
      }
      loss_terms <- tibble::as_tibble_row(score$loss_terms) %>%
        dplyr::rename_with(~ paste0("loss_", .x))
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
          gamma = theta$gamma[[1]],
          pred_scale_re_sigma = sigma_val
        ),
        delta_row,
        tibble::tibble(
          r2_arrival = score$r2_arrival,
          lag_mean = score$lag_mean,
          coverage = score$coverage,
          anisotropy_obs = score$anisotropy_obs,
          anisotropy_sim = score$anisotropy_sim,
          anisotropy_gap = score$anisotropy_gap,
          coverage_curve_rmse = score$coverage_curve_rmse,
          delta_penalty = score$delta_penalty,
          unit_timing_stat = score$unit_timing_stat,
          loss = score$loss,
          compatible = compatible
        ),
        loss_terms
      )
      coverage_sim <- score$coverage
      meta_path <- file.path(pilot_tx_meta_dir, sprintf("tx_%03d.json", draw))
      jsonlite::write_json(
        list(
          draw = draw,
          params = result %>%
            dplyr::select(tidyselect::any_of(c(
              "alpha", "disp_mean_km", "disp_mean_cells", "A_over_K",
              "pred_c", "pred_h", "pred_scale", "gamma", "pred_scale_re_sigma",
              delta_cols,
              "ramp_years", "rmax", "K0"
            ))) %>%
            dplyr::slice(1) %>%
            as.list(),
          loss = result$loss,
          coverage = coverage_sim,
          unit_timing_stat = unit_timing_stat,
          delta_region = delta_lookup_region,
          tx_path = tx_path,
          coverage_curve_obs = score$coverage_curve_obs,
          coverage_curve_sim = score$coverage_curve_sim,
          loss_terms = score$loss_terms
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
    tar_target_raw("pilot_cfg_file", rlang::expr(!!cfg_path), format = "file"),
    tar_target(pilot_cfg, {
      yaml::read_yaml(pilot_cfg_file)
    }),
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
      exdyn_points_to_grid(pilot_mammal_gbif, pilot_grid_riparian)
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
      exdyn_points_to_grid(pilot_vole_gbif, pilot_grid_riparian)
    }, deployment = "main"),
    tar_target(pilot_analysis_unit_pref, {
      tolower(pilot_cfg$pilot$analysis_unit %||% "segment")
    }),
    tar_target(pilot_vole_tx_riparian, exdyn_tx_map(
      pilot_vole_cells,
      pilot_cfg$pilot$years,
      pilot_cfg$pilot$vole,
      pilot_grid_info,
      effort_cells = pilot_mammal_cells,
      mask = pilot_grid_info[["riparian_matrix"]]
    )),
    tar_target(pilot_vole_tx_all, exdyn_tx_map(
      pilot_vole_cells,
      pilot_cfg$pilot$years,
      pilot_cfg$pilot$vole,
      pilot_grid_info,
      effort_cells = pilot_mammal_cells,
      mask = exdyn_land_mask_from_lookup(pilot_grid_info)
    )),
    tar_target(pilot_vole_tx, {
      if (identical(pilot_analysis_unit_pref, "grid_all")) {
        pilot_vole_tx_all
      } else {
        pilot_vole_tx_riparian
      }
    }),
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
      norm_res <- purrr::map(
        nested$counts,
        ~ exdyn_tx_from_po(.x, pilot_cfg$pilot$years, cfg_vol, normalize_by = cfg_vol$normalize_by %||% NULL)
      )
      raw_res <- purrr::map(
        nested$counts,
        ~ exdyn_tx_from_po(.x, pilot_cfg$pilot$years, cfg_vol, normalize_by = NULL)
      )
      tx_norm <- purrr::map_int(norm_res, ~ .x$tx %||% NA_integer_)
      tx_raw <- purrr::map_int(raw_res, ~ .x$tx %||% NA_integer_)
      changed_idx <- which(!(tx_norm == tx_raw | (is.na(tx_norm) & is.na(tx_raw))))
      changed_tbl <- if (length(changed_idx)) {
        nested[changed_idx, c("cell_id", "row", "col")] %>%
          dplyr::mutate(
            tx_norm = tx_norm[changed_idx],
            tx_raw = tx_raw[changed_idx],
            tau_norm = purrr::map_dbl(norm_res[changed_idx], ~ .x$tau %||% NA_real_),
            tau_raw = purrr::map_dbl(raw_res[changed_idx], ~ .x$tau %||% NA_real_),
            baseline_norm = purrr::map_dbl(norm_res[changed_idx], ~ .x$baseline %||% NA_real_),
            baseline_raw = purrr::map_dbl(raw_res[changed_idx], ~ .x$baseline %||% NA_real_),
            threshold_mode_norm = purrr::map_chr(norm_res[changed_idx], ~ .x$threshold_mode %||% NA_character_),
            threshold_mode_raw = purrr::map_chr(raw_res[changed_idx], ~ .x$threshold_mode %||% NA_character_),
            reason_norm = purrr::map_chr(norm_res[changed_idx], ~ .x$reason %||% NA_character_),
            reason_raw = purrr::map_chr(raw_res[changed_idx], ~ .x$reason %||% NA_character_)
          )
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
      cat(log_line, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
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
    tar_target(pilot_unit_min_tx_obs, {
      as.integer(pilot_cfg$pilot$unit_min_tx_obs %||% 50L)
    }),
    tar_target(pilot_unit_timing_stat, {
      pilot_cfg$pilot$loss$unit_timing_stat %||% "median"
    }),
    tar_target(pilot_unit_structure, {
      preferred <- pilot_analysis_unit_pref
      years_vec <- pilot_years
      coverage_breaks <- exdyn_coverage_breaks(years_vec)
      unit_min <- pilot_unit_min_tx_obs %||% 50L
      make_mask <- function(lookup_tbl) {
        mask <- matrix(FALSE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        if (nrow(lookup_tbl)) {
          idx <- cbind(lookup_tbl$row_idx, lookup_tbl$col_idx)
          mask[idx] <- TRUE
        }
        mask
      }
      build_cell_adjacency <- function(lookup_tbl) {
        if (!nrow(lookup_tbl)) {
          return(tibble::tibble(unit_i = character(), unit_j = character()))
        }
        base <- lookup_tbl %>%
          dplyr::distinct(.data$unit_id, .data$row_idx, .data$col_idx)
        shifts <- tibble::tribble(
          ~dr, ~dc,
          1L, 0L,
          -1L, 0L,
          0L, 1L,
          0L, -1L
        )
        nbr <- purrr::pmap_dfr(shifts, function(dr, dc) {
          base %>%
            dplyr::transmute(
              unit_i = .data$unit_id,
              row_idx = .data$row_idx + dr,
              col_idx = .data$col_idx + dc
            ) %>%
            dplyr::inner_join(
              base %>% dplyr::transmute(unit_j = .data$unit_id, row_idx, col_idx),
              by = c("row_idx", "col_idx")
            )
        })
        if (!nrow(nbr)) {
          return(tibble::tibble(unit_i = character(), unit_j = character()))
        }
        nbr %>%
          dplyr::filter(.data$unit_i != .data$unit_j) %>%
          dplyr::mutate(
            pair_min = pmin(.data$unit_i, .data$unit_j),
            pair_max = pmax(.data$unit_i, .data$unit_j)
          ) %>%
          dplyr::distinct(.data$pair_min, .data$pair_max) %>%
          dplyr::transmute(unit_i = .data$pair_min, unit_j = .data$pair_max)
      }
      build_grid_units <- function(grid_mode = c("grid_all", "grid_riparian")) {
        grid_mode <- match.arg(grid_mode)
        tx_src <- if (identical(grid_mode, "grid_all")) pilot_vole_tx_all else pilot_vole_tx_riparian
        tx_tbl <- tx_src$table %||% tibble::tibble()
        if (!nrow(tx_tbl)) {
          return(NULL)
        }
        rip_tbl <- pilot_riparian_table %>%
          dplyr::select(
            cell_id,
            river_km_join = river_km,
            riparian_join = riparian,
            region_join = region
          )
        lookup <- pilot_grid_info$lookup %>%
          dplyr::left_join(rip_tbl, by = "cell_id") %>%
          dplyr::mutate(
            riparian = dplyr::coalesce(.data$riparian_join, .data$riparian, FALSE),
            river_km = dplyr::coalesce(.data$river_km_join, .data$river_km, 0),
            region = dplyr::coalesce(.data$region_join, .data$region, "UNKNOWN")
          )
        if (identical(grid_mode, "grid_riparian")) {
          lookup <- lookup %>% dplyr::filter(.data$riparian)
        }
        lookup <- lookup %>%
          dplyr::filter(!is.na(.data$row_idx), !is.na(.data$col_idx)) %>%
          dplyr::mutate(unit_id = paste0("cell_", .data$cell_id))
        tx_tbl <- lookup %>%
          dplyr::select(cell_id, unit_id_lookup = unit_id, region_lookup = region) %>%
          dplyr::left_join(tx_tbl, by = "cell_id") %>%
          dplyr::mutate(
            unit_id = .data$unit_id_lookup,
            region = dplyr::coalesce(.data$region_lookup, .data$region, "UNKNOWN")
          ) %>%
          dplyr::select(-dplyr::any_of(c("unit_id_lookup", "region_lookup")))
        list(
          type = grid_mode,
          lookup = lookup %>% dplyr::select(row_idx, col_idx, unit_id, region, cell_id, dplyr::any_of(c("centroid_x", "centroid_y"))),
          mask = make_mask(lookup),
          adjacency = build_cell_adjacency(lookup),
          tx_table = tx_tbl,
          unit_ids = sort(unique(lookup$unit_id)),
          n_units = dplyr::n_distinct(lookup$unit_id),
          n_tx_obs = sum(is.finite(tx_tbl$tx_obs)),
          region_lookup = lookup %>%
            dplyr::distinct(unit_id, region, .keep_all = FALSE)
        )
      }
      build_segment_units <- function() {
        comp_tbl <- pilot_riparian_components$table
        if (!"region" %in% names(comp_tbl)) {
          comp_tbl$region <- NA_character_
        }
        comp_tbl <- comp_tbl %>%
          dplyr::left_join(
            pilot_riparian_table %>% dplyr::select(cell_id, region_join = region),
            by = "cell_id"
          ) %>%
          dplyr::mutate(
            region = dplyr::coalesce(region_join, region, "UNKNOWN")
          ) %>%
          dplyr::select(-dplyr::any_of("region_join"))
        if (!nrow(comp_tbl)) {
          return(NULL)
        }
        lookup <- comp_tbl %>%
          dplyr::filter(!is.na(comp_id))
        if (!"region" %in% names(lookup)) {
          lookup$region <- NA_character_
        }
        if (!"centroid_x" %in% names(lookup)) {
          lookup$centroid_x <- lookup$col_idx
        }
        if (!"centroid_y" %in% names(lookup)) {
          lookup$centroid_y <- lookup$row_idx
        }
        lookup <- lookup %>%
          dplyr::transmute(
            row_idx = row_idx,
            col_idx = col_idx,
            unit_id = paste0("seg_", comp_id),
            region = dplyr::coalesce(region, "UNKNOWN"),
            cell_id = dplyr::coalesce(cell_id, NA_integer_),
            centroid_x = dplyr::coalesce(centroid_x, as.numeric(col_idx)),
            centroid_y = dplyr::coalesce(centroid_y, as.numeric(row_idx))
          )
        mask <- make_mask(lookup)
        adjacency <- exdyn_component_adjacency(pilot_riparian_components$matrix) %>%
          dplyr::mutate(
            unit_i = paste0("seg_", .data$unit_i),
            unit_j = paste0("seg_", .data$unit_j)
          )
        region_by_comp <- lookup %>%
          dplyr::distinct(unit_id, region) %>%
          dplyr::mutate(comp_id = as.integer(sub("^seg_", "", unit_id)))
        tx_tbl <- pilot_segment_tx %>%
          dplyr::left_join(region_by_comp, by = "comp_id") %>%
          dplyr::mutate(
            unit_id = paste0("seg_", .data$comp_id),
            region = dplyr::coalesce(.data$region, "UNKNOWN")
          )
        list(
          type = "segment",
          lookup = lookup,
          mask = mask,
          adjacency = adjacency,
          tx_table = tx_tbl,
          unit_ids = sort(unique(lookup$unit_id)),
          n_units = length(unique(lookup$unit_id)),
          n_tx_obs = sum(is.finite(tx_tbl$tx_obs)),
          region_lookup = lookup %>%
            dplyr::distinct(unit_id, region, .keep_all = FALSE) %>%
            dplyr::select(unit_id, region)
        )
      }
      unit_info <- switch(
        preferred,
        segment = build_segment_units(),
        grid_all = build_grid_units("grid_all"),
        grid_riparian = build_grid_units("grid_riparian"),
        build_segment_units()
      )
      if (is.null(unit_info)) {
        stop("Failed to build analysis units for configuration: ", preferred)
      }
      unit_info$coverage_breaks <- coverage_breaks
      unit_info$preferred <- preferred
      unit_info$unit_threshold <- unit_min
      unit_info$unit_threshold_met <- unit_info$n_tx_obs >= unit_min
      unit_info$unit_timing_stat <- pilot_unit_timing_stat
      dir.create("logs", showWarnings = FALSE)
      log_line <- sprintf(
        "[%s] Analysis units=%s preferred=%s n_units=%d n_tx_obs=%d threshold=%d met=%s timing=%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        unit_info$type,
        preferred,
        unit_info$n_units,
        unit_info$n_tx_obs,
        unit_min,
        unit_info$unit_threshold_met,
        pilot_unit_timing_stat
      )
      cat(log_line, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
      unit_info
    }),
    tar_target(pilot_information_audit, {
      unit_info <- pilot_unit_structure
      unit_mask <- unit_info$mask %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      T_P <- pilot_mink_field_default$T_P
      TX_obs <- pilot_vole_tx$matrix
      arrival_stats <- exdyn_arrival_coverage_stats(T_P, mask = unit_mask)
      counts <- exdyn_summary_counts(TX_obs, T_P, mask = unit_mask)
      effort_tbl <- pilot_mammal_cells %||% tibble::tibble()
      unit_cells <- unit_info$lookup %>%
        dplyr::distinct(.data$cell_id) %>%
        dplyr::filter(!is.na(.data$cell_id))
      effort_subset <- if (nrow(effort_tbl) && nrow(unit_cells)) {
        effort_tbl %>% dplyr::semi_join(unit_cells, by = "cell_id")
      } else {
        tibble::tibble()
      }
      tx_vals <- TX_obs[is.finite(TX_obs) & unit_mask]
      tx_span <- if (length(tx_vals) >= 2) diff(range(tx_vals)) else NA_real_
      audit <- tibble::tibble(
        analysis_unit = unit_info$type %||% pilot_analysis_unit_pref,
        preferred_unit = pilot_analysis_unit_pref,
        unit_timing_stat = unit_info$unit_timing_stat %||% pilot_unit_timing_stat,
        n_units = unit_info$n_units %||% NA_integer_,
        n_TX_obs = counts[["n_TX_finite"]] %||% 0,
        coverage_obs = if ((counts[["n_mask"]] %||% 0) > 0) (counts[["n_TX_finite"]] %||% 0) / (counts[["n_mask"]] %||% 1) else NA_real_,
        frac_finite_TP_in_mask = arrival_stats$frac_finite_mask %||% NA_real_,
        n_pairs = counts[["n_pairs"]] %||% 0,
        n_TP_finite = counts[["n_TP_finite"]] %||% 0,
        years_span_TX_obs = tx_span,
        effort_records = nrow(effort_subset),
        effort_cells = dplyr::n_distinct(effort_subset$cell_id),
        effort_years = dplyr::n_distinct(effort_subset$year),
        unit_min_threshold = unit_info$unit_threshold %||% (pilot_unit_min_tx_obs %||% 50L),
        meets_unit_gate = (unit_info$n_tx_obs %||% 0) >= (unit_info$unit_threshold %||% (pilot_unit_min_tx_obs %||% 50L))
      )
      readr::write_csv(audit, file.path("outputs", "realdata", "information_audit.csv"))
      audit
    }),
    tar_target(pilot_representation_audit, {
      arrival_tbl <- pilot_grid_info$lookup %>%
        dplyr::mutate(T_P = pilot_mink_field_default$T_P[cbind(.data$row_idx, .data$col_idx)])
      metric_from_tbl <- function(tbl, unit_col = "cell_id", tx_col = "tx_obs", tp_col = "T_P",
                                  label, class = "grid") {
        if (!nrow(tbl)) {
          return(tibble::tibble(
            representation = label,
            class = class,
            n_units = 0L,
            n_TX_obs = 0L,
            coverage_obs = NA_real_,
            n_pairs = 0L,
            frac_finite_TP = NA_real_,
            years_span_TX_obs = NA_real_,
            r2_arrival = NA_real_,
            lag_mean = NA_real_
          ))
        }
        cols_needed <- c(unit_col, tx_col, tp_col)
        if (!all(cols_needed %in% names(tbl))) {
          missing <- paste(setdiff(cols_needed, names(tbl)), collapse = ", ")
          stop("metric_from_tbl missing required columns: ", missing)
        }
        tbl_u <- tibble::as_tibble(tbl[, cols_needed, drop = FALSE])
        names(tbl_u) <- c("unit_id", "tx_obs_raw", "tp_raw")
        tbl_u <- tbl_u %>%
          dplyr::group_by(.data$unit_id) %>%
          dplyr::summarise(
            tx_obs = {
              vals <- .data$tx_obs_raw
              vals <- vals[is.finite(vals)]
              if (length(vals)) suppressWarnings(stats::median(vals, na.rm = TRUE)) else NA_real_
            },
            T_P = {
              vals <- .data$tp_raw
              vals <- vals[is.finite(vals)]
              if (length(vals)) suppressWarnings(stats::median(vals, na.rm = TRUE)) else NA_real_
            },
            .groups = "drop"
          )
        unit_vec <- tbl_u$unit_id
        tx_vec <- tbl_u$tx_obs
        tp_vec <- tbl_u$T_P
        n_units <- dplyr::n_distinct(unit_vec)
        n_tx <- sum(is.finite(tx_vec))
        n_tp <- sum(is.finite(tp_vec))
        n_pairs <- sum(is.finite(tx_vec) & is.finite(tp_vec))
        valid <- is.finite(tx_vec) & is.finite(tp_vec)
        r2 <- NA_real_
        lag <- NA_real_
        if (sum(valid) >= 3) {
          tx_ok <- tx_vec[valid]
          tp_ok <- tp_vec[valid]
          r <- suppressWarnings(stats::cor(tx_ok, tp_ok, use = "complete.obs"))
          r2 <- if (is.finite(r)) max(0, min(1, r^2)) else NA_real_
          lag <- mean(tx_ok - tp_ok, na.rm = TRUE)
        }
        tx_ok <- tx_vec[is.finite(tx_vec)]
        tx_span <- if (length(tx_ok) >= 2) diff(range(tx_ok)) else NA_real_
        tibble::tibble(
          representation = label,
          class = class,
          n_units = n_units,
          n_TX_obs = n_tx,
          coverage_obs = if (n_units > 0) n_tx / n_units else NA_real_,
          n_pairs = n_pairs,
          frac_finite_TP = if (n_units > 0) n_tp / n_units else NA_real_,
          years_span_TX_obs = tx_span,
          r2_arrival = r2,
          lag_mean = lag
        )
      }

      grid_all_tbl <- arrival_tbl %>%
        dplyr::select(cell_id, T_P) %>%
        dplyr::left_join(
          pilot_vole_tx_all$table %>% dplyr::select(cell_id, tx_obs),
          by = "cell_id"
        )
      riparian_ids <- pilot_riparian_table %>%
        dplyr::filter(.data$riparian) %>%
        dplyr::distinct(cell_id)
      grid_rip_tbl <- arrival_tbl %>%
        dplyr::semi_join(riparian_ids, by = "cell_id") %>%
        dplyr::select(cell_id, T_P) %>%
        dplyr::left_join(
          pilot_vole_tx_riparian$table %>% dplyr::select(cell_id, tx_obs),
          by = "cell_id"
        )

      comp_lookup <- pilot_riparian_components$table %>%
        dplyr::filter(!is.na(.data$cell_id)) %>%
        dplyr::select(cell_id, comp_id)
      segment_arrivals <- comp_lookup %>%
        dplyr::left_join(arrival_tbl %>% dplyr::select(cell_id, T_P), by = "cell_id") %>%
        dplyr::group_by(comp_id) %>%
        dplyr::summarise(T_P = suppressWarnings(stats::median(.data$T_P, na.rm = TRUE)), .groups = "drop")
      segment_tbl <- comp_lookup %>%
        dplyr::distinct(comp_id) %>%
        dplyr::left_join(segment_arrivals, by = "comp_id") %>%
        dplyr::left_join(
          pilot_segment_tx %>% dplyr::select(comp_id, tx_obs),
          by = "comp_id"
        ) %>%
        dplyr::mutate(unit_id = paste0("seg_", .data$comp_id))

      audit <- dplyr::bind_rows(
        metric_from_tbl(grid_all_tbl, unit_col = "cell_id", label = "grid_all", class = "grid"),
        metric_from_tbl(grid_rip_tbl, unit_col = "cell_id", label = "grid_riparian", class = "grid"),
        metric_from_tbl(segment_tbl, unit_col = "unit_id", label = "segment", class = "segment")
      ) %>%
        dplyr::mutate(
          unit_timing_stat = pilot_unit_timing_stat,
          unit_min_threshold = pilot_unit_min_tx_obs %||% 50L,
          meets_unit_gate = .data$n_TX_obs >= .data$unit_min_threshold,
          preferred = .data$representation == pilot_analysis_unit_pref
        ) %>%
        dplyr::arrange(dplyr::desc(.data$meets_unit_gate), dplyr::desc(.data$n_TX_obs))
      readr::write_csv(audit, file.path("outputs", "realdata", "representation_audit.csv"))
      audit
    }),
    tar_target(pilot_representation_choice, {
      audit <- pilot_representation_audit
      if (!nrow(audit)) {
        return(tibble::tibble(
          selected_representation = pilot_analysis_unit_pref,
          selected_reason = "no_audit_rows",
          meets_unit_gate = FALSE
        ))
      }
      preferred_row <- audit %>%
        dplyr::filter(.data$representation == pilot_analysis_unit_pref) %>%
        dplyr::slice_head(n = 1)
      if (nrow(preferred_row) && isTRUE(preferred_row$meets_unit_gate[[1]])) {
        return(preferred_row %>%
          dplyr::transmute(
            selected_representation = .data$representation,
            selected_reason = "preferred_meets_gate",
            meets_unit_gate = .data$meets_unit_gate
          ))
      }
      fallback <- audit %>%
        dplyr::filter(.data$meets_unit_gate) %>%
        dplyr::arrange(dplyr::desc(.data$n_TX_obs), dplyr::desc(.data$coverage_obs)) %>%
        dplyr::slice_head(n = 1)
      if (!nrow(fallback)) {
        fallback <- audit %>% dplyr::slice_head(n = 1)
        reason <- "no_representation_meets_gate"
      } else {
        reason <- "fallback_to_gate_passing_representation"
      }
      fallback %>%
        dplyr::transmute(
          selected_representation = .data$representation,
          selected_reason = reason,
          meets_unit_gate = .data$meets_unit_gate
        )
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
      unit_mask <- pilot_unit_structure$mask %||% matrix(TRUE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
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
          T_P_adj_guard[!unit_mask] <- NA_real_
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
            mask = unit_mask
          )
          TX_guard[!unit_mask] <- NA_real_
          coverage[i] <- if (any(unit_mask, na.rm = TRUE)) mean(is.finite(TX_guard[unit_mask]), na.rm = TRUE) else NA_real_
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
      cat(
        sprintf(
          "[%s] Guard attempt 1 coverage=%.4f",
          format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          guard1$mean_cov
        ),
        "\n",
        file = file.path("logs", "wo9d.log"),
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
        cat(
          sprintf(
            "[%s] Guard attempt 2 coverage=%.4f (pred_scale_max=%.3f pred_c_max=%.3f)",
            format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            guard2$mean_cov,
            widened$pred_scale[2],
            widened$pred_c[2]
          ),
          "\n",
          file = file.path("logs", "wo9d.log"),
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
          cat(
            sprintf(
              "[%s] Guard accepted widened bounds (coverage %.4f → %.4f)",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
              guard1$mean_cov,
              guard2$mean_cov
            ),
            "\n",
            file = file.path("logs", "wo9d.log"),
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
          cat(
            sprintf(
              "[%s] Guard coverage did not improve; retaining original bounds",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S")
            ),
            "\n",
            file = file.path("logs", "wo9d.log"),
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
    tar_target(pilot_shortlist, {
      top_n <- pilot_cfg$pilot$abc$shortlist %||% 200
      pilot_screen %>% dplyr::arrange(loss) %>% dplyr::slice_head(n = min(top_n, nrow(pilot_screen)))
    }),
    tar_target(pilot_abc_obs_summary, {
      coverage_breaks <- pilot_unit_structure$coverage_breaks
      exdyn_summary_tx_response(
        pilot_vole_tx$matrix,
        pilot_mink_field_default$T_P,
        years = pilot_years,
        coverage_breaks = coverage_breaks
      )
    }),
    tar_target(pilot_theta_bounds, exdyn_param_bounds(pilot_screen_cfg, cell_km = pilot_cfg$pilot$grid_cell_km)),
    tar_target(pilot_prior_sampler, {
      bounds <- pilot_theta_bounds
      shortlist <- pilot_shortlist
      jitter_sd <- pilot_cfg$pilot$abc$jitter_sd %||% 0.05
      seed_prob <- pilot_cfg$pilot$abc$seed_prob %||% 0.5
      base_sampler <- function() {
        theta <- list(
          alpha = runif(1, bounds$alpha[1], bounds$alpha[2]),
          disp_mean_km = runif(1, bounds$disp_mean_km[1], bounds$disp_mean_km[2]),
          A_over_K = runif(1, bounds$A_over_K[1], bounds$A_over_K[2]),
          pred_c = runif(1, bounds$pred_c[1], bounds$pred_c[2]),
          pred_h = runif(1, bounds$pred_h[1], bounds$pred_h[2]),
          ramp_years = runif(1, bounds$ramp_years[1], bounds$ramp_years[2]),
          pred_scale = runif(1, bounds$pred_scale[1], bounds$pred_scale[2]),
          gamma = runif(1, bounds$gamma[1], bounds$gamma[2]),
          rmax = runif(1, bounds$rmax[1], bounds$rmax[2]),
          K0 = pilot_screen_cfg$K0
        )
        if (!is.null(bounds$pred_scale_re_sigma)) {
          theta$pred_scale_re_sigma <- runif(1, bounds$pred_scale_re_sigma[1], bounds$pred_scale_re_sigma[2])
        }
        delta_cols <- grep("^delta_", names(bounds), value = TRUE)
        if (length(delta_cols)) {
          deltas <- purrr::map_dbl(delta_cols, ~ runif(1, bounds[[.x]][1], bounds[[.x]][2]))
          names(deltas) <- sub("^delta_", "", delta_cols)
          theta$delta_region <- deltas
        }
        theta$disp_mean_cells <- theta$disp_mean_km / (bounds$cell_km %||% 10)
        theta
      }
      jitterer <- function(row) {
        theta <- as.list(row[1, ])
        theta <- exdyn_theta_jitter(theta, bounds, jitter_sd)
        theta
      }
      function() {
        use_seed <- nrow(shortlist) > 0 && runif(1) < seed_prob
        if (use_seed) {
          row <- shortlist[sample.int(nrow(shortlist), 1), , drop = FALSE]
          return(jitterer(row))
        }
        base_sampler()
      }
    }),
    tar_target(pilot_abc_stage1, {
      cfg <- pilot_cfg$pilot$abc
      S_obs <- pilot_abc_obs_summary
      coverage_breaks <- pilot_unit_structure$coverage_breaks
      unit_lookup <- pilot_unit_structure$lookup
      unit_mask <- pilot_unit_structure$mask
      adjacency <- pilot_unit_structure$adjacency
      region_lookup <- pilot_unit_structure$region_lookup
      scale_vec <- cfg$scale %||% pmax(abs(S_obs), 1e-6)
      eps1 <- cfg$eps1 %||% 1
      n1 <- cfg$n_stage1 %||% 2000
      sampler <- pilot_prior_sampler
      simulate_once <- function(theta) {
        delta_lookup <- theta$delta_region %||% list()
        T_P_adj <- exdyn_adjust_arrival_matrix(pilot_mink_field_default$T_P, pilot_grid_info, delta_lookup, pilot_years)
        if (any(!unit_mask)) T_P_adj[!unit_mask] <- NA_real_
        pars <- list(
          rmax = theta$rmax,
          A_frac = theta$A_over_K * theta$K0,
          beta_H = 0,
          d = 0.03
        )
        sigma_val <- theta$pred_scale_re_sigma %||% 0
        unit_ids <- unit_lookup$unit_id
        unit_effects <- exdyn_sample_pred_scale_re(unit_ids, sigma = sigma_val)
        scale_matrix <- exdyn_scale_matrix_from_units(pilot_grid_info, unit_lookup, unit_effects)
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = pilot_years,
          T_P = T_P_adj,
          ramp_years = round(theta$ramp_years),
          pars = pars,
          K0 = theta$K0,
          alpha = theta$alpha,
          disp_mean_cells = theta$disp_mean_cells,
          pred = list(
            type = "II",
            c = theta$pred_c,
            h = theta$pred_h,
            scale = theta$pred_scale,
            gamma = theta$gamma,
            scale_matrix = scale_matrix
          ),
          pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
          mask = unit_mask
        )
        TX_mat <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) TX_mat[idx] <- pilot_years[TX_idx[idx]]
        TX_mat[!unit_mask] <- NA_real_
        list(TX = TX_mat, T_P = T_P_adj)
      }
      summary_fn <- function(sim) {
        exdyn_summary_tx_response(
          sim$TX,
          sim$T_P,
          years = pilot_years,
          coverage_breaks = coverage_breaks
        )
      }
      res <- exdyn_abc_rejection(
        S_obs = S_obs,
        prior_sampler = sampler,
        simulator = simulate_once,
        summary_fn = summary_fn,
        n_sims = n1,
        eps = eps1,
        scale = scale_vec,
        progress = TRUE
      )
      res$stage <- 1
      res
    }, deployment = "main"),
    tar_target(pilot_abc_stage2, {
      cfg <- pilot_cfg$pilot$abc
      if (!length(pilot_abc_stage1$samples) || !nrow(pilot_abc_stage1$samples)) {
        return(pilot_abc_stage1)
      }
      eps2 <- cfg$eps2 %||% (cfg$eps1 %||% 1) * 0.5
      n2 <- cfg$n_stage2 %||% 2000
      bounds <- pilot_theta_bounds
      jitter_sd <- cfg$jitter_sd %||% 0.05
      mix_prob <- cfg$seed_prob_refine %||% 0.65
      particles <- pilot_abc_stage1$samples
      sampler <- pilot_prior_sampler
      sampler_refine <- function() {
        use_particle <- nrow(particles) > 0 && runif(1) < mix_prob
        if (use_particle) {
          theta <- as.list(particles[sample.int(nrow(particles), 1), , drop = FALSE])
          theta <- exdyn_theta_jitter(theta, bounds, jitter_sd)
          return(theta)
        }
        sampler()
      }
      S_obs <- pilot_abc_obs_summary
      coverage_breaks <- pilot_unit_structure$coverage_breaks
      unit_lookup <- pilot_unit_structure$lookup
      unit_mask <- pilot_unit_structure$mask
      scale_vec <- cfg$scale %||% pmax(abs(S_obs), 1e-6)
      simulate_once <- function(theta) {
        delta_lookup <- theta$delta_region %||% list()
        T_P_adj <- exdyn_adjust_arrival_matrix(pilot_mink_field_default$T_P, pilot_grid_info, delta_lookup, pilot_years)
        if (any(!unit_mask)) T_P_adj[!unit_mask] <- NA_real_
        pars <- list(
          rmax = theta$rmax,
          A_frac = theta$A_over_K * theta$K0,
          beta_H = 0,
          d = 0.03
        )
        sigma_val <- theta$pred_scale_re_sigma %||% 0
        unit_ids <- unit_lookup$unit_id
        unit_effects <- exdyn_sample_pred_scale_re(unit_ids, sigma = sigma_val)
        scale_matrix <- exdyn_scale_matrix_from_units(pilot_grid_info, unit_lookup, unit_effects)
        TX_idx <- exdyn_simulate_tx_only(
          grid_info = pilot_grid_info,
          years = pilot_years,
          T_P = T_P_adj,
          ramp_years = round(theta$ramp_years),
          pars = pars,
          K0 = theta$K0,
          alpha = theta$alpha,
          disp_mean_cells = theta$disp_mean_cells,
          pred = list(
            type = "II",
            c = theta$pred_c,
            h = theta$pred_h,
            scale = theta$pred_scale,
            gamma = theta$gamma,
            scale_matrix = scale_matrix
          ),
          pre_leak = pilot_cfg$pilot$mink_P$pre_arrival_leak,
          mask = unit_mask
        )
        TX_mat <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        idx <- is.finite(TX_idx)
        if (any(idx)) TX_mat[idx] <- pilot_years[TX_idx[idx]]
        TX_mat[!unit_mask] <- NA_real_
        list(TX = TX_mat, T_P = T_P_adj)
      }
      summary_fn <- function(sim) {
        exdyn_summary_tx_response(
          sim$TX,
          sim$T_P,
          years = pilot_years,
          coverage_breaks = coverage_breaks
        )
      }
      res <- exdyn_abc_rejection(
        S_obs = S_obs,
        prior_sampler = sampler_refine,
        simulator = simulate_once,
        summary_fn = summary_fn,
        n_sims = n2,
        eps = eps2,
        scale = scale_vec,
        progress = TRUE
      )
      res$stage <- 2
      res
    }, deployment = "main"),
    tar_target(pilot_abc_final, {
      if (is.null(pilot_abc_stage2$samples)) pilot_abc_stage1 else pilot_abc_stage2
    }),
    tar_target(pilot_ablation_cfg, {
      pilot_cfg$pilot$ablation %||% list(enabled = TRUE, n_draws = NULL, n_cores = 4, seed = 8201)
    }),
    tar_target(pilot_ablation_theta, {
      cfg <- pilot_ablation_cfg
      if (!isTRUE(cfg$enabled)) {
        return(tibble::tibble())
      }
      draws_env <- suppressWarnings(as.integer(Sys.getenv("EXDYN_ABLATION_DRAWS", NA_character_)))
      n_draws_cfg <- cfg$n_draws %||% nrow(pilot_theta)
      n_draws <- if (is.finite(draws_env) && draws_env > 0) draws_env else n_draws_cfg
      n_draws <- min(nrow(pilot_theta), max(1L, as.integer(n_draws)))
      pilot_theta %>% dplyr::arrange(.data$draw) %>% dplyr::slice_head(n = n_draws)
    }),
    tar_target(pilot_ablation_results, {
      cfg <- pilot_ablation_cfg
      if (!isTRUE(cfg$enabled) || !nrow(pilot_ablation_theta)) {
        return(tibble::tibble())
      }
      cores_env <- suppressWarnings(as.integer(Sys.getenv("EXDYN_ABLATION_CORES", NA_character_)))
      n_cores_cfg <- cfg$n_cores %||% 4L
      n_cores <- if (is.finite(cores_env) && cores_env > 0) cores_env else n_cores_cfg
      seed_base <- cfg$seed %||% 8201L
      delta_penalty_cfg <- pilot_cfg$pilot$delta_penalty %||% list(lambda_mag = 0, lambda_tv = 0)
      base_args <- list(
        theta_tbl = pilot_ablation_theta,
        grid_info = pilot_grid_info,
        years_vec = pilot_years,
        T_P_base = pilot_mink_field_default$T_P,
        TX_obs = pilot_vole_tx$matrix,
        unit_info = pilot_unit_structure,
        mink_cfg = pilot_cfg$pilot$mink_P,
        compat_cfg = pilot_cfg$pilot$compat,
        delta_penalty_cfg = delta_penalty_cfg,
        unit_timing_stat = pilot_unit_timing_stat,
        n_cores = n_cores,
        log_mem = FALSE
      )
      delta_only <- do.call(
        exdyn_real_ablation_screen,
        c(base_args, list(use_re = FALSE, seed_base = seed_base))
      )
      delta_plus_re <- do.call(
        exdyn_real_ablation_screen,
        c(base_args, list(use_re = TRUE, seed_base = seed_base + 100000L))
      )
      dplyr::bind_rows(delta_only, delta_plus_re)
    }, deployment = "main"),
    tar_target(pilot_ablation_summary, {
      exdyn_real_ablation_summary(pilot_ablation_results)
    }),
    tar_target(pilot_ablation_written, {
      if (!nrow(pilot_ablation_results)) {
        return(character())
      }
      out_dir <- pilot_output_dir
      detail_path <- file.path(out_dir, "ablation_delta_re.csv")
      summary_path <- file.path(out_dir, "ablation_delta_re_summary.csv")
      plot_path <- file.path(out_dir, "ablation_delta_re.png")
      readr::write_csv(pilot_ablation_results, detail_path)
      readr::write_csv(pilot_ablation_summary, summary_path)
      p <- pilot_ablation_results %>%
        dplyr::mutate(model = factor(.data$model, levels = c("delta_only", "delta_plus_re"))) %>%
        ggplot2::ggplot(ggplot2::aes(x = .data$model, y = .data$loss, fill = .data$model)) +
        ggplot2::geom_boxplot(outlier.alpha = 0.2) +
        ggplot2::theme_minimal() +
        ggplot2::scale_fill_manual(values = c("#4c78a8", "#f58518")) +
        ggplot2::labs(
          title = "Ablation: delta regularisation only vs + pred_scale RE",
          x = "Condition",
          y = "Screen loss"
        )
      ggplot2::ggsave(plot_path, p, width = 6.5, height = 4.5, dpi = 150)
      c(detail_path, summary_path, plot_path)
    }, format = "file"),
    tar_target(pilot_ppc_cfg, {
      pilot_cfg$pilot$ppc %||% list(n_draws = 20, seed = 9103)
    }),
    tar_target(pilot_posterior_predictive, {
      abc_samples <- pilot_abc_final$samples %||% tibble::tibble()
      if (!nrow(abc_samples)) {
        return(list(curves = tibble::tibble(), summaries = tibble::tibble(), q50 = NULL))
      }
      cfg <- pilot_ppc_cfg
      n_draws <- min(nrow(abc_samples), max(1L, as.integer(cfg$n_draws %||% 20L)))
      set.seed(cfg$seed %||% 9103L)
      pick <- sample.int(nrow(abc_samples), n_draws)
      draws <- abc_samples[pick, , drop = FALSE]
      curves <- vector("list", n_draws)
      summaries <- vector("list", n_draws)
      tx_stack <- array(NA_real_, dim = c(pilot_grid_info$nx, pilot_grid_info$ny, n_draws))
      for (i in seq_len(n_draws)) {
        theta <- draws[i, , drop = FALSE]
        sim <- exdyn_real_simulate_tx(
          theta = theta,
          grid_info = pilot_grid_info,
          years_vec = pilot_years,
          T_P_base = pilot_mink_field_default$T_P,
          unit_lookup = pilot_unit_structure$lookup,
          unit_mask = pilot_unit_structure$mask,
          mink_cfg = pilot_cfg$pilot$mink_P,
          sigma_override = NULL,
          seed = (cfg$seed %||% 9103L) + i,
          log_mem = FALSE,
          log_tag = sprintf("ppc draw %02d", i)
        )
        tx_stack[, , i] <- sim$TX_sim
        sum_i <- exdyn_summary_tx_response(
          sim$TX_sim,
          sim$T_P_adj,
          years = pilot_years,
          coverage_breaks = pilot_unit_structure$coverage_breaks,
          mask = pilot_unit_structure$mask
        )
        summaries[[i]] <- tibble::enframe(sum_i, name = "stat", value = "value") %>%
          dplyr::mutate(draw = i)
        curve_vals <- sum_i[grepl("^cov_curve_", names(sum_i))]
        curves[[i]] <- tibble::tibble(
          draw = i,
          break_id = seq_along(curve_vals),
          value = as.numeric(curve_vals)
        )
      }
      q50 <- apply(tx_stack, c(1, 2), function(x) stats::quantile(x, probs = 0.5, na.rm = TRUE))
      list(
        curves = dplyr::bind_rows(curves),
        summaries = dplyr::bind_rows(summaries),
        q50 = q50
      )
    }, deployment = "main"),
    tar_target(pilot_posterior_predictive_written, {
      out_dir <- pilot_output_dir
      curves <- pilot_posterior_predictive$curves %||% tibble::tibble()
      summaries <- pilot_posterior_predictive$summaries %||% tibble::tibble()
      q50 <- pilot_posterior_predictive$q50
      curve_obs <- exdyn_summary_tx_response(
        pilot_vole_tx$matrix,
        pilot_mink_field_default$T_P,
        years = pilot_years,
        coverage_breaks = pilot_unit_structure$coverage_breaks,
        mask = pilot_unit_structure$mask
      )
      obs_vals <- curve_obs[grepl("^cov_curve_", names(curve_obs))]
      n_breaks <- length(obs_vals)
      if (n_breaks == 0L) {
        n_breaks <- length(pilot_unit_structure$coverage_breaks) + 2L
      }
      curve_env <- if (nrow(curves)) {
        curves %>%
          dplyr::group_by(.data$break_id) %>%
          dplyr::summarise(
            q05 = stats::quantile(.data$value, 0.05, na.rm = TRUE),
            q50 = stats::quantile(.data$value, 0.50, na.rm = TRUE),
            q95 = stats::quantile(.data$value, 0.95, na.rm = TRUE),
            .groups = "drop"
          ) %>%
          dplyr::mutate(obs = obs_vals[.data$break_id])
      } else {
        tibble::tibble(
          break_id = seq_len(n_breaks),
          q05 = NA_real_,
          q50 = NA_real_,
          q95 = NA_real_,
          obs = obs_vals[seq_len(n_breaks)]
        )
      }
      curve_path <- file.path(out_dir, "posterior_predictive_coverage.csv")
      summary_path <- file.path(out_dir, "posterior_predictive_summaries.csv")
      curve_plot_path <- file.path(out_dir, "posterior_predictive_coverage.png")
      map_path <- file.path(out_dir, "posterior_predictive_tx_q50.png")
      readr::write_csv(curve_env, curve_path)
      readr::write_csv(summaries, summary_path)
      if (nrow(curves)) {
        p_curve <- ggplot2::ggplot(curve_env, ggplot2::aes(x = .data$break_id)) +
          ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$q05, ymax = .data$q95), fill = "#a6cee3", alpha = 0.35) +
          ggplot2::geom_line(ggplot2::aes(y = .data$q50), color = "#1f78b4", linewidth = 1) +
          ggplot2::geom_point(ggplot2::aes(y = .data$obs), color = "#e31a1c", size = 2) +
          ggplot2::theme_minimal() +
          ggplot2::labs(
            title = "Posterior predictive coverage curve",
            x = "Coverage breakpoint index",
            y = "Cumulative coverage"
          )
      } else {
        p_curve <- ggplot2::ggplot(curve_env, ggplot2::aes(x = .data$break_id, y = .data$obs)) +
          ggplot2::geom_point(color = "#e31a1c", size = 2) +
          ggplot2::geom_line(color = "#e31a1c", linewidth = 0.8) +
          ggplot2::theme_minimal() +
          ggplot2::labs(
            title = "Posterior predictive coverage curve (no accepted ABC draws)",
            subtitle = "Observed curve shown; envelope unavailable",
            x = "Coverage breakpoint index",
            y = "Cumulative coverage"
          )
      }
      ggplot2::ggsave(curve_plot_path, p_curve, width = 6.5, height = 4.5, dpi = 150)
      out_paths <- c(curve_path, summary_path, curve_plot_path)
      if (!is.null(q50)) {
        p_map <- exdyn_plot_surface(
          q50,
          pilot_grid_info,
          "Posterior predictive TX (median)",
          "Year"
        )
        ggplot2::ggsave(map_path, p_map, width = 6.5, height = 6.0, dpi = 150)
        out_paths <- c(out_paths, map_path)
      }
      out_paths
    }, format = "file"),
    tar_target(pilot_gate_evaluation, {
      best <- pilot_screen %>% dplyr::arrange(.data$rank) %>% dplyr::slice_head(n = 1)
      best_val <- function(col) {
        if (!nrow(best) || !(col %in% names(best))) return(NA_real_)
        val <- best[[col]][[1]]
        if (is.null(val)) NA_real_ else as.numeric(val)
      }
      abc_samples <- pilot_abc_final$samples %||% tibble::tibble()
      abc_summ <- pilot_abc_final$summaries %||% tibble::tibble()
      n_sims <- pilot_cfg$pilot$abc$n_stage2 %||% pilot_cfg$pilot$abc$n_stage1 %||% NA_real_
      accept_rate <- if (is.finite(n_sims) && n_sims > 0) nrow(abc_samples) / n_sims else NA_real_
      best_r2 <- best_val("r2_arrival")
      best_lag <- best_val("lag_mean")
      best_cov <- best_val("coverage")
      gate_tbl <- tibble::tibble(
        gate = c("best_r2", "best_lag", "best_coverage", "abc_accept_rate"),
        value = c(best_r2, best_lag, best_cov, accept_rate),
        threshold = c(">=0.20", "[2,25]", ">=0.15", "0<rate<0.20"),
        pass = c(
          is.finite(best_r2) && best_r2 >= 0.20,
          is.finite(best_lag) && best_lag >= 2 && best_lag <= 25,
          is.finite(best_cov) && best_cov >= 0.15,
          is.finite(accept_rate) && accept_rate > 0 && accept_rate < 0.20
        )
      )
      posterior_tbl <- if (!nrow(abc_summ)) {
        tibble::tibble(
          metric = c("abc_r2_median", "abc_lag_median", "abc_coverage_median"),
          value = NA_real_
        )
      } else {
        tibble::tibble(
          metric = c("abc_r2_median", "abc_lag_median", "abc_coverage_median"),
          value = c(
            stats::median(abc_summ$r2_arrival, na.rm = TRUE),
            stats::median(abc_summ$lag_mean, na.rm = TRUE),
            stats::median(abc_summ$coverage, na.rm = TRUE)
          )
        )
      }
      list(gates = gate_tbl, posterior = posterior_tbl)
    }),
    tar_target(pilot_gate_evaluation_csv, {
      gate_path <- file.path(pilot_output_dir, "gate_evaluation.csv")
      post_path <- file.path(pilot_output_dir, "posterior_metrics.csv")
      readr::write_csv(pilot_gate_evaluation$gates %||% tibble::tibble(), gate_path)
      readr::write_csv(pilot_gate_evaluation$posterior %||% tibble::tibble(), post_path)
      c(gate_path, post_path)
    }, format = "file"),
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
      pilot_shortlist
      pilot_abc_final
      pilot_information_audit
      pilot_representation_audit
      pilot_representation_choice
      pilot_ablation_written
      pilot_gate_evaluation_csv
      pilot_posterior_predictive_written
      pilot_output_dir
      pilot_tables_written
      pilot_maps_written
      pilot_scatter_path
      quarto::quarto_render("reports/pilot_mink_vole.qmd", output_format = "html")
      file.path("reports", "pilot_mink_vole.html")
    }, format = "file"),
    tar_target(pilot_report_pdf, {
      pilot_scores
      pilot_theta
      pilot_grid
      pilot_grid_info
      pilot_vole_tx
      pilot_mink_field_default
      pilot_shortlist
      pilot_abc_final
      pilot_information_audit
      pilot_representation_audit
      pilot_representation_choice
      pilot_ablation_written
      pilot_gate_evaluation_csv
      pilot_posterior_predictive_written
      pilot_output_dir
      pilot_tables_written
      pilot_maps_written
      pilot_scatter_path
      quarto::quarto_render("reports/pilot_mink_vole.qmd", output_format = "pdf")
      file.path("reports", "pilot_mink_vole.pdf")
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
      cat(log_line, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
      summary
    }, deployment = "main"),
    tar_target(pilot_canonical_cfg, {
      pilot_cfg$pilot$canonical %||% list(enabled = FALSE)
    }),
    tar_target(pilot_canonical_dir, {
      cfg <- pilot_canonical_cfg
      if (!isTRUE(cfg$enabled)) {
        return(NULL)
      }
      root <- cfg$root %||% file.path("outputs", "canonical")
      milestone <- cfg$milestone %||% "0.4"
      wp_id <- cfg$wp_id %||% "WP-0.4.3"
      run_id <- cfg$run_id %||% exdyn_make_run_id("real")
      exdyn_canonical_run_dir(root, milestone, wp_id, run_id)
    }),
    tar_target(pilot_canonical_manifest, {
      cfg <- pilot_canonical_cfg
      canonical_dir <- pilot_canonical_dir
      if (is.null(canonical_dir)) {
        return(NULL)
      }
      snapshot_path <- file.path(canonical_dir, "config", "realdata.yaml")
      exdyn_write_config_snapshot(pilot_cfg, snapshot_path)
      session_path <- file.path(canonical_dir, "session_info.txt")
      exdyn_write_session_info(session_path)
      outputs <- c(
        pilot_report_html,
        pilot_report_pdf,
        pilot_tables_written,
        pilot_maps_written,
        pilot_scatter_path,
        pilot_ablation_written,
        pilot_gate_evaluation_csv,
        pilot_posterior_predictive_written,
        file.path("outputs", "realdata", "information_audit.csv"),
        file.path("outputs", "realdata", "representation_audit.csv")
      )
      copied <- exdyn_copy_to_canonical(outputs, canonical_dir)
      manifest <- list(
        schema_version = exdyn_schema_version(),
        commit_sha = exdyn_git_sha(),
        run_id = basename(canonical_dir),
        run_timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        milestone = cfg$milestone %||% "0.4",
        wp_id = cfg$wp_id %||% "WP-0.4.3",
        config_snapshots = list(realdata = exdyn_relative_path(snapshot_path, canonical_dir)),
        seeds = list(
          screen_seed = 42L,
          abc_seed = pilot_cfg$pilot$abc$seed %||% NA_integer_,
          ppc_seed = pilot_ppc_cfg$seed %||% NA_integer_,
          ablation_seed = pilot_ablation_cfg$seed %||% NA_integer_
        ),
        commands = cfg$commands %||% c("make pilot")
      )
      manifest$outputs <- sort(unique(exdyn_relative_path(copied, canonical_dir)))
      exdyn_write_manifest(manifest, file.path(canonical_dir, "manifest.yaml"))
    }, format = "file")
  )
}
