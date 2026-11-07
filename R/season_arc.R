# Season arcs (issue #47, plans/explore-questions.md question 6): one stat per
# player, one row per season, indexed by the player's career season. Built on
# the fly from the cleaned player_stats where an investigation needs it, not
# bundled into the DuckDB asset (decision 0041).

# The (category, statType) stats carried by the season-arc table. Each is a
# count or yardage that a fan can read as "how much did he do this year".
season_arc_stat_map <- tibble::tribble(
  ~category   , ~statType , ~label            ,
  "passing"   , "YDS"     , "Passing yards"   ,
  "rushing"   , "YDS"     , "Rushing yards"   ,
  "receiving" , "YDS"     , "Receiving yards" ,
  "defensive" , "TOT"     , "Tackles"
)

#' Season arc for one stat
#'
#' Pivots one `(category, statType)` stat of the long `player_stats` into one
#' row per player-season. A player on two teams in one season (27 player-seasons
#' in the data, all transfers) is summed across the team rows, so the value is
#' the season total. `season_index` is the player's career season: `1` for the
#' first season with any stat line in `player_stats`, counted over all stats so
#' an index means the same season in every arc. The data starts in 2010, so a
#' player who began earlier has index 1 at his first season in the data.
#'
#' @param player_stats Cleaned long player stats ([clean_player_stats()] output;
#'   key `playerId`, `season`, `team`, `category`, `statType`, `stat`).
#' @param category,stat_type A `category` and `statType` pair, e.g. `"passing"`
#'   and `"YDS"`.
#'
#' @return One row per `(playerId, season)` with the stat line, with columns
#'   `playerId`, `player`, `season`, `season_index`, `team` (the team with the
#'   larger share of the season), `category`, `statType`, `value`.
#' @export
season_arc <- function(player_stats, category, stat_type) {
  career_index <- player_stats |>
    dplyr::distinct(.data$playerId, .data$season) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(season_index = as.integer(dplyr::dense_rank(.data$season))) |>
    dplyr::ungroup()

  per_team <- player_stats |>
    dplyr::filter(
      .data$category == .env$category,
      .data$statType == .env$stat_type
    ) |>
    dplyr::mutate(value = suppressWarnings(as.numeric(.data$stat))) |>
    dplyr::filter(!is.na(.data$value)) |>
    dplyr::group_by(.data$playerId, .data$player, .data$season, .data$team) |>
    dplyr::summarise(value = sum(.data$value), .groups = "drop")

  per_team |>
    dplyr::group_by(.data$playerId, .data$season) |>
    dplyr::summarise(
      player = .data$player[1],
      team = .data$team[which.max(.data$value)],
      value = sum(.data$value),
      .groups = "drop"
    ) |>
    dplyr::left_join(career_index, by = c("playerId", "season")) |>
    dplyr::mutate(
      category = .env$category,
      statType = .env$stat_type
    ) |>
    dplyr::select(
      "playerId",
      "player",
      "season",
      "season_index",
      "team",
      "category",
      "statType",
      "value"
    ) |>
    dplyr::arrange(.data$playerId, .data$season)
}

#' Season arcs for the headline stats
#'
#' Binds [season_arc()] over `stat_map` (by default the headline stat table
#' defined at the top of this file) into one
#' long table keyed by `(playerId, season, category, statType)`.
#'
#' @param player_stats Cleaned long player stats.
#' @param stat_map A table with `category` and `statType` columns.
#' @return The stacked [season_arc()] outputs.
#' @export
build_season_arcs <- function(player_stats, stat_map = season_arc_stat_map) {
  arcs <- lapply(seq_len(nrow(stat_map)), function(i) {
    season_arc(player_stats, stat_map$category[[i]], stat_map$statType[[i]])
  })
  dplyr::bind_rows(arcs)
}
