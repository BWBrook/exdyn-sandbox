# Canonical artefact helpers (internal)

exdyn_canonical_manifest_fields <- function() {
  c(
    "schema_version",
    "commit_sha",
    "run_id",
    "run_timestamp",
    "milestone",
    "wp_id",
    "config_snapshots",
    "seeds",
    "commands"
  )
}

exdyn_validate_manifest <- function(manifest, required_fields = exdyn_canonical_manifest_fields()) {
  if (!is.list(manifest)) {
    stop("manifest must be a list")
  }
  missing <- setdiff(required_fields, names(manifest))
  if (length(missing)) {
    stop("manifest missing required fields: ", paste(missing, collapse = ", "))
  }
  manifest
}

exdyn_write_manifest <- function(manifest, path) {
  exdyn_validate_manifest(manifest)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(manifest, path)
  path
}

exdyn_make_run_id <- function(prefix = "run") {
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  rand <- sprintf("%04d", sample.int(9999, 1))
  paste(prefix, stamp, rand, sep = "_")
}

exdyn_git_sha <- function() {
  sha <- tryCatch(system("git rev-parse HEAD", intern = TRUE), error = function(...) character())
  if (!length(sha)) {
    return(NA_character_)
  }
  trimws(sha[1])
}

exdyn_relative_path <- function(path, root = getwd()) {
  if (length(path) > 1) {
    return(vapply(path, exdyn_relative_path, character(1), root = root))
  }
  root <- normalizePath(root, winslash = "/", mustWork = FALSE)
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- gsub("/+$", "", root)
  if (startsWith(path, paste0(root, "/"))) {
    sub(paste0("^", root, "/"), "", path)
  } else {
    path
  }
}

exdyn_copy_to_canonical <- function(paths, canonical_dir, root = getwd()) {
  if (is.null(paths) || !length(paths)) {
    return(character())
  }
  out_paths <- character()
  for (path in paths) {
    if (is.na(path) || !nzchar(path)) next
    if (dir.exists(path)) {
      files <- list.files(path, recursive = TRUE, full.names = TRUE)
      files <- files[!dir.exists(files)]
    } else {
      files <- path
    }
    for (file in files) {
      if (!file.exists(file)) next
      rel <- exdyn_relative_path(file, root)
      dest <- file.path(canonical_dir, rel)
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      file.copy(file, dest, overwrite = TRUE)
      out_paths <- c(out_paths, dest)
    }
  }
  unique(out_paths)
}

exdyn_write_session_info <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  capture.output(sessionInfo(), file = path)
  path
}

exdyn_write_config_snapshot <- function(cfg, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(cfg, path)
  path
}

exdyn_canonical_run_dir <- function(root, milestone, wp_id, run_id) {
  dir <- file.path(root, milestone, wp_id, run_id)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}
