# cfb2nfl pipeline (decision 0004). Single source of truth for the processing
# graph, lineage/audit (decision 0005), and the rendered process map.
#
# Stages: ingest -> clean -> link -> features -> model -> report.
#
# Ingest targets read the committed raw parquet in data/ so the pipeline runs
# offline. A fresh CFBD pull (the scheduled refresh job) instead calls the
# ingest_*() functions in R/ingest.R.

library(targets)

tar_option_set(
  packages = c("dplyr", "arrow", "tibble", "tidyr", "purrr", "pointblank"),
  format = "rds"
)

# Load all package functions (R/).
targets::tar_source()

list(
  # ---- ingest (decisions 0017-0018, 0034) -----------------------------------
  # Refresh mode (CFB2NFL_REFRESH=true) pulls each source from CFBD/nflverse in
  # memory; track mode (default, no key) leaves them NULL because the cleaned
  # parquet below is read directly. Season-keyed CFBD sources pull only the
  # seasons CFB2NFL_REFRESH_SEASONS selects (unset = the full window; decision
  # 0034) and the *_file targets splice them into the published table.
  # Whole-table sources (/draft/picks, /coaches, /teams: one call each) and the
  # nflverse tables (no CFBD calls) are always pulled in full. Targets are NOT
  # cued "always": a re-refresh is explicit, via data-raw/refresh*.R or the
  # data workflows, which invalidate the ingest targets before running.
  tar_target(
    raw_picks,
    if (refresh_enabled()) ingest_picks()
  ),
  tar_target(
    raw_player_stats,
    if (refresh_enabled()) {
      ingest_player_stats(refresh_seasons(source = "player_stats"))
    }
  ),
  tar_target(
    raw_coaches,
    if (refresh_enabled()) ingest_coaches()
  ),
  tar_target(
    raw_teams,
    if (refresh_enabled()) ingest_teams()
  ),
  tar_target(
    raw_roster,
    if (refresh_enabled()) ingest_roster(refresh_seasons(source = "roster"))
  ),
  tar_target(
    raw_recruiting,
    if (refresh_enabled()) {
      ingest_recruiting(refresh_seasons(source = "recruiting"))
    }
  ),
  # Game statistics (CFBD /games family). /games/players carries the shared
  # athlete id, so game_player_stats joins the playerId namespace directly.
  # Dynamic branching (decision 0029): each branch is ONE API call, cached
  # separately, so a failed refresh resumes at the first un-ingested week
  # instead of re-pulling the whole sweep. Combines keep the original full-table
  # shapes, so everything downstream is unchanged.
  tar_target(
    games_grid,
    tidyr::expand_grid(
      season = refresh_seasons(source = "games"),
      seasonType = c("regular", "postseason")
    )
  ),
  # The branch targets map one API call per branch; these aggregates consume
  # the full branch value, so a plain bind_rows restores the original
  # full-table shape for everything downstream (decision 0029).
  tar_target(
    raw_games_chunk,
    if (refresh_enabled()) {
      ingest_games_chunk(games_grid$season, games_grid$seasonType)
    },
    pattern = map(games_grid)
  ),
  tar_target(
    raw_games,
    if (refresh_enabled()) dplyr::bind_rows(raw_games_chunk)
  ),
  # The week grid comes from the cleaned games (fresh ingest in refresh mode,
  # the published parquet in track mode), so the stats ingests never re-pull
  # /games to discover weeks and track mode never touches a NULL raw target.
  # Only the selected seasons' weeks with a completed game are pulled, so an
  # in-season run skips the scheduled-but-unplayed weeks.
  tar_target(
    week_grid,
    games |>
      dplyr::filter(
        season %in% refresh_seasons(source = "games"),
        completed
      ) |>
      dplyr::distinct(season, seasonType, week) |>
      dplyr::arrange(season, seasonType, week)
  ),
  tar_target(
    raw_game_team_stats_chunk,
    if (refresh_enabled()) {
      ingest_game_team_stats_chunk(
        week_grid$season,
        week_grid$week,
        week_grid$seasonType
      )
    },
    pattern = map(week_grid)
  ),
  tar_target(
    raw_game_team_stats,
    if (refresh_enabled()) dplyr::bind_rows(raw_game_team_stats_chunk)
  ),
  tar_target(
    raw_game_player_stats_chunk,
    if (refresh_enabled()) {
      ingest_game_player_stats_chunk(
        week_grid$season,
        week_grid$week,
        week_grid$seasonType
      )
    },
    pattern = map(week_grid)
  ),
  tar_target(
    raw_game_player_stats,
    if (refresh_enabled()) dplyr::bind_rows(raw_game_player_stats_chunk)
  ),
  # Play-by-play (decision 0031). /plays is one call per played week, mapped
  # over the same week grid as the game stats; the two dimensions are one call
  # each. /plays/stats is one call per GAME (~1,700 a season), branched by
  # season with the games looped inside the chunk. The current season pulls
  # only new games plus a one-week re-pull (decision 0045); a past season only
  # with CFB2NFL_PLAYS_STATS (see play_stats_enabled()).
  tar_target(raw_play_types, if (refresh_enabled()) ingest_play_types()),
  tar_target(
    raw_play_stat_types,
    if (refresh_enabled()) ingest_play_stat_types()
  ),
  tar_target(
    raw_plays_chunk,
    if (refresh_enabled()) {
      ingest_plays_chunk(week_grid$season, week_grid$week, week_grid$seasonType)
    },
    pattern = map(week_grid)
  ),
  tar_target(
    raw_plays,
    if (refresh_enabled()) dplyr::bind_rows(raw_plays_chunk)
  ),
  tar_target(play_stats_grid, refresh_seasons(source = "play_stats")),
  # The games to pull come from the plays, so only games CFBD has
  # play-by-play for are queried, minus those already published (read from
  # the downloaded play_stats.parquet, decision 0045).
  tar_target(plays_games, dplyr::distinct(plays, season, gameId)),
  tar_target(
    raw_play_stats_chunk,
    if (refresh_enabled()) {
      path <- "data/play_stats.parquet"
      published <- if (file.exists(path)) {
        arrow::read_parquet(path, col_select = "gameId")$gameId
      }
      ids <- play_stats_games_to_pull(
        play_stats_grid,
        plays_games,
        games,
        published_ids = published,
        backfill = play_stats_enabled()
      )
      if (length(ids)) ingest_play_stats_chunk(ids)
    },
    pattern = map(play_stats_grid)
  ),
  tar_target(
    raw_play_stats,
    if (refresh_enabled()) dplyr::bind_rows(raw_play_stats_chunk)
  ),
  # NFL outcomes via nflverse (decision 0014); no CFBD key required to ingest.
  tar_target(
    raw_nfl_draft_picks,
    if (refresh_enabled()) ingest_nfl_draft_picks()
  ),
  tar_target(
    raw_nfl_rosters,
    if (refresh_enabled()) ingest_nfl_rosters()
  ),
  tar_target(
    raw_nfl_player_stats,
    if (refresh_enabled()) ingest_nfl_player_stats()
  ),
  # NFL Scouting Combine via nflverse (decision 0043); no CFBD calls.
  tar_target(
    raw_combine,
    if (refresh_enabled()) ingest_combine()
  ),

  # ---- clean -> published parquet assets (decision 0018) --------------------
  # The published parquet ARE the cleaned tables, so parquet and the DuckDB
  # bundle carry identical schemas. In refresh mode parquet_asset() cleans the
  # freshly ingested raw and WRITES the parquet; in track mode it tracks the
  # existing committed/downloaded file (no key, no re-clean). Each `<table>`
  # target then reads the cleaned parquet, so it is the single source of truth.
  tar_target(
    picks_file,
    parquet_asset("data/picks.parquet", function() clean_picks(raw_picks)),
    format = "file"
  ),
  tar_target(picks, arrow::read_parquet(picks_file)),
  tar_target(
    player_stats_file,
    parquet_asset("data/player_stats.parquet", function() {
      splice_seasons(
        clean_player_stats(raw_player_stats),
        "data/player_stats.parquet",
        "season",
        refresh_seasons(source = "player_stats"),
        full = refresh_is_full(source = "player_stats")
      )
    }),
    format = "file"
  ),
  tar_target(player_stats, arrow::read_parquet(player_stats_file)),
  tar_target(
    coaches_file,
    parquet_asset("data/coaches.parquet", function() {
      clean_coaches(raw_coaches)
    }),
    format = "file"
  ),
  tar_target(coaches, arrow::read_parquet(coaches_file)),
  tar_target(
    teams_file,
    parquet_asset("data/teams.parquet", function() clean_teams(raw_teams)),
    format = "file"
  ),
  tar_target(teams, arrow::read_parquet(teams_file)),
  tar_target(
    roster_file,
    parquet_asset("data/roster.parquet", function() {
      splice_seasons(
        clean_roster(raw_roster),
        "data/roster.parquet",
        "season",
        refresh_seasons(source = "roster"),
        full = refresh_is_full(source = "roster")
      )
    }),
    format = "file"
  ),
  tar_target(roster, arrow::read_parquet(roster_file)),
  tar_target(
    recruiting_file,
    parquet_asset("data/recruiting.parquet", function() {
      splice_seasons(
        clean_recruiting(raw_recruiting),
        "data/recruiting.parquet",
        "hs_class",
        refresh_seasons(source = "recruiting"),
        full = refresh_is_full(source = "recruiting"),
        dedupe = dedupe_recruiting
      )
    }),
    format = "file"
  ),
  tar_target(recruiting, arrow::read_parquet(recruiting_file)),
  tar_target(
    games_file,
    parquet_asset("data/games.parquet", function() {
      splice_seasons(
        clean_games(raw_games),
        "data/games.parquet",
        "season",
        refresh_seasons(source = "games"),
        full = refresh_is_full(source = "games")
      )
    }),
    format = "file"
  ),
  tar_target(games, arrow::read_parquet(games_file)),
  tar_target(
    game_team_stats_file,
    parquet_asset("data/game_team_stats.parquet", function() {
      splice_seasons(
        clean_game_team_stats(raw_game_team_stats),
        "data/game_team_stats.parquet",
        "season",
        refresh_seasons(source = "game_team_stats"),
        full = refresh_is_full(source = "game_team_stats")
      )
    }),
    format = "file"
  ),
  tar_target(game_team_stats, arrow::read_parquet(game_team_stats_file)),
  tar_target(
    game_player_stats_file,
    parquet_asset("data/game_player_stats.parquet", function() {
      splice_seasons(
        clean_game_player_stats(raw_game_player_stats),
        "data/game_player_stats.parquet",
        "season",
        refresh_seasons(source = "game_player_stats"),
        full = refresh_is_full(source = "game_player_stats")
      )
    }),
    format = "file"
  ),
  tar_target(game_player_stats, arrow::read_parquet(game_player_stats_file)),
  tar_target(
    play_types_file,
    parquet_asset("data/play_types.parquet", function() {
      clean_play_types(raw_play_types)
    }),
    format = "file"
  ),
  tar_target(play_types, arrow::read_parquet(play_types_file)),
  tar_target(
    play_stat_types_file,
    parquet_asset("data/play_stat_types.parquet", function() {
      clean_play_stat_types(raw_play_stat_types)
    }),
    format = "file"
  ),
  tar_target(play_stat_types, arrow::read_parquet(play_stat_types_file)),
  # plays is millions of rows, so the in-store copies are parquet, not rds.
  tar_target(
    plays_file,
    parquet_asset("data/plays.parquet", function() {
      splice_seasons(
        clean_plays(raw_plays, play_types),
        "data/plays.parquet",
        "season",
        refresh_seasons(source = "plays"),
        full = refresh_is_full(source = "plays")
      )
    }),
    format = "file"
  ),
  tar_target(plays, arrow::read_parquet(plays_file), format = "parquet"),
  # The pulled games replace their own rows; every other game is kept.
  tar_target(
    play_stats_file,
    parquet_asset("data/play_stats.parquet", function() {
      assemble_play_stats(
        raw_play_stats,
        play_stat_types,
        "data/play_stats.parquet"
      )
    }),
    format = "file"
  ),
  tar_target(
    play_stats,
    arrow::read_parquet(play_stats_file),
    format = "parquet"
  ),
  tar_target(
    nfl_draft_picks_file,
    parquet_asset(
      "data/nfl_draft_picks.parquet",
      function() clean_nfl_draft_picks(raw_nfl_draft_picks)
    ),
    format = "file"
  ),
  tar_target(nfl_draft_picks, arrow::read_parquet(nfl_draft_picks_file)),
  tar_target(
    nfl_rosters_file,
    parquet_asset(
      "data/nfl_rosters.parquet",
      function() clean_nfl_rosters(raw_nfl_rosters)
    ),
    format = "file"
  ),
  tar_target(nfl_rosters, arrow::read_parquet(nfl_rosters_file)),
  tar_target(
    nfl_player_stats_file,
    parquet_asset(
      "data/nfl_player_stats.parquet",
      function() clean_nfl_player_stats(raw_nfl_player_stats)
    ),
    format = "file"
  ),
  tar_target(nfl_player_stats, arrow::read_parquet(nfl_player_stats_file)),
  # Combine measurables linked to CFBD athlete ids (decision 0043). The link
  # runs inside the asset so the published parquet carries athlete_id and
  # link_method (parquet == DuckDB == dict); a link change needs a refresh.
  # Pre-draft information: kept off the in-career model inputs.
  tar_target(
    combine_file,
    parquet_asset(
      "data/combine.parquet",
      function() {
        link_combine(
          clean_combine(raw_combine),
          picks,
          player_stats,
          roster,
          nfl_draft_picks,
          reused = reused
        )
      }
    ),
    format = "file"
  ),
  tar_target(combine, arrow::read_parquet(combine_file)),
  # conference_tiers derived from the cleaned player_stats (decision 0017),
  # published as its own cleaned parquet asset.
  tar_target(
    tiers_file,
    parquet_asset(
      "data/conference_tiers.parquet",
      function() build_conference_tiers(player_stats)
    ),
    format = "file"
  ),
  tar_target(tiers, arrow::read_parquet(tiers_file)),
  # Stat-phase taxonomy: hand-authored package data (inst/extdata), read via
  # stat_taxonomy(); makes the long player_stats interpretable (phase + labels).
  # Target is suffixed _tbl to avoid colliding with the stat_taxonomy()
  # function from tar_source() (targets warns on the name clash).
  tar_target(stat_taxonomy_tbl, stat_taxonomy()),

  # ---- contracts (decision 0005): pass/fail feeds the audit log -------------
  tar_target(
    ok_picks,
    pointblank::all_passed(
      contract_picks(picks, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_player_stats,
    pointblank::all_passed(
      contract_player_stats(player_stats, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_player_season,
    pointblank::all_passed(
      contract_player_season(player_season, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_coaches,
    pointblank::all_passed(
      contract_coaches(coaches, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_roster,
    pointblank::all_passed(
      contract_roster(roster, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_recruiting,
    pointblank::all_passed(
      contract_recruiting(recruiting, stop_on_fail = FALSE)
    )
  ),
  # Season-scoped refreshes rewrite only some seasons (decision 0034); no
  # season may go missing from a season-keyed table.
  tar_target(
    ok_season_coverage,
    pointblank::all_passed(
      contract_season_coverage(
        list(
          player_stats = player_stats$season,
          roster = roster$season,
          recruiting = recruiting$hs_class,
          games = games$season,
          game_team_stats = game_team_stats$season,
          game_player_stats = game_player_stats$season,
          plays = plays$season
        ),
        required = required_seasons(c(
          "player_stats",
          "roster",
          "recruiting",
          "games",
          "game_team_stats",
          "game_player_stats",
          "plays"
        )),
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_teams,
    pointblank::all_passed(
      contract_teams(teams, player_season, stop_on_fail = FALSE)$coverage
    )
  ),
  tar_target(
    ok_games,
    pointblank::all_passed(contract_games(games, stop_on_fail = FALSE))
  ),
  tar_target(
    ok_game_team_stats,
    pointblank::all_passed(
      contract_game_team_stats(game_team_stats, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_game_player_stats,
    pointblank::all_passed(
      contract_game_player_stats(game_player_stats, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_play_types,
    pointblank::all_passed(
      contract_play_dimension(
        play_types,
        "text",
        "play_types",
        min_rows = 40L,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_play_stat_types,
    pointblank::all_passed(
      contract_play_dimension(
        play_stat_types,
        "name",
        "play_stat_types",
        min_rows = 25L,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_plays,
    pointblank::all_passed(contract_plays(plays, games, stop_on_fail = FALSE))
  ),
  tar_target(
    ok_play_stats,
    pointblank::all_passed(
      contract_play_stats(play_stats, plays, roster, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_player_game,
    pointblank::all_passed(
      contract_player_game(
        player_game,
        game_player_stats,
        games,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_player_usage,
    pointblank::all_passed(
      contract_player_usage(
        player_usage,
        player_game,
        games,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_tiers,
    pointblank::all_passed(
      contract_conference_tiers(
        tiers,
        player_stats,
        stop_on_fail = FALSE
      )$coverage
    )
  ),
  tar_target(
    ok_drafted,
    pointblank::all_passed(
      contract_drafted(ps_draft, ps_tier, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_nfl_draft_picks,
    pointblank::all_passed(
      contract_nfl_draft_picks(nfl_draft_picks, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_nfl_rosters,
    pointblank::all_passed(
      contract_nfl_rosters(nfl_rosters, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_nfl_player_stats,
    pointblank::all_passed(
      contract_nfl_player_stats(nfl_player_stats, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_combine,
    pointblank::all_passed(
      contract_combine(
        combine,
        n_expected = if (refresh_enabled()) nrow(raw_combine),
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_nfl_link,
    pointblank::all_passed(
      contract_nfl_link(picks_nfl, picks, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_career,
    pointblank::all_passed(
      contract_career_summary(career, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_position_path,
    pointblank::all_passed(
      contract_position_path(
        position_path,
        n_universe = position_counts$n_universe,
        n_picks_universe = position_counts$n_picks_universe,
        n_recruits_universe = position_counts$n_recruits_universe,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_position_mapping,
    pointblank::all_passed(
      contract_position_mapping(
        list(
          recruiting = recruiting$recruit_position,
          roster = roster$position,
          picks = picks$position,
          nfl_draft = nfl_draft_picks$position,
          nfl_roster = nfl_rosters$position
        ),
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_stat_taxonomy,
    pointblank::all_passed(
      contract_stat_taxonomy(
        player_stats,
        stat_taxonomy_tbl,
        stop_on_fail = FALSE
      )$coverage
    )
  ),
  tar_target(
    ok_outcomes,
    pointblank::all_passed(
      contract_outcomes(outcomes, ps_pop, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_team_season,
    pointblank::all_passed(
      contract_team_season(team_season, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_team_draft,
    pointblank::all_passed(
      contract_team_draft(
        team_draft,
        exits,
        picks,
        reused,
        stop_on_fail = FALSE
      )
    )
  ),
  # Contract gate (decision 0023): a FALSE anywhere stops tar_make() (the
  # default error = "stop" aborts the run, so CI never publishes a failing
  # build). NA (steps without a contract yet) is not a failure.
  tar_target(
    contract_gate,
    assert_contracts_pass(list(
      picks = ok_picks,
      player_stats = ok_player_stats,
      player_season = ok_player_season,
      coaches = ok_coaches,
      roster = ok_roster,
      recruiting = ok_recruiting,
      teams = ok_teams,
      season_coverage = ok_season_coverage,
      games = ok_games,
      game_team_stats = ok_game_team_stats,
      game_player_stats = ok_game_player_stats,
      explorer_plays_files = ok_explorer_plays_files,
      play_types = ok_play_types,
      play_stat_types = ok_play_stat_types,
      plays = ok_plays,
      play_stats = ok_play_stats,
      tiers = ok_tiers,
      drafted = ok_drafted,
      coach_link = ok_coach_link,
      tier_link = ok_tier_link,
      reused_filter = ok_reused_filter,
      change_features = ok_change,
      roster_weight = ok_weight,
      recruit_link = ok_recruit_link,
      nfl_draft_picks = ok_nfl_draft_picks,
      nfl_rosters = ok_nfl_rosters,
      nfl_player_stats = ok_nfl_player_stats,
      nfl_link = ok_nfl_link,
      combine = ok_combine,
      career_summary = ok_career,
      position_mapping = ok_position_mapping,
      position_path = ok_position_path,
      player_game = ok_player_game,
      player_usage = ok_player_usage,
      stat_taxonomy = ok_stat_taxonomy,
      outcomes = ok_outcomes,
      team_season = ok_team_season,
      team_draft = ok_team_draft,
      explorer = ok_explorer,
      explorer_team_games = ok_explorer_team_games,
      explorer_plays = ok_explorer_plays,
      explorer_players = ok_explorer_players,
      explorer_combine = ok_explorer_combine,
      explorer_careers = ok_explorer_careers
    ))
  ),
  # ---- link-step contracts (audit-hygiene workstream C) ----------------------
  tar_target(
    ok_coach_link,
    pointblank::all_passed(
      contract_coach_link(
        ps_coach,
        player_season,
        coaches,
        stop_on_fail = FALSE
      )
    )
  ),
  tar_target(
    ok_tier_link,
    pointblank::all_passed(
      contract_tier_link(ps_tier, ps_coach, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_reused_filter,
    pointblank::all_passed(
      contract_reused_filter(ps_pop, ps_draft, reused, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_change,
    pointblank::all_passed(
      contract_change_features(ps_change, ps_pop, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_weight,
    pointblank::all_passed(
      contract_roster_weight(model_table, ps_change, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_recruit_link,
    pointblank::all_passed(
      contract_recruit_link(ps_recruit, player_season, stop_on_fail = FALSE)
    )
  ),

  # ---- link -----------------------------------------------------------------
  tar_target(player_season, build_player_season(player_stats)),
  tar_target(ps_coach, link_coaches(player_season, coaches)),
  tar_target(ps_tier, link_tiers(ps_coach, tiers)),
  tar_target(ps_draft, link_drafted(ps_tier, picks)),
  # Exclude CFBD-reused athlete ids (one id spanning >7 roster seasons = multiple
  # real people, decision 0022) from the model population.
  tar_target(reused, reused_ids(roster)),
  tar_target(ps_pop, dplyr::filter(ps_draft, !.data$playerId %in% reused)),
  # HS recruiting ratings, name-guarded (decision 0013); kept off the model path.
  tar_target(ps_recruit, link_recruiting(player_season, recruiting)),
  # NFL outcomes bridged to CFBD picks by draft slot (decision 0014); an
  # outcome/label source, kept off the model input path. A pipeline step only
  # (decision 0041): read it with tar_read(picks_nfl), it is not in the DuckDB.
  tar_target(picks_nfl, link_nfl_draft(picks, nfl_draft_picks)),
  # Per-player position path, HS -> college -> NFL (issue #49, decision 0021).
  # A contract-checked pipeline step for a single post, not in the DuckDB
  # (decision 0041): read it with tar_read(position_path).
  tar_target(
    position_path,
    build_position_path(
      roster,
      recruiting,
      player_season,
      picks_nfl,
      nfl_draft_picks,
      reused = reused
    )
  ),
  tar_target(
    position_counts,
    position_universe_counts(roster, picks_nfl, reused, recruiting)
  ),

  # ---- features -------------------------------------------------------------
  tar_target(ps_change, add_change_features(ps_pop)),
  tar_target(model_table, add_roster_weight(ps_change, roster)),
  # Career grain (Explore questions 4/5/12). A DERIVED table: bundled into the
  # DuckDB asset and documented in inst/dict like stat_taxonomy, but not
  # published as parquet; it rebuilds from roster in any mode (decision 0021).
  tar_target(career, career_summary(roster)),
  # Player x game grain (decision 0035): one row per (playerId, gameId) with a
  # stat line; the shared base for per-game usage and opponent-adjusted
  # performance. Derived like career, not published parquet.
  tar_target(player_game, build_player_game(game_player_stats, games)),
  # Playing time (issue #50, decision 0038): games appeared out of team games
  # per player-season-team, from player_game. A pipeline step only, not in the
  # DuckDB (decision 0041): read it with tar_read(player_usage).
  tar_target(player_usage, build_player_usage(player_game, roster, games)),
  # Team- and conference-grain derived tables (plans/conferences-teams.md,
  # decision 0033): credit each player's exit to their final pre-draft
  # roster team; derived like career, not published parquet.
  tar_target(
    team_season,
    build_team_season(roster, games, tiers, player_season, coaches)
  ),
  tar_target(
    exits,
    exit_cohort(
      roster,
      picks,
      udfa_ids = unique(outcomes$playerId[
        outcomes$outcome_signed_udfa_d %in% TRUE
      ]),
      reused = reused
    )
  ),
  tar_target(team_draft, build_team_draft(exits, team_season)),
  # Explorer assets (plans/explorer.md, decision 0046): slim JSON the OJS
  # page fetches at runtime, rebuilt on every tar_make() (including the
  # track-mode site build) so the page follows the weekly refresh.
  tar_target(explorer_team_season, build_explorer_team_season(games, tiers)),
  tar_target(explorer_teams, build_explorer_teams(teams, explorer_team_season)),
  tar_target(explorer_meta, build_explorer_meta(games)),
  tar_target(
    ok_explorer,
    pointblank::all_passed(contract_explorer_shell(
      explorer_teams,
      explorer_team_season,
      explorer_meta,
      games,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    explorer_shell_files,
    write_explorer_assets(list(
      meta = explorer_meta,
      teams = explorer_teams,
      team_season = explorer_team_season
    )),
    format = "file"
  ),
  # Teams tab (plans/explorer.md step 3): each team's side of each game, and
  # the plays the game timeline draws. explorer_plays is ~3M rows, so it is
  # stored as parquet rather than rds.
  tar_target(
    explorer_team_games,
    build_explorer_team_games(
      games,
      explorer_team_season,
      unique(plays$gameId)
    )
  ),
  tar_target(
    explorer_plays,
    build_explorer_plays(
      plays,
      games,
      teams,
      play_stats,
      explorer_player_seasons
    ),
    format = "parquet"
  ),
  tar_target(
    ok_explorer_team_games,
    pointblank::all_passed(contract_explorer_team_games(
      explorer_team_games,
      explorer_team_season,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    ok_explorer_plays,
    pointblank::all_passed(contract_explorer_plays(
      explorer_plays,
      plays,
      games,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    ok_explorer_plays_files,
    pointblank::all_passed(contract_explorer_plays_files(
      explorer_game_files[!endsWith(explorer_game_files, ".json")],
      explorer_plays,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    explorer_game_files,
    c(
      write_explorer_team_games(explorer_team_games),
      write_explorer_plays(explorer_plays)
    ),
    format = "file"
  ),
  # Players tab (plans/explorer.md step 4): each player's NFL outcome, then
  # every player-season's headline stats and percentiles, one parquet file
  # per position group.
  tar_target(
    explorer_player_outcomes,
    build_explorer_player_outcomes(
      career_end_status(career, outcomes, picks_nfl),
      picks_nfl,
      explorer_meta$default_season
    )
  ),
  tar_target(
    explorer_player_seasons,
    build_explorer_player_seasons(
      player_stats,
      tiers,
      explorer_teams,
      explorer_player_outcomes,
      explorer_meta$default_season
    )
  ),
  tar_target(
    explorer_player_files,
    write_explorer_players(explorer_player_seasons),
    format = "file"
  ),
  # Combine tab (plans/explorer.md step 5): every invitee's measurables and
  # draft outcome as one columnar JSON file.
  tar_target(
    explorer_combine,
    build_explorer_combine(combine, explorer_player_seasons)
  ),
  tar_target(
    explorer_combine_file,
    write_explorer_combine(explorer_combine),
    format = "file"
  ),
  tar_target(
    ok_explorer_combine,
    pointblank::all_passed(contract_explorer_combine(
      explorer_combine,
      combine,
      explorer_combine_file,
      stop_on_fail = FALSE
    ))
  ),
  # Draft & careers tab (plans/explorer.md step 6): every pick since 2010
  # with its NFL roster seasons, and transfer arrivals by team and season.
  tar_target(
    explorer_careers,
    build_explorer_careers(
      build_explorer_draft(
        picks_nfl,
        nfl_rosters,
        tiers,
        explorer_teams,
        explorer_player_seasons
      ),
      build_explorer_transfers(ps_change, explorer_teams),
      transfer_rate(career),
      nfl_rosters
    )
  ),
  tar_target(
    explorer_careers_file,
    write_explorer_careers(explorer_careers),
    format = "file"
  ),
  tar_target(
    ok_explorer_careers,
    pointblank::all_passed(contract_explorer_careers(
      explorer_careers,
      picks_nfl,
      ps_change,
      min(tiers$season),
      explorer_careers_file,
      stop_on_fail = FALSE
    ))
  ),
  tar_target(
    ok_explorer_players,
    pointblank::all_passed(contract_explorer_players(
      explorer_player_seasons,
      player_stats,
      explorer_player_files,
      stop_on_fail = FALSE
    ))
  ),
  # Person-period outcome table (decision 0032): the modeling dependent
  # variables. Derived from cleaned tables (no new API calls), but PUBLISHED
  # as parquet on data-latest per plan (user request), alongside the DuckDB
  # bundle — so models query the label directly from either asset.
  tar_target(
    outcomes_file,
    parquet_asset(
      "data/outcomes.parquet",
      function() {
        build_outcomes(
          ps_pop,
          career,
          recruiting,
          picks_nfl,
          nfl_rosters,
          nfl_player_stats
        )
      }
    ),
    format = "file"
  ),
  tar_target(outcomes, arrow::read_parquet(outcomes_file)),

  # ---- model + report (placeholders) ----------------------------------------
  tar_target(model_fit, fit_draft_model(model_table)),

  # ---- package: bundle cleaned tables into a queryable DuckDB asset ----------
  # One SQL-queryable file carrying the cleaned, contract-checked tables (the
  # schemas in inst/dict/*.yml), published alongside the parquet on the
  # data-latest release (decision 0016). format = "file" so targets tracks it.
  tar_target(
    duckdb_file,
    build_duckdb(
      list(
        picks = picks,
        player_stats = player_stats,
        coaches = coaches,
        teams = teams,
        conference_tiers = tiers,
        roster = roster,
        recruiting = recruiting,
        games = games,
        game_team_stats = game_team_stats,
        game_player_stats = game_player_stats,
        play_types = play_types,
        play_stat_types = play_stat_types,
        plays = plays,
        play_stats = play_stats,
        nfl_draft_picks = nfl_draft_picks,
        nfl_rosters = nfl_rosters,
        nfl_player_stats = nfl_player_stats,
        combine = combine,
        stat_taxonomy = stat_taxonomy_tbl,
        ps_change = ps_change,
        career_summary = career,
        player_game = player_game,
        team_season = team_season,
        team_draft = team_draft,
        outcomes = outcomes,
        audit_log = db_audit_log
      ),
      "data/cfb2nfl.duckdb"
    ),
    format = "file"
  ),

  # ---- audit log (decision 0005): one uniform row per tracked step ----------
  tar_target(
    audit_log,
    dplyr::bind_rows(
      audit_step(
        picks,
        "clean_picks",
        "clean",
        raw_picks,
        keys = c("year", "round", "pick"),
        contract_passed = ok_picks
      ),
      audit_step(
        player_stats,
        "clean_player_stats",
        "clean",
        raw_player_stats,
        keys = c("playerId", "season"),
        contract_passed = ok_player_stats
      ),
      audit_step(
        coaches,
        "clean_coaches",
        "clean",
        raw_coaches,
        keys = c("coach_id", "season"),
        contract_passed = ok_coaches
      ),
      audit_step(
        roster,
        "clean_roster",
        "clean",
        raw_roster,
        keys = c("playerId", "season"),
        contract_passed = ok_roster
      ),
      audit_step(
        recruiting,
        "clean_recruiting",
        "clean",
        raw_recruiting,
        keys = "playerId",
        contract_passed = ok_recruiting
      ),
      audit_step(
        teams,
        "clean_teams",
        "clean",
        raw_teams,
        keys = "team",
        contract_passed = ok_teams
      ),
      audit_step(
        games,
        "clean_games",
        "clean",
        raw_games,
        keys = "id",
        contract_passed = ok_games
      ),
      audit_step(
        game_team_stats,
        "clean_game_team_stats",
        "clean",
        raw_game_team_stats,
        keys = c("gameId", "team", "category"),
        contract_passed = ok_game_team_stats
      ),
      audit_step(
        game_player_stats,
        "clean_game_player_stats",
        "clean",
        raw_game_player_stats,
        keys = c("gameId", "playerId", "category", "statType"),
        contract_passed = ok_game_player_stats
      ),
      audit_step(
        play_types,
        "clean_play_types",
        "clean",
        raw_play_types,
        keys = "id",
        contract_passed = ok_play_types
      ),
      audit_step(
        play_stat_types,
        "clean_play_stat_types",
        "clean",
        raw_play_stat_types,
        keys = "id",
        contract_passed = ok_play_stat_types
      ),
      audit_step(
        plays,
        "clean_plays",
        "clean",
        raw_plays,
        keys = "id",
        contract_passed = ok_plays
      ),
      audit_step(
        play_stats,
        "clean_play_stats",
        "clean",
        raw_play_stats,
        keys = c("playId", "athleteId", "statTypeId"),
        contract_passed = ok_play_stats
      ),
      audit_step(
        player_season,
        "build_player_season",
        "link",
        player_stats,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_player_season
      ),
      audit_step(
        ps_coach,
        "link_coaches",
        "link",
        player_season,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_coach_link
      ),
      audit_step(
        ps_tier,
        "link_tiers",
        "link",
        ps_coach,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_tier_link
      ),
      audit_step(
        ps_draft,
        "link_drafted",
        "link",
        ps_tier,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_drafted
      ),
      audit_step(
        ps_pop,
        "filter_reused_ids",
        "link",
        ps_draft,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_reused_filter
      ),
      audit_step(
        ps_change,
        "add_change_features",
        "features",
        ps_pop,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_change
      ),
      audit_step(
        career,
        "career_summary",
        "features",
        roster,
        keys = "playerId",
        contract_passed = ok_career
      ),
      audit_step(
        position_path,
        "position_path",
        "features",
        roster,
        keys = "playerId",
        contract_passed = ok_position_path
      ),
      audit_step(
        player_game,
        "build_player_game",
        "features",
        game_player_stats,
        keys = c("playerId", "gameId"),
        contract_passed = ok_player_game
      ),
      audit_step(
        player_usage,
        "build_player_usage",
        "features",
        player_game,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_player_usage
      ),
      audit_step(
        model_table,
        "add_roster_weight",
        "features",
        ps_change,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_weight
      ),
      audit_step(
        ps_recruit,
        "link_recruiting",
        "link",
        player_season,
        keys = c("playerId", "season", "team"),
        contract_passed = ok_recruit_link
      ),
      audit_step(
        nfl_draft_picks,
        "clean_nfl_draft_picks",
        "clean",
        raw_nfl_draft_picks,
        keys = c("season", "round", "pick"),
        contract_passed = ok_nfl_draft_picks
      ),
      audit_step(
        nfl_rosters,
        "clean_nfl_rosters",
        "clean",
        raw_nfl_rosters,
        keys = c("gsis_id", "season"),
        contract_passed = ok_nfl_rosters
      ),
      audit_step(
        nfl_player_stats,
        "clean_nfl_player_stats",
        "clean",
        raw_nfl_player_stats,
        keys = c("gsis_id", "season"),
        contract_passed = ok_nfl_player_stats
      ),
      audit_step(
        picks_nfl,
        "link_nfl_draft",
        "link",
        picks,
        keys = "playerId",
        contract_passed = ok_nfl_link
      ),
      audit_step(
        combine,
        "link_combine",
        "link",
        raw_combine,
        keys = c("season", "player_name", "school", "pos"),
        contract_passed = ok_combine,
        linked = !is.na(combine$athlete_id)
      ),
      audit_step(
        stat_taxonomy_tbl,
        "stat_taxonomy",
        "clean",
        keys = c("category", "statType"),
        contract_passed = ok_stat_taxonomy
      ),
      audit_step(
        outcomes,
        "build_outcomes",
        "features",
        ps_pop,
        keys = c("playerId", "season"),
        contract_passed = ok_outcomes
      ),
      audit_step(
        team_season,
        "build_team_season",
        "features",
        roster,
        keys = c("team", "season"),
        contract_passed = ok_team_season
      ),
      audit_step(
        team_draft,
        "build_team_draft",
        "features",
        exits,
        keys = c("team", "season", "position_group"),
        contract_passed = ok_team_draft
      ),
      audit_step(
        explorer_team_season,
        "build_explorer_team_season",
        "features",
        games,
        keys = c("team_id", "season"),
        contract_passed = ok_explorer
      ),
      audit_step(
        explorer_team_games,
        "build_explorer_team_games",
        "features",
        games,
        keys = c("team_id", "game_id"),
        contract_passed = ok_explorer_team_games
      ),
      audit_step(
        explorer_plays,
        "build_explorer_plays",
        "features",
        plays,
        keys = "play_id",
        contract_passed = ok_explorer_plays
      ),
      audit_step(
        explorer_player_seasons,
        "build_explorer_player_seasons",
        "features",
        player_stats,
        keys = c("pos", "player_id", "season", "team"),
        contract_passed = ok_explorer_players
      ),
      audit_step(
        explorer_combine,
        "build_explorer_combine",
        "features",
        combine,
        keys = c("season", "name", "school", "combine_pos"),
        contract_passed = ok_explorer_combine
      ),
      audit_step(
        explorer_careers$draft,
        "build_explorer_draft",
        "features",
        picks_nfl,
        keys = c("year", "overall"),
        contract_passed = ok_explorer_careers
      )
    )
  ),
  # Slimmed lineage log bundled into the DuckDB asset (decision 0027): drops
  # the nested na_by_col list column so it is flat SQL.
  tar_target(db_audit_log, slim_audit_log(audit_log)),

  # ---- schema history: schema_hash across refreshes (audit-hygiene D) -------
  # Refresh mode appends this run's hashes to data/audit_history.csv (seeded
  # from the data-latest release asset by data-refresh.yaml); track mode just
  # reads the file if it's present.
  tar_target(
    schema_history,
    {
      path <- "data/audit_history.csv"
      if (refresh_enabled()) {
        update_schema_history(audit_log, path)
      } else if (file.exists(path)) {
        tibble::as_tibble(utils::read.csv(path))
      }
    }
  )
)
