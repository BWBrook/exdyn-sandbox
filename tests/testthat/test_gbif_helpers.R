test_that("target group helper supports multiple taxa", {
  taxa <- list(
    list(name = "Mustelidae", rank = "FAMILY"),
    list(name = "Arvicolinae", rank = "SUBFAMILY")
  )
  counts <- c(Mustelidae = 2L, Arvicolinae = 0L)
  keys <- c(Mustelidae = 123L, Arvicolinae = NA_integer_)

  df <- testthat::with_mocked_bindings(
    exdyn_gbif_usage_key = function(sci, rank = "SPECIES") {
      keys[[sci]]
    },
    exdyn_gbif_fetch = function(key, country, year_min, year_max,
                                cache_dir = "data/raw/gbif",
                                max_records = 200000,
                                force = FALSE) {
      tibble::tibble(
        decimalLongitude = seq_len(counts[["Mustelidae"]]),
        decimalLatitude = seq_len(counts[["Mustelidae"]]),
        year = rep(year_min, counts[["Mustelidae"]]),
        month = 1,
        day = 1,
        basisOfRecord = "HUMAN_OBSERVATION",
        occurrenceID = paste0("occ_", seq_len(counts[["Mustelidae"]])),
        catalogNumber = paste0("cat_", seq_len(counts[["Mustelidae"]])),
        recordedBy = NA_character_,
        coordinateUncertaintyInMeters = NA_real_,
        issue = NA_character_,
        issues = NA_character_
      )
    },
    exdyn_gbif_clean = function(df) {
      tibble::tibble(
        lon = df$decimalLongitude,
        lat = df$decimalLatitude,
        year = df$year,
        month = df$month,
        day = df$day,
        basisOfRecord = df$basisOfRecord,
        occurrenceID = df$occurrenceID,
        catalogNumber = df$catalogNumber,
        coordinateUncertaintyInMeters = df$coordinateUncertaintyInMeters
      )
    },
    suppressWarnings(exdyn_gbif_target_group(
      taxa = taxa,
      country = "GB",
      years = c(2020L, 2020L),
      max_records = 50,
      cache_dir = tempdir()
    ))
  )
  expect_true("effort_taxon" %in% names(df))
  expect_equal(nrow(df), counts[["Mustelidae"]])
  expect_true(all(df$effort_taxon == "Mustelidae"))
  expect_equal(unname(attr(df, "usage_key")), c(123, NA))
})
