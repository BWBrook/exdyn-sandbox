#' Fill missing numeric values with column means
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

#' Prepare feature set for classifiers
#' @keywords internal
exdyn_prepare_features <- function(df) {
  drops <- c("exp_id", "species", "predation_type", "replicate", "scenario", "po_n", "foss_n")
  keep_numeric <- vapply(df, is.numeric, logical(1))
  feature_names <- setdiff(names(df)[keep_numeric], drops)
  if (!length(feature_names)) stop("No numeric features available for classifier.")
  feature_df <- df[, feature_names, drop = FALSE]
  feature_df <- exdyn_fill_na(feature_df)
  list(features = feature_names, matrix = feature_df)
}

#' Fit balanced ranger and cross-validated glmnet classifiers
#' @export
exdyn_fit_classifier <- function(df, seed = 321) {
  stopifnot("scenario" %in% names(df))
  if (!nrow(df)) stop("No rows supplied to classifier.")
  prep <- exdyn_prepare_features(df)
  feature_df <- prep$matrix
  feature_names <- prep$features
  scenario <- factor(df$scenario)
  set.seed(seed)
  split <- rsample::initial_split(data.frame(feature_df, scenario = scenario), prop = 0.7, strata = scenario)
  train_data <- rsample::training(split)
  test_data <- rsample::testing(split)
  train_x <- train_data[, feature_names, drop = FALSE]
  train_y <- factor(train_data$scenario)
  test_x <- test_data[, feature_names, drop = FALSE]
  test_truth <- factor(test_data$scenario, levels = levels(train_y))

  # ranger model with class weights
  freq <- table(train_y)
  weights <- length(train_y) / (length(freq) * as.numeric(freq))
  names(weights) <- names(freq)
  ranger_model <- ranger::ranger(
    dependent.variable.name = "scenario",
    data = data.frame(scenario = train_y, train_x),
    probability = TRUE,
    importance = "impurity",
    num.trees = 800,
    class.weights = weights,
    seed = seed
  )
  ranger_pred_probs <- predict(ranger_model, data = data.frame(test_x))$predictions
  ranger_estimate <- colnames(ranger_pred_probs)[max.col(ranger_pred_probs, ties.method = "first")]
  ranger_pred_tbl <- tibble::tibble(
    truth = test_truth,
    estimate = factor(ranger_estimate, levels = levels(train_y))
  )
  ranger_macro_f1 <- yardstick::f_meas(ranger_pred_tbl, truth, estimate, estimator = "macro")$.estimate
  ranger_importance <- tibble::tibble(
    feature = names(ranger_model$variable.importance),
    importance = as.numeric(ranger_model$variable.importance)
  )

  # glmnet multinomial with 5-fold CV
  train_mat <- as.matrix(train_x)
  test_mat <- as.matrix(test_x)
  glmnet_result <- tryCatch({
    cv <- glmnet::cv.glmnet(
      train_mat,
      train_y,
      family = "multinomial",
      type.measure = "class",
      nfolds = 5
    )
    est <- as.vector(predict(cv, newx = test_mat, s = "lambda.1se", type = "class"))
    pred_tbl <- tibble::tibble(
      truth = test_truth,
      estimate = factor(est, levels = levels(train_y))
    )
    macro <- yardstick::f_meas(pred_tbl, truth, estimate, estimator = "macro")$.estimate
    coef_list <- glmnet::coef.glmnet(cv$glmnet.fit, s = cv$lambda.1se)
    coef_mat <- do.call(cbind, lapply(coef_list, function(mat) as.numeric(mat[-1, , drop = FALSE])))
    rownames(coef_mat) <- rownames(coef_list[[1]])[-1]
    importance <- tibble::tibble(
      feature = rownames(coef_mat),
      importance = apply(abs(coef_mat), 1, max, na.rm = TRUE)
    )
    list(model = cv, predictions = pred_tbl, macro_f1 = macro, importance = importance)
  }, error = function(e) {
    warning(sprintf("glmnet fallback: %s", conditionMessage(e)), call. = FALSE)
    fallback_class <- levels(train_y)[which.max(table(train_y))]
    fallback_est <- factor(rep(fallback_class, length(test_truth)), levels = levels(train_y))
    pred_tbl <- tibble::tibble(truth = test_truth, estimate = fallback_est)
    list(
      model = NULL,
      predictions = pred_tbl,
      macro_f1 = NA_real_,
      importance = tibble::tibble(feature = feature_names, importance = NA_real_)
    )
  })

  list(
    features = feature_names,
    levels = levels(train_y),
    ranger = list(
      model = ranger_model,
      predictions = ranger_pred_tbl,
      macro_f1 = ranger_macro_f1,
      importance = ranger_importance
    ),
    glmnet = list(
      model = glmnet_result$model,
      predictions = glmnet_result$predictions,
      macro_f1 = glmnet_result$macro_f1,
      importance = glmnet_result$importance
    )
  )
}

#' Compute confusion metrics from prediction tibble
#' @export
exdyn_confusion <- function(pred_tbl) {
  pred_tbl <- tibble::as_tibble(pred_tbl)
  stopifnot(all(c("truth", "estimate") %in% names(pred_tbl)))
  truth <- factor(pred_tbl$truth)
  estimate <- factor(pred_tbl$estimate, levels = levels(truth))
  tab <- table(truth, estimate)
  confusion_df <- tibble::as_tibble(as.data.frame(tab))
  names(confusion_df) <- c("truth", "estimate", "n")
  recalls <- diag(tab) / pmax(1, rowSums(tab))
  precisions <- diag(tab) / pmax(1, colSums(tab))
  per_class <- tibble::tibble(
    scenario = levels(truth),
    precision = as.numeric(precisions[levels(truth)]),
    recall = as.numeric(recalls)
  )
  pred_tbl_eval <- tibble::tibble(truth = truth, estimate = estimate)
  overall_acc <- yardstick::accuracy(pred_tbl_eval, truth, estimate)
  macro_f1 <- yardstick::f_meas(pred_tbl_eval, truth, estimate, estimator = "macro")$.estimate
  list(
    confusion = confusion_df,
    per_class = per_class,
    overall = tibble::tibble(metric = "accuracy", estimate = overall_acc$.estimate),
    macro_f1 = macro_f1
  )
}
