#' Read YAML config and complete with archetype parameters
#' @export
exdyn_config <- function(path="config/default.yaml") {
  if (!file.exists(path)) {
    candidates <- c(file.path("..", path), file.path("..", "..", path))
    hit <- candidates[file.exists(candidates)][1]
    if (!is.na(hit)) {
      path <- hit
    }
  }
  cfg <- yaml::read_yaml(path)
  set.seed(cfg$seed)
  arche <- exdyn_archetype(cfg$species)
  pars <- arche
  pars$beta_H <- cfg$habitat$beta
  list(
    nx=cfg$nx, ny=cfg$ny, years=cfg$years, K0=cfg$cell_k,
    alpha=cfg$dispersal$alpha,
    disp_mean_cells = cfg$dispersal$mean_km / cfg$cellsize_km,
    pred = list(type=cfg$predation$type, c=cfg$predation$c, h=cfg$predation$h),
    pars = pars,
    scenario = cfg$threat_scenario,
    ramp_start = cfg$habitat$ramp_start,
    ramp_end   = cfg$habitat$ramp_end,
    obs = cfg$obs
  )
}
