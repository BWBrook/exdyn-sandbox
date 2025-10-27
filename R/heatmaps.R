resolve_control <- function(nm) {
  aliases <- c(
    mean_km = "dispersal_mean_km",
    presence_only_rate = "presence_rate",
    pred_speed = "pred_speed",
    alpha = "alpha",
    allee_A_over_K = "allee_A_over_K"
  )
  if (nm %in% names(aliases)) aliases[[nm]] else nm
}

#' Bin controls and compute macro-F1 per cell
#'
#' @param oof Tibble of out-of-fold predictions with control metadata, truth, and estimate.
#' @param x,y Control names (aliases accepted).
#' @param bins Number of bins per axis (default 8).
#' @param min_n Minimum observations per cell required to compute macro-F1.
#' @return Tibble with columns describing bin ids, midpoints, widths, counts, and macro-F1.
#' @export
#' @importFrom dplyr mutate group_by summarise n
#' @importFrom tidyr complete
#' @importFrom forcats fct_inorder
#' @importFrom yardstick f_meas_vec
exdyn_bin_f1 <- function(oof, x, y, bins = 8, min_n = 5) {
  stopifnot(is.data.frame(oof))
  x_col <- resolve_control(x)
  y_col <- resolve_control(y)
  required <- c(x_col, y_col, "truth", "estimate")
  missing <- setdiff(required, names(oof))
  if (length(missing)) {
    stop("Missing columns in out-of-fold predictions: ", paste(missing, collapse = ", "))
  }
  df <- tibble::as_tibble(oof)
  levels_all <- levels(factor(df$truth))

  make_bins <- function(values, bins) {
    unique_n <- length(unique(values))
    if (unique_n <= 1) {
      mids <- mean(values, na.rm = TRUE)
      width_val <- max(1e-6, diff(range(values, na.rm = TRUE)))
      if (!is.finite(width_val) || width_val == 0) width_val <- max(1e-6, abs(mids))
      widths <- rep(width_val, 1)
      list(
        id = rep(1L, length(values)),
        mids = mids,
        widths = widths,
        breaks = c(mids - widths / 2, mids + widths / 2)
      )
    } else {
      bin_count <- max(1, min(bins, unique_n))
      min_val <- min(values, na.rm = TRUE)
      max_val <- max(values, na.rm = TRUE)
      if (min_val == max_val) {
        min_val <- min_val - 0.5
        max_val <- max_val + 0.5
      }
      breaks <- seq(min_val, max_val, length.out = bin_count + 1)
      ids <- findInterval(values, breaks, all.inside = TRUE)
      widths <- diff(breaks)
      mids <- (breaks[-1] + breaks[-length(breaks)]) / 2
      list(
        id = ids,
        mids = mids,
        widths = widths,
        breaks = breaks
      )
    }
  }

  x_info <- make_bins(df[[x_col]], bins)
  y_info <- make_bins(df[[y_col]], bins)
  df <- df %>%
    dplyr::mutate(
      x_id = x_info$id,
      y_id = y_info$id
    )

  all_x <- seq_along(x_info$mids)
  all_y <- seq_along(y_info$mids)

  cell <- df %>%
    dplyr::group_by(x_id, y_id) %>%
    dplyr::summarise(
      n = dplyr::n(),
      macro_f1 = {
        if (n() < min_n) {
          NA_real_
        } else {
          truth_vec <- factor(truth, levels = levels_all)
          estimate_vec <- factor(estimate, levels = levels_all)
          yardstick::f_meas_vec(truth_vec, estimate_vec, estimator = "macro")
        }
      },
      .groups = "drop"
    ) %>%
    tidyr::complete(
      x_id = all_x,
      y_id = all_y,
      fill = list(n = 0L, macro_f1 = NA_real_)
    ) %>%
    dplyr::mutate(
      x_mid = x_info$mids[pmax(pmin(x_id, length(x_info$mids)), 1)],
      y_mid = y_info$mids[pmax(pmin(y_id, length(y_info$mids)), 1)],
      x_width = x_info$widths[pmax(pmin(x_id, length(x_info$widths)), 1)],
      y_height = y_info$widths[pmax(pmin(y_id, length(y_info$widths)), 1)]
    )

  if (!is.null(x_info$breaks)) {
    x_labels <- sprintf("%.2f", x_info$mids)
    cell <- cell %>% dplyr::mutate(x_label = x_labels[pmax(pmin(x_id, length(x_labels)), 1)])
  }
  if (!is.null(y_info$breaks)) {
    y_labels <- sprintf("%.2f", y_info$mids)
    cell <- cell %>% dplyr::mutate(y_label = y_labels[pmax(pmin(y_id, length(y_labels)), 1)])
  }

  cell
}

#' Heatmap plot helper for sensitivity grids
#'
#' @param cell Output of `exdyn_bin_f1()`.
#' @param xlab,y labelling strings for axes.
#' @param title Plot title.
#' @return A ggplot object.
#' @export
exdyn_plot_heatmap <- function(cell, xlab, ylab, title = NULL) {
  if (!nrow(cell)) {
    stop("No data supplied to exdyn_plot_heatmap.")
  }
  breaks_x <- sort(unique(cell$x_mid))
  breaks_y <- sort(unique(cell$y_mid))
  label_fun <- function(vals) sprintf("%.2f", vals)

  ggplot2::ggplot(cell, ggplot2::aes(x = x_mid, y = y_mid, fill = macro_f1)) +
    ggplot2::geom_tile(ggplot2::aes(width = x_width, height = y_height), color = "white") +
    ggplot2::geom_text(
      data = subset(cell, is.na(macro_f1)),
      ggplot2::aes(label = paste0("n=", n)),
      size = 2.8,
      color = "grey30"
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "C",
      name = "Macro F1",
      limits = c(0.5, 1),
      na.value = "grey90"
    ) +
    ggplot2::scale_x_continuous(breaks = breaks_x, labels = label_fun(breaks_x)) +
    ggplot2::scale_y_continuous(breaks = breaks_y, labels = label_fun(breaks_y)) +
    ggplot2::labs(x = xlab, y = ylab, title = title) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(panel.grid = ggplot2::element_blank())
}
