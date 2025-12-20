# Internal helper for cumulative coverage
exdyn_coverage_curve <- function(TX, T_P, breaks) {
  if (is.null(breaks) || !length(breaks)) {
    return(numeric())
  }
  finite <- is.finite(TX) & is.finite(T_P)
  denom <- sum(is.finite(T_P))
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
#'
#' @return Named numeric vector containing gradient magnitude, principal
#'   axis ratio, coverage, mean/SD lag, orientation concentration,
#'   front speed, overall extirpation statistics, and (optionally) the
#'   cumulative coverage evaluated at each requested break.
#' @export
exdyn_summary_tx_response <- function(TX, T_P, years = NULL, coverage_breaks = NULL) {
  stopifnot(length(dim(TX)) == 2L, length(dim(T_P)) == 2L)
  stopifnot(all(dim(TX) == dim(T_P)))
  plane <- exdyn_front_plane(TX)
  orient <- exdyn_orientation_metrics(TX)
  speed_est <- exdyn_front_speed_estimate(TX, orient$dominant)
  finite <- is.finite(TX) & is.finite(T_P)
  denom <- sum(is.finite(T_P))
  coverage <- if (denom > 0) sum(finite) / denom else 0
  lag_mean <- lag_sd <- NA_real_
  if (coverage > 0) {
    lag_vals <- TX[finite] - T_P[finite]
    lag_mean <- mean(lag_vals)
    lag_sd <- stats::sd(lag_vals)
  }
  r2_arrival <- NA_real_
  if (sum(finite) >= 3) {
    fit <- stats::lm(TX[finite] ~ T_P[finite])
    r2_arrival <- max(0, min(1, summary(fit)$r.squared))
  }
  tx_vals <- TX[is.finite(TX)]
  tx_mean <- if (length(tx_vals)) mean(tx_vals) else NA_real_
  tx_sd <- if (length(tx_vals)) stats::sd(tx_vals) else NA_real_
  if (is.null(coverage_breaks)) {
    if (!is.null(years) && length(years) >= 2) {
      coverage_breaks <- exdyn_coverage_breaks(years)
    } else {
      coverage_breaks <- numeric()
    }
  }
  coverage_curve <- exdyn_coverage_curve(TX, T_P, coverage_breaks)
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
  accepted <- rep(FALSE, n_sims)
  for (i in seq_len(n_sims)) {
    theta <- prior_sampler()
    sim <- simulator(theta)
    S_sim <- summary_fn(sim)
    S_sim <- S_sim[names_obs]
    valid <- is.finite(S_sim) & is.finite(S_obs) & is.finite(scale)
    if (!any(valid)) {
      dist <- Inf
    } else {
      dist <- sqrt(sum(((S_sim[valid] - S_obs[valid]) / scale[valid])^2))
    }
    theta_list[[i]] <- theta
    summary_list[[i]] <- S_sim
    dist_vec[i] <- dist
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
    distance = dist_vec
  ) %>%
    dplyr::mutate(parameters = theta_list, summaries = summary_list)
  list(
    samples = samples,
    summaries = summaries,
    distances = dist_vec[accepted_idx],
    all = all_log,
    eps = eps,
    scale = scale
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
