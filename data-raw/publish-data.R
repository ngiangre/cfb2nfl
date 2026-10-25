# Upload the local cleaned data assets to the `data-latest` GitHub release
# (decision 0017) — the local fallback when the scheduled data-refresh Action
# fails. Run `data-raw/refresh.R` first so the parquet/DuckDB are current, then
# this script, then re-dispatch `site.yaml` so the track-mode site build picks
# up the new data.

repo <- "ngiangre/cfb2nfl"

assets <- list.files(
  "data",
  pattern = "\\.(parquet|duckdb)$",
  full.names = TRUE
)
if (length(assets) == 0) {
  stop("No parquet/duckdb files found in data/.")
}

piggyback::pb_upload(
  file = assets,
  repo = repo,
  tag = "data-latest",
  overwrite = TRUE
)
