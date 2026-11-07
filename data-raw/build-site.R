# Build the altdoc site locally the way CI does (site.yaml): point vignettes at
# the project root via CFB2NFL_ROOT (altdoc renders in a temp dir, so tar_read()
# and data/*.parquet must resolve to an absolute path) and reuse the committed
# _quarto/_freeze/ cache with freeze = TRUE so frozen blog posts are not
# re-executed. Run from the project root: Rscript data-raw/build-site.R
#
# Prereqs (as in CI): the package dependencies are installed (cfb2nfl itself
# is not: vignettes load it from the checkout with pkgload, decision 0042) and
# the pipeline is current (targets::tar_make()) so the audit/DAG pages have
# targets to read. Quarto skips projects under a hidden directory, so render
# from a checkout whose path has no dot-directory (not .claude/worktrees/).

Sys.setenv(CFB2NFL_ROOT = normalizePath("."))
altdoc::render_docs(freeze = TRUE)
