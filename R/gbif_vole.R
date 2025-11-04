#' Species-level GBIF wrapper
#'
#' Fetches, caches, and cleans GBIF occurrence records for a target species.
#'
#' @param sci Scientific name.
#' @param rank Taxonomic rank (e.g. "SPECIES").
#' @param country Two-letter country code (ISO2).
#' @param years Integer vector of length 2 giving min/max years.
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

#' Targeted GBIF effort wrapper
#'
#' Fetches occurrences for broader effort taxa (e.g. families) to serve as
#' observation denominators. Supports either a single taxon via `group`/`rank`,
#' or a list of taxa supplied through `taxa`, where each element provides a
#' `name` and optional `rank`.
#'
#' @param group Scientific name of the taxon group (default \code{"Mammalia"}).
#'   Ignored when `taxa` is supplied.
#' @param rank Taxonomic rank (default \code{"CLASS"}). Ignored when `taxa` is
#'   supplied unless an entry omits its own rank.
#' @param taxa Optional list (or character vector) of taxa to fetch. Each entry
#'   may be a list containing `name` and `rank`, or a scalar character (default
#'   rank falls back to "SPECIES").
#' @param country Two-letter ISO country code.
#' @param years Integer vector of length 2 giving min/max year.
#' @param cache_dir Directory for cached CSVs.
#' @param max_records Maximum number of records to retain per taxon.
#' @param force Logical; re-download even if cache exists.
#'
#' @return Tibble with cleaned occurrences and a `effort_taxon` column. Adds a
#'   `usage_key` attribute (vector when multiple taxa are fetched).
#' @export
exdyn_gbif_target_group <- function(group = "Mammalia", rank = "CLASS",
                                    taxa = NULL,
                                    country,
                                    years,
                                    cache_dir = "data/raw/gbif",
                                    max_records = 200000,
                                    force = FALSE) {
  stopifnot(length(years) == 2)
  entries <- if (is.null(taxa)) {
    list(list(name = group, rank = rank))
  } else if (is.character(taxa)) {
    lapply(taxa, function(x) list(name = x, rank = "SPECIES"))
  } else if (is.list(taxa)) {
    purrr::map(taxa, function(x) {
      if (is.character(x)) {
        list(name = x, rank = "SPECIES")
      } else {
        list(
          name = x$name %||% x[[1]],
          rank = x$rank %||% x[[2]] %||% rank
        )
      }
    })
  } else {
    stop("`taxa` must be NULL, a character vector, or a list.")
  }

  fetch_one <- function(entry) {
    nm <- entry$name
    rk <- entry$rank %||% rank
    key <- exdyn_gbif_usage_key(nm, rk)
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
    if (!nrow(df)) {
      return(list(df = tibble::tibble(), key = key, name = nm))
    }
    df$effort_taxon <- nm
    list(df = df, key = key, name = nm)
  }

  fetched <- purrr::imap(entries, function(entry, idx) {
    res <- fetch_one(entry)
    if (idx < length(entries)) {
      Sys.sleep(0.2)
    }
    res
  })
  dfs <- purrr::map(fetched, "df")
  out <- dplyr::bind_rows(dfs)
  usage_keys <- purrr::map_dbl(fetched, "key")
  attr(out, "usage_key") <- usage_keys
  out
}
