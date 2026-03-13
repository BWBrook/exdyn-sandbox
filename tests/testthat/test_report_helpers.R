test_that("effort taxa helper normalises mixed config styles", {
  tbl <- exdyn.sandbox:::exdyn_effort_taxa_table(list(
    list(name = "Mustelidae", rank = "FAMILY"),
    list("Microtus", "GENUS")
  ))

  expect_equal(tbl$name, c("Mustelidae", "Microtus"))
  expect_equal(tbl$rank, c("FAMILY", "GENUS"))
})

test_that("report metric helper summarizes tx coverage and lag", {
  df <- tibble::tibble(
    tx_obs = c(2004, 2006, NA_real_, 2008),
    T_P = c(2000, 2002, 2004, 2005)
  )

  metrics <- exdyn.sandbox:::exdyn_metrics_from_tx_df(df)

  expect_equal(metrics$n_units, 4)
  expect_equal(metrics$n_tx, 3)
  expect_equal(metrics$coverage, 0.75)
  expect_true(is.finite(metrics$lag_mean))
})
