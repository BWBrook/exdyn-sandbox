skip_if_not_installed("rgbif")

has_internet <- function() {
  if (!requireNamespace("curl", quietly = TRUE)) {
    return(TRUE)
  }
  curl::has_internet()
}

test_that("target group helper supports multiple taxa", {
  if (!has_internet()) {
    skip("no internet connection for GBIF lookup")
  }
  taxa <- list(
    list(name = "Mustelidae", rank = "FAMILY"),
    list(name = "Arvicolinae", rank = "SUBFAMILY")
  )
  df <- exdyn_gbif_target_group(
    taxa = taxa,
    country = "GB",
    years = c(2020L, 2020L),
    max_records = 50,
    cache_dir = tempdir()
  )
  expect_true("effort_taxon" %in% names(df) || nrow(df) == 0)
  if (nrow(df)) {
    expect_true(all(df$effort_taxon %in% c("Mustelidae", "Arvicolinae")))
  }
})
