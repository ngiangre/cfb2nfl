# Season calendar, the season-scoped refresh selector, and the season splice
# (decision 0034).
#
# Pure functions of a date, an environment variable, and local files: no API
# calls. The ingest targets call refresh_seasons() to decide which seasons to
# pull, and splice_seasons() to merge them into the published table.

#' Source groups for season-keyed refresh
#'
#' Maps each season-keyed source to the calendar rule that decides its
#' "current" season (decision 0034, section 3). `plays` and `play_stats` are
#' forward declarations for issue #44.
#'
#' @keywords internal
refresh_source_groups <- c(
  games = "cfb",
  game_team_stats = "cfb",
  game_player_stats = "cfb",
  player_stats = "cfb",
  roster = "cfb",
  coaches = "cfb",
  plays = "cfb",
  play_stats = "cfb",
  recruiting = "recruiting",
  picks = "draft",
  nfl_draft_picks = "draft",
  combine = "draft",
  nfl_rosters = "nfl",
  nfl_player_stats = "nfl"
)

#' Current college football season
#'
#' The CFBD season is the calendar year the season starts in. The season
#' changes on August 1, so January bowls and the national championship belong
#' to the prior season, and July 31 is still the old season.
#'
#' @param date A date (or anything [as.Date()] accepts).
#'
#' @return An integer season year.
#' @keywords internal
current_season <- function(date = Sys.Date()) {
  d <- as.POSIXlt(as.Date(date))
  year <- d$year + 1900L
  as.integer(if (d$mon + 1L >= 8L) year else year - 1L)
}

#' Most recently completed NFL draft year
#'
#' Draft-keyed sources (picks, NFL draft picks, combine) are keyed by draft
#' year. The draft is in late April, so the new draft year takes over on May 1.
#' Refreshing before that would pull a draft that has not happened yet.
#'
#' @param date A date (or anything [as.Date()] accepts).
#'
#' @return An integer draft year.
#' @keywords internal
draft_season <- function(date = Sys.Date()) {
  d <- as.POSIXlt(as.Date(date))
  year <- d$year + 1900L
  as.integer(if (d$mon + 1L >= 5L) year else year - 1L)
}

#' The season a source's `current` selector refers to
#'
#' Also the upper bound of the source's window: nothing later than this season
#' is ingested.
#'
#' @param source One of the names in `refresh_source_groups`.
#' @param date A date (or anything [as.Date()] accepts).
#'
#' @return An integer season year.
#' @keywords internal
refresh_season_for <- function(source, date = Sys.Date()) {
  group <- refresh_source_group(source)
  season <- switch(
    group,
    cfb = current_season(date),
    # The class enrolled this season: CFBD assigns athlete ids to a class
    # once it enrolls, and the cleaned table keeps only recruits with an id,
    # so the incoming class (all ids missing) would add no rows.
    recruiting = current_season(date),
    draft = draft_season(date),
    nfl = current_season(date)
  )
  as.integer(season)
}

#' Validate a source name and return its group
#'
#' @param source A single source name.
#'
#' @return The source group (`"cfb"`, `"recruiting"`, `"draft"`, or `"nfl"`).
#' @keywords internal
refresh_source_group <- function(source) {
  if (!is.character(source) || length(source) != 1L || is.na(source)) {
    cli::cli_abort("{.arg source} must be a single source name.")
  }
  if (!source %in% names(refresh_source_groups)) {
    cli::cli_abort(c(
      "Unknown season-keyed source {.val {source}}.",
      "i" = "Known sources: {.val {names(refresh_source_groups)}}."
    ))
  }
  unname(refresh_source_groups[[source]])
}

#' Seasons to ingest for one source
#'
#' Parses the `CFB2NFL_REFRESH_SEASONS` selector (decision 0034, section 2).
#' An unset or empty spec means the full window, `min_season` through the
#' source's current season. Otherwise the spec is a comma-separated list of
#' tokens, each one of:
#'
#' - `current`: the source's current season ([refresh_season_for()]);
#' - a single year, e.g. `2024`;
#' - an inclusive range, e.g. `2010:2025`.
#'
#' Seasons outside the source's window (before `min_season` or after the
#' current season) are dropped with a warning.
#'
#' @param spec The selector string. Defaults to the `CFB2NFL_REFRESH_SEASONS`
#'   environment variable.
#' @param source A season-keyed source name (see `refresh_source_groups`).
#' @param min_season The earliest season in the window.
#' @param date The date the window is evaluated at.
#'
#' @return An integer vector of seasons, sorted and unique.
#' @keywords internal
refresh_seasons <- function(
  spec = Sys.getenv("CFB2NFL_REFRESH_SEASONS", ""),
  source,
  min_season = 2010L,
  date = Sys.Date()
) {
  max_season <- refresh_season_for(source, date)
  min_season <- as.integer(min_season)
  if (length(min_season) != 1L || is.na(min_season)) {
    cli::cli_abort("{.arg min_season} must be a single year.")
  }
  if (min_season > max_season) {
    cli::cli_abort(
      "The window for {.val {source}} is empty ({min_season} to {max_season})."
    )
  }

  if (is.null(spec) || length(spec) == 0L || is.na(spec[[1]])) {
    spec <- ""
  }
  if (!is.character(spec) || length(spec) != 1L) {
    cli::cli_abort("The refresh seasons selector must be a single string.")
  }
  spec <- trimws(spec)
  if (!nzchar(spec)) {
    return(seq.int(min_season, max_season))
  }

  # strsplit() drops a trailing empty token, so restore it explicitly.
  tokens <- strsplit(spec, ",", fixed = TRUE)[[1]]
  if (endsWith(spec, ",")) {
    tokens <- c(tokens, "")
  }
  tokens <- trimws(tokens)
  if (any(!nzchar(tokens))) {
    cli::cli_abort(c(
      "Empty token in the refresh seasons selector {.val {spec}}.",
      "i" = "Use a comma-separated list, e.g. {.val 2021,2023:2025}."
    ))
  }

  seasons <- unlist(lapply(tokens, parse_season_token, max_season = max_season))
  seasons <- sort(unique(as.integer(seasons)))

  in_window <- seasons >= min_season & seasons <= max_season
  if (any(!in_window)) {
    cli::cli_warn(
      "Dropping seasons outside the {.val {source}} window ({min_season} to {max_season}): {seasons[!in_window]}."
    )
  }
  seasons <- seasons[in_window]
  if (length(seasons) == 0L) {
    cli::cli_abort(
      "The refresh seasons selector {.val {spec}} selects no season in the {.val {source}} window ({min_season} to {max_season})."
    )
  }
  seasons
}

#' Parse one token of the seasons selector
#'
#' @param token A single trimmed token.
#' @param max_season The source's current season (the value of `current`).
#'
#' @return An integer vector of the seasons the token names.
#' @keywords internal
parse_season_token <- function(token, max_season) {
  if (identical(token, "current")) {
    return(max_season)
  }
  if (grepl("^[0-9]{4}$", token)) {
    return(as.integer(token))
  }
  if (grepl("^[0-9]{4}:[0-9]{4}$", token)) {
    bounds <- as.integer(strsplit(token, ":", fixed = TRUE)[[1]])
    if (bounds[[1]] > bounds[[2]]) {
      cli::cli_abort(
        "Range {.val {token}} runs backwards; write it as {.val {paste0(bounds[[2]], ':', bounds[[1]])}}."
      )
    }
    return(seq.int(bounds[[1]], bounds[[2]]))
  }
  cli::cli_abort(c(
    "Unrecognized token {.val {token}} in the refresh seasons selector.",
    "i" = "Use {.val current}, a year such as {.val 2024}, or a range such as {.val 2010:2025}."
  ))
}

#' Does the selector cover a source's full window?
#'
#' A full-window refresh rebuilds the table from scratch (today's behavior);
#' anything narrower splices into the published table ([splice_seasons()]).
#'
#' @inheritParams refresh_seasons
#' @return `TRUE` when the selector selects every season in the window.
#' @keywords internal
refresh_is_full <- function(
  spec = Sys.getenv("CFB2NFL_REFRESH_SEASONS", ""),
  source,
  min_season = 2010L,
  date = Sys.Date()
) {
  setequal(
    refresh_seasons(spec, source, min_season, date),
    refresh_seasons("", source, min_season, date)
  )
}

#' Splice freshly cleaned seasons into the published table
#'
#' A season-scoped refresh (decision 0034) re-ingests only some seasons. The
#' published asset stays one parquet per table (one `data-latest` release, no
#' partition directories), so the fresh rows replace exactly those seasons'
#' rows in the existing file and every other season is kept as published.
#'
#' Guards, all failing before anything is written:
#' - the existing file must be present (download `data-latest` first);
#' - the fresh rows must have the published columns (a schema change needs a
#'   full refresh, which rebuilds every season);
#' - no refreshed season may shrink below `min_ratio` of its published rows,
#'   so a truncated or failed pull cannot silently replace good data. A season
#'   with no published rows (a new season) is not checked.
#'
#' @param fresh The freshly cleaned rows for `seasons`.
#' @param path The published parquet to splice into.
#' @param season_col The table's season column (e.g. `"season"`, `"hs_class"`).
#' @param seasons The seasons `fresh` replaces.
#' @param full When `TRUE`, `fresh` is the whole table and is returned as is.
#' @param dedupe Optional function applied after binding (e.g. to restore a
#'   one-row-per-athlete key, see [dedupe_recruiting()]).
#' @param min_ratio Smallest allowed fresh-to-published row ratio per season.
#' @return The spliced table.
#' @keywords internal
splice_seasons <- function(
  fresh,
  path,
  season_col,
  seasons,
  full = FALSE,
  dedupe = NULL,
  min_ratio = 0.5
) {
  if (isTRUE(full)) {
    return(fresh)
  }
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "Season-scoped refresh needs the published {.path {path}} to splice into.",
      "i" = "Download the {.val data-latest} release first ({.file data-raw/pull-data.R}), or run a full refresh."
    ))
  }
  old <- arrow::read_parquet(path)
  if (!setequal(names(fresh), names(old))) {
    cli::cli_abort(c(
      "Fresh rows for {.path {path}} do not match the published columns.",
      "x" = "Added: {.val {setdiff(names(fresh), names(old))}}; missing: {.val {setdiff(names(old), names(fresh))}}.",
      "i" = "A schema change needs a full refresh (unset {.envvar CFB2NFL_REFRESH_SEASONS})."
    ))
  }
  old_n <- table(factor(old[[season_col]], levels = seasons))
  new_n <- table(factor(fresh[[season_col]], levels = seasons))
  shrunk <- seasons[old_n > 0 & new_n < min_ratio * old_n]
  if (length(shrunk) > 0) {
    cli::cli_abort(c(
      "Refreshed seasons shrank below {min_ratio * 100}% of their published rows in {.path {path}}: {shrunk}.",
      "i" = "Published: {as.integer(old_n[as.character(shrunk)])}; fresh: {as.integer(new_n[as.character(shrunk)])}. The pull is likely truncated; nothing was written."
    ))
  }
  out <- dplyr::bind_rows(
    old[!old[[season_col]] %in% seasons, , drop = FALSE],
    fresh[, names(old)]
  )
  if (!is.null(dedupe)) {
    out <- dedupe(out)
  }
  out
}

#' Estimate the CFBD calls a refresh will make
#'
#' Mirrors the ingest call patterns: one call per season for player stats,
#' roster, and recruiting; two `/games` calls per season (regular and
#' postseason); one `/games/teams` and one `/games/players` call per played
#' week; plus one call each for the whole-table `/draft/picks`, `/coaches`,
#' and `/teams`. Week counts come from the published games; a season not yet
#' published is assumed to have `default_weeks` played weeks. nflverse sources
#' cost no CFBD calls.
#'
#' @param seasons Named list of season vectors for `games`, `player_stats`,
#'   `roster`, and `recruiting` (as from [refresh_seasons()]).
#' @param games The published games table (`season`, `seasonType`, `week`,
#'   `completed`), or `NULL`.
#' @param default_weeks Played weeks assumed for an unpublished season.
#' @return A named integer vector of calls by endpoint, with a `total`.
#' @keywords internal
estimate_refresh_calls <- function(seasons, games = NULL, default_weeks = 16L) {
  game_seasons <- seasons$games
  weeks <- if (is.null(games)) {
    0L
  } else {
    games |>
      dplyr::filter(.data$season %in% game_seasons, .data$completed) |>
      dplyr::distinct(.data$season, .data$seasonType, .data$week) |>
      nrow()
  }
  known <- if (is.null(games)) integer() else unique(games$season)
  weeks <- weeks + default_weeks * sum(!game_seasons %in% known)
  calls <- c(
    games = 2L * length(game_seasons),
    game_team_stats = as.integer(weeks),
    game_player_stats = as.integer(weeks),
    player_stats = length(seasons$player_stats),
    roster = length(seasons$roster),
    recruiting = length(seasons$recruiting),
    picks_coaches_teams = 3L
  )
  c(calls, total = sum(calls))
}
