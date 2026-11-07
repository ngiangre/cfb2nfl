# Opponent-adjusted game production (issue #47, decision 0037). Built on the fly
# from the player x game table (decision 0035) where an investigation needs it,
# not bundled into the DuckDB asset (decision 0041).

# The per-game yardage columns of player_game that are adjusted.
game_production_stat_cols <- c("pass_yds", "rush_yds", "rec_yds")

#' Opponent Elo band
#'
#' Buckets a CFBD pregame Elo rating into the bands the opponent-adjusted
#' production uses. Opponents with no Elo (mostly FCS and lower-division teams,
#' which CFBD does not rate) form their own `"Unrated"` band rather than being
#' dropped or imputed.
#'
#' @param elo Numeric pregame Elo of the opponent (`NA` when unrated).
#' @return A character vector of band labels, ordered as
#'   `opponent_elo_band_levels`.
#' @export
opponent_elo_band <- function(elo) {
  band <- dplyr::case_when(
    is.na(elo) ~ "Unrated",
    elo < 1400 ~ "Under 1400",
    elo < 1600 ~ "1400 to 1599",
    elo < 1800 ~ "1600 to 1799",
    TRUE ~ "1800 and up"
  )
  as.character(factor(band, levels = opponent_elo_band_levels))
}

# Band order, shortest opponent first; "Unrated" last.
opponent_elo_band_levels <- c(
  "Under 1400",
  "1400 to 1599",
  "1600 to 1799",
  "1800 and up",
  "Unrated"
)

#' Opponent-adjusted game production
#'
#' Turns the player x game table into one row per player-game-stat for the
#' passing, rushing and receiving yardage columns, with a residual against a
#' baseline. The baseline is the mean value of that stat over every player-game
#' in the same season and opponent Elo band that has a line in that category
#' (`value` is not `NA`). So `residual > 0` means the player gained more in that
#' game than the typical player with a line in that category did against
#' opponents of the same strength in the same season. A stat that is `NA` in
#' `player_game` (no line in that category) produces no row.
#'
#' Groups are formed within `(season, stat, opponent_elo_band)`, so every row
#' keeps its own group's baseline and no join can fan out or drop rows.
#'
#' @param player_game Output of [build_player_game()].
#' @return One row per `(playerId, gameId, stat)`: `playerId`, `gameId`,
#'   `season`, `week`, `team`, `opponent`, `opponent_elo_band`, `stat` (the
#'   `player_game` column name), `value`, `baseline` (mean in the group),
#'   `band_n` (player-games in the group), `residual` (`value - baseline`).
#' @export
build_game_production <- function(player_game) {
  long <- player_game |>
    dplyr::transmute(
      .data$playerId,
      .data$gameId,
      .data$season,
      .data$week,
      .data$team,
      .data$opponent,
      opponent_elo_band = opponent_elo_band(.data$opponent_pregame_elo),
      dplyr::across(dplyr::all_of(game_production_stat_cols))
    ) |>
    tidyr::pivot_longer(
      dplyr::all_of(game_production_stat_cols),
      names_to = "stat",
      values_to = "value",
      values_drop_na = TRUE
    )

  long |>
    dplyr::group_by(.data$season, .data$stat, .data$opponent_elo_band) |>
    dplyr::mutate(
      baseline = mean(.data$value),
      band_n = dplyr::n(),
      residual = .data$value - .data$baseline
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      gameId = as.integer(.data$gameId),
      band_n = as.integer(.data$band_n)
    ) |>
    dplyr::select(
      "playerId",
      "gameId",
      "season",
      "week",
      "team",
      "opponent",
      opponent_elo_band = "opponent_elo_band",
      "stat",
      "value",
      "baseline",
      "band_n",
      "residual"
    ) |>
    dplyr::arrange(.data$season, .data$gameId, .data$playerId, .data$stat)
}
