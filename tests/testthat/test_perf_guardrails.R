test_that("perf smoke guardrail stays within generous limits", {
  res <- exdyn_perf_guardrail_run()
  expect_true(is.finite(res$runtime_sec))
  expect_lt(res$runtime_sec, 60)
  if (is.finite(res$peak_rss_mb)) {
    expect_lt(res$peak_rss_mb, 2000)
  }
})

test_that("schema version is pinned for guardrails", {
  expect_equal(exdyn_schema_version(), "0.3.2")
})
