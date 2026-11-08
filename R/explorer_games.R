# Explorer game-level assets (plans/explorer.md step 3, decision 0046): each
# team's side of each game, and slim per-season play files for the game
# timeline.

#' Elo expected win probability
#'
#' A neutral-field expectation: no home advantage is applied.
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
#' probability before kickoff (`wp_pre`, a neutral-field expectation with no
#' home advantage), CFBD's postgame win probability, and whether
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

#' Play types that change possession by turnover
#'
#' Plain "Fumble" is not flagged (the recovering team is unknown), nor are
#' blocked kicks or turnovers on downs.
#'
#' @return Character vector of CFBD `playType` values.
#' @export
explorer_turnover_types <- function() {
  c(
    "Fumble Recovery (Opponent)",
    "Fumble Return Touchdown",
    "Interception",
    "Interception Return Touchdown",
    "Pass Interception",
    "Pass Interception Return"
  )
}

#' Elapsed game time in seconds
#'
#' Regulation runs 0 to 3600 seconds (four 900-second quarters, the clock
#' clamped into its quarter). Overtime has no clock, so each overtime period
#' gets a 300-second slot and its plays are spread evenly by order.
#'
#' @param period Period (1-4 regulation, 5+ overtime).
#' @param clock_minutes,clock_seconds Clock remaining in the period.
#' @param overtime_position Play's position within its period, in `[0, 1)`.
#' @return Integer seconds since kickoff (`NA` for a missing regulation clock).
#' @export
explorer_elapsed <- function(
  period,
  clock_minutes,
  clock_seconds,
  overtime_position
) {
  remaining <- pmin(pmax(clock_minutes * 60 + clock_seconds, 0), 900)
  regulation <- (period - 1) * 900 + (900 - remaining)
  overtime <- 3600 + (period - 5 + overtime_position) * 300
  as.integer(round(ifelse(period <= 4, regulation, overtime)))
}

#' Explorer plays table
#'
#' One row per play, in game order, with everything the game timeline draws
#' already computed: elapsed seconds, the score and margin from the home
#' team's side, cumulative PPA from the home side (the home offense's PPA
#' minus the away offense's, NA counted as 0), scoring and turnover flags, and
#' the players credited on the play as a JSON array (`NA` when none). The page
#' flips signs for the away team.
#'
#' Elapsed time is non-decreasing within each game. CFBD's clock jitters (a
#' 0:11 play after a 0:10 play, or a stray mid-quarter 0:00), so a stray 0:00
#' (one followed by a later timed play in its period) takes the previous
#' play's elapsed, or the period start if it opens the period, and a running
#' maximum within each period removes backward steps. Plays are ordered by
#' period, then drive and play number, because CFBD sometimes mislabels a
#' drive's number against its period. The raw `clock` text is
#' kept. Missing clocks stay `NA`.
#'
#' The last play's score is not always the final score (the play-by-play is
#' truncated or stale in about 4% of games), so the final score comes from
#' [build_explorer_team_games()].
#'
#' @param plays Cleaned plays.
#' @param games Cleaned games.
#' @param teams Cleaned teams.
#' @param play_stats Cleaned play stats.
#' @return A tibble keyed by `play_id`, one row per input play.
#' @export
build_explorer_plays <- function(plays, games, teams, play_stats) {
  homes <- dplyr::select(games, gameId = "id", home_team = "homeTeam")
  offense_ids <- dplyr::select(teams, offense = "team", offense_id = "team_id")
  # One entry per athlete per play: a punter carries several stat types.
  players <- play_stats |>
    dplyr::summarise(
      stat = paste(unique(.data$statType), collapse = ", "),
      .by = c("playId", "athleteId", "athleteName")
    ) |>
    dplyr::summarise(
      players = as.character(jsonlite::toJSON(data.frame(
        id = .data$athleteId,
        name = .data$athleteName,
        stat = .data$stat
      ))),
      .by = "playId"
    )
  plays |>
    dplyr::left_join(homes, by = "gameId", relationship = "many-to-one") |>
    dplyr::left_join(
      offense_ids,
      by = "offense",
      relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      players,
      by = c("id" = "playId"),
      relationship = "one-to-one"
    ) |>
    dplyr::arrange(
      .data$gameId,
      .data$period,
      .data$driveNumber,
      .data$playNumber
    ) |>
    dplyr::mutate(
      # Only overtime periods use this; the NA-period group's value is unused.
      overtime_position = (dplyr::row_number() - 1) / dplyr::n(),
      .by = c("gameId", "period")
    ) |>
    dplyr::mutate(
      home_offense = dplyr::coalesce(.data$offense == .data$home_team, FALSE),
      home_score = dplyr::if_else(
        .data$home_offense,
        .data$offenseScore,
        .data$defenseScore
      ),
      away_score = dplyr::if_else(
        .data$home_offense,
        .data$defenseScore,
        .data$offenseScore
      ),
      home_cum_ppa = round(
        cumsum(
          dplyr::if_else(.data$home_offense, 1, -1) *
            dplyr::coalesce(.data$ppa, 0)
        ),
        2
      ),
      .by = "gameId"
    ) |>
    dplyr::mutate(
      remaining = .data$clock_minutes * 60 + .data$clock_seconds,
      elapsed = explorer_elapsed(
        .data$period,
        .data$clock_minutes,
        .data$clock_seconds,
        .data$overtime_position
      )
    ) |>
    dplyr::mutate(
      # CFBD stamps a stray 0:00 mid-quarter; it takes the previous play's
      # time (the period start if it opens the period) instead of the clock.
      later_timed = rev(cumsum(rev(
        .data$remaining > 0 & !is.na(.data$remaining)
      ))) -
        (.data$remaining > 0 & !is.na(.data$remaining)),
      stray = .data$period <= 4L &
        .data$remaining %in% 0 &
        .data$later_timed > 0,
      elapsed = dplyr::if_else(
        .data$stray,
        as.integer((.data$period - 1L) * 900L),
        .data$elapsed
      ),
      elapsed = dplyr::if_else(
        is.na(.data$elapsed),
        NA_integer_,
        as.integer(cummax(dplyr::coalesce(.data$elapsed, 0L)))
      ),
      .by = c("gameId", "period")
    ) |>
    dplyr::transmute(
      season = .data$season,
      game_id = .data$gameId,
      play_id = .data$id,
      period = .data$period,
      clock = dplyr::case_when(
        is.na(.data$period) ~ NA_character_,
        .data$period > 4L ~ paste0("OT", .data$period - 4L),
        is.na(.data$clock_minutes) | is.na(.data$clock_seconds) ~ NA_character_,
        .default = sprintf("%d:%02d", .data$clock_minutes, .data$clock_seconds)
      ),
      elapsed = .data$elapsed,
      offense_id = .data$offense_id,
      home_score = .data$home_score,
      away_score = .data$away_score,
      home_margin = .data$home_score - .data$away_score,
      home_cum_ppa = .data$home_cum_ppa,
      down = .data$down,
      distance = .data$distance,
      yards_to_goal = .data$yardsToGoal,
      play_type = .data$playType,
      play_text = .data$playText,
      scoring = .data$scoring %in% TRUE,
      turnover = .data$playType %in% explorer_turnover_types(),
      players = .data$players
    )
}

#' Write the per-season team-games JSON files
#'
#' @param team_games Output of [build_explorer_team_games()].
#' @param dir Output directory.
#' @return The written paths, `team_games_<season>.json`.
#' @export
write_explorer_team_games <- function(
  team_games,
  dir = "vignettes/explorer-data"
) {
  by_season <- split(team_games, team_games$season)
  names(by_season) <- paste0("team_games_", names(by_season))
  write_explorer_assets(by_season, dir)
}

#' Write the per-season plays parquet files
#'
#' Rows stay in game order and row groups stay small, so each group's
#' `game_id` min/max statistics let the page fetch one game with a couple of
#' range requests (decision 0046).
#'
#' @param explorer_plays Output of [build_explorer_plays()].
#' @param dir Output directory.
#' @param chunk_size Rows per row group.
#' @return The written paths, `plays_<season>.parquet`.
#' @export
write_explorer_plays <- function(
  explorer_plays,
  dir = "vignettes/explorer-data",
  chunk_size = 5000L
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  seasons <- sort(unique(explorer_plays$season))
  paths <- file.path(dir, sprintf("plays_%d.parquet", seasons))
  for (i in seq_along(seasons)) {
    explorer_plays |>
      dplyr::filter(.data$season == seasons[[i]]) |>
      dplyr::select(-"season") |>
      arrow::write_parquet(paths[[i]], chunk_size = chunk_size)
  }
  paths
}
