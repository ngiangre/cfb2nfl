# Playing time from game_player_stats (issue #50, decision 0038): games
# appeared out of team games, per player-season-team, plus per-game usage
# proxies. Built from player_game (decision 0035) as a contract-checked
# pipeline step, read with tar_read(player_usage); not in the DuckDB asset
# (decision 0041).
#
# "Appeared" means the player has at least one stat line in the game. CFBD
# lists a stat line only when the player recorded something, so offensive
# linemen and many special-teamers log none even when they play. Read the
# appearance rate per position group with that in mind (see the post).

#' Team games played, from completed games with scores
#'
#' The same definition [team_record()] uses for `games_played` (decision
#' 0035): a game counts when it is completed and both scores are present,
#' postseason included. One row per team per game, so a team's count of
#' rows in a season equals its `games_played`.
#'
#' @param games Cleaned games ([clean_games()]).
#' @return One row per `(gameId, team)`: `season`, `week`, `seasonType`,
#'   `gameId`, `team`.
#' @export
team_game_schedule <- function(games) {
  done <- games |>
    dplyr::filter(
      .data$completed,
      !is.na(.data$homePoints),
      !is.na(.data$awayPoints)
    )
  side <- function(team) {
    done |>
      dplyr::transmute(
        season = as.integer(.data$season),
        week = as.integer(.data$week),
        seasonType = .data$seasonType,
        gameId = as.integer(.data$id),
        team = .data[[team]]
      )
  }
  dplyr::bind_rows(side("homeTeam"), side("awayTeam"))
}

# Every player-season-team to score: the roster's rows plus any player-season
# with a stat line that the roster lacks (about 1.7k of 78k stat-line
# player-season-teams are off the roster). Taking the union means no
# stat-line player is dropped from the usage table.
player_season_universe <- function(player_game, roster) {
  from_roster <- roster |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      team = .data$team
    )
  from_stats <- player_game |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      team = .data$team
    )
  dplyr::bind_rows(from_roster, from_stats) |>
    dplyr::distinct()
}

#' Appearance sequence: every team game for every player-season
#'
#' For each player-season-team, one row per game the team played that season
#' (from [team_game_schedule()]), flagged `appeared` when the player has a
#' stat line in that game. This is the input for issue #51: a run of
#' consecutive `FALSE` rows in the middle of a season, for a player who
#' appeared in most games, is a gap that may be injury-shaped. Rows with no
#' appearance are kept, so the sequence is complete for every player-season.
#'
#' Player-seasons whose team has no completed game in the season (for example
#' a season still in progress) produce no rows here.
#'
#' @param player_game Output of [build_player_game()].
#' @param roster Cleaned roster ([clean_roster()]); its player-seasons are the
#'   universe, unioned with the player-seasons in `player_game`.
#' @param games Cleaned games ([clean_games()]).
#' @return One row per `(playerId, season, team, gameId)`: `week`,
#'   `seasonType` and `appeared` (logical).
#' @export
player_appearance_sequence <- function(player_game, roster, games) {
  universe <- player_season_universe(player_game, roster)
  appeared <- player_game |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      gameId = as.integer(.data$gameId),
      team = .data$team
    ) |>
    dplyr::distinct() |>
    dplyr::mutate(appeared = TRUE)

  team_game_schedule(games) |>
    dplyr::inner_join(
      universe,
      by = c("season", "team"),
      relationship = "many-to-many"
    ) |>
    dplyr::left_join(appeared, by = c("playerId", "gameId", "team")) |>
    dplyr::mutate(appeared = dplyr::coalesce(.data$appeared, FALSE)) |>
    dplyr::select(
      "playerId",
      "season",
      "team",
      "gameId",
      "week",
      "seasonType",
      "appeared"
    ) |>
    dplyr::arrange(.data$season, .data$team, .data$playerId, .data$gameId)
}

#' Build the player usage table
#'
#' One row per `(playerId, season, team)`. `team_games` is the team's games
#' played in the season (all divisions, postseason included; the
#' [team_record()] count). `games_appeared` counts those games in which the
#' player has a stat line, so `appearance_rate` is games appeared over team
#' games. The `reg_` columns repeat both counts for regular-season games only.
#'
#' Per-game proxies (`pass_att_pg`, `rush_car_pg`, `rec_pg`, `tackles_pg`) are
#' the player's total in that stat over games appeared, divided by
#' `games_appeared`; they are `NA` when the player appeared in no game. A
#' stat absent from a game counts as zero for that game.
#'
#' `position_group` is the harmonized roster position for that team-season
#' ([harmonize_position()], `"roster"` source). `on_roster` is `FALSE` for a
#' player-season that appears only in the game stats; its position and class
#' year are then `NA`.
#'
#' @param player_game Output of [build_player_game()].
#' @param roster Cleaned roster ([clean_roster()]).
#' @param games Cleaned games ([clean_games()]).
#' @return One row per `(playerId, season, team)`.
#' @export
build_player_usage <- function(player_game, roster, games) {
  seq <- player_appearance_sequence(player_game, roster, games)
  universe <- player_season_universe(player_game, roster)

  counts <- seq |>
    dplyr::group_by(.data$playerId, .data$season, .data$team) |>
    dplyr::summarise(
      team_games = dplyr::n(),
      games_appeared = sum(.data$appeared),
      reg_team_games = sum(.data$seasonType == "regular"),
      reg_games_appeared = sum(.data$appeared & .data$seasonType == "regular"),
      .groups = "drop"
    )

  per_game_cols <- c("pass_att", "rush_car", "rec", "tackles")
  totals <- player_game |>
    dplyr::mutate(playerId = as.character(.data$playerId)) |>
    dplyr::group_by(.data$playerId, .data$season, .data$team) |>
    dplyr::summarise(
      dplyr::across(dplyr::all_of(per_game_cols), \(x) sum(x, na.rm = TRUE)),
      .groups = "drop"
    )

  attrs <- roster |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      team = .data$team,
      position_group = harmonize_position(.data$position, "roster"),
      class_year = as.integer(.data$class_year),
      on_roster = TRUE
    ) |>
    dplyr::distinct(.data$playerId, .data$season, .data$team, .keep_all = TRUE)

  out <- universe |>
    dplyr::left_join(counts, by = c("playerId", "season", "team")) |>
    dplyr::left_join(totals, by = c("playerId", "season", "team")) |>
    dplyr::left_join(attrs, by = c("playerId", "season", "team")) |>
    dplyr::mutate(
      team_games = dplyr::coalesce(.data$team_games, 0L),
      games_appeared = dplyr::coalesce(.data$games_appeared, 0L),
      reg_team_games = dplyr::coalesce(.data$reg_team_games, 0L),
      reg_games_appeared = dplyr::coalesce(.data$reg_games_appeared, 0L),
      on_roster = dplyr::coalesce(.data$on_roster, FALSE),
      appearance_rate = dplyr::if_else(
        .data$team_games > 0,
        .data$games_appeared / .data$team_games,
        NA_real_
      ),
      reg_appearance_rate = dplyr::if_else(
        .data$reg_team_games > 0,
        .data$reg_games_appeared / .data$reg_team_games,
        NA_real_
      ),
      dplyr::across(
        dplyr::all_of(per_game_cols),
        \(x) dplyr::if_else(.data$games_appeared > 0, x, NA_real_)
      )
    )

  # Per-game means: total over games appeared, divided by games appeared.
  out <- out |>
    dplyr::mutate(
      dplyr::across(
        dplyr::all_of(per_game_cols),
        \(x) x / .data$games_appeared,
        .names = "{.col}_pg"
      )
    ) |>
    dplyr::select(-dplyr::all_of(per_game_cols))

  out |>
    dplyr::mutate(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      team_games = as.integer(.data$team_games),
      games_appeared = as.integer(.data$games_appeared),
      reg_team_games = as.integer(.data$reg_team_games),
      reg_games_appeared = as.integer(.data$reg_games_appeared),
      position_group = dplyr::if_else(
        .data$on_roster,
        .data$position_group,
        NA_character_
      ),
      class_year = as.integer(.data$class_year)
    ) |>
    dplyr::select(
      "playerId",
      "season",
      "team",
      "position_group",
      "class_year",
      "on_roster",
      "team_games",
      "games_appeared",
      "appearance_rate",
      "reg_team_games",
      "reg_games_appeared",
      "reg_appearance_rate",
      "pass_att_pg",
      "rush_car_pg",
      "rec_pg",
      "tackles_pg"
    ) |>
    dplyr::arrange(.data$season, .data$team, .data$playerId)
}
