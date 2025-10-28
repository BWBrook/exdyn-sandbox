#' Memory log helper
#'
#' Emits a simple GC and RSS summary to the log. Intended for debugging
#' long-running simulations to detect runaway allocations.
#'
#' @param tag Label to include in the log message.
#' @keywords internal
#' @export
exdyn_mem_log <- function(tag = "") {
  info <- utils::gc()
  rss_kb <- tryCatch(
    as.numeric(system("awk '/VmRSS/ {print $2}' /proc/self/status", intern = TRUE)),
    error = function(...) NA_real_
  )
  rss_mb <- if (is.na(rss_kb)) NA_real_ else rss_kb / 1024
  total_mb <- sum(info[, "used"]) / 1024
  msg <- sprintf("[mem] %s GC=%.1f MB RSS=%s MB",
                 tag,
                 total_mb,
                 if (is.na(rss_mb)) "NA" else sprintf("%.1f", rss_mb))
  message(msg)
  invisible(list(gc_mb = total_mb, rss_mb = rss_mb))
}
