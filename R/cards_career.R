# Data behind the career-shape figure cards (feature F25, batch career): the
# yardage arcs, the playing-time shares, the absence signals and the
# redshirt coverage. The cards call these on the tables they read, so each
# figure's numbers are tested here and the card code stays the figure.

# Each offensive skill position is followed through one yardage stat: a
# quarterback by passing, a running back by rushing, a receiver by receiving.
signature_stats <- tibble::tribble(
  ~pos , ~group         , ~game_stat , ~category   ,
  "QB" , "Quarterback"  , "pass_yds" , "passing"   ,
  "RB" , "Running back" , "rush_yds" , "rushing"   ,
  "WR" , "Receiver"     , "rec_yds"  , "receiving"
)

# Opponent Elo bands in order, the last being opponents CFBD does not rate.
opponent_band_levels <- c(
  "Under 1400",
  "1400 to 1599",
  "1600 to 1799",
  "1800 and up",
  "Unrated"
)

#' One signature position per player
#'
#' The position a player appears at most often on a roster, restricted to
#' quarterback, running back and receiver (ties go to the first position
#' sorted alphabetically). Keyed on athlete id.
#'
#' @param roster The roster table (`playerId`, `season`, `position`).
#' @return A tibble with `playerId`, `pos` and `group`.
#' @export
signature_positions <- function(roster) {
  roster |>
    dplyr::filter(.data$position %in% signature_stats$pos) |>
    dplyr::count(.data$playerId, .data$position, name = "n") |>
    dplyr::group_by(.data$playerId) |>
    dplyr::slice_max(.data$n, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      pos = .data$position,
      group = position_group(.data$position)
    ) |>
    dplyr::arrange(.data$playerId)
}

#' Season totals of each player's signature yards
#'
#' @param sa Season arcs from [build_season_arcs()].
#' @param positions Output of [signature_positions()].
#' @return One row per player-season with the group and its yardage total.
#' @export
signature_season_values <- function(sa, positions) {
  sa |>
    dplyr::filter(.data$statType == "YDS") |>
    dplyr::inner_join(
      positions,
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::inner_join(
      signature_stats |> dplyr::select("pos", "category"),
      by = c("pos", "category")
    ) |>
    dplyr::select(
      "group",
      "pos",
      "playerId",
      "player",
      "season",
      "season_index",
      "team",
      "value"
    )
}

#' Game-level signature yards, banded by opponent strength
#'
#' @param gp Game production from [build_game_production()].
#' @param positions Output of [signature_positions()].
#' @return One row per player-game with the group, opponent band (a factor in
#'   [opponent_band_levels]), yards and opponent-adjusted residual.
#' @export
signature_game_values <- function(gp, positions) {
  gp |>
    dplyr::inner_join(
      positions,
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::inner_join(
      signature_stats |> dplyr::select("pos", stat = "game_stat"),
      by = c("pos", "stat")
    ) |>
    dplyr::mutate(
      band = factor(.data$opponent_elo_band, opponent_band_levels)
    ) |>
    dplyr::select(
      "group",
      "pos",
      "playerId",
      "season",
      "band",
      "value",
      "residual"
    )
}

#' Median signature yards by career season
#'
#' Keeps only the career seasons where every group still has at least
#' `min_players` players, so the medians compare like with like.
#'
#' @param values Output of [signature_season_values()].
#' @param min_players The fewest players a group needs in a career season.
#' @return One row per group and kept career season.
#' @export
median_arcs <- function(values, min_players = 50L) {
  counts <- values |>
    dplyr::count(.data$group, .data$season_index, name = "n")
  keep <- counts |>
    dplyr::group_by(.data$season_index) |>
    dplyr::summarise(smallest = min(.data$n), .groups = "drop") |>
    dplyr::filter(.data$smallest >= min_players) |>
    dplyr::pull(.data$season_index)
  values |>
    dplyr::filter(.data$season_index %in% keep) |>
    dplyr::group_by(.data$group, .data$season_index) |>
    dplyr::summarise(
      med = stats::median(.data$value),
      q1 = stats::quantile(.data$value, 0.25, names = FALSE),
      q3 = stats::quantile(.data$value, 0.75, names = FALSE),
      players = dplyr::n(),
      .groups = "drop"
    )
}

#' Mean signature yards by group and opponent band
#'
#' @param games Output of [signature_game_values()].
#' @return One row per group and band, with the mean, its standard deviation
#'   and the mean plus or minus one standard deviation (floored at zero).
#' @export
band_gradient <- function(games) {
  games |>
    dplyr::group_by(.data$group, .data$band) |>
    dplyr::summarise(
      mean_yds = mean(.data$value),
      sd_yds = stats::sd(.data$value),
      games = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      lo = pmax(.data$mean_yds - .data$sd_yds, 0),
      hi = .data$mean_yds + .data$sd_yds
    )
}

#' How much yards fall from the weakest to the strongest rated band
#'
#' Unrated opponents are not the weakest rated band, so they are left out.
#'
#' @param grad Output of [band_gradient()].
#' @return One row per group: the drop in mean yards per game.
#' @export
band_drop <- function(grad) {
  grad |>
    dplyr::filter(.data$band != "Unrated") |>
    dplyr::group_by(.data$group) |>
    dplyr::summarise(
      drop = .data$mean_yds[.data$band == "Under 1400"] -
        .data$mean_yds[.data$band == "1800 and up"],
      .groups = "drop"
    )
}

#' Game-to-game spread of the opponent-adjusted residual
#'
#' The residual is yards minus the season and opponent-band baseline, so it
#' centres near zero; `rel_sd` is its standard deviation over the group's
#' mean yards per game, so groups on different yardage scales compare.
#'
#' @param games Output of [signature_game_values()].
#' @return One row per group.
#' @export
residual_spread <- function(games) {
  games |>
    dplyr::group_by(.data$group) |>
    dplyr::summarise(
      games = dplyr::n(),
      sd = stats::sd(.data$residual),
      iqr = stats::IQR(.data$residual),
      p90 = stats::quantile(.data$residual, 0.9, names = FALSE),
      rel_sd = stats::sd(.data$residual) / mean(.data$value),
      .groups = "drop"
    )
}

#' Rostered player-seasons, one team each, in the seasons read
#'
#' The population the playing-time and absence cards reason about: a player
#' on a roster with a scheduled game in a season, on one team only, so a
#' transfer's split season is not read as a gap.
#'
#' @param usage The playing-time table ([build_player_usage()]).
#' @param seasons The seasons to keep.
#' @return The filtered rows, with a position group.
#' @export
rostered_one_team <- function(usage, seasons) {
  usage |>
    dplyr::filter(
      .data$on_roster,
      .data$team_games > 0,
      .data$season %in% seasons,
      !is.na(.data$position_group)
    ) |>
    dplyr::group_by(.data$playerId, .data$season) |>
    dplyr::filter(dplyr::n() == 1L) |>
    dplyr::ungroup()
}

#' Share of rostered player-seasons that log a stat line
#'
#' @param usage The playing-time table.
#' @param seasons The seasons to keep.
#' @return One row per position group: player-seasons, the share with a stat
#'   line in at least one game, and the median share of games with a line
#'   among those who logged one.
#' @export
stat_line_share <- function(usage, seasons) {
  rostered_one_team(usage, seasons) |>
    dplyr::group_by(.data$position_group) |>
    dplyr::summarise(
      player_seasons = dplyr::n(),
      any_line = mean(.data$games_appeared > 0),
      median_share_if_any = stats::median(
        .data$appearance_rate[.data$games_appeared > 0]
      ),
      .groups = "drop"
    )
}

#' Rostered player-seasons labelled drafted or not
#'
#' Draft status is an outcome label, joined here and never on the playing-time
#' table itself. Only draft-eligible seasons with a known outcome are kept.
#'
#' @param usage The playing-time table.
#' @param outcomes The outcomes table.
#' @param seasons The seasons to keep.
#' @return One row per labelled player-season, with `drafted`.
#' @export
drafted_stat_line <- function(usage, outcomes, seasons) {
  labels <- outcomes |>
    dplyr::filter(
      .data$draft_eligible %in% TRUE,
      !is.na(.data$outcome_drafted_d)
    ) |>
    dplyr::transmute(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season),
      drafted = .data$outcome_drafted_d %in% TRUE
    )
  rostered_one_team(usage, seasons) |>
    dplyr::inner_join(labels, by = c("playerId", "season"))
}

#' Each group's early stop set against its next most common ending
#'
#' @param statline Finished stat-line careers with `position_group` and
#'   `career_end`.
#' @return Two rows per group: the early stop, and the most common other
#'   ending (`bar` says which).
#' @export
early_stop_comparison <- function(statline) {
  shares <- statline |>
    dplyr::count(.data$position_group, .data$career_end, name = "n") |>
    dplyr::group_by(.data$position_group) |>
    dplyr::mutate(share = .data$n / sum(.data$n)) |>
    dplyr::ungroup()
  early <- shares |>
    dplyr::filter(.data$career_end == "early_stop") |>
    dplyr::mutate(bar = "Stopped with eligibility left")
  runner_up <- shares |>
    dplyr::filter(.data$career_end != "early_stop") |>
    dplyr::group_by(.data$position_group) |>
    dplyr::slice_max(.data$share, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::mutate(bar = "Next most common ending")
  dplyr::bind_rows(early, runner_up) |>
    dplyr::select("position_group", "career_end", "share", "bar")
}

#' Absence shapes by position group
#'
#' Shares are among the seasons that can be read (`observable`), so a
#' season-ending absence and an absence followed by a return are read only
#' where the box score can show them.
#'
#' @param absence Output of [absence_runs()] joined to a position group.
#' @return One row per position group.
#' @export
absence_summary <- function(absence) {
  absence |>
    dplyr::group_by(.data$position_group) |>
    dplyr::summarise(
      seasons = dplyr::n(),
      readable_n = sum(.data$observable),
      readable = mean(.data$observable),
      returned = mean(.data$absence_shape[.data$observable] == "returned"),
      season_ending = mean(
        .data$absence_shape[.data$observable] == "season_ending"
      ),
      injury_shaped = .data$returned + .data$season_ending,
      .groups = "drop"
    )
}

#' Benching-shaped declines by position and usage count
#'
#' @param decline Output of [usage_decline()] with a position group.
#' @param absence_by_pos Output of [absence_summary()], for the seasons base.
#' @return One row per position group and usage count.
#' @export
decline_summary <- function(decline, absence_by_pos) {
  decline |>
    dplyr::group_by(.data$position_group, .data$usage_label) |>
    dplyr::summarise(
      with_line = dplyr::n(),
      readable_n = sum(.data$observable),
      declined = mean(.data$declined[.data$observable]),
      .groups = "drop"
    ) |>
    dplyr::left_join(
      dplyr::select(absence_by_pos, "position_group", "seasons"),
      by = "position_group"
    ) |>
    dplyr::mutate(readable = .data$readable_n / .data$seasons)
}

#' How finished stat-line careers' final seasons ended
#'
#' @param statline Finished stat-line careers with `playerId`, `last_season`
#'   and `career_end`.
#' @param absence Absence shapes by player-season ([absence_runs()]).
#' @param window The seasons the careers' final seasons must fall in.
#' @param final_endings The endings to keep.
#' @return One row per ending: careers, the share whose final season can be
#'   read, and the share of readable final seasons ending in a season-ending
#'   absence.
#' @export
final_endings <- function(statline, absence, window, final_endings) {
  statline |>
    dplyr::filter(
      .data$last_season %in% window,
      .data$career_end %in% final_endings
    ) |>
    dplyr::left_join(
      dplyr::select(
        absence,
        "playerId",
        "season",
        "observable",
        "absence_shape"
      ),
      by = c("playerId", "last_season" = "season")
    ) |>
    dplyr::mutate(observable = .data$observable %in% TRUE) |>
    dplyr::group_by(.data$career_end) |>
    dplyr::summarise(
      careers = dplyr::n(),
      readable = mean(.data$observable),
      season_ending = mean(
        .data$absence_shape[.data$observable] == "season_ending"
      ),
      .groups = "drop"
    )
}

#' A season's usage-based redshirt flag
#'
#' A season is redshirt-shaped when the team's game-statistics table covers
#' at least five regular-season games and the player recorded a statistic in
#' at most one of them. Thinner coverage is unresolved, not cleared.
#'
#' @param flags Roster seasons (`playerId`, `season`, `team`).
#' @param attempts Pass attempts per player-season (`playerId`, `season`,
#'   `attempts`).
#' @param player_games Games with a statistic per player-season
#'   (`playerId`, `season`, `games_with_stat`).
#' @param covered Covered regular-season games per team-season
#'   (`season`, `team`, `games_covered`).
#' @return The roster seasons with attempts, the game counts and `likely_rs`
#'   (`TRUE`, `FALSE`, or `NA` when unresolvable) and a reader label.
#' @export
redshirt_spine <- function(flags, attempts, player_games, covered) {
  flags |>
    dplyr::left_join(attempts, by = c("playerId", "season")) |>
    dplyr::left_join(player_games, by = c("playerId", "season")) |>
    dplyr::left_join(covered, by = c("season", "team")) |>
    dplyr::mutate(
      games_with_stat = dplyr::coalesce(.data$games_with_stat, 0L),
      likely_rs = dplyr::if_else(
        !is.na(.data$games_covered) & .data$games_covered >= 5,
        .data$games_with_stat <= 1,
        NA
      ),
      flag_label = dplyr::case_when(
        is.na(.data$likely_rs) ~ "Unresolvable (under 5 covered games)",
        .data$likely_rs ~ "Redshirt-shaped",
        TRUE ~ "Played"
      )
    )
}

#' How often a stat line shows up, for full-time and other seasons
#'
#' A full-time season is in the top quarter of its position by volume. Only
#' seasons the data has finished count: the season still being played would
#' pull the rates down.
#'
#' @param stat_rate One row per player-season-team with `pos`, `season`,
#'   `volume` and `rate` (share of covered games with a stat line).
#' @param last_season The last complete season.
#' @return One row per position and full-time flag: the median rate and the
#'   number of seasons.
#' @export
observability_by_position <- function(stat_rate, last_season) {
  stat_rate |>
    dplyr::filter(.data$season <= last_season) |>
    dplyr::group_by(.data$pos) |>
    dplyr::mutate(
      full_time = .data$volume >= stats::quantile(.data$volume, 0.75)
    ) |>
    dplyr::group_by(.data$pos, .data$full_time) |>
    dplyr::summarise(
      rate = stats::median(.data$rate),
      n = dplyr::n(),
      .groups = "drop"
    )
}

#' Text colour that reads on a fill
#'
#' White on dark fills, near-black on light ones, by relative luminance.
#'
#' @param hex Fill colours.
#' @return A character vector of text colours.
#' @export
label_text_colour <- function(hex) {
  m <- grDevices::col2rgb(hex) / 255
  lin <- ifelse(m <= 0.03928, m / 12.92, ((m + 0.055) / 1.055)^2.4)
  lum <- 0.2126 * lin[1, ] + 0.7152 * lin[2, ] + 0.0722 * lin[3, ]
  ifelse(lum < 0.5, "white", "#111827")
}
