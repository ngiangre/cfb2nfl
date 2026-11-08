# Fixture: two FBS teams (1, 2) and one FCS team (3) across two seasons, plus
# an unplayed game and a D-II game that the export must ignore.
explorer_games_fixture <- function() {
  tibble::tibble(
    id = 1:6,
    season = c(2025L, 2025L, 2025L, 2026L, 2026L, 2026L),
    startDate = c(
      "2025-09-01T19:00:00Z",
      "2025-09-08T19:00:00Z",
      "2025-09-15T19:00:00Z",
      "2026-09-05T19:00:00Z",
      "2026-09-12T19:00:00Z",
      "2026-09-19T19:00:00Z"
    ),
    completed = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    homeId = c(1L, 2L, 1L, 2L, 4L, 1L),
    awayId = c(2L, 3L, 3L, 1L, 5L, 2L),
    homeConference = c("SEC", "SEC", "SEC", "SEC", "GLIAC", "SEC"),
    awayConference = c("SEC", "SWAC", "SWAC", "SEC", "GLIAC", "SEC"),
    homeClassification = c("fbs", "fbs", "fbs", "fbs", "ii", "fbs"),
    awayClassification = c("fbs", "fcs", "fcs", "fbs", "ii", "fbs"),
    homePoints = c(30L, 41L, 20L, 17L, 10L, NA),
    awayPoints = c(27L, 3L, 20L, 24L, 7L, NA),
    homePostgameElo = c(1610, 1580, 1600, 1560, NA, NA),
    awayPostgameElo = c(1590, NA, NA, 1640, NA, NA),
    week = c(1L, 2L, 3L, 1L, 2L, 3L),
    seasonType = "regular",
    neutralSite = c(FALSE, FALSE, TRUE, FALSE, FALSE, FALSE),
    homeTeam = c(
      "Texas",
      "Alabama",
      "Texas",
      "Alabama",
      "Ferris State",
      "Texas"
    ),
    awayTeam = c(
      "Alabama",
      "Grambling",
      "Grambling",
      "Texas",
      "Grand Valley State",
      "Alabama"
    ),
    homePregameElo = c(1600, 1570, 1610, 1570, NA, NA),
    awayPregameElo = c(1600, NA, NA, 1630, NA, NA),
    homePostgameWinProbability = c(0.7, 0.99, 0.5, 0.3, NA, NA),
    awayPostgameWinProbability = c(0.3, 0.01, 0.5, 0.7, NA, NA)
  )
}

explorer_tiers_fixture <- function() {
  tibble::tibble(
    season = c(2025L, 2025L, 2026L, 2026L),
    conference = c("SEC", "SWAC", "SEC", "SWAC"),
    tier = c(3L, 1L, 3L, 1L),
    tier_label = c("Power", "FCS and below", "Power", "FCS and below")
  )
}

explorer_teams_fixture <- function() {
  tibble::tibble(
    team_id = c(1L, 2L, 3L, 4L, 99L),
    team = c("Texas", "Alabama", "Grambling", "Ferris State", "Unused"),
    mascot = c("Longhorns", "Crimson Tide", "Tigers", "Bulldogs", "X"),
    abbreviation = c("TEX", "ALA", "GRAM", "FSU", "X"),
    classification = c("fbs", "fbs", "fcs", "ii", NA),
    color = c("#bf5700", "#9e1b32", "#null", "#cc0000", "#000000"),
    alt_color = c("#ffffff", "#null", "#000000", "#000000", "#000000"),
    logo_light = c("t.png", "a.png", "g.png", "f.png", NA),
    logo_dark = c("td.png", "ad.png", "gd.png", "fd.png", NA)
  )
}

explorer_shell_fixture <- function() {
  g <- explorer_games_fixture()
  ts <- build_explorer_team_season(g, explorer_tiers_fixture())
  teams <- build_explorer_teams(explorer_teams_fixture(), ts)
  meta <- build_explorer_meta(g)
  # The real default (Texas, 251) is not in this fixture; point the page's
  # fallback at a team the fixture does have.
  meta$default_team <- min(teams$team_id)
  list(games = g, team_season = ts, teams = teams, meta = meta)
}

# Game 1: Texas (home, id 1) vs Alabama (id 2), with an OT play; game 4:
# Alabama home. Scores are each play's offense/defense score.
explorer_plays_fixture <- function() {
  tibble::tibble(
    id = c("11", "12", "13", "14", "15", "41"),
    gameId = c(1L, 1L, 1L, 1L, 1L, 4L),
    season = c(2025L, 2025L, 2025L, 2025L, 2025L, 2026L),
    driveNumber = c(1L, 1L, 2L, 3L, 4L, 1L),
    playNumber = c(1L, 2L, 1L, 1L, 1L, 1L),
    period = c(1L, 1L, 2L, 4L, 5L, 1L),
    clock_minutes = c(15L, 10L, 7L, 0L, 15L, 14L),
    clock_seconds = c(0L, 30L, 30L, 5L, 0L, 0L),
    offense = c("Texas", "Texas", "Alabama", "Texas", "Alabama", "Alabama"),
    defense = c("Alabama", "Alabama", "Texas", "Alabama", "Texas", "Texas"),
    offenseScore = c(0L, 7L, 0L, 27L, 24L, 0L),
    defenseScore = c(0L, 0L, 7L, 24L, 27L, 0L),
    down = c(1L, 2L, 1L, 3L, 1L, 1L),
    distance = c(10L, 5L, 10L, 2L, 10L, 10L),
    yardsToGoal = c(75L, 40L, 80L, 30L, 25L, 75L),
    playType = c(
      "Rush",
      "Passing Touchdown",
      "Pass Interception Return",
      "Field Goal Good",
      "Rush",
      "Rush"
    ),
    playText = c("a", "b", "c", "d", "e", "f"),
    ppa = c(0.5, 2.0, -1.5, NA, 0.25, 0.1),
    scoring = c(FALSE, TRUE, FALSE, TRUE, FALSE, FALSE)
  )
}

explorer_play_stats_fixture <- function() {
  tibble::tibble(
    playId = c("12", "12"),
    athleteId = c("p1", "p2"),
    athleteName = c("Passer One", "Receiver Two"),
    statType = c("Completion", "Reception")
  )
}
