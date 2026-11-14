# Draft & careers tab asset (plans/explorer.md step 6): every draft pick
# since the data window opens with its school, tier and NFL roster seasons,
# plus transfer arrivals by team and season. These replace the charts of the
# retired Visualizations page.

#' Map NFL draft position names to reader-facing position groups
#'
#' CFBD's draft picks spell positions out ("Offensive Tackle", "Defensive
#' Edge"). This maps them onto the groups of [position_group()]. Unknown
#' names become "Position not recorded".
#'
#' @param position Character vector of `picks$position` values.
#' @return Character vector of group labels (see [position_group_levels()]).
#' @export
draft_position_group <- function(position) {
  map <- c(
    "Quarterback" = "Quarterback",
    "Running Back" = "Running back",
    "Fullback" = "Running back",
    "Wide Receiver" = "Receiver",
    "Tight End" = "Tight end",
    "Offensive Tackle" = "Offensive line",
    "Offensive Guard" = "Offensive line",
    "Center" = "Offensive line",
    "Defensive End" = "Defensive line",
    "Defensive Tackle" = "Defensive line",
    "Defensive Edge" = "Defensive line",
    "Linebacker" = "Linebacker",
    "Inside Linebacker" = "Linebacker",
    "Outside Linebacker" = "Linebacker",
    "Cornerback" = "Defensive back",
    "Safety" = "Defensive back",
    "Defensive Back" = "Defensive back",
    "Place Kicker" = "Special teams",
    "Punter" = "Special teams",
    "Long Snapper" = "Special teams",
    "Kick Returner" = "Special teams"
  )
  out <- unname(map[position])
  out[is.na(out)] <- "Position not recorded"
  out
}

#' Conference tier at the nearest season with one
#'
#' Looks up each conference's tier in `season`, else in the closest season
#' the conference has a tier (the 2010 draft class played in 2009, before the
#' tiers start). A conference with no tier at all (lower divisions) is tier 1,
#' the same default as [build_conference_tiers()].
#'
#' @param conference,season Conference names and seasons, same length.
#' @param tiers Output of [build_conference_tiers()].
#' @return Integer tiers.
#' @export
explorer_tier_at <- function(conference, season, tiers) {
  vapply(
    seq_along(conference),
    function(i) {
      t <- tiers[tiers$conference %in% conference[i], ]
      if (!nrow(t)) {
        return(1L)
      }
      as.integer(t$tier[which.min(abs(t$season - season[i]))])
    },
    integer(1)
  )
}

#' Explorer draft picks
#'
#' One row per draft pick from the first season with conference tiers on:
#' the school (as an explorer `team_id` when it has one), the tier of its
#' conference in the pick's final college season, the position group, and
#' NFL longevity as distinct seasons on an NFL roster. `nfl_seasons` is `NA`
#' when the pick is not linked to nflverse, and `active` marks a player on
#' the latest NFL roster, whose count is still growing (right-censored).
#' `players_pos` is the Players-tab group of the player's last stat season,
#' for the tap-through.
#'
#' @param picks_nfl CFBD picks linked to nflverse (see [link_nfl_draft()]).
#' @param nfl_rosters Cleaned NFL rosters.
#' @param tiers Output of [build_conference_tiers()].
#' @param teams Output of [build_explorer_teams()].
#' @param player_seasons Output of [build_explorer_player_seasons()].
#' @return A tibble, one row per kept pick.
#' @export
build_explorer_draft <- function(
  picks_nfl,
  nfl_rosters,
  tiers,
  teams,
  player_seasons
) {
  latest <- max(nfl_rosters$season)
  seasons <- nfl_rosters |>
    dplyr::distinct(.data$gsis_id, .data$season) |>
    dplyr::summarise(
      nfl_seasons = dplyr::n(),
      active = any(.data$season == latest),
      .by = "gsis_id"
    )
  groups <- explorer_combine_groups()
  players_pos <- player_seasons |>
    dplyr::arrange(.data$player_id, dplyr::desc(.data$season)) |>
    dplyr::distinct(.data$player_id, .keep_all = TRUE) |>
    dplyr::select(playerId = "player_id", players_pos = "pos")
  picks_nfl |>
    dplyr::filter(.data$year >= min(tiers$season)) |>
    dplyr::mutate(
      tier = explorer_tier_at(.data$collegeConference, .data$year - 1L, tiers),
      group = draft_position_group(.data$position)
    ) |>
    dplyr::left_join(
      dplyr::select(teams, "team_id", collegeTeam = "team"),
      by = "collegeTeam",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      groups,
      by = "group",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(seasons, by = "gsis_id", relationship = "many-to-one") |>
    dplyr::left_join(
      players_pos,
      by = "playerId",
      relationship = "many-to-one"
    ) |>
    dplyr::transmute(
      year = .data$year,
      round = as.integer(.data$round),
      overall = as.integer(.data$overall),
      name = .data$name,
      pos = .data$pos,
      team_id = .data$team_id,
      team = .data$collegeTeam,
      tier = .data$tier,
      player_id = .data$playerId,
      players_pos = .data$players_pos,
      nfl_seasons = dplyr::if_else(
        .data$nfl_matched,
        dplyr::coalesce(.data$nfl_seasons, 0L),
        NA_integer_
      ),
      active = dplyr::if_else(
        .data$nfl_matched,
        dplyr::coalesce(.data$active, FALSE),
        NA
      )
    ) |>
    dplyr::arrange(.data$year, .data$overall)
}

#' Explorer transfer arrivals
#'
#' Transfers counted at the school the player moved to: one row per team,
#' season and tier direction (`up`, `lateral`, `down`). Summed over teams
#' they equal [transfer_counts()]; like it, they cover players with a stat
#' line.
#'
#' @param ps_change Player-season change features (see
#'   [add_change_features()]).
#' @param teams Output of [build_explorer_teams()].
#' @return A tibble: `season`, `team_id`, `team`, `direction`, `n`.
#' @export
build_explorer_transfers <- function(ps_change, teams) {
  ps_change |>
    dplyr::filter(.data$transferred) |>
    dplyr::count(
      .data$season,
      team = .data$team,
      direction = .data$transfer_direction,
      name = "n"
    ) |>
    dplyr::left_join(
      dplyr::select(teams, "team_id", "team"),
      by = "team",
      relationship = "many-to-one"
    ) |>
    dplyr::select("season", "team_id", "team", "direction", "n") |>
    dplyr::arrange(.data$season, .data$team)
}

#' Explorer Draft & careers asset
#'
#' @param draft Output of [build_explorer_draft()].
#' @param transfers Output of [build_explorer_transfers()].
#' @param transfer_rate Output of [transfer_rate()].
#' @param nfl_rosters Cleaned NFL rosters (for the latest NFL season).
#' @return A list: `draft`, `transfers`, `transfer_rate` (`players`,
#'   `transferred`, `share`), `nfl_latest_season`.
#' @export
build_explorer_careers <- function(
  draft,
  transfers,
  transfer_rate,
  nfl_rosters
) {
  list(
    draft = draft,
    transfers = transfers,
    transfer_rate = lapply(as.list(transfer_rate), jsonlite::unbox),
    nfl_latest_season = jsonlite::unbox(max(nfl_rosters$season))
  )
}

#' Write the Draft & careers asset
#'
#' `careers.json`, with the draft and transfer tables as objects of columns
#' (one array per field), like `combine.json`.
#'
#' @param careers Output of [build_explorer_careers()].
#' @param dir Output directory.
#' @return The written path.
#' @export
write_explorer_careers <- function(
  careers,
  dir = "vignettes/explorer-data"
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, "careers.json")
  json <- jsonlite::toJSON(
    careers,
    dataframe = "columns",
    na = "null",
    digits = NA
  )
  writeLines(enc2utf8(json), path, useBytes = TRUE)
  path
}
