#' Latin hypercube draw for continuous parameters
#' @export
exdyn_lhs_draw <- function(defaults) {
  if (is.null(defaults$allee) || is.null(defaults$allee$A_over_K)) {
    defaults$allee <- list(A_over_K = 0.1)
  }
  ranges <- list(
    dispersal_mean_km = defaults$dispersal$mean_km,
    pred_c = defaults$predation$c,
    pred_h = defaults$predation$h,
    pred_speed = defaults$predation$speed_cells_per_year,
    habitat_beta = defaults$habitat$beta,
    habitat_ramp_start = defaults$habitat$ramp_start,
    habitat_ramp_end = defaults$habitat$ramp_end,
    climate_drift = defaults$climate$drift_per_century,
    effort_strength = defaults$obs$effort_strength,
    allee_A_over_K = defaults$allee$A_over_K
  )
  vars <- length(ranges)
  sample <- lhs::randomLHS(1, vars)
  draw <- vector("list", vars)
  names(draw) <- names(ranges)
  for (i in seq_len(vars)) {
    rng <- ranges[[i]]
    if (length(rng) == 1) {
      draw[[i]] <- rng[1]
    } else {
      lo <- min(rng)
      hi <- max(rng)
      draw[[i]] <- lo + sample[1, i] * (hi - lo)
    }
  }
  draw$habitat_ramp_start <- round(draw$habitat_ramp_start)
  draw$habitat_ramp_end <- round(draw$habitat_ramp_end)
  if (draw$habitat_ramp_end <= draw$habitat_ramp_start) {
    draw$habitat_ramp_end <- draw$habitat_ramp_start + 1
  }
  if (!is.null(defaults$allee$A_over_K)) {
    draw$allee_A_over_K <- max(min(draw$allee_A_over_K, 0.99), 0)
  } else {
    draw$allee_A_over_K <- NA_real_
  }
  draw
}

#' Generate experiment grid with parameter draws
#' @export
exdyn_experiment_grid <- function(path = "config/experiments.yaml") {
  if (!file.exists(path)) {
    candidates <- file.path(c("..", file.path("..", "..")), path)
    hit <- candidates[file.exists(candidates)][1]
    if (!is.na(hit)) {
      path <- hit
    }
  }
  cfg <- yaml::read_yaml(path)
  base_grid <- expand.grid(
    species = cfg$grid$species,
    scenario = cfg$grid$scenario,
    predation_type = cfg$grid$predation_type,
    replicate = seq_len(cfg$replicates),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  base_grid <- tibble::as_tibble(base_grid)
  set.seed(cfg$seed)
  draws <- replicate(nrow(base_grid), exdyn_lhs_draw(cfg$defaults), simplify = FALSE)
  exp_id <- stringr::str_c(
    base_grid$species, base_grid$scenario,
    base_grid$predation_type, base_grid$replicate,
    seq_len(nrow(base_grid)),
    sep = "_"
  )
  defaults <- cfg$defaults
  if (is.null(defaults$allee) || is.null(defaults$allee$A_over_K)) {
    defaults$allee <- list(A_over_K = 0.1)
  }
  base_grid$params <- draws
  base_grid$exp_id <- exp_id
  base_grid$seed <- cfg$seed + seq_len(nrow(base_grid))
  base_grid$nx <- defaults$nx
  base_grid$ny <- defaults$ny
  base_grid$years <- defaults$years
  base_grid$cell_k <- defaults$cell_k
  base_grid$cellsize_km <- defaults$cellsize_km
  base_grid$alpha <- defaults$dispersal$alpha
  base_grid$presence_rate <- defaults$obs$presence_only_rate
  base_grid$fossil_sites <- defaults$obs$fossil_sites
  base_grid$fossil_sd <- defaults$obs$fossil_date_sd_y
  base_grid$pred_seeds <- rep(list(defaults$predation$seeds), nrow(base_grid))
  base_grid
}

#' Field constructor wrapper for experiments
#' @export
exdyn_make_fields_param <- function(nx, ny, years, pars, scenario, seeds) {
  exdyn_make_fields(
    nx = nx,
    ny = ny,
    years = years,
    scenario = scenario,
    habitat_beta = pars$habitat_beta,
    ramp_start = pars$habitat_ramp_start,
    ramp_end = pars$habitat_ramp_end,
    predation_speed = pars$pred_speed,
    predation_seeds = seeds,
    climate_drift = pars$climate_drift
  )
}

#' Run a single experiment row
#' @export
exdyn_run_core <- function(row, arrival_threshold_frac = 0.02) {
  stopifnot(is.list(row))
  params <- row$params[[1]]
  set.seed(row$seed[[1]])
  arche <- exdyn_archetype(row$species[[1]])
  arche$beta_H <- params$habitat_beta
  if (!is.null(params$allee_A_over_K)) {
    arche$A_frac <- params$allee_A_over_K
  }
  disp_mean_cells <- params$dispersal_mean_km / row$cellsize_km[[1]]
  pred <- list(
    type = row$predation_type[[1]],
    c = params$pred_c,
    h = params$pred_h
  )
  fields <- exdyn_make_fields_param(
    nx = row$nx[[1]],
    ny = row$ny[[1]],
    years = row$years[[1]],
    pars = params,
    scenario = row$scenario[[1]],
    seeds = row$pred_seeds[[1]]
  )
  N <- exdyn_simulate(
    nx = row$nx[[1]],
    ny = row$ny[[1]],
    years = row$years[[1]],
    fields = fields,
    pars = arche,
    K0 = row$cell_k[[1]],
    alpha = row$alpha[[1]],
    disp_mean_cells = disp_mean_cells,
    pred = pred
  )
  po <- exdyn_presence_only(
    N,
    rate = row$presence_rate[[1]],
    effort_strength = params$effort_strength
  )
  foss <- exdyn_fossils(
    N,
    n_sites = row$fossil_sites[[1]],
    date_sd = row$fossil_sd[[1]]
  )
  summs_driver <- exdyn_summaries(N, fields, K0 = row$cell_k[[1]])
  summs_resp <- exdyn_summaries_response_only(N, row$cell_k[[1]], arrival_threshold_frac)
  summs <- dplyr::bind_cols(summs_driver, summs_resp)
  summs <- tibble::add_column(
    summs,
    exp_id = row$exp_id[[1]],
    species = row$species[[1]],
    scenario = row$scenario[[1]],
    predation_type = row$predation_type[[1]],
    replicate = row$replicate[[1]],
    nx = row$nx[[1]],
    ny = row$ny[[1]],
    years = row$years[[1]],
    alpha = row$alpha[[1]],
    presence_rate = row$presence_rate[[1]],
    dispersal_mean_km = params$dispersal_mean_km,
    pred_speed = params$pred_speed,
    pred_c = params$pred_c,
    pred_h = params$pred_h,
    habitat_beta = params$habitat_beta,
    habitat_ramp_start = params$habitat_ramp_start,
    habitat_ramp_end = params$habitat_ramp_end,
    effort_strength = params$effort_strength,
    allee_A_over_K = params$allee_A_over_K,
    climate_drift = params$climate_drift,
    cell_k = row$cell_k[[1]],
    cellsize_km = row$cellsize_km[[1]],
    po_n = nrow(po),
    foss_n = nrow(foss),
    .before = 1
  )
  list(
    summary = summs,
    summary_response = summs_resp,
    fields = fields,
    N = N,
    T_X = exdyn_extirpation_time(N, row$cell_k[[1]], frac = arrival_threshold_frac),
    po = po,
    foss = foss
  )
}

#' Run a single experiment row (summary only)
#' @export
exdyn_run_once <- function(row) {
  exdyn_run_core(row)$summary
}

#' Construct the small power-analysis grid
#' @export
exdyn_power_grid <- function(path = "config/experiments.yaml") {
  cfg <- yaml::read_yaml(path)
  defaults <- cfg$defaults
  combos <- tidyr::expand_grid(
    presence_rate = c(0.0008, 0.0025),
    alpha = c(0, 0.2, 0.4),
    scenario = c("predation_front", "habitat_erosion")
  ) %>% tibble::as_tibble()
  midpoint <- function(x) {
    if (is.list(x)) x <- unlist(x)
    if (length(x) == 2) mean(x) else x
  }
  param_template <- list(
    dispersal_mean_km = midpoint(defaults$dispersal$mean_km),
    pred_c = midpoint(defaults$predation$c),
    pred_h = midpoint(defaults$predation$h),
    pred_speed = midpoint(defaults$predation$speed_cells_per_year),
    habitat_beta = midpoint(defaults$habitat$beta),
    habitat_ramp_start = round(midpoint(defaults$habitat$ramp_start)),
    habitat_ramp_end = round(midpoint(defaults$habitat$ramp_end)),
    climate_drift = midpoint(defaults$climate$drift_per_century),
    effort_strength = midpoint(defaults$obs$effort_strength),
    allee_A_over_K = midpoint(defaults$allee$A_over_K)
  )
  if (param_template$habitat_ramp_end <= param_template$habitat_ramp_start) {
    param_template$habitat_ramp_end <- param_template$habitat_ramp_start + 1
  }
  params_list <- rep(list(param_template), nrow(combos))
  pred_seeds <- defaults$predation$seeds
  purrr::map_dfr(seq_len(nrow(combos)), function(i) {
    row <- tibble::tibble(
      exp_id = sprintf("power_%s_rate%.4f_alpha%.1f", combos$scenario[i], combos$presence_rate[i], combos$alpha[i]),
      species = "B",
      scenario = combos$scenario[i],
      predation_type = "II",
      replicate = 1L,
      params = list(params_list[[i]]),
      seed = cfg$seed + i * 100L,
      nx = defaults$nx,
      ny = defaults$ny,
      years = defaults$years,
      cell_k = defaults$cell_k,
      cellsize_km = defaults$cellsize_km,
      alpha = combos$alpha[i],
      presence_rate = combos$presence_rate[i],
      fossil_sites = defaults$obs$fossil_sites,
      fossil_sd = defaults$obs$fossil_date_sd_y,
      pred_seeds = list(pred_seeds)
    )
    row
  })
}

#' Construct response-only sensitivity sweep grid
#' @export
exdyn_sweep_grid <- function(path = "config/experiments.yaml") {
  cfg <- yaml::read_yaml(path)
  if (is.null(cfg$sweep)) {
    stop("No sweep configuration found in experiments.yaml")
  }
  sweep <- cfg$sweep
  defaults <- cfg$defaults
  n_draws <- sweep$n_sweep
  if (n_draws <= 0) stop("n_sweep must be positive")

  pred_types <- cfg$grid$predation_type
  if (is.null(pred_types)) pred_types <- "II"
  combos <- expand.grid(
    species = cfg$grid$species,
    scenario = cfg$grid$scenario,
    predation_type = pred_types,
    replicate = seq_len(sweep$replicates),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  combos <- tibble::as_tibble(combos)
  if (!nrow(combos)) stop("Sweep grid combinations are empty")
  combo_idx <- rep(seq_len(nrow(combos)), length.out = n_draws)

  ranges <- list(
    nx = sweep$nx,
    ny = sweep$ny,
    years = sweep$years,
    dispersal_mean_km = sweep$dispersal$mean_km,
    alpha = sweep$dispersal$alpha,
    pred_speed = sweep$predation$speed_cells_per_year,
    pred_c = sweep$predation$c,
    pred_h = sweep$predation$h,
    habitat_beta = sweep$habitat$beta,
    habitat_ramp_start = sweep$habitat$ramp_start,
    habitat_ramp_end = sweep$habitat$ramp_end,
    effort_strength = sweep$obs$effort_strength,
    presence_rate = sweep$obs$presence_only_rate,
    allee_A_over_K = sweep$allee$A_over_K
  )
  vars <- length(ranges)
  samples <- lhs::randomLHS(n_draws, vars)
  draw_values <- vector("list", vars)
  names(draw_values) <- names(ranges)

  rescale_val <- function(rng, u, to_integer = FALSE) {
    if (length(rng) == 1) {
      val <- rng
    } else {
      lo <- min(rng)
      hi <- max(rng)
      val <- lo + u * (hi - lo)
      if (to_integer) {
        val <- round(val)
      }
      val <- max(lo, min(hi, val))
    }
    val
  }

  integer_cols <- c("nx", "ny", "years", "habitat_ramp_start", "habitat_ramp_end")
  for (i in seq_len(vars)) {
    key <- names(ranges)[i]
    to_int <- key %in% integer_cols
    draw_values[[key]] <- vapply(seq_len(n_draws), function(idx) rescale_val(ranges[[key]], samples[idx, i], to_int), numeric(1))
  }

  # ensure ramp end after ramp start
  draw_values$habitat_ramp_end <- pmax(draw_values$habitat_ramp_end, draw_values$habitat_ramp_start + 1)

  midpoint <- function(x) {
    if (is.list(x)) x <- unlist(x)
    if (length(x) == 0) return(0)
    if (length(x) == 1) x else mean(range(x))
  }

  climate_mid <- midpoint(defaults$climate$drift_per_century)
  cell_k <- defaults$cell_k
  cellsize_km <- defaults$cellsize_km
  fossil_sites <- defaults$obs$fossil_sites
  fossil_sd <- defaults$obs$fossil_date_sd_y
  seeds <- defaults$predation$seeds

  tibble::tibble(idx = seq_len(n_draws)) %>%
    dplyr::mutate(
      species = combos$species[combo_idx],
      scenario = combos$scenario[combo_idx],
      predation_type = combos$predation_type[combo_idx],
      replicate = combos$replicate[combo_idx],
      nx = draw_values$nx,
      ny = draw_values$ny,
      years = draw_values$years,
      alpha = draw_values$alpha,
      presence_rate = draw_values$presence_rate,
      params = purrr::pmap(
        list(
          dispersal_mean_km = draw_values$dispersal_mean_km,
          pred_speed = draw_values$pred_speed,
          pred_c = draw_values$pred_c,
          pred_h = draw_values$pred_h,
          habitat_beta = draw_values$habitat_beta,
          habitat_ramp_start = draw_values$habitat_ramp_start,
          habitat_ramp_end = draw_values$habitat_ramp_end,
          effort_strength = draw_values$effort_strength,
          allee_A_over_K = draw_values$allee_A_over_K
        ),
        function(dispersal_mean_km, pred_speed, pred_c, pred_h, habitat_beta, habitat_ramp_start,
                 habitat_ramp_end, effort_strength, allee_A_over_K) {
          list(
            dispersal_mean_km = dispersal_mean_km,
            pred_speed = pred_speed,
            pred_c = pred_c,
            pred_h = pred_h,
            habitat_beta = habitat_beta,
            habitat_ramp_start = habitat_ramp_start,
            habitat_ramp_end = habitat_ramp_end,
            climate_drift = climate_mid,
            effort_strength = effort_strength,
            allee_A_over_K = allee_A_over_K
          )
        }
      ),
      seed = cfg$seed + seq_len(n_draws) * 1000L,
      exp_id = sprintf("sweep_%04d", idx),
      cell_k = cell_k,
      cellsize_km = cellsize_km,
      fossil_sites = fossil_sites,
      fossil_sd = fossil_sd,
      pred_seeds = replicate(n_draws, seeds, simplify = FALSE)
    ) %>%
    dplyr::select(-idx)
}
