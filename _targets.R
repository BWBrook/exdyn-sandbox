library(targets)
library(tarchetypes)
tar_option_set(
  packages = c(
    "yaml","data.table","ggplot2","matrixStats","tibble",
    "dplyr","purrr","tidyr","stringr","ranger","yardstick","lhs",
    "viridisLite","rlang",
    "rsample","glmnet"
  ),
  error = "continue"
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
    joined <- sweep_predictions %>%
      dplyr::left_join(sweep_results %>% dplyr::select(exp_id, dispersal_mean_km, pred_speed, presence_rate,
        effort_strength, allee_A_over_K), by = "exp_id")
    helper_macro <- function(df) {
      if (nrow(df) < 5) return(NA_real_)
      truth <- factor(df$truth, levels = levels(sweep_predictions$truth))
      est <- factor(df$estimate, levels = levels(truth))
      conf <- table(truth, est)
      diag_vals <- diag(conf)
      precision <- diag_vals / pmax(1, colSums(conf))
      recall <- diag_vals / pmax(1, rowSums(conf))
      f1 <- ifelse(precision + recall == 0, NA_real_, 2 * precision * recall / (precision + recall))
      mean(f1, na.rm = TRUE)
    }
    make_heat <- function(xvar, yvar, file_stub) {
      png_path <- file.path("outputs", "heatmaps", paste0(file_stub, ".png"))
      placeholder <- function(msg) {
        grDevices::png(png_path, width = 650, height = 500)
        on.exit(grDevices::dev.off(), add = TRUE)
        par(mar = c(0, 0, 0, 0))
        plot.new()
        text(0.5, 0.5, msg, cex = 1.2)
        png_path
      }
      if (!(xvar %in% names(joined)) || !(yvar %in% names(joined))) {
        return(placeholder("Controls unavailable"))
      }
      df <- joined[, c("truth", "estimate", xvar, yvar), drop = FALSE]
      df <- df[stats::complete.cases(df), , drop = FALSE]
      if (!nrow(df)) return(placeholder("No observations"))
      x_breaks <- unique(stats::quantile(df[[xvar]], probs = seq(0, 1, length.out = 8), na.rm = TRUE))
      y_breaks <- unique(stats::quantile(df[[yvar]], probs = seq(0, 1, length.out = 8), na.rm = TRUE))
      if (length(x_breaks) < 2 || length(y_breaks) < 2) return(placeholder("Insufficient spread"))
      df$x_bin <- cut(df[[xvar]], breaks = x_breaks, include_lowest = TRUE)
      df$y_bin <- cut(df[[yvar]], breaks = y_breaks, include_lowest = TRUE)
      df <- df[!is.na(df$x_bin) & !is.na(df$y_bin), , drop = FALSE]
      if (!nrow(df)) return(placeholder("Empty bins"))
      df$key <- interaction(df$x_bin, df$y_bin, drop = TRUE)
      heat <- purrr::imap_dfr(split(df, df$key), function(subdf, key) {
        bins <- strsplit(key, "\\.")[[1]]
        tibble::tibble(
          x_bin = bins[1],
          y_bin = bins[2],
          macro_f1 = helper_macro(subdf),
          x_mid = mean(subdf[[xvar]], na.rm = TRUE),
          y_mid = mean(subdf[[yvar]], na.rm = TRUE),
          n = nrow(subdf)
        )
      })
      if (!nrow(heat) || all(is.na(heat$macro_f1))) return(placeholder("No variation"))
      plt <- ggplot2::ggplot(heat, ggplot2::aes(x = x_mid, y = y_mid, fill = macro_f1)) +
        ggplot2::geom_tile(color = NA) +
        ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey85") +
        ggplot2::labs(x = xvar, y = yvar, fill = "Macro F1", title = paste("F1 heatmap:", xvar, "vs", yvar)) +
        ggplot2::theme_minimal(base_size = 12)
      ggplot2::ggsave(png_path, plt, width = 6.5, height = 5, dpi = 130)
      png_path
    }
    files <- c(
      make_heat("alpha", "pred_speed", "alpha_vs_pred_speed"),
      make_heat("dispersal_mean_km", "presence_rate", "mean_km_vs_presence"),
      make_heat("allee_A_over_K", "pred_speed", "allee_vs_pred_speed")
    )
    files[!vapply(files, is.null, logical(1))]
  }),
  tar_target(design_table, {
    joined <- sweep_predictions %>%
      dplyr::left_join(sweep_results %>% dplyr::select(exp_id, dispersal_mean_km,
        pred_speed, effort_strength, allee_A_over_K, nx, ny, years), by = "exp_id") %>%
      dplyr::mutate(correct = as.integer(truth == estimate))
    binary_f1 <- function(df, target_scenario) {
      if (length(target_scenario) != 1) target_scenario <- target_scenario[1]
      target_scenario <- as.character(target_scenario)
      if (nrow(df) < 5) return(NA_real_)
      truth <- factor(ifelse(df$truth == target_scenario, target_scenario, "other"), levels = c(target_scenario, "other"))
      est <- factor(ifelse(df$estimate == target_scenario, target_scenario, "other"), levels = c(target_scenario, "other"))
      conf <- table(truth, est)
      tp <- conf[target_scenario, target_scenario]
      precision <- tp / pmax(1, sum(conf[, target_scenario]))
      recall <- tp / pmax(1, sum(conf[target_scenario, ]))
      if (precision + recall == 0) return(NA_real_)
      2 * precision * recall / (precision + recall)
    }
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
    summarised <- joined %>%
      dplyr::group_by(scenario, species) %>%
      dplyr::summarise(
        nx = stats::median(nx, na.rm = TRUE),
        ny = stats::median(ny, na.rm = TRUE),
        years = stats::median(years, na.rm = TRUE),
        alpha_range = range_fmt(alpha[correct == 1]),
        mean_km_range = range_fmt(dispersal_mean_km[correct == 1]),
        speed_cells_per_year_range = range_fmt(pred_speed[correct == 1]),
        presence_only_rate_min = safe_min(presence_rate[correct == 1]),
        effort_strength_max = safe_max(effort_strength[correct == 1]),
        A_over_K_max = safe_max(allee_A_over_K[correct == 1]),
        macro_F1_median = binary_f1(dplyr::pick(dplyr::everything()), dplyr::cur_group()$scenario),
        macro_F1_p10 = stats::quantile(correct, probs = 0.1, na.rm = TRUE),
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
