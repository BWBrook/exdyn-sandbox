.PHONY: init test run report report-leak report-qa exp report-id report-sens pilot pilot-future

init:
	R --vanilla -e 'renv::restore(); devtools::document(); renv::snapshot(prompt=FALSE)'

test:
	R --vanilla -e 'source("renv/activate.R"); devtools::test()'

run:
	R --vanilla -e 'targets::tar_make()'

report:
	R --vanilla -e 'targets::tar_load(c(default_N,default_po,default_foss,default_summs,cfg)); quarto::quarto_render("reports/sandbox.qmd")'

exp:
	R --vanilla -e 'targets::tar_make()'

report-id:
	R --vanilla -e 'quarto::quarto_render("reports/identifiability.qmd")'

report-leak:
	R --vanilla -e 'quarto::quarto_render("reports/leakage_and_ablation.qmd")'

report-qa:
	R --vanilla -e 'quarto::quarto_render("reports/qa_sanity.qmd")'

report-sens:
	R --vanilla -e 'quarto::quarto_render("reports/sensitivity.qmd")'

pilot:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make(names=c("pilot_screen","pilot_report"))'

pilot-future:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make_future(names=c("pilot_screen","pilot_report"), workers=6)'
