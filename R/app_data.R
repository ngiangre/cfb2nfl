# Shared app data: DuckDB connection, table inventory, row counts, and
# dictionaries. Cached in a package-level environment so app_ui() and
# app_server() see the same state without re-querying the database.

.app_state <- new.env(parent = emptyenv())

#' Connect to the DuckDB bundle and describe its tables
#'
#' Builds (once per process) the read-only DuckDB connection, the ordered table
#' list (skipping internal metadata tables, leading with the wide
#' player-season table), per-table row counts, and the data dictionaries.
#' @noRd
app_data <- function(
  dbdir = Sys.getenv("CFB2NFL_DB", "data/cfb2nfl.duckdb")
) {
  if (is.null(.app_state$con)) {
    con <- DBI::dbConnect(
      duckdb::duckdb(),
      dbdir = dbdir,
      read_only = TRUE
    )
    tables <- DBI::dbGetQuery(
      con,
      "SELECT table_name FROM information_schema.tables
       WHERE table_schema = 'main' ORDER BY table_name"
    )$table_name
    # skip internal metadata tables (_meta, _schema_manifest)
    tables <- grep("^[A-Za-z][A-Za-z0-9_]*$", tables, value = TRUE)
    # lead with the wide player-season table: easiest join base
    tables <- c("player_season_stats", setdiff(tables, "player_season_stats"))

    n_rows <- vapply(
      tables,
      function(tb) {
        DBI::dbGetQuery(
          con,
          sprintf(
            "SELECT COUNT(*) FROM %s",
            DBI::dbQuoteIdentifier(con, tb)
          )
        )[[1]]
      },
      numeric(1)
    )

    .app_state$con <- con
    .app_state$tables <- tables
    .app_state$n_rows <- n_rows
    .app_state$dict <- app_dict()
  }
  .app_state
}
