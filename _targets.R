library(targets)
library(tarchetypes)
tar_option_set(
  packages = c(
    "yaml","data.table","ggplot2","matrixStats","tibble",
    "dplyr","purrr","tidyr","stringr","ranger","yardstick","lhs",
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
  tar_target(classifiers, exdyn_fit_classifier(results)),
  tar_target(conf_ranger, exdyn_confusion(classifiers$ranger$predictions)),
  tar_target(conf_glmnet, exdyn_confusion(classifiers$glmnet$predictions)),
  tar_target(primary_model, {
    scores <- c(ranger = classifiers$ranger$macro_f1, glmnet = classifiers$glmnet$macro_f1)
    scores[is.na(scores)] <- -Inf
    names(scores)[which.max(scores)]
  }),
  tar_target(clf_primary, if (primary_model == "ranger") classifiers$ranger else classifiers$glmnet),
  tar_target(clf_secondary, if (primary_model == "ranger") classifiers$glmnet else classifiers$ranger),
  tar_target(confusion_primary, if (primary_model == "ranger") conf_ranger else conf_glmnet),
  tar_target(confusion_secondary, if (primary_model == "ranger") conf_glmnet else conf_ranger),
  tar_target(feature_importance_primary, {
    imp <- if (primary_model == "ranger") classifiers$ranger$importance else classifiers$glmnet$importance
    imp %>% dplyr::mutate(importance = tidyr::replace_na(importance, -Inf)) %>%
      dplyr::arrange(dplyr::desc(importance)) %>%
      dplyr::mutate(importance = dplyr::if_else(importance == -Inf, NA_real_, importance))
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
        D = core$fields$D
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
    invisible(purrr::map(diagnostic_maps, function(diag) {
      scen <- diag$scenario
      save_surface(diag$T_P, file.path("outputs", "diagnostics", paste0("TP_", scen, ".png")),
                   main = paste("Arrival (T_P)", scen))
      save_surface(diag$T_X, file.path("outputs", "diagnostics", paste0("TX_", scen, ".png")),
                   main = paste("Extirpation (T_X)", scen))
      save_surface(diag$D, file.path("outputs", "diagnostics", paste0("D_", scen, ".png")),
                   main = paste("Distance (D)", scen))
    }))
    list.files(file.path("outputs", "diagnostics"), full.names = TRUE)
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
    data.table::fwrite(results, "outputs/experiment_results.csv")
    data.table::fwrite(confusion_primary$confusion, "outputs/confusion_primary.csv")
    data.table::fwrite(confusion_primary$per_class, "outputs/confusion_primary_per_class.csv")
    data.table::fwrite(confusion_secondary$confusion, "outputs/confusion_secondary.csv")
    data.table::fwrite(confusion_secondary$per_class, "outputs/confusion_secondary_per_class.csv")
    data.table::fwrite(confusion_primary$overall, "outputs/confusion_primary_overall.csv")
    data.table::fwrite(feature_importance_primary, "outputs/feature_importance_primary.csv")
    "outputs"
  }),
  tar_target(design_guidance, {
    dir.create("outputs", showWarnings = FALSE)
    macro_primary <- if (primary_model == "ranger") classifiers$ranger$macro_f1 else classifiers$glmnet$macro_f1
    top_feats <- head(feature_importance_primary, 5)
    front_row <- dplyr::filter(confusion_primary$per_class, scenario == "predation_front")
    front_recall <- if (nrow(front_row)) front_row$recall else NA_real_
    front_summary <- results %>%
      dplyr::filter(scenario == "predation_front") %>%
      dplyr::summarise(
        median_r2_arrival = stats::median(r2_arrival, na.rm = TRUE),
        median_r2_dist = stats::median(r2_dist, na.rm = TRUE)
      )
    front_msg <- if (!is.na(front_recall) && front_recall < 0.5) {
      sprintf(
        "Predation-front recall %.2f < 0.5. Median r2_arrival=%.2f, r2_dist=%.2f. Consider faster fronts or higher predation contrast before scaling.",
        front_recall,
        front_summary$median_r2_arrival,
        front_summary$median_r2_dist
      )
    } else {
      sprintf("Predation-front recall %.2f meets target; maintain current metric set.", front_recall)
    }
    lines <- c(
      sprintf("Primary model: %s (macro F1 = %.3f)", primary_model, macro_primary),
      front_msg,
      "Key metrics aiding predation-front detection:",
      sprintf("- %s (importance %.3f)", top_feats$feature, top_feats$importance)
    )
    writeLines(lines, "outputs/design_guidance.txt")
    "outputs/design_guidance.txt"
  })
)

# To scale out, consider `targets::tar_make_future()` or `tarchetypes::tar_make_clustermq()`.
