# Cleaning: standardize schemas and coerce join keys onto the shared athlete-id
# namespace (decision 0003). Cleaning never mutates raw inputs; it returns new
# tibbles. Keep transformations minimal and legible so the audit layer
# (decision 0005) can attribute every row change.

#' Clean draft picks
#'
#' Coerces the (int) `collegeAthleteId` to a string `playerId` so picks join
#' directly to `player_stats.playerId` / `roster.id` (decision 0003). Retains
#' the original id for QA.
#'
#' @param picks Raw picks tibble from [ingest_picks()].
#'
#' @return A cleaned picks tibble with a string `playerId` key.
#' @export
clean_picks <- function(picks) {
  picks |>
    dplyr::mutate(
      playerId = dplyr::if_else(
        is.na(.data$collegeAthleteId),
        NA_character_,
        as.character(.data$collegeAthleteId)
      ),
      drafted = TRUE
    )
}

#' Clean player season stats
#'
#' Ensures key column types on the long player-season stats. Stays long; the
#' pivot to position-relevant features happens in the features stage.
#'
#' @param player_stats Raw long stats tibble from [ingest_player_stats()].
#'
#' @return A cleaned long player-season stats tibble.
#' @export
clean_player_stats <- function(player_stats) {
  player_stats |>
    dplyr::mutate(
      playerId = as.character(.data$playerId),
      season = as.integer(.data$season)
    )
}

#' Clean coaches
#'
#' Renames the unnested `seasons_*` columns to a tidy head-coach-season schema
#' and builds the `(school, season)` key used to join coaches to player-seasons.
#'
#' @param coaches Raw coaches tibble from [ingest_coaches()].
#'
#' @return A cleaned tibble, one row per head-coach-season.
#' @export
clean_coaches <- function(coaches) {
  coaches |>
    dplyr::transmute(
      coach_id = .data$id,
      coach_name = paste(.data$firstName, .data$lastName),
      school = .data$seasons_school,
      conference = .data$seasons_conference,
      season = as.integer(.data$seasons_year),
      games = .data$seasons_games,
      wins = .data$seasons_wins,
      losses = .data$seasons_losses,
      srs = .data$seasons_srs,
      sp_overall = .data$seasons_spOverall,
      sp_offense = .data$seasons_spOffense,
      sp_defense = .data$seasons_spDefense
    )
}

#' Clean team metadata
#'
#' Standardizes the `/teams` dimension for a **name join** on `team` (= CFBD
#' `school`), which is the same namespace as `player_stats.team` and the coach
#' join (decision 0008). The key cleaning step is **deduping to one row per
#' school**: `/teams` contains duplicate school names (a real program plus a
#' phantom row with `NA` classification and no logos); a naive join would fan
#' out. We keep the row with a real `classification`, then the one that has a
#' logo, dropping the phantom. Logo URLs were flattened at ingest; a handful of
#' small programs carry no logo and are left `NA` (placeholder at display time).
#'
#' @param teams Raw teams tibble from [ingest_teams()] (already flat).
#'
#' @return A cleaned tibble, one row per `team`, with colors and logo URLs.
#' @export
clean_teams <- function(teams) {
  teams |>
    # Prefer the real program (non-NA classification), then the row with a logo.
    dplyr::arrange(
      .data$school,
      is.na(.data$classification),
      is.na(.data$logo_light)
    ) |>
    dplyr::distinct(.data$school, .keep_all = TRUE) |>
    dplyr::transmute(
      team = .data$school,
      team_id = .data$id,
      mascot = .data$mascot,
      abbreviation = .data$abbreviation,
      conference = .data$conference,
      classification = .data$classification,
      color = .data$color,
      alt_color = .data$alternateColor,
      logo_light = .data$logo_light,
      logo_dark = .data$logo_dark
    )
}

#' Clean rosters
#'
#' Standardizes roster physicals to the athlete-id key. Column names may vary by
#' CFBD version; this selects defensively via [dplyr::any_of()].
#'
#' A listed `weight` outside the plausible 100-500 lb range is an impossible
#' value — `0` is a missing-data placeholder in `/roster`, and other out-of-range
#' entries (e.g. `23`) are data-entry errors — so all are coerced to `NA`
#' (decision 0009 Outcome; matches the roster contract's 100-500 lb range).
#'
#' @param roster Raw roster tibble from [ingest_roster()].
#'
#' @return A cleaned roster tibble keyed by string `playerId` and `season`.
#' @export
clean_roster <- function(roster) {
  roster |>
    dplyr::mutate(playerId = as.character(.data$id)) |>
    dplyr::select(
      "playerId",
      "season",
      dplyr::any_of(c(
        "team",
        "position",
        "height",
        "weight",
        "jersey",
        "class_year",
        home_state = "homeState",
        home_city = "homeCity"
      ))
    ) |>
    dplyr::mutate(
      season = as.integer(.data$season),
      dplyr::across(
        dplyr::any_of("weight"),
        \(w) dplyr::if_else(w >= 100 & w <= 500, as.integer(w), NA_integer_)
      ),
      # Height (inches): same precedent as the weight/class_year coercions
      # (decision 0009) — a handful of data-entry errors (9, 50, 57 in) sit
      # outside the plausible 60-85 range and are coerced to NA.
      dplyr::across(
        dplyr::any_of("height"),
        \(h) dplyr::if_else(h >= 60 & h <= 85, as.integer(h), NA_integer_)
      ),
      # Older CFBD seasons return the queried YEAR in the eligibility-class
      # field (~124k rows with class_year == season). Anything outside the
      # plausible 1-5 class range is unmeasurable, so coerce to NA (same
      # precedent as the weight coercion, decision 0009).
      dplyr::across(
        dplyr::any_of("class_year"),
        \(cy) dplyr::if_else(cy >= 1 & cy <= 5, as.integer(cy), NA_integer_)
      )
    )
}

#' Clean high-school recruiting ratings
#'
#' Standardizes the raw recruiting feed to a **per-athlete** rating table keyed
#' by the string `playerId` (from `athleteId`). Recruits with no `athleteId`
#' cannot join the athlete-id namespace (decision 0003) and are dropped here
#' (~40% of the feed: never enrolled, JUCO/international, or unlinked).
#' Deduplicates to one row per athlete, keeping the highest `rating` (then
#' `stars`, then most recent class) since a player can appear in more than one
#' record/class — the same dedupe philosophy as [clean_teams()].
#'
#' The recruiting `athleteId` is **not** a reliable member of the shared
#' athlete-id namespace: it collides across different people (decision 0013), so
#' the join this table feeds must be name-guarded — see [link_recruiting()].
#'
#' @param recruiting Raw recruiting tibble from [ingest_recruiting()].
#'
#' @return A cleaned tibble, one row per recruited athlete, keyed by `playerId`.
#' @export
clean_recruiting <- function(recruiting) {
  recruiting |>
    dplyr::filter(!is.na(.data$athleteId)) |>
    dplyr::transmute(
      playerId = as.character(.data$athleteId),
      recruit_name = .data$name,
      hs_class = as.integer(.data$year),
      stars = as.integer(.data$stars),
      rating = as.double(.data$rating),
      national_rank = as.integer(.data$ranking),
      recruit_position = .data$position,
      committed_to = .data$committedTo
    ) |>
    dedupe_recruiting()
}

#' Keep one recruiting record per athlete
#'
#' The highest `rating`, then `stars`, then most recent class wins. Shared by
#' [clean_recruiting()] and the season-scoped refresh, which re-dedupes after
#' splicing a refreshed class into the published table ([splice_seasons()]).
#' A splice only sees each athlete's previously kept record, so it can differ
#' from a full re-clean when a refreshed record drops below one the published
#' table had already discarded; a full refresh resolves it.
#'
#' @param recruiting Cleaned recruiting rows (possibly several per athlete).
#' @return One row per `playerId`.
#' @keywords internal
dedupe_recruiting <- function(recruiting) {
  recruiting |>
    dplyr::arrange(
      .data$playerId,
      dplyr::desc(.data$rating),
      dplyr::desc(.data$stars),
      dplyr::desc(.data$hs_class)
    ) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE)
}

# ---- NFL outcomes via nflverse (decision 0014) ------------------------------

#' Clean NFL draft picks (nflverse)
#'
#' Standardizes the nflverse draft table to a curated, stable schema: the link
#' keys (`gsis_id`, `pfr_player_id`, `cfb_player_id`, plus the draft slot) and a
#' Pro-Football-Reference **career summary** (games, `seasons_started`, last
#' active season `to`, weighted/draft AV, Pro Bowls / All-Pro / HOF, and career
#' box-score totals). The source `car_av` is dropped — it arrives all-`NA` for
#' our window (decision 0014). Stat column names are aligned with
#' [clean_nfl_player_stats()] so the career and per-season tables share a
#' vocabulary.
#'
#' @param nfl_draft_picks Raw tibble from [ingest_nfl_draft_picks()].
#'
#' @return A cleaned tibble, one row per draft pick (unique on
#'   `season`/`round`/`pick`).
#' @export
clean_nfl_draft_picks <- function(nfl_draft_picks) {
  nfl_draft_picks |>
    dplyr::transmute(
      season = as.integer(.data$season),
      round = as.integer(.data$round),
      pick = as.integer(.data$pick),
      nfl_team = as.character(.data$team),
      gsis_id = as.character(.data$gsis_id),
      pfr_player_id = as.character(.data$pfr_player_id),
      cfb_player_id = as.character(.data$cfb_player_id),
      pfr_player_name = as.character(.data$pfr_player_name),
      position = as.character(.data$position),
      side = as.character(.data$side),
      college = as.character(.data$college),
      age = as.integer(.data$age),
      to = as.integer(.data$to),
      hof = as.logical(.data$hof),
      allpro = as.integer(.data$allpro),
      probowls = as.integer(.data$probowls),
      seasons_started = as.integer(.data$seasons_started),
      w_av = as.integer(.data$w_av),
      dr_av = as.integer(.data$dr_av),
      games = as.integer(.data$games),
      pass_completions = as.integer(.data$pass_completions),
      pass_attempts = as.integer(.data$pass_attempts),
      pass_yards = as.integer(.data$pass_yards),
      pass_tds = as.integer(.data$pass_tds),
      pass_ints = as.integer(.data$pass_ints),
      rush_atts = as.integer(.data$rush_atts),
      rush_yards = as.integer(.data$rush_yards),
      rush_tds = as.integer(.data$rush_tds),
      receptions = as.integer(.data$receptions),
      rec_yards = as.integer(.data$rec_yards),
      rec_tds = as.integer(.data$rec_tds),
      def_solo_tackles = as.integer(.data$def_solo_tackles),
      def_ints = as.integer(.data$def_ints),
      def_sacks = as.double(.data$def_sacks)
    )
}

#' Plausible ranges for combine measurables
#'
#' Bounds used by [clean_combine()] to coerce data-entry errors to `NA` and by
#' [contract_combine()] to enforce the same ranges (the roster weight/height
#' precedent, decision 0009). Units: inches, pounds, seconds, repetitions.
#'
#' @keywords internal
combine_ranges <- list(
  height = c(60, 85),
  weight = c(100, 500),
  forty = c(4.0, 6.5),
  bench = c(0, 60),
  vertical = c(10, 55),
  broad_jump = c(60, 160),
  cone = c(6.0, 10.0),
  shuttle = c(3.5, 6.0)
)

#' Clean NFL Scouting Combine results (nflverse)
#'
#' Standardizes the nflverse combine table (decision 0043): height `"6-2"` to
#' inches, numeric drills, integer draft slot. A drill the invitee did not run
#' stays `NA`, as do values outside [combine_ranges]. nflverse attaches draft
#' info by name, and a handful of invitees carry a **different year's** draft
#' slot (a namesake's pick: the combine is held in the spring of the draft year,
#' so `draft_year` must equal `season`); those draft columns and the `pfr_id`
#' that came with them are nulled rather than kept as a wrong-person label.
#'
#' @param combine Raw tibble from [ingest_combine()].
#'
#' @return A cleaned tibble, one row per combine invitee (unique on
#'   `season`/`player_name`/`school`/`pos`).
#' @export
clean_combine <- function(combine) {
  in_range <- function(x, col) {
    r <- combine_ranges[[col]]
    dplyr::if_else(x >= r[1] & x <= r[2], x, NA)
  }
  ht <- strsplit(as.character(combine$ht), "-", fixed = TRUE)
  height <- vapply(
    ht,
    \(p) {
      if (length(p) != 2) {
        return(NA_integer_)
      }
      suppressWarnings(as.integer(p[1]) * 12L + as.integer(p[2]))
    },
    integer(1)
  )
  out <- combine |>
    dplyr::transmute(
      season = as.integer(.data$season),
      player_name = as.character(.data$player_name),
      pos = as.character(.data$pos),
      school = as.character(.data$school),
      height = in_range(.env$height, "height"),
      weight = in_range(as.integer(round(.data$wt)), "weight"),
      forty = in_range(as.double(.data$forty), "forty"),
      bench = in_range(as.integer(.data$bench), "bench"),
      vertical = in_range(as.double(.data$vertical), "vertical"),
      broad_jump = in_range(as.double(.data$broad_jump), "broad_jump"),
      cone = in_range(as.double(.data$cone), "cone"),
      shuttle = in_range(as.double(.data$shuttle), "shuttle"),
      draft_year = as.integer(.data$draft_year),
      draft_round = as.integer(.data$draft_round),
      draft_ovr = as.integer(.data$draft_ovr),
      draft_team = as.character(.data$draft_team),
      pfr_id = as.character(.data$pfr_id),
      cfb_id = as.character(.data$cfb_id)
    )
  wrong_year <- !is.na(out$draft_year) & out$draft_year != out$season
  out$draft_team[wrong_year] <- NA_character_
  out$draft_year[wrong_year] <- NA_integer_
  out$draft_round[wrong_year] <- NA_integer_
  out$draft_ovr[wrong_year] <- NA_integer_
  # The PFR id arrives with the namesake's draft row, so it is wrong too.
  out$pfr_id[wrong_year] <- NA_character_
  out
}

#' Clean NFL rosters (nflverse)
#'
#' Standardizes nflverse rosters to one row per `gsis_id` × `season`, keeping
#' the fields needed to measure roster longevity and describe the player. Rows
#' with no `gsis_id` (unlinkable to the rest of nflverse) are dropped, and the
#' table is deduped to one row per player-season defensively.
#'
#' @param nfl_rosters Raw tibble from [ingest_nfl_rosters()].
#'
#' @return A cleaned tibble keyed by `gsis_id` and `season`.
#' @export
clean_nfl_rosters <- function(nfl_rosters) {
  nfl_rosters |>
    dplyr::filter(!is.na(.data$gsis_id)) |>
    dplyr::transmute(
      gsis_id = as.character(.data$gsis_id),
      season = as.integer(.data$season),
      # Player name kept (unlike the other id-only bridges) so an undrafted
      # college->NFL match can be name-guarded (there is no draft slot to key on
      # for UDFAs); see resolve_nfl_outcome().
      player_name = as.character(.data$full_name),
      nfl_team = as.character(.data$team),
      position = as.character(.data$position),
      status = as.character(.data$status),
      years_exp = as.integer(.data$years_exp),
      height = as.double(.data$height),
      # A weight of 0 is a missing-data placeholder (as in CFBD /roster,
      # decision 0009); a handful of other rows carry impossible values (e.g.
      # 18 or 1794 lbs). Coerce anything outside a plausible NFL range to NA.
      weight = dplyr::if_else(
        as.integer(.data$weight) < 100 | as.integer(.data$weight) > 500,
        NA_integer_,
        as.integer(.data$weight)
      ),
      college = as.character(.data$college),
      rookie_year = as.integer(.data$rookie_year)
    ) |>
    dplyr::arrange(.data$gsis_id, .data$season) |>
    dplyr::distinct(.data$gsis_id, .data$season, .keep_all = TRUE)
}

#' Clean NFL player stats (nflverse)
#'
#' Aggregates the long weekly nflverse stats to the **player-season** grain,
#' **regular season only** (decision 0014): one row per `gsis_id` × `season`
#' with season totals for the common passing / rushing / receiving / defensive
#' box-score categories, plus `games` (weeks with a recorded stat line — an
#' approximation of games played, not roster games). Stat column names match
#' [clean_nfl_draft_picks()]' career totals.
#'
#' @param nfl_player_stats Raw weekly tibble from [ingest_nfl_player_stats()].
#'
#' @return A cleaned tibble keyed by `gsis_id` and `season`.
#' @export
clean_nfl_player_stats <- function(nfl_player_stats) {
  nfl_player_stats |>
    dplyr::filter(.data$season_type == "REG", !is.na(.data$player_id)) |>
    dplyr::group_by(
      gsis_id = as.character(.data$player_id),
      season = as.integer(.data$season)
    ) |>
    dplyr::summarise(
      player_name = dplyr::first(.data$player_display_name),
      games = dplyr::n_distinct(.data$week),
      pass_completions = sum(.data$completions, na.rm = TRUE),
      pass_attempts = sum(.data$attempts, na.rm = TRUE),
      pass_yards = sum(.data$passing_yards, na.rm = TRUE),
      pass_tds = sum(.data$passing_tds, na.rm = TRUE),
      pass_ints = sum(.data$passing_interceptions, na.rm = TRUE),
      rush_atts = sum(.data$carries, na.rm = TRUE),
      rush_yards = sum(.data$rushing_yards, na.rm = TRUE),
      rush_tds = sum(.data$rushing_tds, na.rm = TRUE),
      targets = sum(.data$targets, na.rm = TRUE),
      receptions = sum(.data$receptions, na.rm = TRUE),
      rec_yards = sum(.data$receiving_yards, na.rm = TRUE),
      rec_tds = sum(.data$receiving_tds, na.rm = TRUE),
      def_solo_tackles = sum(.data$def_tackles_solo, na.rm = TRUE),
      def_sacks = sum(.data$def_sacks, na.rm = TRUE),
      def_ints = sum(.data$def_interceptions, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::transmute(
      .data$gsis_id,
      .data$player_name,
      .data$season,
      games = as.integer(.data$games),
      pass_completions = as.integer(.data$pass_completions),
      pass_attempts = as.integer(.data$pass_attempts),
      pass_yards = as.integer(.data$pass_yards),
      pass_tds = as.integer(.data$pass_tds),
      pass_ints = as.integer(.data$pass_ints),
      rush_atts = as.integer(.data$rush_atts),
      rush_yards = as.integer(.data$rush_yards),
      rush_tds = as.integer(.data$rush_tds),
      targets = as.integer(.data$targets),
      receptions = as.integer(.data$receptions),
      rec_yards = as.integer(.data$rec_yards),
      rec_tds = as.integer(.data$rec_tds),
      def_solo_tackles = as.integer(.data$def_solo_tackles),
      def_sacks = as.double(.data$def_sacks),
      def_ints = as.integer(.data$def_ints)
    )
}

# ---- game statistics (see R/ingest.R for the /games family) -----------------

#' Clean game metadata
#'
#' Coerces period/identifier columns to integer and flag columns to logical so
#' the parquet schema matches inst/dict/games.yml. `stat`-like columns are not
#' present here; Elo, win probability, and excitement remain double.
#'
#' @param games Raw games tibble from [ingest_games()].
#'
#' @return A cleaned games tibble, one row per game, keyed by integer `id`.
#' @export
clean_games <- function(games) {
  games |>
    dplyr::transmute(
      id = as.integer(.data$id),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      seasonType = as.character(.data$seasonType),
      startDate = as.character(.data$startDate),
      startTimeTBD = as.logical(.data$startTimeTBD),
      completed = as.logical(.data$completed),
      neutralSite = as.logical(.data$neutralSite),
      conferenceGame = as.logical(.data$conferenceGame),
      attendance = as.numeric(.data$attendance),
      venueId = as.integer(.data$venueId),
      venue_name = as.character(.data$venue_name),
      homeId = as.integer(.data$homeId),
      homeTeam = as.character(.data$homeTeam),
      homeClassification = as.character(.data$homeClassification),
      homeConference = as.character(.data$homeConference),
      homePoints = as.integer(.data$homePoints),
      homePregameElo = as.numeric(.data$homePregameElo),
      homePostgameElo = as.numeric(.data$homePostgameElo),
      homePostgameWinProbability = as.numeric(.data$homePostgameWinProbability),
      awayId = as.integer(.data$awayId),
      awayTeam = as.character(.data$awayTeam),
      awayClassification = as.character(.data$awayClassification),
      awayConference = as.character(.data$awayConference),
      awayPoints = as.integer(.data$awayPoints),
      awayPregameElo = as.numeric(.data$awayPregameElo),
      awayPostgameElo = as.numeric(.data$awayPostgameElo),
      awayPostgameWinProbability = as.numeric(.data$awayPostgameWinProbability),
      excitementIndex = as.numeric(.data$excitementIndex),
      notes = as.character(.data$notes)
    )
}

#' Clean team game statistics
#'
#' Coerces keys/counts to integer; `stat` stays string (same convention as
#' `player_stats`, whose values also arrive as strings from CFBD).
#'
#' @param game_team_stats Raw flattened team game stats from
#'   [ingest_game_team_stats()].
#'
#' @return A cleaned tibble, one row per team-game-category-stat.
#' @export
clean_game_team_stats <- function(game_team_stats) {
  game_team_stats |>
    dplyr::transmute(
      gameId = as.integer(.data$gameId),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      seasonType = as.character(.data$seasonType),
      teamId = as.integer(.data$teamId),
      team = as.character(.data$team),
      conference = as.character(.data$conference),
      homeAway = as.character(.data$homeAway),
      points = as.integer(.data$points),
      category = as.character(.data$category),
      stat = as.character(.data$stat)
    )
}

#' Clean player game statistics
#'
#' Coerces keys/counts to integer; `playerId` is already the string athlete id
#' (the shared namespace, decision 0003) from the flatten step.
#'
#' @param game_player_stats Raw flattened player game stats from
#'   [ingest_game_player_stats()].
#'
#' @return A cleaned tibble, one row per player-game-category-statType-stat.
#' @export
clean_game_player_stats <- function(game_player_stats) {
  game_player_stats |>
    dplyr::transmute(
      gameId = as.integer(.data$gameId),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      seasonType = as.character(.data$seasonType),
      team = as.character(.data$team),
      conference = as.character(.data$conference),
      homeAway = as.character(.data$homeAway),
      points = as.integer(.data$points),
      category = as.character(.data$category),
      statType = as.character(.data$statType),
      playerId = as.character(.data$playerId),
      player = as.character(.data$player),
      stat = as.character(.data$stat)
    )
}

# ---- play-by-play (see R/ingest.R for the /plays family) --------------------

#' Add any missing columns as `NA`
#'
#' Older seasons' `/plays` responses can omit a field entirely, and an unpulled
#' table (`NULL`) has no columns at all; padding first lets the cleaners'
#' `transmute()` always produce the full, typed schema (zero rows for `NULL`).
#'
#' @param x A data frame or `NULL`.
#' @param cols Column names the cleaner reads.
#' @return A tibble carrying every column in `cols`.
#' @keywords internal
with_cols <- function(x, cols) {
  x <- tibble::as_tibble(x %||% tibble::tibble())
  for (col in setdiff(cols, names(x))) {
    x[[col]] <- rep(NA, nrow(x))
  }
  x
}

#' Clean the play-type dimension
#'
#' Keeps CFBD's `Uncategorized` (999) and `placeholder` (70) rows: they are
#' part of the vocabulary plays are tagged with, so dropping them would orphan
#' those plays' `playTypeId`.
#'
#' @param play_types Raw tibble from [ingest_play_types()].
#' @return A tibble, one row per play type, keyed by integer `id`.
#' @export
clean_play_types <- function(play_types) {
  play_types |>
    with_cols(c("id", "text", "abbreviation")) |>
    dplyr::transmute(
      id = as.integer(.data$id),
      text = as.character(.data$text),
      abbreviation = as.character(.data$abbreviation)
    ) |>
    dplyr::arrange(.data$id)
}

#' Clean the play-stat-type dimension
#'
#' @param play_stat_types Raw tibble from [ingest_play_stat_types()].
#' @return A tibble, one row per play-stat type, keyed by integer `id`.
#' @export
clean_play_stat_types <- function(play_stat_types) {
  play_stat_types |>
    with_cols(c("id", "name")) |>
    dplyr::transmute(
      id = as.integer(.data$id),
      name = as.character(.data$name)
    ) |>
    dplyr::arrange(.data$id)
}

#' Clean plays
#'
#' Types every column to the schema in inst/dict/plays.yml. Play and drive ids
#' stay strings (CFBD concatenates the game id into them, past integer range);
#' `gameId` is an integer like `games.id`. `/plays` names the play type only
#' by text, so `playTypeId` is looked up from the dimension (`NA` for a text
#' the dimension does not carry).
#'
#' Situational fields are normalized to what the contract enforces: CFBD
#' marks non-scrimmage plays (kickoffs, extra points) `down = -1` through 2013
#' and `0` after, so `-1` becomes `0`; the few impossible values left
#' (`down` 5, `yardsToGoal` outside 0 to 100, `period` 0, more than 15
#' minutes on the clock; about 125 of 3.1 million plays) become `NA`.
#'
#' @param plays Raw plays from [ingest_plays_chunk()] (bound across weeks).
#' @param play_types Cleaned play-type dimension ([clean_play_types()]).
#' @return A tibble, one row per play, keyed by `id`.
#' @export
clean_plays <- function(plays, play_types) {
  cols <- c(
    "id",
    "gameId",
    "driveId",
    "season",
    "week",
    "seasonType",
    "driveNumber",
    "playNumber",
    "offense",
    "offenseConference",
    "offenseScore",
    "defense",
    "defenseConference",
    "defenseScore",
    "home",
    "away",
    "period",
    "clock_minutes",
    "clock_seconds",
    "offenseTimeouts",
    "defenseTimeouts",
    "yardline",
    "yardsToGoal",
    "down",
    "distance",
    "yardsGained",
    "scoring",
    "playType",
    "playText",
    "ppa",
    "wallclock"
  )
  na_outside <- function(x, lo, hi) replace(x, x < lo | x > hi, NA)
  plays |>
    with_cols(cols) |>
    dplyr::transmute(
      id = as.character(.data$id),
      gameId = as.integer(.data$gameId),
      driveId = as.character(.data$driveId),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      seasonType = as.character(.data$seasonType),
      driveNumber = as.integer(.data$driveNumber),
      playNumber = as.integer(.data$playNumber),
      offense = as.character(.data$offense),
      offenseConference = as.character(.data$offenseConference),
      offenseScore = as.integer(.data$offenseScore),
      defense = as.character(.data$defense),
      defenseConference = as.character(.data$defenseConference),
      defenseScore = as.integer(.data$defenseScore),
      home = as.character(.data$home),
      away = as.character(.data$away),
      period = na_outside(as.integer(.data$period), 1L, Inf),
      clock_minutes = na_outside(as.integer(.data$clock_minutes), 0L, 15L),
      clock_seconds = na_outside(as.integer(.data$clock_seconds), 0L, 59L),
      offenseTimeouts = as.integer(.data$offenseTimeouts),
      defenseTimeouts = as.integer(.data$defenseTimeouts),
      yardline = as.integer(.data$yardline),
      yardsToGoal = na_outside(as.integer(.data$yardsToGoal), 0L, 100L),
      down = na_outside(pmax(as.integer(.data$down), 0L), 0L, 4L),
      distance = as.integer(.data$distance),
      yardsGained = as.integer(.data$yardsGained),
      scoring = as.logical(.data$scoring),
      playTypeId = play_types$id[match(.data$playType, play_types$text)],
      playType = as.character(.data$playType),
      playText = as.character(.data$playText),
      ppa = as.double(.data$ppa),
      wallclock = as.character(.data$wallclock)
    )
}

#' Clean play stats
#'
#' Types every column to the schema in inst/dict/play_stats.yml. `athleteId`
#' is the shared CFBD athlete id (a string, like `roster$playerId`).
#' `/plays/stats` names the stat type only by text, so `statTypeId` is looked
#' up from the dimension. `NULL` (no season pulled yet) gives the empty,
#' typed table that is published until the first per-game pull.
#'
#' @param play_stats Raw play stats from [ingest_play_stats_chunk()], or
#'   `NULL`.
#' @param play_stat_types Cleaned dimension ([clean_play_stat_types()]).
#' @return A tibble, one row per athlete-play-stat, keyed by
#'   `(playId, athleteId, statTypeId)`.
#' @export
clean_play_stats <- function(play_stats, play_stat_types) {
  cols <- c(
    "gameId",
    "season",
    "week",
    "team",
    "conference",
    "opponent",
    "teamScore",
    "opponentScore",
    "driveId",
    "playId",
    "period",
    "clock_minutes",
    "clock_seconds",
    "yardsToGoal",
    "down",
    "distance",
    "athleteId",
    "athleteName",
    "statType",
    "stat"
  )
  play_stats |>
    with_cols(cols) |>
    dplyr::transmute(
      gameId = as.integer(.data$gameId),
      season = as.integer(.data$season),
      week = as.integer(.data$week),
      team = as.character(.data$team),
      conference = as.character(.data$conference),
      opponent = as.character(.data$opponent),
      teamScore = as.integer(.data$teamScore),
      opponentScore = as.integer(.data$opponentScore),
      driveId = as.character(.data$driveId),
      playId = as.character(.data$playId),
      period = as.integer(.data$period),
      clock_minutes = as.integer(.data$clock_minutes),
      clock_seconds = as.integer(.data$clock_seconds),
      yardsToGoal = as.integer(.data$yardsToGoal),
      down = as.integer(.data$down),
      distance = as.integer(.data$distance),
      athleteId = as.character(.data$athleteId),
      athleteName = as.character(.data$athleteName),
      statTypeId = play_stat_types$id[
        match(.data$statType, play_stat_types$name)
      ],
      statType = as.character(.data$statType),
      stat = as.double(.data$stat)
    )
}

#' Build the published play-stats table
#'
#' The per-game pull is opt-in ([play_stats_enabled()]), so most refreshes
#' must leave the published table exactly as it is. When seasons were pulled,
#' they are spliced in ([splice_seasons()]); otherwise the published file is
#' kept, or, before any pull exists, the empty typed table is written.
#'
#' @param raw Raw play stats for the pulled seasons, or `NULL` (not pulled).
#' @param play_stat_types Cleaned dimension ([clean_play_stat_types()]).
#' @param path The published parquet.
#' @param seasons The seasons `raw` covers.
#' @return The play-stats table to publish.
#' @keywords internal
assemble_play_stats <- function(raw, play_stat_types, path, seasons) {
  if (!is.null(raw)) {
    return(splice_seasons(
      clean_play_stats(raw, play_stat_types),
      path,
      "season",
      seasons
    ))
  }
  if (file.exists(path)) {
    return(arrow::read_parquet(path))
  }
  clean_play_stats(NULL, play_stat_types)
}
