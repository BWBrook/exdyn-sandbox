#' GBIF helper utilities
#'
#' Functions to look up usage keys, download and cache occurrence records,
#' and perform lightweight cleaning prior to gridding.
#'
#' @name gbif_connect
NULL

#' Lookup a GBIF usage key for a scientific name
#'
#' @param sci Scientific name as a character string.
#' @param rank Taxonomic rank (default \code{"SPECIES"}).
#'
#' @return Integer usage key if found, otherwise \code{NA_integer_}.
#' @export
exdyn_gbif_usage_key <- function(sci, rank = "SPECIES") {
  stopifnot(is.character(sci), length(sci) == 1)
  res <- rgbif::name_backbone(name = sci, rank = rank)
  key <- res$usageKey %||% NA_integer_
  if (is.na(key)) {
    warning("No GBIF usage key found for: ", sci)
  }
  key
}

#' Fetch GBIF occurrences with caching
#'
#' @param key Usage key (integer).
#' @param country Two-letter country code.
#' @param year_min Minimum year (inclusive).
#' @param year_max Maximum year (inclusive).
#' @param cache_dir Directory for cached CSV files.
#' @param max_records Maximum records to retain (sampling by year if exceeded).
#' @param force If \code{TRUE}, force re-download even if cache exists.
#'
#' @return Tibble of raw occurrence records (selected columns only).
#' @export
exdyn_gbif_fetch <- function(key, country, year_min, year_max,
                             cache_dir = "data/raw/gbif",
                             max_records = 200000,
                             force = FALSE) {
  stopifnot(length(key) == 1, !is.na(key))
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  cache_file <- file.path(
    cache_dir,
    sprintf("%s_%s_%s_%s.csv.gz", key, country, year_min, year_max)
  )
  meta_file <- sub("\\.csv\\.gz$", "_meta.yaml", cache_file)

  if (!force && file.exists(cache_file)) {
    message("Reading GBIF cache: ", cache_file)
    raw <- readr::read_csv(cache_file, show_col_types = FALSE)
    return(raw)
  }

  message("Downloading GBIF occurrences for key ", key, " (", country, ")")
  per_page <- 200
  offset <- 0
  out <- list()
  repeat {
    query <- rgbif::occ_search(
      taxonKey = key,
      country = country,
      year = paste(year_min, year_max, sep = ","),
      hasCoordinate = TRUE,
      limit = per_page,
      start = offset,
      fields = c(
        "decimalLongitude", "decimalLatitude", "year", "month", "day",
        "basisOfRecord", "occurrenceID", "catalogNumber", "recordedBy",
        "coordinateUncertaintyInMeters", "issue", "issues"
      )
    )
    if (NROW(query$data) == 0) break
    out[[length(out) + 1]] <- tibble::as_tibble(query$data)
    returned <- query$meta$returned
    end_of_records <- isTRUE(query$meta$endOfRecords)
    if (!length(returned) || is.na(returned)) returned <- NROW(query$data)
    offset <- offset + returned
    total_count <- query$meta$count
    if (!length(total_count) || is.na(total_count)) total_count <- Inf
    if (end_of_records || returned < per_page || offset >= total_count) {
      break
    }
  }

  if (!length(out)) {
    warning("No GBIF records returned.")
    return(tibble::tibble())
  }

  raw <- dplyr::bind_rows(out)

  if (nrow(raw) > max_records) {
    message("Trimming records from ", nrow(raw), " to ", max_records, " (per-year sampling)")
    set.seed(42)
    n_years <- max(1L, dplyr::n_distinct(raw$year))
    per_year <- max(1L, max_records %/% n_years)
    raw <- raw %>%
      dplyr::group_by(year) %>%
      dplyr::group_modify(function(df, ...) {
        size <- min(per_year, nrow(df))
        if (size >= nrow(df)) {
          df
        } else {
          df[sample.int(nrow(df), size = size), , drop = FALSE]
        }
      }) %>%
      dplyr::ungroup()
  }

  readr::write_csv(raw, cache_file)
  yaml::write_yaml(
    list(
      key = key,
      country = country,
      year_min = year_min,
      year_max = year_max,
      n_records = nrow(raw),
      retrieved = Sys.time()
    ),
    meta_file
  )

  raw
}

#' Clean GBIF occurrences
#'
#' @param df Tibble of raw GBIF records (output of \code{exdyn_gbif_fetch}).
#'
#' @return Tibble with columns \code{lon, lat, year, month, day, basisOfRecord,
#' coordinateUncertaintyInMeters, occurrenceID, catalogNumber}.
#' @export
exdyn_gbif_clean <- function(df) {
  if (!nrow(df)) return(tibble::tibble())
  issues_bad <- c("COORDINATE_OUT_OF_RANGE", "ZERO_COORDINATE", "COUNTRY_COORDINATE_MISMATCH")
  issue_values <- if ("issue" %in% names(df)) {
    df$issue
  } else if ("issues" %in% names(df)) {
    df$issues
  } else {
    rep("", nrow(df))
  }

  clean <- df %>%
    dplyr::rename(
      lon = decimalLongitude,
      lat = decimalLatitude
    ) %>%
    dplyr::mutate(
      issue = as.character(issue_values),
      issue = dplyr::coalesce(issue, "")
    ) %>%
    dplyr::filter(
      !is.na(lon), !is.na(lat), !is.na(year),
      basisOfRecord %in% c("HUMAN_OBSERVATION", "OBSERVATION", "PRESERVED_SPECIMEN"),
      !stringr::str_detect(issue, paste(issues_bad, collapse = "|"))
    ) %>%
    dplyr::distinct(
      occurrenceID, catalogNumber, lon, lat, year, month, day,
      .keep_all = TRUE
    ) %>%
    dplyr::select(
      lon, lat, year, month, day,
      basisOfRecord, occurrenceID, catalogNumber,
      coordinateUncertaintyInMeters
    )

  clean
}
