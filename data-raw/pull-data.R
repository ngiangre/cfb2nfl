# Pull the latest published data assets from the `data-latest` GitHub release
# (decision 0017). The scheduled data-refresh Action rebuilds and uploads them
# weekly, so most local work needs no API call: download, then run
# `targets::tar_make()` in track mode (default; no CFBD_API_KEY required).

dir.create("data", showWarnings = FALSE)
piggyback::pb_download(
  repo = "ngiangre/cfb2nfl",
  tag = "data-latest",
  dest = "data"
)
# Stamp the release date for card captions (data_release_date()); the
# DuckDB's own _meta timestamp dates each rebuild, not the release.
pkgload::load_all(quiet = TRUE)
record_release_date("data")
