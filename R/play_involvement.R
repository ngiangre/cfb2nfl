# Player involvement in plays: who the play-stats log names on a play, plus
# anyone the play-by-play text names that the log leaves out (CFBD's log
# carries no tackle stat type in many games, while the text lists the
# tacklers in parentheses). Built on the fly for posts (decision 0041).

# A text mention: jersey, then an initial-dot-surname name with an optional
# generational suffix, e.g. "#95 J.Marshall" or "#81 C.Dandridge Jr.".
mention_pattern <- paste0(
  "#(\\d+) ([A-Z][A-Za-z']*\\.\\s?[A-Z][A-Za-z'\\-]+",
  "(?: (?:Jr\\.?|Sr\\.?|II|III|IV|V)(?![A-Za-z]))?)"
)

# Lowercase surname with any generational suffix removed.
name_surname <- function(x) {
  x |>
    stringr::str_remove(" (Jr\\.?|Sr\\.?|II|III|IV|V)$") |>
    stringr::str_extract("[A-Za-z'\\-]+$") |>
    tolower()
}

#' Players named in play-by-play text
#'
#' Extracts every `#<jersey> <I.Surname>` mention from each play's text and
#' labels the role the surrounding words give it. Text that does not describe
#' the counted play is removed first: an overturned play's "Original Play"
#' description, and the extra-point attempt appended to a touchdown row.
#' Players reported injured on the play are dropped, since being hurt is not
#' taking part in the play's result.
#'
#' @param plays Data frame with `id` and `playText`.
#' @return One row per mention: `id`, `jersey` (integer), `text_name`,
#'   `role` (`"Ball carrier or passer"`, `"Target"`, `"Tackle"`,
#'   `"Pass breakup"`, `"Interception"`, `"Fumble"`, `"Fumble forced"`,
#'   `"Fumble recovered"`, `"Penalty"`, `"Kicker or punter"`, `"Holder"`,
#'   `"Long snapper"`, `"Kick blocked"` or `"Other"`).
#' @export
play_text_mentions <- function(plays) {
  txt <- plays$playText |>
    dplyr::coalesce("") |>
    stringr::str_remove("\\(Original Play:.*$") |>
    stringr::str_remove("#\\d+ \\S+ kick attempt.*$")
  hits <- stringr::str_match_all(txt, mention_pattern)
  locs <- stringr::str_locate_all(txt, mention_pattern)
  n <- vapply(hits, nrow, integer(1))
  out <- tibble::tibble(
    id = rep(plays$id, n),
    txt = rep(txt, n),
    jersey = as.integer(unlist(lapply(hits, \(h) h[, 2]))),
    text_name = unlist(lapply(hits, \(h) h[, 3])),
    start = unlist(lapply(locs, \(l) l[, 1])),
    end = unlist(lapply(locs, \(l) l[, 2]))
  )
  out |>
    dplyr::mutate(
      before = stringr::str_sub(
        .data$txt,
        pmax(1L, .data$start - 40L),
        .data$start - 1L
      ),
      after = stringr::str_sub(.data$txt, .data$end + 1L, .data$end + 14L),
      role = dplyr::case_when(
        stringr::str_detect(.data$after, "^ injured") ~ "Injured",
        stringr::str_detect(
          .data$before,
          "PENALTY [A-Z]+ [A-Za-z ]+\\($"
        ) ~ "Penalty",
        stringr::str_detect(.data$before, "broken up by $") ~ "Pass breakup",
        stringr::str_detect(.data$before, "forced by $") ~ "Fumble forced",
        stringr::str_detect(.data$before, "fumbled by $") ~ "Fumble",
        stringr::str_detect(
          .data$before,
          "recovered by [A-Z]+ $"
        ) ~ "Fumble recovered",
        stringr::str_detect(.data$before, "intercepted by $") ~ "Interception",
        stringr::str_detect(.data$before, "blocked by $") ~ "Kick blocked",
        stringr::str_detect(.data$before, "H: $") ~ "Holder",
        stringr::str_detect(.data$before, "LS: $") ~ "Long snapper",
        stringr::str_detect(
          .data$after,
          "^ (kickoff|punt|field goal|on-side kick|onside kick)"
        ) ~
          "Kicker or punter",
        stringr::str_detect(.data$after, "^ return") ~ "Interception",
        stringr::str_detect(.data$after, "^ (rush|pass|sacked|scramble)") ~
          "Ball carrier or passer",
        stringr::str_detect(.data$before, " to $") ~ "Target",
        stringr::str_detect(.data$before, "(\\(|; )$") ~ "Tackle",
        .default = "Other"
      )
    ) |>
    dplyr::filter(.data$role != "Injured") |>
    dplyr::select("id", "jersey", "text_name", "role")
}

#' Resolve text mentions to athlete ids
#'
#' Matches each mention to a player in a name directory by jersey number and
#' surname. Jersey alone is not enough, since a team reuses numbers across
#' offense and defense, and both teams are searched because the text does not
#' say which side a tackler plays for. A mention with no match, or with more
#' than one, keeps `playerId = NA` so the caller can count it.
#'
#' @param mentions Output of [play_text_mentions()].
#' @param directory Data frame with one row per player: `playerId`, `team`,
#'   `jersey`, `player` (full name), plus any `by` columns.
#' @param by Extra columns, in both `mentions` and `directory`, that narrow
#'   the search, e.g. `"gameId"` with a directory of each game's two rosters
#'   from [play_mention_directory()]. The default searches the whole
#'   directory, so it should hold only the game's two teams.
#' @return `mentions` with `playerId` and `team` added (both `NA` when the
#'   mention does not resolve to exactly one player).
#' @export
match_play_mentions <- function(mentions, directory, by = character()) {
  dir <- directory |>
    dplyr::transmute(
      dplyr::across(dplyr::all_of(by)),
      .data$playerId,
      .data$team,
      jersey = as.integer(.data$jersey),
      surname = name_surname(.data$player)
    ) |>
    dplyr::distinct()
  keyed <- mentions |>
    dplyr::mutate(
      .row = dplyr::row_number(),
      surname = name_surname(.data$text_name)
    )
  hits <- keyed |>
    dplyr::select(".row", dplyr::all_of(by), "jersey", "surname") |>
    dplyr::inner_join(
      dir,
      by = c(by, "jersey", "surname"),
      relationship = "many-to-many"
    ) |>
    dplyr::filter(dplyr::n() == 1L, .by = ".row")
  keyed |>
    dplyr::left_join(
      dplyr::select(hits, ".row", "playerId", "team"),
      by = ".row"
    ) |>
    dplyr::select(-".row", -"surname")
}

#' Each game's two rosters, for matching play-text mentions
#'
#' The directory [match_play_mentions()] searches with `by = "gameId"`: every
#' player on either team's roster in the game's season, named from the roster
#' (so linemen and others with no stat line can still match).
#'
#' @param roster Cleaned roster (`playerId`, `season`, `team`, `jersey`,
#'   `first_name`, `last_name`).
#' @param games Games with `id`, `season`, `homeTeam` and `awayTeam`.
#' @return One row per game and roster player: `gameId`, `playerId`, `team`,
#'   `jersey`, `player`. Players with no jersey are left out.
#' @export
play_mention_directory <- function(roster, games) {
  sides <- dplyr::bind_rows(
    dplyr::select(games, gameId = "id", "season", team = "homeTeam"),
    dplyr::select(games, gameId = "id", "season", team = "awayTeam")
  )
  roster |>
    dplyr::filter(!is.na(.data$jersey)) |>
    dplyr::transmute(
      .data$season,
      .data$team,
      .data$playerId,
      jersey = as.integer(.data$jersey),
      player = stringr::str_squish(paste(
        dplyr::coalesce(.data$first_name, ""),
        dplyr::coalesce(.data$last_name, "")
      ))
    ) |>
    dplyr::distinct() |>
    dplyr::inner_join(
      sides,
      by = c("season", "team"),
      relationship = "many-to-many"
    ) |>
    dplyr::select("gameId", "playerId", "team", "jersey", "player")
}

#' Players the play text names but the play-stats log leaves out
#'
#' Reads each play's text with [play_text_mentions()], resolves the mentions
#' against the game's two rosters with [match_play_mentions()], and keeps the
#' players the log does not already name on that play. Unresolved and
#' ambiguous mentions are dropped rather than guessed.
#'
#' @param plays Data frame with `id`, `gameId` and `playText`.
#' @param play_stats Play-stats log rows with `playId` and `athleteId`.
#' @param directory Output of [play_mention_directory()].
#' @return One row per `(id, playerId)`: `team`, `player` (the roster name)
#'   and `roles` (comma-separated, in text order).
#' @export
play_text_players <- function(plays, play_stats, directory) {
  logged <- dplyr::distinct(
    play_stats,
    id = .data$playId,
    playerId = as.character(.data$athleteId)
  )
  who <- dplyr::distinct(directory, .data$playerId, .data$player) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE)
  mentions <- play_text_mentions(plays)
  mentions$gameId <- plays$gameId[match(mentions$id, plays$id)]
  mentions |>
    match_play_mentions(directory, by = "gameId") |>
    dplyr::filter(!is.na(.data$playerId)) |>
    dplyr::mutate(playerId = as.character(.data$playerId)) |>
    dplyr::anti_join(logged, by = c("id", "playerId")) |>
    dplyr::summarise(
      team = dplyr::first(.data$team),
      roles = paste(unique(.data$role), collapse = ", "),
      .by = c("id", "playerId")
    ) |>
    dplyr::left_join(who, by = "playerId", relationship = "many-to-one") |>
    dplyr::select("id", "playerId", "team", "player", "roles")
}

# Log stat types -> the role labels the text mentions use.
log_role <- function(stat_type) {
  dplyr::case_when(
    stat_type %in%
      c(
        "Rush",
        "Completion",
        "Incompletion",
        "Interception Thrown",
        "Sack Taken"
      ) ~
      "Ball carrier or passer",
    stat_type %in% c("Reception", "Target") ~ "Target",
    stat_type == "Pass Breakup" ~ "Pass breakup",
    stat_type == "Fumble Forced" ~ "Fumble forced",
    stat_type == "Fumble Recovered" ~ "Fumble recovered",
    .default = stat_type
  )
}

#' Players involved in each play, with the play's EPA split among them
#'
#' One row per player per play. The play-stats log is read first; a text
#' mention adds a player only when the log does not already name that athlete
#' on that play. Each play's EPA is then credited to its players from their
#' own side: the offense's players share `ppa`, the defense's players share
#' `-ppa`, split evenly among the players named on that side. So the shares of
#' a team's offensive players add up to the team's EPA on those plays, and a
#' play that names no defender gives the defense no credit.
#'
#' @param plays Data frame with `id`, `offense` and `ppa` (plays with `NA`
#'   `ppa` are dropped).
#' @param play_stats Play-stats log rows with `playId`, `athleteId`, `team`
#'   and `statType`.
#' @param mentions Output of [match_play_mentions()]; unresolved mentions are
#'   ignored.
#' @return One row per `(id, playerId)`: `team`, `source` (`"Play-stats log"`
#'   or `"Play text"`), `roles` (comma-separated), `side` (`"Offense"` or
#'   `"Defense"`), `epa_side` (the play's EPA from the player's side),
#'   `n_side` (players named on that side of the play) and `share`
#'   (`epa_side / n_side`).
#' @export
build_play_involvement <- function(plays, play_stats, mentions) {
  plays <- dplyr::filter(plays, !is.na(.data$ppa))
  from_log <- play_stats |>
    dplyr::filter(.data$playId %in% plays$id) |>
    dplyr::transmute(
      id = .data$playId,
      playerId = as.character(.data$athleteId),
      .data$team,
      role = log_role(.data$statType),
      source = "Play-stats log"
    )
  from_text <- mentions |>
    dplyr::filter(!is.na(.data$playerId), .data$id %in% plays$id) |>
    dplyr::transmute(
      .data$id,
      playerId = as.character(.data$playerId),
      .data$team,
      .data$role,
      source = "Play text"
    ) |>
    dplyr::anti_join(from_log, by = c("id", "playerId"))
  dplyr::bind_rows(from_log, from_text) |>
    dplyr::filter(.data$role != "Touchdown") |>
    dplyr::summarise(
      team = dplyr::first(.data$team),
      source = dplyr::first(.data$source),
      roles = paste(unique(.data$role), collapse = ", "),
      .by = c("id", "playerId")
    ) |>
    dplyr::inner_join(
      dplyr::select(plays, "id", "offense", "ppa"),
      by = "id"
    ) |>
    dplyr::mutate(
      side = dplyr::if_else(.data$team == .data$offense, "Offense", "Defense"),
      epa_side = dplyr::if_else(.data$side == "Offense", .data$ppa, -.data$ppa)
    ) |>
    dplyr::mutate(n_side = dplyr::n(), .by = c("id", "side")) |>
    dplyr::mutate(share = .data$epa_side / .data$n_side) |>
    dplyr::select(-"offense", -"ppa")
}
