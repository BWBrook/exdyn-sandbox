# Graph-mode parallel runner (screen + ABC) for GB pilot grid

#' Run graph-mode screen/ABC in parallel (GB pilot grid)
#' @keywords internal
exdyn_perf_graph_parallel_run <- function(workers = 8L,
                                          n_draws = 64L,
                                          n_sims = 200L,
                                          mode = c("full", "screen", "abc"),
                                          seed = 1045L,
                                          out_dir = NULL,
                                          graph_radius = 5L,
                                          graph_include_self = TRUE) {
  if (!requireNamespace("future.apply", quietly = TRUE)) {
    stop("future.apply is required for parallel graph runner")
  }
  mode <- match.arg(mode)
  workers <- as.integer(workers)
  if (!is.finite(workers) || workers < 1) workers <- 1L
  workers <- min(workers, parallel::detectCores())
  options(future.globals.maxSize = Inf)
  if (identical(.Platform$OS.type, "windows")) {
    future::plan(future::multisession, workers = workers)
  } else {
    future::plan(future::multicore, workers = workers)
  }
  set.seed(seed)

  sim_cfg <- list(
    K0 = 120, rmax = 0.4, A_over_K = 0.1, alpha = 0.2, disp_mean_km = 10,
    pred_c = 1.2, pred_h = 30, pred_scale = 2.0, gamma = 1.0,
    ramp_years = 8, pred_type = "II", pre_leak = 0,
    truth_frac = 0.08, truth_rel0 = 1.0, conv_reuse = TRUE
  )

  obs_counts <- list(po_rate = 0.02, effort_strength = 1.0,
                     missing_years_prob = 0, random_tx_dropout = 0,
                     obs_mode = "counts")

  tx_cfg <- list(
    smooth_window = 5,
    min_years_active = 3,
    baseline_window = 5,
    drop_fraction = 0.2,
    hold_years = 3,
    normalize_by = NULL
  )

  compat_cfg <- list(min_r2_arrival = 0.1, lag_range = c(0, 30), min_coverage = 0.05)

  screen_cfg <- list(
    n_draws = as.integer(n_draws),
    seed = seed,
    K0 = sim_cfg$K0,
    alpha = c(0.05, 0.45),
    disp_mean_km = c(6, 22),
    A_over_K = c(0.02, 0.15),
    pred_c = c(0.8, 3.2),
    pred_h = c(20, 60),
    ramp_years = c(5, 12),
    pred_scale = c(0.8, 4.0),
    gamma = c(1.0, 2.0),
    rmax = c(0.3, 0.6),
    crop = FALSE,
    dispersal_mode = "graph"
  )

  abc_cfg <- list(
    n_sims = as.integer(n_sims),
    eps = 12.3,
    lhs = list(n = 0),
    prior = list(
      alpha = screen_cfg$alpha,
      disp_mean_km = screen_cfg$disp_mean_km,
      A_over_K = screen_cfg$A_over_K,
      pred_c = screen_cfg$pred_c,
      pred_h = screen_cfg$pred_h,
      ramp_years = screen_cfg$ramp_years,
      pred_scale = screen_cfg$pred_scale,
      gamma = screen_cfg$gamma,
      rmax = screen_cfg$rmax
    )
  )

  theta_star <- list(pred_type = "II", pre_leak = 0)

  pilot_grid <- targets::tar_read(pilot_grid_riparian)
  pilot_grid_info <- targets::tar_read(pilot_grid_info)
  pilot_arrivals <- targets::tar_read(pilot_mink_arrivals)
  pilot_years <- targets::tar_read(pilot_years)

  years_vec <- pilot_years
  grid_label <- sprintf("%dx%d", pilot_grid_info$nx, pilot_grid_info$ny)

  lookup <- pilot_grid_info$lookup
  land_mask <- matrix(FALSE, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
  land_mask[cbind(lookup$row_idx, lookup$col_idx)] <- TRUE

  river_km <- pilot_grid$river_km
  if (is.null(river_km)) {
    river_km <- ifelse(pilot_grid$riparian %||% FALSE, 1, 0)
  }
  river_km[is.na(river_km)] <- 0
  if (max(river_km, na.rm = TRUE) > min(river_km, na.rm = TRUE)) {
    river_scaled <- (river_km - min(river_km, na.rm = TRUE)) /
      (max(river_km, na.rm = TRUE) - min(river_km, na.rm = TRUE))
  } else {
    river_scaled <- rep(0, length(river_km))
  }
  river_scaled <- 0.2 + 0.8 * river_scaled
  suitability_full <- matrix(1, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
  idx_full <- cbind(lookup$row_idx, lookup$col_idx)
  suitability_full[idx_full] <- river_scaled[match(lookup$cell_id, pilot_grid$cell_id)]

  graph_plan <- exdyn_land_graph_plan(
    pilot_grid_info,
    mask = land_mask,
    radius = graph_radius,
    include_self = graph_include_self
  )
  screen_cfg$graph <- graph_plan
  screen_cfg$scale_matrix <- suitability_full

  arrivals <- exdyn_prepare_arrivals(pilot_arrivals)
  T_P <- exdyn_arrival_matrix(arrivals, pilot_grid_info, years_vec)
  T_P[!land_mask] <- NA_real_

  disp_mean_cells <- sim_cfg$disp_mean_km / (pilot_grid_info$cell_km %||% 10)
  pars <- list(rmax = sim_cfg$rmax, A_frac = sim_cfg$A_over_K * sim_cfg$K0, beta_H = 0, d = 0.02)
  pred <- list(
    type = sim_cfg$pred_type,
    c = sim_cfg$pred_c,
    h = sim_cfg$pred_h,
    scale = sim_cfg$pred_scale,
    gamma = sim_cfg$gamma,
    scale_matrix = suitability_full
  )

  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  out_dir <- out_dir %||% file.path("outputs", "perf", "ladder", "gb_land_graph", "parallel", timestamp)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  meta <- tibble::tibble(
    timestamp = timestamp,
    workers = workers,
    n_draws = n_draws,
    n_sims = n_sims,
    grid = grid_label,
    land_cells = sum(land_mask, na.rm = TRUE),
    graph_nodes = graph_plan$n
  )
  readr::write_csv(meta, file.path(out_dir, "parallel_meta.csv"))

  screen_parallel <- function(theta_tbl, coverage_breaks, tx_map) {
    chunks <- split(seq_len(nrow(theta_tbl)), rep(seq_len(workers), length.out = nrow(theta_tbl)))
    res_list <- future.apply::future_lapply(chunks, function(idx) {
      if (!length(idx)) return(tibble::tibble())
      exdyn_synthetic_screen_run(
        theta_tbl = theta_tbl[idx, , drop = FALSE],
        grid_info = pilot_grid_info,
        years_vec = years_vec,
        T_P = T_P,
        TX_obs = tx_map$matrix,
        screen_cfg = screen_cfg,
        compat_cfg = compat_cfg,
        coverage_breaks = coverage_breaks,
        mask = land_mask,
        theta_star = theta_star,
        keep_best_tx = FALSE
      )$results
    }, future.seed = TRUE)
    dplyr::bind_rows(res_list)
  }

  abc_parallel <- function(summary_obs, coverage_breaks) {
    scale_vec <- pmax(abs(summary_obs), 1e-6)
    names_obs <- names(summary_obs)
    prior_cfg <- abc_cfg$prior %||% list()
    delta_bounds <- prior_cfg$delta_region %||% screen_cfg$delta_region
    scalar_bounds <- prior_cfg[setdiff(names(prior_cfg), "delta_region")]
    prior_sampler <- exdyn_prior_sampler_syn(scalar_bounds, delta_bounds)

    simulate_once <- function(theta) {
      delta_lookup <- theta$delta_region %||% list()
      T_P_adj <- exdyn_adjust_arrival_matrix(T_P, pilot_grid_info, delta_lookup, years_vec)
      if (any(!land_mask)) T_P_adj[!land_mask] <- NA_real_
      TX_idx <- exdyn_simulate_tx_only(
        grid_info = pilot_grid_info,
        years = years_vec,
        T_P = T_P_adj,
        ramp_years = round(theta$ramp_years),
        pars = list(rmax = theta$rmax, A_frac = theta$A_over_K * screen_cfg$K0, beta_H = 0, d = 0.02),
        K0 = screen_cfg$K0,
        alpha = theta$alpha,
        disp_mean_cells = theta$disp_mean_km / (pilot_grid_info$cell_km %||% 10),
        pred = list(
          type = theta_star$pred_type %||% "II",
          c = theta$pred_c,
          h = theta$pred_h,
          scale = theta$pred_scale,
          gamma = theta$gamma,
          scale_matrix = suitability_full
        ),
        pre_leak = theta_star$pre_leak %||% 0,
        mask = land_mask,
        dispersal_mode = "graph",
        graph = graph_plan
      )
      TX_years <- matrix(NA_real_, nrow = pilot_grid_info$nx, ncol = pilot_grid_info$ny)
      idx <- is.finite(TX_idx)
      if (any(idx)) TX_years[idx] <- years_vec[TX_idx[idx]]
      TX_years[!land_mask] <- NA_real_
      S_sim <- exdyn_summary_tx_response(
        TX_years,
        T_P_adj,
        years = years_vec,
        coverage_breaks = coverage_breaks,
        mask = land_mask
      )
      S_sim <- S_sim[names_obs]
      valid <- is.finite(S_sim) & is.finite(summary_obs) & is.finite(scale_vec)
      dist <- if (any(valid)) sqrt(sum(((S_sim[valid] - summary_obs[valid]) / scale_vec[valid])^2)) else Inf
      list(theta = theta, summary = S_sim, distance = dist, accepted = is.finite(dist) && dist <= abc_cfg$eps)
    }

    res <- future.apply::future_lapply(seq_len(n_sims), function(i) {
      theta <- prior_sampler()
      simulate_once(theta)
    }, future.seed = TRUE)

    accepted_idx <- which(vapply(res, function(x) isTRUE(x$accepted), logical(1)))
    samples <- if (length(accepted_idx)) {
      theta_flat <- purrr::map(res[accepted_idx], function(x) x$theta)
      theta_flat <- purrr::map(theta_flat, function(theta) {
        if (!is.null(theta$delta_region)) {
          delta <- theta$delta_region
          theta$delta_region <- NULL
          for (nm in names(delta)) theta[[paste0("delta_", nm)]] <- delta[[nm]]
        }
        theta
      })
      dplyr::bind_rows(purrr::map(theta_flat, tibble::as_tibble_row))
    } else {
      tibble::tibble()
    }
    summaries <- if (length(accepted_idx)) {
      dplyr::bind_rows(purrr::map(res[accepted_idx], ~ tibble::as_tibble_row(.x$summary)))
    } else {
      tibble::tibble()
    }
    list(samples = samples, summaries = summaries, distances = vapply(res, function(x) x$distance, numeric(1)))
  }

  counts_out <- exdyn_simulate_counts_stream(
    grid_info = pilot_grid_info,
    years = years_vec,
    T_P = T_P,
    ramp_years = sim_cfg$ramp_years,
    pars = pars,
    K0 = sim_cfg$K0,
    alpha = sim_cfg$alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    rate = obs_counts$po_rate,
    effort_strength = obs_counts$effort_strength,
    pre_leak = sim_cfg$pre_leak,
    mask = land_mask,
    conv_reuse = sim_cfg$conv_reuse,
    dispersal_mode = "graph",
    graph = graph_plan
  )

  tx_map <- exdyn_tx_map_counts(
    counts_mat = counts_out$counts_mat,
    years = range(years_vec),
    cfg = tx_cfg,
    grid_info = pilot_grid_info,
    effort_mat = counts_out$effort_mat,
    mask = land_mask,
    cells_dt = counts_out$cells,
    return_counts = FALSE
  )

  coverage_breaks <- exdyn_coverage_breaks(years_vec)
  summary_obs <- exdyn_summary_tx_response(tx_map$matrix, T_P, years = years_vec,
                                           coverage_breaks = coverage_breaks, mask = land_mask)

  if (mode %in% c("screen", "full")) {
    theta_tbl <- exdyn_param_lhs(screen_cfg, n = screen_cfg$n_draws,
                                 cell_km = pilot_grid_info$cell_km %||% 10,
                                 seed = screen_cfg$seed)
    t0 <- proc.time()[["elapsed"]]
    screen_res <- screen_parallel(theta_tbl, coverage_breaks, tx_map)
    elapsed <- proc.time()[["elapsed"]] - t0
    readr::write_csv(screen_res, file.path(out_dir, "screen_parallel_results.csv"))
    readr::write_csv(tibble::tibble(stage = "screen", elapsed_sec = elapsed), file.path(out_dir, "screen_parallel_timing.csv"))
  }

  if (mode %in% c("abc", "full")) {
    t0 <- proc.time()[["elapsed"]]
    abc_res <- abc_parallel(summary_obs, coverage_breaks)
    elapsed <- proc.time()[["elapsed"]] - t0
    readr::write_csv(abc_res$samples, file.path(out_dir, "abc_parallel_samples.csv"))
    readr::write_csv(abc_res$summaries, file.path(out_dir, "abc_parallel_summaries.csv"))
    readr::write_csv(tibble::tibble(stage = "abc", elapsed_sec = elapsed, n_accept = nrow(abc_res$samples)),
                     file.path(out_dir, "abc_parallel_timing.csv"))
  }

  readr::write_csv(tibble::as_tibble_row(summary_obs), file.path(out_dir, "summary_obs.csv"))
  list(out_dir = out_dir, meta = meta)
}
