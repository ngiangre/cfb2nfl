# Bundle the cleaned tables into a single queryable DuckDB file (decision 0016).
# Built as the `duckdb_file` pipeline target (see _targets.R) so it is part of
# the DAG and rebuilt whenever an upstream table changes; published alongside
# the parquet on the data-latest release. It carries the CLEANED,
# contract-checked tables — the schemas documented in inst/dict/*.yml — not the
# raw ingest parquet, plus derived convenience tables (decision 0026): the wide
# `player_season_stats` pivot and the name-guarded `nfl_pick_link` bridge
# (decision 0014), a slimmed `audit_log`, a `_meta` table with
# build/season-completeness metadata, and an auto-generated `_schema_manifest`
# (grain + key read from the dictionaries at build time, so the manifest can
# never silently drift from inst/dict) (decision 0027).

#' Pivot long stats into a wide player-season stat table
#'
#' Reshapes the long `player_stats` (one row per player-season-category-
#' statType-stat) into a wide table, one row per `(playerId, season, team)` with
#' one numeric column per `(category, statType)` pair, named
#' `<category>_<statType>` (lowercased, non-alphanumerics to `_`). Values are
#' summed over duplicate pairs and coerced to double; pairs a player-season
#' never logged are `NA`. Meant to be bundled into the DuckDB asset so SQL users
#' get a directly queryable wide stat table instead of pivoting 1.5M long rows
#' (decision 0026).
#'
#' @param player_stats Cleaned long stats from [clean_player_stats()].
#'
#' @return A tibble, one row per `(playerId, season, team)`.
#' @export
build_player_season_stats <- function(player_stats) {
  player_stats |>
    dplyr::mutate(
      # One column per (category, statType); statType repeats across categories
      # (TD in passing AND rushing), so the category must be in the name.
      stat_col = tolower(gsub(
        "[^A-Za-z0-9]+",
        "_",
        paste(.data$category, .data$statType)
      )),
      stat_value = suppressWarnings(as.numeric(.data$stat))
    ) |>
    tidyr::pivot_wider(
      id_cols = c(
        "playerId",
        "player",
        "season",
        "team",
        "conference",
        "position"
      ),
      names_from = "stat_col",
      values_from = "stat_value",
      values_fn = sum,
      values_fill = NA_real_
    )
}

#' Bundle cleaned tables into a queryable DuckDB database
#'
#' Writes each supplied data frame as a table in a single DuckDB database file,
#' so the whole cfb2nfl data model can be explored with SQL from one asset
#' (decision 0016). The database is rebuilt from scratch on each call so a
#' dropped or renamed table never lingers. Intended to run as the `duckdb_file`
#' target: it bundles the cleaned tables whose schemas are documented in
#' `inst/dict/*.yml`.
#'
#' Two generated metadata structures are added on every build (decision 0027):
#' a `_schema_manifest` table — grain, key and dictionary path per table, read
#' from `inst/dict/*.yml` at build time — and a `_meta` table with the refresh
#' timestamp and the last COMPLETE college season / NFL draft (later seasons
#' may be partial; see [last_complete_cfb_season()]). If `ps_change` is among
#' the tables, a `player_season_inputs` view is also created: `ps_change` with
#' the draft-outcome columns excluded, i.e. the leakage-safe model input
#' surface.
#'
#' @param tables A named list of data frames. Each name becomes a DuckDB table
#'   (e.g. `conference_tiers = tiers`).
#' @param db_path Output DuckDB file path.
#'
#' @return `db_path`, invisibly (so the target can track it with
#'   `format = "file"`).
#' @export
build_duckdb <- function(tables, db_path = "data/cfb2nfl.duckdb") {
  rlang::check_installed(
    c("DBI", "duckdb", "yaml"),
    reason = "to build the DuckDB data asset."
  )
  if (
    !length(tables) || is.null(names(tables)) || any(!nzchar(names(tables)))
  ) {
    cli::cli_abort("{.arg tables} must be a non-empty {.emph named} list.")
  }

  dir.create(dirname(db_path), showWarnings = FALSE, recursive = TRUE)
  # Rebuild from scratch so a dropped/renamed table never lingers.
  if (file.exists(db_path)) {
    file.remove(db_path)
  }
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (name in names(tables)) {
    DBI::dbWriteTable(
      con,
      name,
      as.data.frame(tables[[name]]),
      overwrite = TRUE
    )
  }

  # Materialize first: dbWriteTable takes its value argument lazily, and its
  # own `trim` handling collides with format() calls inside the builders.
  manifest <- schema_manifest(names(tables))
  meta <- build_meta()
  DBI::dbWriteTable(con, "_schema_manifest", manifest)
  DBI::dbWriteTable(con, "_meta", meta)
  if ("ps_change" %in% names(tables)) {
    DBI::dbExecute(
      con,
      "CREATE VIEW player_season_inputs AS
       SELECT * EXCLUDE (draft_year, draft_round, draft_overall, drafted)
       FROM ps_change"
    )
  }

  cli::cli_alert_success(
    "Built DuckDB {.path {db_path}} with {length(tables)} table{?s}: {.val {names(tables)}}."
  )
  invisible(db_path)
}

#' Build the schema manifest for the DuckDB bundle
#'
#' One row per bundled table, read from the package's `inst/dict/*.yml`
#' dictionaries at build time: grain + key (`grain_key`) and the dictionary
#' file path. Tables without a dictionary get `NA` documentation fields, so the
#' manifest doubles as a drift check visible inside the asset itself: an
#' undocumented bundled table shows up as `documented = FALSE`.
#'
#' @param table_names Names of the tables bundled into the DuckDB file.
#' @param dict_dir Directory holding the `inst/dict` YAML files (defaults to
#'   the installed package's copy; override for tests).
#'
#' @return A tibble, one row per table.
#' @export
schema_manifest <- function(
  table_names,
  dict_dir = app_sys("dict")
) {
  docs <- vapply(
    table_names,
    \(nm) {
      path <- file.path(dict_dir, paste0(nm, ".yml"))
      if (!file.exists(path)) {
        return(NA_character_)
      }
      y <- yaml::read_yaml(path)
      paste0(y$grain, " | key: ", y$key)
    },
    character(1)
  )
  tibble::tibble(
    table_name = table_names,
    documented = !is.na(docs),
    grain_key = unname(docs),
    dict_file = unname(ifelse(
      is.na(docs),
      NA_character_,
      file.path("inst", "dict", paste0(table_names, ".yml"))
    ))
  )
}

#' Build the `_meta` table for the DuckDB bundle
#'
#' One row of build-time context for SQL users (decision 0027): when the bundle
#' was refreshed, and which college season / NFL draft class are the most recent
#' ones known to be COMPLETE. Later seasons may be partial (an in-progress
#' season, an unsigned draft class) — out-of-time model frames and
#' "career completed" logic must stop at these values.
#'
#' @param as_of Reference date (default today; override for tests).
#'
#' @return A one-row tibble.
#' @export
build_meta <- function(as_of = Sys.Date()) {
  # Compute before the tibble() data mask: inside it, `as_of` would resolve to
  # the just-created character column, not the date argument.
  refreshed <- as.POSIXct(format(Sys.time()), tz = "UTC")
  complete_cfb <- last_complete_cfb_season(as_of)
  complete_draft <- last_complete_nfl_draft(as_of)
  tibble::tibble(
    refreshed_at = refreshed,
    as_of = as.character(as_of),
    last_complete_cfb_season = complete_cfb,
    last_complete_nfl_draft = complete_draft
  )
}

#' Last complete college football season as of a date
#'
#' A season (Aug–Jan) is treated as complete once the data refresh date is past
#' March 1 of the following year (post-bowl buffer). Used by the `_meta` table
#' so out-of-time logic can stop at a defensible boundary instead of the raw
#' max season (which may be in progress).
#'
#' @param as_of Reference date.
#'
#' @return Integer season year.
#' @export
last_complete_cfb_season <- function(as_of = Sys.Date()) {
  year <- as.integer(format(as_of, "%Y"))
  if (as_of >= as.Date(sprintf("%d-03-01", year))) {
    year - 1L
  } else {
    year - 2L
  }
}

#' Last complete NFL draft class as of a date
#'
#' The NFL draft for class year Y happens in April of Y+1, so a draft class is
#' treated as complete once the refresh date is past May 1 of Y+1.
#'
#' @param as_of Reference date.
#'
#' @return Integer draft year.
#' @export
last_complete_nfl_draft <- function(as_of = Sys.Date()) {
  year <- as.integer(format(as_of, "%Y"))
  if (as_of >= as.Date(sprintf("%d-05-01", year))) {
    year - 1L
  } else {
    year - 2L
  }
}
