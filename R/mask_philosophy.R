# Masking philosophy comparison utilities (internal)

exdyn_land_mask_from_lookup <- function(grid_info) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  mask <- matrix(FALSE, nrow = nx, ncol = ny)
  lookup <- grid_info$lookup %||% tibble::tibble()
  if (nrow(lookup)) {
    idx <- cbind(lookup$row_idx, lookup$col_idx)
    mask[idx] <- TRUE
  }
  mask
}

exdyn_summary_get <- function(summary, name) {
  if (is.null(summary) || is.null(names(summary)) || !name %in% names(summary)) {
    return(NA_real_)
  }
  summary[[name]]
}

exdyn_soft_suitability_matrix <- function(grid_info,
                                          method = "river_km",
                                          range = c(0.5, 1.5),
                                          transform = "log1p") {
  lookup <- grid_info$lookup %||% tibble::tibble()
  nx <- grid_info$nx
  ny <- grid_info$ny
  scale_mat <- matrix(1, nrow = nx, ncol = ny)
  if (!nrow(lookup)) {
    return(list(matrix = scale_mat, stats = list(min = 1, max = 1, mean = 1)))
  }
  if (identical(method, "river_km") && "river_km" %in% names(lookup)) {
    vals <- lookup$river_km
  } else if ("riparian" %in% names(lookup)) {
    vals <- as.numeric(lookup$riparian)
  } else {
    vals <- rep(1, nrow(lookup))
  }
  vals <- pmax(vals, 0)
  max_val <- max(vals, na.rm = TRUE)
  if (!is.finite(max_val) || max_val <= 0) {
    return(list(matrix = scale_mat, stats = list(min = 1, max = 1, mean = 1)))
  }
  scaled <- vals / max_val
  if (identical(transform, "log1p")) {
    scaled <- log1p(vals) / log1p(max_val)
  }
  min_scale <- range[1]
  max_scale <- range[2]
  scaled <- min_scale + (max_scale - min_scale) * scaled
  idx <- cbind(lookup$row_idx, lookup$col_idx)
  scale_mat[idx] <- scaled
  list(
    matrix = scale_mat,
    stats = list(
      min = min(scaled, na.rm = TRUE),
      max = max(scaled, na.rm = TRUE),
      mean = mean(scaled, na.rm = TRUE)
    )
  )
}

exdyn_mask_philosophy_compare <- function(arrivals_real,
                                          grid_info,
                                          years_vec,
                                          mask_hard,
                                          theta_star,
                                          noise_cfg,
                                          tx_cfg,
                                          coverage_breaks,
                                          cfg,
                                          output_root = NULL) {
  cfg <- cfg %||% list()
  if (!isTRUE(cfg$enabled)) {
    return(list(table = tibble::tibble(), outputs = character()))
  }
  arrival_source <- cfg$arrival_source %||% "real"
  reps <- cfg$reps %||% 3L
  seed_base <- cfg$seed %||% 2027L
  scenarios <- cfg$scenarios %||% c("hard", "soft")
  soft_cfg <- cfg$soft %||% list()
  dispersal_mode <- tolower(cfg$dispersal_mode %||% "fft")
  graph_cfg <- cfg$graph %||% list()

  arrivals_tbl <- exdyn_synthetic_arrival_table(
    arrivals = arrivals_real,
    grid_info = grid_info,
    years = years_vec,
    source = arrival_source,
    seed = seed_base
  )
  T_P <- exdyn_arrival_matrix(
    arrivals = arrivals_tbl,
    grid_info = grid_info,
    years = years_vec,
    delta_region = NULL
  )

  land_mask <- exdyn_land_mask_from_lookup(grid_info)
  outputs <- character()
  rows <- list()

  for (scenario in scenarios) {
    scenario <- tolower(scenario)
    if (identical(scenario, "soft")) {
      mask_use <- land_mask
      scale_info <- exdyn_soft_suitability_matrix(
        grid_info = grid_info,
        method = soft_cfg$method %||% "river_km",
        range = soft_cfg$range %||% c(0.5, 1.5),
        transform = soft_cfg$transform %||% "log1p"
      )
      scale_matrix <- scale_info$matrix
      scale_stats <- scale_info$stats
    } else {
      mask_use <- mask_hard
      scale_matrix <- NULL
      scale_stats <- list(min = NA_real_, max = NA_real_, mean = NA_real_)
    }

    graph_plan <- NULL
    if (identical(dispersal_mode, "graph")) {
      graph_plan <- exdyn_land_graph_plan(
        grid_info = grid_info,
        mask = mask_use,
        radius = graph_cfg$radius %||% 5L,
        include_self = graph_cfg$include_self %||% TRUE
      )
    }
    n_nodes <- graph_plan$n %||% sum(mask_use, na.rm = TRUE)
    n_edges <- if (!is.null(graph_plan$edges$i)) length(graph_plan$edges$i) else NA_integer_
    mean_degree <- if (is.finite(n_edges) && n_nodes > 0) n_edges / n_nodes else NA_real_

    noise_use <- noise_cfg
    noise_use$scale_matrix <- scale_matrix
    if (identical(dispersal_mode, "graph")) {
      noise_use$dispersal_mode <- "graph"
      noise_use$graph <- graph_plan
    }

    for (replicate_id in seq_len(reps)) {
      seed <- seed_base + replicate_id
      set.seed(seed)
      truth <- exdyn_make_synthetic(
        theta_star = theta_star,
        noise_cfg = noise_use,
        arrivals = arrivals_tbl,
        grid_info = grid_info,
        years = years_vec,
        tx_cfg = tx_cfg,
        K0 = cfg$K0 %||% 120,
        mask = mask_use
      )
      summary_obs <- exdyn_summary_tx_response(
        truth$TX_true,
        truth$T_P,
        years = years_vec,
        coverage_breaks = coverage_breaks,
        mask = mask_use
      )
      counts <- exdyn_summary_counts(truth$TX_true, truth$T_P, mask = mask_use)
      n_pairs <- counts[["n_pairs"]] %||% NA_real_
      n_TP_finite <- counts[["n_TP_finite"]] %||% NA_real_
      coverage_true <- if (is.finite(n_TP_finite) && n_TP_finite > 0) n_pairs / n_TP_finite else NA_real_
      lag_mean <- exdyn_summary_get(summary_obs, "lag_mean")
      lag_sd <- exdyn_summary_get(summary_obs, "lag_sd")
      r2_arrival <- exdyn_summary_get(summary_obs, "r2_arrival")
      grad_mag <- exdyn_summary_get(summary_obs, "grad_mag")
      orient_R <- exdyn_summary_get(summary_obs, "orient_R")
      speed_cells <- exdyn_summary_get(summary_obs, "speed_cells_per_year")
      speed_r2 <- exdyn_summary_get(summary_obs, "speed_r2")
      tx_sd <- exdyn_summary_get(summary_obs, "tx_sd")
      tx_range <- exdyn_summary_get(summary_obs, "tx_range")
      rows[[length(rows) + 1L]] <- tibble::tibble(
        mask_type = scenario,
        arrival_source = arrival_source,
        replicate = replicate_id,
        n_nodes = n_nodes,
        n_edges = n_edges,
        mean_degree = mean_degree,
        n_mask = counts[["n_mask"]] %||% NA_real_,
        n_TP_finite = n_TP_finite,
        frac_finite_TP_in_mask = if (is.finite(n_TP_finite) && counts[["n_mask"]] %||% 0 > 0) n_TP_finite / counts[["n_mask"]] else NA_real_,
        n_TX_true = counts[["n_TX_finite"]] %||% NA_real_,
        coverage_true = coverage_true,
        lag_mean = lag_mean,
        lag_sd = lag_sd,
        r2_arrival = r2_arrival,
        grad_mag = grad_mag,
        orient_R = orient_R,
        speed_cells_per_year = speed_cells,
        speed_r2 = speed_r2,
        tx_sd = tx_sd,
        tx_range = tx_range,
        summary_finite_rate = exdyn_arrival_realism_summary_rate(summary_obs),
        scale_min = scale_stats$min,
        scale_max = scale_stats$max,
        scale_mean = scale_stats$mean
      )
    }

    if (!is.null(output_root)) {
      plot_path <- file.path(output_root, sprintf("TX_true_%s_mask.png", scenario))
      plot_title <- sprintf("TX_true (%s mask)", scenario)
      p <- exdyn_plot_surface(truth$TX_true, grid_info, plot_title, fill_label = "Extirpation year")
      ggplot2::ggsave(plot_path, p, width = 6, height = 7, dpi = 150)
      outputs <- c(outputs, plot_path)

      if (identical(scenario, "hard")) {
        mask_path <- file.path(output_root, "mask_cells_hard.png")
        mask_mat <- matrix(NA_real_, nrow = nrow(mask_use), ncol = ncol(mask_use))
        mask_mat[mask_use] <- 1
        p_mask <- exdyn_plot_surface(mask_mat, grid_info, "Hard mask cells", fill_label = "Mask")
        ggplot2::ggsave(mask_path, p_mask, width = 6, height = 7, dpi = 150)
        outputs <- c(outputs, mask_path)
      }

      if (identical(scenario, "soft") && !is.null(scale_matrix)) {
        scale_path <- file.path(output_root, "suitability_scale_soft.png")
        p_scale <- exdyn_plot_surface(scale_matrix, grid_info, "Soft suitability scale", fill_label = "Suitability scale")
        ggplot2::ggsave(scale_path, p_scale, width = 6, height = 7, dpi = 150)
        outputs <- c(outputs, scale_path)

        arrival_path <- file.path(output_root, "arrival_plane_mask_philosophy.png")
        p_arrival <- exdyn_plot_surface(truth$T_P, grid_info, "Arrival surface (mask gate)", fill_label = "Arrival year")
        ggplot2::ggsave(arrival_path, p_arrival, width = 6, height = 7, dpi = 150)
        outputs <- c(outputs, arrival_path)
      }
    }
  }

  tbl <- dplyr::bind_rows(rows)
  if (!is.null(output_root)) {
    csv_path <- file.path(output_root, "mask_philosophy_compare.csv")
    readr::write_csv(tbl, csv_path)
    outputs <- c(outputs, csv_path)
  }
  list(table = tbl, outputs = outputs)
}
