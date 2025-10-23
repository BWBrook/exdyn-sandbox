.PHONY: init test run report report-leak exp report-id

init:
	R --vanilla -e 'renv::restore(); devtools::document(); renv::snapshot(prompt=FALSE)'

test:
	R --vanilla -e 'devtools::test()'

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
