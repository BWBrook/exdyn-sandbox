.PHONY: init test run report exp report-id

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
	R --vanilla -e 'targets::tar_load(c(results,confusion_primary,confusion_secondary,feature_importance_primary,primary_model,classifiers,diagnostic_maps,save_diagnostics)); quarto::quarto_render("reports/identifiability.qmd")'
