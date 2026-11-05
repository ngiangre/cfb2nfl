# Refresh ALL data by running the pipeline in refresh mode (decision 0017):
# ingest every season from CFBD/nflverse, derive conference_tiers, process,
# and write every data asset (cleaned parquet + the DuckDB bundle) in one
# dependency-ordered pass. Requires CFBD_API_KEY. Costs ~780 CFBD calls: the
# routine path is the weekly current-season run
# (.github/workflows/data-current.yaml, ~40 calls), and
# data-raw/refresh-historical.R re-pulls selected seasons (decision 0034).
# Use this full rebuild only when a schema change needs every season re-cleaned.
#
# Without CFB2NFL_REFRESH the pipeline runs in track mode: it reads the
# committed/downloaded parquet and never calls an API (how the site build runs).
#
# Ingest and parquet-asset targets are NOT cued "always", so this script first
# invalidates every target: a refresh is an explicit, full rebuild by design.
# To skip the API entirely, use data-raw/pull-data.R to fetch the latest
# published assets from the data-latest release instead.

call_log <- tempfile("cfbd-calls-", fileext = ".tsv")
Sys.setenv(
  CFB2NFL_REFRESH = "true",
  CFB2NFL_REFRESH_SEASONS = "",
  CFB2NFL_CALL_LOG = call_log
)
targets::tar_invalidate(everything = TRUE)
targets::tar_make()
if (file.exists(call_log)) {
  cat(sprintf("\nCFBD calls made: %d.\n", length(readLines(call_log))))
}
