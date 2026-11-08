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
#' Refresh mode is opt-in via the `CFB2NFL_REFRESH` environment variable so the
#' pipeline can run offline against committed/downloaded parquet by default
#' (decision 0017). The site build and ordinary analysis leave it unset.
#'
#' @return `TRUE` when `CFB2NFL_REFRESH` is set to a truthy value.
#' @keywords internal
refresh_enabled <- function() {
  isTRUE(as.logical(Sys.getenv("CFB2NFL_REFRESH", "false")))
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
      "i" = "Set {.envvar CFB2NFL_REFRESH=true} to ingest it, or download the {.val data-latest} release."
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
cfbd_request <- function(
  endpoint,
  query = list(),
  throttle = NULL,
  retry_max_tries = 5,
  retry_max_seconds = 120
) {
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
    httr2::req_user_agent("cfb2nfl (https://github.com)") |>
    # 429/503 are transient by default; broaden to all server-side 5xx. 5
    # tries with exponential backoff (~1s..16s) rides out short outages
    # without dragging a refresh for minutes per call. High-volume pulls
    # (the /games family) pass a longer retry budget instead of relying on
    # backoff alone.
    httr2::req_retry(
      max_tries = retry_max_tries,
      max_seconds = retry_max_seconds,
      is_transient = \(resp) {
        # Any 5xx (CFBD has thrown 525 Cloudflare errors alongside the usual
        # 500/502/503/504) plus the 429 rate limit.
        httr2::resp_status(resp) == 429 || httr2::resp_status(resp) >= 500
      }
    )
  # Paced cadence (requests per second) for high-volume endpoints; requests
  # without `throttle` are unaffected. All throttled requests share httr2's
  # realm, so the pacing holds across the whole refresh process.
  if (!is.null(throttle)) {
    req <- req |> httr2::req_throttle(rate = throttle)
  }
  if (length(query)) {
    req <- httr2::req_url_query(req, !!!query)
  }
  req
}

#' Log a CFBD call when a call log is configured
#'
#' Appends one line (time, endpoint, query) to the file named by
#' `CFB2NFL_CALL_LOG`, if set, so a refresh can report how many calls it made
#' against the monthly quota (decision 0034). Retries inside one call are not
#' counted separately.
#'
#' @param endpoint API path.
#' @param query Named list of query parameters.
#' @return `NULL`, invisibly.
#' @keywords internal
cfbd_log_call <- function(endpoint, query = list()) {
  log <- Sys.getenv("CFB2NFL_CALL_LOG")
  if (nzchar(log)) {
    q <- paste(names(query), unlist(query), sep = "=", collapse = "&")
    cat(
      format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
      "\t",
      endpoint,
      "\t",
      q,
      "\n",
      file = log,
      append = TRUE,
      sep = ""
    )
  }
  invisible(NULL)
}

#' Perform an authenticated CFBD API request
#'
#' Performs the request from [cfbd_request()] and returns the parsed body as a
#' tibble.
#'
#' @param endpoint API path, e.g. `"/draft/picks"`.
#' @param query Named list of query parameters (optional).
#' @param throttle Optional pacing in requests per second (e.g. `0.5` = one
#'   call every 2 s) for high-volume endpoints; `NULL` (default) paces nothing.
#' @param retry_max_tries,retry_max_seconds Retry policy passed through to
#'   [cfbd_request()].
#'
#' @return A tibble of the (vector-simplified) JSON response.
#' @keywords internal
cfbd_get <- function(
  endpoint,
  query = list(),
  throttle = NULL,
  retry_max_tries = 5,
  retry_max_seconds = 120
) {
  rlang::check_installed(c("httr2", "tibble"), reason = "to call the CFBD API.")
  cfbd_log_call(endpoint, query)
  cfbd_request(
    endpoint,
    query,
    throttle = throttle,
    retry_max_tries = retry_max_tries,
    retry_max_seconds = retry_max_seconds
  ) |>
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

#' Ingest NFL Scouting Combine results (nflverse)
#'
#' Pulls nflverse combine results (`nflreadr::load_combine()`): one row per
#' combine invitee, with measurables (height, weight, 40, bench, vertical,
#' broad jump, 3-cone, shuttle) and, for drafted invitees, the draft slot. No
#' API key. nflverse publishes every combine year in one file, so the whole
#' table is read and filtered to `seasons`; a combine year that hasn't happened
#' yet is simply absent. Linked to CFBD athlete ids by [link_combine()]
#' (decision 0043).
#'
#' @param seasons Integer vector of combine years (== draft years; default
#'   2010:2026).
#'
#' @return A tibble, one row per combine invitee.
#' @export
ingest_combine <- function(seasons = 2010:2026) {
  rlang::check_installed("nflreadr", reason = "to pull nflverse combine data.")
  nflreadr::load_combine() |>
    tibble::as_tibble() |>
    dplyr::filter(.data$season %in% as.integer(seasons))
}

# ---- game statistics (CFBD /games family) ----------------------------------
#
# Three endpoints, three grains (see inst/dict/games*.yml):
#   /games         -> `games`: one row per game (metadata: date, venue, points)
#   /games/teams   -> `game_team_stats`: one team-game-category-stat row
#   /games/players -> `game_player_stats`: one player-game-category-stat row
# /games/players carries the athlete `id`, so it joins the shared playerId
# namespace directly (decision 0003); the flattened rows attach `season`,
# `week`, `seasonType` from the loop so each table is self-describing.
#
# These pulls make ~700 week-level calls per season sweep, far more than the
# rest of the refresh combined, so they are paced (1 call / 1 s, shared httr2
# realm) and carry a longer retry budget: CFBD sheds load with 429/503 under
# sustained bursts, and the base 5-try/2-min policy (decision 0028) exhausts
# before the limit window resets.
cfbd_game_throttle <- 1
cfbd_game_retry_tries <- 10L
cfbd_game_retry_seconds <- 600

cfbd_game_get <- function(endpoint, query = list()) {
  cfbd_get(
    endpoint,
    query,
    throttle = cfbd_game_throttle,
    retry_max_tries = cfbd_game_retry_tries,
    retry_max_seconds = cfbd_game_retry_seconds
  )
}

#' Season weeks actually played, by season type
#'
#' Bowl/postseason weeks reuse low week numbers (CFBP rounds are week 1+ under
#' `seasonType = "postseason"`), so weeks must be discovered per season type
#' from the `/games` listing rather than assumed.
#'
#' @param year Season year.
#' @return Integer vector of weeks with at least one game.
#' @keywords internal
cfbd_season_weeks <- function(year) {
  purrr::map(c("regular", "postseason"), \(st) {
    games <- cfbd_game_get("/games", list(year = year, seasonType = st))
    # An unplayed season type returns an empty body (no columns at all).
    if (!nrow(games) || !"week" %in% names(games)) {
      return(integer(0))
    }
    dplyr::pull(games, .data$week) |>
      unique() |>
      sort()
  }) |>
    purrr::set_names(c("regular", "postseason"))
}

#' Played weeks for one season, from the ingested games table when available
#'
#' Same contract as [cfbd_season_weeks()], but derives the weeks from the
#' already-ingested `games` tibble (columns `season`, `seasonType`, `week`) so
#' the stats ingests don't re-pull `/games` — 34 calls saved per refresh.
#'
#' @param year Season year.
#' @param games Ingested `/games` tibble, or `NULL` to fall back to
#'   [cfbd_season_weeks()].
#' @return Named list of integer week vectors by season type.
#' @keywords internal
weeks_for_year <- function(year, games) {
  if (is.null(games)) {
    return(cfbd_season_weeks(year))
  }
  g <- games[games$season == year, ]
  purrr::map(c("regular", "postseason"), \(st) {
    sort(unique(dplyr::pull(g[g$seasonType == st, ], .data$week)))
  }) |>
    purrr::set_names(c("regular", "postseason"))
}

#' Flatten one /games/players response to player-game-stat rows
#'
#' The raw response nests teams -> categories -> types -> athletes; each athlete
#' entry carries the shared CFBD athlete id. Unnested rows are tagged with the
#' season/week/seasonType of the pull so the table needs no join to `games` for
#' basic period filters.
#'
#' @param raw One `/games/players` tibble (list-column grain: one row per game).
#' @param season Season year of the pull.
#' @param week Week number of the pull.
#' @param season_type `regular` or `postseason`.
#' @return A flat tibble, one row per player-game-category-statType-stat.
#' @keywords internal
flatten_game_player_stats <- function(raw, season, week, season_type) {
  purrr::map_dfr(seq_len(nrow(raw)), \(i) {
    game_id <- raw$id[[i]]
    teams <- raw$teams[[i]]
    purrr::map_dfr(seq_len(nrow(teams)), \(j) {
      t <- teams[j, ]
      cats <- t$categories[[1]]
      purrr::map_dfr(seq_len(nrow(cats)), \(k) {
        ty <- cats$types[[k]]
        purrr::map_dfr(seq_len(nrow(ty)), \(m) {
          # One row per athlete: a stat type lists every player who recorded
          # it, so take the whole columns, not their first element.
          athlete <- ty$athletes[[m]]
          tibble::tibble(
            gameId = game_id,
            season = season,
            week = week,
            seasonType = season_type,
            team = t$team,
            conference = t$conference,
            homeAway = t$homeAway,
            points = t$points,
            category = cats$name[[k]],
            statType = ty$name[[m]],
            playerId = as.character(athlete$id),
            player = as.character(athlete$name),
            stat = as.character(athlete$stat)
          )
        })
      })
    })
  })
}

#' Flatten one /games/teams response to team-game-stat rows
#'
#' Same nesting as the player endpoint, but `types` is a plain category/stat
#' frame per team (no per-player block).
#'
#' @inheritParams flatten_game_player_stats
#' @return A flat tibble, one row per team-game-category-stat.
#' @keywords internal
flatten_game_team_stats <- function(raw, season, week, season_type) {
  purrr::map_dfr(seq_len(nrow(raw)), \(i) {
    game_id <- raw$id[[i]]
    teams <- raw$teams[[i]]
    purrr::map_dfr(seq_len(nrow(teams)), \(j) {
      t <- teams[j, ]
      stats <- t$stats[[1]]
      tibble::tibble(
        gameId = game_id,
        season = season,
        week = week,
        seasonType = season_type,
        teamId = t$teamId,
        team = t$team,
        conference = t$conference,
        homeAway = t$homeAway,
        points = t$points,
        category = stats$category,
        stat = stats$stat
      )
    })
  })
}

#' Ingest game metadata
#'
#' Pulls `/games` for the given seasons, both season types (regular +
#' postseason). One row per game with venue, kickoff, points, Elo, and win
#' probability. List columns (`homeLineScores`/`awayLineScores` quarter scores,
#' `highlights`, `playoff`) are dropped so the parquet stays flat.
#'
#' @param years Integer vector of seasons (default 2010:2026).
#'
#' @return A flat tibble, one row per game, keyed by `id`.
#' @export
ingest_games <- function(years = 2010:2026) {
  as.integer(years) |>
    purrr::map(\(y) {
      purrr::map(c("regular", "postseason"), \(st) {
        raw <- cfbd_game_get("/games", list(year = y, seasonType = st))
        # Unplayed season types return an empty body (no columns at all);
        # contributing NULL keeps downstream list_rbind() happy.
        if (!nrow(raw)) {
          return(NULL)
        }
        raw |>
          # `venue` is a flat venue-name string (venueId is top-level already).
          dplyr::mutate(venue_name = as.character(.data$venue)) |>
          dplyr::select(-dplyr::any_of("venue"))
      }) |>
        purrr::list_rbind()
    }) |>
    purrr::list_rbind() |>
    dplyr::select(
      -dplyr::any_of(c(
        "homeLineScores",
        "awayLineScores",
        "highlights",
        "playoff"
      ))
    )
}

#' Ingest team game statistics
#'
#' Pulls `/games/teams` week by week (weeks derived from the ingested `games`
#' table when supplied, otherwise re-discovered from `/games`) and flattens to
#' one row per team-game-category-stat. A season with no played weeks yet
#' (e.g. a future season) contributes no rows.
#'
#' @param years Integer vector of seasons (default 2010:2026).
#' @param games Optional ingested `games` tibble (the `raw_games` target) used
#'   to derive played weeks without re-pulling `/games`.
#'
#' @return A flat tibble, one row per team-game-category-stat.
#' @export
ingest_game_team_stats <- function(years = 2010:2026, games = NULL) {
  as.integer(years) |>
    purrr::map(\(y) {
      weeks <- weeks_for_year(y, games)
      purrr::imap(weeks, \(wks, st) {
        purrr::map(wks, \(w) {
          # Pacing comes from cfbd_game_get()'s req_throttle (1 call / 1 s);
          # no extra sleep here or the ingest doubles its wall time.
          raw <- cfbd_game_get(
            "/games/teams",
            list(
              year = y,
              week = w,
              seasonType = st
            )
          )
          flatten_game_team_stats(raw, y, w, st)
        })
      }) |>
        purrr::list_flatten() |>
        purrr::list_rbind()
    }) |>
    purrr::list_rbind()
}

# ---- dynamic-branching chunks (decision 0029) ------------------------------
#
# The targets pipeline maps these one-call helpers over (season x season type)
# and (season x season type x week) grids, so a failed week pull resumes where
# it left off instead of re-ingesting the whole sweep. The full-table
# ingest_*() functions above stay as the programmatic API.

#' Ingest game metadata for one season and season type
#'
#' One `/games` call; the per-season-type chunk target in `_targets.R` maps
#' over `season_type` so each call is cached independently (decision 0029).
#'
#' @param year Season year.
#' @param season_type `regular` or `postseason`.
#' @return A flat tibble of games, or `NULL` for an unplayed season type.
#' @keywords internal
ingest_games_chunk <- function(year, season_type) {
  raw <- cfbd_game_get("/games", list(year = year, seasonType = season_type))
  if (!nrow(raw)) {
    return(NULL)
  }
  raw |>
    # `venue` is a flat venue-name string (venueId is top-level already).
    dplyr::mutate(venue_name = as.character(.data$venue)) |>
    dplyr::select(-dplyr::any_of("venue"))
}

#' Ingest one week of team game statistics
#'
#' One `/games/teams` call for a single season/week/season-type, flattened via
#' [flatten_game_team_stats()] — the week-level branch target in `_targets.R`
#' maps over this (decision 0029).
#'
#' @inheritParams ingest_games_chunk
#' @param week Week number.
#' @return A flat tibble, one row per team-game-category-stat.
#' @keywords internal
ingest_game_team_stats_chunk <- function(year, week, season_type) {
  raw <- cfbd_game_get(
    "/games/teams",
    list(year = year, week = week, seasonType = season_type)
  )
  flatten_game_team_stats(raw, year, week, season_type)
}

#' Ingest one week of player game statistics
#'
#' One `/games/players` call for a single season/week/season-type, flattened
#' via [flatten_game_player_stats()] (decision 0029).
#'
#' @inheritParams ingest_game_team_stats_chunk
#' @return A flat tibble, one row per player-game-category-statType-stat.
#' @keywords internal
ingest_game_player_stats_chunk <- function(year, week, season_type) {
  raw <- cfbd_game_get(
    "/games/players",
    list(year = year, week = week, seasonType = season_type)
  )
  flatten_game_player_stats(raw, year, week, season_type)
}

#' Ingest player game statistics
#'
#' Pulls `/games/players` week by week (weeks derived from the ingested `games`
#' table when supplied, otherwise re-discovered from `/games`) and flattens to
#' one row per player-game-category-stat. The
#' athlete `id` becomes the string `playerId` key (decision 0003 namespace), so
#' this table joins `player_stats`/`roster` directly — no name guard needed.
#'
#' @param years Integer vector of seasons (default 2010:2026).
#' @param games Optional ingested `games` tibble (the `raw_games` target) used
#'   to derive played weeks without re-pulling `/games`.
#'
#' @return A flat tibble, one row per player-game-category-statType-stat.
#' @export
ingest_game_player_stats <- function(years = 2010:2026, games = NULL) {
  as.integer(years) |>
    purrr::map(\(y) {
      weeks <- weeks_for_year(y, games)
      purrr::imap(weeks, \(wks, st) {
        purrr::map(wks, \(w) {
          raw <- cfbd_game_get(
            "/games/players",
            list(
              year = y,
              week = w,
              seasonType = st
            )
          )
          flatten_game_player_stats(raw, y, w, st)
        })
      }) |>
        purrr::list_flatten() |>
        purrr::list_rbind()
    }) |>
    purrr::list_rbind()
}

# ---- play-by-play (CFBD /plays family, decision 0031) ----------------------
#
# Four endpoints, four tables (see inst/dict/play*.yml):
#   /plays/types       -> `play_types`: the play-type dimension (one call)
#   /plays/stats/types -> `play_stat_types`: the play-stat-type dimension
#   /plays             -> `plays`: one row per play, one call per week
#   /plays/stats       -> `play_stats`: one row per athlete-play-stat, one
#                         call per GAME (the week grain silently caps at
#                         2,000 rows), so ~1,700 calls per season
# All share the /games family pacing and retry budget. `play_stats` is pulled
# incrementally for the current season (new games plus a one-week re-pull,
# decision 0045); past seasons are opt-in ([play_stats_enabled()]).

#' Ingest the play-type dimension
#'
#' One `/plays/types` call: the 49 play types (`id`, `text`, `abbreviation`),
#' including CFBD's own `Uncategorized` (999) and `placeholder` (70) entries,
#' which are kept because plays can carry them.
#'
#' @return A tibble, one row per play type.
#' @export
ingest_play_types <- function() {
  cfbd_get("/plays/types")
}

#' Ingest the play-stat-type dimension
#'
#' One `/plays/stats/types` call: the 31 athlete-attribution stat types
#' (`id`, `name`) used by `/plays/stats`.
#'
#' @return A tibble, one row per play-stat type.
#' @export
ingest_play_stat_types <- function() {
  cfbd_get("/plays/stats/types")
}

#' Unnest the clock block of a /plays or /plays/stats response
#'
#' CFBD nests the game clock as `clock = {minutes, seconds}` (time remaining in
#' the period); this flattens it to `clock_minutes` / `clock_seconds` so the
#' parquet stays flat.
#'
#' @param raw One `/plays` or `/plays/stats` tibble.
#' @return `raw` with the clock columns flattened.
#' @keywords internal
unnest_clock <- function(raw) {
  clock <- raw$clock
  raw$clock <- NULL
  raw$clock_minutes <- if (is.data.frame(clock)) clock$minutes else NA_integer_
  raw$clock_seconds <- if (is.data.frame(clock)) clock$seconds else NA_integer_
  raw
}

#' Flatten one /plays response
#'
#' Unnests the clock ([unnest_clock()]) and stamps the season/week/seasonType
#' of the pull (`/plays` carries none of them), so the table needs no join to
#' `games` for period filters. An empty response (no plays that week) returns
#' `NULL`.
#'
#' @param raw One `/plays` tibble.
#' @param season Season year of the pull.
#' @param week Week number of the pull.
#' @param season_type `regular` or `postseason`.
#' @return A flat tibble, or `NULL` for an empty response.
#' @keywords internal
flatten_plays <- function(raw, season, week, season_type) {
  if (!nrow(raw)) {
    return(NULL)
  }
  raw <- unnest_clock(raw)
  raw$season <- season
  raw$week <- week
  raw$seasonType <- season_type
  raw
}

#' Ingest one week of plays
#'
#' One `/plays` call for a single season/week/season-type (no row cap at this
#' grain), flattened via [flatten_plays()]. The week-level branch target in
#' `_targets.R` maps over this, like the game-stats chunks (decision 0029).
#'
#' @inheritParams ingest_game_team_stats_chunk
#' @return A flat tibble, one row per play, or `NULL` for a week with none.
#' @keywords internal
ingest_plays_chunk <- function(year, week, season_type) {
  raw <- cfbd_game_get(
    "/plays",
    list(year = year, week = week, seasonType = season_type)
  )
  flatten_plays(raw, year, week, season_type)
}

#' Is the whole-season play-stats backfill switched on?
#'
#' `/plays/stats` costs one call per game (~1,700 per season), so pulling a
#' past season runs only when `CFB2NFL_PLAYS_STATS` is truthy (decision 0031,
#' Phase 2), and only for an explicit season selection: with the flag on, an
#' unset `CFB2NFL_REFRESH_SEASONS` (the full window, ~28,000 calls) is an
#' error. The current season does not need the flag; it is pulled game by game
#' as games are played ([play_stats_games_to_pull()], decision 0045).
#'
#' @param spec The seasons selector (see [refresh_seasons()]).
#' @return `TRUE` when the flag is set and the selection is narrower than the
#'   full window.
#' @keywords internal
play_stats_enabled <- function(
  spec = Sys.getenv("CFB2NFL_REFRESH_SEASONS", "")
) {
  on <- isTRUE(as.logical(Sys.getenv("CFB2NFL_PLAYS_STATS", "false")))
  if (on && refresh_is_full(spec, source = "play_stats")) {
    cli::cli_abort(c(
      "{.envvar CFB2NFL_PLAYS_STATS} is on for the full season window.",
      "i" = "Play stats cost one call per game (~2,100 per season); select seasons with {.envvar CFB2NFL_REFRESH_SEASONS}, e.g. {.val 2025}."
    ))
  }
  on
}

#' Games the play-stats pull should query
#'
#' Decision 0045. For the **current** season: every game with plays that the
#' published `play_stats` does not have yet (a game CFBD had not posted stats
#' for comes back empty, so it is retried on the next run), plus every game
#' that kicked off in the last `settle_days` days, re-pulled once so a
#' correction CFBD makes in the days after a game is picked up. For a **past**
#' season: every game with plays, but only when `backfill` is `TRUE`
#' ([play_stats_enabled()]); otherwise none.
#'
#' @param season One season.
#' @param plays_games Distinct `(season, gameId)` from `plays`.
#' @param games Cleaned games (`id`, `startDate`).
#' @param published_ids `gameId`s already in the published `play_stats`.
#' @param backfill Pull a whole past season?
#' @param settle_days Re-pull window, in days before `date`.
#' @param date The date of the pull.
#' @return An integer vector of game ids.
#' @keywords internal
play_stats_games_to_pull <- function(
  season,
  plays_games,
  games,
  published_ids,
  backfill = FALSE,
  settle_days = 8L,
  date = Sys.Date()
) {
  ids <- unique(plays_games$gameId[plays_games$season == season])
  if (season != current_season(date)) {
    return(if (isTRUE(backfill)) ids else integer())
  }
  kickoff <- as.Date(substr(games$startDate, 1L, 10L))
  recent <- games$id[!is.na(kickoff) & kickoff >= as.Date(date) - settle_days]
  ids[!ids %in% published_ids | ids %in% recent]
}

#' Ingest one season of play stats, game by game
#'
#' One `/plays/stats` call per `gameId` (the only query unit that returns a
#' complete game; the week grain is capped at 2,000 rows). Branched at season
#' grain in `_targets.R` with the games looped here, so a season does not mint
#' ~2,100 targets (decision 0031).
#'
#' @param game_ids Game ids to pull (one season's games with plays).
#' @return A flat tibble, one row per athlete-play-stat.
#' @keywords internal
ingest_play_stats_chunk <- function(game_ids) {
  purrr::map(unique(game_ids), \(g) {
    raw <- cfbd_game_get("/plays/stats", list(gameId = g))
    if (!nrow(raw)) {
      return(NULL)
    }
    # Unlike /plays, the response carries its own season and week.
    unnest_clock(raw)
  }) |>
    purrr::list_rbind()
}
