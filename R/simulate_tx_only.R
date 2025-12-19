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
