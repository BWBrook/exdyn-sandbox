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
        delta_penalty_cfg = delta_penalty_cfg
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
    tar_target(pilot_unit_structure, {
      preferred <- pilot_cfg$pilot$analysis_unit %||% "segment"
      years_vec <- pilot_years
      coverage_breaks <- exdyn_coverage_breaks(years_vec)
      make_mask <- function(lookup) {
        mask <- matrix(FALSE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
        if (nrow(lookup)) {
          idx <- cbind(lookup$row_idx, lookup$col_idx)
          mask[idx] <- TRUE
        }
        mask
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
        lookup <- lookup %>%
          dplyr::transmute(
            row_idx = row_idx,
            col_idx = col_idx,
            unit_id = paste0("seg_", comp_id),
            region = dplyr::coalesce(region, "UNKNOWN"),
            cell_id = dplyr::coalesce(cell_id, NA_integer_)
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
      unit_info <- build_segment_units()
      if (is.null(unit_info)) {
        stop("Failed to build analysis units for configuration: ", preferred)
      }
      unit_info$coverage_breaks <- coverage_breaks
      unit_info$preferred <- preferred
      unit_info$unit_threshold_met <- unit_info$n_tx_obs >= 50
      dir.create("logs", showWarnings = FALSE)
      log_line <- sprintf(
        "[%s] Analysis units=%s n_units=%d n_tx_obs=%d threshold_met=%s",
        format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
        unit_info$type,
        unit_info$n_units,
        unit_info$n_tx_obs,
        unit_info$unit_threshold_met
      )
      cat(log_line, "\n", file = file.path("logs", "wo9.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9b.log"), append = TRUE)
      cat(log_line, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
      unit_info
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
      pilot_shortlist
      pilot_abc_final
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
      cat(log_line, "\n", file = file.path("logs", "wo9d.log"), append = TRUE)
      summary
    }, deployment = "main")
  )
}
