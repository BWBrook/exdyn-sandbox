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
  per_page <- min(500, max_records, 500L)
  offset <- 0
  out <- list()
  repeat {
    resp <- httr::GET(
      url = "https://api.gbif.org/v1/occurrence/search",
      query = list(
        taxonKey = key,
        country = country,
        year = paste(year_min, year_max, sep = ","),
        hasCoordinate = "true",
        limit = per_page,
        offset = offset
      )
    )
    httr::stop_for_status(resp)
    payload <- jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"), simplifyDataFrame = TRUE)
    results <- payload$results
    if (length(results) == 0) break
    df <- tibble::as_tibble(results, .name_repair = "minimal")
    wanted_fields <- c(
      "decimalLongitude", "decimalLatitude", "year", "month", "day",
      "basisOfRecord", "occurrenceID", "catalogNumber", "recordedBy",
      "coordinateUncertaintyInMeters", "issue", "issues"
    )
    missing_cols <- setdiff(wanted_fields, names(df))
    if (length(missing_cols)) {
      for (nm in missing_cols) df[[nm]] <- NA
    }
    df <- df[, wanted_fields, drop = FALSE]
    out[[length(out) + 1]] <- df
    returned <- length(results)
    offset <- offset + returned
    total_count <- payload$count %||% Inf
    message(sprintf(
      "  fetched %d of ~%s (batch=%d)",
      offset,
      ifelse(is.finite(total_count), total_count, "?"),
      returned
    ))
    if (offset >= total_count || offset >= max_records) {
      break
    }
    Sys.sleep(0.1)
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
    raw <- dplyr::group_by(raw, year)
    raw <- dplyr::group_modify(raw, function(df, ...) {
      size <- min(per_year, nrow(df))
      if (size >= nrow(df)) {
        df
      } else {
        df[sample.int(nrow(df), size = size), , drop = FALSE]
      }
    })
    raw <- dplyr::ungroup(raw)
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

  clean <- df |>
    dplyr::rename(
      lon = decimalLongitude,
      lat = decimalLatitude
    ) |>
    dplyr::mutate(
      issue = as.character(issue_values),
      issue = dplyr::coalesce(issue, "")
    ) |>
    dplyr::filter(
      !is.na(lon), !is.na(lat), !is.na(year),
      basisOfRecord %in% c("HUMAN_OBSERVATION", "OBSERVATION", "PRESERVED_SPECIMEN"),
      !stringr::str_detect(issue, paste(issues_bad, collapse = "|"))
    ) |>
    dplyr::distinct(
      occurrenceID, catalogNumber, lon, lat, year, month, day,
      .keep_all = TRUE
    ) |>
    dplyr::select(
      lon, lat, year, month, day,
      basisOfRecord, occurrenceID, catalogNumber,
      coordinateUncertaintyInMeters
    ) |>
    dplyr::mutate(
      catalogNumber = as.character(catalogNumber),
      occurrenceID = as.character(occurrenceID),
      basisOfRecord = as.character(basisOfRecord),
      coordinateUncertaintyInMeters = as.numeric(coordinateUncertaintyInMeters)
    )

  clean
}
