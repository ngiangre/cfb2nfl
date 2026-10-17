# Features: longitudinal (career-sequence) change features (decision 0003).
# Each player's seasons are linked chronologically by athlete id and lag/delta
# features are attached to the player-season row. Lags may only use prior-season
# data (no leakage from the predicted draft class); the model stage enforces the
# out-of-time split.

#' Flag athlete ids whose roster span exceeds a plausible single career
#'
#' CFBD athlete ids are occasionally **reused across distinct individuals**: the
#' same id (one name, one team) appears on rosters across an impossible span —
#' e.g. a Cal DB listed 2010-2023. These are almost certainly multiple real
#' players sharing a recycled id, not one career (decision 0022). Returns the
#' suspect ids so downstream steps can exclude them from the career/model
#' population.
#'
#' @param roster Cleaned roster from [clean_roster()].
#' @param max_span Maximum plausible span in seasons (default 7; NCAA eligibility
#'   allows at most ~5-6 seasons even with the COVID year and medical hardship).
#'
#' @return A character vector of suspect `playerId`s.
#' @export
reused_ids <- function(roster, max_span = 7L) {
  roster |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      span = max(.data$season) - min(.data$season) + 1L,
      .groups = "drop"
    ) |>
    dplyr::filter(.data$span > .env$max_span) |>
    dplyr::pull(.data$playerId)
}

#' Summarize each player's college career from the roster backbone
#'
#' Collapses the roster player-season grain (question 4 of the Explore plan) to
#' one row per player: seasons on a roster, first/last season, gap seasons
#' (years absent between first and last — an injury- or redshirt-shaped gap),
#' and transfer count (distinct teams minus one). Built on the **roster**
#' backbone so it includes no-stat seasons, unlike `player_stats`.
#'
#' Ids whose roster span exceeds `max_span` are excluded: a span that long is
#' CFBD id reuse across distinct individuals, not one career (decision 0022).
#'
#' @param roster Cleaned roster from [clean_roster()] with `playerId`, `season`,
#'   `team`.
#' @param max_span Maximum plausible career span in seasons (see
#'   [reused_ids()]).
#'
#' @return One row per `playerId` with `seasons`, `first_season`,
#'   `last_season`, `gap_seasons`, `teams`, `transfers`.
#' @export
career_summary <- function(roster, max_span = 7L) {
  roster |>
    dplyr::filter(!.data$playerId %in% reused_ids(roster, max_span)) |>
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
      .after = "teams"
    )
}

#' Count transfers by season and tier direction
#'
#' Aggregates the per-season change features ([add_change_features()]) into
#' season × direction counts for the Explore question-5 viz. Direction is the
#' season-aware tier move (decision 0003): `up` (to a higher tier), `down`,
#' `lateral`. A transfer between seasons separated by a gap is still caught
#' (lag compares to the prior observed season), but a transfer to/from a season
#' with no roster row is invisible at this grain.
#'
#' @param ps_change Player-season table with `season`, `transferred`,
#'   `transfer_direction` (see [add_change_features()]).
#'
#' @return One row per `season` × `transfer_direction` with `n_transfers`.
#' @export
transfer_counts <- function(ps_change) {
  ps_change |>
    dplyr::filter(.data$transferred) |>
    dplyr::count(.data$season, .data$transfer_direction, name = "n_transfers")
}

#' Share of careers with at least one transfer
#'
#' Career-grain transfer rate from [career_summary()] — the full roster
#' backbone, so it includes players with no stat line (the `ps_change`-based
#' per-season counts do not). A player changing teams is a transfer; a gap
#' season (e.g. sitting out) between two schools still counts once.
#'
#' @param career Per-player career summary (see [career_summary()]).
#'
#' @return A one-row tibble with `players`, `transferred`, and `share`.
#' @export
transfer_rate <- function(career) {
  career |>
    dplyr::summarise(
      players = dplyr::n(),
      transferred = sum(.data$transfers > 0L),
      share = .data$transferred / .data$players
    )
}

#' Flag approximate redshirt seasons and careers
#'
#' Formalizes the Explore plan's redshirt definition (question 12) with two
#' signals, both **approximate**:
#'
#' 1. **Stat-gap rule** — a roster season with no stat line that is followed by
#'   another observed season. This is the classic redshirt shape (sat a year,
#'   returned); the "followed by another season" guard excludes a final-year
#'   absence, which is just as likely an injury or an early departure.
#' 2. **Fifth-year signal** — the player was ever observed at `class_year` 5,
#'   the endpoint's eligibility class beyond the nominal four-year window.
#'
#' Per-season: `redshirt_season` (rule 1). Per-career: `redshirt_career`
#' (any rule-1 season) and `fifth_year_career` (rule 2). A `class_year` 5
#' player may be a grad transfer rather than a redshirt, and a no-stat season
#' may be a season ending early — the flags are redshirt-*shaped*, not
#' certified.
#'
#' @param roster Cleaned roster (see [clean_roster()]) with `playerId`,
#'   `season`, `class_year`.
#' @param player_stats Cleaned long stats (see [clean_player_stats()]) with
#'   `playerId`, `season`.
#'
#' @return `roster` with `has_stats`, `redshirt_season`, `redshirt_career`,
#'   and `fifth_year_career` columns added.
#' @export
flag_redshirt <- function(roster, player_stats) {
  stat_seasons <- player_stats |>
    dplyr::distinct(.data$playerId, .data$season) |>
    dplyr::mutate(has_stats = TRUE)

  career_bounds <- roster |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(last_season = max(.data$season), .groups = "drop")

  roster |>
    dplyr::left_join(stat_seasons, by = c("playerId", "season")) |>
    dplyr::mutate(has_stats = dplyr::coalesce(.data$has_stats, FALSE)) |>
    dplyr::left_join(career_bounds, by = "playerId") |>
    dplyr::group_by(.data$playerId) |>
    dplyr::mutate(
      redshirt_season = !.data$has_stats & .data$season < .data$last_season,
      redshirt_career = any(.data$redshirt_season),
      fifth_year_career = any(.data$class_year == 5L, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-dplyr::all_of("last_season"))
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
