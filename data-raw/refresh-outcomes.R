# Rebuild the derived `outcomes` table (decision 0032) from the cleaned tables
# already in the targets store, then everything downstream, without any API
# call. `outcomes.parquet` is written only in refresh mode, and a plain
# refresh-mode build re-pulls every CFBD source, so this builds the one
# target in refresh mode and the rest in track mode.
#
#   Rscript data-raw/refresh-outcomes.R --yes             # rebuild locally
#   Rscript data-raw/refresh-outcomes.R --yes --publish   # and upload
#
# How it stays off CFBD: `tar_make(names = outcomes_file, shortcut = TRUE)`
# builds only `outcomes_file` from the stored upstream values, so no `raw_*`
# ingest and no always-tracked `*_file` asset runs. It stops before
# publishing if the CFBD call log is not empty, any other parquet changed,
# or local data/ no longer matches data-latest. Pull the current release
# first (data-raw/pull-data.R) and build once in track mode, so the store
# holds current upstream tables.
#
# Publish and merge the change that needed this in one sitting, Monday to
# Saturday: the merge's site build then reads the new table, and no Sunday
# data-current.yaml run rebuilds it with the old code in between.

args <- commandArgs(trailingOnly = TRUE)
yes <- "--yes" %in% args
publish <- "--publish" %in% args

pkgload::load_all(quiet = TRUE)

path <- "data/outcomes.parquet"
cat("Rebuilds ", path, " from the targets store.\n", sep = "")
cat("CFBD calls expected: 0.\n")
if (!yes) {
  if (!interactive()) {
    stop("Re-run with --yes to rebuild.")
  }
  if (!tolower(readline("Rebuild outcomes? [y/N] ")) %in% c("y", "yes")) {
    stop("Cancelled; nothing was rebuilt.")
  }
}

others <- setdiff(list.files("data", "\\.parquet$", full.names = TRUE), path)
before_md5 <- tools::md5sum(others)
before <- if (file.exists(path)) arrow::read_parquet(path) else NULL

call_log <- tempfile("cfbd-calls-", fileext = ".tsv")
Sys.setenv(CFB2NFL_REFRESH = "true", CFB2NFL_CALL_LOG = call_log)
targets::tar_invalidate(tidyselect::any_of("outcomes_file"))
targets::tar_make(names = tidyselect::any_of("outcomes_file"), shortcut = TRUE)

# Everything downstream in track mode: published parquet only, no API.
Sys.setenv(CFB2NFL_REFRESH = "false")
targets::tar_make()

made <- if (file.exists(call_log)) length(readLines(call_log)) else 0L
changed <- names(before_md5)[tools::md5sum(others) != before_md5]

after <- arrow::read_parquet(path)
summ <- function(x, label) {
  if (is.null(x)) {
    return(NULL)
  }
  data.frame(
    table = label,
    rows = nrow(x),
    players = length(unique(x$playerId)),
    eligible = sum(x$draft_eligible),
    drafted = sum(x$outcome_drafted_d %in% TRUE),
    signed_udfa = sum(x$outcome_signed_udfa_d %in% TRUE)
  )
}
print(rbind(summ(before, "before"), summ(after, "after")), row.names = FALSE)
cat(sprintf("\nCFBD calls made: %d.\n", made))
if (made > 0L) {
  stop("CFBD calls were made; not publishing. See ", call_log, ".")
}
if (length(changed) > 0L) {
  stop(
    "Other parquet changed; not publishing: ",
    paste(changed, collapse = ", ")
  )
}
cat("Other parquet unchanged.\n")

if (publish) {
  # The DuckDB bundles every table, so the local parquet must match the
  # release, or the upload would replace newer published tables with a stale
  # local copy. GitHub reports sizes, not checksums: compare those.
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
  # A cached pb_list() made pb_upload() silently upload nothing (2026-11-22):
  # clear it and confirm each asset through the GitHub API.
  piggyback::.pb_cache_clear()
  upload <- c(path, "data/cfb2nfl.duckdb")
  for (f in upload) {
    piggyback::pb_upload(
      f,
      repo = "ngiangre/cfb2nfl",
      tag = "data-latest",
      overwrite = TRUE
    )
  }
  id <- gh::gh("GET /repos/ngiangre/cfb2nfl/releases/tags/data-latest")$id
  assets <- gh::gh(
    "GET /repos/ngiangre/cfb2nfl/releases/{id}/assets",
    id = id,
    .limit = 100
  )
  on_release <- stats::setNames(
    vapply(assets, \(a) a$size, numeric(1)),
    vapply(assets, \(a) a$name, character(1))
  )
  missing <- upload[
    on_release[basename(upload)] != file.size(upload) |
      is.na(on_release[basename(upload)])
  ]
  if (length(missing) > 0L) {
    stop("Upload did not land for: ", paste(basename(missing), collapse = ", "))
  }
  cat("Published and verified; merge, or dispatch site.yaml.\n")
}
