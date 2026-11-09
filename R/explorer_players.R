# Players tab assets (plans/explorer.md step 4): one row per player-season
# per position group, with the group's headline stats and their percentiles
# already computed, plus each player's NFL outcome. The page only filters and
# draws.

#' Explorer headline stats by position group
#'
#' The stats the Players tab can plot for each position group, first one the
#' default. Offensive linemen have no box-score stats, so they have no row.
#' Rate stats carry a minimum volume (`min_stat_type` in the same category at
#' least `min_value`), so a backup with two attempts doesn't sit at the top.
#' `reverse` marks stats where lower is better (interceptions thrown).
#'
#' @return A tibble, one row per (position group, stat): `pos` (hash code),
#'   `group` (reader-facing label), `key` (column name in the asset),
#'   `category`, `stat_type`, `label`, `format` (`int`, `dec1` or `pct`),
#'   `reverse`, `min_stat_type`, `min_value`.
#' @export
explorer_positions <- function() {
  tibble::tribble(
    ~pos , ~group           , ~key                , ~category       , ~stat_type , ~label                 , ~format , ~reverse , ~min_stat_type , ~min_value ,
    "QB" , "Quarterback"    , "passing_yds"       , "passing"       , "YDS"      , "Passing yards"        , "int"   , FALSE    , NA             , NA         ,
    "QB" , "Quarterback"    , "passing_td"        , "passing"       , "TD"       , "Passing touchdowns"   , "int"   , FALSE    , NA             , NA         ,
    "QB" , "Quarterback"    , "passing_int"       , "passing"       , "INT"      , "Interceptions thrown" , "int"   , TRUE     , "ATT"          ,        100 ,
    "QB" , "Quarterback"    , "passing_ypa"       , "passing"       , "YPA"      , "Yards per attempt"    , "dec1"  , FALSE    , "ATT"          ,        100 ,
    "QB" , "Quarterback"    , "passing_pct"       , "passing"       , "PCT"      , "Completion rate"      , "pct"   , FALSE    , "ATT"          ,        100 ,
    "QB" , "Quarterback"    , "rushing_yds"       , "rushing"       , "YDS"      , "Rushing yards"        , "int"   , FALSE    , NA             , NA         ,
    "RB" , "Running back"   , "rushing_yds"       , "rushing"       , "YDS"      , "Rushing yards"        , "int"   , FALSE    , NA             , NA         ,
    "RB" , "Running back"   , "rushing_td"        , "rushing"       , "TD"       , "Rushing touchdowns"   , "int"   , FALSE    , NA             , NA         ,
    "RB" , "Running back"   , "rushing_ypc"       , "rushing"       , "YPC"      , "Yards per carry"      , "dec1"  , FALSE    , "CAR"          ,         50 ,
    "RB" , "Running back"   , "receiving_yds"     , "receiving"     , "YDS"      , "Receiving yards"      , "int"   , FALSE    , NA             , NA         ,
    "WR" , "Receiver"       , "receiving_yds"     , "receiving"     , "YDS"      , "Receiving yards"      , "int"   , FALSE    , NA             , NA         ,
    "WR" , "Receiver"       , "receiving_rec"     , "receiving"     , "REC"      , "Receptions"           , "int"   , FALSE    , NA             , NA         ,
    "WR" , "Receiver"       , "receiving_td"      , "receiving"     , "TD"       , "Receiving touchdowns" , "int"   , FALSE    , NA             , NA         ,
    "WR" , "Receiver"       , "receiving_ypr"     , "receiving"     , "YPR"      , "Yards per catch"      , "dec1"  , FALSE    , "REC"          ,         15 ,
    "TE" , "Tight end"      , "receiving_yds"     , "receiving"     , "YDS"      , "Receiving yards"      , "int"   , FALSE    , NA             , NA         ,
    "TE" , "Tight end"      , "receiving_rec"     , "receiving"     , "REC"      , "Receptions"           , "int"   , FALSE    , NA             , NA         ,
    "TE" , "Tight end"      , "receiving_td"      , "receiving"     , "TD"       , "Receiving touchdowns" , "int"   , FALSE    , NA             , NA         ,
    "TE" , "Tight end"      , "receiving_ypr"     , "receiving"     , "YPR"      , "Yards per catch"      , "dec1"  , FALSE    , "REC"          ,         10 ,
    "DL" , "Defensive line" , "defense_sacks"     , "defensive"     , "SACKS"    , "Sacks"                , "dec1"  , FALSE    , NA             , NA         ,
    "DL" , "Defensive line" , "defense_tfl"       , "defensive"     , "TFL"      , "Tackles for loss"     , "dec1"  , FALSE    , NA             , NA         ,
    "DL" , "Defensive line" , "defense_hur"       , "defensive"     , "QB HUR"   , "Quarterback hurries"  , "int"   , FALSE    , NA             , NA         ,
    "DL" , "Defensive line" , "defense_tot"       , "defensive"     , "TOT"      , "Total tackles"        , "int"   , FALSE    , NA             , NA         ,
    "LB" , "Linebacker"     , "defense_tot"       , "defensive"     , "TOT"      , "Total tackles"        , "int"   , FALSE    , NA             , NA         ,
    "LB" , "Linebacker"     , "defense_tfl"       , "defensive"     , "TFL"      , "Tackles for loss"     , "dec1"  , FALSE    , NA             , NA         ,
    "LB" , "Linebacker"     , "defense_sacks"     , "defensive"     , "SACKS"    , "Sacks"                , "dec1"  , FALSE    , NA             , NA         ,
    "LB" , "Linebacker"     , "defense_pd"        , "defensive"     , "PD"       , "Passes defended"      , "int"   , FALSE    , NA             , NA         ,
    "DB" , "Defensive back" , "defense_pd"        , "defensive"     , "PD"       , "Passes defended"      , "int"   , FALSE    , NA             , NA         ,
    "DB" , "Defensive back" , "interceptions_int" , "interceptions" , "INT"      , "Interceptions"        , "int"   , FALSE    , NA             , NA         ,
    "DB" , "Defensive back" , "defense_tot"       , "defensive"     , "TOT"      , "Total tackles"        , "int"   , FALSE    , NA             , NA         ,
    "ST" , "Special teams"  , "kicking_fgm"       , "kicking"       , "FGM"      , "Field goals made"     , "int"   , FALSE    , NA             , NA         ,
    "ST" , "Special teams"  , "kicking_pct"       , "kicking"       , "PCT"      , "Field goal rate"      , "pct"   , FALSE    , "FGA"          ,         10 ,
    "ST" , "Special teams"  , "punting_ypp"       , "punting"       , "YPP"      , "Yards per punt"       , "dec1"  , FALSE    , "NO"           ,         20
  ) |>
    dplyr::mutate(
      min_stat_type = as.character(.data$min_stat_type),
      min_value = as.numeric(.data$min_value)
    )
}

#' Explorer outcome categories
#'
#' Reader-facing NFL outcome labels for the Players and Combine tabs, in
#' legend order.
#'
#' @return A tibble: `outcome` (code), `label`.
#' @export
explorer_outcome_levels <- function() {
  tibble::tibble(
    outcome = c("r1", "r2_3", "r4_7", "udfa", "none", "active"),
    label = c(
      "Drafted, round 1",
      "Drafted, rounds 2-3",
      "Drafted, rounds 4-7",
      "Signed as an undrafted free agent",
      "No NFL",
      "Still playing"
    )
  )
}

# Round to outcome code, shared with the combine export.
explorer_round_outcome <- function(round) {
  dplyr::case_when(
    round == 1L ~ "r1",
    round %in% 2:3 ~ "r2_3",
    round >= 4L ~ "r4_7"
  )
}

#' Explorer player outcomes
#'
#' One row per player: the outcome chip at the end of a career. Drafted wins,
#' then a signed undrafted free agent, then a player still on a current-season
#' roster ("Still playing"); everyone else is "No NFL". The draft detail is
#' the player's first pick after their first roster season, the same rule as
#' [career_end_status()].
#'
#' @param career_end Output of [career_end_status()].
#' @param picks_nfl CFBD picks bridged to nflverse (see [link_nfl_draft()]).
#' @param current_season The in-progress season ([explorer_default_season()]).
#' @return A tibble keyed by `playerId`: `outcome`, `outcome_label`.
#' @export
build_explorer_player_outcomes <- function(
  career_end,
  picks_nfl,
  current_season
) {
  draft <- picks_nfl |>
    dplyr::filter(!is.na(.data$playerId)) |>
    dplyr::inner_join(
      dplyr::select(career_end, "playerId", "first_season"),
      by = "playerId",
      relationship = "many-to-one"
    ) |>
    dplyr::filter(.data$year > .data$first_season) |>
    dplyr::arrange(.data$playerId, .data$year, .data$overall) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE) |>
    dplyr::select("playerId", "round", "overall", "nflTeam")
  career_end |>
    dplyr::left_join(draft, by = "playerId", relationship = "one-to-one") |>
    dplyr::mutate(
      drafted = .data$drafted & !is.na(.data$round),
      outcome = dplyr::case_when(
        .data$drafted ~ explorer_round_outcome(as.integer(.data$round)),
        .data$signed_udfa ~ "udfa",
        .data$last_season >= current_season ~ "active",
        TRUE ~ "none"
      ),
      outcome_label = dplyr::case_when(
        .data$drafted ~ sprintf(
          "Drafted R%d #%d (%s)",
          as.integer(.data$round),
          as.integer(.data$overall),
          .data$nflTeam
        ),
        .data$outcome == "udfa" ~ "Signed UDFA",
        .data$outcome == "active" ~ "Still playing",
        TRUE ~ "No NFL"
      )
    ) |>
    dplyr::select("playerId", "outcome", "outcome_label")
}

#' Position group per player-season
#'
#' The position comes from the season's stat line (the season's roster
#' position). A season with no recorded position takes the group from the
#' player's nearest season that has one (the earlier season on a tie).
#'
#' @param player_stats Cleaned long player stats.
#' @return A tibble keyed by `(playerId, season)`: `group`.
#' @export
explorer_player_groups <- function(player_stats) {
  seasons <- player_stats |>
    dplyr::distinct(.data$playerId, .data$season, .data$position) |>
    dplyr::mutate(group = position_group(.data$position)) |>
    dplyr::summarise(
      group = dplyr::first(
        .data$group[.data$group != "Position not recorded"],
        default = "Position not recorded"
      ),
      .by = c("playerId", "season")
    )
  known <- dplyr::filter(seasons, .data$group != "Position not recorded")
  filled <- seasons |>
    dplyr::filter(.data$group == "Position not recorded") |>
    dplyr::select("playerId", "season") |>
    dplyr::inner_join(
      dplyr::rename(known, near = "season", near_group = "group"),
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::arrange(abs(.data$near - .data$season), .data$near) |>
    dplyr::distinct(.data$playerId, .data$season, .keep_all = TRUE) |>
    dplyr::select("playerId", "season", fill = "near_group")
  seasons |>
    dplyr::left_join(
      filled,
      by = c("playerId", "season"),
      relationship = "one-to-one"
    ) |>
    dplyr::mutate(
      group = dplyr::if_else(
        .data$group == "Position not recorded" & !is.na(.data$fill),
        .data$fill,
        .data$group
      )
    ) |>
    dplyr::select("playerId", "season", "group")
}

# Percentile 0-100 among non-missing values; a lone player sits at 100.
explorer_percentile <- function(x, reverse = FALSE) {
  if (reverse) {
    x <- -x
  }
  n <- sum(!is.na(x))
  if (n <= 1L) {
    return(ifelse(is.na(x), NA_integer_, 100L))
  }
  as.integer(round(100 * dplyr::percent_rank(x)))
}

#' Explorer player-season table
#'
#' One row per player-season-team in a position group with a headline stat
#' (see [explorer_positions()]). Each stat has a value column (`<key>`) and a
#' percentile column (`<key>_pct`, 0-100) ranked within position group and
#' season among every player with the stat, across all tiers. A rate stat
#' below its minimum volume keeps its value but has no percentile, and a
#' lower-is-better stat is reversed so a higher percentile is always better.
#' Keys not in the row's group are `NA`.
#'
#' @param player_stats Cleaned long player stats.
#' @param tiers Conference tiers.
#' @param teams Explorer teams ([build_explorer_teams()]): FBS and FCS names
#'   to `team_id`. Lower-division teams keep their name and have no id.
#' @param player_outcomes Output of [build_explorer_player_outcomes()].
#' @param current_season The in-progress season, for players with no
#'   outcome row (no roster career).
#' @return A tibble: `pos`, `player_id`, `name`, `season`, `team`, `team_id`,
#'   `conference`, `tier`, `outcome`, `outcome_label`, then the stat columns.
#' @export
build_explorer_player_seasons <- function(
  player_stats,
  tiers,
  teams,
  player_outcomes,
  current_season
) {
  defs <- explorer_positions()
  wanted <- unique(c(
    paste(defs$category, defs$stat_type),
    paste(defs$category, defs$min_stat_type)[!is.na(defs$min_stat_type)]
  ))
  wide <- player_stats |>
    dplyr::filter(paste(.data$category, .data$statType) %in% wanted) |>
    dplyr::mutate(
      col = paste(.data$category, .data$statType),
      value = suppressWarnings(as.numeric(.data$stat))
    ) |>
    tidyr::pivot_wider(
      id_cols = c("playerId", "season", "team", "conference"),
      names_from = "col",
      values_from = "value",
      values_fn = sum
    )
  names_by_id <- player_stats |>
    dplyr::distinct(.data$playerId, .data$season, .data$player) |>
    dplyr::summarise(
      name = dplyr::last(.data$player),
      .by = c("playerId", "season")
    )
  groups <- dplyr::distinct(defs, .data$pos, .data$group)
  base <- wide |>
    dplyr::left_join(
      explorer_player_groups(player_stats),
      by = c("playerId", "season"),
      relationship = "many-to-one"
    ) |>
    dplyr::inner_join(groups, by = "group", relationship = "many-to-one")

  out <- lapply(split(base, base$pos), function(d) {
    pos_defs <- dplyr::filter(defs, .data$pos == d$pos[[1]])
    for (i in seq_len(nrow(pos_defs))) {
      def <- pos_defs[i, ]
      col <- paste(def$category, def$stat_type)
      v <- if (col %in% names(d)) d[[col]] else rep(NA_real_, nrow(d))
      d[[def$key]] <- v
      ok <- !is.na(v)
      if (!is.na(def$min_stat_type)) {
        vol_col <- paste(def$category, def$min_stat_type)
        vol <- if (vol_col %in% names(d)) {
          d[[vol_col]]
        } else {
          rep(NA_real_, nrow(d))
        }
        ok <- ok & !is.na(vol) & vol >= def$min_value
      }
      d[[paste0(def$key, "_pct")]] <- stats::ave(
        ifelse(ok, v, NA_real_),
        d$season,
        FUN = function(x) explorer_percentile(x, def$reverse)
      )
    }
    # A row needs at least one of its group's headline stats.
    d[rowSums(!is.na(d[pos_defs$key])) > 0, , drop = FALSE]
  })
  keys <- unique(defs$key)
  all <- dplyr::bind_rows(out)
  # Groups absent from the input still get their (empty) stat columns.
  for (col in setdiff(c(keys, paste0(keys, "_pct")), names(all))) {
    all[[col]] <- if (endsWith(col, "_pct")) NA_integer_ else NA_real_
  }
  all |>
    dplyr::left_join(
      names_by_id,
      by = c("playerId", "season"),
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier"),
      by = c("season", "conference"),
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      dplyr::select(teams, "team", "team_id"),
      by = "team",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      player_outcomes,
      by = "playerId",
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      last_stat_season = max(.data$season),
      .by = "playerId"
    ) |>
    dplyr::mutate(
      tier = as.integer(dplyr::coalesce(.data$tier, 1L)),
      no_row = is.na(.data$outcome),
      outcome = dplyr::case_when(
        !.data$no_row ~ .data$outcome,
        .data$last_stat_season >= current_season ~ "active",
        TRUE ~ "none"
      ),
      outcome_label = dplyr::case_when(
        !.data$no_row ~ .data$outcome_label,
        .data$outcome == "active" ~ "Still playing",
        TRUE ~ "No NFL"
      ),
      dplyr::across(dplyr::ends_with("_pct"), as.integer)
    ) |>
    dplyr::select(
      "pos",
      player_id = "playerId",
      "name",
      "season",
      "team",
      "team_id",
      "conference",
      "tier",
      "outcome",
      "outcome_label",
      dplyr::all_of(c(keys, paste0(keys, "_pct")))
    ) |>
    dplyr::arrange(.data$pos, .data$season, .data$player_id)
}

#' Write the Players tab assets
#'
#' One parquet file per position group, `players/<pos>.parquet`, carrying
#' only that group's stat columns, sorted by season. The team name is kept
#' only for teams without an id (the page reads names from `teams.json`).
#' Files are uncompressed because GitHub Pages gzips them in transit, which
#' beats snappy plus gzip. The directory is cleared first so a dropped group
#' leaves no stale file.
#'
#' @param player_seasons Output of [build_explorer_player_seasons()].
#' @param dir Output directory.
#' @return The written paths.
#' @export
write_explorer_players <- function(
  player_seasons,
  dir = "vignettes/explorer-data"
) {
  out_dir <- file.path(dir, "players")
  unlink(out_dir, recursive = TRUE)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  defs <- explorer_positions()
  common <- c(
    "player_id",
    "name",
    "season",
    "team",
    "team_id",
    "tier",
    "outcome",
    "outcome_label"
  )
  paths <- character()
  for (p in unique(defs$pos)) {
    keys <- defs$key[defs$pos == p]
    d <- player_seasons |>
      dplyr::filter(.data$pos == p) |>
      dplyr::select(dplyr::all_of(c(common, keys, paste0(keys, "_pct")))) |>
      dplyr::mutate(
        season = as.integer(.data$season),
        team_id = as.integer(.data$team_id),
        team = dplyr::if_else(is.na(.data$team_id), .data$team, NA_character_)
      ) |>
      dplyr::arrange(.data$season, .data$player_id)
    path <- file.path(out_dir, paste0(p, ".parquet"))
    arrow::write_parquet(d, path, compression = "uncompressed")
    paths <- c(paths, path)
  }
  paths
}
