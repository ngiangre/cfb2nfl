# Self-contained QueryChat module: all querychat data processing (dictionary
# context, greeting, QueryChat construction, table registration) lives here so
# app.R stays declarative and the chat page sits in a navbar panel.

# Build the QueryChat R6 object: dictionaries from inst/dict as LLM context,
# plus join-namespace rules. Called inside the module server so it runs once
# per app session, not at global scope.
querychat_setup <- function(con, tables) {
  dict_files <- list.files(
    app_sys("dict"),
    "\\.yml$",
    full.names = TRUE
  )
  data_description <- paste(
    c(
      "CFB stats: what shapes a college football player's path to the NFL draft.",
      "Player key: player_stats.playerId, roster.playerId, picks.playerId are one namespace (never join players on name).",
      "Team key: player_stats.team = roster.team = coaches.school = teams.team (teams is display-only metadata).",
      "Coach context: join (team, season) to coaches (school, season); a school can have >1 head coach in a season.",
      "Conference tiers are season-aware: join (conference, season) to conference_tiers.",
      "NFL side: use nfl_pick_link (name-guarded draft-slot bridge) to get gsis_id; then join (gsis_id, season) to nfl_rosters/nfl_player_stats. NEVER join picks.nflAthleteId to nflverse.",
      "recruiting.athleteId is an untrusted namespace: never join it to playerId; recruiting links are name-guarded in the pipeline only.",
      "player_stats is LONG (one row per player-season-category-statType-stat); aggregate to player-season grain before joining, or use the wide player_season_stats.",
      "ps_change carries the drafted label; player_season_inputs is the leakage-safe view (label columns dropped).",
      "Join keys:",
      "player_stats/roster/player_season_stats/ps_change/roster_flags/career_summary on (playerId [, season]);",
      "picks on playerId (draft year in `year`);",
      "picks <-> nfl_pick_link on draft slot (year, round, overall) = (season, round, pick);",
      "nfl_pick_link/nfl_draft_picks on (season, round, pick);",
      "nfl_rosters/nfl_player_stats on (gsis_id, season);",
      "stat_taxonomy on (category, statType).",
      "Data dictionaries follow."
    ),
    vapply(
      dict_files,
      function(f) {
        paste0(
          "## ",
          basename(f),
          "\n\n",
          paste(readLines(f), collapse = "\n"),
          collapse = "\n\n"
        )
      },
      character(1)
    ),
    collapse = "\n\n"
  )

  greeting <- sprintf(
    "Welcome to **cfbstats** — exploring what shapes a college football player's
path to the NFL draft. This DuckDB bundle has **%d tables**: college stat lines
(`player_season_stats` is the wide, player-season base table), rosters,
coaches, recruiting, draft picks, and NFL outcomes via `nfl_pick_link`.

Tables join on shared keys — `playerId` across college tables, `gsis_id` on the
NFL side — so feel free to ask questions that span them.

##### Explore the data
<ul>
<li><span class=\"suggestion\">What tables are in the database and what does each cover?</span></li>
<li><span class=\"suggestion\">How many players, teams, and seasons does player_season_stats cover?</span></li>
</ul>

##### Analyze performance
<ul>
<li><span class=\"suggestion\">Who were the top 10 passing leaders by season yardage?</span></li>
<li><span class=\"suggestion\">What was the drafted rate of players by conference tier, joining player_season_stats to conference_tiers and picks?</span></li>
</ul>
",
    length(tables)
  )

  qc <- querychat::QueryChat$new(
    con,
    tables[1],
    data_description = data_description,
    greeting = greeting,
    client = ellmer::chat_posit(model = "zai-org/GLM-5.3-Flash")
  )
  qc$add_tables(con, tables[-1])
  qc
}

mod_querychat_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::uiOutput(ns("qc_ui"))
  )
}

mod_querychat_server <- function(id, con, tables) {
  shiny::moduleServer(id, function(input, output, session) {
    qc <- querychat_setup(con, tables)
    # querychat >= 0.4: id is keyword-only ($server's first positional arg is
    # data_source), and a NULL data_source uses the tables registered at setup.
    chat_id <- session$ns("chat")
    output$qc_ui <- shiny::renderUI(qc$ui(id = chat_id))
    qc$server(id = chat_id)
  })
}
