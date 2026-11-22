# Pull the play-level NFL tables (feature F23: nfl_pbp, nfl_participation,
# nfl_snap_counts, nfl_rosters_weekly) from nflverse and rebuild everything
# downstream, without touching any CFBD source. nflverse needs no API key and
# costs no CFBD calls.
#
#   Rscript data-raw/refresh-nfl.R --yes             # full NFL window, 2022 on
#   Rscript data-raw/refresh-nfl.R 2024 --yes        # re-pull one season
#   Rscript data-raw/refresh-nfl.R --yes --publish   # and upload
#
# The first pull must be the full window: a season splice needs a published
# table to splice into. The selector is CFB2NFL_REFRESH_SEASONS syntax,
# applied inside the NFL window (nfl_refresh_seasons()).
#
# How it stays off CFBD: only the NFL ingest and asset targets are built in
# refresh mode; everything downstream (contracts, the DuckDB, the explorer)
# is then built in track mode, which reads the published parquet and calls no
# API. It stops before publishing if the CFBD call log is not empty or any
# non-NFL parquet changed, or if local data/ no longer matches data-latest.
# Pull the current release first (data-raw/pull-data.R) so the DuckDB is
# built from current tables.

args <- commandArgs(trailingOnly = TRUE)
spec <- args[!startsWith(args, "--")][1]
if (is.na(spec)) {
  spec <- ""
}
yes <- "--yes" %in% args
publish <- "--publish" %in% args

pkgload::load_all(quiet = TRUE)

nfl_paths <- file.path("data", paste0(nfl_play_sources, ".parquet"))
names(nfl_paths) <- nfl_play_sources
seasons <- lapply(
  stats::setNames(nm = nfl_play_sources),
  \(s) nfl_refresh_seasons(spec, s)
)
if (all(lengths(seasons) == 0L)) {
  stop(
    "The selector `",
    spec,
    "` names no season from ",
    nfl_play_min_season,
    " on."
  )
}
cat("NFL seasons selected by `", spec, "`:\n", sep = "")
for (s in nfl_play_sources) {
  cat(sprintf("  %-20s %s\n", s, paste(range(seasons[[s]]), collapse = "-")))
}
cat("CFBD calls expected: 0 (nflverse only).\n")

if (!yes) {
  if (!interactive()) {
    stop("Re-run with --yes to pull from nflverse.")
  }
  if (!tolower(readline("Pull these seasons? [y/N] ")) %in% c("y", "yes")) {
    stop("Cancelled; nothing was pulled.")
  }
}

others <- setdiff(
  list.files("data", "\\.parquet$", full.names = TRUE),
  nfl_paths
)
before_md5 <- tools::md5sum(others)
before_rows <- nfl_play_row_counts()

call_log <- tempfile("cfbd-calls-", fileext = ".tsv")
Sys.setenv(
  CFB2NFL_REFRESH = "true",
  CFB2NFL_REFRESH_SEASONS = spec,
  CFB2NFL_CALL_LOG = call_log
)
nfl_targets <- c(
  paste0("raw_", nfl_play_sources),
  paste0(nfl_play_sources, "_file")
)
# Targets does not see env vars, so force the selected pull.
targets::tar_invalidate(tidyselect::any_of(nfl_targets))
# tar_make() evaluates `names` in its own process: inline the vector.
rlang::inject(targets::tar_make(names = tidyselect::any_of(!!nfl_targets)))

# Everything downstream in track mode: published parquet only, no API.
Sys.setenv(CFB2NFL_REFRESH = "false")
targets::tar_make()

made <- if (file.exists(call_log)) length(readLines(call_log)) else 0L
changed <- names(before_md5)[tools::md5sum(others) != before_md5]

rows <- dplyr::full_join(
  before_rows,
  nfl_play_row_counts(),
  by = c("table", "season"),
  suffix = c("_before", "_after")
)
cat("\nRows per season:\n")
print(as.data.frame(rows))
cat(sprintf("\nCFBD calls made: %d.\n", made))
if (made > 0L) {
  stop("CFBD calls were made; not publishing. See ", call_log, ".")
}
if (length(changed) > 0L) {
  stop(
    "Non-NFL parquet changed; not publishing: ",
    paste(changed, collapse = ", ")
  )
}
cat("Non-NFL parquet unchanged.\n")

if (publish) {
  # The DuckDB bundles every table, so the local non-NFL parquet must match
  # the release, or the upload would replace newer published tables with a
  # stale local copy. GitHub reports sizes, not checksums: compare those.
  release <- piggyback::pb_list(repo = "ngiangre/cfb2nfl", tag = "data-latest")
  local <- file.size(others)
  published <- release$size[match(basename(others), release$file_name)]
  stale <- basename(others)[is.na(published) | published != local]
  if (length(stale) > 0L) {
    stop(
      "Local data/ differs from data-latest (",
      paste(stale, collapse = ", "),
      "); run data-raw/pull-data.R, then this script again."
    )
  }
  piggyback::pb_upload(
    file = c(nfl_paths[file.exists(nfl_paths)], "data/cfb2nfl.duckdb"),
    repo = "ngiangre/cfb2nfl",
    tag = "data-latest",
    overwrite = TRUE
  )
  cat("Published; dispatch site.yaml to rebuild the site.\n")
}
