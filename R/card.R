# Figure cards (feature F25): one question, one figure. A card's builder
# returns one ggplot; the card saves it as a static thumbnail for the
# Investigations wall and shows it as an interactive figure on its page.
# Thumbnails are committed, so a sidecar of hashes lets the style check tell
# when a thumbnail no longer matches its card's code or the R/ functions it
# calls (file times are useless: a fresh checkout resets them).

#' Record the date of the downloaded data release
#'
#' Run after downloading `data-latest` (`data-raw/pull-data.R`, the
#' `site.yaml` download step). The DuckDB's own `_meta` timestamp cannot be
#' used: every fresh `tar_make()` rebuilds the bundle and restamps it, so it
#' would date the build, not the release.
#'
#' @param dest The data directory the release was downloaded into.
#' @param repo,tag The release to read the asset timestamp from.
#' @return The stamp path, invisibly.
#' @export
record_release_date <- function(
  dest = "data",
  repo = "ngiangre/cfb2nfl",
  tag = "data-latest"
) {
  assets <- piggyback::pb_list(repo = repo, tag = tag)
  ts <- assets$timestamp[assets$file_name == "cfb2nfl.duckdb"]
  write_release_stamp(ts[[1]], dest)
}

#' @rdname record_release_date
#' @param time The release asset's upload time.
#' @export
write_release_stamp <- function(time, dest = "data") {
  path <- file.path(dest, ".release-date")
  writeLines(format(as.Date(time, tz = "UTC"), "%Y-%m-%d"), path)
  invisible(path)
}

#' The data release date
#'
#' The date of the `data-latest` release the local data came from, read from
#' the stamp [record_release_date()] writes on download.
#'
#' @param dir The data directory.
#' @return A `Date`.
#' @export
data_release_date <- function(dir = file.path(card_root(), "data")) {
  path <- file.path(dir, ".release-date")
  if (!file.exists(path)) {
    cli::cli_abort(c(
      "No data release stamp at {.path {path}}.",
      "i" = "Download the release with {.file data-raw/pull-data.R}, which records its date."
    ))
  }
  as.Date(readLines(path, n = 1, warn = FALSE))
}

#' Where a card lives in the checkout
#'
#' altdoc renders a copy of each vignette under `_quarto/`, which git
#' ignores, so card paths resolve against the checkout (`CFB2NFL_ROOT`, else
#' the package root) to keep thumbnails where they are committed.
#'
#' @param input The file being rendered.
#' @return `card_root()`: the checkout root. `card_source()`: the card's
#'   path under `vignettes/`. `card_thumb_dir()`: the thumbnail directory.
#' @export
card_root <- function() {
  root <- Sys.getenv("CFB2NFL_ROOT")
  if (nzchar(root)) root else pkgload::pkg_path()
}

#' @rdname card_root
#' @export
card_source <- function(input = knitr::current_input()) {
  file.path(card_root(), "vignettes", basename(input))
}

#' @rdname card_root
#' @export
card_thumb_dir <- function() {
  file.path(card_root(), "vignettes", "card-thumbs")
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
#' being knit, resolved to its source under `vignettes/` ([card_source()]).
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
  card = card_source(),
  release = NULL,
  dir = card_thumb_dir(),
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
  dir = card_thumb_dir(),
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
