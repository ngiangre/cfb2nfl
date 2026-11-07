# NFL Scouting Combine -> CFBD athlete id (decision 0043). nflverse combine
# rows carry no CFBD id, so they are linked in name-guarded tiers: the draft
# slot for drafted invitees (the link_nfl_draft() bridge), then name + school +
# final season for the rest. Measurables are PRE-DRAFT information: fair inputs
# for a draft-time model, never for the in-career forecasts.

# nflverse (PFR-style) school spellings that school_key()'s generic
# normalization can't reconcile with CFBD team names. Keys are normalized
# nflverse names; values are CFBD `team` strings.
combine_school_map <- c(
  "mississippi" = "Ole Miss",
  "miami (fl)" = "Miami",
  "miami (ohio)" = "Miami (OH)",
  "boston col" = "Boston College",
  "north carolina state" = "NC State",
  "central florida" = "UCF",
  "connecticut" = "UConn",
  "appalachian state" = "App State",
  "texas san antonio" = "UTSA",
  "texas el paso" = "UTEP",
  "tenn chattanooga" = "Chattanooga",
  "tennessee chattanooga" = "Chattanooga",
  "tennessee martin" = "UT Martin",
  "louisiana lafayette" = "Louisiana",
  "la monroe" = "UL Monroe",
  "louisiana monroe" = "UL Monroe",
  "ala birmingham" = "UAB",
  "alabama birmingham" = "UAB",
  "california davis" = "UC Davis",
  "ark pine bluff" = "Arkansas-Pine Bluff",
  "university of arkansas at pine bluff" = "Arkansas-Pine Bluff",
  "mcneese state" = "McNeese",
  "southeastern louisiana" = "SE Louisiana",
  "southern mississippi" = "Southern Miss",
  "louisiana state" = "LSU",
  "middle tenn state" = "Middle Tennessee",
  "middle tennessee state" = "Middle Tennessee",
  "nicholls state" = "Nicholls",
  "nw state (la)" = "Northwestern State",
  "northwestern state (la)" = "Northwestern State",
  "prairie view" = "Prairie View A&M",
  "sam houston state" = "Sam Houston",
  "southern utah state" = "Southern Utah",
  "stephen f austin state" = "Stephen F. Austin",
  "houston christian university" = "Houston Christian",
  "fayetteville state university" = "Fayetteville State",
  "grambling state" = "Grambling",
  "texas a&m commerce" = "East Texas A&M",
  "dixie state" = "Utah Tech",
  "brigham young" = "BYU",
  "southern california" = "USC",
  "southwest texas state" = "Texas State"
)

#' Normalize a school name for cross-source matching
#'
#' Reconciles nflverse/PFR school spellings ("Boston Col.", "Ohio St.",
#' "Miami (FL)") with CFBD `team` names ("Boston College", "Ohio State",
#' "Miami") so the two can be compared as keys: transliterates accents
#' ("San José"), expands `St.`/`East.`/`West.` abbreviations, drops a leading
#' "The" and punctuation, then applies a small hand-kept crosswalk for names
#' that differ outright ("Mississippi" / "Ole Miss"). Applied to both sides, so
#' compare `school_key(a) == school_key(b)`.
#'
#' @param x Character vector of school names.
#' @return A character vector of comparison keys (`NA` stays `NA`).
#' @keywords internal
school_key <- function(x) {
  base <- function(x) {
    x <- tolower(iconv(x, to = "ASCII//TRANSLIT"))
    x <- gsub("\u2013|\u2014", "-", x)
    x <- gsub("\\bst\\.?$", "state", x)
    x <- gsub("\\bst\\. ", "state ", x)
    x <- gsub("\\beast\\.", "eastern", x)
    x <- gsub("\\bwest\\.", "western", x)
    x <- gsub("\\bnorth\\.", "northern", x)
    x <- gsub("\\bsouth\\.", "southern", x)
    x <- gsub("^the ", "", x)
    x <- gsub("[.'`]", "", x)
    x <- gsub("[^a-z0-9&()]+", " ", x)
    trimws(gsub("\\s+", " ", x))
  }
  k <- base(x)
  mapped <- unname(combine_school_map[k])
  dplyr::if_else(is.na(mapped), k, base(mapped))
}

#' Link combine invitees to CFBD athlete ids
#'
#' nflverse combine rows carry no CFBD id, so each is matched in tiers, every
#' tier name-guarded (decision 0043), and the tier that matched is recorded in
#' `link_method`:
#'
#' 1. `"draft_slot"`: a drafted invitee's `(draft_year, draft_round,
#'    draft_ovr)` == CFBD `picks` `(year, round, overall)`, the bridge
#'    [link_nfl_draft()] uses. The names must be [name_variant()]s **or** the
#'    schools must agree, which admits nicknames ("Ziggy Ansah" / "Ezekiel
#'    Ansah") without trusting a slot whose school and name both disagree.
#'    A slot that more than one combine row claims (nflverse attached one
#'    pick to two namesakes) is ambiguous and skips this tier.
#' 2. `"name_school"`: otherwise, the CFBD player whose name agrees after
#'    [normalize_name()], whose last college season before the draft is
#'    `draft_year - 1` or `- 2`, and who was on a team matching `school`
#'    ([school_key()]) that season. Two or more candidates is ambiguous and
#'    links nothing (the [link_recruiting()] precedent, decision 0013).
#' 3. `"unmatched"`: kept with `athlete_id = NA`, never dropped.
#'
#' CFBD reuses athlete ids across people over long spans (decision 0022), so a
#' `reused` id only links when its roster seasons put it in college within
#' three seasons of the draft. An id links to at most one invitee per combine;
#' a `name_school` id that collides with another row's link is dropped.
#'
#' Names come from `player_stats` (CFBD `/roster` carries none), so an
#' undrafted invitee with no college stat line, typically an offensive
#' lineman, can only be `unmatched`.
#'
#' @param combine Cleaned combine from [clean_combine()].
#' @param picks Cleaned CFBD picks ([clean_picks()]): `year`, `round`,
#'   `overall`, `name`, `playerId`, `collegeTeam`.
#' @param player_stats Cleaned long stats ([clean_player_stats()]), or any
#'   table with `playerId`, `player`, `season`, `team` (the name source).
#' @param roster Cleaned roster ([clean_roster()]): `playerId`, `season`,
#'   `team` (career seasons, including no-stat seasons).
#' @param nfl_draft_picks Cleaned nflverse draft picks
#'   ([clean_nfl_draft_picks()]); cross-checks `pfr_id` at the draft slot.
#' @param reused Character vector of reused athlete ids ([reused_ids()]).
#'
#' @return `combine` with `athlete_id` (CFBD athlete id, string), `link_method`
#'   (`draft_slot`/`name_school`/`unmatched`), and `pfr_agrees` (the
#'   invitee's `pfr_id` equals nflverse's at the draft slot; `NA` when either
#'   is missing). Same rows as `combine`.
#' @export
link_combine <- function(
  combine,
  picks,
  player_stats,
  roster,
  nfl_draft_picks,
  reused = character()
) {
  if (nrow(combine) == 0) {
    return(dplyr::mutate(
      combine,
      athlete_id = character(),
      link_method = character(),
      pfr_agrees = logical()
    ))
  }
  cmb <- combine |>
    dplyr::mutate(
      .row = dplyr::row_number(),
      .dy = dplyr::coalesce(.data$draft_year, .data$season),
      .school = school_key(.data$school),
      .name = normalize_name(.data$player_name)
    )

  # Career seasons per id (roster includes no-stat seasons), for the reuse
  # guard and the final-season rule.
  seasons <- dplyr::bind_rows(
    dplyr::select(roster, "playerId", "season", "team"),
    dplyr::distinct(player_stats, .data$playerId, .data$season, .data$team) |>
      dplyr::collect()
  ) |>
    dplyr::filter(!is.na(.data$playerId)) |>
    dplyr::distinct()
  # A reused id is only trusted with a season close to this draft.
  plausible <- function(ids, dy) {
    near <- seasons |>
      dplyr::filter(.data$playerId %in% ids[ids %in% reused]) |>
      dplyr::distinct(.data$playerId, .data$season)
    vapply(
      seq_along(ids),
      \(i) {
        if (is.na(ids[i]) || !ids[i] %in% reused) {
          return(TRUE)
        }
        s <- near$season[near$playerId == ids[i]]
        any(s >= dy[i] - 3L & s <= dy[i] - 1L)
      },
      logical(1)
    )
  }

  # ---- tier 1: draft slot ----
  slot_rows <- cmb |>
    dplyr::filter(!is.na(.data$draft_ovr)) |>
    dplyr::add_count(.data$draft_year, .data$draft_ovr, name = ".claims") |>
    dplyr::filter(.data$.claims == 1L)
  slot <- slot_rows |>
    dplyr::select(".row", "draft_year", "draft_round", "draft_ovr", ".dy") |>
    dplyr::inner_join(
      picks |>
        dplyr::filter(!is.na(.data$playerId)) |>
        dplyr::distinct(
          .data$year,
          .data$round,
          .data$overall,
          .keep_all = TRUE
        ) |>
        dplyr::select(
          draft_year = "year",
          draft_round = "round",
          draft_ovr = "overall",
          "name",
          "playerId",
          "collegeTeam"
        ),
      by = c("draft_year", "draft_round", "draft_ovr")
    ) |>
    dplyr::left_join(
      dplyr::select(cmb, ".row", "player_name", ".school"),
      by = ".row"
    ) |>
    dplyr::filter(
      # as.logical(): name_variant() returns list() on zero rows.
      as.logical(name_variant(.data$player_name, .data$name)) |
        school_key(.data$collegeTeam) == .data$.school
    ) |>
    dplyr::filter(plausible(.data$playerId, .data$.dy)) |>
    dplyr::transmute(.data$.row, slot_id = .data$playerId)

  # ---- tier 2: name + school + final season ----
  name_ids <- player_stats |>
    dplyr::distinct(.data$playerId, .data$player) |>
    dplyr::collect() |>
    dplyr::mutate(.name = normalize_name(.data$player)) |>
    dplyr::distinct(.data$playerId, .data$.name)
  # Scored for every row: it also rescues a drafted invitee whose CFBD pick id
  # never appears in the college data (below).
  ns <- cmb |>
    dplyr::select(".row", ".dy", ".name", ".school") |>
    dplyr::inner_join(name_ids, by = ".name", relationship = "many-to-many") |>
    dplyr::inner_join(
      seasons,
      by = "playerId",
      relationship = "many-to-many"
    ) |>
    dplyr::filter(.data$season < .data$.dy) |>
    dplyr::mutate(.team_ok = school_key(.data$team) == .data$.school) |>
    dplyr::group_by(.data$.row, .data$playerId, .data$.dy) |>
    dplyr::summarise(
      last_pre = max(.data$season),
      # The school must match the final pre-draft season's team.
      school_ok = any(.data$.team_ok[.data$season == .data$last_pre]),
      .groups = "drop"
    ) |>
    dplyr::filter(.data$last_pre >= .data$.dy - 2L, .data$school_ok) |>
    dplyr::filter(plausible(.data$playerId, .data$.dy)) |>
    dplyr::group_by(.data$.row) |>
    dplyr::filter(dplyr::n_distinct(.data$playerId) == 1L) |>
    dplyr::ungroup() |>
    dplyr::distinct(.data$.row, ns_id = .data$playerId)

  # pfr cross-check at the slot.
  pfr <- nfl_draft_picks |>
    dplyr::select(
      draft_year = "season",
      draft_round = "round",
      draft_ovr = "pick",
      nfl_pfr = "pfr_player_id"
    )

  # Some CFBD picks carry a collegeAthleteId that never appears in roster or
  # player_stats (5-15% of slot links per class), which joins no college
  # career; a name_school id that does is preferred for those rows.
  in_career <- unique(seasons$playerId)
  out <- cmb |>
    dplyr::left_join(slot, by = ".row") |>
    dplyr::left_join(ns, by = ".row") |>
    dplyr::mutate(
      .slot_ok = !is.na(.data$slot_id) &
        (.data$slot_id %in% in_career | is.na(.data$ns_id)),
      athlete_id = dplyr::if_else(.data$.slot_ok, .data$slot_id, .data$ns_id),
      link_method = dplyr::case_when(
        .data$.slot_ok ~ "draft_slot",
        !is.na(.data$ns_id) ~ "name_school",
        .default = "unmatched"
      )
    ) |>
    # One link per id per combine: a name_school id another row already holds
    # is a collision, not a second person.
    dplyr::group_by(.data$season, .data$athlete_id) |>
    dplyr::mutate(
      .dupe = !is.na(.data$athlete_id) &
        dplyr::n() > 1L &
        .data$link_method == "name_school"
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      athlete_id = dplyr::if_else(.data$.dupe, NA_character_, .data$athlete_id),
      link_method = dplyr::if_else(.data$.dupe, "unmatched", .data$link_method)
    ) |>
    dplyr::left_join(pfr, by = c("draft_year", "draft_round", "draft_ovr")) |>
    dplyr::mutate(pfr_agrees = .data$pfr_id == .data$nfl_pfr) |>
    dplyr::arrange(.data$.row)
  dplyr::select(
    out,
    dplyr::all_of(names(combine)),
    "athlete_id",
    "link_method",
    "pfr_agrees"
  )
}
