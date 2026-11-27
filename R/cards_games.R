# Game-flow figure cards (feature F25): one game's play log turned into
# expected-points flow, drives and player involvement. The four cards for the
# Georgia vs Missouri game (week 11, 2026) read the plays table through these
# builders, so each figure is built one way (decision 0041). Expected points
# (EP) is the points the offense nets over the rest of the half; a play's EPA
# is the EP after it minus the EP before. Every EPA a card shows is CFBD's
# predicted points added (PPA) unless the expected-points curve is named.

#' Play types that carry no scrimmage EPA
#'
#' Kickoffs, punts, kicks, two-point tries, penalties without a play, timeouts
#' and period markers. Scrimmage plays are everything else.
#'
#' @return A character vector of `playType` values.
#' @export
game_kick_types <- function() {
  c(
    "Kickoff",
    "Kickoff Return (Offense)",
    "Kickoff Return Touchdown",
    "Punt",
    "Punt Return (Offense)",
    "Punt Return (Defension)",
    "Punt Return (Defensive)",
    "Punt Return Touchdown",
    "Field Goal Good",
    "Field Goal Missed",
    "Blocked Field Goal",
    "Extra Point Good",
    "Extra Point Missed",
    "Blocked Extra Point",
    "Two-Point Pass",
    "Two-Point Rush",
    "Two-Point Return",
    "Uncategorized",
    "End Period",
    "Timeout",
    "Penalty"
  )
}

# Scoring play types, split by the side that scored.
game_off_td <- function() c("Rushing Touchdown", "Passing Touchdown")
game_def_td <- function() {
  c(
    "Interception Return Touchdown",
    "Punt Return Touchdown",
    "Kickoff Return Touchdown",
    "Fumble Return Touchdown"
  )
}

# Expected points of a touchdown, the value the curve assigns it (kept fixed).
game_td_value <- 6.94

#' One game's plays, in CFBD's id order
#'
#' @param con A DuckDB connection to `cfb2nfl.duckdb`.
#' @param game_id The CFBD game id.
#' @return The game's rows of the `plays` table.
#' @export
game_plays <- function(con, game_id) {
  DBI::dbGetQuery(
    con,
    "SELECT * FROM plays WHERE gameId = ? ORDER BY id",
    params = list(as.integer(game_id))
  )
}

#' A game's scrimmage plays in game order
#'
#' Drops the plays in [game_kick_types()] and numbers the rest by drive and
#' play, since the string ids are not in game order.
#'
#' @param plays A game's plays ([game_plays()]).
#' @return The scrimmage plays with a `seq` game-order index.
#' @export
game_scrimmage <- function(plays) {
  plays |>
    dplyr::filter(!.data$playType %in% game_kick_types()) |>
    dplyr::arrange(.data$driveNumber, .data$playNumber) |>
    dplyr::mutate(seq = dplyr::row_number())
}

#' Expected-points curve fit on a season's scrimmage plays
#'
#' A linear model with natural splines of the net points the offense went on
#' to score over the rest of the half, on yards to the goal, down and distance.
#' The target is anchored on the home-away score difference, so both teams'
#' rows read from one perspective. Used only to show what PPA measures.
#'
#' @param season_plays The season's plays, with the columns of the `plays`
#'   table used here (`gameId`, `driveId`, `driveNumber`, `playNumber`,
#'   `period`, `offense`, `home`, `offenseScore`, `defenseScore`,
#'   `yardsToGoal`, `down`, `distance`, `playType`).
#' @return An `lm` object.
#' @export
game_ep_fit <- function(season_plays) {
  ns <- splines::ns
  h <- season_plays |>
    dplyr::filter(
      !.data$playType %in% game_kick_types(),
      .data$down > 0,
      !is.na(.data$yardsToGoal),
      !is.na(.data$distance),
      !is.na(.data$down)
    ) |>
    dplyr::mutate(
      half = dplyr::if_else(.data$period <= 2L, 1L, 2L),
      home_diff = dplyr::if_else(
        .data$offense == .data$home,
        .data$offenseScore - .data$defenseScore,
        .data$defenseScore - .data$offenseScore
      )
    ) |>
    dplyr::group_by(.data$gameId, .data$half) |>
    dplyr::arrange(.data$driveNumber, .data$playNumber, .by_group = TRUE) |>
    dplyr::mutate(final_diff = dplyr::last(.data$home_diff)) |>
    dplyr::ungroup() |>
    # Scoring plays already carry their points in the row's score; shift the
    # target back to the pre-play state. A touchdown row shows six points, not
    # yet the extra point, so seven folds the expected kick in.
    dplyr::mutate(
      pts_off = dplyr::case_when(
        .data$playType %in% game_off_td() ~ 7,
        .data$playType == "Safety" ~ 2,
        .data$playType %in% game_def_td() ~ -7,
        .data$playType == "Field Goal" ~ 3,
        .default = 0
      ),
      pts_home = .data$pts_off *
        dplyr::if_else(.data$offense == .data$home, 1L, -1L),
      y_pre = .data$final_diff - (.data$home_diff - .data$pts_home),
      y_off = .data$y_pre *
        dplyr::if_else(.data$offense == .data$home, 1L, -1L)
    )
  stats::lm(
    y_off ~
      ns(yardsToGoal, df = 8) *
      factor(down) +
      ns(distance, df = 4) +
      factor(down):ns(distance, df = 3),
    data = h
  )
}

#' Expected points at a situation, for vectors of situations
#'
#' Clamps yards to the goal to the field and down to 1 to 4, then predicts
#' from the fit. Vectorised, so a whole game's plays are scored in one call.
#'
#' @param fit A model from [game_ep_fit()].
#' @param yards_to_goal,down,distance Vectors of the situation.
#' @return A numeric vector of expected points.
#' @export
game_ep_at <- function(fit, yards_to_goal, down, distance) {
  as.numeric(stats::predict(
    fit,
    data.frame(
      yardsToGoal = pmin(pmax(yards_to_goal, 0), 99),
      down = pmin(pmax(as.integer(down), 1L), 4L),
      distance = distance
    )
  ))
}

#' Each scrimmage play's EP before and after, and its model EPA
#'
#' The curve's change across a play: the EP after minus the EP before, with a
#' touchdown worth `game_td_value` (6.94 points), a turnover handing the defense the mirrored
#' field position, and an incompletion on fourth down a turnover on downs.
#'
#' @param scr Scrimmage plays ([game_scrimmage()]).
#' @param fit A model from [game_ep_fit()].
#' @return `scr` with `td_off`, `turnover`, `incomplete`, `ep_before`,
#'   `ep_after` and `epa_mine`.
#' @export
game_epa_model <- function(scr, fit) {
  at <- function(ytg, dn, dist) game_ep_at(fit, ytg, dn, dist)
  scr |>
    dplyr::mutate(
      td_off = .data$playType %in% game_off_td(),
      turnover = .data$playType %in%
        c("Pass Interception Return", "Fumble Recovery (Opponent)"),
      incomplete = .data$playType == "Pass Incompletion",
      ep_before = at(.data$yardsToGoal, .data$down, .data$distance),
      ytg2 = .data$yardsToGoal - .data$yardsGained,
      ep_after = dplyr::case_when(
        .data$td_off ~ game_td_value,
        .data$turnover ~ -at(100 - .data$yardsToGoal, 1L, 10),
        .data$incomplete & .data$down < 4 ~
          at(.data$yardsToGoal, .data$down + 1L, .data$distance),
        .data$incomplete ~ -at(100 - .data$yardsToGoal, 1L, 10),
        .data$ytg2 <= 0 ~ game_td_value,
        .data$distance - .data$yardsGained <= 0 ~
          at(.data$ytg2, 1L, pmin(10, .data$ytg2)),
        .data$down + 1 > 4 ~ -at(100 - .data$ytg2, 1L, 10),
        .default = at(
          .data$ytg2,
          .data$down + 1L,
          .data$distance - .data$yardsGained
        )
      ),
      epa_mine = .data$ep_after - .data$ep_before
    )
}

#' Game clock as minutes elapsed in the game
#'
#' @param period,clock_minutes,clock_seconds The play's quarter and clock.
#' @return Minutes from kickoff, 0 to 60.
#' @export
game_minutes <- function(period, clock_minutes, clock_seconds) {
  (period - 1) * 15 + 15 - (clock_minutes + clock_seconds / 60)
}

#' Running EPA for each offense, in game order
#'
#' @param epa Scrimmage plays with `ppa` and `seq` ([game_epa_model()]).
#' @return The rated plays (non-missing `ppa`) with `play_n` (the offense's
#'   n-th rated play), `cum_ppa` (its running total) and `game_min`.
#' @export
game_running <- function(epa) {
  epa |>
    dplyr::filter(!is.na(.data$ppa)) |>
    dplyr::arrange(.data$seq) |>
    dplyr::group_by(.data$offense) |>
    dplyr::mutate(
      play_n = dplyr::row_number(),
      cum_ppa = cumsum(.data$ppa),
      game_min = game_minutes(
        .data$period,
        .data$clock_minutes,
        .data$clock_seconds
      )
    ) |>
    dplyr::ungroup()
}

#' EPA bands for each rated play
#'
#' Explosive plays gain at least `threshold` EPA, ordinary plays between 0 and
#' the threshold, negative plays below zero.
#'
#' @param epa Scrimmage plays with `ppa`, `period` and the clock.
#' @param threshold The EPA that makes a play explosive.
#' @return The rated plays with `quarter` ("Q1" to "Q4"), `band` and `minute`
#'   (minutes into the quarter).
#' @export
game_bands <- function(epa, threshold = 1.5) {
  band_exp <- paste0("Explosive play (EPA ", threshold, "+)")
  band_ord <- paste0("Ordinary play (EPA 0 to ", threshold, ")")
  band_neg <- "Negative play (EPA below 0)"
  epa |>
    dplyr::filter(!is.na(.data$ppa)) |>
    dplyr::mutate(
      quarter = paste0("Q", .data$period),
      band = dplyr::case_when(
        .data$ppa >= threshold ~ band_exp,
        .data$ppa >= 0 ~ band_ord,
        .default = band_neg
      ),
      minute = 15 - (.data$clock_minutes + .data$clock_seconds / 60)
    )
}

# The last non-missing value, or NA when there is none.
last_known <- function(x) {
  x <- x[!is.na(x)]
  if (length(x)) x[[length(x)]] else NA_real_
}

#' One row per drive, with its outcome and points
#'
#' The possession team is the offense of most of the drive's scrimmage plays
#' (the play log files a kickoff under the receiving team's drive). Points come
#' from each team's running score, since `offenseScore` flips with the offense.
#' A drive that ends on a turnover with no points is a turnover, not "no score".
#'
#' @param epa Scrimmage plays with `driveId`, `driveNumber`, `offense`,
#'   `yardsToGoal`, `seq`, `turnover`, `ppa` ([game_epa_model()]).
#' @param plays All of the game's plays ([game_plays()]), for the scores.
#' @param home_team,away_team The two teams' names, as the `offense` column
#'   spells them.
#' @return One row per drive: `offense`, `start_ytg`, `points`, `outcome`
#'   (factor), `drive_epa`, `home_start`, `away_start` and `drive_n`.
#' @export
game_drives <- function(epa, plays, home_team, away_team) {
  drive_scores <- plays |>
    dplyr::arrange(.data$driveNumber, .data$playNumber) |>
    dplyr::mutate(
      home_score = dplyr::if_else(
        .data$offense == .data$home,
        .data$offenseScore,
        .data$defenseScore
      ),
      away_score = dplyr::if_else(
        .data$offense == .data$home,
        .data$defenseScore,
        .data$offenseScore
      )
    ) |>
    dplyr::summarise(
      home_end = max(.data$home_score),
      away_end = max(.data$away_score),
      .by = c("driveId", "driveNumber")
    ) |>
    dplyr::arrange(.data$driveNumber) |>
    dplyr::mutate(
      home_start = dplyr::lag(cummax(.data$home_end), default = 0L),
      away_start = dplyr::lag(cummax(.data$away_end), default = 0L)
    )
  possession <- epa |>
    dplyr::count(.data$driveId, .data$offense) |>
    dplyr::slice_max(.data$n, n = 1, by = "driveId", with_ties = FALSE) |>
    dplyr::select("driveId", "offense")
  turnover_ends <- epa |>
    dplyr::filter(.data$turnover) |>
    dplyr::slice_max(.data$seq, n = 1, by = "driveId") |>
    dplyr::pull("driveId")
  drive_epa <- epa |>
    dplyr::filter(!is.na(.data$ppa)) |>
    dplyr::summarise(drive_epa = sum(.data$ppa), .by = "driveId")
  epa |>
    dplyr::semi_join(possession, by = c("driveId", "offense")) |>
    # kneel-downs carry 0 yards to goal, which no snap can start from
    dplyr::filter(.data$yardsToGoal > 0) |>
    dplyr::summarise(
      start_ytg = dplyr::first(.data$yardsToGoal),
      .by = c("driveId", "driveNumber", "offense")
    ) |>
    dplyr::left_join(drive_scores, by = c("driveId", "driveNumber")) |>
    dplyr::mutate(
      points = dplyr::if_else(
        .data$offense == home_team,
        .data$home_end - .data$home_start,
        .data$away_end - .data$away_start
      ),
      outcome = dplyr::case_when(
        .data$points >= 6 ~ "Touchdown",
        .data$points == 3 ~ "Field goal",
        .default = "No score"
      ),
      outcome = dplyr::if_else(
        .data$outcome == "No score" & .data$driveId %in% turnover_ends,
        "Turnover",
        .data$outcome
      ),
      outcome = factor(
        .data$outcome,
        c("Touchdown", "Field goal", "No score", "Turnover")
      )
    ) |>
    dplyr::left_join(drive_epa, by = "driveId") |>
    dplyr::arrange(.data$driveNumber) |>
    dplyr::mutate(drive_n = dplyr::row_number()) |>
    dplyr::select(
      "driveId",
      "driveNumber",
      "offense",
      "start_ytg",
      "points",
      "outcome",
      "drive_epa",
      "home_start",
      "away_start",
      "drive_n"
    )
}

# Plays whose spot is where the ball was at the snap, not where it was carried.
game_spot_at_snap <- function() {
  c(
    "Punt",
    "Punt Return",
    "Field Goal Good",
    "Field Goal Missed",
    "Blocked Field Goal",
    "Penalty",
    "Pass Interception Return",
    "Fumble Recovery (Opponent)",
    "Interception Return Touchdown",
    "Fumble Return Touchdown"
  )
}

#' Where each drive starts and ends on the field
#'
#' Punts, kicks and turnovers end at the line of scrimmage (a turnover's yards
#' include the return); other plays end where the ball was carried. Kneel-downs
#' give no spot, so a kneel-only drive ends where it began. `x` runs from the
#' home team's goal line (0) to the opponent's (100).
#'
#' @param drives Drives from [game_drives()].
#' @param plays All of the game's plays.
#' @param home_team The team that defends the left end zone (x = 0).
#' @return `drives` with `t0`, `t1` (game minutes at the first and last snap),
#'   `x0`, `x1` (the field position), `x_next` and `t_next` (the next drive's
#'   start, which the change of possession links to).
#' @export
game_drive_arrows <- function(drives, plays, home_team) {
  geo <- plays |>
    dplyr::inner_join(
      dplyr::select(drives, "driveId", poss = "offense"),
      by = "driveId"
    ) |>
    dplyr::filter(
      .data$offense == .data$poss,
      !.data$playType %in%
        c("Kickoff", "Timeout", "End Period", "End of Half", "End of Game")
    ) |>
    dplyr::arrange(.data$driveNumber, .data$playNumber) |>
    dplyr::mutate(
      t = game_minutes(.data$period, .data$clock_minutes, .data$clock_seconds),
      spot = dplyr::case_when(
        .data$yardsToGoal == 0 ~ NA_real_,
        .data$playType %in% game_off_td() ~ 0,
        .data$playType %in% game_spot_at_snap() ~ .data$yardsToGoal,
        .default = pmax(.data$yardsToGoal - .data$yardsGained, 1)
      )
    ) |>
    dplyr::summarise(
      t0 = dplyr::first(.data$t),
      t1 = dplyr::last(.data$t),
      end_ytg = last_known(.data$spot),
      .by = "driveId"
    )
  drives |>
    dplyr::left_join(geo, by = "driveId") |>
    dplyr::mutate(
      end_ytg = dplyr::coalesce(.data$end_ytg, .data$start_ytg),
      x0 = dplyr::if_else(
        .data$offense == home_team,
        100 - .data$start_ytg,
        .data$start_ytg
      ),
      x1 = dplyr::if_else(
        .data$offense == home_team,
        100 - .data$end_ytg,
        .data$end_ytg
      ),
      x_next = dplyr::lead(.data$x0),
      t_next = dplyr::lead(.data$t0)
    )
}

#' Each drive's average EPA per play, placed at its midpoint in game time
#'
#' @param running Rated plays from [game_running()].
#' @return One row per drive: `driveId`, `offense`, `plays`, `avg` (the mean
#'   PPA), `game_min` (the midpoint of its first and last snap), `period`.
#' @export
game_drive_averages <- function(running) {
  running |>
    dplyr::summarise(
      plays = dplyr::n(),
      avg = mean(.data$ppa),
      mid_min = (min(.data$game_min) + max(.data$game_min)) / 2,
      period = dplyr::first(.data$period),
      .by = c("driveId", "offense")
    ) |>
    dplyr::rename(game_min = "mid_min") |>
    dplyr::arrange(.data$game_min)
}

#' Each play's players: the log plus the play text's extra names
#'
#' Resolves the play text's `#<jersey> <I.Surname>` mentions against the
#' game's two rosters (season `season`), then splits each play's EPA evenly
#' among the players named on each side ([build_play_involvement()]). Roles
#' come from the play-stats log, the text, or both.
#'
#' @param con A DuckDB connection to `cfb2nfl.duckdb`.
#' @param game_id The CFBD game id.
#' @param season The season the rosters are read from.
#' @param rated The game's rated plays with `id`, `playText`, `offense`,
#'   `ppa`, `seq`, `period` and `yardsGained` ([game_running()] or
#'   [game_epa_model()]).
#' @param teams The two team names the rosters are read for.
#' @return A list: `involvement` (one row per player per play, with `player`,
#'   `jersey`, `position`, `group` (position group), `label` (`"#14 Name, QB"`)
#'   and `share`), `unresolved` (the number of text mentions that matched no
#'   roster player) and `log` (the play-stats log rows).
#' @export
game_involvement <- function(con, game_id, season, rated, teams) {
  game_log <- DBI::dbGetQuery(
    con,
    paste0(
      "SELECT playId, athleteId, athleteName, team, statType ",
      "FROM play_stats WHERE gameId = ?"
    ),
    params = list(as.integer(game_id))
  )
  directory <- DBI::dbGetQuery(
    con,
    "SELECT r.playerId, r.team, r.jersey, r.position, s.player
     FROM roster r
     JOIN (SELECT DISTINCT playerId, team, player FROM player_stats
           WHERE season = ?) s
       ON s.playerId = r.playerId AND s.team = r.team
     WHERE r.season = ? AND r.team IN (?, ?)",
    params = list(
      as.integer(season),
      as.integer(season),
      teams[[1]],
      teams[[2]]
    )
  )
  mentions <- play_text_mentions(rated) |>
    match_play_mentions(directory)
  log_names <- dplyr::distinct(
    game_log,
    playerId = .data$athleteId,
    log_name = .data$athleteName
  )
  inv <- build_play_involvement(rated, game_log, mentions) |>
    dplyr::left_join(
      dplyr::distinct(
        directory,
        .data$playerId,
        .data$player,
        .data$position,
        .data$jersey
      ),
      by = "playerId"
    ) |>
    dplyr::left_join(log_names, by = "playerId") |>
    dplyr::left_join(
      dplyr::select(rated, "id", "seq", "period", "playText", "yardsGained"),
      by = "id"
    ) |>
    dplyr::mutate(
      player = dplyr::coalesce(.data$player, .data$log_name),
      group = harmonize_position(.data$position, "roster"),
      label = paste0(
        dplyr::if_else(is.na(.data$jersey), "", paste0("#", .data$jersey, " ")),
        .data$player,
        dplyr::if_else(is.na(.data$position), "", paste0(", ", .data$position))
      )
    )
  list(
    involvement = inv,
    unresolved = sum(is.na(mentions$playerId)),
    log = game_log
  )
}

#' One row per player: how often named and what the plays were worth
#'
#' @param inv The involvement table ([game_involvement()]).
#' @return One row per player: `playerId`, `player`, `label`, `team`, `group`,
#'   `involvements`, `epa` (the sum of their shares), `per_inv` (the average
#'   EPA of their plays from their own side), `q_played` and `q_pos` (quarters
#'   played, and quarters their share was positive).
#' @export
game_players <- function(inv) {
  inv |>
    dplyr::summarise(
      team = dplyr::first(.data$team),
      group = dplyr::first(.data$group),
      involvements = dplyr::n(),
      epa = sum(.data$share),
      per_inv = mean(.data$epa_side),
      q_played = dplyr::n_distinct(.data$period),
      q_pos = sum(tapply(.data$share, .data$period, sum) > 0),
      .by = c("playerId", "player", "label")
    ) |>
    dplyr::arrange(dplyr::desc(.data$epa))
}

#' Each position group's typical play
#'
#' Compares every involvement with its group's typical play: the average EPA
#' per involvement over both teams. The offensive line is left out, since the
#' text names a lineman only on a tackle after a turnover.
#'
#' @param inv The involvement table ([game_involvement()]).
#' @return The involvements of the groups in [harmonized_position_levels()]
#'   order, with `group` a factor and `typical` the group's average `epa_side`.
#' @export
game_group_typical <- function(inv) {
  group_order <- intersect(
    harmonized_position_levels(),
    setdiff(unique(inv$group), "Offensive line")
  )
  inv |>
    dplyr::filter(.data$group %in% group_order) |>
    dplyr::mutate(
      group = factor(.data$group, levels = group_order),
      typical = mean(.data$epa_side),
      .by = "group"
    )
}
