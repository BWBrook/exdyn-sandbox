# Helper utilities to keep _targets.R readable ------------------------------

# QA summaries ----------------------------------------------------------------

#' Summarise QA metrics by scenario
#' @keywords internal
build_qa_metrics_overview <- function(results) {
  tibble::as_tibble(results) %>%
    dplyr::group_by(scenario) %>%
    dplyr::summarise(
      median_arrival_coverage = stats::median(arrival_coverage, na.rm = TRUE),
      iqr_arrival_coverage    = stats::IQR(arrival_coverage, na.rm = TRUE),
      median_lag_arrival      = stats::median(lag_arrival_mean, na.rm = TRUE),
      iqr_lag_arrival         = stats::IQR(lag_arrival_mean, na.rm = TRUE),
      median_r2_arrival       = stats::median(r2_arrival, na.rm = TRUE),
      iqr_r2_arrival          = stats::IQR(r2_arrival, na.rm = TRUE),
      median_resp_orient_R    = stats::median(resp_orient_R, na.rm = TRUE),
      iqr_resp_orient_R       = stats::IQR(resp_orient_R, na.rm = TRUE),
      median_resp_edge_dir_R  = stats::median(resp_edge_dir_R, na.rm = TRUE),
      iqr_resp_edge_dir_R     = stats::IQR(resp_edge_dir_R, na.rm = TRUE),
      median_resp_speed_r2    = stats::median(resp_speed_r2, na.rm = TRUE),
      iqr_resp_speed_r2       = stats::IQR(resp_speed_r2, na.rm = TRUE),
      .groups = "drop"
    )
}

#' Per-run QA summary table
#' @keywords internal
build_qa_summary_table <- function(results) {
  tibble::as_tibble(results) %>%
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
}

#' Identify QA outliers
#' @keywords internal
build_qa_outliers <- function(qa_summary, top_fraction = 0.1) {
  if (!nrow(qa_summary)) {
    return(qa_summary)
  }
  qa_summary %>%
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
    dplyr::select(-.reasons) %>%
    dplyr::filter(score > 0) %>%
    dplyr::arrange(dplyr::desc(score), arrival_coverage, lag_arrival_mean) %>%
    dplyr::slice_head(n = max(1, ceiling(nrow(qa_summary) * top_fraction)))
}

#' Write QA tables
#' @keywords internal
write_qa_tables <- function(qa_summary, qa_outliers, qa_metrics, dir = "outputs") {
  dir.create(dir, showWarnings = FALSE)
  paths <- c(
    qa_run = file.path(dir, "qa_run_summary.csv"),
    qa_outliers = file.path(dir, "qa_outliers.csv"),
    metrics = file.path(dir, "metrics_overview.csv")
  )
  data.table::fwrite(qa_summary, paths["qa_run"])
  data.table::fwrite(qa_outliers, paths["qa_outliers"])
  data.table::fwrite(qa_metrics, paths["metrics"])
  unname(paths)
}

# Sweep summaries --------------------------------------------------------------

build_sweep_f1_by_scenario <- function(predictions) {
  preds <- tibble::as_tibble(predictions)
  levels_all <- levels(preds$truth)
  conf <- table(preds$truth, preds$estimate)
  diag_vals <- diag(conf)
  precision <- diag_vals / pmax(1, colSums(conf))
  recall <- diag_vals / pmax(1, rowSums(conf))
  f1 <- ifelse(precision + recall == 0, NA_real_, 2 * precision * recall / (precision + recall))
  tibble::tibble(scenario = levels_all, macro_f1 = f1)
}

build_sweep_f1_by_archetype <- function(predictions) {
  preds <- tibble::as_tibble(predictions)
  helper <- function(df) {
    if (nrow(df) < 3) return(NA_real_)
    truth <- factor(df$truth, levels = levels(preds$truth))
    est <- factor(df$estimate, levels = levels(truth))
    conf <- table(truth, est)
    diag_vals <- diag(conf)
    precision <- diag_vals / pmax(1, colSums(conf))
    recall <- diag_vals / pmax(1, rowSums(conf))
    f1 <- ifelse(precision + recall == 0, NA_real_, 2 * precision * recall / (precision + recall))
    mean(f1, na.rm = TRUE)
  }
  preds %>%
    dplyr::group_by(species) %>%
    dplyr::summarise(macro_f1 = helper(dplyr::cur_data_all()), .groups = "drop")
}

write_sweep_tables <- function(f1_scenario, f1_archetype, dir = "outputs") {
  dir.create(dir, showWarnings = FALSE)
  files <- c(
    file.path(dir, "sweep_f1_by_scenario.csv"),
    file.path(dir, "sweep_f1_by_archetype.csv")
  )
  data.table::fwrite(f1_scenario, files[1])
  data.table::fwrite(f1_archetype, files[2])
  files
}

# Partial dependence ----------------------------------------------------------

write_partial_dependence <- function(predictions, sweep_results, dir = file.path("outputs", "partial_dependence"), top_n = 4) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  joined <- predictions %>%
    dplyr::left_join(
      sweep_results %>% dplyr::select(exp_id, dispersal_mean_km, pred_speed, effort_strength,
        allee_A_over_K, habitat_beta, habitat_ramp_start, habitat_ramp_end, nx, ny, years),
      by = "exp_id"
    ) %>%
    dplyr::mutate(correct = as.numeric(truth == estimate))

  ctrl_vars <- c("alpha", "dispersal_mean_km", "pred_speed", "presence_rate",
                 "effort_strength", "allee_A_over_K", "habitat_beta")

  pd_data <- joined %>% dplyr::select(dplyr::any_of(ctrl_vars), correct) %>% tidyr::drop_na()
  if (!nrow(pd_data)) {
    return(character())
  }

  ctrl_formula <- stats::as.formula(paste("factor(correct, levels = c(0,1)) ~", paste(ctrl_vars, collapse = " + ")))
  rf <- tryCatch(
    ranger::ranger(ctrl_formula, data = pd_data, probability = TRUE,
                   importance = "impurity", num.trees = 600, seed = 2468),
    error = function(e) NULL
  )
  importance <- if (is.null(rf)) {
    tibble::tibble(feature = ctrl_vars, importance = NA_real_)
  } else {
    tibble::tibble(feature = names(rf$variable.importance), importance = as.numeric(rf$variable.importance)) %>%
      dplyr::arrange(dplyr::desc(importance))
  }
  top_features <- head(importance$feature[is.finite(importance$importance)], top_n)
  if (!length(top_features)) top_features <- head(ctrl_vars, top_n)

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
    csv_path <- file.path(dir, paste0(feat, ".csv"))
    data.table::fwrite(pd_tbl, csv_path)
    plot_path <- file.path(dir, paste0(feat, ".png"))
    plt <- ggplot2::ggplot(pd_tbl, ggplot2::aes(x = value, y = mean_correct)) +
      ggplot2::geom_line(color = "#2b8cbe", linewidth = 1) +
      ggplot2::geom_point(color = "#045a8d") +
      ggplot2::labs(title = paste("Partial dependence:", feat), x = feat, y = "Pr(correct classification)") +
      ggplot2::theme_minimal(base_size = 12)
    ggplot2::ggsave(plot_path, plt, width = 6, height = 4, dpi = 130)
    out_files <- c(out_files, csv_path, plot_path)
  }
  out_files
}

# Heatmaps --------------------------------------------------------------------

write_sensitivity_heatmaps <- function(oof_predictions, dir = file.path("outputs", "heatmaps")) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  combos <- list(
    alpha_vs_pred_speed = list(x = "alpha", y = "pred_speed", xlab = expression(alpha),
                               ylab = "Front speed (cells·yr\u207b\u00b9)",
                               title = "Macro-F1: alpha vs front speed"),
    mean_km_vs_presence = list(x = "dispersal_mean_km", y = "presence_rate",
                               xlab = "Dispersal mean (km)",
                               ylab = "Presence-only rate",
                               title = "Macro-F1: dispersal mean vs presence rate"),
    allee_vs_pred_speed = list(x = "allee_A_over_K", y = "pred_speed",
                               xlab = "Allee A/K",
                               ylab = "Front speed (cells·yr\u207b\u00b9)",
                               title = "Macro-F1: Allee strength vs front speed")
  )
  purrr::imap_chr(combos, function(combo, stub) {
    cells <- exdyn_bin_f1(oof_predictions, combo$x, combo$y, bins = 8, min_n = 5)
    png_path <- file.path(dir, paste0(stub, ".png"))
    if (!nrow(cells)) {
      grDevices::png(png_path, width = 650, height = 500)
      on.exit(grDevices::dev.off(), add = TRUE)
      par(mar = c(0, 0, 0, 0))
      plot.new()
      text(0.5, 0.5, "No data available", cex = 1.2)
      return(png_path)
    }
    plt <- exdyn_plot_heatmap(cells, combo$xlab, combo$ylab, combo$title)
    ggplot2::ggsave(png_path, plt, width = 6.5, height = 5, dpi = 130)
    png_path
  })
}

# Design table & guidance -----------------------------------------------------

build_design_table <- function(predictions, sweep_results) {
  preds <- tibble::as_tibble(predictions)
  per_run <- preds %>%
    dplyr::group_by(exp_id) %>%
    dplyr::summarise(
      species = dplyr::first(species),
      scenario = dplyr::first(scenario),
      presence_rate = dplyr::first(presence_rate),
      alpha = dplyr::first(alpha),
      macro_f1 = yardstick::f_meas_vec(
        factor(truth, levels = levels(preds$truth)),
        factor(estimate, levels = levels(preds$truth)),
        estimator = "macro"
      ),
      .groups = "drop"
    ) %>%
    dplyr::left_join(
      sweep_results %>% dplyr::select(exp_id, nx, ny, years, dispersal_mean_km, pred_speed,
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
  per_run %>%
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
}

write_design_table <- function(design_table, path = file.path("outputs", "design_table.csv")) {
  dir.create(dirname(path), showWarnings = FALSE)
  data.table::fwrite(design_table, path)
  path
}

write_design_guidance <- function(clf_driver, clf_response, conf_driver, results, power_cv,
                                  feature_importance_driver, feature_importance_response,
                                  path = file.path("outputs", "design_guidance.txt")) {
  dir.create(dirname(path), showWarnings = FALSE)
  driver_label <- clf_driver$primary$label
  driver_macro <- clf_driver$primary$macro_f1
  response_macro <- clf_response$primary$macro_f1
  front_row <- dplyr::filter(conf_driver$per_class, scenario == "predation_front")
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
  driver_feats <- head(feature_importance_driver, 5)
  resp_feats <- head(feature_importance_response, 5)
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
  writeLines(lines, path)
  path
}

# Diagnostics -----------------------------------------------------------------

select_diagnostic_cases <- function(exp_grid, n_per_scenario = 1) {
  exp_grid %>%
    dplyr::group_by(scenario) %>%
    dplyr::slice_head(n = n_per_scenario) %>%
    dplyr::ungroup()
}

write_diagnostic_surfaces <- function(exp_grid, cases, dir = file.path("outputs", "diagnostics")) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  palette_fn <- grDevices::colorRampPalette(c("#f7fbff", "#c6dbef", "#6baed6", "#08306b"))
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
  files <- character(0)
  for (idx in seq_len(nrow(cases))) {
    row <- cases[idx, , drop = FALSE]
    core <- exdyn_run_core(row)
    exp_id <- row$exp_id[[1]]
    prefix <- file.path(dir, paste0("rasters_", exp_id))
    tp_file <- paste0(prefix, "_TP.png")
    tx_file <- paste0(prefix, "_TX.png")
    files <- c(files, save_surface(core$fields$T_P, tp_file, sprintf("Predator arrival (T_P) – %s", exp_id)))
    files <- c(files, save_surface(core$T_X, tx_file, sprintf("Extirpation time (T_X) – %s", exp_id)))
    yrs <- dim(core$N)[3]
    time_points <- unique(round(seq(1, yrs, length.out = 3)))
    for (tpt in time_points) {
      n_file <- paste0(prefix, sprintf("_N_t%03d.png", tpt))
      files <- c(files, save_abundance(core$N, tpt, n_file, sprintf("log(N+1) at t=%d – %s", tpt, exp_id)))
    }
  }
  files[!is.na(files)]
}

# Design guidance -------------------------------------------------------------

write_design_guidance <- function(clf_driver, clf_response, conf_driver, results, power_cv,
                                  feature_importance_driver, feature_importance_response,
                                  path = file.path("outputs", "design_guidance.txt")) {
  dir.create(dirname(path), showWarnings = FALSE)
  driver_label <- clf_driver$primary$label
  driver_macro <- clf_driver$primary$macro_f1
  response_macro <- clf_response$primary$macro_f1
  front_row <- dplyr::filter(conf_driver$per_class, scenario == "predation_front")
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
  driver_feats <- head(feature_importance_driver, 5)
  resp_feats <- head(feature_importance_response, 5)
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
  writeLines(lines, path)
  path
}

# Power experiment outputs ----------------------------------------------------

write_power_outputs <- function(power_summary, dir = "outputs") {
  dir.create(dir, showWarnings = FALSE)
  csv_path <- file.path(dir, "power_curve_response_only.csv")
  png_path <- file.path(dir, "power_curve.png")
  data.table::fwrite(power_summary, csv_path)
  plt <- ggplot2::ggplot(power_summary,
    ggplot2::aes(x = alpha, y = macro_f1, color = factor(presence_rate), group = factor(presence_rate))) +
    ggplot2::geom_line() +
    ggplot2::geom_point() +
    ggplot2::labs(color = "presence_rate", x = expression(alpha), y = "Macro F1",
      title = "Response-only macro F1 under observation bias and dispersal") +
    ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(filename = png_path, plot = plt, width = 6, height = 4, dpi = 120)
  c(csv_path, png_path)
}
