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
    reps = Sys.getenv("EXDYN_SYNTHETIC_REPS", unset = ""),
    screen_draws = Sys.getenv("EXDYN_SYNTHETIC_SCREEN_DRAWS", unset = ""),
    abc_n_sims = Sys.getenv("EXDYN_SYNTHETIC_ABC_N", unset = ""),
    abc_lhs_n = Sys.getenv("EXDYN_SYNTHETIC_ABC_LHS_N", unset = ""),
    abc_lhs_keep = Sys.getenv("EXDYN_SYNTHETIC_ABC_LHS_KEEP", unset = ""),
    abc_refine = Sys.getenv("EXDYN_SYNTHETIC_ABC_REFINE", unset = "")
  )
}

exdyn_synthetic_cfg_apply_overrides <- function(cfg, env = NULL) {
  cfg <- cfg %||% list()
  env <- env %||% exdyn_synthetic_env_snapshot()
  cfg$canonical <- cfg$canonical %||% list()
  if (nzchar(env$canonical_enabled)) {
    cfg$canonical$enabled <- exdyn_env_flag(env$canonical_enabled, default = FALSE)
  }
  if (nzchar(env$canonical_wp)) cfg$canonical$wp_id <- env$canonical_wp
  if (nzchar(env$canonical_run_id)) cfg$canonical$run_id <- env$canonical_run_id
  if (nzchar(env$canonical_milestone)) cfg$canonical$milestone <- env$canonical_milestone
  if (nzchar(env$canonical_root)) cfg$canonical$root <- env$canonical_root

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
