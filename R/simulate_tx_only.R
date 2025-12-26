# Internal helper for tx-only simulation with constant S and H
exdyn_update_local_const <- function(N, P, pars, K0, pred_type = c("II", "III"), pred_c, pred_h, r_eff_const) {
  pred_type <- match.arg(pred_type)
  A <- pars$A_frac
  allee <- (1 - A / (pmax(N, 0) + A))
  if (pred_type == "II") {
    M <- pred_c * (P * N) / (pred_h + N)
  } else {
    M <- pred_c * (P * N^2) / (pred_h^2 + N^2)
  }
  growth <- r_eff_const * allee * (1 - N / K0) - M - pars$d
  N * exp(growth)
}

# Internal helper for tx-only simulation on vectors (graph mode)
.exdyn_update_local_const_vec <- function(N, P, pars, K0, pred_type = c("II", "III"), pred_c, pred_h, r_eff_const) {
  pred_type <- match.arg(pred_type)
  A <- pars$A_frac
  allee <- (1 - A / (pmax(N, 0) + A))
  if (pred_type == "II") {
    M <- pred_c * (P * N) / (pred_h + N)
  } else {
    M <- pred_c * (P * N^2) / (pred_h^2 + N^2)
  }
  growth <- r_eff_const * allee * (1 - N / K0) - M - pars$d
  N * exp(growth)
}

# Internal core for tx-only simulation (no cropping).
.exdyn_simulate_tx_only_core <- function(grid_info, years, T_P, ramp_years,
                                         pars, K0, alpha,
                                         disp_mean_cells, pred,
                                         frac = 0.02, rel0 = 0.5,
                                         pre_leak = 0, log_mem = FALSE,
                                         log_tag = NULL,
                                         mask = NULL,
                                         profile = FALSE,
                                         conv_reuse = TRUE) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  stopifnot(length(years) >= 2)
  Tn <- length(years)
  ramp_years <- max(1, ramp_years)
  # initialise abundance (matching exdyn_simulate convention)
  N <- matrix(pmax(1, round(K0 * 0.1)), nrow = nx, ncol = ny)
  tau <- pmin(frac * K0, rel0 * N)
  TX <- matrix(NA_integer_, nrow = nx, ncol = ny)
  if (!is.null(mask)) {
    mask <- as.matrix(mask)
    if (!all(dim(mask) == c(nx, ny))) {
      stop("mask must have dimensions nx × ny")
    }
    N[!mask] <- 0
    TX[!mask] <- NA_integer_
  }
  conv_plan <- if (alpha > 0) {
    ker <- exdyn_kernel(mean_cells = disp_mean_cells, radius = 5L)
    exdyn_conv2_plan(nx, ny, ker, reuse_buffer = conv_reuse)
  } else {
    NULL
  }
  r_eff_const <- pars$rmax * exdyn_fS(1)
  k <- 6 / ramp_years
  pred_scale <- pred$scale %||% 1
  pred_gamma <- pred$gamma %||% 1
  scale_matrix <- pred$scale_matrix
  if (!is.null(scale_matrix)) {
    scale_matrix <- as.matrix(scale_matrix)
    if (!all(dim(scale_matrix) == c(nx, ny))) {
      stop("pred$scale_matrix must have dimensions nx × ny")
    }
    if (!is.null(mask)) {
      scale_matrix[!mask] <- 1
    }
  }

  prof <- NULL
  if (isTRUE(profile)) {
    prof <- list(
      pred_field = 0,
      local_update = 0,
      dispersal = 0,
      threshold = 0,
      total = 0,
      n_steps = Tn - 1
    )
    elapsed <- function() base::proc.time()[["elapsed"]]
  }

  for (tt in seq_len(Tn - 1)) {
    if (isTRUE(profile)) {
      step_start <- elapsed()
    }
    if (isTRUE(profile)) {
      t0 <- elapsed()
    }
    dt <- years[tt] - T_P
    P_t <- ifelse(
      is.na(T_P),
      pre_leak,
      {
        val <- 0.2 + 0.8 / (1 + exp(-k * (dt - ramp_years / 2)))
        val[dt < 0] <- pre_leak
        val <- pmax(pre_leak, pmin(1, val))
        if (!isTRUE(all.equal(pred_gamma, 1)) || !isTRUE(all.equal(pred_scale, 1)) || !is.null(scale_matrix)) {
          idx <- dt >= 0 & !is.na(dt)
          if (any(idx)) {
            scaled <- (val[idx] ^ pred_gamma) * pred_scale
            if (!is.null(scale_matrix)) {
              scaled <- scaled * scale_matrix[idx]
            }
            val[idx] <- scaled
          }
        }
        val[val < 0] <- 0
        val
      }
    )
    if (isTRUE(profile)) {
      prof$pred_field <- prof$pred_field + (elapsed() - t0)
      t0 <- elapsed()
    }
    local <- exdyn_update_local_const(
      N = N,
      P = P_t,
      pars = pars,
      K0 = K0,
      pred_type = pred$type,
      pred_c = pred$c,
      pred_h = pred$h,
      r_eff_const = r_eff_const
    )
    if (isTRUE(profile)) {
      prof$local_update <- prof$local_update + (elapsed() - t0)
      t0 <- elapsed()
    }
    if (!is.null(mask)) {
      local[!mask] <- 0
    }
    N_next <- if (alpha > 0) {
      moved <- exdyn_conv2_apply(local, conv_plan)
      if (!is.null(mask)) {
        moved[!mask] <- 0
      }
      (1 - alpha) * local + alpha * moved
    } else {
      local
    }
    if (isTRUE(profile)) {
      prof$dispersal <- prof$dispersal + (elapsed() - t0)
      t0 <- elapsed()
    }
    if (!is.null(mask)) {
      N_next[!mask] <- 0
    }
    crossed <- is.na(TX) & (N > tau) & (N_next <= tau)
    if (any(crossed, na.rm = TRUE)) {
      TX[crossed] <- tt + 1
    }
    N <- pmax(N_next, 0)
    if (isTRUE(profile)) {
      prof$threshold <- prof$threshold + (elapsed() - t0)
      prof$total <- prof$total + (elapsed() - step_start)
    }
    if (log_mem && tt %% 10L == 0L) {
      msg <- if (is.null(log_tag)) sprintf("t=%d", tt) else sprintf("%s t=%d", log_tag, tt)
      exdyn_mem_log(msg)
    }
  }
  if (isTRUE(profile)) {
    attr(TX, "profile") <- prof
  }
  TX
}

# Internal core for tx-only simulation using land-cell graph dispersal
.exdyn_simulate_tx_only_core_graph <- function(grid_info, years, T_P, ramp_years,
                                               pars, K0, alpha,
                                               disp_mean_cells, pred,
                                               frac = 0.02, rel0 = 0.5,
                                               pre_leak = 0,
                                               mask = NULL,
                                               profile = FALSE,
                                               graph = NULL,
                                               graph_radius = 5L,
                                               graph_include_self = TRUE) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  stopifnot(length(years) >= 2)
  Tn <- length(years)
  ramp_years <- max(1, ramp_years)

  if (is.null(mask)) {
    mask <- matrix(TRUE, nrow = nx, ncol = ny)
  }
  mask <- as.matrix(mask)
  if (!all(dim(mask) == c(nx, ny))) {
    stop("mask must have dimensions nx × ny")
  }

  graph_plan <- graph %||% exdyn_land_graph_plan(
    grid_info = grid_info,
    mask = mask,
    radius = graph_radius,
    include_self = graph_include_self
  )
  W <- exdyn_land_graph_weights(graph_plan, disp_mean_cells)

  rows <- graph_plan$rows
  cols <- graph_plan$cols
  n_nodes <- graph_plan$n

  N_vec <- rep(pmax(1, round(K0 * 0.1)), n_nodes)
  tau_vec <- pmin(frac * K0, rel0 * N_vec)
  TX_vec <- rep(NA_integer_, n_nodes)

  T_P_vec <- T_P[cbind(rows, cols)]

  pred_scale <- pred$scale %||% 1
  pred_gamma <- pred$gamma %||% 1
  scale_vec <- NULL
  if (!is.null(pred$scale_matrix)) {
    scale_vec <- as.matrix(pred$scale_matrix)[cbind(rows, cols)]
  }
  r_eff_const <- pars$rmax * exdyn_fS(1)
  k <- 6 / ramp_years

  prof <- NULL
  if (isTRUE(profile)) {
    prof <- list(
      pred_field = 0,
      local_update = 0,
      dispersal = 0,
      threshold = 0,
      total = 0,
      n_steps = Tn - 1
    )
    elapsed <- function() base::proc.time()[["elapsed"]]
  }

  for (tt in seq_len(Tn - 1)) {
    if (isTRUE(profile)) {
      step_start <- elapsed()
    }
    if (isTRUE(profile)) {
      t0 <- elapsed()
    }
    dt <- years[tt] - T_P_vec
    P_t <- rep(pre_leak, length(dt))
    idx_dt <- !is.na(dt)
    if (any(idx_dt)) {
      val <- 0.2 + 0.8 / (1 + exp(-k * (dt[idx_dt] - ramp_years / 2)))
      val[dt[idx_dt] < 0] <- pre_leak
      val <- pmax(pre_leak, pmin(1, val))
      if (!isTRUE(all.equal(pred_gamma, 1)) || !isTRUE(all.equal(pred_scale, 1)) || !is.null(scale_vec)) {
        idx_active <- dt[idx_dt] >= 0
        if (any(idx_active)) {
          scaled <- (val[idx_active] ^ pred_gamma) * pred_scale
          if (!is.null(scale_vec)) {
            scaled <- scaled * scale_vec[idx_dt][idx_active]
          }
          val[idx_active] <- scaled
        }
      }
      val[val < 0] <- 0
      P_t[idx_dt] <- val
    }
    if (isTRUE(profile)) {
      prof$pred_field <- prof$pred_field + (elapsed() - t0)
      t0 <- elapsed()
    }

    local_vec <- .exdyn_update_local_const_vec(
      N = N_vec,
      P = P_t,
      pars = pars,
      K0 = K0,
      pred_type = pred$type,
      pred_c = pred$c,
      pred_h = pred$h,
      r_eff_const = r_eff_const
    )
    if (isTRUE(profile)) {
      prof$local_update <- prof$local_update + (elapsed() - t0)
      t0 <- elapsed()
    }
    N_next <- if (alpha > 0) {
      moved_vec <- as.numeric(W %*% local_vec)
      (1 - alpha) * local_vec + alpha * moved_vec
    } else {
      local_vec
    }
    if (isTRUE(profile)) {
      prof$dispersal <- prof$dispersal + (elapsed() - t0)
      t0 <- elapsed()
    }
    crossed <- is.na(TX_vec) & (N_vec > tau_vec) & (N_next <= tau_vec)
    if (any(crossed, na.rm = TRUE)) {
      TX_vec[crossed] <- tt + 1
    }
    N_vec <- pmax(N_next, 0)
    if (isTRUE(profile)) {
      prof$threshold <- prof$threshold + (elapsed() - t0)
      prof$total <- prof$total + (elapsed() - step_start)
    }
  }

  TX <- matrix(NA_integer_, nrow = nx, ncol = ny)
  TX[cbind(rows, cols)] <- TX_vec
  TX[!mask] <- NA_integer_
  if (isTRUE(profile)) {
    attr(TX, "profile") <- prof
  }
  TX
}

#' Compute crop bounds for a mask
#' @keywords internal
.exdyn_crop_bounds <- function(mask, nx, ny, pad = 0L) {
  if (is.null(mask)) {
    return(list(rows = seq_len(nx), cols = seq_len(ny), row_min = 1L, col_min = 1L, cropped = FALSE))
  }
  idx <- which(mask, arr.ind = TRUE)
  if (!nrow(idx)) {
    return(list(rows = seq_len(nx), cols = seq_len(ny), row_min = 1L, col_min = 1L, cropped = FALSE))
  }
  pad <- max(0L, as.integer(pad))
  r_min <- max(1L, min(idx[, 1]) - pad)
  r_max <- min(nx, max(idx[, 1]) + pad)
  c_min <- max(1L, min(idx[, 2]) - pad)
  c_max <- min(ny, max(idx[, 2]) + pad)
  rows <- r_min:r_max
  cols <- c_min:c_max
  cropped <- r_min > 1L || r_max < nx || c_min > 1L || c_max < ny
  list(rows = rows, cols = cols, row_min = r_min, col_min = c_min, cropped = cropped)
}

#' Access surface for effort weighting
#' @keywords internal
.exdyn_access_surface <- function(nx, ny, effort_strength) {
  access <- outer(seq(0, 1, length.out = nx), seq(0, 1, length.out = ny),
                  function(i, j) 1 - pmin(i, 1 - i, j, 1 - j))
  access <- access^effort_strength
  access / mean(access)
}

#' Streamed simulation returning first-passage times only
#'
#' This helper runs the vole dynamics for a single parameter draw while
#' avoiding storage of full 3-D abundance arrays. It maintains only the
#' current abundance matrix and the output first-passage matrix, keeping
#' memory use approximately constant across time steps.
#'
#' @param grid_info List returned by [exdyn_grid_lookup()], must contain
#'   `nx`, `ny`, and optionally `cell_km`.
#' @param years Integer vector of simulation years.
#' @param T_P Matrix of mink arrival years (same dimensions as grid).
#' @param ramp_years Integer ramp duration (years to reach full predation).
#' @param pars List with entries `rmax`, `A_frac`, `beta_H`, `d`.
#' @param K0 Carrying capacity per cell.
#' @param alpha Dispersal share.
#' @param disp_mean_cells Dispersal scale in grid cells.
#' @param pred List with entries `type`, `c`, `h`.
#' @param frac Threshold fraction for first passage (defaults to 0.02).
#' @param rel0 Relative threshold to initial abundance (defaults to 0.5).
#' @param pre_leak Baseline predation prior to arrival (default 0).
#' @param log_mem If TRUE, emits memory telemetry every 10 time steps.
#' @param log_tag Optional label appended to memory log messages.
#' @param profile If TRUE, attaches timing diagnostics as an attribute.
#' @param conv_reuse If TRUE, reuse convolution buffers to reduce allocations.
#' @param mask Optional logical matrix (nx × ny). Cells with `FALSE` are treated
#'   as outside the simulation: their abundance is fixed at zero and they do not
#'   receive or donate dispersers.
#' @param crop If TRUE, crop the simulation domain to the bounding box of
#'   `mask` (with padding) to reduce FFT size.
#' @param crop_pad Padding (cells) to include around the mask bounding box.
#'
#' @return Matrix of first-passage times (year indices).
#' @export
exdyn_simulate_tx_only <- function(grid_info, years, T_P, ramp_years,
                                   pars, K0, alpha,
                                   disp_mean_cells, pred,
                                   frac = 0.02, rel0 = 0.5,
                                   pre_leak = 0, log_mem = FALSE,
                                   log_tag = NULL,
                                   mask = NULL,
                                   profile = FALSE,
                                   conv_reuse = TRUE,
                                   crop = FALSE,
                                   crop_pad = NULL,
                                   dispersal_mode = c("fft", "graph"),
                                   graph = NULL,
                                   graph_radius = 5L,
                                   graph_include_self = TRUE) {
  dispersal_mode <- match.arg(dispersal_mode)
  if (dispersal_mode == "graph") {
    return(.exdyn_simulate_tx_only_core_graph(
      grid_info = grid_info,
      years = years,
      T_P = T_P,
      ramp_years = ramp_years,
      pars = pars,
      K0 = K0,
      alpha = alpha,
      disp_mean_cells = disp_mean_cells,
      pred = pred,
      frac = frac,
      rel0 = rel0,
      pre_leak = pre_leak,
      mask = mask,
      profile = profile,
      graph = graph,
      graph_radius = graph_radius,
      graph_include_self = graph_include_self
    ))
  }
  nx <- grid_info$nx
  ny <- grid_info$ny
  if (isTRUE(crop) && !is.null(mask)) {
    pad <- crop_pad %||% 5L
    bounds <- .exdyn_crop_bounds(mask, nx, ny, pad = pad)
    if (isTRUE(bounds$cropped)) {
      rows <- bounds$rows
      cols <- bounds$cols
      T_P_sub <- T_P[rows, cols, drop = FALSE]
      mask_sub <- mask[rows, cols, drop = FALSE]
      pred_sub <- pred
      if (!is.null(pred$scale_matrix)) {
        pred_sub$scale_matrix <- pred$scale_matrix[rows, cols, drop = FALSE]
      }
      grid_sub <- list(nx = length(rows), ny = length(cols), cell_km = grid_info$cell_km)
      TX_sub <- .exdyn_simulate_tx_only_core(
        grid_info = grid_sub,
        years = years,
        T_P = T_P_sub,
        ramp_years = ramp_years,
        pars = pars,
        K0 = K0,
        alpha = alpha,
        disp_mean_cells = disp_mean_cells,
        pred = pred_sub,
        frac = frac,
        rel0 = rel0,
        pre_leak = pre_leak,
        log_mem = log_mem,
        log_tag = log_tag,
        mask = mask_sub,
        profile = profile,
        conv_reuse = conv_reuse
      )
      TX_full <- matrix(NA_integer_, nrow = nx, ncol = ny)
      TX_full[rows, cols] <- TX_sub
      if (!is.null(mask)) {
        TX_full[!mask] <- NA_integer_
      }
      if (isTRUE(profile)) {
        attr(TX_full, "profile") <- attr(TX_sub, "profile")
      }
      return(TX_full)
    }
  }
  .exdyn_simulate_tx_only_core(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = pars,
    K0 = K0,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    frac = frac,
    rel0 = rel0,
    pre_leak = pre_leak,
    log_mem = log_mem,
    log_tag = log_tag,
    mask = mask,
    profile = profile,
    conv_reuse = conv_reuse
  )
}

#' Streamed simulation for counts-only observations (core)
#' @keywords internal
.exdyn_simulate_counts_stream_core <- function(grid_info, years, T_P, ramp_years,
                                               pars, K0, alpha,
                                               disp_mean_cells, pred,
                                               rate, effort_strength = 1,
                                               pre_leak = 0,
                                               mask = NULL,
                                               conv_reuse = TRUE,
                                               access = NULL) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  stopifnot(length(years) >= 2)
  Tn <- length(years)
  ramp_years <- max(1, ramp_years)
  if (!is.null(mask)) {
    mask <- as.matrix(mask)
    if (!all(dim(mask) == c(nx, ny))) {
      stop("mask must have dimensions nx × ny")
    }
  }
  N <- matrix(pmax(1, round(K0 * 0.1)), nrow = nx, ncol = ny)
  conv_plan <- if (alpha > 0) {
    ker <- exdyn_kernel(mean_cells = disp_mean_cells, radius = 5L)
    exdyn_conv2_plan(nx, ny, ker, reuse_buffer = conv_reuse)
  } else {
    NULL
  }
  r_eff_const <- pars$rmax * exdyn_fS(1)
  k <- 6 / ramp_years
  pred_scale <- pred$scale %||% 1
  pred_gamma <- pred$gamma %||% 1
  scale_matrix <- pred$scale_matrix
  if (!is.null(scale_matrix)) {
    scale_matrix <- as.matrix(scale_matrix)
    if (!all(dim(scale_matrix) == c(nx, ny))) {
      stop("pred$scale_matrix must have dimensions nx × ny")
    }
  }

  if (is.null(access)) {
    access <- .exdyn_access_surface(nx, ny, effort_strength)
  }
  lookup <- grid_info$lookup
  cell_idx <- cbind(lookup$row_idx, lookup$col_idx)
  n_cells <- nrow(lookup)
  counts_mat <- matrix(0L, nrow = n_cells, ncol = Tn)

  record_counts <- function(year_idx) {
    lam <- N * access * rate
    lam[!is.finite(lam)] <- 0
    lam <- pmax(lam, 0)
    if (!is.null(mask)) {
      lam[!mask] <- 0
    }
    counts <- stats::rpois(length(lam), lam)
    counts <- matrix(counts, nrow = nx, ncol = ny)
    counts_mat[, year_idx] <<- counts[cell_idx]
  }

  for (tt in seq_len(Tn - 1)) {
    record_counts(tt)
    dt <- years[tt] - T_P
    P_t <- ifelse(
      is.na(T_P),
      pre_leak,
      {
        val <- 0.2 + 0.8 / (1 + exp(-k * (dt - ramp_years / 2)))
        val[dt < 0] <- pre_leak
        val <- pmax(pre_leak, pmin(1, val))
        if (!isTRUE(all.equal(pred_gamma, 1)) || !isTRUE(all.equal(pred_scale, 1)) || !is.null(scale_matrix)) {
          idx <- dt >= 0 & !is.na(dt)
          if (any(idx)) {
            scaled <- (val[idx] ^ pred_gamma) * pred_scale
            if (!is.null(scale_matrix)) {
              scaled <- scaled * scale_matrix[idx]
            }
            val[idx] <- scaled
          }
        }
        val[val < 0] <- 0
        val
      }
    )
    local <- exdyn_update_local_const(
      N = N,
      P = P_t,
      pars = pars,
      K0 = K0,
      pred_type = pred$type,
      pred_c = pred$c,
      pred_h = pred$h,
      r_eff_const = r_eff_const
    )
    N_next <- if (alpha > 0) {
      moved <- exdyn_conv2_apply(local, conv_plan)
      (1 - alpha) * local + alpha * moved
    } else {
      local
    }
    N <- pmax(N_next, 0)
  }
  record_counts(Tn)
  list(
    counts_mat = counts_mat,
    effort_mat = counts_mat,
    years = years,
    cells = lookup
  )
}

#' Streamed simulation for counts-only observations (graph core)
#' @keywords internal
.exdyn_simulate_counts_stream_core_graph <- function(grid_info, years, T_P, ramp_years,
                                                     pars, K0, alpha,
                                                     disp_mean_cells, pred,
                                                     rate, effort_strength = 1,
                                                     pre_leak = 0,
                                                     mask = NULL,
                                                     graph = NULL,
                                                     graph_radius = 5L,
                                                     graph_include_self = TRUE,
                                                     access = NULL) {
  nx <- grid_info$nx
  ny <- grid_info$ny
  stopifnot(length(years) >= 2)
  Tn <- length(years)
  ramp_years <- max(1, ramp_years)
  if (is.null(mask)) {
    mask <- matrix(TRUE, nrow = nx, ncol = ny)
  }
  mask <- as.matrix(mask)
  if (!all(dim(mask) == c(nx, ny))) {
    stop("mask must have dimensions nx × ny")
  }
  graph_plan <- graph %||% exdyn_land_graph_plan(
    grid_info = grid_info,
    mask = mask,
    radius = graph_radius,
    include_self = graph_include_self
  )
  W <- exdyn_land_graph_weights(graph_plan, disp_mean_cells)
  rows <- graph_plan$rows
  cols <- graph_plan$cols
  n_nodes <- graph_plan$n
  lookup <- grid_info$lookup
  lookup_idx <- graph_plan$lookup_idx
  if (is.null(lookup_idx)) {
    lookup_map <- matrix(NA_integer_, nrow = nx, ncol = ny)
    lookup_map[cbind(lookup$row_idx, lookup$col_idx)] <- seq_len(nrow(lookup))
    lookup_idx <- lookup_map[cbind(rows, cols)]
  }

  N_vec <- rep(pmax(1, round(K0 * 0.1)), n_nodes)
  r_eff_const <- pars$rmax * exdyn_fS(1)
  k <- 6 / ramp_years
  pred_scale <- pred$scale %||% 1
  pred_gamma <- pred$gamma %||% 1
  scale_vec <- NULL
  if (!is.null(pred$scale_matrix)) {
    scale_vec <- as.matrix(pred$scale_matrix)[cbind(rows, cols)]
  }

  if (is.null(access)) {
    access <- .exdyn_access_surface(nx, ny, effort_strength)
  }
  access_vec <- access[cbind(rows, cols)]

  counts_mat <- matrix(0L, nrow = nrow(lookup), ncol = Tn)

  record_counts <- function(year_idx) {
    lam <- N_vec * access_vec * rate
    lam[!is.finite(lam)] <- 0
    lam <- pmax(lam, 0)
    counts_vec <- stats::rpois(length(lam), lam)
    counts_mat[lookup_idx, year_idx] <<- counts_vec
  }

  T_P_vec <- T_P[cbind(rows, cols)]
  for (tt in seq_len(Tn - 1)) {
    record_counts(tt)
    dt <- years[tt] - T_P_vec
    P_t <- rep(pre_leak, length(dt))
    idx_dt <- !is.na(dt)
    if (any(idx_dt)) {
      val <- 0.2 + 0.8 / (1 + exp(-k * (dt[idx_dt] - ramp_years / 2)))
      val[dt[idx_dt] < 0] <- pre_leak
      val <- pmax(pre_leak, pmin(1, val))
      if (!isTRUE(all.equal(pred_gamma, 1)) || !isTRUE(all.equal(pred_scale, 1)) || !is.null(scale_vec)) {
        idx_active <- dt[idx_dt] >= 0
        if (any(idx_active)) {
          scaled <- (val[idx_active] ^ pred_gamma) * pred_scale
          if (!is.null(scale_vec)) {
            scaled <- scaled * scale_vec[idx_dt][idx_active]
          }
          val[idx_active] <- scaled
        }
      }
      val[val < 0] <- 0
      P_t[idx_dt] <- val
    }

    local_vec <- .exdyn_update_local_const_vec(
      N = N_vec,
      P = P_t,
      pars = pars,
      K0 = K0,
      pred_type = pred$type,
      pred_c = pred$c,
      pred_h = pred$h,
      r_eff_const = r_eff_const
    )
    N_next <- if (alpha > 0) {
      moved_vec <- as.numeric(W %*% local_vec)
      (1 - alpha) * local_vec + alpha * moved_vec
    } else {
      local_vec
    }
    N_vec <- pmax(N_next, 0)
  }
  record_counts(Tn)
  list(
    counts_mat = counts_mat,
    effort_mat = counts_mat,
    years = years,
    cells = lookup
  )
}

#' Streamed simulation for counts-only observations
#' @keywords internal
exdyn_simulate_counts_stream <- function(grid_info, years, T_P, ramp_years,
                                         pars, K0, alpha,
                                         disp_mean_cells, pred,
                                         rate, effort_strength = 1,
                                         pre_leak = 0,
                                         mask = NULL,
                                         conv_reuse = TRUE,
                                         crop = FALSE,
                                         crop_pad = NULL,
                                         dispersal_mode = c("fft", "graph"),
                                         graph = NULL,
                                         graph_radius = 5L,
                                         graph_include_self = TRUE) {
  dispersal_mode <- match.arg(dispersal_mode)
  if (dispersal_mode == "graph") {
    return(.exdyn_simulate_counts_stream_core_graph(
      grid_info = grid_info,
      years = years,
      T_P = T_P,
      ramp_years = ramp_years,
      pars = pars,
      K0 = K0,
      alpha = alpha,
      disp_mean_cells = disp_mean_cells,
      pred = pred,
      rate = rate,
      effort_strength = effort_strength,
      pre_leak = pre_leak,
      mask = mask,
      graph = graph,
      graph_radius = graph_radius,
      graph_include_self = graph_include_self
    ))
  }
  nx <- grid_info$nx
  ny <- grid_info$ny
  if (isTRUE(crop) && !is.null(mask)) {
    pad <- crop_pad %||% 5L
    bounds <- .exdyn_crop_bounds(mask, nx, ny, pad = pad)
    if (isTRUE(bounds$cropped)) {
      rows <- bounds$rows
      cols <- bounds$cols
      T_P_sub <- T_P[rows, cols, drop = FALSE]
      mask_sub <- mask[rows, cols, drop = FALSE]
      pred_sub <- pred
      if (!is.null(pred$scale_matrix)) {
        pred_sub$scale_matrix <- pred$scale_matrix[rows, cols, drop = FALSE]
      }
      lookup_full <- grid_info$lookup
      lookup_full$cell_idx <- seq_len(nrow(lookup_full))
      in_bounds <- lookup_full$row_idx %in% rows & lookup_full$col_idx %in% cols
      lookup_sub <- lookup_full[in_bounds, , drop = FALSE]
      lookup_sub_local <- lookup_sub
      lookup_sub_local$row_idx <- lookup_sub$row_idx - bounds$row_min + 1L
      lookup_sub_local$col_idx <- lookup_sub$col_idx - bounds$col_min + 1L
      grid_sub <- list(
        nx = length(rows),
        ny = length(cols),
        cell_km = grid_info$cell_km,
        lookup = lookup_sub_local
      )
      access_full <- .exdyn_access_surface(nx, ny, effort_strength)
      access_sub <- access_full[rows, cols, drop = FALSE]
      counts_sub <- .exdyn_simulate_counts_stream_core(
        grid_info = grid_sub,
        years = years,
        T_P = T_P_sub,
        ramp_years = ramp_years,
        pars = pars,
        K0 = K0,
        alpha = alpha,
        disp_mean_cells = disp_mean_cells,
        pred = pred_sub,
        rate = rate,
        effort_strength = effort_strength,
        pre_leak = pre_leak,
        mask = mask_sub,
        conv_reuse = conv_reuse,
        access = access_sub
      )
      n_cells_full <- nrow(lookup_full)
      counts_full <- matrix(0L, nrow = n_cells_full, ncol = length(years))
      counts_full[lookup_sub$cell_idx, ] <- counts_sub$counts_mat
      return(list(
        counts_mat = counts_full,
        effort_mat = counts_full,
        years = years,
        cells = lookup_full
      ))
    }
  }
  .exdyn_simulate_counts_stream_core(
    grid_info = grid_info,
    years = years,
    T_P = T_P,
    ramp_years = ramp_years,
    pars = pars,
    K0 = K0,
    alpha = alpha,
    disp_mean_cells = disp_mean_cells,
    pred = pred,
    rate = rate,
    effort_strength = effort_strength,
    pre_leak = pre_leak,
    mask = mask,
    conv_reuse = conv_reuse
  )
}
