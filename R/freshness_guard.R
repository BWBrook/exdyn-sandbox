# Output freshness guardrails (internal)

exdyn_freshness_guard <- function(output_paths, config_path, label = "output") {
  output_paths <- output_paths %||% character()
  output_paths <- output_paths[file.exists(output_paths)]
  if (!length(output_paths) || is.null(config_path) || !file.exists(config_path)) {
    return(TRUE)
  }
  cfg_time <- file.mtime(config_path)
  stale <- output_paths[file.mtime(output_paths) < cfg_time]
  if (length(stale)) {
    stop(sprintf("stale %s(s) detected: %s", label, paste(basename(stale), collapse = ", ")))
  }
  TRUE
}
