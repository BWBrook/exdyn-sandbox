skip_if_not_installed("sf")

fixture_path <- system.file("extdata", "gbif_mink_gb_small.csv", package = "exdyn.sandbox", mustWork = TRUE)
raw_fixture <- readr::read_csv(fixture_path, show_col_types = FALSE)

test_that("exdyn_gbif_clean drops invalid rows and deduplicates", {
  clean <- exdyn_gbif_clean(raw_fixture)
  expect_true(nrow(clean) < nrow(raw_fixture))
  expect_true(all(!is.na(clean$lon)))
  expect_false(any(stringr::str_detect(clean$basisOfRecord, "COUNTRY_COORDINATE_MISMATCH")))
  expect_equal(sum(clean$occurrenceID == "occ-1"), 1)
  expect_equal(sum(clean$occurrenceID == "occ-4"), 1)
})

test_that("exdyn_points_to_grid assigns most points inside GB grid", {
  clean <- exdyn_gbif_clean(raw_fixture)
  grid <- exdyn_make_grid(country_code = "GB", cell_km = 200, crs_out = "EPSG:27700")
  cells <- exdyn_points_to_grid(clean, grid)
  expect_gt(nrow(cells), 0)
  expect_gt(mean(!is.na(cells$cell_id)), 0.9)
})
