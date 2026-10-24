# AD HOC exploration script (not part of the pipeline; safe to delete).
#
# Pulls every play/drive/player layer the CFBD API exposes for one game
# (Auburn vs Georgia, week 7) and writes each layer to a sheet of an Excel
# workbook, plus a data-dictionary sheet, so a partner can browse what
# information is available at game granularity.
#
# Usage: Rscript inst/scripts/auburn-uga-week7-explorer.R
# Requires CFBDAPI key in the environment (CFBD_API_KEY) and network access.

library(dplyr)
library(purrr)
library(tidyr)
library(tibble)

source(here::here("R", "ingest.R")) # cfbd_get() / cfbd_request()

SEASON <- 2026L
WEEK <- 7L
TEAMS <- c("Auburn", "Georgia")
OUT <- here::here("inst", "scripts", "auburn-uga-week7-layers.xlsx")

# ---------------------------------------------------------------- helpers ---

# Recursively flatten one nested list (an API row) into named scalars/list-cols
# with dotted names, e.g. offense.passingPlays.ppa.
flatten_row <- function(x, prefix = "") {
  if (is.null(x)) {
    return(set_names(list(NA), prefix))
  }
  if (!is.list(x)) {
    return(set_names(list(x), prefix))
  }
  # Unnamed arrays (e.g. line scores) get positional names
  if (is.null(names(x))) {
    x <- set_names(x, as.character(seq_along(x)))
  } else {
    names(x) <- ifelse(
      is.na(names(x)) | names(x) == "",
      as.character(seq_along(x)),
      names(x)
    )
  }
  # The recursion already applies the prefix, so splice the flattened pieces
  # back together keeping only their (inner) names.
  out <- list_flatten(
    imap(x, \(v, n) {
      nm <- if (nzchar(prefix)) paste(prefix, n, sep = ".") else n
      flatten_row(v, nm)
    }),
    name_spec = "{inner}"
  )
  if (length(out) == 0) set_names(list(NA), prefix) else out
}

rows_to_tibble <- function(lst) {
  if (is.null(lst) || length(lst) == 0) {
    return(tibble())
  }
  map_dfr(lst, ~ as_tibble_row(flatten_row(.x)))
}

# writexl cannot take list columns; stringify them for display.
stringify_lists <- function(df) {
  df |> modify_if(is.list, ~ map_chr(.x, \(v) paste(v, collapse = "; ")))
}

# ------------------------------------------------------------ find the game ---

cat("Locating the Auburn vs Georgia week", WEEK, "game in", SEASON, "...\n")
games <- cfbd_get(
  "/games",
  list(year = SEASON, week = WEEK, seasonType = "regular")
)
game <- games |>
  filter((homeTeam %in% TEAMS) & (awayTeam %in% TEAMS))
if (nrow(game) == 0) {
  stop("Game not found for ", SEASON, " week ", WEEK)
}
game_id <- game$id
cat("Found game id", game_id, ":", game$awayTeam, "@", game$homeTeam, "\n")

# ------------------------------------------------------------- pull layers ---

cat("Pulling layers (each is one or two API calls)...\n")

# Raw JSON list response; used where cfbd_get()'s simplification chokes on
# the heterogeneously nested /game/box/advanced response.
cfbd_raw <- function(endpoint, query = list()) {
  cfbd_request(endpoint, query) |>
    httr2::req_perform() |>
    httr2::resp_body_json(simplifyVector = FALSE)
}

drives_raw <- cfbd_raw(
  "/drives",
  list(year = SEASON, week = WEEK, seasonType = "regular")
)
drives <- rows_to_tibble(drives_raw) |>
  filter(gameId == game_id) |>
  arrange(as.integer(driveNumber))

# /plays and the enriched play endpoints require year+week (not gameId alone);
# filter down to the game afterwards.
plays_raw <- cfbd_raw(
  "/plays",
  list(year = SEASON, week = WEEK, seasonType = "regular")
)
plays <- rows_to_tibble(plays_raw) |>
  filter(gameId == game_id) |>
  arrange(as.integer(playNumber))

play_stats_raw <- tryCatch(
  cfbd_raw("/plays/stats", list(gameId = game_id)),
  error = \(e) {
    message("play_stats pull failed: ", conditionMessage(e))
    list()
  }
)
play_stats <- rows_to_tibble(play_stats_raw)

passing_plays_raw <- cfbd_raw(
  "/passing/plays",
  list(year = SEASON, week = WEEK, seasonType = "regular")
)
rushing_plays_raw <- cfbd_raw(
  "/rushing/plays",
  list(year = SEASON, week = WEEK, seasonType = "regular")
)
punting_plays_raw <- cfbd_raw(
  "/punting/plays",
  list(year = SEASON, gameId = game_id)
)
keep_game <- function(rows, key = "gameId", id = game_id) {
  keep(rows, \(r) identical(as.character(r[[key]]), as.character(id)))
}
passing_plays <- rows_to_tibble(keep_game(passing_plays_raw))
rushing_plays <- rows_to_tibble(keep_game(rushing_plays_raw))
punting_plays <- rows_to_tibble(punting_plays_raw)

team_game_stats <- cfbd_raw("/games/teams", list(id = game_id)) |>
  map_dfr(\(game) {
    map_dfr(game$teams, \(tm) {
      map_dfr(tm$stats, \(s) tibble(category = s$category, stat = s$stat)) |>
        mutate(
          teamId = tm$teamId,
          team = tm$team,
          conference = tm$conference,
          homeAway = tm$homeAway,
          points = tm$points,
          .before = 1
        )
    })
  })

player_game_stats <- cfbd_raw("/games/players", list(id = game_id)) |>
  map_dfr(\(game) {
    map_dfr(game$teams, \(tm) {
      map_dfr(tm$categories, \(cat) {
        map_dfr(cat$types, \(typ) {
          map_dfr(typ$athletes, \(a) {
            tibble(
              team = tm$team,
              conference = tm$conference,
              homeAway = tm$homeAway,
              category = cat$name,
              statType = typ$name,
              athleteId = a$id,
              athleteName = a$name,
              stat = a$stat
            )
          })
        })
      })
    })
  })

advanced_box_raw <- cfbd_raw("/game/box/advanced", list(id = game_id))
advanced_box <- list(
  gameInfo = rows_to_tibble(list(advanced_box_raw$gameInfo)),
  team_metrics = imap_dfr(advanced_box_raw$teams, \(rows, section) {
    rows_to_tibble(rows) |>
      mutate(metric = section, .before = 1)
  }),
  player_metrics = imap_dfr(advanced_box_raw$players, \(rows, section) {
    rows_to_tibble(rows) |>
      mutate(metric = section, .before = 1)
  })
)

game_info <- games |>
  filter(id == game_id) |>
  stringify_lists()

sheets <- list(
  game_info = game_info,
  drives = stringify_lists(drives),
  plays = stringify_lists(plays),
  play_stats = stringify_lists(play_stats),
  passing_plays = stringify_lists(passing_plays),
  rushing_plays = stringify_lists(rushing_plays),
  punting_plays = stringify_lists(rows_to_tibble(as.list(transpose(
    punting_plays
  )))),
  team_game_stats = team_game_stats,
  player_game_stats = player_game_stats,
  advanced_box_game = advanced_box$gameInfo,
  advanced_box_teams = stringify_lists(advanced_box$team_metrics),
  advanced_box_players = stringify_lists(advanced_box$player_metrics)
)

# ------------------------------------------------------- data dictionary ---

# Plain-language descriptions keyed on the final component of a dotted name.
term_glossary <- c(
  "id" = "CFBD unique identifier",
  "gameId" = "CFBD game id (links every layer for this game)",
  "playId" = "CFBD play id within the game",
  "driveId" = "CFBD drive id (links plays to drives)",
  "driveNumber" = "Drive sequence number within the game",
  "playNumber" = "Play sequence number within the game",
  "season" = "Season year",
  "seasonType" = "regular / postseason (etc.)",
  "week" = "Week within the season",
  "date" = "Date or kickoff timestamp",
  "startDate" = "Kickoff timestamp",
  "startTimeTBD" = "Kickoff time not yet set",
  "completed" = "Game has finished",
  "neutralSite" = "Played at a neutral venue",
  "conferenceGame" = "Conference matchup",
  "venue" = "Stadium name",
  "venueId" = "CFBD venue id",
  "attendance" = "Announced attendance",
  "excitementIndex" = "CFBD excitement rating for the game",
  "homeTeam" = "Home team school name",
  "awayTeam" = "Away team school name",
  "homeConference" = "Home team conference",
  "awayConference" = "Away team conference",
  "homePoints" = "Home team final points",
  "awayPoints" = "Away team final points",
  "homeLineScores" = "Home points by quarter",
  "awayLineScores" = "Away points by quarter",
  "homeId" = "CFBD team id, home team",
  "awayId" = "CFBD team id, away team",
  "homeWinProbability" = "Model win probability, home side",
  "homePregameElo" = "Elo rating before the game (home)",
  "homePostgameElo" = "Elo rating after the game (home)",
  "spread" = "Betting spread (home-relative)",
  "overUnder" = "Betting over/under",
  "offense" = "Offensive (possessing) team name",
  "defense" = "Defending team name",
  "offenseId" = "CFBD team id, offense",
  "defenseId" = "CFBD team id, defense",
  "offenseConference" = "Offense conference",
  "defenseConference" = "Defense conference",
  "offenseScore" = "Offense score at the time of the play",
  "defenseScore" = "Defense score at the time of the play",
  "period" = "Quarter (1-4, 5 = OT)",
  "clock" = "Game clock at the play/drive boundary",
  "minutes" = "Clock minutes",
  "seconds" = "Clock seconds",
  "down" = "Down number",
  "distance" = "Yards to go for a first down",
  "yardline" = "Field position (CFBD convention)",
  "startYardline" = "Yardline where the play/drive started",
  "endYardline" = "Yardline where the play/drive ended",
  "startYardsToGoal" = "Yards from offense's spot to the goal line at start",
  "endYardsToGoal" = "Yards from offense's spot to the goal line at end",
  "yardsToGoal" = "Yards from the line of scrimmage to the goal line",
  "yardsGained" = "Yards gained on the play",
  "scoring" = "Drive/play produced points",
  "playType" = "Play classification (pass, rush, punt, penalty, ...)",
  "playText" = "Human-readable play description",
  "ppa" = "Predicted points added (EPA-style value of the play)",
  "success" = "Successful play (standard success-rate definition)",
  "drives" = "Number of drives",
  "plays" = "Number of plays",
  "passingPlays" = "Metrics restricted to passing plays",
  "rushingPlays" = "Metrics restricted to rushing plays",
  "passingDowns" = "Metrics on passing downs (2nd/3rd & long, etc.)",
  "standardDowns" = "Metrics on standard downs",
  "explosiveness" = "Average PPA on successful plays",
  "successRate" = "Share of plays counted successful",
  "totalPPA" = "Sum of PPA over the plays",
  "ppa" = "Average PPA over the plays",
  "rate" = "Share of total plays in this bucket",
  "havoc" = "Havoc rate (TFLs + turnovers + passes defended per play)",
  "db" = "Defensive-back component of havoc",
  "frontSeven" = "Front-seven component of havoc",
  "total" = "Total value",
  "fieldPosition" = "Average starting field position metrics",
  "averageStart" = "Average starting yardline",
  "averagePredictedPoints" = "Average predicted points at the average start",
  "pointsPerOpportunity" = "Points scored per scoring opportunity",
  "totalOpportunies" = "Number of scoring opportunities",
  "openFieldYards" = "Average yards gained beyond 15 yards downfield",
  "secondLevelYards" = "Average yards gained 5-10 yards downfield",
  "lineYards" = "Average yards attributable to the offensive line (0-4 yds)",
  "stuffRate" = "Share of rushes stuffed at or behind the line",
  "powerSuccess" = "Success rate on 3rd/4th & 2 or fewer",
  "cumulativePpa" = "Running PPA totals by quarter",
  "quarter1" = "First-quarter value",
  "quarter2" = "Second-quarter value",
  "quarter3" = "Third-quarter value",
  "quarter4" = "Fourth-quarter value",
  "attempts" = "Attempts",
  "completions" = "Completions",
  "incompletions" = "Incompletions",
  "interceptions" = "Interceptions thrown",
  "completionRate" = "Completions / attempts",
  "airYards" = "Yards the ball traveled through the air",
  "passDepth" = "short or deep (20+ yards)",
  "passDirection" = "left, middle, or right",
  "passLocation" = "Combined depth x direction bucket",
  "totalYards" = "Total yards (air + YAC)",
  "yardsAfterCatch" = "Yards after the catch",
  "averageDepthOfTarget" = "Average air yards per attempt",
  "cpoe" = "Completion percentage over expected (percentage points)",
  "completionProbability" = "Model probability the pass is completed",
  "isSpike" = "QB spike",
  "isThrowaway" = "Deliberate throwaway",
  "isIntentionalGrounding" = "Intentional grounding",
  "locationAnalysisEligible" = "Play eligible for location analysis",
  "rusherId" = "Athlete id of the ball carrier",
  "rusher" = "Ball carrier name",
  "rushDirection" = "left, middle, or right",
  "rushingYards" = "Team rushing yards on the play",
  "rusherYards" = "Yards credited to the individual rusher",
  "isRushingTouchdown" = "Rushing touchdown",
  "isSack" = "Sack (loss behind the line on a pass play)",
  "isKneel" = "QB kneel-down",
  "isTeamRush" = "Rush not attributed to an individual",
  "attributionStatus" = "How the rusher was attributed (individual, team, ...)",
  "directionAnalysisEligible" = "Eligible for direction analysis",
  "parseStatus" = "How completely the play was parsed",
  "punterId" = "Punter athlete id",
  "punter" = "Punter name",
  "returnerId" = "Returner athlete id",
  "returner" = "Returner name",
  "puntYards" = "Gross punt yards",
  "returnYards" = "Return yards",
  "netPuntYards" = "Net punt yards (gross - returns - touchback penalty)",
  "isTouchback" = "Punt went for a touchback",
  "isFairCatch" = "Fair catch",
  "isDowned" = "Punt downed in place",
  "isBlocked" = "Punt blocked",
  "isMuffed" = "Return muffed",
  "countsAsPunt" = "Counts as a punt play",
  "countsAsReturn" = "Counts as a punt return",
  "athleteId" = "CFBD athlete id (shared player namespace)",
  "athleteName" = "Player name",
  "playerId" = "CFBD athlete id (shared player namespace)",
  "player" = "Player name",
  "passerId" = "Passer athlete id",
  "passer" = "Passer name",
  "targetId" = "Intended receiver athlete id",
  "target" = "Intended receiver name",
  "outcome" = "completion / incompletion / interception",
  "statType" = "Stat name within the category (e.g. YDS, TD)",
  "stat" = "Stat value",
  "category" = "Statistical category (e.g. passing, receiving, defensive)",
  "teamId" = "CFBD numeric team id",
  "team" = "Team school name",
  "conference" = "Team conference",
  "opponent" = "Opponent school name",
  "homeAway" = "home or away",
  "points" = "Points scored",
  "metric" = "Which advanced-box metric block this row belongs to",
  "gameInfo" = "Game-level context from the advanced box score",
  "teamId" = "CFBD numeric team id",
  "wallclock" = "Timestamp of the play in real time",
  "offenseTimeouts" = "Offense timeouts remaining",
  "defenseTimeouts" = "Defense timeouts remaining",
  "scoringOpportunity" = "Drive reached the opponent's 40 or red zone",
  "driveResult" = "How the drive ended (TD, FG, Punt, Downs, ...)",
  "yards" = "Total yards",
  "startPeriod" = "Quarter the drive started in",
  "endPeriod" = "Quarter the drive ended in",
  "startClock" = "Clock at drive start",
  "endClock" = "Clock at drive end",
  "duration" = "Drive elapsed time",
  "pointsGained" = "Points scored on the drive",
  "isHomeOffense" = "Home team had the ball",
  "startOffenseScore" = "Score when the drive started",
  "endOffenseScore" = "Score when the drive ended",
  "airYardsAttemptsAvailable" = "Attempts with known air yards",
  "totalAirYards" = "Sum of air yards",
  "totalYardsAttemptsAvailable" = "Attempts with known total yards",
  "yardsAfterCatchAttemptsAvailable" = "Completions with computable YAC",
  "ppaAttemptsAvailable" = "Attempts with known PPA",
  "successAttemptsAvailable" = "Attempts with known success flag",
  "successfulAttempts" = "Attempts flagged successful",
  "cpoeAttemptsAvailable" = "Attempts with a completion probability",
  "cpoeCompletions" = "Completions among attempts with a probability",
  "expectedCompletions" = "Sum of completion probabilities",
  "expectedCompletionRate" = "Expected completions / attempts",
  "locationEligibleAttempts" = "Attempts eligible for location analysis",
  "locationAvailableAttempts" = "Attempts with recognized depth + direction",
  "locations" = "Per-location production buckets (7)",
  "individualAttempts" = "Carries attributed to an individual",
  "unattributedAttempts" = "Carries not attributed to an individual",
  "multiCarrierAttempts" = "Carries credited to multiple players",
  "teamRushes" = "Team-only rushes (no individual credited)",
  "sacks" = "Sacks",
  "kneels" = "Kneel-downs",
  "rushingYardsAvailable" = "Carries with known rushing yards",
  "yardsPerCarry" = "Rushing yards per carry",
  "directionEligibleAttempts" = "Carries eligible for direction analysis",
  "directionAvailableAttempts" = "Carries with a recognized direction",
  "directions" = "Per-direction production (left/middle/right/unknown)",
  "touchdownStatusAvailable" = "Carries with known touchdown status",
  "rushingTouchdowns" = "Rushing touchdowns",
  "punts" = "Number of punts",
  "puntYardsAvailable" = "Punts with known gross yards",
  "yardsPerPunt" = "Average gross punt yards",
  "longestPunt" = "Longest punt",
  "punts50Plus" = "Punts of 50+ yards",
  "netPuntYardsAvailable" = "Punts with known net yards",
  "netYardsPerPunt" = "Average net punt yards",
  "touchbacks" = "Touchbacks",
  "fairCatches" = "Fair catches forced",
  "outOfBounds" = "Punts out of bounds",
  "downed" = "Punts downed",
  "inside20" = "Punts downed inside the 20",
  "blocked" = "Punts blocked",
  "returns" = "Punt returns",
  "returnYardsAvailable" = "Returns with known yards",
  "yardsPerReturn" = "Yards per return",
  "longestReturn" = "Longest return",
  "returns20Plus" = "Returns of 20+ yards",
  "returnTouchdowns" = "Return touchdowns",
  "muffs" = "Muffed punts",
  "receivingTeamTurnovers" = "Turnovers on punts",
  "averagePPA" = "Average PPA",
  "totalPPA" = "Total PPA",
  "usage" = "Share of plays the player was involved in",
  "games" = "Games played",
  "excitement" = "Excitement index",
  "homeWinner" = "Home team won",
  "homeWinProb" = "Home win probability",
  "awayWinProb" = "Away win probability",
  "lineScores" = "Points by quarter"
)

describe_column <- function(col) {
  leaf <- sub(".*\\.", "", col)
  base <- gsub("^X\\d+$", "Unnamed positional column", leaf)
  if (base %in% names(term_glossary)) {
    return(term_glossary[[base]])
  }
  # Nested name: explain the leaf against its parent path
  parts <- strsplit(col, ".", fixed = TRUE)[[1]]
  if (length(parts) > 1) {
    paste0(
      "Nested field; '",
      leaf,
      "' as defined above, scoped to the '",
      paste(parts[-length(parts)], collapse = "."),
      "' context."
    )
  } else {
    "Field from the CFBD API response (see inst/cfbd-api-coverage.md)"
  }
}

dictionary <- imap_dfr(sheets, \(df, sheet) {
  first_row <- if (nrow(df) > 0) df[1, ] else df
  tibble(
    sheet = sheet,
    column = names(df),
    description = map_chr(names(df), describe_column),
    example = vapply(
      names(df),
      \(n) {
        v <- first_row[[n]][1]
        if (length(v) == 0 || is.na(v)) "" else substr(as.character(v), 1, 60)
      },
      character(1)
    )
  )
})

overview <- tibble(
  item = c(
    "Game",
    "Game id",
    "Season / week",
    "Layers pulled",
    "API docs snapshot",
    "Script"
  ),
  value = c(
    paste(game$awayTeam, "@", game$homeTeam),
    as.character(game_id),
    paste(SEASON, "week", WEEK),
    paste(names(sheets), collapse = ", "),
    "inst/cfbd-api-coverage.md (OpenAPI 5.33.0)",
    "inst/scripts/auburn-uga-week7-explorer.R"
  )
)

dictionary <- bind_rows(
  tibble(
    sheet = "README",
    column = overview$item,
    description = overview$value,
    example = ""
  ),
  dictionary
)

# ------------------------------------------------------------- write book ---

sheets$dictionary <- dictionary
writexl::write_xlsx(sheets, OUT)
cat("Wrote", OUT, "\n")
for (nm in names(sheets)) {
  cat(sprintf(
    "  %-22s %5d rows x %3d cols\n",
    nm,
    nrow(sheets[[nm]]),
    ncol(sheets[[nm]])
  ))
}
