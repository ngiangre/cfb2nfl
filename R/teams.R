# Team- and conference-grain derived tables (plans/conferences-teams.md).
# A draftee is credited to the team of their final roster season before the
# draft (decision 0033); rates divide by players whose college career ended
# at that team, so offensive linemen (who have almost no stat lines) count.

#' Position-group labels, in display order
#'
#' @return A character vector of the nine reader-facing position groups.
#' @export
position_group_levels <- function() {
  c(
    "Quarterback",
    "Running back",
    "Receiver",
    "Tight end",
    "Offensive line",
    "Defensive line",
    "Linebacker",
    "Defensive back",
    "Special teams"
  )
}

#' Map roster position codes to reader-facing position groups
#'
#' One map shared by every post and table, so numerators and denominators
#' group positions identically. Unknown codes (`?`, `ATH`, `NA`, anything
#' new) become "Position not recorded" rather than being dropped.
#'
#' @param position Character vector of CFBD roster position codes.
#' @return Character vector of group labels (see [position_group_levels()]).
#' @export
position_group <- function(position) {
  map <- c(
    QB = "Quarterback",
    RB = "Running back",
    FB = "Running back",
    WR = "Receiver",
    TE = "Tight end",
    T = "Offensive line",
    G = "Offensive line",
    C = "Offensive line",
    OL = "Offensive line",
    OT = "Offensive line",
    DL = "Defensive line",
    DE = "Defensive line",
    DT = "Defensive line",
    NT = "Defensive line",
    EDGE = "Defensive line",
    LB = "Linebacker",
    ILB = "Linebacker",
    OLB = "Linebacker",
    DB = "Defensive back",
    S = "Defensive back",
    CB = "Defensive back",
    PK = "Special teams",
    P = "Special teams",
    LS = "Special teams",
    PR = "Special teams",
    KR = "Special teams"
  )
  out <- unname(map[position])
  out[is.na(out)] <- "Position not recorded"
  out
}

# Most frequent non-NA value (ties broken alphabetically), for the one
# team-season listed under two conferences in games.
mode_chr <- function(x) {
  x <- x[!is.na(x)]
  if (length(x) == 0L) {
    return(NA_character_)
  }
  tab <- table(x)
  names(tab)[tab == max(tab)][1L]
}

#' Season win-loss record for every team in the games table
#'
#' Stacks home and away sides so every team that appears in `games` (all
#' divisions) gets one row per season. Conference and classification come
#' from every listed game; the record counts completed games with scores
#' only, so an in-progress season has a partial record. A tie counts as half
#' a win in `win_pct`.
#'
#' @param games Cleaned games ([clean_games()]).
#' @return One row per `(season, team)`: `conference`, `classification`,
#'   `games_played`, `wins`, `losses`, `ties`, `win_pct`.
#' @export
team_record <- function(games) {
  side <- function(team, conf, class, pf, pa) {
    tibble::tibble(
      season = games$season,
      team = games[[team]],
      conference = games[[conf]],
      classification = games[[class]],
      done = games$completed & !is.na(games[[pf]]) & !is.na(games[[pa]]),
      pf = games[[pf]],
      pa = games[[pa]]
    )
  }
  dplyr::bind_rows(
    side(
      "homeTeam",
      "homeConference",
      "homeClassification",
      "homePoints",
      "awayPoints"
    ),
    side(
      "awayTeam",
      "awayConference",
      "awayClassification",
      "awayPoints",
      "homePoints"
    )
  ) |>
    dplyr::group_by(.data$season, .data$team) |>
    dplyr::summarise(
      conference = mode_chr(.data$conference),
      classification = mode_chr(.data$classification),
      games_played = sum(.data$done),
      wins = sum(.data$done & .data$pf > .data$pa),
      losses = sum(.data$done & .data$pf < .data$pa),
      ties = sum(.data$done & .data$pf == .data$pa),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      dplyr::across(c("games_played", "wins", "losses", "ties"), as.integer),
      win_pct = dplyr::if_else(
        .data$games_played > 0L,
        (.data$wins + 0.5 * .data$ties) / .data$games_played,
        NA_real_
      )
    )
}

#' Build the team-season table
#'
#' One row per team per season across every division: conference and tier,
#' win-loss record ([team_record()]), FBS ratings (SRS, SP+ from the coaches
#' table; NA elsewhere), roster size, and how many players carry a stat line.
#' The universe is every team in `games` plus any roster team without games,
#' so the landscape counts teams that played, not only teams with stats.
#' Conferences missing from the tier lookup (Division II/III and others that
#' never appear in player stats) fall back to tier 1 when the team is not FBS.
#'
#' @param roster Cleaned roster.
#' @param games Cleaned games.
#' @param tiers Conference-tier lookup.
#' @param player_season Player-season table ([build_player_season()]).
#' @param coaches Cleaned coaches.
#' @return One row per `(team, season)`. `conference_filled` is TRUE where the
#'   conference came from the team's nearest season with games.
#' @export
build_team_season <- function(roster, games, tiers, player_season, coaches) {
  tier_levels <- conference_tier_levels()
  ros <- roster |>
    dplyr::filter(!is.na(.data$team)) |>
    dplyr::distinct(.data$season, .data$team, .data$playerId) |>
    dplyr::count(.data$season, .data$team, name = "n_roster")
  stat <- player_season |>
    dplyr::distinct(.data$season, .data$team, .data$playerId) |>
    dplyr::count(.data$season, .data$team, name = "n_stat_players")
  # Mid-season coaching changes duplicate (school, season); ratings are team
  # properties, so take the first non-NA.
  rating <- coaches |>
    dplyr::group_by(team = .data$school, .data$season) |>
    dplyr::summarise(
      srs = dplyr::first(stats::na.omit(.data$srs), default = NA_real_),
      sp_overall = dplyr::first(
        stats::na.omit(.data$sp_overall),
        default = NA_real_
      ),
      .groups = "drop"
    )
  # Roster-only team-seasons (no games ingested) borrow conference and
  # classification from the nearest season so FBS teams keep their tier.
  team_record(games) |>
    dplyr::full_join(ros, by = c("season", "team")) |>
    dplyr::arrange(.data$team, .data$season) |>
    dplyr::mutate(conference_filled = is.na(.data$conference)) |>
    dplyr::group_by(.data$team) |>
    tidyr::fill("conference", "classification", .direction = "downup") |>
    dplyr::ungroup() |>
    dplyr::mutate(
      conference_filled = .data$conference_filled & !is.na(.data$conference)
    ) |>
    dplyr::left_join(stat, by = c("season", "team")) |>
    dplyr::left_join(rating, by = c("season", "team")) |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier"),
      by = c("season", "conference")
    ) |>
    dplyr::mutate(
      dplyr::across(
        c(
          "games_played",
          "wins",
          "losses",
          "ties",
          "n_roster",
          "n_stat_players"
        ),
        \(x) dplyr::coalesce(as.integer(x), 0L)
      ),
      has_stat_lines = .data$n_stat_players > 0L,
      tier = dplyr::if_else(
        is.na(.data$tier) &
          ((!is.na(.data$classification) & .data$classification != "fbs") |
            (is.na(.data$classification) & .data$games_played > 0L)),
        1L,
        .data$tier
      ),
      tier_label = names(tier_levels)[match(.data$tier, tier_levels)]
    ) |>
    dplyr::select(
      "team",
      "season",
      "conference",
      "classification",
      "conference_filled",
      "tier",
      "tier_label",
      "games_played",
      "wins",
      "losses",
      "ties",
      "win_pct",
      "srs",
      "sp_overall",
      "n_roster",
      "n_stat_players",
      "has_stat_lines"
    ) |>
    dplyr::arrange(.data$season, .data$team)
}

#' Each player's college exit: the team that gets credit and the outcome
#'
#' A drafted player is credited to the team of their final roster season
#' before the draft year (one pick per player: the most recent pick inside
#' `draft_window`, decision 0011, since CFBD ids are reused by decades-old
#' picks);
#' an undrafted player to their final roster season, feeding the next draft
#' class. Undrafted players still on the latest roster are excluded (their
#' outcome is not yet known). "Eligible" is a roster-based proxy for the NFL's
#' three-years-out-of-high-school rule: three or more roster seasons, or
#' drafted, or signed as a UDFA. The proxy is left-truncated for players whose
#' careers began before the 2010 roster window, so use draft classes 2014 and
#' later for rates. Roster coverage jumps (2022 lists 307 teams versus about
#' 225 earlier) create one-season listings that look like exits.
#'
#' @param roster Cleaned roster with `playerId`, `season`, `team`, `position`.
#' @param picks Cleaned picks with `playerId`, `year`, `round`.
#' @param udfa_ids Character vector of player ids who signed as undrafted
#'   free agents (from `outcomes`).
#' @param reused Reused athlete ids to exclude ([reused_ids()]).
#' @param draft_window Plausible draft years; picks outside it are ignored.
#' @param last_roster_season Latest roster season in the data.
#' @return One row per player: `playerId`, `team`, `last_season`,
#'   `first_season`, `seasons`, `position`, `position_group`, `draft_class`,
#'   `drafted`, `draft_round`, `udfa`, `eligible`.
#' @export
exit_cohort <- function(
  roster,
  picks,
  udfa_ids,
  reused,
  draft_window = 2010:2027,
  last_roster_season = max(roster$season)
) {
  pk <- picks |>
    dplyr::filter(
      !is.na(.data$playerId),
      !.data$playerId %in% reused,
      .data$year %in% draft_window
    ) |>
    dplyr::arrange(.data$playerId, dplyr::desc(.data$year)) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::select("playerId", draft_year = "year", draft_round = "round")
  roster |>
    dplyr::filter(!.data$playerId %in% reused, !is.na(.data$team)) |>
    # One team per player-season; alphabetical tie-break for the rare
    # same-season duplicate.
    dplyr::arrange(.data$playerId, .data$season, .data$team) |>
    dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE) |>
    dplyr::left_join(pk, by = "playerId") |>
    dplyr::filter(is.na(.data$draft_year) | .data$season < .data$draft_year) |>
    dplyr::group_by(.data$playerId) |>
    dplyr::summarise(
      team = .data$team[which.max(.data$season)],
      position = .data$position[which.max(.data$season)],
      first_season = .data$season[which.min(.data$season)],
      last_season = .data$season[which.max(.data$season)],
      seasons = dplyr::n_distinct(.data$season),
      draft_year = dplyr::first(.data$draft_year),
      draft_round = dplyr::first(.data$draft_round),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      drafted = !is.na(.data$draft_year),
      udfa = !.data$drafted & .data$playerId %in% udfa_ids,
      draft_class = dplyr::if_else(
        .data$drafted,
        .data$draft_year,
        .data$last_season + 1L
      ),
      eligible = .data$drafted | .data$udfa | .data$seasons >= 3L,
      position_group = position_group(.data$position)
    ) |>
    dplyr::filter(
      .data$drafted | .data$last_season < .env$last_roster_season
    ) |>
    dplyr::select(
      "playerId",
      "team",
      "last_season",
      "first_season",
      "seasons",
      "position",
      "position_group",
      "draft_class",
      "drafted",
      "draft_round",
      "udfa",
      "eligible"
    )
}

#' Draft output per team, final college season, and position group
#'
#' Aggregates [exit_cohort()] to the team whose roster the player left, in
#' the season they left it, with that season's conference and tier from
#' [build_team_season()]. Rates are `n_drafted / n_eligible`.
#'
#' @param cohort Output of [exit_cohort()].
#' @param team_season Output of [build_team_season()].
#' @return One row per `(team, season, position_group)`.
#' @export
build_team_draft <- function(cohort, team_season) {
  cohort |>
    dplyr::group_by(
      .data$team,
      season = .data$last_season,
      .data$position_group
    ) |>
    dplyr::summarise(
      n_exits = dplyr::n(),
      n_eligible = sum(.data$eligible),
      n_drafted = sum(.data$drafted),
      n_round1 = sum(.data$draft_round %in% 1L),
      n_udfa = sum(.data$udfa),
      .groups = "drop"
    ) |>
    dplyr::mutate(dplyr::across(dplyr::starts_with("n_"), as.integer)) |>
    dplyr::left_join(
      dplyr::select(
        team_season,
        "team",
        "season",
        "conference",
        "tier",
        "tier_label"
      ),
      by = c("team", "season")
    ) |>
    dplyr::relocate("conference", "tier", "tier_label", .after = "season")
}
