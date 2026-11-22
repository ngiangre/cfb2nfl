# Generate inst/dict/*.yml for the play-level NFL tables (feature F23) from
# nflreadr's own data dictionaries plus the column types of one published
# season. Re-run when nflverse adds columns we want to keep; the cleaned
# tables are conformed to these dictionaries (conform_to_dict()), so a column
# not listed here is dropped at clean time.
#
#   Rscript data-raw/make-nfl-dicts.R

pkgload::load_all(quiet = TRUE)

season <- 2025L

r_type <- function(x) {
  switch(
    class(x)[1],
    character = "string",
    integer = "int32",
    numeric = "double",
    logical = "logical",
    stop("Unhandled column class: ", class(x)[1])
  )
}

# nflreadr's dictionaries differ in their column names (Field/field, ...).
describe <- function(dictionary) {
  names(dictionary) <- tolower(names(dictionary))
  stats::setNames(
    gsub("\\s+", " ", trimws(dictionary$description)),
    dictionary$field
  )
}

# `extra` documents derived columns; `override` replaces an nflreadr
# description that is wrong at this table's grain.
write_dict <- function(
  dataset,
  header,
  sample,
  descriptions,
  extra = list(),
  override = list()
) {
  descriptions[names(override)] <- unlist(override)
  cols <- lapply(names(sample), function(nm) {
    list(
      name = nm,
      type = r_type(sample[[nm]]),
      description = extra[[nm]] %||% unname(descriptions[nm]) %||% NA,
      provenance = if (nm %in% names(extra)) "derived" else "raw"
    )
  })
  cols <- lapply(cols, function(col) {
    if (is.na(col$description)) {
      col$description <- "nflverse field."
    }
    col
  })
  path <- file.path("inst", "dict", paste0(dataset, ".yml"))
  yaml::write_yaml(c(header, list(columns = cols)), path)
  cli::cli_alert_success("{.path {path}}: {length(cols)} columns.")
}

window <- "2022 to the current NFL season"
truncation <- paste(
  "Coverage starts in 2022, so careers that began earlier are truncated:",
  "use season-grain nfl_rosters for whole careers and for longevity.",
  "The current season is partial until it ends."
)

# ---- nfl_pbp: every nflverse play-by-play column ---------------------------
pbp <- nflreadr::load_pbp(season)
write_dict(
  "nfl_pbp",
  list(
    dataset = "nfl_pbp",
    source = paste0("nflverse nflreadr::load_pbp (seasons ", window, ")"),
    grain = "one NFL play (regular season and postseason)",
    key = "(game_id, play_id)",
    description = paste(
      "nflverse (nflfastR) play-by-play with every column nflverse ships,",
      "including EPA, WPA and success. Every *_player_id column is a GSIS id",
      "that joins outcomes.gsis_id, nfl_rosters.gsis_id and",
      "nfl_rosters_weekly.gsis_id. An outcome table: never an in-career model",
      "input (decision 0014).",
      truncation
    )
  ),
  pbp,
  describe(nflreadr::dictionary_pbp)
)

# ---- nfl_participation: on-field players per play --------------------------
part <- nflreadr::load_participation(season)
part <- dplyr::relocate(
  dplyr::mutate(
    part,
    season = as.integer(substr(.data$nflverse_game_id, 1, 4))
  ),
  "season",
  .after = "play_id"
)
write_dict(
  "nfl_participation",
  list(
    dataset = "nfl_participation",
    source = paste0(
      "nflverse nflreadr::load_participation (seasons ",
      window,
      ", as nflverse publishes them)"
    ),
    grain = "one NFL play",
    key = "(nflverse_game_id, play_id)",
    description = paste(
      "Who was on the field for each play: offense_players and",
      "defense_players are ';'-separated GSIS ids, so linemen and others",
      "with no credited play still appear. Joins nfl_pbp on",
      "nflverse_game_id = game_id and play_id. 2022 uses the older",
      "NGS-sourced format, so the name/position/number lists are NA there;",
      "nflverse publishes a season some time after it ends.",
      truncation
    )
  ),
  part,
  describe(nflreadr::dictionary_participation),
  extra = list(
    season = "NFL season, from the first four characters of nflverse_game_id."
  )
)

# ---- nfl_snap_counts: snaps per player-game --------------------------------
snaps <- nflreadr::load_snap_counts(season)
write_dict(
  "nfl_snap_counts",
  list(
    dataset = "nfl_snap_counts",
    source = paste0(
      "nflverse nflreadr::load_snap_counts (seasons ",
      window,
      ")"
    ),
    grain = "one player-game (regular season and postseason)",
    key = "(game_id, pfr_player_id)",
    description = paste(
      "Offense, defense and special-teams snaps and shares for every player",
      "who played, every position included (Pro-Football-Reference).",
      "Keyed by pfr_player_id, not GSIS: map to gsis_id through the nflverse",
      "player crosswalk (nflreadr::load_players, the pipeline's nfl_players",
      "target). game_id joins nfl_pbp.game_id.",
      truncation
    )
  ),
  snaps,
  describe(nflreadr::dictionary_snap_counts)
)

# ---- nfl_rosters_weekly: roster status per player-week ---------------------
weekly_cols <- c(
  "season",
  "week",
  "game_type",
  "team",
  "gsis_id",
  "pfr_id",
  "full_name",
  "position",
  "depth_chart_position",
  "jersey_number",
  "status",
  "status_description_abbr",
  "years_exp",
  "entry_year",
  "rookie_year",
  "draft_club",
  "draft_number"
)
weekly <- nflreadr::load_rosters_weekly(season)[weekly_cols]
weekly$jersey_number <- as.integer(weekly$jersey_number)
write_dict(
  "nfl_rosters_weekly",
  list(
    dataset = "nfl_rosters_weekly",
    source = paste0(
      "nflverse nflreadr::load_rosters_weekly (seasons ",
      window,
      ")"
    ),
    grain = "one player on one team's roster in one week",
    key = "(season, week, team, gsis_id)",
    description = paste(
      "Where a player stood each week: status ACT (active), DEV (practice",
      "squad), INA (inactive), RES (reserve, mostly injured reserve), CUT,",
      "RET, TRD and others; a change of team between weeks is a move. A",
      "player can appear for two teams in the week of a move. Rows with",
      "no gsis_id are dropped. Season-grain nfl_rosters stays the longevity",
      "source. Cross-platform ids, headshots and physicals are not kept",
      "(physicals are in nfl_rosters).",
      truncation
    )
  ),
  weekly,
  describe(nflreadr::dictionary_rosters),
  override = list(
    season = "NFL season.",
    week = "Week of the season this roster row describes.",
    game_type = "Game type of that week: REG, WC, DIV, CON or SB."
  )
)
