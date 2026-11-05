# Season calendar and the season-scoped refresh selector (decision 0034).
#
# Pure functions of a date and an environment variable: no API calls. The
# ingest targets will call refresh_seasons() to decide which seasons to pull;
# until they do, nothing here changes what the pipeline ingests.

#' Source groups for season-keyed refresh
#'
#' Maps each season-keyed source to the calendar rule that decides its
#' "current" season (decision 0034, section 3). `plays`, `play_stats`, and
#' `combine` are forward declarations for issues #44 and #45.
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
    recruiting = current_season(date) + 1L,
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
