# Figure cards (feature F25): one question, one figure. A card's builder
# returns one ggplot; the card saves it as a static thumbnail for the
# Investigations wall and shows it as an interactive figure on its page.
# Thumbnails are committed, so a sidecar of hashes lets the style check tell
# when a thumbnail no longer matches its card's code or the R/ functions it
# calls (file times are useless: a fresh checkout resets them).

#' The data release date of the DuckDB bundle
#'
#' Read from the bundle's `_meta` table ([build_meta()]), so it is the date
#' of the `data-latest` refresh in track mode too, with no API call.
#'
#' @param con A DBI connection to `cfb2nfl.duckdb`.
#' @return A `Date`.
#' @export
data_release_date <- function(con) {
  meta <- DBI::dbGetQuery(con, "SELECT refreshed_at FROM _meta LIMIT 1")
  as.Date(meta$refreshed_at[[1]])
}

#' Caption line for a card figure
#'
#' @param release The data release date ([data_release_date()]).
#' @param source Who the data comes from.
#' @return One string for `labs(caption = )`.
#' @export
card_caption <- function(release, source = "CFBD, nflverse") {
  paste0("Data: ", source, " | data release ", format(release, "%Y-%m-%d"))
}

#' Theme for card figures
#'
#' [theme_cfb2nfl()] at a larger base size, so a thumbnail about 400 px wide
#' on the Investigations wall stays legible, with the caption (source and
#' release date) set small and left.
#'
#' @param base_size Base font size in points.
#' @return A ggplot2 theme object.
#' @export
theme_card <- function(base_size = 20) {
  theme_cfb2nfl(base_size = base_size) +
    ggplot2::theme(
      plot.caption.position = "plot",
      plot.caption = ggplot2::element_text(
        hjust = 0,
        face = "plain",
        colour = "grey40",
        size = ggplot2::rel(0.7)
      )
    )
}

#' The R code of a card
#'
#' The lines inside a card's ```` ```{r} ```` chunks. Front matter and text
#' are left out, so editing a card's question or tags does not stale its
#' thumbnail.
#'
#' @param card Path to a `card-<id>.qmd`.
#' @return A character vector of code lines.
#' @export
card_code <- function(card) {
  lines <- readLines(card, warn = FALSE)
  open <- grepl("^\\s*```+\\s*\\{r", lines)
  close <- grepl("^\\s*```+\\s*$", lines)
  inside <- FALSE
  keep <- logical(length(lines))
  for (i in seq_along(lines)) {
    if (!inside && open[i]) {
      inside <- TRUE
    } else if (inside && close[i]) {
      inside <- FALSE
    } else {
      keep[i] <- inside
    }
  }
  lines[keep]
}

# Package functions named in a set of expressions or function bodies.
pkg_names_in <- function(x, ns) {
  intersect(all.names(x), ls(ns))
}

#' The cfb2nfl functions a card calls
#'
#' Every package function the card's code names, plus every package function
#' those call in turn, so a change to a helper deep in a builder still stales
#' the thumbnail.
#'
#' @param card Path to a `card-<id>.qmd`.
#' @return A sorted character vector of function names.
#' @export
card_functions <- function(card) {
  ns <- asNamespace("cfb2nfl")
  exprs <- parse(text = card_code(card), keep.source = FALSE)
  is_fn <- function(f) is.function(get(f, envir = ns))
  found <- Filter(is_fn, pkg_names_in(exprs, ns))
  queue <- found
  while (length(queue) > 0) {
    f <- get(queue[[1]], envir = ns)
    queue <- queue[-1]
    new <- setdiff(Filter(is_fn, pkg_names_in(body(f), ns)), found)
    found <- c(found, new)
    queue <- c(queue, new)
  }
  sort(found)
}

# Hash of a function's code, ignoring comments and layout (the deparse does
# not use the source reference).
fn_hash <- function(name) {
  f <- get(name, envir = asNamespace("cfb2nfl"))
  rlang::hash(deparse(f, control = c("keepNA", "keepInteger", "niceNames")))
}

card_hashes <- function(card) {
  fns <- card_functions(card)
  list(
    code_hash = rlang::hash(card_code(card)),
    functions = stats::setNames(lapply(fns, fn_hash), fns)
  )
}

#' Save a card's thumbnail and its freshness sidecar
#'
#' Writes `<dir>/<id>.png` and `<dir>/<id>.json`; the sidecar records a hash
#' of the card's R code, a hash of every package function it calls
#' ([card_functions()]) and the data release, for [card_freshness()].
#' Called inside the card while it renders, so `card` defaults to the file
#' being knit.
#'
#' @param p A ggplot (styled with [theme_card()]).
#' @param id The card id (`card-<id>.qmd`).
#' @param card Path to the card file.
#' @param release The data release date, or `NULL`.
#' @param dir Thumbnail directory.
#' @param width,height Size in inches.
#' @param dpi Resolution.
#' @return The PNG path, invisibly.
#' @export
card_thumbnail <- function(
  p,
  id,
  card = knitr::current_input(dir = TRUE),
  release = NULL,
  dir = file.path(dirname(card), "card-thumbs"),
  width = 8,
  height = 5.5,
  dpi = 120
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  png <- file.path(dir, paste0(id, ".png"))
  ggplot2::ggsave(
    png,
    p,
    width = width,
    height = height,
    dpi = dpi,
    bg = "white",
    device = ragg::agg_png
  )
  side <- c(
    list(
      id = id,
      release = if (is.null(release)) NULL else format(release, "%Y-%m-%d")
    ),
    card_hashes(card)
  )
  jsonlite::write_json(
    side,
    file.path(dir, paste0(id, ".json")),
    auto_unbox = TRUE,
    pretty = TRUE,
    null = "null"
  )
  invisible(png)
}

#' Is a card's thumbnail still in step with its card?
#'
#' Compares the sidecar written by [card_thumbnail()] with the card as it is
#' now. A changed card or package function means the thumbnail must be
#' re-rendered; a newer data release only means it is out of date.
#'
#' @param card Path to the card file.
#' @param id The card id.
#' @param dir Thumbnail directory.
#' @param release The current data release date, or `NULL` to skip that check.
#' @return A list: `status` (`"fresh"`, `"missing"`, `"stale_code"`,
#'   `"stale_r"` or `"stale_data"`) and `changed` (the functions that
#'   changed, for `"stale_r"`).
#' @export
card_freshness <- function(
  card,
  id,
  dir = file.path(dirname(card), "card-thumbs"),
  release = NULL
) {
  png <- file.path(dir, paste0(id, ".png"))
  json <- file.path(dir, paste0(id, ".json"))
  if (!file.exists(png) || !file.exists(json)) {
    return(list(status = "missing", changed = character()))
  }
  side <- jsonlite::read_json(json)
  now <- card_hashes(card)
  if (!identical(side$code_hash, now$code_hash)) {
    return(list(status = "stale_code", changed = character()))
  }
  was <- unlist(side$functions)
  is <- unlist(now$functions)
  fns <- union(names(was), names(is))
  changed <- fns[is.na(was[fns]) | is.na(is[fns]) | was[fns] != is[fns]]
  if (length(changed) > 0) {
    return(list(status = "stale_r", changed = sort(changed)))
  }
  if (
    !is.null(release) && !identical(side$release, format(release, "%Y-%m-%d"))
  ) {
    return(list(status = "stale_data", changed = character()))
  }
  list(status = "fresh", changed = character())
}

#' The interactive version of a card's figure
#'
#' @param p The card's ggplot, with `ggiraph` interactive layers for hover.
#' @param ... Passed to [ggiraph::girafe()].
#' @return A `girafe` htmlwidget.
#' @export
card_interactive <- function(p, ...) {
  rlang::check_installed("ggiraph")
  ggiraph::girafe(ggobj = p, width_svg = 9, height_svg = 6, ...)
}
