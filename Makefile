.PHONY: init test run report

init:
	R --vanilla -e 'renv::restore(); devtools::document(); renv::snapshot(prompt=FALSE)'

test:
	R --vanilla -e 'devtools::test()'

run:
	R --vanilla -e 'targets::tar_make()'

report:
	R --vanilla -e 'targets::tar_load(c(N,po,foss,summs,cfg)); quarto::quarto_render("reports/sandbox.qmd")'
