# Map tab (plans/explorer.md step 7, issue #48): each team's home stadium and
# how far apart each conference's members sit, season by season.

#' Great-circle distance in miles
#'
#' Haversine distance on a sphere of Earth's mean radius (3,958.8 miles).
#' Vectorized over its arguments.
#'
#' @param lat1,lon1,lat2,lon2 Coordinates in decimal degrees.
#' @return Numeric miles.
#' @export
great_circle_miles <- function(lat1, lon1, lat2, lon2) {
  rad <- pi / 180
  a <- sin((lat2 - lat1) * rad / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin((lon2 - lon1) * rad / 2)^2
  2 * 3958.8 * asin(pmin(1, sqrt(a)))
}

#' Mean distance between members
#'
#' The average great-circle distance over every pair of points: the length of
#' a typical trip between two member stadiums.
#'
#' @param latitude,longitude Member coordinates.
#' @return Numeric miles; `NA` for fewer than two points.
#' @noRd
mean_pairwise_miles <- function(latitude, longitude) {
  if (length(latitude) < 2L) {
    return(NA_real_)
  }
  pairs <- utils::combn(length(latitude), 2L)
  mean(great_circle_miles(
    latitude[pairs[1, ]],
    longitude[pairs[1, ]],
    latitude[pairs[2, ]],
    longitude[pairs[2, ]]
  ))
}

#' Explorer Map asset
#'
#' Home-stadium coordinates for every team in the team-season export, and each
#' conference's geographic spread per season: the mean distance between two
#' members' home stadiums, in miles. Independents are not a conference, so they
#' have no spread row. Conference membership is the season's own (from
#' `team_season`), so realignment shows up as a change in spread.
#'
#' @param teams Cleaned teams (with `latitude`/`longitude`, see [clean_teams()]).
#' @param team_season Output of [build_explorer_team_season()].
#' @return A list: `teams` (`team_id`, `latitude`, `longitude`, `city`,
#'   `state`, `venue`) and `spread` (`season`, `conference`, `classification`,
#'   `members`, `mapped`, `spread_miles`).
#' @export
build_explorer_map <- function(teams, team_season) {
  located <- teams |>
    dplyr::filter(
      .data$team_id %in% team_season$team_id,
      !is.na(.data$latitude),
      !is.na(.data$longitude)
    ) |>
    dplyr::transmute(
      team_id = .data$team_id,
      latitude = round(.data$latitude, 3),
      longitude = round(.data$longitude, 3),
      city = .data$city,
      state = .data$state,
      venue = .data$venue
    ) |>
    dplyr::arrange(.data$team_id)

  spread <- team_season |>
    dplyr::filter(
      !is.na(.data$conference),
      !grepl("Independent", .data$conference)
    ) |>
    dplyr::left_join(
      dplyr::select(located, "team_id", "latitude", "longitude"),
      by = "team_id",
      relationship = "many-to-one"
    ) |>
    dplyr::summarise(
      # A conference with any FBS member is an FBS conference that season.
      classification = if (any(.data$classification == "fbs")) "fbs" else "fcs",
      members = dplyr::n(),
      mapped = sum(!is.na(.data$latitude)),
      spread_miles = round(mean_pairwise_miles(
        .data$latitude[!is.na(.data$latitude)],
        .data$longitude[!is.na(.data$longitude)]
      )),
      .by = c("season", "conference")
    ) |>
    dplyr::mutate(members = as.integer(.data$members)) |>
    dplyr::arrange(.data$season, .data$conference)

  list(teams = located, spread = spread)
}

#' Write the Map asset
#'
#' `map.json`, with both tables as objects of columns (one array per field),
#' like `careers.json`.
#'
#' @param map Output of [build_explorer_map()].
#' @param dir Output directory.
#' @return The written path.
#' @export
write_explorer_map <- function(map, dir = "vignettes/explorer-data") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, "map.json")
  json <- jsonlite::toJSON(map, dataframe = "columns", na = "null", digits = NA)
  writeLines(enc2utf8(json), path, useBytes = TRUE)
  path
}
