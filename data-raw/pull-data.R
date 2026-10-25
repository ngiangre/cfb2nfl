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
