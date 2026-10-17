# cfbstats pipeline (decision 0004). Single source of truth for the processing
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
  # ---- ingest (decisions 0017-0018) -----------------------------------------
  # Refresh mode (CFBSTATS_REFRESH=true) pulls each source from CFBD/nflverse in
  # memory; track mode (default, no key) leaves them NULL because the cleaned
  # parquet below is read directly. `cue = always` so a local re-refresh always
  # re-ingests.
  tar_target(
    raw_picks,
    if (refresh_enabled()) ingest_picks(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_player_stats,
    if (refresh_enabled()) ingest_player_stats(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_coaches,
    if (refresh_enabled()) ingest_coaches(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_teams,
    if (refresh_enabled()) ingest_teams(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_roster,
    if (refresh_enabled()) ingest_roster(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_recruiting,
    if (refresh_enabled()) ingest_recruiting(),
    cue = tar_cue(mode = "always")
  ),
  # NFL outcomes via nflverse (decision 0014); no CFBD key required to ingest.
  tar_target(
    raw_nfl_draft_picks,
    if (refresh_enabled()) ingest_nfl_draft_picks(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_nfl_rosters,
    if (refresh_enabled()) ingest_nfl_rosters(),
    cue = tar_cue(mode = "always")
  ),
  tar_target(
    raw_nfl_player_stats,
    if (refresh_enabled()) ingest_nfl_player_stats(),
    cue = tar_cue(mode = "always")
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
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(picks, arrow::read_parquet(picks_file)),
  tar_target(
    player_stats_file,
    parquet_asset(
      "data/player_stats.parquet",
      function() clean_player_stats(raw_player_stats)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(player_stats, arrow::read_parquet(player_stats_file)),
  tar_target(
    coaches_file,
    parquet_asset("data/coaches.parquet", function() {
      clean_coaches(raw_coaches)
    }),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(coaches, arrow::read_parquet(coaches_file)),
  tar_target(
    teams_file,
    parquet_asset("data/teams.parquet", function() clean_teams(raw_teams)),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(teams, arrow::read_parquet(teams_file)),
  tar_target(
    roster_file,
    parquet_asset("data/roster.parquet", function() clean_roster(raw_roster)),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(roster, arrow::read_parquet(roster_file)),
  tar_target(
    recruiting_file,
    parquet_asset(
      "data/recruiting.parquet",
      function() clean_recruiting(raw_recruiting)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(recruiting, arrow::read_parquet(recruiting_file)),
  tar_target(
    nfl_draft_picks_file,
    parquet_asset(
      "data/nfl_draft_picks.parquet",
      function() clean_nfl_draft_picks(raw_nfl_draft_picks)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(nfl_draft_picks, arrow::read_parquet(nfl_draft_picks_file)),
  tar_target(
    nfl_rosters_file,
    parquet_asset(
      "data/nfl_rosters.parquet",
      function() clean_nfl_rosters(raw_nfl_rosters)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(nfl_rosters, arrow::read_parquet(nfl_rosters_file)),
  tar_target(
    nfl_player_stats_file,
    parquet_asset(
      "data/nfl_player_stats.parquet",
      function() clean_nfl_player_stats(raw_nfl_player_stats)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(nfl_player_stats, arrow::read_parquet(nfl_player_stats_file)),
  # conference_tiers derived from the cleaned player_stats (decision 0017),
  # published as its own cleaned parquet asset.
  tar_target(
    tiers_file,
    parquet_asset(
      "data/conference_tiers.parquet",
      function() build_conference_tiers(player_stats)
    ),
    format = "file",
    cue = tar_cue(mode = "always")
  ),
  tar_target(tiers, arrow::read_parquet(tiers_file)),
  # Stat-phase taxonomy: hand-authored package data (inst/extdata), read via
  # stat_taxonomy(); makes the long player_stats interpretable (phase + labels).
  tar_target(stat_taxonomy, stat_taxonomy()),

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
  tar_target(
    ok_teams,
    pointblank::all_passed(
      contract_teams(teams, player_season, stop_on_fail = FALSE)$coverage
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
    ok_roster_flags,
    pointblank::all_passed(
      contract_redshirt(roster_flags, stop_on_fail = FALSE)
    )
  ),
  tar_target(
    ok_stat_taxonomy,
    pointblank::all_passed(
      contract_stat_taxonomy(
        player_stats,
        stat_taxonomy,
        stop_on_fail = FALSE
      )$coverage
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
      career_summary = ok_career,
      redshirt = ok_roster_flags,
      stat_taxonomy = ok_stat_taxonomy
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
  # outcome/label source, kept off the model input path.
  tar_target(picks_nfl, link_nfl_draft(picks, nfl_draft_picks)),

  # ---- features -------------------------------------------------------------
  tar_target(ps_change, add_change_features(ps_pop)),
  tar_target(model_table, add_roster_weight(ps_change, roster)),
  # Career-grain and roster-grain derived features (Explore questions 4/5/12).
  # These are in-pipeline DERIVED tables: bundled into the DuckDB asset and
  # documented in inst/dict like stat_taxonomy, but not published as parquet —
  # they rebuild from other cleaned tables in any mode, so track mode needs no
  # release asset for them (decision 0021).
  tar_target(career, career_summary(roster)),
  tar_target(roster_flags, flag_redshirt(roster, player_stats)),

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
        nfl_draft_picks = nfl_draft_picks,
        nfl_rosters = nfl_rosters,
        nfl_player_stats = nfl_player_stats,
        stat_taxonomy = stat_taxonomy,
        ps_change = ps_change,
        roster_flags = roster_flags,
        career_summary = career
      ),
      "data/cfbstats.duckdb"
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
        roster_flags,
        "flag_redshirt",
        "features",
        roster,
        keys = c("playerId", "season"),
        contract_passed = ok_roster_flags
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
        stat_taxonomy,
        "stat_taxonomy",
        "clean",
        keys = c("category", "statType"),
        contract_passed = ok_stat_taxonomy
      )
    )
  ),

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
    },
    cue = targets::tar_cue("always")
  )
)
