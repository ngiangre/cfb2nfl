# Build the altdoc site locally the way CI does (site.yaml): point vignettes at
# the project root via CFB2NFL_ROOT (altdoc renders in a temp dir, so tar_read()
# and data/*.parquet must resolve to an absolute path) and reuse the committed
# _quarto/_freeze/ cache with freeze = TRUE so frozen blog posts are not
# re-executed. Run from the project root: Rscript data-raw/build-site.R
#
# Prereqs (as in CI): the cfb2nfl package is installed (vignettes call
# library(cfb2nfl)) and the pipeline is current (targets::tar_make()) so the
# audit/DAG pages have targets to read.

Sys.setenv(CFB2NFL_ROOT = normalizePath("."))
altdoc::render_docs(freeze = TRUE)
