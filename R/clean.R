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
