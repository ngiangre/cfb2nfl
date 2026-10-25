# Ad-hoc data-quality check: do the DB high-school star ratings agree with what
# Wikipedia publicly states? Kept as a package function (not a pipeline target)
# so it can be run on demand with a chosen seed. Logic is *Wikipedia-first*:
# confirm Wikipedia states a rating and that the recruiting year corroborates
# identity (name-collision guard, cf. decision 0013) BEFORE reading the DB.

#' Fetch the plain-text extract of a Wikipedia article
#'
#' @param title Article title (followed through redirects).
#'
#' @return A list with `title`, `missing` (logical), and `text` (character).
#' @keywords internal
wiki_extract <- function(title) {
  rlang::check_installed("httr2", reason = "to query the Wikipedia API.")
  pages <- httr2::request("https://en.wikipedia.org/w/api.php") |>
    httr2::req_url_query(
      action = "query",
      prop = "extracts",
      explaintext = 1,
      redirects = 1,
      format = "json",
      titles = title
    ) |>
    httr2::req_user_agent("cfb2nfl (https://github.com)") |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  pg <- pages$query$pages[[1]]
  list(
    title = pg$title %||% title,
    missing = !is.null(pg$missing),
    text = pg$extract %||% ""
  )
}

#' Parse a recruiting star rating from Wikipedia article text
#'
#' Star ratings appear as prose ("a five-star recruit"), occasionally digits.
#' Guards against false hits by (a) requiring `star` as a whole word so game
#' "starts" do not match, (b) only considering sentences with recruiting
#' context, and (c) requiring the sentence to mention the subject's surname, so
#' a *teammate's* star rating quoted in the article is not picked up. Returns
#' the most common value found, `NA` if none.
#'
#' @param text Article plain text.
#' @param surname Subject's surname; sentences must mention it. `NULL` disables
#'   the subject filter.
#'
#' @return An integer star rating in 1:5, or `NA_integer_`.
#' @keywords internal
wiki_parse_star <- function(text, surname = NULL) {
  ctx_re <- "recruit|prospect|rivals|247|espn|composite|consensus|rated|ranked|signee"
  sentences <- strsplit(text, "(?<=\\.)\\s+", perl = TRUE)[[1]]
  sentences <- sentences[grepl(
    ctx_re,
    sentences,
    ignore.case = TRUE,
    perl = TRUE
  )]
  if (!is.null(surname) && nzchar(surname)) {
    sentences <- sentences[grepl(
      surname,
      sentences,
      ignore.case = TRUE,
      fixed = FALSE
    )]
  }
  if (!length(sentences)) {
    return(NA_integer_)
  }
  ctx <- paste(sentences, collapse = " ")

  words <- c(one = 1L, two = 2L, three = 3L, four = 4L, five = 5L)
  grab <- function(pat) {
    regmatches(ctx, gregexpr(pat, ctx, ignore.case = TRUE, perl = TRUE))[[1]]
  }
  wm <- grab("\\b(one|two|three|four|five)[ -]star\\b")
  dm <- grab("\\b([1-5])[ -]star\\b")

  vals <- integer()
  if (length(wm)) {
    w <- tolower(regmatches(
      wm,
      regexpr("one|two|three|four|five", wm, ignore.case = TRUE, perl = TRUE)
    ))
    vals <- c(vals, unname(words[w]))
  }
  if (length(dm)) {
    vals <- c(vals, as.integer(regmatches(dm, regexpr("[1-5]", dm))))
  }
  if (!length(vals)) {
    return(NA_integer_)
  }
  as.integer(names(sort(table(vals), decreasing = TRUE))[1])
}

#' Extract candidate class years mentioned in article text
#'
#' @param text Article plain text.
#'
#' @return A sorted integer vector of distinct 2000s/2010s/2020s years.
#' @keywords internal
wiki_parse_years <- function(text) {
  y <- regmatches(text, gregexpr("\\b20[0-2][0-9]\\b", text))[[1]]
  sort(unique(as.integer(y)))
}

#' Cross-check DB recruiting star ratings against Wikipedia
#'
#' Draws a reproducible random sample of drafted players (fixed `seed`) and,
#' **Wikipedia-first**, keeps only those where (1) the player's Wikipedia article
#' states a recruiting star rating and (2) the recruiting class year is
#' corroborated by the article and resolves to exactly one class — a
#' name-collision guard (a name mapping to two different classes is rejected).
#' Only for players clearing both gates is the internal DB rating read and
#' compared. Candidates are walked in the shuffled order until `n_target` clear
#' the gates or `max_candidates` lookups are spent.
#'
#' @param seed Integer seed for the reproducible candidate shuffle.
#' @param n_target Number of gate-passing players to collect. Default 5.
#' @param max_candidates Cap on Wikipedia lookups. Default 60.
#' @param picks Drafted-players tibble; defaults to reading `data/picks.parquet`.
#' @param recruiting Recruiting tibble; defaults to reading
#'   `data/recruiting.parquet`.
#' @param quiet If `TRUE`, suppress the progress message. Default `FALSE`.
#'
#' @return A tibble with one row per gate-passing player: `name`,
#'   `matched_year`, `wiki_stars`, `db_stars`, `agree`, `verdict`. The number of
#'   candidates examined is attached as attribute `"n_examined"`.
#' @importFrom rlang %||%
#' @export
verify_wikipedia_ratings <- function(
  seed,
  n_target = 5L,
  max_candidates = 60L,
  picks = NULL,
  recruiting = NULL,
  quiet = FALSE
) {
  if (is.null(picks) || is.null(recruiting)) {
    rlang::check_installed(
      "arrow",
      reason = "to read the default parquet data."
    )
    picks <- picks %||% arrow::read_parquet("data/picks.parquet")
    recruiting <- recruiting %||% arrow::read_parquet("data/recruiting.parquet")
  }

  rec <- recruiting |>
    dplyr::filter(!is.na(.data$stars)) |>
    dplyr::mutate(key = normalize_name(.data$recruit_name))

  candidates <- picks |>
    dplyr::filter(!is.na(.data$name)) |>
    dplyr::transmute(.data$name, key = normalize_name(.data$name)) |>
    dplyr::distinct() |>
    dplyr::semi_join(rec, by = "key")

  set.seed(seed)
  candidates <- dplyr::slice_sample(candidates, prop = 1)

  records <- list()
  examined <- 0L

  for (i in seq_len(nrow(candidates))) {
    if (length(records) >= n_target || examined >= max_candidates) {
      break
    }
    examined <- examined + 1L

    nm <- candidates$name[i]
    key <- candidates$key[i]
    pg <- wiki_extract(nm)
    Sys.sleep(0.2) # be polite to the API

    # Gate 0: a real, unambiguous article.
    if (
      pg$missing || grepl("\\bmay refer to\\b", pg$text, ignore.case = TRUE)
    ) {
      next
    }

    # Gate 1: Wikipedia states a star rating (about this subject, by surname).
    ws <- wiki_parse_star(pg$text, surname = sub(".* ", "", key))
    if (is.na(ws)) {
      next
    }

    # Gate 2: identity via recruiting year -- the DB class year must be
    # corroborated by the article and pick out exactly one class.
    rec_rows <- dplyr::filter(rec, .data$key == !!key)
    confirmed <- dplyr::filter(
      rec_rows,
      .data$hs_class %in% wiki_parse_years(pg$text)
    )
    years_confirmed <- sort(unique(confirmed$hs_class))
    if (length(years_confirmed) != 1L) {
      next
    } # 0 = uncorroborated, >1 = collision

    # Both gates passed: now read the internal DB rating.
    db_stars <- confirmed |>
      dplyr::count(.data$stars, sort = TRUE) |>
      dplyr::slice(1) |>
      dplyr::pull(.data$stars)

    records[[length(records) + 1L]] <- tibble::tibble(
      name = nm,
      matched_year = years_confirmed,
      wiki_stars = ws,
      db_stars = db_stars,
      agree = ws == db_stars
    )
  }

  result <- dplyr::bind_rows(records)
  if (nrow(result)) {
    result$verdict <- ifelse(result$agree, "MATCH", "MISMATCH")
  }
  attr(result, "n_examined") <- examined

  if (!quiet) {
    cli::cli_inform(
      "Examined {examined} candidate{?s} to collect {nrow(result)} gate-passing player{?s}."
    )
  }
  result
}
