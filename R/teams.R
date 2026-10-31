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
