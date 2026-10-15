# Features: longitudinal (career-sequence) change features (decision 0003).
# Each player's seasons are linked chronologically by athlete id and lag/delta
# features are attached to the player-season row. Lags may only use prior-season
# data (no leakage from the predicted draft class); the model stage enforces the
# out-of-time split.

#' Summarize each player's college career from the roster backbone
#'
#' Collapses the roster player-season grain (question 4 of the Explore plan) to
#' one row per player: seasons on a roster, first/last season, gap seasons
#' (years absent between first and last — an injury- or redshirt-shaped gap),
#' and transfer count (distinct teams minus one). Built on the **roster**
#' backbone so it includes no-stat seasons, unlike `player_stats`.
#'
#' @param roster Cleaned roster from [clean_roster()] with `playerId`, `season`,
#'   `team`.
#'
#' @return One row per `playerId` with `seasons`, `first_season`,
#'   `last_season`, `gap_seasons`, `teams`, `transfers`.
#' @export
career_summary <- function(roster) {
  roster |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      seasons = dplyr::n_distinct(.data$season),
      first_season = min(.data$season),
      last_season = max(.data$season),
      teams = dplyr::n_distinct(.data$team),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      gap_seasons = .data$last_season - .data$first_season + 1L - .data$seasons,
      transfers = .data$teams - 1L,
      .after = .data$teams
    )
}

#' Add between-season change features
#'
#' Sorts each athlete's seasons chronologically and derives:
#' - `transferred` — team differs from prior season;
#' - `transfer_direction` — `up` / `lateral` / `down` from the tier delta;
#' - `hc_changed` — head coach differs from prior season;
#' - `followed_coach` — same head coach as prior season *and* transferred.
#'
#' Requires the tier and coach columns already attached
#' ([link_tiers()], [link_coaches()]).
#'
#' @param player_season Player-season table with `team`, `tier`, `coach_id`.
#'
#' @return `player_season` with the change features and prior-season lags added.
#' @export
add_change_features <- function(player_season) {
  player_season |>
    dplyr::arrange(.data$playerId, .data$season) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(
      prev_team = dplyr::lag(.data$team),
      prev_tier = dplyr::lag(.data$tier),
      prev_coach_id = dplyr::lag(.data$coach_id),
      transferred = !is.na(.data$prev_team) & .data$team != .data$prev_team,
      transfer_direction = dplyr::case_when(
        is.na(.data$prev_tier) | is.na(.data$tier) ~ NA_character_,
        .data$tier > .data$prev_tier ~ "up",
        .data$tier < .data$prev_tier ~ "down",
        TRUE ~ "lateral"
      ),
      hc_changed = !is.na(.data$prev_coach_id) &
        .data$coach_id != .data$prev_coach_id,
      followed_coach = .data$transferred &
        !is.na(.data$prev_coach_id) &
        .data$coach_id == .data$prev_coach_id
    ) |>
    dplyr::ungroup()
}

#' Attach roster weight
#'
#' Joins the player's listed roster weight by athlete id and season.
#'
#' Note (decision 0003 Outcome): the CFBD `/roster` endpoint reports a **static**
#' weight per player — repeated across every season, with no year-over-year
#' variation (0 of ~44k multi-season players show any change). A between-season
#' `weight_delta` is therefore not derivable from this source, so we keep the
#' static physical attribute only. A career-span change (e.g. recruiting vs.
#' draft weight) would need a different source.
#'
#' @param player_season Player-season table keyed by `playerId`, `season`.
#' @param roster Cleaned roster from [clean_roster()] (must include `weight`).
#'
#' @return `player_season` with the static roster `weight` attached.
#' @export
add_roster_weight <- function(player_season, roster) {
  weight_by_season <- roster |>
    dplyr::filter(!is.na(.data$weight)) |>
    dplyr::group_by(.data$playerId, .data$season) |>
    dplyr::summarise(weight = dplyr::first(.data$weight), .groups = "drop")

  player_season |>
    dplyr::left_join(weight_by_season, by = c("playerId", "season"))
}
