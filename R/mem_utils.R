#' Memory log helper
#'
#' Emits a simple GC and RSS summary to the log. Intended for debugging
#' long-running simulations to detect runaway allocations.
#'
#' @param tag Label to include in the log message.
#' @keywords internal
#' @export
exdyn_mem_log <- function(tag = "") {
  info <- base::gc()
  rss_kb <- tryCatch(
    as.numeric(system("awk '/VmRSS/ {print $2}' /proc/self/status", intern = TRUE)),
    error = function(...) NA_real_
  )
  rss_mb <- if (is.na(rss_kb)) NA_real_ else rss_kb / 1024

  vc_mb <- info["Vcells", "used"] * 8 / (1024^2)
  ptr_size <- if (.Machine$sizeof.pointer == 8) 8 else 4
  nc_mb <- info["Ncells", "used"] * (2 * ptr_size) / (1024^2)
  gc_mb <- vc_mb + nc_mb

  msg <- sprintf("[mem] %s GC≈%.1f MB RSS=%s MB",
                 tag,
                 gc_mb,
                 if (is.na(rss_mb)) "NA" else sprintf("%.1f", rss_mb))
  message(msg)
  invisible(list(gc_mb = gc_mb, rss_mb = rss_mb))
}

#' Snapshot memory usage (GC + RSS)
#' @keywords internal
exdyn_mem_snapshot <- function() {
  info <- base::gc()
  rss_kb <- tryCatch(
    as.numeric(system("awk '/VmRSS/ {print $2}' /proc/self/status", intern = TRUE)),
    error = function(...) NA_real_
  )
  hwm_kb <- tryCatch(
    as.numeric(system("awk '/VmHWM/ {print $2}' /proc/self/status", intern = TRUE)),
    error = function(...) NA_real_
  )
  rss_mb <- if (is.na(rss_kb)) NA_real_ else rss_kb / 1024
  hwm_mb <- if (is.na(hwm_kb)) NA_real_ else hwm_kb / 1024

  vc_mb <- info["Vcells", "used"] * 8 / (1024^2)
  ptr_size <- if (.Machine$sizeof.pointer == 8) 8 else 4
  nc_mb <- info["Ncells", "used"] * (2 * ptr_size) / (1024^2)
  gc_mb <- vc_mb + nc_mb

  list(gc_mb = gc_mb, rss_mb = rss_mb, rss_peak_mb = hwm_mb)
}
