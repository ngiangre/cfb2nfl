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
