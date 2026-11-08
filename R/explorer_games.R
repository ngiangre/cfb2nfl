# Explorer game-level assets (plans/explorer.md step 3, decision 0046): each
# team's side of each game, and slim per-season play files for the game
# timeline.

#' Elo expected win probability
#'
#' @param elo,opp_elo Ratings of the team and its opponent.
#' @return The team's expected win probability, `1 / (1 + 10^(-(elo - opp_elo) / 400))`.
#' @export
explorer_elo_expectation <- function(elo, opp_elo) {
  1 / (1 + 10^(-(elo - opp_elo) / 400))
}

#' Explorer team-games table
#'
#' One row per FBS/FCS team per completed, scored game, from that team's side:
#' site (and whether the team is the listed home side, kept at neutral sites),
#' score, result, Elo before and after, the Elo expected win
#' probability before kickoff, CFBD's postgame win probability, and whether
#' the game has play-by-play. Rows match the team-season records exactly.
#'
#' @param games Cleaned games.
#' @param team_season Output of [build_explorer_team_season()].
#' @param play_game_ids Game ids that have rows in `plays`.
#' @return A tibble keyed by `(team_id, game_id)`.
#' @export
build_explorer_team_games <- function(games, team_season, play_game_ids) {
  done <- dplyr::filter(
    games,
    .data$completed %in% TRUE,
    !is.na(.data$homePoints),
    !is.na(.data$awayPoints)
  )
  side <- function(us, them) {
    dplyr::transmute(
      done,
      season = .data$season,
      week = .data$week,
      season_type = .data$seasonType,
      start = .data$startDate,
      game_id = .data$id,
      team_id = .data[[paste0(us, "Id")]],
      opp_id = .data[[paste0(them, "Id")]],
      opp_name = .data[[paste0(them, "Team")]],
      site = dplyr::if_else(.data$neutralSite %in% TRUE, "neutral", us),
      home = us == "home",
      points = .data[[paste0(us, "Points")]],
      opp_points = .data[[paste0(them, "Points")]],
      elo_pre_raw = .data[[paste0(us, "PregameElo")]],
      opp_elo_pre = .data[[paste0(them, "PregameElo")]],
      elo_post_raw = .data[[paste0(us, "PostgameElo")]],
      wp_post = round(.data[[paste0(us, "PostgameWinProbability")]], 3)
    )
  }
  dplyr::bind_rows(side("home", "away"), side("away", "home")) |>
    dplyr::semi_join(team_season, by = c("team_id", "season")) |>
    dplyr::mutate(
      result = dplyr::case_when(
        .data$points > .data$opp_points ~ "W",
        .data$points < .data$opp_points ~ "L",
        .default = "T"
      ),
      elo_pre = as.integer(round(.data$elo_pre_raw)),
      elo_post = as.integer(round(.data$elo_post_raw)),
      elo_delta = as.integer(round(.data$elo_post_raw - .data$elo_pre_raw)),
      wp_pre = round(
        explorer_elo_expectation(.data$elo_pre_raw, .data$opp_elo_pre),
        3
      ),
      has_plays = .data$game_id %in% play_game_ids
    ) |>
    dplyr::arrange(.data$team_id, .data$season, .data$start) |>
    dplyr::select(
      "season",
      "week",
      "season_type",
      "start",
      "game_id",
      "team_id",
      "opp_id",
      "opp_name",
      "site",
      "home",
      "points",
      "opp_points",
      "result",
      "elo_pre",
      "elo_post",
      "elo_delta",
      "wp_pre",
      "wp_post",
      "has_plays"
    )
}
