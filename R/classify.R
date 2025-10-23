#' Fit ranger classifier on summaries
#' @export
exdyn_fit_classifier <- function(df, seed = 321) {
  stopifnot("scenario" %in% names(df))
  if (!nrow(df)) stop("No rows supplied to classifier.")
  numeric_cols <- vapply(df, is.numeric, logical(1))
  ignored <- names(df) %in% c("exp_id", "species", "predation_type", "replicate", "scenario")
  features <- names(df)[numeric_cols & !ignored]
  if (!length(features)) stop("No numeric features available for classifier.")
  set.seed(seed)
  n <- nrow(df)
  train_n <- max(1, floor(0.7 * n))
  train_idx <- sort(sample(seq_len(n), size = train_n))
  train_data <- df[train_idx, features, drop = FALSE]
  train_data <- exdyn_fill_na(train_data)
  train_df <- data.frame(
    scenario = factor(df$scenario[train_idx]),
    train_data,
    check.names = FALSE
  )
  model <- ranger::ranger(
    dependent.variable.name = "scenario",
    data = train_df,
    probability = TRUE,
    importance = "impurity",
    num.trees = 500,
    seed = seed
  )
  list(
    model = model,
    features = features,
    train_idx = train_idx,
    levels = levels(train_df$scenario)
  )
}

#' Confusion matrix from held-out predictions
#' @export
exdyn_confusion <- function(df, clf) {
  idx <- setdiff(seq_len(nrow(df)), clf$train_idx)
  if (!length(idx)) idx <- clf$train_idx
  newdata <- df[idx, clf$features, drop = FALSE]
  newdata <- exdyn_fill_na(newdata)
  preds <- predict(clf$model, data = newdata)$predictions
  pred_class <- colnames(preds)[max.col(preds, ties.method = "first")]
  truth <- factor(df$scenario[idx], levels = clf$levels)
  estimate <- factor(pred_class, levels = clf$levels)
  pred_tbl <- tibble::tibble(truth = truth, estimate = estimate)
  confusion_df <- tibble::as_tibble(as.data.frame(table(truth, estimate)))
  names(confusion_df) <- c("truth", "estimate", "n")
  tab <- table(truth, estimate)
  recall <- diag(tab) / pmax(1, rowSums(tab))
  precision <- diag(tab) / pmax(1, colSums(tab))
  per_class <- tibble::tibble(
    scenario = clf$levels,
    recall = recall,
    precision = precision
  )
  overall <- yardstick::accuracy(pred_tbl, truth, estimate)
  importance <- tibble::tibble(
    feature = names(clf$model$variable.importance),
    importance = as.numeric(clf$model$variable.importance)
  )
  list(
    predictions = pred_tbl,
    confusion = confusion_df,
    per_class = per_class,
    overall = tibble::tibble(metric = "accuracy", estimate = overall$.estimate),
    importance = importance
  )
}

#' Fill NA with column means
#' @keywords internal
exdyn_fill_na <- function(df) {
  for (nm in names(df)) {
    col <- df[[nm]]
    if (is.numeric(col)) {
      mean_val <- mean(col, na.rm = TRUE)
      if (is.na(mean_val)) mean_val <- 0
      col[is.na(col)] <- mean_val
      df[[nm]] <- col
    }
  }
  df
}
