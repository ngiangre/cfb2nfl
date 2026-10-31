# Linking: assemble the player-season backbone and attach coach, conference-tier,
# and draft-outcome context by joining on stable keys (athlete id; school+season).
# Left joins throughout so the audit layer (decision 0005) can flag any silent
# row loss or unmatched keys.

#' Build the player-season backbone
#'
#' Collapses the long stats to one identity row per player-season-team
#' (dropping the category/statType/stat columns). This is the grain the
#' longitudinal change features and the draft outcome attach to.
#'
#' @param player_stats Cleaned long stats from [clean_player_stats()].
#'
#' @return A tibble, one row per `(playerId, season, team)`.
#' @export
build_player_season <- function(player_stats) {
  player_stats |>
    dplyr::distinct(
      .data$playerId,
      .data$player,
      .data$season,
      .data$team,
      .data$conference,
      .data$position
    )
}

#' Attach head-coach context to player-seasons
#'
#' Left-joins coaches on `school == team` and `season`. May introduce >1 row per
#' player-season if a school had multiple head coaches recorded in a year; the
#' audit layer reports any such row inflation.
#'
#' @param player_season Player-season backbone from [build_player_season()].
#' @param coaches Cleaned coaches from [clean_coaches()].
#'
#' @return `player_season` with coach columns attached.
#' @export
link_coaches <- function(player_season, coaches) {
  player_season |>
    dplyr::left_join(
      dplyr::rename(coaches, team = "school"),
      by = c("team", "season"),
      suffix = c("", "_coach"),
      # A school can have >1 head coach in a season (midseason changes); this
      # intentionally fans out and the audit layer reports the row inflation.
      relationship = "many-to-many"
    )
}

#' Attach season-aware conference tier
#'
#' Left-joins the `(season, conference) -> tier` lookup (decision 0003). Coverage
#' is guaranteed by [contract_conference_tiers()]; run that contract in the
#' pipeline so unmapped conferences fail fast rather than silently `NA`.
#'
#' @param player_season Player-season table with `season` and `conference`.
#' @param tiers Conference-tier lookup (`data/conference_tiers.parquet`).
#'
#' @return `player_season` with `tier` and `tier_label` attached.
#' @export
link_tiers <- function(player_season, tiers) {
  player_season |>
    dplyr::left_join(
      dplyr::select(tiers, "season", "conference", "tier", "tier_label"),
      by = c("season", "conference")
    )
}

#' Attach team display metadata (logos, colors)
#'
#' Left-joins the team dimension ([clean_teams()]) onto any table carrying a
#' `team` column, on the shared school-name key. This is a **display** helper for
#' the site/report (logos, colors), deliberately kept off the model path so logo
#' URLs never leak into features. Coverage is guaranteed by [contract_teams()];
#' a few small programs carry `NA` logo URLs (use a placeholder when rendering).
#'
#' @param x A table with a `team` column (e.g. the player-season backbone).
#' @param teams Cleaned team dimension from [clean_teams()].
#'
#' @return `x` with `logo_light`, `logo_dark`, `color`, `alt_color`, and team
#'   `mascot`/`abbreviation` attached.
#' @export
link_team_meta <- function(x, teams) {
  x |>
    dplyr::left_join(
      dplyr::select(
        teams,
        "team",
        "mascot",
        "abbreviation",
        "color",
        "alt_color",
        "logo_light",
        "logo_dark"
      ),
      by = "team"
    )
}

#' Attach the draft outcome
#'
#' Marks each player-season with whether that athlete was ever drafted and, if
#' so, the draft year/round/overall. Joins on the shared string `playerId`
#' (decision 0003). Outcome definition is refined in the features/model stages
#' (draft-eligible seasons only; out-of-time framing).
#'
#' `picks` carries the full NFL draft history (back to 1936) and CFBD reuses
#' `collegeAthleteId` across eras, so a modern player's id can match a pick from
#' decades earlier. Left unchecked that fans out the join (duplicating a
#' player-season) and falsely attributes an ancient draft to a current player
#' (decision 0011). Since a 2010-2026 college career can only lead to a
#' 2010-2027 draft, picks outside `draft_window` are dropped before the join —
#' this removes the pre-window collision artifacts entirely. The lookup is then
#' collapsed to **one pick per `playerId`** (most recent, a guard against any
#' future intra-window collision), so the join is strictly 1:1 on `playerId`,
#' adds no rows, and marks `drafted` only for a plausible in-window pick.
#'
#' @param player_season Player-season backbone.
#' @param picks Cleaned picks from [clean_picks()].
#' @param draft_window Integer vector of plausible draft years for players in
#'   the backbone; picks outside it are ignored. Defaults to `2010:2027` (the
#'   2010-2026 stats window plus the following spring's draft).
#'
#' @return `player_season` with `drafted`, `draft_year`, `draft_round`,
#'   `draft_overall`. Same row count as `player_season`.
#' @export
link_drafted <- function(player_season, picks, draft_window = 2010:2027) {
  draft_lookup <- picks |>
    dplyr::filter(
      !is.na(.data$playerId),
      .data$year %in% draft_window
    ) |>
    dplyr::transmute(
      .data$playerId,
      draft_year = .data$year,
      draft_round = .data$round,
      draft_overall = .data$overall
    ) |>
    # Guard against any future intra-window id collision: keep the most recent
    # pick so the lookup is one row per player (decision 0011).
    dplyr::arrange(.data$playerId, dplyr::desc(.data$draft_year)) |>
    dplyr::distinct(.data$playerId, .keep_all = TRUE)
  player_season |>
    dplyr::left_join(draft_lookup, by = "playerId") |>
    dplyr::mutate(drafted = !is.na(.data$draft_year))
}

#' Normalize a player name for guarded matching
#'
#' Lowercases, strips punctuation, collapses whitespace, and removes a trailing
#' generational suffix (Jr./Sr./II-V) so benign formatting differences don't
#' defeat a name-agreement check. Base R only (no new pipeline dependency).
#'
#' @param x Character vector of names.
#'
#' @return A normalized character vector.
#' @keywords internal
normalize_name <- function(x) {
  x <- tolower(x)
  # Drop periods/apostrophes so "T.J." matches "TJ" and "D'Andre" matches "DAndre".
  x <- gsub("[.'\u2019]", "", x)
  # Other separators (hyphens, etc.) become spaces so surnames still split.
  x <- gsub("[^a-z ]", " ", x)
  x <- gsub("\\s+", " ", trimws(x))
  x <- sub(" (jr|sr|ii|iii|iv|v)$", "", x)
  trimws(x)
}

#' Attach name-guarded high-school recruiting ratings
#'
#' Left-joins the per-athlete recruiting ratings ([clean_recruiting()]) onto the
#' player-season backbone on the string `playerId`, then **guards the join by
#' name**. The recruiting `athleteId` collides across different people
#' (decision 0013) — e.g. Cam Ward's id maps to a different recruit, Xavier Ward
#' — so a rating is trusted only when the recruiting name agrees with the
#' backbone `player` name after [normalize_name()]. Ratings from a
#' name-conflicting (wrong-person) link are set to `NA`; `recruit_matched`
#' records whether a validated rating was attached. The recruiting table is one
#' row per `playerId`, so the join is many-to-one and never inflates the
#' backbone.
#'
#' This is a display/feature enrichment kept off the model path for now (like
#' [link_team_meta()]); wiring HS rating into the model is future work.
#'
#' @param player_season Player-season backbone from [build_player_season()]
#'   (carries the athlete `player` name).
#' @param recruiting Cleaned recruiting ratings from [clean_recruiting()].
#'
#' @return `player_season` with `hs_stars`, `hs_rating`, `hs_national_rank`,
#'   `hs_class`, and `recruit_matched` attached. Same row count as
#'   `player_season`.
#' @export
link_recruiting <- function(player_season, recruiting) {
  player_season |>
    dplyr::left_join(recruiting, by = "playerId") |>
    dplyr::mutate(
      recruit_matched = !is.na(.data$recruit_name) &
        normalize_name(.data$player) == normalize_name(.data$recruit_name),
      hs_stars = dplyr::if_else(
        .data$recruit_matched,
        .data$stars,
        NA_integer_
      ),
      hs_rating = dplyr::if_else(
        .data$recruit_matched,
        .data$rating,
        NA_real_
      ),
      hs_national_rank = dplyr::if_else(
        .data$recruit_matched,
        .data$national_rank,
        NA_integer_
      ),
      hs_class = dplyr::if_else(
        .data$recruit_matched,
        .data$hs_class,
        NA_integer_
      )
    ) |>
    dplyr::select(
      -dplyr::any_of(c(
        "recruit_name",
        "stars",
        "rating",
        "national_rank",
        "recruit_position",
        "committed_to"
      ))
    )
}

#' Assemble a player's college-through-NFL trajectory spine
#'
#' For a small registry of subjects, builds one row per player-season across
#' both stages (college roster + NFL roster) and attaches a **data-backed draft
#' status**. Draft status keys on the reliable nflverse `gsis_id`: presence in
#' `nfl_draft_picks` means drafted (with the draft year/round/overall attached),
#' absence means the player entered the NFL undrafted. Because `gsis_id` is
#' nflverse's own namespace shared by both the subject registry and the draft
#' table, this join needs no name guard (unlike the CFBD-side bridges in
#' [link_nfl_draft()] / [link_recruiting()]).
#'
#' The source tables may be lazy `arrow` Datasets (the published
#' `data/*.parquet`, read on their **cleaned** schema — decision 0018 — so
#' `roster` uses `playerId`, `nfl_rosters` uses `nfl_team`, and NFL tables key on
#' `gsis_id`) or in-memory tibbles; the pipeline runs the same dplyr verbs over
#' either and `collect()`s at the end. This encapsulates the data pull a blog
#' post would otherwise inline (decision 0015).
#'
#' @param subjects A registry tibble with `who` (display name), `cfb_athlete_id`
#'   (CFBD athlete id, string), and `gsis_id` (nflverse id, string).
#' @param roster College roster source (cleaned `data/roster.parquet` schema:
#'   `playerId`, `season`, `team`).
#' @param nfl_rosters NFL roster source (cleaned `data/nfl_rosters.parquet`
#'   schema: `gsis_id`, `season`, `nfl_team`).
#' @param nfl_draft_picks NFL draft-pick source (cleaned
#'   `data/nfl_draft_picks.parquet` schema: `gsis_id`, `season`, `round`,
#'   `pick`). Lists drafted players only.
#'
#' @return A tibble, one row per subject player-season, with `who`,
#'   `cfb_athlete_id`, `season`, `team`, `stage` (`"College"`/`"NFL"`),
#'   `drafted` (logical), and `draft_year`/`draft_round`/`draft_overall`
#'   (`NA` for undrafted players), arranged by `who` then `season`.
#' @export
player_trajectory <- function(subjects, roster, nfl_rosters, nfl_draft_picks) {
  stopifnot(
    all(c("who", "cfb_athlete_id", "gsis_id") %in% names(subjects))
  )
  cfb_ids <- subjects$cfb_athlete_id
  gsis_ids <- subjects$gsis_id

  college <- roster |>
    dplyr::filter(.data$playerId %in% cfb_ids) |>
    dplyr::select(cfb_athlete_id = "playerId", "season", "team") |>
    dplyr::collect() |>
    dplyr::mutate(stage = "College")

  nfl <- nfl_rosters |>
    dplyr::filter(.data$gsis_id %in% gsis_ids) |>
    dplyr::distinct(.data$gsis_id, .data$season, .data$nfl_team) |>
    dplyr::collect() |>
    dplyr::rename(team = "nfl_team") |>
    dplyr::left_join(
      dplyr::select(subjects, "gsis_id", "cfb_athlete_id"),
      by = "gsis_id"
    ) |>
    dplyr::select("cfb_athlete_id", "season", "team") |>
    dplyr::mutate(stage = "NFL")

  # Drafted iff the nflverse gsis_id appears in the draft-pick table; collapse
  # to one row per player (a player is drafted at most once).
  draft_status <- nfl_draft_picks |>
    dplyr::filter(.data$gsis_id %in% gsis_ids) |>
    dplyr::select(
      "gsis_id",
      draft_year = "season",
      draft_round = "round",
      draft_overall = "pick"
    ) |>
    dplyr::collect() |>
    dplyr::distinct(.data$gsis_id, .keep_all = TRUE) |>
    dplyr::right_join(
      dplyr::select(subjects, "cfb_athlete_id", "gsis_id"),
      by = "gsis_id"
    ) |>
    dplyr::mutate(drafted = !is.na(.data$draft_year)) |>
    dplyr::select(
      "cfb_athlete_id",
      "drafted",
      "draft_year",
      "draft_round",
      "draft_overall"
    )

  dplyr::bind_rows(college, nfl) |>
    dplyr::left_join(
      dplyr::select(subjects, "who", "cfb_athlete_id"),
      by = "cfb_athlete_id"
    ) |>
    dplyr::left_join(draft_status, by = "cfb_athlete_id") |>
    dplyr::arrange(.data$who, .data$season)
}

#' Resolve a single player's NFL outcome (drafted or undrafted-signed)
#'
#' The general college->NFL bridge used by [player_dossier()]. Answers, for one
#' player, whether they reached the NFL and how: **drafted** (via the reliable
#' draft-slot bridge already in [link_nfl_draft()]) or **undrafted-signed** (via
#' a name-guarded match against `nfl_rosters`, which is the only way to catch a
#' UDFA — there is no draft slot to key on). This is deliberately an
#' **outcome/label** resolver kept off the model input path (leakage), and it
#' **never fabricates a link**: an ambiguous name match (multiple candidate
#' players that college/entry-window can't disambiguate) resolves to
#' `no-NFL-record` rather than a guessed id.
#'
#' Longevity (distinct NFL roster seasons, first/last season, career games) is
#' computed from the matched `gsis_id`; `right_censored` flags players whose last
#' roster season is the most recent one available (possibly still active), so
#' treat their longevity as a ">=" outcome (decision 0014).
#'
#' @param subject A one-row tibble/list with `playerId` (CFBD athlete id,
#'   string), `player` (name), and optionally `college` (CFBD school name) and
#'   `last_college_season` (int) used to bound the draft window and disambiguate
#'   name collisions.
#' @param picks_nfl CFBD picks bridged to nflverse ([link_nfl_draft()]).
#' @param nfl_rosters Cleaned NFL rosters ([clean_nfl_rosters()]); must carry
#'   `player_name`.
#' @param nfl_player_stats Cleaned NFL player-season stats
#'   ([clean_nfl_player_stats()]); used for career games.
#'
#' @return A one-row tibble: `nfl_status`
#'   (`drafted`/`undrafted-signed`/`no-NFL-record`), `nfl_match_method`
#'   (`slot`/`name`/`name+college`/`name+window`/`none`), `gsis_id`,
#'   `draft_year`/`draft_round`/`draft_overall`, `nfl_seasons`,
#'   `nfl_first_season`, `nfl_last_season`, `nfl_games`, `right_censored`, and a
#'   human `note`.
#' @export
resolve_nfl_outcome <- function(
  subject,
  picks_nfl,
  nfl_rosters,
  nfl_player_stats
) {
  stopifnot(all(c("playerId", "player") %in% names(subject)))
  pid <- as.character(subject$playerId[[1]])
  nm <- subject$player[[1]]
  coll <- if ("college" %in% names(subject)) {
    subject$college[[1]]
  } else {
    NA_character_
  }
  last_season <- if ("last_college_season" %in% names(subject)) {
    suppressWarnings(as.integer(subject$last_college_season[[1]]))
  } else {
    NA_integer_
  }

  picks_nfl <- dplyr::collect(picks_nfl)
  rosters <- nfl_rosters |>
    dplyr::select(
      "gsis_id",
      "player_name",
      "season",
      "college",
      "rookie_year"
    ) |>
    dplyr::collect()
  max_nfl_season <- suppressWarnings(max(rosters$season, na.rm = TRUE))

  longevity <- function(gsis) {
    if (is.na(gsis)) {
      return(list(
        seasons = NA_integer_,
        first = NA_integer_,
        last = NA_integer_,
        games = NA_integer_,
        censored = NA
      ))
    }
    seas <- rosters$season[rosters$gsis_id == gsis]
    seas <- seas[!is.na(seas)]
    games <- nfl_player_stats |>
      dplyr::filter(.data$gsis_id == gsis) |>
      dplyr::summarise(g = sum(.data$games, na.rm = TRUE)) |>
      dplyr::collect() |>
      dplyr::pull(.data$g)
    list(
      seasons = length(unique(seas)),
      first = if (length(seas)) min(seas) else NA_integer_,
      last = if (length(seas)) max(seas) else NA_integer_,
      games = if (length(games)) as.integer(games) else NA_integer_,
      censored = length(seas) > 0 && max(seas) >= max_nfl_season
    )
  }

  outcome <- function(status, method, gsis, dy, dr, do, note) {
    lg <- longevity(gsis)
    tibble::tibble(
      nfl_status = status,
      nfl_match_method = method,
      gsis_id = gsis,
      draft_year = as.integer(dy),
      draft_round = as.integer(dr),
      draft_overall = as.integer(do),
      nfl_seasons = lg$seasons,
      nfl_first_season = lg$first,
      nfl_last_season = lg$last,
      nfl_games = lg$games,
      right_censored = lg$censored,
      note = note
    )
  }

  # ---- drafted path: reliable draft-slot bridge (decision 0014) ----
  draft_rows <- dplyr::filter(picks_nfl, .data$playerId == pid)
  if (!is.na(last_season)) {
    # A career ending in season S drafts in S+1; bound to guard against the
    # cross-era collegeAthleteId reuse the picks table carries (decision 0011).
    draft_rows <- dplyr::filter(
      draft_rows,
      is.na(.data$year) |
        (.data$year >= last_season & .data$year <= last_season + 2L)
    )
  }
  draft_rows <- draft_rows |>
    dplyr::arrange(dplyr::desc(.data$year)) |>
    utils::head(1)
  if (nrow(draft_rows) == 1) {
    gsis <- draft_rows$gsis_id[[1]]
    return(outcome(
      "drafted",
      if (!is.na(gsis)) "slot" else "slot-unmatched",
      gsis,
      draft_rows$year[[1]],
      draft_rows$round[[1]],
      draft_rows$overall[[1]],
      if (!is.na(gsis)) {
        "Drafted; bridged to nflverse by draft slot."
      } else {
        "Drafted; no nflverse match at the draft slot (longevity unavailable)."
      }
    ))
  }

  # ---- undrafted path: name-guarded match against NFL rosters ----
  cands <- rosters |>
    dplyr::distinct(
      .data$gsis_id,
      .data$player_name,
      .data$college,
      .data$rookie_year
    ) |>
    dplyr::filter(normalize_name(.data$player_name) == normalize_name(nm))

  if (nrow(cands) == 0) {
    return(outcome(
      "no-NFL-record",
      "none",
      NA_character_,
      NA,
      NA,
      NA,
      "No drafted pick and no name match on an NFL roster."
    ))
  }

  method <- "name"
  if (dplyr::n_distinct(cands$gsis_id) > 1) {
    # Disambiguate a name collision by college, then by rookie-year window;
    # refuse to guess if neither resolves to a single player.
    narrowed <- cands
    if (!is.na(coll)) {
      by_college <- dplyr::filter(
        narrowed,
        normalize_name(.data$college) == normalize_name(coll)
      )
      if (dplyr::n_distinct(by_college$gsis_id) == 1) {
        narrowed <- by_college
        method <- "name+college"
      }
    }
    if (dplyr::n_distinct(narrowed$gsis_id) > 1 && !is.na(last_season)) {
      by_window <- dplyr::filter(
        narrowed,
        !is.na(.data$rookie_year) & .data$rookie_year == last_season + 1L
      )
      if (dplyr::n_distinct(by_window$gsis_id) == 1) {
        narrowed <- by_window
        method <- "name+window"
      }
    }
    if (dplyr::n_distinct(narrowed$gsis_id) != 1) {
      return(outcome(
        "no-NFL-record",
        "none",
        NA_character_,
        NA,
        NA,
        NA,
        paste0(
          "Ambiguous NFL name match (",
          dplyr::n_distinct(cands$gsis_id),
          " candidates); not linked to avoid a false attribution."
        )
      ))
    }
    cands <- narrowed
  }

  gsis <- unique(cands$gsis_id)[[1]]
  outcome(
    "undrafted-signed",
    method,
    gsis,
    NA,
    NA,
    NA,
    paste0("Undrafted; signed to an NFL roster (matched by ", method, ").")
  )
}

#' Bridge CFBD picks to nflverse ids and NFL outcomes
#'
#' Attaches nflverse player ids and headline NFL-career outcomes to CFBD `picks`
#' by **draft slot** — CFBD `(year, round, overall)` == nflverse
#' `(season, round, pick)`. This is the reliable bridge: CFBD `nflAthleteId` is a
#' different id namespace (0 of 4,350 recent picks match nflverse `espn_id`) and
#' name-only matching is collision-prone, whereas the slot join matched
#' 4,350/4,350 recent picks (99.7% carrying a `pfr_player_id`); decision 0014.
#'
#' A [normalize_name()] guard (as in [link_recruiting()], decision 0013) nulls
#' the attached ids/outcomes whenever the CFBD and PFR names disagree, flagged by
#' `nfl_matched`; benign suffix/nickname differences (Will Anderson Jr. ↔ Will
#' Anderson) pass. The nflverse table is unique per slot, so the join is
#' many-to-one and never inflates `picks`. Picks outside the nflverse window
#' (e.g. pre-2010) simply find no slot and stay unmatched.
#'
#' Longevity note (decision 0014): `nfl_to` (last active NFL season) and
#' `nfl_games` are **right-censored** for recent draft classes still active —
#' treat them as "≥" outcomes, not completed careers.
#'
#' @param picks Cleaned CFBD picks from [clean_picks()].
#' @param nfl_draft_picks Cleaned nflverse draft picks from
#'   [clean_nfl_draft_picks()].
#'
#' @return `picks` with `gsis_id`, `pfr_player_id`, `nfl_to`, `nfl_games`,
#'   `nfl_seasons_started`, and the `nfl_matched` flag attached. Same row count
#'   as `picks`.
#' @export
link_nfl_draft <- function(picks, nfl_draft_picks) {
  lookup <- nfl_draft_picks |>
    dplyr::transmute(
      year = .data$season,
      round = .data$round,
      overall = .data$pick,
      gsis_id = .data$gsis_id,
      pfr_player_id = .data$pfr_player_id,
      nfl_name = .data$pfr_player_name,
      nfl_to = .data$to,
      nfl_games = .data$games,
      nfl_seasons_started = .data$seasons_started
    )
  picks |>
    dplyr::left_join(lookup, by = c("year", "round", "overall")) |>
    dplyr::mutate(
      nfl_matched = !is.na(.data$nfl_name) &
        normalize_name(.data$name) == normalize_name(.data$nfl_name),
      dplyr::across(
        c("gsis_id", "pfr_player_id"),
        \(x) dplyr::if_else(.data$nfl_matched, x, NA_character_)
      ),
      dplyr::across(
        c("nfl_to", "nfl_games", "nfl_seasons_started"),
        \(x) dplyr::if_else(.data$nfl_matched, x, NA_integer_)
      )
    ) |>
    dplyr::select(-dplyr::any_of("nfl_name"))
}

# Pick-level coach links: the blog-analysis grain. A head coach is associated
# with a draftee, not their sole developer (CFBD has no assistant data), so the
# verb throughout is "coached under", never "produced". Two attribution rules
# are supported side by side because they answer different questions and
# disagree for a large share of picks (see plans/coaches-draftees.md).

#' Link draft picks to the head coaches who coached them
#'
#' Joins draft picks to head-coach seasons through the roster backbone
#' (`playerId` -> `(season, team)` -> `(school, season)`), restricted to roster
#' seasons **before** the draft year. Two attribution rules:
#'
#' * `last`: only the coach(es) of the player's final roster season before the
#'   draft (credit for the finished product).
#' * `any`: every coach the player had at least one roster season with,
#'   counted once per pick (everyone who oversaw part of the development). No
#'   minimum-exposure threshold: one season is credit.
#'
#' Schools with multiple recorded head coaches in a season (mid-season
#' changes, interims) credit **all** of them; the result is association, not
#' sole attribution.
#'
#' @param picks Cleaned picks with `playerId`, `year`, `overall`, `position`,
#'   `name`. Picks without a `playerId` are dropped (id coverage is ~100%
#'   from draft year 2011 on).
#' @param roster Roster backbone (`playerId`, `season`, `team`).
#' @param coaches Cleaned coach-seasons (`school`, `season`, `coach_id`,
#'   `coach_name`).
#' @param rule Attribution rule: `"last"` or `"any"`.
#' @param reused Optional character vector of reused athlete ids (from
#'   [reused_ids()]) to exclude; NULL keeps everything.
#' @param draft_year_min Minimum draft year to include (roster coverage starts
#'   in 2010, so early classes have truncated observable careers).
#'
#' @return One row per `(year, overall, coach_id)`: the pick columns plus
#'   `team`, `season` (the crediting roster season), and coach columns.
#' @export
link_coaches_picks <- function(
  picks,
  roster,
  coaches,
  rule = c("last", "any"),
  reused = NULL,
  draft_year_min = 2011L
) {
  rule <- rlang::arg_match(rule)
  stopifnot(
    all(c("playerId", "year", "overall") %in% names(picks)),
    all(c("playerId", "season", "team") %in% names(roster)),
    all(c("school", "season", "coach_id", "coach_name") %in% names(coaches))
  )
  p <- picks |>
    dplyr::filter(!is.na(.data$playerId), .data$year >= .env$draft_year_min)
  if (!is.null(reused)) {
    p <- dplyr::filter(p, !.data$playerId %in% .env$reused)
  }
  seasons <- p |>
    dplyr::inner_join(
      dplyr::distinct(roster, .data$playerId, .data$season, .data$team),
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::filter(.data$season < .data$year)
  if (rule == "last") {
    seasons <- seasons |>
      dplyr::group_by(.data$year, .data$overall) |>
      dplyr::filter(.data$season == max(.data$season)) |>
      dplyr::ungroup()
  }
  seasons |>
    dplyr::inner_join(
      dplyr::distinct(
        coaches,
        .data$school,
        .data$season,
        .data$coach_id,
        .data$coach_name
      ),
      by = dplyr::join_by(team == school, season)
    ) |>
    dplyr::distinct(
      .data$year,
      .data$overall,
      .data$coach_id,
      .keep_all = TRUE
    ) |>
    dplyr::select(
      "year",
      "overall",
      "position",
      "name",
      "playerId",
      "team",
      "season",
      "coach_id",
      "coach_name"
    )
}
