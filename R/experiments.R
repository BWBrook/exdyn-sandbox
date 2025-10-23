#' Latin hypercube draw for continuous parameters
#' @export
exdyn_lhs_draw <- function(defaults) {
  ranges <- list(
    dispersal_mean_km = defaults$dispersal$mean_km,
    pred_c = defaults$predation$c,
    pred_h = defaults$predation$h,
    pred_speed = defaults$predation$speed_cells_per_year,
    habitat_beta = defaults$habitat$beta,
    habitat_ramp_start = defaults$habitat$ramp_start,
    habitat_ramp_end = defaults$habitat$ramp_end,
    climate_drift = defaults$climate$drift_per_century,
    effort_strength = defaults$obs$effort_strength
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
exdyn_run_once <- function(row) {
  stopifnot(is.list(row))
  params <- row$params[[1]]
  set.seed(row$seed[[1]])
  arche <- exdyn_archetype(row$species[[1]])
  arche$beta_H <- params$habitat_beta
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
  summs <- exdyn_summaries(N, fields)
  summs <- tibble::add_column(
    summs,
    exp_id = row$exp_id[[1]],
    species = row$species[[1]],
    scenario = row$scenario[[1]],
    predation_type = row$predation_type[[1]],
    replicate = row$replicate[[1]],
    po_n = nrow(po),
    foss_n = nrow(foss),
    .before = 1
  )
  summs
}
