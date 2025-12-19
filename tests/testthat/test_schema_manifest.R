test_that("schema version is defined", {
  expect_true(nzchar(exdyn_schema_version()))
})

test_that("manifest validation catches missing required fields", {
  manifest <- list(schema_version = exdyn_schema_version())
  expect_error(exdyn_validate_manifest(manifest), "missing required fields")
})
