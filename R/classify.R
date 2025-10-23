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

#' Identify driver-aware and response-only feature sets
#' @export
exdyn_feature_sets <- function(df) {
  required_cols <- c("exp_id", "species", "scenario", "predation_type", "replicate")
  missing <- setdiff(required_cols, names(df))
  if (length(missing)) {
    stop(sprintf("Missing required columns for feature selection: %s", paste(missing, collapse = ", ")))
  }
  numeric_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  meta_numeric <- c("po_n", "foss_n", "alpha", "presence_rate")
  resp_cols <- grep("^resp_", numeric_cols, value = TRUE)
  driver_cols <- setdiff(numeric_cols, resp_cols)
  driver_cols <- setdiff(driver_cols, meta_numeric)
  resp_cols <- setdiff(resp_cols, meta_numeric)

  if (!length(driver_cols)) stop("No driver-aware numeric features available.")
  if (!length(resp_cols)) stop("No response-only numeric features available.")

  if (any(grepl("(P|H|arrival|xcorr_)", resp_cols))) {
    stop("Response-only feature set leaks driver information.")
  }
  if (!any(grepl("(P|H|arrival|xcorr_)", driver_cols))) {
    warning("Driver-aware features lack explicit driver metrics; check configuration.", call. = FALSE)
  }

  list(
    driver_aware = driver_cols,
    response_only = resp_cols
  )
}

#' Train candidate models on provided splits
#' @keywords internal
exdyn_train_candidates <- function(train_x, train_y, test_x, test_truth, features, seed) {
  set.seed(seed)
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
  ranger_importance <- tibble::tibble(
    feature = names(ranger_model$variable.importance),
    importance = as.numeric(ranger_model$variable.importance)
  )
  ranger_conf <- exdyn_confusion(ranger_pred_tbl)

  train_mat <- as.matrix(train_x)
  test_mat <- as.matrix(test_x)
  glmnet_result <- tryCatch({
    cv <- glmnet::cv.glmnet(
      x = train_mat,
      y = train_y,
      family = "multinomial",
      type.measure = "class",
      nfolds = 5
    )
    est <- as.vector(predict(cv, newx = test_mat, s = "lambda.1se", type = "class"))
    pred_tbl <- tibble::tibble(
      truth = test_truth,
      estimate = factor(est, levels = levels(train_y))
    )
    coef_list <- glmnet::coef.glmnet(cv$glmnet.fit, s = cv$lambda.1se)
    coef_mat <- do.call(cbind, lapply(coef_list, function(mat) as.numeric(mat[-1, , drop = FALSE])))
    rownames(coef_mat) <- rownames(coef_list[[1]])[-1]
    importance <- tibble::tibble(
      feature = rownames(coef_mat),
      importance = apply(abs(coef_mat), 1, max, na.rm = TRUE)
    )
    list(
      model = cv,
      predictions = pred_tbl,
      importance = importance,
      confusion = exdyn_confusion(pred_tbl)
    )
  }, error = function(e) {
    warning(sprintf("glmnet fallback: %s", conditionMessage(e)), call. = FALSE)
    fallback_class <- levels(train_y)[which.max(table(train_y))]
    fallback_est <- factor(rep(fallback_class, length(test_truth)), levels = levels(train_y))
    pred_tbl <- tibble::tibble(truth = test_truth, estimate = fallback_est)
    list(
      model = NULL,
      predictions = pred_tbl,
      importance = tibble::tibble(feature = features, importance = NA_real_),
      confusion = exdyn_confusion(pred_tbl)
    )
  })

  list(
    ranger = list(
      model = ranger_model,
      predictions = ranger_pred_tbl,
      confusion = ranger_conf,
      importance = ranger_importance,
      macro_f1 = ranger_conf$macro_f1
    ),
    glmnet = glmnet_result
  )
}

#' Fit balanced ranger and cross-validated glmnet, returning best performer
#' @export
exdyn_fit_and_eval <- function(df, features, target = "scenario", seed = 321) {
  stopifnot(length(features) > 0, target %in% names(df))
  if (!nrow(df)) stop("No rows supplied to classifier.")

  data <- tibble::as_tibble(df)
  feature_df <- data[, features, drop = FALSE]
  feature_df <- exdyn_fill_na(feature_df)
  outcome <- factor(data[[target]])
  full_data <- data.frame(feature_df, scenario = outcome, check.names = FALSE)

  set.seed(seed)
  split <- rsample::initial_split(full_data, prop = 0.7, strata = "scenario")
  train_data <- rsample::training(split)
  test_data <- rsample::testing(split)

  train_x <- train_data[, features, drop = FALSE]
  train_y <- factor(train_data$scenario)
  test_x <- test_data[, features, drop = FALSE]
  test_truth <- factor(test_data$scenario, levels = levels(train_y))

  candidates <- exdyn_train_candidates(train_x, train_y, test_x, test_truth, features, seed)

  scores <- c(
    ranger = candidates$ranger$macro_f1,
    glmnet = candidates$glmnet$confusion$macro_f1
  )
  scores[is.na(scores)] <- -Inf
  best_label <- names(scores)[which.max(scores)]

  if (best_label == "ranger") {
    primary <- list(
      label = "ranger",
      model = candidates$ranger$model,
      predictions = candidates$ranger$predictions,
      confusion = candidates$ranger$confusion,
      importance = candidates$ranger$importance,
      macro_f1 = candidates$ranger$macro_f1
    )
  } else {
    primary <- list(
      label = "glmnet",
      model = candidates$glmnet$model,
      predictions = candidates$glmnet$predictions,
      confusion = candidates$glmnet$confusion,
      importance = candidates$glmnet$importance,
      macro_f1 = candidates$glmnet$confusion$macro_f1
    )
  }

  list(
    features = features,
    primary = primary,
    ranger = candidates$ranger,
    glmnet = candidates$glmnet
  )
}

#' Cross-validated macro-F1 and predictions (helper for power experiments)
#' @export
exdyn_cv_macro_f1 <- function(df, features, target = "scenario", v = 3, seed = 321) {
  stopifnot(length(features) > 0, target %in% names(df))
  data <- tibble::as_tibble(df)
  all_levels <- levels(factor(data[[target]]))
  feature_df <- exdyn_fill_na(data[, features, drop = FALSE])
  others <- dplyr::select(data, -dplyr::all_of(features))
  cv_data <- dplyr::bind_cols(feature_df, others)

  set.seed(seed)
  folds <- rsample::vfold_cv(cv_data, v = v, strata = target)

  pred_rows <- purrr::map2_dfr(folds$splits, seq_along(folds$splits), function(split, idx) {
    train <- rsample::analysis(split)
    assess <- rsample::assessment(split)
    train_x <- train[, features, drop = FALSE]
    train_y <- factor(train[[target]], levels = all_levels)
    test_x <- assess[, features, drop = FALSE]
    test_truth <- factor(assess[[target]], levels = all_levels)
    candidates <- exdyn_train_candidates(train_x, train_y, test_x, test_truth, features, seed + idx)
    scores <- c(
      ranger = candidates$ranger$macro_f1,
      glmnet = candidates$glmnet$confusion$macro_f1
    )
    scores[is.na(scores)] <- -Inf
    best <- names(scores)[which.max(scores)]
    pred_tbl <- if (best == "ranger") {
      candidates$ranger$predictions
    } else {
      candidates$glmnet$predictions
    }
    assess_meta <- assess %>%
      dplyr::select(dplyr::any_of(c("exp_id", "presence_rate", "alpha", "species", "scenario")))
    dplyr::bind_cols(
      assess_meta,
      tibble::tibble(
        truth = factor(pred_tbl$truth, levels = all_levels),
        estimate = factor(pred_tbl$estimate, levels = all_levels),
        fold = idx,
        model = best
      )
    )
  })

  power_summary <- pred_rows %>%
    dplyr::group_by(presence_rate, alpha) %>%
    dplyr::summarise(
      macro_f1 = {
        df_group <- tibble::tibble(
          truth = factor(truth, levels = all_levels),
          estimate = factor(estimate, levels = all_levels)
        )
        yardstick::f_meas(df_group, truth, estimate, estimator = "macro")$.estimate
      },
      .groups = "drop"
    )

  list(
    predictions = pred_rows,
    summary = power_summary
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
