# Player x game derived table (decision 0035): the shared grain for per-game
# usage (#50), opponent-adjusted game performance (#47), and games-appeared
# counts. A derived table like career_summary (decision 0021): built from the
# cleaned game tables, bundled into DuckDB, not published as parquet.

# Stat columns kept on the player-game grain: one wide column per (category,
# statType) pair, named for what it counts. Passing completions and attempts
# come from CFBD's "C/ATT" string and are split in `build_player_game()`.
player_game_stat_map <- tibble::tribble(
  ~category   , ~statType , ~column        ,
  "passing"   , "YDS"     , "pass_yds"     ,
  "passing"   , "TD"      , "pass_td"      ,
  "passing"   , "INT"     , "pass_int"     ,
  "rushing"   , "CAR"     , "rush_car"     ,
  "rushing"   , "YDS"     , "rush_yds"     ,
  "rushing"   , "TD"      , "rush_td"      ,
  "receiving" , "REC"     , "rec"          ,
  "receiving" , "YDS"     , "rec_yds"      ,
  "receiving" , "TD"      , "rec_td"       ,
  "defensive" , "TOT"     , "tackles"      ,
  "defensive" , "SOLO"    , "solo_tackles" ,
  "defensive" , "TFL"     , "tfl"          ,
  "defensive" , "SACKS"   , "sacks"
)

#' Build the player x game table
#'
#' One row per `(playerId, gameId)` that has at least one stat line in
#' `game_player_stats`, whatever the category. The player's team, opponent,
#' side, neutral-site flag, points and pregame Elo come from `games`; the
#' wide columns are the per-game box-score counts from
#' `player_game_stat_map`. `team_games` is the team's games played in that
#' season from [team_record()], so `games appeared / team_games` is a
#' per-team-season participation rate.
#'
#' A stat column is `NA` when the player had no line in that category in that
#' game (CFBD lists a category only when the player recorded something in it).
#' A recorded zero stays `0`. Rows are never dropped for lacking a usage stat:
#' a kicker or punter who only logged special-teams lines still gets a row.
#'
#' @param game_player_stats Cleaned long player-game stats
#'   ([clean_game_player_stats()]).
#' @param games Cleaned games ([clean_games()]); every `gameId` must be in
#'   `games$id`.
#'
#' @return One row per `(playerId, gameId)`: identifiers and period
#'   (`season`, `week`, `seasonType`), `team`, `team_conference`, `opponent`,
#'   `opponent_conference`, `home_away`, `neutral_site`, `team_points`,
#'   `opponent_points`, `team_pregame_elo`, `opponent_pregame_elo` (NA for
#'   games without a CFBD Elo, mostly FCS and lower-division opponents),
#'   `team_games`, then the stat columns in `player_game_stat_map` plus
#'   `pass_cmp` and `pass_att`.
#' @export
build_player_game <- function(game_player_stats, games) {
  meta <- game_player_stats |>
    dplyr::distinct(
      .data$playerId,
      .data$gameId,
      .keep_all = TRUE
    ) |>
    dplyr::select(
      "playerId",
      "gameId",
      "season",
      "week",
      "seasonType",
      "team",
      "homeAway"
    )

  side <- games |>
    dplyr::transmute(
      gameId = .data$id,
      homeTeam = .data$homeTeam,
      awayTeam = .data$awayTeam,
      homeConference = .data$homeConference,
      awayConference = .data$awayConference,
      homePoints = as.integer(.data$homePoints),
      awayPoints = as.integer(.data$awayPoints),
      homePregameElo = .data$homePregameElo,
      awayPregameElo = .data$awayPregameElo,
      neutral_site = .data$neutralSite
    )

  out <- meta |>
    dplyr::left_join(side, by = "gameId") |>
    dplyr::mutate(
      home_away = .data$homeAway,
      is_home = .data$home_away == "home",
      team_conference = dplyr::if_else(
        .data$is_home,
        .data$homeConference,
        .data$awayConference
      ),
      opponent = dplyr::if_else(
        .data$is_home,
        .data$awayTeam,
        .data$homeTeam
      ),
      opponent_conference = dplyr::if_else(
        .data$is_home,
        .data$awayConference,
        .data$homeConference
      ),
      team_points = dplyr::if_else(
        .data$is_home,
        .data$homePoints,
        .data$awayPoints
      ),
      opponent_points = dplyr::if_else(
        .data$is_home,
        .data$awayPoints,
        .data$homePoints
      ),
      team_pregame_elo = dplyr::if_else(
        .data$is_home,
        .data$homePregameElo,
        .data$awayPregameElo
      ),
      opponent_pregame_elo = dplyr::if_else(
        .data$is_home,
        .data$awayPregameElo,
        .data$homePregameElo
      )
    ) |>
    dplyr::select(
      -dplyr::all_of(c(
        "homeAway",
        "is_home",
        "homeTeam",
        "awayTeam",
        "homeConference",
        "awayConference",
        "homePoints",
        "awayPoints",
        "homePregameElo",
        "awayPregameElo"
      ))
    )

  # Team games played per team-season (all divisions, postseason included),
  # the denominator for games appeared.
  team_games <- team_record(games) |>
    dplyr::select(
      "season",
      "team",
      team_games = "games_played"
    )
  out <- out |>
    dplyr::left_join(team_games, by = c("season", "team"))

  # Wide per-game usage stats: one column per (category, statType) pair.
  stat_long <- game_player_stats |>
    dplyr::inner_join(
      player_game_stat_map,
      by = c("category", "statType")
    ) |>
    dplyr::transmute(
      .data$playerId,
      .data$gameId,
      .data$column,
      value = suppressWarnings(as.numeric(.data$stat))
    ) |>
    dplyr::distinct(
      .data$playerId,
      .data$gameId,
      .data$column,
      .keep_all = TRUE
    ) |>
    tidyr::pivot_wider(
      id_cols = c("playerId", "gameId"),
      names_from = "column",
      values_from = "value"
    )

  # "C/ATT" holds completions and attempts in one string, e.g. "14/29".
  cmp_att <- game_player_stats |>
    dplyr::filter(.data$category == "passing", .data$statType == "C/ATT") |>
    dplyr::distinct(.data$playerId, .data$gameId, .keep_all = TRUE) |>
    dplyr::transmute(
      .data$playerId,
      .data$gameId,
      pass_cmp = suppressWarnings(as.numeric(sub("/.*$", "", .data$stat))),
      pass_att = suppressWarnings(as.numeric(sub("^.*/", "", .data$stat)))
    )

  out <- out |>
    dplyr::left_join(stat_long, by = c("playerId", "gameId")) |>
    dplyr::left_join(cmp_att, by = c("playerId", "gameId"))

  # A category absent from the input entirely still gets its column (all NA)
  # so the schema is stable across refreshes and fixtures.
  stat_cols <- c(
    "pass_cmp",
    "pass_att",
    player_game_stat_map$column
  )
  for (col in setdiff(stat_cols, names(out))) {
    out[[col]] <- NA_real_
  }

  out |>
    dplyr::mutate(
      playerId = as.character(.data$playerId),
      gameId = as.integer(.data$gameId),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      team_games = as.integer(.data$team_games),
      dplyr::across(dplyr::all_of(stat_cols), as.numeric)
    ) |>
    dplyr::select(
      "playerId",
      "gameId",
      "season",
      "week",
      "seasonType",
      "team",
      "team_conference",
      "opponent",
      "opponent_conference",
      "home_away",
      "neutral_site",
      "team_points",
      "opponent_points",
      "team_pregame_elo",
      "opponent_pregame_elo",
      "team_games",
      dplyr::all_of(stat_cols)
    ) |>
    dplyr::arrange(.data$season, .data$gameId, .data$playerId)
}
