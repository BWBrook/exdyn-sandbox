
library(targets)
library(tarchetypes)
source("pipelines/plan_server.R", local = TRUE)

if (!requireNamespace("qs", quietly = TRUE)) {
  install.packages("qs")
}

tar_option_args <- list(
  packages = c(
    "yaml","data.table","ggplot2","matrixStats","tibble",
    "dplyr","purrr","tidyr","stringr","ranger","yardstick","lhs",
    "viridisLite","rlang","future",
    "rsample","glmnet","zoo","sf","readr","httr","jsonlite"
  ),
  error = "stop",
  envir = globalenv(),
  format = "qs",
  memory = "transient",
  garbage_collection = TRUE,
  cue = tar_cue(mode = "thorough"),
  reporter = "timestamp"
)
tryCatch(
  do.call(tar_option_set, tar_option_args),
  error = function(e) {
    tar_option_args$reporter <- NULL
    do.call(tar_option_set, tar_option_args)
  }
)

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(export_all = FALSE)
}

source("R/utils.R", local = TRUE)
source("R/targets_helpers.R", local = TRUE)
source("R/mem_utils.R", local = TRUE)
source("R/schema.R", local = TRUE)
source("R/canonical.R", local = TRUE)
source("R/mink_predation_field.R", local = TRUE)
source("R/observe.R", local = TRUE)
source("R/simulate_tx_only.R", local = TRUE)
source("R/vole_extirpation.R", local = TRUE)
source("R/synthetic_cfg.R", local = TRUE)
source("R/synthetic_recovery.R", local = TRUE)
source("R/coverage_utils.R", local = TRUE)
source("R/synthetic_twin.R", local = TRUE)
source("R/perf_utils.R", local = TRUE)
source("pipelines/targets_realdata_gbif.R", local = TRUE)
source("pipelines/targets_pilot_mink_vole.R", local = TRUE)
source("pipelines/targets_synthetic.R", local = TRUE)
source("pipelines/targets_perf.R", local = TRUE)

c(
  list(
  # -- Baseline run ----------------------------------------------------------
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
  tar_target(save_out, {
    dir.create("outputs", showWarnings = FALSE)
    saveRDS(default_N, "outputs/N.rds")
    data.table::fwrite(default_po, "outputs/presence_only.csv")
    data.table::fwrite(default_foss, "outputs/fossils.csv")
    utils::write.csv(
      data.frame(year = seq_len(cfg$years), total = apply(default_N, 3, sum)),
      "outputs/total_abundance.csv", row.names = FALSE
    )
    saveRDS(default_summs, "outputs/default_summary.rds")
    "outputs"
  }),

  # -- Experiment grid & QA --------------------------------------------------
  tar_target(exp_grid, exdyn_experiment_grid("config/experiments.yaml")),
  tar_target(exp_summaries, exdyn_run_once(exp_grid), pattern = map(exp_grid), iteration = "list"),
  tar_target(results, dplyr::bind_rows(exp_summaries)),
  tar_target(results_response_only, {
    results %>%
      dplyr::select(exp_id, species, scenario, predation_type, replicate, dplyr::starts_with("resp_"))
  }),
  tar_target(qa_summary_table, build_qa_summary_table(results)),
  tar_target(qa_outlier_table, build_qa_outliers(qa_summary_table)),
  tar_target(qa_metrics_overview, build_qa_metrics_overview(results)),
  tar_target(save_qa_tables, write_qa_tables(qa_summary_table, qa_outlier_table, qa_metrics_overview)),
  tar_target(feature_sets, exdyn_feature_sets(results)),
  tar_target(clf_driver_aware, exdyn_fit_and_eval(results, feature_sets$driver_aware)),
  tar_target(clf_response_only, exdyn_fit_and_eval(results, feature_sets$response_only)),
  tar_target(conf_driver_aware, clf_driver_aware$primary$confusion),
  tar_target(conf_response_only, clf_response_only$primary$confusion),
  tar_target(feature_importance_driver_aware, {
    clf_driver_aware$primary$importance %>%
      dplyr::mutate(importance = tidyr::replace_na(importance, NA_real_)) %>%
      dplyr::arrange(dplyr::desc(importance))
  }),
  tar_target(feature_importance_response_only, {
    clf_response_only$primary$importance %>%
      dplyr::mutate(importance = tidyr::replace_na(importance, NA_real_)) %>%
      dplyr::arrange(dplyr::desc(importance))
  }),

  # -- QA diagnostics --------------------------------------------------------
  tar_target(diagnostic_cases, select_diagnostic_cases(exp_grid)),
  tar_target(save_diagnostics, write_diagnostic_surfaces(exp_grid, diagnostic_cases)),

  # -- Sensitivity sweep -----------------------------------------------------
  tar_target(sweep_grid, exdyn_sweep_grid("config/experiments.yaml")),
  tar_target(sweep_summaries, exdyn_run_once(sweep_grid), pattern = map(sweep_grid), iteration = "list"),
  tar_target(sweep_results, dplyr::bind_rows(sweep_summaries)),
  tar_target(sweep_feature_sets, exdyn_feature_sets(sweep_results)),
  tar_target(sweep_oof, exdyn_oof_predictions(sweep_results, sweep_feature_sets$response_only, v = 5, seed = 987)),
  tar_target(sweep_clf_response_only, exdyn_fit_and_eval(sweep_results, sweep_feature_sets$response_only)),
  tar_target(sweep_cv, exdyn_cv_macro_f1(sweep_results, sweep_feature_sets$response_only, v = 5, seed = 987)),
  tar_target(sweep_predictions, sweep_cv$predictions),
  tar_target(sweep_macro_overall, sweep_clf_response_only$primary$macro_f1),
  tar_target(sweep_f1_by_scenario, build_sweep_f1_by_scenario(sweep_predictions)),
  tar_target(sweep_f1_by_archetype, build_sweep_f1_by_archetype(sweep_predictions)),
  tar_target(save_sweep_tables, write_sweep_tables(sweep_f1_by_scenario, sweep_f1_by_archetype)),
  tar_target(save_partial_dependence, write_partial_dependence(sweep_predictions, sweep_results)),
  tar_target(save_heatmaps, write_sensitivity_heatmaps(sweep_oof)),
  tar_target(design_table, build_design_table(sweep_predictions, sweep_results)),
  tar_target(design_table_path, write_design_table(design_table)),

  # -- Power experiment ------------------------------------------------------
  tar_target(power_grid, exdyn_power_grid()),
  tar_target(power_runs, exdyn_run_core(power_grid), pattern = map(power_grid), iteration = "list"),
  tar_target(power_results, dplyr::bind_rows(purrr::map(power_runs, "summary"))),
  tar_target(power_feature_sets, exdyn_feature_sets(power_results)),
  tar_target(power_cv, exdyn_cv_macro_f1(power_results, power_feature_sets$response_only, v = 3, seed = 432)),
  tar_target(power_predictions, power_cv$predictions),
  tar_target(save_power_outputs, write_power_outputs(power_cv$summary)),

  # -- Consolidated outputs --------------------------------------------------
  tar_target(save_res, {
    dir.create("outputs", showWarnings = FALSE)
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
  tar_target(design_guidance, write_design_guidance(
    clf_driver_aware,
    clf_response_only,
    conf_driver_aware,
    results,
    power_cv,
    feature_importance_driver_aware,
    feature_importance_response_only
  ))
  ),
  targets_realdata_gbif(),
  targets_pilot_mink_vole(),
  targets_synthetic_mink_vole(),
  targets_perf()
)
