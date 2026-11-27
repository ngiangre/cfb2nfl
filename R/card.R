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
#' @param root The checkout root.
#' @return `card_root()`: the checkout root. `card_source()`: the card's
#'   path under `vignettes/`. `card_thumb_dir()`: the thumbnail directory.
#' @export
card_root <- function() {
  root <- Sys.getenv("CFB2NFL_ROOT")
  if (nzchar(root)) root else pkgload::pkg_path()
}

#' @rdname card_root
#' @export
card_source <- function(input = knitr::current_input(), root = card_root()) {
  # Quarto knits an intermediate `.rmarkdown` copy, so take the stem.
  stem <- tools::file_path_sans_ext(basename(input))
  file.path(root, "vignettes", paste0(stem, ".qmd"))
}

#' @rdname card_root
#' @export
card_thumb_dir <- function(root = card_root()) {
  file.path(root, "vignettes", "card-thumbs")
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

# Every top-level function defined in R/, parsed from the files rather than
# the loaded namespace so the style check needs no package load. Each entry
# keeps the function expression (to trace what it calls) and a hash of its
# source tokens without comments, so comment and layout edits do not stale a
# thumbnail, and the hash is the same on every platform and R version.
r_function_index <- function(root = card_root()) {
  files <- list.files(file.path(root, "R"), "[.][Rr]$", full.names = TRUE)
  index <- list()
  for (f in files) {
    exprs <- parse(f, keep.source = TRUE)
    refs <- attr(exprs, "srcref")
    for (i in seq_along(exprs)) {
      e <- exprs[[i]]
      is_fn_def <- is.call(e) &&
        is.name(e[[1]]) &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) &&
        is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))
      if (!is_fn_def) {
        next
      }
      pd <- utils::getParseData(
        parse(text = as.character(refs[[i]]), keep.source = TRUE)
      )
      tokens <- pd$text[pd$terminal & pd$token != "COMMENT"]
      index[[as.character(e[[2]])]] <- list(
        expr = e[[3]],
        hash = rlang::hash(tokens)
      )
    }
  }
  index
}

# Card plumbing that saves, shows or checks a figure but does not shape it;
# editing it should not stale every thumbnail.
card_machinery <- c(
  "card_thumbnail",
  "card_interactive",
  "card_footer",
  "card_freshness",
  "card_functions",
  "card_hashes",
  "card_code",
  "card_root",
  "card_source",
  "card_thumb_dir",
  "card_vocabulary",
  "qmd_front_matter",
  "r_function_index",
  "data_release_date",
  "record_release_date",
  "write_release_stamp"
)

#' The cfb2nfl functions a card calls
#'
#' Every function defined in `R/` that the card's code names, plus every one
#' those call in turn, so a change to a helper deep in a builder still stales
#' the thumbnail. The card machinery (saving, showing and checking the
#' figure) is left out: it does not change what the figure shows.
#'
#' @param card Path to a `card-<id>.qmd`.
#' @param root The checkout root.
#' @param index The parsed `R/` functions (built from `root` if not given).
#' @return A sorted character vector of function names.
#' @export
card_functions <- function(
  card,
  root = card_root(),
  index = r_function_index(root)
) {
  index <- index[setdiff(names(index), card_machinery)]
  exprs <- parse(text = card_code(card), keep.source = FALSE)
  found <- intersect(all.names(exprs), names(index))
  queue <- found
  while (length(queue) > 0) {
    new <- setdiff(
      intersect(all.names(index[[queue[[1]]]]$expr), names(index)),
      found
    )
    queue <- c(queue[-1], new)
    found <- c(found, new)
  }
  sort(found)
}

card_hashes <- function(
  card,
  root = card_root(),
  index = r_function_index(root)
) {
  fns <- card_functions(card, index = index)
  list(
    code_hash = rlang::hash(card_code(card)),
    functions = stats::setNames(lapply(fns, \(f) index[[f]]$hash), fns)
  )
}

#' Wrap a card figure's title and subtitle to the thumbnail's width
#'
#' At [theme_card()] sizes an 8-inch thumbnail fits about 40 title and 55
#' subtitle characters per line; longer ones would run off the edge.
#'
#' @param p A ggplot.
#' @param title_width,subtitle_width Characters per line.
#' @return `p` with wrapped labels.
#' @export
card_label_wrap <- function(p, title_width = 40, subtitle_width = 55) {
  wrap <- function(x, width) {
    if (is.null(x) || !is.character(x)) {
      return(x)
    }
    paste(strwrap(x, width), collapse = "\n")
  }
  p +
    ggplot2::labs(
      title = wrap(p$labels$title, title_width),
      subtitle = wrap(p$labels$subtitle, subtitle_width)
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
#' @param root The checkout root (whose `R/` functions are hashed).
#' @param width,height Size in inches.
#' @param dpi Resolution.
#' @return The PNG path, invisibly.
#' @export
card_thumbnail <- function(
  p,
  id,
  card = card_source(root = root),
  release = NULL,
  dir = card_thumb_dir(root),
  root = card_root(),
  width = 8,
  height = 5.5,
  dpi = 120
) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  png <- file.path(dir, paste0(id, ".png"))
  ggplot2::ggsave(
    png,
    card_label_wrap(p),
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
    card_hashes(card, root = root)
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
#' @param root The checkout root.
#' @param index The parsed `R/` functions (reused across cards by the style
#'   check).
#' @return A list: `status` (`"fresh"`, `"missing"`, `"stale_code"`,
#'   `"stale_r"` or `"stale_data"`) and `changed` (the functions that
#'   changed, for `"stale_r"`).
#' @export
card_freshness <- function(
  card,
  id,
  dir = card_thumb_dir(root),
  release = NULL,
  root = card_root(),
  index = r_function_index(root)
) {
  png <- file.path(dir, paste0(id, ".png"))
  json <- file.path(dir, paste0(id, ".json"))
  if (!file.exists(png) || !file.exists(json)) {
    return(list(status = "missing", changed = character()))
  }
  side <- jsonlite::read_json(json)
  now <- card_hashes(card, index = index)
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
#' @param width_svg,height_svg Figure size in inches.
#' @param ... Passed to [ggiraph::girafe()].
#' @return A `girafe` htmlwidget.
#' @export
card_interactive <- function(p, width_svg = 11, height_svg = 6, ...) {
  rlang::check_installed("ggiraph")
  # The hover and tooltip styling the posts used.
  options <- list(
    ggiraph::opts_hover(
      css = "stroke:#111827;stroke-width:2.5px;filter:brightness(1.12);"
    ),
    ggiraph::opts_hover_inv(css = "opacity:0.45;"),
    ggiraph::opts_tooltip(
      css = "background:#111827;color:#fff;padding:6px 9px;border-radius:5px;font-weight:bold;font-size:15px;"
    ),
    ggiraph::opts_zoom(min = 1, max = 5),
    ggiraph::opts_toolbar(saveaspng = TRUE, position = "topright"),
    ggiraph::opts_sizing(rescale = TRUE)
  )
  ggiraph::girafe(
    ggobj = p,
    width_svg = width_svg,
    height_svg = height_svg,
    options = options,
    ...
  )
}
