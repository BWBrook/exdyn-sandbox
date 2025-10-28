#' Species-level GBIF wrapper
#'
#' Fetches, caches, and cleans GBIF occurrence records for a target species.
#'
#' @param sci Scientific name.
#' @param rank Taxonomic rank (e.g. "SPECIES").
#' @param country Two-letter country code (ISO2).
#' @param years Integer vector of length 2 giving [min, max] years.
#' @param cache_dir Directory where cached CSVs are stored.
#' @param max_records Maximum number of records to retain (per-year sampled if exceeded).
#' @param force Logical; re-download even if cache exists.
#'
#' @return Tibble with cleaned records (lon, lat, year, ...). Adds `usage_key` attribute.
#' @export
exdyn_gbif_species <- function(sci, rank, country, years,
                               cache_dir = "data/raw/gbif",
                               max_records = 200000,
                               force = FALSE) {
  stopifnot(length(years) == 2)
  key <- exdyn_gbif_usage_key(sci, rank)
  raw <- exdyn_gbif_fetch(
    key = key,
    country = country,
    year_min = years[1],
    year_max = years[2],
    cache_dir = cache_dir,
    max_records = max_records,
    force = force
  )
  df <- exdyn_gbif_clean(raw)
  attr(df, "usage_key") <- key
  df
}
