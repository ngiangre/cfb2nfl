# Ingestion: pure functions that pull raw CFBD data and return tibbles.
# Writing to disk / parquet is the pipeline's job (see _targets.R), not these
# functions'. Refactored from the original data-raw/DATASET.R (decision 0004).

#' Base CFBD API URL
#'
#' @return The CFBD API base URL as a string.
#' @keywords internal
cfbd_base_url <- function() {
  "https://api.collegefootballdata.com"
}

#' Is the pipeline running in refresh (re-ingest) mode?
#'
#' Refresh mode is opt-in via the `CFBSTATS_REFRESH` environment variable so the
#' pipeline can run offline against committed/downloaded parquet by default
#' (decision 0017). The site build and ordinary analysis leave it unset.
#'
#' @return `TRUE` when `CFBSTATS_REFRESH` is set to a truthy value.
#' @keywords internal
refresh_enabled <- function() {
  isTRUE(as.logical(Sys.getenv("CFBSTATS_REFRESH", "false")))
}

#' Materialize (in refresh mode) or track a parquet data asset
#'
#' The pipeline's ingest targets call this (decision 0017). In **refresh mode**
#' ([refresh_enabled()]) it calls `build()` and writes the result to `path`; in
#' **track mode** (the default) it assumes `path` already exists — committed, or
#' downloaded from the `data-latest` release — and simply returns it, so the DAG
#' runs with no API key. Returned so a `format = "file"` target can track it.
#'
#' @param path Destination parquet path.
#' @param build A zero-argument function returning the table to write (e.g. an
#'   `ingest_*()` function). Only evaluated in refresh mode.
#'
#' @return `path` (returned visibly so a `format = "file"` target can track it).
#' @keywords internal
parquet_asset <- function(path, build) {
  if (refresh_enabled()) {
    rlang::check_installed("arrow", reason = "to write a parquet data asset.")
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    arrow::write_parquet(build(), path)
  } else if (!file.exists(path)) {
    cli::cli_abort(c(
      "Data asset {.path {path}} not found and refresh is off.",
      "i" = "Set {.envvar CFBSTATS_REFRESH=true} to ingest it, or download the {.val data-latest} release."
    ))
  }
  path
}

#' Build an authenticated CFBD API request
#'
#' Thin request builder over `httr2`: attaches the bearer token from the
#' `CFBD_API_KEY` environment variable and a retry policy (decision 0028) so
#' transient CFBD failures (rate limiting, 503 outages) are retried with
#' exponential backoff instead of failing the whole refresh — the weekly CI
#' refresh makes ~60 back-to-back calls and CFBD sheds load with 503s.
#'
#' @param endpoint API path, e.g. `"/draft/picks"`.
#' @param query Named list of query parameters (optional).
#'
#' @return An `httr2` request.
#' @keywords internal
cfbd_request <- function(endpoint, query = list()) {
  rlang::check_installed("httr2", reason = "to call the CFBD API.")
  key <- Sys.getenv("CFBD_API_KEY")
  if (!nzchar(key)) {
    cli::cli_abort(
      "{.envvar CFBD_API_KEY} is not set; cannot call the CFBD API."
    )
  }
  req <- httr2::request(cfbd_base_url()) |>
    httr2::req_url_path_append(endpoint) |>
    httr2::req_headers(Authorization = paste("Bearer", key)) |>
    httr2::req_user_agent("cfbstats (https://github.com)") |>
    # 429/503 are transient by default; broaden to all server-side 5xx. 5
    # tries with exponential backoff (~1s..16s) rides out short outages
    # without dragging a refresh for minutes per call.
    httr2::req_retry(
      max_tries = 5,
      max_seconds = 120,
      is_transient = \(resp) {
        httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
      }
    )
  if (length(query)) {
    req <- httr2::req_url_query(req, !!!query)
  }
  req
}

#' Perform an authenticated CFBD API request
#'
#' Performs the request from [cfbd_request()] and returns the parsed body as a
#' tibble.
#'
#' @param endpoint API path, e.g. `"/draft/picks"`.
#' @param query Named list of query parameters (optional).
#'
#' @return A tibble of the (vector-simplified) JSON response.
#' @keywords internal
cfbd_get <- function(endpoint, query = list()) {
  rlang::check_installed(c("httr2", "tibble"), reason = "to call the CFBD API.")
  cfbd_request(endpoint, query) |>
    httr2::req_perform() |>
    httr2::resp_body_json(simplifyVector = TRUE) |>
    tibble::as_tibble()
}

#' Ingest NFL draft picks
#'
#' Pulls `/draft/picks` and unnests the nested `hometownInfo` block. The draft
#' outcome table; `collegeAthleteId` is the (int) athlete key that joins to
#' player stats once coerced to string (decision 0003).
#'
#' @return A tibble, one row per drafted player.
#' @export
ingest_picks <- function() {
  rlang::check_installed("tidyr")
  cfbd_get("/draft/picks") |>
    tidyr::unnest(cols = "hometownInfo", names_sep = "_")
}

#' Ingest player season stats for one or more years
#'
#' Pulls `/stats/player/season` per year. Returns **long** data: one row per
#' player-season-category-statType-stat (decision 0003 / VISION §4).
#'
#' @param years Integer vector of seasons (default 2010:2026).
#'
#' @return A long tibble of player-season stats across `years`.
#' @export
ingest_player_stats <- function(years = 2010:2026) {
  rlang::check_installed("purrr")
  purrr::map(
    as.integer(years),
    \(y) cfbd_get("/stats/player/season", query = list(year = y))
  ) |>
    purrr::list_rbind()
}

#' Ingest high-school recruiting ratings for one or more years
#'
#' Pulls `/recruiting/players` per year: one row per HS recruit with the
#' industry `stars` (2-5), composite `rating` (~0.74-1.0), and national
#' `ranking`. The `athleteId` (string) is the CFBD athlete key that joins to
#' [ingest_roster()]'s `id` and, coerced from int, `picks$collegeAthleteId`
#' (decision 0003 namespace). Recruits with no `athleteId` (~50%: never
#' enrolled, JUCO/international, or unlinked) cannot be joined and are kept as-is
#' here; filtering is a cleaning/feature concern.
#'
#' @param years Integer vector of recruiting classes (default 2010:2026).
#'
#' @return A flat tibble, one row per recruit, with `hometownInfo` unnested.
#' @export
ingest_recruiting <- function(years = 2010:2026) {
  rlang::check_installed(c("purrr", "tidyr"))
  purrr::map(
    as.integer(years),
    \(y) cfbd_get("/recruiting/players", query = list(year = y))
  ) |>
    purrr::list_rbind() |>
    tidyr::unnest(cols = "hometownInfo", names_sep = "_")
}

#' Ingest head coaches
#'
#' Pulls `/coaches` and unnests the per-season `seasons` block. Head coaches
#' only (no coordinators / S&C); one row per head-coach-season.
#'
#' @return A tibble, one row per head-coach-season.
#' @export
ingest_coaches <- function() {
  rlang::check_installed("tidyr")
  cfbd_get("/coaches") |>
    tidyr::unnest(cols = "seasons", names_sep = "_")
}

#' Ingest team metadata (logos, colors, conference)
#'
#' Pulls `/teams` — the team **dimension** table, one row per program with
#' display metadata (colors, mascot, abbreviation, conference). The raw `logos`
#' block is a list of the same image at several resolutions in light and `-dark`
#' variants; like the other ingest functions (which unnest `hometownInfo` /
#' `seasons`), this flattens it here into `logo_light` / `logo_dark` so the
#' persisted parquet stays flat. Deduping duplicate school names is a cleaning
#' concern, handled in [clean_teams()].
#'
#' @return A flat tibble, one row per team row returned by `/teams` (school names
#'   may still repeat until [clean_teams()] dedupes them).
#' @export
ingest_teams <- function() {
  rlang::check_installed("purrr")
  first_match <- function(x, pattern) {
    if (length(x)) x[grep(pattern, x)][1] else NA_character_
  }
  cfbd_get("/teams") |>
    dplyr::transmute(
      id = .data$id,
      school = .data$school,
      mascot = .data$mascot,
      abbreviation = .data$abbreviation,
      conference = .data$conference,
      classification = .data$classification,
      color = .data$color,
      alternateColor = .data$alternateColor,
      logo_light = purrr::map_chr(
        .data$logos,
        first_match,
        pattern = "/logos/"
      ),
      logo_dark = purrr::map_chr(
        .data$logos,
        first_match,
        pattern = "/logos-dark/"
      )
    )
}

#' Ingest team rosters for one or more years
#'
#' Pulls `/roster` per year for per-season physicals (height, **weight**),
#' position, jersey, and hometown, keyed by athlete `id`. New for decision 0003:
#' the source for weight-change features and a full player-season backbone
#' (includes players with no qualifying stat line).
#'
#' The `season` is stamped from the queried year: the endpoint's own `year`
#' field is the player's **eligibility class** (1-5), not the season, so it is
#' renamed to `class_year` and never used as the season key.
#'
#' @param years Integer vector of seasons (default 2010:2026).
#'
#' @return A tibble, one row per player-season on a roster, with an authoritative
#'   `season` column.
#' @export
ingest_roster <- function(years = 2010:2026) {
  rlang::check_installed(c("purrr", "dplyr"))
  purrr::map(
    as.integer(years),
    \(y) {
      cfbd_get("/roster", query = list(year = y)) |>
        dplyr::rename(dplyr::any_of(c(class_year = "year"))) |>
        dplyr::mutate(season = y)
    }
  ) |>
    purrr::list_rbind()
}

# ---- NFL outcomes via nflverse (decision 0014) ------------------------------
# These pull post-draft NFL data from nflverse (nflreadr), *not* CFBD, so they
# take no API key. They are linked to CFBD picks by draft slot, never by the
# CFBD `nflAthleteId` (a different id namespace; decision 0014).

#' Ingest NFL draft picks (nflverse)
#'
#' Pulls nflverse's draft-pick table (`nflreadr::load_draft_picks()`). This is
#' the **bridge** from CFBD `picks` to nflverse player ids (`gsis_id`,
#' `pfr_player_id`) *and* a Pro-Football-Reference **career summary**: games,
#' seasons started, last active season (`to`), career box-score totals, and
#' Pro Bowl / All-Pro / Hall-of-Fame flags. Linked to CFBD `picks` by draft slot
#' — `(year, round, overall)` == `(season, round, pick)` — the reliable key,
#' since CFBD `nflAthleteId` is a different namespace (0/4350 recent picks match
#' nflverse `espn_id`) and name-only matching is collision-prone (decision 0014).
#'
#' @param seasons Integer vector of draft seasons (default 2010:2026).
#'
#' @return A tibble, one row per draft pick (unique on `season`/`round`/`pick`).
#' @export
ingest_nfl_draft_picks <- function(seasons = 2010:2026) {
  rlang::check_installed("nflreadr", reason = "to pull nflverse draft picks.")
  nflreadr::load_draft_picks(seasons = as.integer(seasons))
}

#' Ingest NFL rosters (nflverse)
#'
#' Pulls nflverse season rosters (`nflreadr::load_rosters()`): one row per
#' player-season on an NFL roster, keyed by `gsis_id`. This is the source for
#' the primary longevity measure — **distinct NFL seasons on a roster** — which,
#' unlike a stats-based definition, counts linemen / special-teamers / backups
#' who accrue no box-score stats (decision 0014).
#'
#' @param seasons Integer vector of NFL seasons (default 2010:2026).
#'
#' @return A tibble, one row per player-season on a roster.
#' @export
ingest_nfl_rosters <- function(seasons = 2010:2026) {
  rlang::check_installed("nflreadr", reason = "to pull nflverse rosters.")
  nflreadr::load_rosters(seasons = as.integer(seasons))
}

#' Ingest NFL player stats (nflverse)
#'
#' Pulls nflverse **weekly** player stats (`nflreadr::load_player_stats()`) for
#' the given seasons (regular + postseason). Returned long by player-week; the
#' aggregation to the player-season grain (regular season only) happens in
#' [clean_nfl_player_stats()] per the grain decision (decision 0014).
#'
#' Seasons in `seasons` for which nflverse stats exist are pulled; a not-yet-
#' played season (e.g. 2026 before kickoff) is skipped, since
#' `load_player_stats()` errors on future seasons.
#'
#' @param seasons Integer vector of NFL seasons (default 2010:2026).
#'
#' @return A wide tibble, one row per player-week (all nflverse stat columns).
#' @export
ingest_nfl_player_stats <- function(seasons = 2010:2026) {
  rlang::check_installed("nflreadr", reason = "to pull nflverse player stats.")
  seasons <- as.integer(seasons)
  # Drop seasons that haven't been played yet (no stats to pull).
  seasons <- seasons[seasons <= nflreadr::most_recent_season()]
  nflreadr::load_player_stats(seasons = seasons)
}
