# Re-pull selected seasons and splice them into the published tables
# (decision 0034). Run locally, where CFBD does not throttle the way it does
# shared GitHub-runner IPs. The weekly current-season refresh runs in CI
# (.github/workflows/data-current.yaml); this script is the on-demand path for
# history: backfills, fixes to one season, staged pulls.
#
#   Rscript data-raw/refresh-historical.R 2024              # one season
#   Rscript data-raw/refresh-historical.R 2021:2025 --yes   # skip the prompt
#   Rscript data-raw/refresh-historical.R 2024 --yes --publish
#
# The selector is CFB2NFL_REFRESH_SEASONS syntax (`current`, a year, `a:b`, a
# comma list). It prints the estimated CFBD call count first and will not
# start without confirmation (`--yes`, or answering "y" when run
# interactively), so nobody re-pulls history by accident. Requires
# CFBD_API_KEY and the published data in data/ (data-raw/pull-data.R).
# For a full rebuild of every season, use data-raw/refresh.R instead.

args <- commandArgs(trailingOnly = TRUE)
spec <- args[!startsWith(args, "--")][1]
yes <- "--yes" %in% args
publish <- "--publish" %in% args
if (is.na(spec) || !nzchar(spec)) {
  stop("Give a season selector, e.g. `2024`, `2021:2025`, or `current`.")
}

pkgload::load_all(quiet = TRUE)

sources <- c("games", "player_stats", "roster", "recruiting")
seasons <- lapply(stats::setNames(nm = sources), \(s) refresh_seasons(spec, s))
games_path <- "data/games.parquet"
published <- c(
  games_path,
  "data/game_team_stats.parquet",
  "data/game_player_stats.parquet",
  "data/player_stats.parquet",
  "data/roster.parquet",
  "data/recruiting.parquet"
)
if (!all(file.exists(published))) {
  stop(
    "Missing published data in data/: ",
    paste(published[!file.exists(published)], collapse = ", "),
    ". Run data-raw/pull-data.R first."
  )
}
est <- estimate_refresh_calls(seasons, arrow::read_parquet(games_path))

cat("Seasons selected by `", spec, "`:\n", sep = "")
for (s in sources) {
  cat(sprintf("  %-13s %s\n", s, paste(range(seasons[[s]]), collapse = "-")))
}
cat("\nEstimated CFBD calls:\n")
print(est)

if (!yes) {
  if (!interactive()) {
    stop("Re-run with --yes to confirm ", est[["total"]], " CFBD calls.")
  }
  answer <- readline(sprintf(
    "Spend about %d CFBD calls? [y/N] ",
    est[["total"]]
  ))
  if (!tolower(answer) %in% c("y", "yes")) {
    stop("Cancelled; nothing was pulled.")
  }
}

call_log <- tempfile("cfbd-calls-", fileext = ".tsv")
Sys.setenv(
  CFB2NFL_REFRESH = "true",
  CFB2NFL_REFRESH_SEASONS = spec,
  CFB2NFL_CALL_LOG = call_log
)
# Ingest and asset targets are not cued "always" and targets does not see env
# vars, so force the selected pull; everything downstream follows from them.
targets::tar_invalidate(
  c(
    tidyselect::starts_with("raw_"),
    tidyselect::ends_with("_file"),
    "games_grid",
    "week_grid"
  )
)
targets::tar_make()

made <- if (file.exists(call_log)) length(readLines(call_log)) else 0L
cat(sprintf("\nCFBD calls made: %d (estimated %d).\n", made, est[["total"]]))

if (publish) {
  source("data-raw/publish-data.R")
}
