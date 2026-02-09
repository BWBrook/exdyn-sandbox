# Synthetic identifiability stress sweep helpers (internal)

exdyn_stress_cfg_resolve <- function(cfg) {
  cfg <- cfg %||% list()
  list(
    enabled = isTRUE(cfg$enabled),
    mode = tolower(cfg$mode %||% "realistic"),
    reps = as.integer(cfg$reps %||% 10L),
    seed = as.integer(cfg$seed %||% 4601L),
    n_cores = as.integer(cfg$n_cores %||% 1L),
    arrival_sources = unique(as.character(cfg$arrival_sources %||% c("synthetic_plane", "real"))),
    obs_multiplier = as.numeric(cfg$obs_multiplier %||% c(0.5, 1.5)),
    pred_scale_multiplier = as.numeric(cfg$pred_scale_multiplier %||% c(0.7, 1.0, 1.3)),
    dropout_add = as.numeric(cfg$dropout_add %||% 0),
    screen = cfg$screen %||% list(),
    abc = cfg$abc %||% list(),
    compat = cfg$compat %||% list()
  )
}

exdyn_stress_scenario_grid <- function(stress_cfg) {
  cfg <- exdyn_stress_cfg_resolve(stress_cfg)
  scenarios <- tidyr::expand_grid(
    arrival_source = cfg$arrival_sources,
    obs_multiplier = cfg$obs_multiplier,
    pred_scale_multiplier = cfg$pred_scale_multiplier,
    dropout_add = cfg$dropout_add
  ) %>%
    dplyr::arrange(.data$arrival_source, .data$obs_multiplier, .data$pred_scale_multiplier, .data$dropout_add) %>%
    dplyr::mutate(
      scenario_id = sprintf(
        "s%02d_%s_o%s_p%s_d%s",
        dplyr::row_number(),
        .data$arrival_source,
        format(round(.data$obs_multiplier, 2), trim = TRUE, scientific = FALSE),
        format(round(.data$pred_scale_multiplier, 2), trim = TRUE, scientific = FALSE),
        format(round(.data$dropout_add, 2), trim = TRUE, scientific = FALSE)
      )
    ) %>%
    dplyr::relocate("scenario_id")
  scenarios
}

exdyn_stress_theta_table <- function(theta_star, screen_cfg, n_draws, cell_km = 10, seed = 1234L) {
  n_draws <- max(0L, as.integer(n_draws %||% 0L))
  lhs <- if (n_draws > 0L) {
    exdyn_param_lhs(screen_cfg, n = n_draws, cell_km = cell_km, seed = seed)
  } else {
    tibble::tibble()
  }
  truth_row <- tibble::tibble(
    draw = 0L,
    alpha = theta_star$alpha,
    disp_mean_km = theta_star$disp_mean_km,
    disp_mean_cells = theta_star$disp_mean_km / cell_km,
    A_over_K = theta_star$A_over_K,
    pred_c = theta_star$pred_c,
    pred_h = theta_star$pred_h,
    ramp_years = theta_star$ramp_years,
    pred_scale = theta_star$pred_scale,
    gamma = theta_star$gamma,
    rmax = theta_star$rmax,
    K0 = screen_cfg$K0
  )
  delta_lookup <- theta_star$delta_region %||% list()
  if (length(delta_lookup)) {
    for (nm in names(delta_lookup)) {
      truth_row[[paste0("delta_", nm)]] <- delta_lookup[[nm]]
    }
  }
  dplyr::bind_rows(truth_row, lhs)
}

exdyn_stress_gate_summary <- function(gate_tbl) {
  if (!nrow(gate_tbl)) {
    return(list(
      per_gate = tibble::tibble(),
      per_scenario = tibble::tibble()
    ))
  }
  per_gate <- gate_tbl %>%
    dplyr::group_by(.data$scenario_id, .data$arrival_source, .data$obs_multiplier, .data$pred_scale_multiplier, .data$gate) %>%
    dplyr::summarise(
      pass_rate = mean(.data$pass, na.rm = TRUE),
      n = dplyr::n(),
      .groups = "drop"
    )
  per_scenario <- gate_tbl %>%
    dplyr::group_by(.data$scenario_id, .data$replicate, .data$arrival_source, .data$obs_multiplier, .data$pred_scale_multiplier) %>%
    dplyr::summarise(all_gates_pass = all(.data$pass), .groups = "drop") %>%
    dplyr::group_by(.data$scenario_id, .data$arrival_source, .data$obs_multiplier, .data$pred_scale_multiplier) %>%
    dplyr::summarise(
      pass_rate_all_gates = mean(.data$all_gates_pass, na.rm = TRUE),
      n_reps = dplyr::n(),
      .groups = "drop"
    )
  list(per_gate = per_gate, per_scenario = per_scenario)
}

exdyn_stress_plot <- function(pass_scenario_tbl, out_path) {
  needed_cols <- c("arrival_source", "obs_multiplier", "pred_scale_multiplier", "pass_rate_all_gates")
  if (!nrow(pass_scenario_tbl) || !all(needed_cols %in% names(pass_scenario_tbl))) {
    p <- ggplot2::ggplot() +
      ggplot2::theme_void() +
      ggplot2::labs(title = "Synthetic stress sweep: no gate data available")
    ggplot2::ggsave(out_path, p, width = 9, height = 5.5, dpi = 150)
    return(out_path)
  }
  p <- ggplot2::ggplot(
    pass_scenario_tbl,
    ggplot2::aes(
      x = factor(.data$obs_multiplier),
      y = factor(.data$pred_scale_multiplier),
      fill = .data$pass_rate_all_gates
    )
  ) +
    ggplot2::geom_tile(color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", .data$pass_rate_all_gates)), size = 3) +
    ggplot2::scale_fill_viridis_c(
      option = "C",
      limits = c(0, 1),
      na.value = "grey85",
      name = "All-gate\npass rate"
    ) +
    ggplot2::facet_wrap(~arrival_source) +
    ggplot2::labs(
      title = "Synthetic identifiability failure regimes",
      subtitle = "Pass rate across G1–G5 by scenario",
      x = "Observation multiplier (po_rate)",
      y = "Predation scale multiplier"
    ) +
    ggplot2::theme_minimal()
  ggplot2::ggsave(out_path, p, width = 9, height = 5.5, dpi = 150)
  out_path
}

exdyn_synthetic_stress_sweep <- function(cfg,
                                         arrivals_real,
                                         grid_info,
                                         years_vec,
                                         theta_star,
                                         noise_cfg,
                                         tx_cfg,
                                         screen_cfg,
                                         compat_cfg,
                                         abc_cfg,
                                         coverage_breaks,
                                         mask,
                                         output_root) {
  stress_cfg <- exdyn_stress_cfg_resolve(cfg)
  if (!isTRUE(stress_cfg$enabled)) {
    return(list(
      scenarios = tibble::tibble(),
      gate_table = tibble::tibble(),
      gate_pass = tibble::tibble(),
      scenario_pass = tibble::tibble(),
      metrics = tibble::tibble(),
      outputs = character()
    ))
  }
  mode <- match.arg(stress_cfg$mode, c("ideal", "realistic"))
  reps <- max(1L, stress_cfg$reps)
  n_cores <- max(1L, stress_cfg$n_cores)
  scenarios <- exdyn_stress_scenario_grid(stress_cfg)
  cell_km <- grid_info$cell_km %||% 10

  tasks <- tidyr::expand_grid(
    scenario_row = seq_len(nrow(scenarios)),
    replicate = seq_len(reps)
  ) %>%
    dplyr::mutate(
      task_seed = stress_cfg$seed + .data$scenario_row * 1000L + .data$replicate
    )

  screen_use <- utils::modifyList(screen_cfg, stress_cfg$screen %||% list())
  abc_use <- utils::modifyList(abc_cfg, stress_cfg$abc %||% list())
  compat_use <- utils::modifyList(compat_cfg, stress_cfg$compat %||% list())

  run_task <- function(task_row) {
    i <- task_row$scenario_row
    replicate_id <- task_row$replicate
    seed <- task_row$task_seed
    sc <- scenarios[i, , drop = FALSE]
    set.seed(seed)
    arrivals_tbl <- exdyn_synthetic_arrival_table(
      arrivals = arrivals_real,
      grid_info = grid_info,
      years = years_vec,
      source = sc$arrival_source[[1]],
      seed = seed + 17L
    )
    theta_local <- theta_star
    theta_local$pred_scale <- theta_star$pred_scale * sc$pred_scale_multiplier[[1]]
    noise_local <- noise_cfg
    base_po <- noise_cfg$po_rate %||% 0.01
    base_dropout <- noise_cfg$random_tx_dropout %||% 0
    noise_local$po_rate <- max(1e-6, base_po * sc$obs_multiplier[[1]])
    noise_local$random_tx_dropout <- min(0.95, max(0, base_dropout + sc$dropout_add[[1]]))

    truth <- exdyn_make_synthetic(
      theta_star = theta_local,
      noise_cfg = noise_local,
      arrivals = arrivals_tbl,
      grid_info = grid_info,
      years = range(years_vec),
      tx_cfg = tx_cfg,
      K0 = screen_use$K0,
      mask = mask
    )
    theta_tbl <- exdyn_stress_theta_table(
      theta_star = theta_local,
      screen_cfg = screen_use,
      n_draws = screen_use$n_draws,
      cell_km = cell_km,
      seed = seed + 101L
    )
    run <- exdyn_synthetic_mode_run(
      truth = truth,
      mode = mode,
      grid_info = grid_info,
      years_vec = years_vec,
      mask = mask,
      theta_tbl = theta_tbl,
      screen_cfg = screen_use,
      compat_cfg = compat_use,
      abc_cfg = abc_use,
      coverage_breaks = coverage_breaks,
      keep_best_tx = FALSE,
      enforce_gates = TRUE
    )
    gates <- run$pilot_gates %||% tibble::tibble()
    if (nrow(gates)) {
      gates <- gates %>%
        dplyr::mutate(
          scenario_id = sc$scenario_id[[1]],
          replicate = replicate_id,
          arrival_source = sc$arrival_source[[1]],
          obs_multiplier = sc$obs_multiplier[[1]],
          pred_scale_multiplier = sc$pred_scale_multiplier[[1]],
          dropout_add = sc$dropout_add[[1]]
        )
    }
    run$replicate <- replicate_id
    run$seed <- seed
    metrics <- exdyn_recovery_rep_metrics(list(run)) %>%
      dplyr::mutate(
        scenario_id = sc$scenario_id[[1]],
        arrival_source = sc$arrival_source[[1]],
        obs_multiplier = sc$obs_multiplier[[1]],
        pred_scale_multiplier = sc$pred_scale_multiplier[[1]],
        dropout_add = sc$dropout_add[[1]]
      )
    list(gates = gates, metrics = metrics)
  }

  if (!nrow(tasks)) {
    return(list(
      scenarios = scenarios,
      gate_table = tibble::tibble(),
      gate_pass = tibble::tibble(),
      scenario_pass = tibble::tibble(),
      metrics = tibble::tibble(),
      outputs = character()
    ))
  }

  n_cores <- min(n_cores, nrow(tasks))
  task_rows <- split(tasks, seq_len(nrow(tasks)))
  results <- if (n_cores > 1L && .Platform$OS.type != "windows") {
    parallel::mclapply(task_rows, run_task, mc.cores = n_cores, mc.set.seed = FALSE)
  } else {
    lapply(task_rows, run_task)
  }

  gate_table <- dplyr::bind_rows(purrr::map(results, "gates"))
  metrics <- dplyr::bind_rows(purrr::map(results, "metrics"))
  gate_summ <- exdyn_stress_gate_summary(gate_table)

  stress_dir <- file.path(output_root, "stress")
  dir.create(stress_dir, recursive = TRUE, showWarnings = FALSE)
  scenario_path <- file.path(stress_dir, "scenario_table.csv")
  gates_path <- file.path(stress_dir, "gate_pass_rates.csv")
  scenario_pass_path <- file.path(stress_dir, "scenario_pass_rates.csv")
  gate_table_path <- file.path(stress_dir, "gate_table.csv")
  metrics_path <- file.path(stress_dir, "replicate_metrics.csv")
  plot_path <- file.path(stress_dir, "failure_regimes_heatmap.png")

  readr::write_csv(scenarios, scenario_path)
  readr::write_csv(gate_summ$per_gate, gates_path)
  readr::write_csv(gate_summ$per_scenario, scenario_pass_path)
  readr::write_csv(gate_table, gate_table_path)
  readr::write_csv(metrics, metrics_path)
  exdyn_stress_plot(gate_summ$per_scenario, plot_path)

  list(
    scenarios = scenarios,
    gate_table = gate_table,
    gate_pass = gate_summ$per_gate,
    scenario_pass = gate_summ$per_scenario,
    metrics = metrics,
    outputs = c(scenario_path, gates_path, scenario_pass_path, gate_table_path, metrics_path, plot_path)
  )
}
