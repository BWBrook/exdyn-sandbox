test_that("abc rejection ignores non-finite summary dimensions when finite ones remain", {
  S_obs <- c(a = 1, b = 2)
  res <- exdyn_abc_rejection(
    S_obs = S_obs,
    prior_sampler = function() list(alpha = 0.1),
    simulator = function(theta) list(theta = theta),
    summary_fn = function(sim) c(a = 1.5, b = NA_real_),
    n_sims = 1,
    eps = 0.6,
    scale = c(a = 1, b = 1),
    progress = FALSE
  )

  expect_equal(res$distances, 0.5)
  expect_equal(nrow(res$samples), 1)
  expect_equal(res$all$distance[[1]], 0.5)
})

test_that("abc rejection rejects draws when all summary dimensions are non-finite", {
  S_obs <- c(a = 1, b = 2)
  res <- exdyn_abc_rejection(
    S_obs = S_obs,
    prior_sampler = function() list(alpha = 0.1),
    simulator = function(theta) list(theta = theta),
    summary_fn = function(sim) c(a = NA_real_, b = NA_real_),
    n_sims = 1,
    eps = 1,
    scale = c(a = 1, b = 1),
    progress = FALSE
  )

  expect_equal(nrow(res$samples), 0)
  expect_true(is.infinite(res$all$distance[[1]]))
})
