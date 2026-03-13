# 047 — Aggressive Refactor Slice (Low/Medium Risk Only)

Date: 2026-03-13

## Scope completed

- Fixed package-test entrypoint naming in `tests/testthat.R`.
- Added `make check` as a package smoke path and wired it into CI.
- Added/updated characterization tests around plotting/report helpers.
- Extracted shared TX/T_P comparison helpers into `R/tx_compare.R`.
- Split synthetic gate and recovery-table helpers out of `R/synthetic_recovery.R`.
- Moved plotting helpers out of `R/pilot_mink_vole.R` into `R/plots_realdata.R`.
- Moved report-only helper logic into `R/report_helpers.R` and thinned pilot/synthetic reports.
- Removed dead legacy helpers `exdyn_simulate_params()` and `exdyn_screen_and_rank()`.

## Sanity checks

- `make test`:
  - PASS 289, FAIL 0, WARN 0, SKIP 0
- `make check`:
  - package smoke path runs successfully via `devtools::check(document = FALSE, manual = FALSE, error_on = "error", args = c("--no-tests"))`
  - warnings/notes are now visible rather than hidden
  - main remaining package debt categories are:
    - non-ASCII code comments/strings
    - stale/incomplete Rd argument docs
    - import/global-variable hygiene for `%>%`, `.data`, `.env`, and assorted helpers

## Interpretation

- This slice improved engineering leverage without changing the tested scientific behavior.
- The package/test harness was weaker than it looked: `devtools::test()` was green while `tests/testthat.R` was actually broken.
- The biggest code-health win was reducing duplication around TX/T_P comparison and shrinking the responsibility footprint of `R/synthetic_recovery.R` and `R/pilot_mink_vole.R`.
- Report-local analysis code was doing too much; moving that logic into R helpers makes future report changes less risky.
- The package smoke check now provides honest signal about packaging debt, but that debt is orthogonal to the main synthetic/ABC scientific problems.

## Next follow-up

- Stop at the planned high-risk checkpoint before changing numerical or scientific semantics.
- Next redesign memo should cover:
  - one coherent objective model for screen / ABC / real-data fitting
  - strict response-only vs driver-conditioned metric families
  - whether to retire the legacy weighted `exdyn_score()` objective
