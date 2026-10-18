# Refresh ALL data by running the pipeline in refresh mode (decision 0017):
# ingest from CFBD/nflverse, derive conference_tiers, process, and write every
# data asset (raw parquet + the DuckDB bundle) in one dependency-ordered pass.
# Requires CFBD_API_KEY. The scheduled data-refresh GitHub Action runs the same
# `tar_make()` with CFBSTATS_REFRESH=true, then publishes the assets.
#
# Without CFBSTATS_REFRESH the pipeline runs in track mode: it reads the
# committed/downloaded parquet and never calls an API (how the site build runs).
#
# Ingest and parquet-asset targets are NOT cued "always", so this script first
# invalidates every target: a refresh is an explicit, full rebuild by design.
# To skip the API entirely, use data-raw/pull-data.R to fetch the latest
# published assets from the data-latest release instead.

Sys.setenv(CFBSTATS_REFRESH = "true")
targets::tar_invalidate(everything = TRUE)
targets::tar_make()
