.PHONY: setup document snapshot init test run report report-leak report-qa exp report-id report-sens pilot pilot-future synthetic graph-parallel manuscript

EXDYN_WORKERS ?= 8
EXDYN_DRAWS ?= 64
EXDYN_SIMS ?= 200
EXDYN_MODE ?= full
EXDYN_SEED ?= 1045

setup:
	R --vanilla -e 'source("renv/activate.R"); renv::restore(prompt=FALSE)'

document:
	R --vanilla -e 'source("renv/activate.R"); devtools::document()'

snapshot:
	R --vanilla -e 'source("renv/activate.R"); renv::snapshot(prompt=FALSE)'

init: setup document snapshot

test:
	R --vanilla -e 'source("renv/activate.R"); devtools::test()'

run:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make()'

report:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_load(c(default_N,default_po,default_foss,default_summs,cfg), store="_targets"); quarto::quarto_render("reports/sandbox.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/sandbox.qmd", output_format="pdf")'

exp:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make()'

report-id:
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/identifiability.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/identifiability.qmd", output_format="pdf")'

report-leak:
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/leakage_and_ablation.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/leakage_and_ablation.qmd", output_format="pdf")'

report-qa:
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/qa_sanity.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/qa_sanity.qmd", output_format="pdf")'

report-sens:
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/sensitivity.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("reports/sensitivity.qmd", output_format="pdf")'

pilot:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make(names=c("pilot_screen","pilot_report_html","pilot_report_pdf","pilot_summary","pilot_canonical_manifest"))'

pilot-future:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make_future(names=c("pilot_screen","pilot_report_html","pilot_report_pdf","pilot_summary","pilot_canonical_manifest"), workers=6)'

graph-parallel:
	EXDYN_WORKERS=$(EXDYN_WORKERS) EXDYN_DRAWS=$(EXDYN_DRAWS) EXDYN_SIMS=$(EXDYN_SIMS) EXDYN_MODE=$(EXDYN_MODE) EXDYN_SEED=$(EXDYN_SEED) \
		Rscript outputs/perf/ladder/gb_land_graph/run_gb_land_graph_parallel_runner.R

synthetic:
	R --vanilla -e 'source("renv/activate.R"); targets::tar_make(names=c("synthetic_report_html","synthetic_report_pdf","synthetic_recovery_written","synthetic_canonical_manifest"))'

manuscript:
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("manuscript/mink_vole_manuscript.qmd", output_format="html")'
	R --vanilla -e 'source("renv/activate.R"); quarto::quarto_render("manuscript/mink_vole_manuscript.qmd", output_format="pdf")'
