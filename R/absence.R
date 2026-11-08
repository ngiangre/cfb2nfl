# Absence-shaped signals from the game-level data (issue #51, part 2). CFBD has
# no injury or depth-chart feed, so injured versus benched can only be read
# from the shape of a player's season: a regular who stops appearing
# (injury-shaped) or one who keeps appearing with less of the ball
# (benching-shaped). Both are heuristics that the data cannot validate, and
# neither is a label (decision 0039). Built on the fly in the post that needs
# them, not pipeline targets (decision 0041).

#' Classify one season's appearance sequence
#'
#' A gap is a run of at least `min_gap` consecutive team games without a stat
#' line, immediately after at least `streak` consecutive games with one (so the
#' player was a regular when it began). A gap that reaches the last team game is
#' `season_ending`, one followed by a return is `returned`; season-ending wins
#' when a season has both. A season with no `streak`-game run of appearances is
#' `not_observable`: there is no regular role for a gap to interrupt.
#'
#' @param appeared Logical, one element per team game in chronological order.
#' @param streak Appearances in a row that make a player a regular.
#' @param min_gap Missed games in a row that make a gap.
#' @return A list: `shape` (`"none"`, `"returned"`, `"season_ending"`,
#'   `"not_observable"`) and `gap_games` (length of the gap behind the shape,
#'   `0` when none).
#' @noRd
classify_absence <- function(appeared, streak = 3L, min_gap = 2L) {
  runs <- rle(as.logical(appeared))
  if (!any(runs$values & runs$lengths >= streak)) {
    return(list(shape = "not_observable", gap_games = 0L))
  }
  n <- length(runs$lengths)
  gap <- !runs$values &
    runs$lengths >= min_gap &
    c(FALSE, utils::head(runs$values & runs$lengths >= streak, -1L))
  if (!any(gap)) {
    return(list(shape = "none", gap_games = 0L))
  }
  if (gap[n]) {
    return(list(shape = "season_ending", gap_games = runs$lengths[n]))
  }
  list(shape = "returned", gap_games = max(runs$lengths[gap]))
}

#' Injury-shaped absences in each player-season
#'
#' Applies the gap rule (a regular who then misses `min_gap` or more games in a
#' row) to every player-season-team in an appearance sequence. Games are
#' ordered regular season first, then postseason, by week. A team game in
#' which no one on the team has a stat line has no box score (common against
#' lower-division opponents), so it is dropped rather than read as a miss for
#' every player. The result says only that a regular stopped logging a stat
#' line: injury, suspension, illness, a depth-chart change, or a role with no
#' box-score line all look the same.
#'
#' @param seq Output of [player_appearance_sequence()]: one row per
#'   `(playerId, season, team, gameId)` with `week`, `seasonType`, `appeared`.
#' @param streak Appearances in a row that make a player a regular (3).
#' @param min_gap Missed games in a row that make a gap (2).
#' @return One row per `(playerId, season, team)` with at least one team game
#'   that has a box score: `box_games` (those games), `games_appeared`,
#'   `observable` (the player had a regular run to interrupt), `absence_shape`
#'   (`none`, `returned`, `season_ending`, `not_observable`) and `gap_games`.
#' @export
absence_runs <- function(seq, streak = 3L, min_gap = 2L) {
  ordered <- seq |>
    dplyr::group_by(.data$season, .data$team, .data$gameId) |>
    dplyr::filter(any(.data$appeared)) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      type_order = match(.data$seasonType, c("regular", "postseason"))
    ) |>
    dplyr::arrange(
      .data$playerId,
      .data$season,
      .data$team,
      .data$type_order,
      .data$week,
      .data$gameId
    )
  counts <- ordered |>
    dplyr::group_by(.data$playerId, .data$season, .data$team) |>
    dplyr::summarise(
      box_games = dplyr::n(),
      games_appeared = sum(.data$appeared),
      .groups = "drop"
    )
  # Only seasons with at least `streak` appearances can hold a regular run;
  # scoring the rest one by one would be slow and always `not_observable`.
  candidates <- counts |>
    dplyr::filter(.data$games_appeared >= streak) |>
    dplyr::select("playerId", "season", "team")
  shapes <- ordered |>
    dplyr::semi_join(candidates, by = c("playerId", "season", "team")) |>
    dplyr::group_by(.data$playerId, .data$season, .data$team) |>
    dplyr::summarise(
      cls = list(classify_absence(.data$appeared, streak, min_gap)),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      absence_shape = purrr::map_chr(.data$cls, "shape"),
      gap_games = purrr::map_int(.data$cls, "gap_games")
    ) |>
    dplyr::select(-"cls")
  counts |>
    dplyr::left_join(shapes, by = c("playerId", "season", "team")) |>
    dplyr::mutate(
      absence_shape = dplyr::coalesce(.data$absence_shape, "not_observable"),
      gap_games = dplyr::coalesce(.data$gap_games, 0L),
      observable = .data$absence_shape != "not_observable"
    ) |>
    dplyr::select(
      "playerId",
      "season",
      "team",
      "box_games",
      "games_appeared",
      "observable",
      "absence_shape",
      "gap_games"
    )
}

#' The per-game usage stat read for each position group
#'
#' One box-score count per position group, the one a starter at that position
#' piles up, with the per-game floor that marks starter-level usage. Offensive
#' line, special teams, athletes and unrecorded positions have no such count
#' in `player_game`, so they are absent and their usage cannot be followed.
#'
#' @return A tibble: `position_group`, `usage_column` (a `player_game` column),
#'   `usage_label` (reader-facing), `floor` (per-game mean in the first half
#'   that makes the player a regular user).
#' @export
usage_signal_map <- function() {
  tibble::tribble(
    ~position_group  , ~usage_column , ~usage_label    , ~floor ,
    "Quarterback"    , "pass_att"    , "pass attempts" ,     15 ,
    "Running back"   , "rush_car"    , "carries"       ,      8 ,
    "Receiver"       , "rec"         , "receptions"    ,      3 ,
    "Tight end"      , "rec"         , "receptions"    ,      2 ,
    "Defensive line" , "tackles"     , "tackles"       ,      2 ,
    "Linebacker"     , "tackles"     , "tackles"       ,      4 ,
    "Defensive back" , "tackles"     , "tackles"       ,      3
  )
}

#' Benching-shaped usage declines in each player-season
#'
#' Splits a player-season's games appeared, in chronological order, into a
#' first half (the earlier `ceiling(n / 2)`) and a second half, and compares the
#' mean of the position's usage stat ([usage_signal_map()]) in each. A season is
#' observable when the player appeared in at least `min_games` games and the
#' first-half mean reaches the position's floor; it `declined` when the
#' second-half mean is at most `ratio` of the first. A game appeared with no
#' line in the usage stat counts as zero. The player kept taking the field, so
#' this is benching-shaped, but a smaller role, a scheme change, or playing
#' through an injury look the same.
#'
#' @param player_game Output of [build_player_game()].
#' @param positions One row per `(playerId, season, team)` with
#'   `position_group` (for example from `player_usage`).
#' @param min_games Games appeared needed to compare halves (6).
#' @param ratio Second-half share of first-half usage at or below which the
#'   season counts as a decline (0.5).
#' @return One row per `(playerId, season, team)` at a position in
#'   [usage_signal_map()] with any games: `position_group`, `usage_label`,
#'   `games_appeared`, `first_half`, `second_half` (per-game means),
#'   `observable` and `declined`.
#' @export
usage_decline <- function(player_game, positions, min_games = 6L, ratio = 0.5) {
  map <- usage_signal_map()
  pos <- positions |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      team = .data$team,
      position_group = .data$position_group
    ) |>
    dplyr::inner_join(map, by = "position_group")

  games <- player_game |>
    dplyr::mutate(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      type_order = match(.data$seasonType, c("regular", "postseason"))
    ) |>
    dplyr::inner_join(pos, by = c("playerId", "season", "team"))
  # Pick each row's usage stat by its position; NA (no line) counts as zero.
  stat_cols <- unique(map$usage_column)
  usage_value <- rep(NA_real_, nrow(games))
  for (col in stat_cols) {
    hit <- games$usage_column == col
    usage_value[hit] <- as.numeric(games[[col]][hit])
  }
  games$usage <- dplyr::coalesce(usage_value, 0)

  games |>
    dplyr::arrange(
      .data$playerId,
      .data$season,
      .data$team,
      .data$type_order,
      .data$week,
      .data$gameId
    ) |>
    dplyr::group_by(
      .data$playerId,
      .data$season,
      .data$team,
      .data$position_group,
      .data$usage_label,
      .data$floor
    ) |>
    dplyr::summarise(
      games_appeared = dplyr::n(),
      first_half = mean(.data$usage[seq_len(ceiling(dplyr::n() / 2))]),
      second_half = mean(.data$usage[-seq_len(ceiling(dplyr::n() / 2))]),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      observable = .data$games_appeared >= min_games &
        .data$first_half >= .data$floor,
      declined = .data$observable &
        .data$second_half <= ratio * .data$first_half
    ) |>
    dplyr::select(
      "playerId",
      "season",
      "team",
      "position_group",
      "usage_label",
      "games_appeared",
      "first_half",
      "second_half",
      "observable",
      "declined"
    )
}
