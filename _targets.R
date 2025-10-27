library(targets)
library(tarchetypes)
tar_option_set(
  packages = c(
    "yaml","data.table","ggplot2","matrixStats","tibble",
    "dplyr","purrr","tidyr","stringr","ranger","yardstick","lhs",
    "viridisLite","rlang",
    "rsample","glmnet"
  ),
  error = "continue",
  envir = globalenv()
)

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(export_all = FALSE)
}

source("R/utils.R", local = TRUE)

list(
  # Baseline single run for quick inspection
  tar_target(cfg, exdyn_config("config/default.yaml"), cue = tar_cue("always")),
  tar_target(default_fields, exdyn_make_fields(
    nx = cfg$nx, ny = cfg$ny, years = cfg$years, scenario = cfg$scenario,
    habitat_beta = cfg$habitat_beta, ramp_start = cfg$ramp_start,
    ramp_end = cfg$ramp_end, predation_speed = cfg$pred$speed,
    predation_seeds = cfg$pred$seeds, climate_drift = cfg$climate$drift_per_century
  )),
  tar_target(default_N, exdyn_simulate(
    nx = cfg$nx, ny = cfg$ny, years = cfg$years, fields = default_fields,
    pars = cfg$pars, K0 = cfg$K0, alpha = cfg$alpha,
    disp_mean_cells = cfg$disp_mean_cells,
    pred = list(type = cfg$pred$type, c = cfg$pred$c, h = cfg$pred$h)
  )),
  tar_target(default_po, exdyn_presence_only(
    default_N, rate = cfg$obs$presence_only_rate, effort_strength = cfg$obs$effort_strength
  )),
  tar_target(default_foss, exdyn_fossils(
    default_N, n_sites = cfg$obs$fossil_sites, date_sd = cfg$obs$fossil_date_sd_y
  )),
  tar_target(default_summs, exdyn_summaries(default_N, default_fields, K0 = cfg$K0)),

  # Experiment grid branching
  tar_target(exp_grid, exdyn_experiment_grid("config/experiments.yaml")),
  tar_target(exp_summaries, exdyn_run_once(exp_grid), pattern = map(exp_grid), iteration = "list"),
  tar_target(results, dplyr::bind_rows(exp_summaries)),
  tar_target(results_response_only, {
    results %>%
      dplyr::select(exp_id, species, scenario, predation_type, replicate, dplyr::starts_with("resp_"))
  }),
  tar_target(qa_summary_table, {
    results %>%
      dplyr::transmute(
        exp_id,
        species,
        scenario,
        predation_type,
        replicate,
        po_n,
        foss_n,
        arrival_coverage,
        lag_arrival_mean,
        initial_below_tau_frac,
        non_first_passage_frac,
        monotone_P = qa_monotone_P,
        monotone_H = qa_monotone_H,
        po_abund_cor,
        resp_orient_R,
        resp_edge_dir_R,
        resp_speed_r2
      )
  }),
  tar_target(qa_outlier_table, {
    summary <- qa_summary_table
    if (!nrow(summary)) return(summary)
    processed <- summary %>%
      dplyr::rowwise() %>%
      dplyr::mutate(
        .reasons = list({
          reasons <- character()
          if (is.finite(arrival_coverage) && arrival_coverage < 0.1) reasons <- c(reasons, "low_coverage")
          if (is.finite(lag_arrival_mean) && lag_arrival_mean <= 0) reasons <- c(reasons, "non_positive_lag")
          if (is.finite(monotone_P) && monotone_P < 0.95) reasons <- c(reasons, "predation_non_monotone")
          if (is.finite(monotone_H) && monotone_H < 0.95) reasons <- c(reasons, "habitat_non_monotone")
          if (is.finite(initial_below_tau_frac) && initial_below_tau_frac > 0.05) reasons <- c(reasons, "initial_below_tau")
          if (is.finite(non_first_passage_frac) && non_first_passage_frac > 0.05) reasons <- c(reasons, "non_first_passage")
          if (is.finite(po_abund_cor) && po_abund_cor < 0.3) reasons <- c(reasons, "po_abundance_weak")
          reasons
        }),
        score = length(.reasons)
      ) %>%
      dplyr::ungroup() %>%
      dplyr::mutate(reason = vapply(.reasons, function(x) {
        if (!length(x)) "" else paste(x, collapse = ";")
      }, character(1))) %>%
      dplyr::select(-.reasons)
    n_all <- nrow(processed)
    keep_n <- max(1, ceiling(0.1 * n_all))
    processed %>%
      dplyr::filter(score > 0) %>%
      dplyr::arrange(dplyr::desc(score), arrival_coverage, lag_arrival_mean) %>%
      dplyr::slice_head(n = keep_n)
  }),
  tar_target(qa_metrics_overview, {
    if (!nrow(results)) return(results)
    results %>%
      dplyr::group_by(scenario) %>%
      dplyr::summarise(
        median_arrival_coverage = stats::median(arrival_coverage, na.rm = TRUE),
        iqr_arrival_coverage = stats::IQR(arrival_coverage, na.rm = TRUE),
        median_lag_arrival = stats::median(lag_arrival_mean, na.rm = TRUE),
        iqr_lag_arrival = stats::IQR(lag_arrival_mean, na.rm = TRUE),
        median_r2_arrival = stats::median(r2_arrival, na.rm = TRUE),
        iqr_r2_arrival = stats::IQR(r2_arrival, na.rm = TRUE),
        median_resp_orient_R = stats::median(resp_orient_R, na.rm = TRUE),
        iqr_resp_orient_R = stats::IQR(resp_orient_R, na.rm = TRUE),
        median_resp_edge_dir_R = stats::median(resp_edge_dir_R, na.rm = TRUE),
        iqr_resp_edge_dir_R = stats::IQR(resp_edge_dir_R, na.rm = TRUE),
        median_resp_speed_r2 = stats::median(resp_speed_r2, na.rm = TRUE),
        iqr_resp_speed_r2 = stats::IQR(resp_speed_r2, na.rm = TRUE),
        .groups = "drop"
      )
  }),
  tar_target(qa_raster_cases, {
    pred_runs <- qa_summary_table %>% dplyr::filter(scenario == "predation_front")
    if (!nrow(pred_runs)) return(tibble::tibble())
    worst_n <- min(3, nrow(pred_runs))
    worst_ids <- pred_runs %>%
      dplyr::arrange(arrival_coverage) %>%
      dplyr::slice_head(n = worst_n) %>%
      dplyr::pull(exp_id)
    best_id <- pred_runs %>%
      dplyr::arrange(dplyr::desc(arrival_coverage)) %>%
      dplyr::slice_head(n = 1) %>%
      dplyr::pull(exp_id)
    ids <- unique(c(worst_ids, best_id))
    exp_grid %>% dplyr::filter(exp_id %in% ids)
  }),
  tar_target(save_qa_diagnostics, {
    dir.create(file.path("outputs", "qa"), recursive = TRUE, showWarnings = FALSE)
    palette_fn <- grDevices::colorRampPalette(c("#f7fbff", "#c6dbef", "#6baed6", "#08306b"))
    files <- character()
    # Distribution plots
    lag_path <- file.path("outputs", "qa", "lag_hist_by_scenario.png")
    lag_data <- qa_summary_table %>% dplyr::filter(is.finite(lag_arrival_mean))
    lag_plot <- ggplot2::ggplot(lag_data, ggplot2::aes(x = lag_arrival_mean, fill = scenario)) +
      ggplot2::geom_histogram(position = "identity", alpha = 0.6, bins = 30, colour = NA) +
      ggplot2::geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
      ggplot2::scale_fill_brewer(palette = "Set1") +
      ggplot2::labs(title = "Lag distribution by scenario", x = "Mean lag (years)", y = "Count") +
      ggplot2::theme_minimal(base_size = 12)
    ggplot2::ggsave(lag_path, lag_plot, width = 6.5, height = 4.5, dpi = 130)
    files <- c(files, lag_path)

    coverage_path <- file.path("outputs", "qa", "coverage_hist_by_scenario.png")
    coverage_data <- qa_summary_table %>% dplyr::filter(is.finite(arrival_coverage))
    coverage_plot <- ggplot2::ggplot(coverage_data, ggplot2::aes(x = arrival_coverage, fill = scenario)) +
      ggplot2::geom_histogram(position = "identity", alpha = 0.6, bins = 30, colour = NA) +
      ggplot2::scale_fill_brewer(palette = "Dark2") +
      ggplot2::labs(title = "Arrival coverage distribution", x = "Coverage", y = "Count") +
      ggplot2::theme_minimal(base_size = 12)
    ggplot2::ggsave(coverage_path, coverage_plot, width = 6.5, height = 4.5, dpi = 130)
    files <- c(files, coverage_path)

    po_path <- file.path("outputs", "qa", "po_vs_total_scatter.png")
    po_plot <- ggplot2::ggplot(results, ggplot2::aes(x = resp_total_final, y = po_n, colour = scenario)) +
      ggplot2::geom_point(alpha = 0.7) +
      ggplot2::scale_colour_brewer(palette = "Set2") +
      ggplot2::labs(
        title = "Presence-only counts vs final total abundance",
        x = "Total abundance (final year)",
        y = "Presence-only count"
      ) +
      ggplot2::theme_minimal(base_size = 12)
    ggplot2::ggsave(po_path, po_plot, width = 6.5, height = 4.5, dpi = 130)
    files <- c(files, po_path)

    save_surface <- function(mat, file, main) {
      if (is.null(mat) || all(!is.finite(mat))) return(NULL)
      grDevices::png(file, width = 600, height = 600)
      on.exit(grDevices::dev.off(), add = TRUE)
      pal <- palette_fn(80)
      image(
        x = seq_len(nrow(mat)), y = seq_len(ncol(mat)),
        z = t(mat)[, nrow(mat):1],
        col = pal, axes = FALSE, xlab = "", ylab = ""
      )
      box()
      title(main)
      invisible(file)
    }
    save_abundance <- function(arr, t_index, file, main) {
      if (length(t_index) != 1 || t_index < 1 || t_index > dim(arr)[3]) return(NULL)
      mat <- arr[, , t_index]
      grDevices::png(file, width = 600, height = 600)
      on.exit(grDevices::dev.off(), add = TRUE)
      pal <- palette_fn(80)
      image(
        x = seq_len(nrow(mat)), y = seq_len(ncol(mat)),
        z = t(log1p(mat))[, nrow(mat):1],
        col = pal, axes = FALSE, xlab = "", ylab = ""
      )
      box()
      title(main)
      invisible(file)
    }
    if (nrow(qa_raster_cases)) {
      for (idx in seq_len(nrow(qa_raster_cases))) {
        row <- qa_raster_cases[idx, , drop = FALSE]
        core <- exdyn_run_core(row)
        exp_id <- row$exp_id[[1]]
        prefix <- file.path("outputs", "qa", paste0("rasters_", exp_id))
        tp_file <- paste0(prefix, "_TP.png")
        tx_file <- paste0(prefix, "_TX.png")
        created_tp <- save_surface(core$fields$T_P, tp_file, sprintf("Predator arrival (T_P) – %s", exp_id))
        created_tx <- save_surface(core$T_X, tx_file, sprintf("Extirpation time (T_X) – %s", exp_id))
        files <- c(files, created_tp, created_tx)
        yrs <- dim(core$N)[3]
        time_points <- unique(round(seq(1, yrs, length.out = 3)))
        for (tpt in time_points) {
          n_file <- paste0(prefix, "_N_t", sprintf("%03d", tpt), ".png")
          created_n <- save_abundance(core$N, tpt, n_file, sprintf("log(N+1) at t=%d – %s", tpt, exp_id))
          files <- c(files, created_n)
        }
      }
    }
    files[!is.na(files)]
  }),
  tar_target(feature_sets, exdyn_feature_sets(results)),
  tar_target(clf_driver_aware, exdyn_fit_and_eval(results, feature_sets$driver_aware)),
  tar_target(clf_response_only, exdyn_fit_and_eval(results, feature_sets$response_only)),
  tar_target(conf_driver_aware, clf_driver_aware$primary$confusion),
  tar_target(conf_response_only, clf_response_only$primary$confusion),
  tar_target(feature_importance_driver_aware, {
    clf_driver_aware$primary$importance %>%
      dplyr::mutate(importance = tidyr::replace_na(importance, -Inf)) %>%
      dplyr::arrange(dplyr::desc(importance)) %>%
      dplyr::mutate(importance = dplyr::if_else(importance == -Inf, NA_real_, importance))
  }),
  tar_target(feature_importance_response_only, {
    clf_response_only$primary$importance %>%
      dplyr::mutate(importance = tidyr::replace_na(importance, -Inf)) %>%
      dplyr::arrange(dplyr::desc(importance)) %>%
      dplyr::mutate(importance = dplyr::if_else(importance == -Inf, NA_real_, importance))
  }),
  tar_target(sweep_grid, exdyn_sweep_grid("config/experiments.yaml")),
  tar_target(sweep_summaries, exdyn_run_once(sweep_grid), pattern = map(sweep_grid), iteration = "list"),
  tar_target(sweep_results, dplyr::bind_rows(sweep_summaries)),
  tar_target(sweep_feature_sets, exdyn_feature_sets(sweep_results)),
  tar_target(sweep_oof, exdyn_oof_predictions(sweep_results, sweep_feature_sets$response_only, v = 5, seed = 987)),
  tar_target(sweep_clf_response_only, exdyn_fit_and_eval(sweep_results, sweep_feature_sets$response_only)),
  tar_target(sweep_cv, exdyn_cv_macro_f1(sweep_results, sweep_feature_sets$response_only, v = 5, seed = 987)),
  tar_target(sweep_predictions, sweep_cv$predictions),
  tar_target(sweep_macro_overall, sweep_clf_response_only$primary$macro_f1),
  tar_target(sweep_f1_by_scenario, {
    preds <- sweep_predictions
    levels <- levels(preds$truth)
    conf <- table(preds$truth, preds$estimate)
    diag_vals <- diag(conf)
    precision <- diag_vals / pmax(1, colSums(conf))
    recall <- diag_vals / pmax(1, rowSums(conf))
    f1 <- ifelse(precision + recall == 0, NA_real_, 2 * precision * recall / (precision + recall))
    tibble::tibble(
      scenario = levels,
      macro_f1 = f1
    )
  }),
  tar_target(sweep_f1_by_archetype, {
    helper <- function(df) {
      if (nrow(df) < 3) return(NA_real_)
      truth <- factor(df$truth, levels = levels(sweep_predictions$truth))
      est <- factor(df$estimate, levels = levels(truth))
      conf <- table(truth, est)
      diag_vals <- diag(conf)
      precision <- diag_vals / pmax(1, colSums(conf))
      recall <- diag_vals / pmax(1, rowSums(conf))
      f1 <- ifelse(precision + recall == 0, NA_real_, 2 * precision * recall / (precision + recall))
      mean(f1, na.rm = TRUE)
    }
    sweep_predictions %>%
      dplyr::group_by(species) %>%
      dplyr::summarise(macro_f1 = helper(dplyr::cur_data_all()), .groups = "drop")
  }),
  tar_target(save_sweep_tables, {
    dir.create("outputs", showWarnings = FALSE)
    data.table::fwrite(sweep_f1_by_scenario, "outputs/sweep_f1_by_scenario.csv")
    data.table::fwrite(sweep_f1_by_archetype, "outputs/sweep_f1_by_archetype.csv")
    c("outputs/sweep_f1_by_scenario.csv", "outputs/sweep_f1_by_archetype.csv")
  }),
  tar_target(save_partial_dependence, {
    dir.create(file.path("outputs", "partial_dependence"), recursive = TRUE, showWarnings = FALSE)
    joined <- sweep_predictions %>%
      dplyr::left_join(sweep_results %>% dplyr::select(exp_id, dispersal_mean_km, pred_speed, effort_strength,
        allee_A_over_K, habitat_beta, habitat_ramp_start, habitat_ramp_end, nx, ny, years), by = "exp_id") %>%
      dplyr::mutate(correct = as.numeric(truth == estimate))
    ctrl_vars <- c("alpha", "dispersal_mean_km", "pred_speed", "presence_rate", "effort_strength", "allee_A_over_K", "habitat_beta")
    pd_data <- joined %>% dplyr::select(any_of(ctrl_vars), correct)
    pd_data <- tidyr::drop_na(pd_data)
    ctrl_formula <- stats::as.formula(paste("factor(correct, levels = c(0,1)) ~", paste(ctrl_vars, collapse = " + ")))
    rf <- tryCatch(
      ranger::ranger(ctrl_formula, data = pd_data, probability = TRUE, importance = "impurity", num.trees = 600, seed = 2468),
      error = function(e) NULL
    )
    importance <- if (is.null(rf)) {
      tibble::tibble(feature = ctrl_vars, importance = NA_real_)
    } else {
      tibble::tibble(feature = names(rf$variable.importance), importance = as.numeric(rf$variable.importance)) %>%
        dplyr::arrange(dplyr::desc(importance))
    }
    top_features <- head(importance$feature[is.finite(importance$importance)], 4)
    if (!length(top_features)) top_features <- head(ctrl_vars, 4)
    out_files <- character(0)
    for (feat in top_features) {
      if (!feat %in% names(joined)) next
      data_feat <- joined[, c(feat, "correct"), drop = FALSE]
      names(data_feat)[1] <- "value"
      data_feat <- tidyr::drop_na(data_feat)
      if (!nrow(data_feat)) next
      breaks <- unique(stats::quantile(data_feat$value, probs = seq(0, 1, length.out = 20), na.rm = TRUE))
      if (length(breaks) < 2) {
        pd_tbl <- tibble::tibble(variable = feat, value = mean(data_feat$value), mean_correct = mean(data_feat$correct), n = nrow(data_feat))
      } else {
        bins <- cut(data_feat$value, breaks = breaks, include.lowest = TRUE, labels = FALSE)
        pd_tbl <- tibble::tibble(
          variable = feat,
          value = as.numeric(tapply(data_feat$value, bins, mean, na.rm = TRUE)),
          mean_correct = as.numeric(tapply(data_feat$correct, bins, mean, na.rm = TRUE)),
          n = as.numeric(tapply(data_feat$correct, bins, length))
        ) %>% tidyr::drop_na()
      }
      csv_path <- file.path("outputs", "partial_dependence", paste0(feat, ".csv"))
      data.table::fwrite(pd_tbl, csv_path)
      plt <- ggplot2::ggplot(pd_tbl, ggplot2::aes(x = value, y = mean_correct)) +
        ggplot2::geom_line(color = "#2b8cbe", linewidth = 1) +
        ggplot2::geom_point(color = "#045a8d") +
        ggplot2::labs(title = paste("Partial dependence:", feat), x = feat, y = "Pr(correct classification)") +
        ggplot2::theme_minimal(base_size = 12)
      png_path <- file.path("outputs", "partial_dependence", paste0(feat, ".png"))
      ggplot2::ggsave(png_path, plt, width = 6, height = 4, dpi = 130)
      out_files <- c(out_files, csv_path, png_path)
    }
    out_files
  }),
  tar_target(save_heatmaps, {
    dir.create(file.path("outputs", "heatmaps"), recursive = TRUE, showWarnings = FALSE)
    combos <- list(
      alpha_vs_pred_speed = list(
        x = "alpha",
        y = "pred_speed",
        xlab = expression(alpha),
        ylab = "Front speed (cells·yr\u207b\u00b9)",
        title = "Macro-F1: \u03b1 vs front speed"
      ),
      mean_km_vs_presence = list(
        x = "dispersal_mean_km",
        y = "presence_rate",
        xlab = "Dispersal mean (km)",
        ylab = "Presence-only rate",
        title = "Macro-F1: dispersal mean vs presence rate"
      ),
      allee_vs_pred_speed = list(
        x = "allee_A_over_K",
        y = "pred_speed",
        xlab = "Allee A/K",
        ylab = "Front speed (cells·yr\u207b\u00b9)",
        title = "Macro-F1: Allee strength vs front speed"
      )
    )
    purrr::map_chr(names(combos), function(name) {
      combo <- combos[[name]]
      cells <- exdyn_bin_f1(sweep_oof, combo$x, combo$y, bins = 8, min_n = 50)
      png_path <- file.path("outputs", "heatmaps", paste0(name, ".png"))
      if (!nrow(cells)) {
        grDevices::png(png_path, width = 650, height = 500)
        on.exit(grDevices::dev.off(), add = TRUE)
        par(mar = c(0, 0, 0, 0))
        plot.new()
        text(0.5, 0.5, "No data available", cex = 1.2)
        return(png_path)
      }
      plot_obj <- exdyn_plot_heatmap(cells, combo$xlab, combo$ylab, combo$title)
      ggplot2::ggsave(png_path, plot_obj, width = 6.5, height = 5, dpi = 130)
      png_path
    })
  }),
  tar_target(design_table, {
    all_levels <- levels(factor(sweep_predictions$truth))
    per_run <- sweep_predictions %>%
      dplyr::group_by(exp_id) %>%
      dplyr::summarise(
        species = dplyr::first(species),
        scenario = dplyr::first(scenario),
        presence_rate = dplyr::first(presence_rate),
        alpha = dplyr::first(alpha),
        macro_f1 = yardstick::f_meas_vec(
          factor(truth, levels = all_levels),
          factor(estimate, levels = all_levels),
          estimator = "macro"
        ),
        .groups = "drop"
      ) %>%
      dplyr::left_join(
        sweep_results %>%
          dplyr::select(exp_id, nx, ny, years, dispersal_mean_km, pred_speed,
            effort_strength, allee_A_over_K),
        by = "exp_id"
      )
    range_fmt <- function(x) {
      x <- x[is.finite(x)]
      if (!length(x)) return(NA_character_)
      sprintf("%.2f-%.2f", min(x), max(x))
    }
    safe_min <- function(x) {
      x <- x[is.finite(x)]
      if (!length(x)) return(NA_real_)
      min(x)
    }
    safe_max <- function(x) {
      x <- x[is.finite(x)]
      if (!length(x)) return(NA_real_)
      max(x)
    }
    summarised <- per_run %>%
      dplyr::group_by(scenario, species) %>%
      dplyr::summarise(
        nx = stats::median(nx, na.rm = TRUE),
        ny = stats::median(ny, na.rm = TRUE),
        years = stats::median(years, na.rm = TRUE),
        alpha_range = range_fmt(alpha[macro_f1 >= 0.8]),
        mean_km_range = range_fmt(dispersal_mean_km[macro_f1 >= 0.8]),
        speed_cells_per_year_range = range_fmt(pred_speed[macro_f1 >= 0.8]),
        presence_only_rate_min = safe_min(presence_rate[macro_f1 >= 0.8]),
        effort_strength_max = safe_max(effort_strength[macro_f1 >= 0.8]),
        A_over_K_max = safe_max(allee_A_over_K[macro_f1 >= 0.8]),
        macro_F1_median = stats::median(macro_f1, na.rm = TRUE),
        macro_F1_p10 = stats::quantile(macro_f1, probs = 0.1, na.rm = TRUE, names = FALSE),
        prop_macro_F1_ge_0_8 = mean(macro_f1 >= 0.8, na.rm = TRUE),
        .groups = "drop"
      )
    data.table::fwrite(summarised, "outputs/design_table.csv")
    "outputs/design_table.csv"
  }),
  tar_target(diagnostic_cases, {
    exp_grid %>% dplyr::group_by(scenario) %>% dplyr::slice_head(n = 1) %>% dplyr::ungroup()
  }),
  tar_target(diagnostic_maps, {
    purrr::map(seq_len(nrow(diagnostic_cases)), function(i) {
      row <- diagnostic_cases[i, , drop = FALSE]
      core <- exdyn_run_core(row)
      list(
        scenario = row$scenario[[1]],
        T_P = core$fields$T_P,
        T_X = core$T_X,
        D = core$fields$D,
        coupling = exdyn_arrival_coupling(core$T_X, core$fields$T_P, core$fields$D),
        plane = exdyn_front_plane(core$T_X)
      )
    })
  }),
  tar_target(save_diagnostics, {
    dir.create(file.path("outputs", "diagnostics"), recursive = TRUE, showWarnings = FALSE)
    pal <- grDevices::colorRampPalette(c("#f7fbff", "#c6dbef", "#6baed6", "#2171b5"))
    save_surface <- function(mat, file, main) {
      if (is.null(mat) || all(is.na(mat))) return(NULL)
      grDevices::png(file, width = 600, height = 600)
      on.exit(grDevices::dev.off(), add = TRUE)
      par(mar = c(2, 2, 3, 2))
      image(x = seq_len(nrow(mat)), y = seq_len(ncol(mat)),
            z = t(mat)[, nrow(mat):1], col = pal(80), axes = FALSE,
            xlab = "", ylab = "")
      box()
      title(main)
    }
    save_scatter <- function(T_P, T_X, coupling, file) {
      if (is.null(T_P) || is.null(T_X)) return(NULL)
      valid <- which(!is.na(T_P) & !is.na(T_X))
      if (!length(valid)) return(NULL)
      grDevices::png(file, width = 600, height = 600)
      on.exit(grDevices::dev.off(), add = TRUE)
      par(mar = c(4, 4, 3, 1))
      plot(T_P[valid], T_X[valid], pch = 16, col = grDevices::rgb(0.1, 0.2, 0.6, 0.6),
           xlab = "Arrival time (T_P)", ylab = "Extirpation time (T_X)")
      fit <- stats::lm(T_X[valid] ~ T_P[valid])
      coefs <- stats::coef(fit)
      if (all(is.finite(coefs))) {
        abline(fit, col = "firebrick", lwd = 2)
      }
      r2 <- if (!is.null(coupling$r2_arrival)) coupling$r2_arrival else suppressWarnings(summary(fit)$r.squared)
      lag <- if (!is.null(coupling$lag_arrival_mean)) coupling$lag_arrival_mean else mean(T_X[valid] - T_P[valid])
      if (!is.finite(r2)) r2 <- NA_real_
      if (!is.finite(lag)) lag <- NA_real_
      title(sprintf("T_X vs T_P (R^2 = %.2f, lag = %.1f)", r2, lag))
    }
    save_plane_residual <- function(T_X, file) {
      placeholder <- function(msg) {
        grDevices::png(file, width = 600, height = 600)
        on.exit(grDevices::dev.off(), add = TRUE)
        par(mar = c(0, 0, 0, 0))
        plot.new()
        text(0.5, 0.5, msg, cex = 1.2)
      }
      if (is.null(T_X) || all(is.na(T_X))) {
        placeholder("Plane residuals unavailable")
        return(NULL)
      }
      idx <- which(!is.na(T_X), arr.ind = TRUE)
      if (nrow(idx) < 3) {
        placeholder("Insufficient data for plane fit")
        return(NULL)
      }
      df <- data.frame(t = T_X[idx], x = idx[,1], y = idx[,2])
      fit <- stats::lm(t ~ x + y, data = df)
      pred <- predict(fit, newdata = df)
      residuals <- matrix(NA_real_, nrow = nrow(T_X), ncol = ncol(T_X))
      residuals[cbind(idx[,1], idx[,2])] <- df$t - pred
      save_surface(residuals, file, "Plane residuals")
    }
    invisible(purrr::map(diagnostic_maps, function(diag) {
      scen <- diag$scenario
      save_surface(diag$T_P, file.path("outputs", "diagnostics", paste0("TP_", scen, ".png")),
                   main = paste("Arrival (T_P)", scen))
      save_surface(diag$T_X, file.path("outputs", "diagnostics", paste0("TX_", scen, ".png")),
                   main = paste("Extirpation (T_X)", scen))
      save_surface(diag$D, file.path("outputs", "diagnostics", paste0("D_", scen, ".png")),
                   main = paste("Distance (D)", scen))
      if (identical(scen, "predation_front")) {
        save_surface(diag$T_P, file.path("outputs", "diagnostics", "T_P.png"), "Arrival (T_P)")
        save_surface(diag$T_X, file.path("outputs", "diagnostics", "T_X.png"), "Extirpation (T_X)")
        save_surface(diag$D, file.path("outputs", "diagnostics", "D.png"), "Distance to seed (D)")
        save_scatter(diag$T_P, diag$T_X, diag$coupling, file.path("outputs", "diagnostics", "T_scatter.png"))
        save_plane_residual(diag$T_X, file.path("outputs", "diagnostics", "front_plane.png"))
      }
    }))
    list.files(file.path("outputs", "diagnostics"), full.names = TRUE)
  }),
  tar_target(power_grid, exdyn_power_grid()),
  tar_target(power_runs, exdyn_run_core(power_grid), pattern = map(power_grid), iteration = "list"),
  tar_target(power_results, dplyr::bind_rows(purrr::map(power_runs, "summary"))),
  tar_target(power_feature_sets, exdyn_feature_sets(power_results)),
  tar_target(power_cv, exdyn_cv_macro_f1(power_results, power_feature_sets$response_only, v = 3, seed = 432)),
  tar_target(power_predictions, power_cv$predictions),
  tar_target(save_power_outputs, {
    dir.create("outputs", showWarnings = FALSE)
    data.table::fwrite(power_cv$summary, "outputs/power_curve_response_only.csv")
    plt <- ggplot2::ggplot(power_cv$summary, ggplot2::aes(x = alpha, y = macro_f1, color = factor(presence_rate), group = factor(presence_rate))) +
      ggplot2::geom_line() +
      ggplot2::geom_point() +
      ggplot2::labs(color = "presence_rate", x = expression(alpha), y = "Macro F1",
        title = "Response-only macro F1 under observation bias and dispersal") +
      ggplot2::theme_minimal(base_size = 12)
    ggplot2::ggsave(filename = "outputs/power_curve.png", plot = plt, width = 6, height = 4, dpi = 120)
    "outputs"
  }),
  tar_target(save_out, {
    dir.create("outputs", showWarnings = FALSE)
    saveRDS(default_N, "outputs/N.rds")
    data.table::fwrite(default_po, "outputs/presence_only.csv")
    data.table::fwrite(default_foss, "outputs/fossils.csv")
    write.csv(
      data.frame(year = seq_len(cfg$years), total = apply(default_N, 3, sum)),
      "outputs/total_abundance.csv", row.names = FALSE
    )
    saveRDS(default_summs, "outputs/default_summary.rds")
    "outputs"
  }),
  tar_target(save_res, {
    dir.create("outputs", showWarnings = FALSE)
    stale <- c(
      "confusion.csv", "confusion_primary.csv", "confusion_primary_overall.csv",
      "confusion_primary_per_class.csv", "confusion_secondary.csv",
      "confusion_secondary_per_class.csv", "confusion_overall.csv",
      "confusion_per_class.csv", "feature_importance.csv",
      "feature_importance_primary.csv"
    )
    unlink(file.path("outputs", stale), recursive = FALSE, force = TRUE)
    data.table::fwrite(results, "outputs/experiment_results.csv")
    data.table::fwrite(results_response_only, "outputs/experiment_results_response_only.csv")
    data.table::fwrite(qa_summary_table, "outputs/qa_run_summary.csv")
    data.table::fwrite(qa_outlier_table, "outputs/qa_outliers.csv")
    data.table::fwrite(qa_metrics_overview, "outputs/metrics_overview.csv")
    data.table::fwrite(conf_driver_aware$confusion, "outputs/confusion_driver_aware.csv")
    data.table::fwrite(conf_driver_aware$per_class, "outputs/confusion_driver_aware_per_class.csv")
    data.table::fwrite(conf_driver_aware$overall, "outputs/confusion_driver_aware_overall.csv")
    data.table::fwrite(conf_response_only$confusion, "outputs/confusion_response_only.csv")
    data.table::fwrite(conf_response_only$per_class, "outputs/confusion_response_only_per_class.csv")
    data.table::fwrite(conf_response_only$overall, "outputs/confusion_response_only_overall.csv")
    data.table::fwrite(feature_importance_driver_aware, "outputs/feature_importance_driver_aware.csv")
    data.table::fwrite(feature_importance_response_only, "outputs/feature_importance_response_only.csv")
    "outputs"
  }),
  tar_target(design_guidance, {
    dir.create("outputs", showWarnings = FALSE)
    driver_label <- clf_driver_aware$primary$label
    driver_macro <- clf_driver_aware$primary$macro_f1
    response_macro <- clf_response_only$primary$macro_f1
    front_row <- dplyr::filter(conf_driver_aware$per_class, scenario == "predation_front")
    front_recall <- if (nrow(front_row)) front_row$recall else NA_real_
    front_summary <- results %>%
      dplyr::filter(scenario == "predation_front") %>%
      dplyr::summarise(
        median_r2_arrival = stats::median(r2_arrival, na.rm = TRUE),
        median_r2_dist = stats::median(r2_dist, na.rm = TRUE),
        median_coverage = stats::median(arrival_coverage, na.rm = TRUE)
      )
    driver_msg <- if (!is.na(front_recall) && front_recall < 0.5) {
      sprintf("Driver-aware predation recall %.2f < 0.5 (median r2_arrival=%.2f, r2_dist=%.2f, coverage=%.2f).",
        front_recall, front_summary$median_r2_arrival, front_summary$median_r2_dist, front_summary$median_coverage)
    } else {
      sprintf("Driver-aware predation recall %.2f with macro F1 %.2f.", front_recall, driver_macro)
    }
    worst_power <- power_cv$summary %>% dplyr::arrange(macro_f1) %>% dplyr::slice_head(n = 1)
    response_msg <- if (!is.na(response_macro) && response_macro < 0.6 && nrow(worst_power)) {
      sprintf("Response-only macro F1 %.2f < 0.6; weakest combo rate=%.4f, alpha=%.1f (macro F1 %.2f).",
        response_macro, worst_power$presence_rate, worst_power$alpha, worst_power$macro_f1)
    } else {
      sprintf("Response-only macro F1 %.2f.", response_macro)
    }
    driver_feats <- head(feature_importance_driver_aware, 5)
    resp_feats <- head(feature_importance_response_only, 5)
    driver_lines <- if (nrow(driver_feats)) sprintf("- %s (importance %.3f)", driver_feats$feature, driver_feats$importance) else "- (no driver-aware features)"
    resp_lines <- if (nrow(resp_feats)) sprintf("- %s (importance %.3f)", resp_feats$feature, resp_feats$importance) else "- (no response-only features)"
    lines <- c(
      sprintf("Driver-aware model: %s (macro F1 = %.3f)", driver_label, driver_macro),
      driver_msg,
      sprintf("Response-only macro F1 = %.3f", response_macro),
      response_msg,
      "Top driver-aware features:",
      driver_lines,
      "Top response-only features:",
      resp_lines
    )
    writeLines(lines, "outputs/design_guidance.txt")
    "outputs/design_guidance.txt"
  })
)

# To scale out, consider `targets::tar_make_future()` or `tarchetypes::tar_make_clustermq()`.
