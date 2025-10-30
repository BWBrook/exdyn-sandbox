Sys.setenv(
  OMP_NUM_THREADS = "1",
  MKL_NUM_THREADS = "1",
  OPENBLAS_NUM_THREADS = "1"
)

if (requireNamespace("RhpcBLASctl", quietly = TRUE)) {
  RhpcBLASctl::blas_set_num_threads(1)
  RhpcBLASctl::omp_set_num_threads(1)
}

options(mc.cores = parallel::detectCores())

# Parallel plan below is only used when calling targets::tar_make_future();
# regular tar_make() still runs sequentially with these BLAS thread caps.
future::plan(
  future::multicore,
  workers = max(1, min(6, parallel::detectCores()))
)
