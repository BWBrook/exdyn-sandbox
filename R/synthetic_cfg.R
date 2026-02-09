# Synthetic config overrides (internal)

exdyn_env_flag <- function(val, default = FALSE) {
  if (is.null(val) || !nzchar(val)) return(default)
  tolower(val) %in% c("1", "true", "yes")
}

exdyn_synthetic_env_snapshot <- function() {
  list(
    canonical_enabled = Sys.getenv("EXDYN_CANONICAL_ENABLED", unset = ""),
    canonical_wp = Sys.getenv("EXDYN_CANONICAL_WP", unset = ""),
    canonical_run_id = Sys.getenv("EXDYN_CANONICAL_RUN_ID", unset = ""),
    canonical_milestone = Sys.getenv("EXDYN_CANONICAL_MILESTONE", unset = ""),
    canonical_root = Sys.getenv("EXDYN_CANONICAL_ROOT", unset = ""),
    smoke = Sys.getenv("EXDYN_SYNTHETIC_SMOKE", unset = ""),
    modes = Sys.getenv("EXDYN_SYNTHETIC_MODES", unset = ""),
    years = Sys.getenv("EXDYN_SYNTHETIC_YEARS", unset = ""),
    grid_type = Sys.getenv("EXDYN_SYNTHETIC_GRID_TYPE", unset = ""),
    grid_nx = Sys.getenv("EXDYN_SYNTHETIC_GRID_NX", unset = ""),
    grid_ny = Sys.getenv("EXDYN_SYNTHETIC_GRID_NY", unset = ""),
    grid_cell_km = Sys.getenv("EXDYN_SYNTHETIC_GRID_CELL_KM", unset = ""),
    grid_riparian_frac = Sys.getenv("EXDYN_SYNTHETIC_GRID_RIPARIAN_FRAC", unset = ""),
    grid_region_n = Sys.getenv("EXDYN_SYNTHETIC_GRID_REGION_N", unset = ""),
    grid_region_labels = Sys.getenv("EXDYN_SYNTHETIC_GRID_REGION_LABELS", unset = ""),
    arrival_source = Sys.getenv("EXDYN_SYNTHETIC_ARRIVAL_SOURCE", unset = ""),
    arrival_realism = Sys.getenv("EXDYN_SYNTHETIC_ARRIVAL_REALISM", unset = ""),
    viability = Sys.getenv("EXDYN_SYNTHETIC_VIABILITY", unset = ""),
    pilot_gates = Sys.getenv("EXDYN_SYNTHETIC_PILOT_GATES", unset = ""),
    obs_mode = Sys.getenv("EXDYN_SYNTHETIC_OBS_MODE", unset = ""),
    mask = Sys.getenv("EXDYN_SYNTHETIC_MASK", unset = ""),
    crop = Sys.getenv("EXDYN_SYNTHETIC_CROP", unset = ""),
    reps = Sys.getenv("EXDYN_SYNTHETIC_REPS", unset = ""),
    screen_draws = Sys.getenv("EXDYN_SYNTHETIC_SCREEN_DRAWS", unset = ""),
    abc_n_sims = Sys.getenv("EXDYN_SYNTHETIC_ABC_N", unset = ""),
    abc_eps = Sys.getenv("EXDYN_SYNTHETIC_ABC_EPS", unset = ""),
    abc_eps_tight = Sys.getenv("EXDYN_SYNTHETIC_ABC_EPS_TIGHT", unset = ""),
    abc_lhs_n = Sys.getenv("EXDYN_SYNTHETIC_ABC_LHS_N", unset = ""),
    abc_lhs_keep = Sys.getenv("EXDYN_SYNTHETIC_ABC_LHS_KEEP", unset = ""),
    abc_refine = Sys.getenv("EXDYN_SYNTHETIC_ABC_REFINE", unset = ""),
    recovery_cores = Sys.getenv("EXDYN_SYNTHETIC_CORES", unset = "")
  )
}

exdyn_synthetic_cfg_apply_overrides <- function(cfg, env = NULL) {
  cfg <- cfg %||% list()
  env <- env %||% exdyn_synthetic_env_snapshot()
  cfg$canonical <- cfg$canonical %||% list()
  cfg$grid <- cfg$grid %||% list()
  if (nzchar(env$canonical_enabled)) {
    cfg$canonical$enabled <- exdyn_env_flag(env$canonical_enabled, default = FALSE)
  }
  if (nzchar(env$canonical_wp)) cfg$canonical$wp_id <- env$canonical_wp
  if (nzchar(env$canonical_run_id)) cfg$canonical$run_id <- env$canonical_run_id
  if (nzchar(env$canonical_milestone)) cfg$canonical$milestone <- env$canonical_milestone
  if (nzchar(env$canonical_root)) cfg$canonical$root <- env$canonical_root
  if (nzchar(env$modes)) {
    cfg$modes <- strsplit(env$modes, ",")[[1]]
    cfg$modes <- trimws(cfg$modes)
  }
  if (nzchar(env$years)) {
    if (tolower(env$years) == "pilot") {
      cfg$years <- "pilot"
    } else {
      parts <- strsplit(env$years, ",")[[1]]
      vals <- suppressWarnings(as.integer(trimws(parts)))
      vals <- vals[is.finite(vals)]
      if (length(vals)) {
        cfg$years <- vals
      }
    }
  }
  if (nzchar(env$grid_type)) cfg$grid$type <- env$grid_type
  if (nzchar(env$grid_nx)) {
    nx <- suppressWarnings(as.integer(env$grid_nx))
    if (is.finite(nx)) cfg$grid$nx <- nx
  }
  if (nzchar(env$grid_ny)) {
    ny <- suppressWarnings(as.integer(env$grid_ny))
    if (is.finite(ny)) cfg$grid$ny <- ny
  }
  if (nzchar(env$grid_cell_km)) {
    cell_km <- suppressWarnings(as.numeric(env$grid_cell_km))
    if (is.finite(cell_km)) cfg$grid$cell_km <- cell_km
  }
  if (nzchar(env$grid_riparian_frac)) {
    rip <- suppressWarnings(as.numeric(env$grid_riparian_frac))
    if (is.finite(rip)) cfg$grid$riparian_frac <- rip
  }
  if (nzchar(env$grid_region_n)) {
    region_n <- suppressWarnings(as.integer(env$grid_region_n))
    if (is.finite(region_n)) cfg$grid$region_n <- region_n
  }
  if (nzchar(env$grid_region_labels)) {
    labels <- strsplit(env$grid_region_labels, ",")[[1]]
    labels <- trimws(labels)
    if (length(labels)) cfg$grid$region_labels <- labels
  }
  if (nzchar(env$arrival_source)) {
    cfg$grid$arrival_source <- env$arrival_source
  }
  if (nzchar(env$arrival_realism)) {
    cfg$arrival_realism <- cfg$arrival_realism %||% list()
    cfg$arrival_realism$enabled <- exdyn_env_flag(env$arrival_realism, default = FALSE)
  }
  if (nzchar(env$viability)) {
    cfg$viability <- cfg$viability %||% list()
    cfg$viability$enabled <- exdyn_env_flag(env$viability, default = FALSE)
  }
  if (nzchar(env$pilot_gates)) {
    cfg$pilot_gates <- cfg$pilot_gates %||% list()
    cfg$pilot_gates$enabled <- exdyn_env_flag(env$pilot_gates, default = TRUE)
  }
  if (nzchar(env$obs_mode)) {
    cfg$noise <- cfg$noise %||% list()
    cfg$noise$obs_mode <- env$obs_mode
  }
  if (nzchar(env$mask)) {
    cfg$mask <- env$mask
  }
  if (exdyn_env_flag(env$crop, default = FALSE)) {
    cfg$screen <- cfg$screen %||% list()
    cfg$abc <- cfg$abc %||% list()
    cfg$noise <- cfg$noise %||% list()
    cfg$screen$crop <- TRUE
    cfg$abc$crop <- TRUE
    cfg$noise$crop <- TRUE
  }

  if (exdyn_env_flag(env$smoke, default = FALSE)) {
    if (!is.null(cfg$screen$n_draws)) {
      cfg$screen$n_draws <- min(cfg$screen$n_draws, 4)
    }
    if (!is.null(cfg$abc$n_sims)) {
      cfg$abc$n_sims <- min(cfg$abc$n_sims, 30)
    }
    if (!is.null(cfg$abc$lhs$n)) {
      cfg$abc$lhs$n <- min(cfg$abc$lhs$n, 8)
    }
    if (!is.null(cfg$abc$lhs$keep)) {
      cfg$abc$lhs$keep <- min(cfg$abc$lhs$keep, 4)
    }
    if (!is.null(cfg$recovery$n_reps)) {
      cfg$recovery$n_reps <- min(cfg$recovery$n_reps, 1)
    }
  }
  if (nzchar(env$reps)) {
    reps <- suppressWarnings(as.integer(env$reps))
    if (is.finite(reps) && reps > 0) {
      cfg$recovery$n_reps <- reps
    }
  }
  if (nzchar(env$recovery_cores)) {
    cores <- suppressWarnings(as.integer(env$recovery_cores))
    if (is.finite(cores) && cores > 0) {
      cfg$recovery$n_cores <- cores
    }
  }
  if (nzchar(env$screen_draws)) {
    draws <- suppressWarnings(as.integer(env$screen_draws))
    if (is.finite(draws) && draws > 0) {
      cfg$screen$n_draws <- draws
    }
  }
  if (nzchar(env$abc_n_sims)) {
    n_sims <- suppressWarnings(as.integer(env$abc_n_sims))
    if (is.finite(n_sims) && n_sims > 0) {
      cfg$abc$n_sims <- n_sims
    }
  }
  if (nzchar(env$abc_eps)) {
    eps <- suppressWarnings(as.numeric(env$abc_eps))
    if (is.finite(eps) && eps > 0) {
      cfg$abc$eps <- eps
    }
  }
  if (nzchar(env$abc_eps_tight)) {
    eps_tight <- suppressWarnings(as.numeric(env$abc_eps_tight))
    if (is.finite(eps_tight) && eps_tight > 0) {
      cfg$abc$eps_tight <- eps_tight
    }
  }
  if (nzchar(env$abc_lhs_n)) {
    lhs_n <- suppressWarnings(as.integer(env$abc_lhs_n))
    if (is.finite(lhs_n) && lhs_n >= 0) {
      cfg$abc$lhs$n <- lhs_n
    }
  }
  if (nzchar(env$abc_lhs_keep)) {
    lhs_keep <- suppressWarnings(as.integer(env$abc_lhs_keep))
    if (is.finite(lhs_keep) && lhs_keep >= 0) {
      cfg$abc$lhs$keep <- lhs_keep
    }
  }
  if (nzchar(env$abc_refine)) {
    cfg$abc$refine <- exdyn_env_flag(env$abc_refine, default = TRUE)
  }
  cfg
}
