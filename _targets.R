library(targets)
library(tarchetypes)
tar_option_set(packages = c("yaml","data.table","ggplot2","matrixStats"),
               error = "continue")

if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
} else if (requireNamespace("devtools", quietly = TRUE)) {
  devtools::load_all(export_all = FALSE)
}

source("R/utils.R", local = TRUE)

list(
  tar_target(cfg, exdyn_config("config/default.yaml"), cue = tar_cue("always")),
  tar_target(fields, exdyn_make_fields(cfg$nx, cfg$ny, cfg$years, cfg$scenario,
                                       cfg$ramp_start, cfg$ramp_end)),
  tar_target(N, exdyn_simulate(cfg$nx, cfg$ny, cfg$years, fields, cfg$pars,
                               K0=cfg$K0, alpha=cfg$alpha,
                               disp_mean_cells = cfg$disp_mean_cells,
                               pred = cfg$pred)),
  tar_target(po, exdyn_presence_only(N, rate = cfg$obs$presence_only_rate)),
  tar_target(foss, exdyn_fossils(N, n_sites = cfg$obs$fossil_sites,
                                 date_sd = cfg$obs$fossil_date_sd_y)),
  tar_target(summs, exdyn_summaries(N, fields)),
  tar_target(save_out, {
    dir.create("outputs", showWarnings = FALSE)
    saveRDS(N, "outputs/N.rds"); 
    data.table::fwrite(po, "outputs/presence_only.csv")
    data.table::fwrite(foss, "outputs/fossils.csv")
    write.csv(data.frame(year=seq_len(cfg$years), total=summs$total),
              "outputs/total_abundance.csv", row.names=FALSE)
    "outputs"
  })
)
