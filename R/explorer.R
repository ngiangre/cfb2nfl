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
