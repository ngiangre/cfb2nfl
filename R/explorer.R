# Explorer assets (plans/explorer.md, decision 0046): slim JSON the OJS page
# fetches at runtime. R computes every derived value; the page only filters
# and draws.

#' Default explorer season
#'
#' The in-progress season: the latest season with a completed game. Before a
#' season's first game this is still the previous season, so the preseason
#' falls back on its own.
#'
#' @param games Cleaned games.
#' @return Integer season.
#' @export
explorer_default_season <- function(games) {
  done <- games$season[games$completed %in% TRUE]
  if (length(done) == 0L) {
    cli::cli_abort("No completed games.")
  }
  as.integer(max(done))
}

#' Team sides of completed games
#'
#' One row per team per completed game (home and away), the base of the
#' team-season export.
#'
#' @param games Cleaned games.
#' @return A tibble: `game_id`, `season`, `start`, `team_id`, `conference`,
#'   `classification`, `points`, `opp_points`, `elo_post`.
#' @export
explorer_game_sides <- function(games) {
  done <- dplyr::filter(games, .data$completed %in% TRUE)
  side <- function(us, them) {
    dplyr::transmute(
      done,
      game_id = .data$id,
      season = .data$season,
      start = .data$startDate,
      team_id = .data[[paste0(us, "Id")]],
      conference = .data[[paste0(us, "Conference")]],
      classification = .data[[paste0(us, "Classification")]],
      points = .data[[paste0(us, "Points")]],
      opp_points = .data[[paste0(them, "Points")]],
      elo_post = .data[[paste0(us, "PostgameElo")]]
    )
  }
  dplyr::bind_rows(side("home", "away"), side("away", "home"))
}

#' Explorer team-season table
#'
#' One row per FBS or FCS team per season with a completed game: record,
#' end-of-season Elo (the postgame Elo after the team's last game that has
#' one; FCS teams have none), and the season-aware conference tier.
#'
#' @param games Cleaned games.
#' @param tiers Conference tiers (`season`, `conference`, `tier`, `tier_label`).
#' @return A tibble keyed by `(team_id, season)`.
#' @export
build_explorer_team_season <- function(games, tiers) {
  explorer_game_sides(games) |>
    dplyr::filter(
      .data$classification %in% c("fbs", "fcs"),
      !is.na(.data$points),
      !is.na(.data$opp_points)
    ) |>
    dplyr::arrange(.data$team_id, .data$season, .data$start) |>
    dplyr::summarise(
      conference = dplyr::last(.data$conference),
      classification = dplyr::last(.data$classification),
      games = dplyr::n(),
      wins = sum(.data$points > .data$opp_points),
      losses = sum(.data$points < .data$opp_points),
      ties = sum(.data$points == .data$opp_points),
      elo_end = as.integer(round(dplyr::last(
        .data$elo_post[!is.na(.data$elo_post)],
        default = NA_real_
      ))),
      .by = c("team_id", "season")
    ) |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier", "tier_label"),
      by = c("season", "conference"),
      relationship = "many-to-one"
    ) |>
    # Tiers come from player_stats, so some FCS conference-seasons are absent;
    # FCS is tier 1 by definition (decision 0003).
    dplyr::mutate(
      fcs_gap = is.na(.data$tier) & .data$classification == "fcs",
      tier = dplyr::if_else(.data$fcs_gap, 1L, as.integer(.data$tier)),
      tier_label = dplyr::if_else(
        .data$fcs_gap,
        "FCS and below",
        .data$tier_label
      )
    ) |>
    dplyr::select(
      "team_id",
      "season",
      "conference",
      "classification",
      "tier",
      "tier_label",
      "games",
      "wins",
      "losses",
      "ties",
      "elo_end"
    )
}

#' Explorer team dimension
#'
#' Display fields for every team in the team-season export, stored once so
#' `team_season.json` carries ids only (decision 0046). Colors go through the
#' shared valid-hex filter, falling back to the shared grey.
#'
#' @param teams Cleaned teams.
#' @param team_season Output of [build_explorer_team_season()].
#' @return A tibble keyed by `team_id`.
#' @export
build_explorer_teams <- function(teams, team_season) {
  valid <- team_color_values(teams)
  teams |>
    dplyr::filter(.data$team_id %in% team_season$team_id) |>
    dplyr::transmute(
      team_id = .data$team_id,
      team = .data$team,
      mascot = .data$mascot,
      abbreviation = .data$abbreviation,
      color = dplyr::coalesce(unname(valid[.data$team]), "#6b7280"),
      alt_color = dplyr::if_else(
        grepl("^#[0-9A-Fa-f]{6}$", .data$alt_color),
        .data$alt_color,
        NA_character_
      ),
      logo = .data$logo_light
    ) |>
    dplyr::arrange(.data$team)
}

#' Source tables behind each explorer visual
#'
#' The page prints these as a "Data:" line linking to each table on the Data
#' page, so readers can look up where a chart comes from.
#'
#' @return A named list: visual key -> character vector of table names.
#' @export
explorer_sources <- function() {
  list(
    teams_landscape = c("games", "teams", "conference_tiers"),
    team_view = c("games", "teams", "conference_tiers"),
    team_season = c("games", "teams"),
    game_timeline = c("plays", "play_types", "games", "play_stats"),
    players = c(
      "player_stats",
      "roster",
      "teams",
      "conference_tiers",
      "outcomes",
      "picks"
    ),
    combine = c("combine", "outcomes", "picks"),
    careers = c("picks", "nfl_draft_picks", "nfl_rosters", "roster"),
    map = c("teams", "games")
  )
}

#' Explorer page metadata
#'
#' @param games Cleaned games.
#' @return A list: `default_season`, `seasons`, `default_team` (Texas, CFBD
#'   team id 251), `sources`.
#' @export
build_explorer_meta <- function(games) {
  done <- games$season[games$completed %in% TRUE]
  list(
    default_season = explorer_default_season(games),
    seasons = sort(unique(as.integer(done))),
    default_team = 251L,
    sources = explorer_sources()
  )
}

#' Serialize an explorer asset
#'
#' Data frames become arrays of row objects with `null` for NA; length-1
#' vectors become scalars, so `meta.json` reads naturally in JS.
#'
#' @param x A data frame or list.
#' @return A `json` string.
#' @export
explorer_json <- function(x) {
  jsonlite::toJSON(
    x,
    dataframe = "rows",
    na = "null",
    auto_unbox = TRUE,
    digits = NA
  )
}

#' Gzipped size of an explorer asset
#'
#' Approximates what GitHub Pages transfers (`memCompress()` returns a zlib
#' stream, a few bytes off true gzip); the first-view budget is set in these
#' bytes (decision 0046).
#'
#' @param x A data frame or list.
#' @return Integer bytes.
#' @export
explorer_json_gzip_bytes <- function(x) {
  length(memCompress(charToRaw(explorer_json(x)), "gzip"))
}

#' Write explorer assets
#'
#' @param assets Named list of data frames / lists; names become file names.
#' @param dir Output directory (created if missing).
#' @return The written file paths, for a `format = "file"` target.
#' @export
write_explorer_assets <- function(assets, dir = "vignettes/explorer-data") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, paste0(names(assets), ".json"))
  for (i in seq_along(assets)) {
    writeLines(explorer_json(assets[[i]]), paths[[i]])
  }
  paths
}
