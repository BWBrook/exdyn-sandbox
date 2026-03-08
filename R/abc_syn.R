# Internal helpers for masking and counts
.exdyn_prepare_mask <- function(mask, dims) {
  if (is.null(mask)) {
    return(matrix(TRUE, nrow = dims[1], ncol = dims[2]))
  }
  mask <- as.matrix(mask)
  if (!all(dim(mask) == dims)) {
    stop("mask must have dimensions nx × ny")
  }
  mask[is.na(mask)] <- FALSE
  mask
}

exdyn_summary_counts <- function(TX, T_P, mask = NULL) {
  stopifnot(length(dim(TX)) == 2L, length(dim(T_P)) == 2L)
  stopifnot(all(dim(TX) == dim(T_P)))
  mask_use <- .exdyn_prepare_mask(mask, dim(TX))
  tp_finite <- is.finite(T_P) & mask_use
  tx_finite <- is.finite(TX) & mask_use
  c(
    n_mask = sum(mask_use),
    n_TP_finite = sum(tp_finite),
    n_TX_finite = sum(tx_finite),
    n_pairs = sum(tp_finite & tx_finite)
  )
}

# Internal helper for cumulative coverage
exdyn_coverage_curve <- function(TX, T_P, breaks, mask = NULL) {
  if (is.null(breaks) || !length(breaks)) {
    return(numeric())
  }
  mask_use <- .exdyn_prepare_mask(mask, dim(TX))
  finite <- is.finite(TX) & is.finite(T_P) & mask_use
  denom <- sum(is.finite(T_P) & mask_use)
  if (!denom) {
    return(rep(NA_real_, length(breaks)))
  }
  purrr::map_dbl(breaks, function(brk) {
    sum(finite & TX <= brk) / denom
  })
}

#' Response-only summary vector for extirpation maps
#'
#' Construct a compact summary of simulated extirpation times that uses
#' only response-side information (extirpations and their geometry) while
#' optionally comparing against a driver arrival surface. The summary is
#' designed for synthetic calibration/ABC workflows.
#'
#' @param TX Matrix of observed or simulated extirpation years.
#' @param T_P Matrix of driver arrival years (same dimensions as `TX`).
#' @param years Optional numeric vector of simulation years.
#' @param coverage_breaks Optional numeric vector of year thresholds used
#'   to derive cumulative coverage values. If NULL, evenly spaced breaks
#'   over the provided years are used (when available).
#' @param mask Optional logical matrix specifying the analysis domain.
#'
#' @return Named numeric vector containing gradient magnitude, principal
#'   axis ratio, coverage, mean/SD lag, orientation concentration,
#'   front speed, overall extirpation statistics, and (optionally) the
#'   cumulative coverage evaluated at each requested break.
#' @export
exdyn_summary_tx_response <- function(TX, T_P, years = NULL, coverage_breaks = NULL, mask = NULL) {
  stopifnot(length(dim(TX)) == 2L, length(dim(T_P)) == 2L)
  stopifnot(all(dim(TX) == dim(T_P)))
  mask_use <- .exdyn_prepare_mask(mask, dim(TX))
  TX_use <- TX
  T_P_use <- T_P
  TX_use[!mask_use] <- NA_real_
  T_P_use[!mask_use] <- NA_real_
  plane <- exdyn_front_plane(TX_use)
  orient <- exdyn_orientation_metrics(TX_use)
  speed_est <- exdyn_front_speed_estimate(TX_use, orient$dominant)
  finite <- is.finite(TX_use) & is.finite(T_P_use)
  denom <- sum(is.finite(T_P_use))
  coverage <- if (denom > 0) sum(finite) / denom else 0
  lag_mean <- lag_sd <- NA_real_
  if (coverage > 0) {
    lag_vals <- TX_use[finite] - T_P_use[finite]
    lag_mean <- mean(lag_vals)
    lag_sd <- stats::sd(lag_vals)
  }
  r2_arrival <- NA_real_
  if (sum(finite) >= 3) {
    tx_vals <- TX_use[finite]
    tp_vals <- T_P_use[finite]
    var_tp <- stats::var(tp_vals)
    var_tx <- stats::var(tx_vals)
    if (!is.finite(var_tp) || var_tp <= 0 || !is.finite(var_tx) || var_tx <= 0) {
      r2_arrival <- 0
    } else {
      r <- suppressWarnings(stats::cor(tx_vals, tp_vals, use = "complete.obs"))
      r2_arrival <- if (is.finite(r)) max(0, min(1, r^2)) else NA_real_
    }
  }
  tx_vals <- TX_use[is.finite(TX_use)]
  tx_mean <- if (length(tx_vals)) mean(tx_vals) else NA_real_
  tx_sd <- if (length(tx_vals)) stats::sd(tx_vals) else NA_real_
  if (is.null(coverage_breaks)) {
    if (!is.null(years) && length(years) >= 2) {
      coverage_breaks <- exdyn_coverage_breaks(years)
    } else {
      coverage_breaks <- numeric()
    }
  }
  coverage_curve <- exdyn_coverage_curve(TX_use, T_P_use, coverage_breaks, mask = mask_use)
  if (length(coverage_curve)) {
    names(coverage_curve) <- paste0("cov_curve_", seq_along(coverage_curve))
  }
  c(
    grad_mag = unname(plane$grad_mag),
    pc_ratio = unname(plane$pc_ratio),
    coverage = coverage,
    lag_mean = lag_mean,
    lag_sd = lag_sd,
    r2_arrival = r2_arrival,
    orient_R = unname(orient$R),
    speed_cells_per_year = unname(speed_est$speed),
    speed_r2 = unname(speed_est$r2),
    tx_mean = tx_mean,
    tx_sd = tx_sd,
    coverage_curve
  )
}

.exdyn_abc_distance_components <- function(S_obs,
                                          S_sim,
                                          scale,
                                          required_metrics = NULL,
                                          optional_missing_penalty = 0) {
  names_obs <- names(S_obs)
  if (is.null(names_obs)) {
    stop("S_obs must be a named numeric vector.")
  }
  S_sim <- S_sim[names_obs]
  scale <- scale[names_obs]
  required_metrics <- required_metrics %||% names_obs
  required_metrics <- intersect(required_metrics, names_obs)
  if (!length(required_metrics)) {
    required_metrics <- names_obs
  }
  optional_metrics <- setdiff(names_obs, required_metrics)
  required_finite <- is.finite(S_sim[required_metrics]) &
    is.finite(S_obs[required_metrics]) &
    is.finite(scale[required_metrics])
  valid_required <- all(required_finite)
  if (!valid_required) {
    return(list(
      valid_required = FALSE,
      n_required = length(required_metrics),
      n_required_finite = sum(required_finite, na.rm = TRUE),
      n_optional = length(optional_metrics),
      n_optional_finite = NA_integer_,
      n_optional_missing = length(optional_metrics),
      distance_core = Inf,
      distance_optional_penalty = Inf,
      distance_total = Inf
    ))
  }
  finite_all <- is.finite(S_sim) & is.finite(S_obs) & is.finite(scale)
  distance_core <- if (any(finite_all)) {
    sqrt(sum(((S_sim[finite_all] - S_obs[finite_all]) / scale[finite_all])^2))
  } else {
    Inf
  }
  optional_missing <- if (length(optional_metrics)) {
    sum(!(is.finite(S_sim[optional_metrics]) &
            is.finite(S_obs[optional_metrics]) &
            is.finite(scale[optional_metrics])))
  } else {
    0L
  }
  distance_optional_penalty <- optional_missing * (optional_missing_penalty %||% 0)
  list(
    valid_required = TRUE,
    n_required = length(required_metrics),
    n_required_finite = sum(required_finite, na.rm = TRUE),
    n_optional = length(optional_metrics),
    n_optional_finite = if (length(optional_metrics)) sum(finite_all[optional_metrics], na.rm = TRUE) else 0L,
    n_optional_missing = optional_missing,
    distance_core = distance_core,
    distance_optional_penalty = distance_optional_penalty,
    distance_total = distance_core + distance_optional_penalty
  )
}

#' Simple rejection ABC for synthetic response-only summaries
#'
#' Run a rejection ABC routine given a summary statistic, prior sampler,
#' and simulator producing synthetic datasets. The caller supplies a
#' function that converts simulator output into the same summary vector
#' used for the observed data.
#'
#' @param S_obs Numeric vector of observed summary statistics (named).
#' @param prior_sampler Function returning a named numeric vector (thetas).
#' @param simulator Function taking a parameter vector and returning a
#'   list used by `summary_fn` (typically the output of
#'   [exdyn_make_synthetic()]).
#' @param summary_fn Function mapping simulator output to a numeric vector
#'   with the same names/order as `S_obs`.
#' @param n_sims Number of simulations to draw.
#' @param eps Acceptance radius (Euclidean distance in scaled summary
#'   space).
#' @param scale Optional numeric vector used to scale each summary
#'   component prior to distance calculation. Defaults to
#'   `pmax(abs(S_obs), 1e-6)`.
#' @param progress If `TRUE`, emits progress every 100 simulations.
#'
#' @return List with accepted parameter draws (`samples`), accepted
#'   summaries (`summaries`), associated distances (`distances`), and the
#'   complete simulation log (`all`).
#' @export
exdyn_abc_rejection <- function(S_obs,
                                prior_sampler,
                                simulator,
                                summary_fn,
                                n_sims = 2000L,
                                eps = 1,
                                scale = NULL,
                                required_metrics = NULL,
                                optional_missing_penalty = 0,
                                progress = TRUE) {
  if (is.null(scale)) {
    scale <- pmax(abs(S_obs), 1e-6)
  }
  names_obs <- names(S_obs)
  S_obs <- as.numeric(S_obs)
  if (!is.null(names_obs)) {
    names(S_obs) <- names_obs
  }
  scale <- as.numeric(scale)
  if (!is.null(names_obs)) {
    names(scale) <- names_obs
  }
  theta_list <- vector("list", n_sims)
  summary_list <- vector("list", n_sims)
  dist_vec <- rep(NA_real_, n_sims)
  dist_core_vec <- rep(NA_real_, n_sims)
  dist_pen_vec <- rep(NA_real_, n_sims)
  valid_required_vec <- rep(FALSE, n_sims)
  n_required_finite_vec <- rep(NA_integer_, n_sims)
  n_optional_missing_vec <- rep(NA_integer_, n_sims)
  accepted <- rep(FALSE, n_sims)
  for (i in seq_len(n_sims)) {
    theta <- prior_sampler()
    sim <- simulator(theta)
    S_sim <- summary_fn(sim)
    S_sim <- S_sim[names_obs]
    dist_info <- .exdyn_abc_distance_components(
      S_obs = S_obs,
      S_sim = S_sim,
      scale = scale,
      required_metrics = required_metrics,
      optional_missing_penalty = optional_missing_penalty
    )
    dist <- dist_info$distance_total
    theta_list[[i]] <- theta
    summary_list[[i]] <- S_sim
    dist_vec[i] <- dist
    dist_core_vec[i] <- dist_info$distance_core
    dist_pen_vec[i] <- dist_info$distance_optional_penalty
    valid_required_vec[i] <- dist_info$valid_required
    n_required_finite_vec[i] <- dist_info$n_required_finite
    n_optional_missing_vec[i] <- dist_info$n_optional_missing
    accepted[i] <- is.finite(dist) && dist <= eps
    if (progress && i %% 100L == 0L) {
      message(sprintf("[abc] %d/%d simulations, accepted %d", i, n_sims, sum(accepted)))
    }
  }
  accepted_idx <- which(accepted)
  samples <- if (length(accepted_idx)) {
    theta_flat <- purrr::map(theta_list[accepted_idx], function(theta) {
      if (!is.null(theta$delta_region)) {
        delta <- theta$delta_region
        theta$delta_region <- NULL
        for (nm in names(delta)) {
          theta[[paste0("delta_", nm)]] <- delta[[nm]]
        }
      }
      theta
    })
    dplyr::bind_rows(purrr::map(theta_flat, tibble::as_tibble_row))
  } else {
    tibble::tibble()
  }
  summaries <- if (length(accepted_idx)) {
    dplyr::bind_rows(purrr::map(summary_list[accepted_idx], tibble::as_tibble_row))
  } else {
    tibble::tibble()
  }
  all_log <- tibble::tibble(
    sim = seq_len(n_sims),
    accepted = accepted,
    distance = dist_vec,
    distance_core = dist_core_vec,
    distance_optional_penalty = dist_pen_vec,
    valid_required = valid_required_vec,
    n_required_finite = n_required_finite_vec,
    n_optional_missing = n_optional_missing_vec
  ) %>%
    dplyr::mutate(parameters = theta_list, summaries = summary_list)
  list(
    samples = samples,
    summaries = summaries,
    distances = dist_vec[accepted_idx],
    all = all_log,
    eps = eps,
    scale = scale,
    required_metrics = required_metrics,
    optional_missing_penalty = optional_missing_penalty
  )
}

#' Uniform prior factory for synthetic mink→vole calibration
#'
#' @param bounds Named list where each element is a length-2 numeric
#'   vector defining lower/upper bounds for a scalar parameter (e.g.
#'   `list(alpha = c(0.05, 0.4))`).
#' @param delta_bounds Optional named list for region-specific delta
#'   parameters; each element must also be a length-2 numeric vector.
#'
#' @return Function that samples a parameter list consistent with the
#'   specified bounds.
#' @export
exdyn_prior_sampler_syn <- function(bounds, delta_bounds = NULL) {
  stopifnot(length(bounds) > 0)
  purrr::walk(bounds, function(x) stopifnot(length(x) == 2, x[1] <= x[2]))
  if (!is.null(delta_bounds)) {
    purrr::walk(delta_bounds, function(x) stopifnot(length(x) == 2, x[1] <= x[2]))
  }
  function() {
    theta <- purrr::imap(bounds, ~ stats::runif(1, .x[1], .x[2]))
    if (!is.null(delta_bounds)) {
      delta <- purrr::imap(delta_bounds, ~ stats::runif(1, .x[1], .x[2]))
      theta$delta_region <- unlist(delta)
    }
    theta
  }
}
