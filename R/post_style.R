# Mechanical checks of the blog-post style (AGENTS.md "Blog style",
# decisions 0015, 0025, 0040). They catch the rules a script can settle, so
# the vignette-reviewer agent can spend its read on flow and reception.
# Judgment calls (wordiness, undefined terms, hardcoded numbers in prose)
# stay with the reviewer.

#' Check one dated blog post against the mechanical style rules
#'
#' Reads a `vignettes/YYYY-MM-DD-*.qmd` post and reports every rule it breaks:
#' front matter (declarative title in sync with `VignetteIndexEntry`,
#' `description`, `followups`, `author`, `freeze: auto`), one visible `setup`
#' chunk first, the five numbered sections in order, numbered assertion
#' headings, a verdict emoji on every expectation, `callout-important` in the
#' Discussion, captioned `kable()` tables, and no em dashes, `stopifnot()`,
#' `include: false` or pie charts.
#'
#' @param path Path to a post `.qmd` file.
#' @return A tibble with one row per violation: `file`, `line` (`NA` for
#'   whole-file rules), `rule` and `message`. Zero rows means the post passes.
#' @keywords internal
check_post_style <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  out <- list()
  flag <- function(rule, message, line = NA_integer_) {
    out[[length(out) + 1L]] <<- tibble::tibble(
      file = basename(path),
      line = as.integer(line),
      rule = rule,
      message = message
    )
  }

  # ---- Front matter ----
  fences <- which(lines == "---")
  if (length(fences) < 2L || fences[1] != 1L) {
    flag("front_matter", "No YAML front matter at the top of the file.")
    return(dplyr::bind_rows(out))
  }
  body_start <- fences[2] + 1L
  meta <- yaml::yaml.load(paste(lines[2:(fences[2] - 1L)], collapse = "\n"))
  title <- meta$title %||% ""
  if (!nzchar(title)) {
    flag("title", "Missing `title:`.")
  } else if (grepl(":", title, fixed = TRUE)) {
    flag("title", "Title contains a colon; use one declarative sentence.")
  }
  index_entry <- regmatches(
    meta$vignette %||% "",
    regexec("\\\\VignetteIndexEntry\\{([^}]*)\\}", meta$vignette %||% "")
  )[[1]]
  if (length(index_entry) < 2L || !identical(index_entry[2], title)) {
    flag("index_entry", "`VignetteIndexEntry` does not match `title:`.")
  }
  if (!nzchar(meta$description %||% "")) {
    flag("description", "Missing `description:` (the finding in a sentence).")
  }
  if (length(meta$followups) == 0L) {
    flag("followups", "Missing `followups:` (open questions for later posts).")
  }
  if (length(meta$author) == 0L) {
    flag("author", "Missing `author:`.")
  }
  if (!identical(meta$freeze, "auto")) {
    flag("freeze", "Use `freeze: auto`; `freeze: true` never deploys edits.")
  }

  # ---- Chunks ----
  body <- seq_along(lines) >= body_start
  chunk_open <- which(body & grepl("^```\\{r", lines))
  chunk_close <- which(body & lines == "```")
  chunks <- lapply(chunk_open, function(i) {
    end <- chunk_close[chunk_close > i][1]
    if (is.na(end)) {
      end <- length(lines) + 1L
    }
    seq.int(i + 1L, end - 1L)
  })
  in_chunk <- rep(FALSE, length(lines))
  for (rows in chunks) {
    in_chunk[rows] <- TRUE
  }
  # Prose = body lines outside chunks and HTML comments.
  in_comment <- cumsum(grepl("<!--", lines)) > cumsum(grepl("-->", lines)) |
    grepl("<!--|-->", lines)
  prose <- body & !in_chunk & !grepl("^```", lines) & !in_comment

  setup <- which(vapply(
    chunks,
    \(rows) any(grepl("^#\\|\\s*label:\\s*setup\\s*$", lines[rows])),
    logical(1)
  ))
  intro <- which(prose & grepl("^## 1\\. Introduction\\s*$", lines))
  if (length(setup) != 1L) {
    flag("setup_chunk", "Need exactly one chunk labelled `setup`.")
  } else if (setup != 1L) {
    flag("setup_chunk", "The `setup` chunk must be the first chunk.")
  } else if (length(intro) && chunk_open[setup] > intro[1]) {
    flag("setup_chunk", "The `setup` chunk must come before the Introduction.")
  }

  for (i in which(in_chunk & grepl("^#\\|\\s*include:\\s*false", lines))) {
    flag(
      "include_false",
      "Show code; use `output: false`, not `include: false`.",
      i
    )
  }
  for (i in which(in_chunk & grepl("stopifnot\\(", lines))) {
    flag("stopifnot", "No `stopifnot()` pins in posts (decision 0040).", i)
  }
  for (i in which(in_chunk & grepl("coord_polar\\(|geom_pie", lines))) {
    flag("pie_chart", "No pie charts; use ordered horizontal bars.", i)
  }

  # Every kable() call carries a caption. Parse the chunk so piped calls
  # (`x |> kable(caption = ...)`) and multi-line calls are read correctly.
  for (k in seq_along(chunks)) {
    code <- lines[chunks[[k]]]
    exprs <- tryCatch(parse(text = code, keep.source = FALSE), error = \(e) {
      NULL
    })
    if (is.null(exprs)) {
      next
    }
    if (n_uncaptioned_kable(exprs) > 0L) {
      flag(
        "kable_caption",
        "A `kable()` table has no `caption =`.",
        chunk_open[k]
      )
    }
  }

  # ---- Prose ----
  for (i in which(body & grepl("\u2014", lines))) {
    flag("em_dash", "Em dash; rewrite with a comma, colon or period.", i)
  }

  sections <- c("Introduction", "Data", "Results", "Summary", "Discussion")
  h2 <- which(prose & grepl("^## ", lines))
  want <- paste0("## ", seq_along(sections), ". ", sections)
  got <- trimws(lines[h2])
  if (!identical(got[got %in% want], want)) {
    flag(
      "sections",
      paste0("Sections must be ", paste(want, collapse = ", "), ", in order.")
    )
  }

  for (i in which(prose & grepl("^### ", lines))) {
    if (!grepl("^### [0-9]+\\.[0-9]+ \\S", lines[i])) {
      flag(
        "assertion_heading",
        "Subsection heading is not `### n.n <claim>`.",
        i
      )
    }
  }

  # An expectation paragraph runs to the next blank line; its verdict emoji
  # may sit on any of its lines.
  for (i in which(prose & grepl("^\\*Expectation:", lines))) {
    end <- i
    while (end < length(lines) && nzchar(trimws(lines[end + 1L]))) {
      end <- end + 1L
    }
    if (!any(grepl("\u2705|\u274c", lines[i:end]))) {
      flag(
        "expectation_verdict",
        "Expectation has no verdict emoji (check or cross).",
        i
      )
    }
  }

  discussion <- which(prose & grepl("^## 5\\. Discussion", lines))
  if (
    length(discussion) &&
      !any(grepl("callout-important", lines[discussion[1]:length(lines)]))
  ) {
    flag("discussion_callout", "Discussion needs `callout-important` blocks.")
  }

  if (length(out) == 0L) {
    return(tibble::tibble(
      file = character(),
      line = integer(),
      rule = character(),
      message = character()
    ))
  }
  dplyr::bind_rows(out)
}

# Count kable()/knitr::kable() calls without a `caption` argument.
n_uncaptioned_kable <- function(x) {
  if (is.expression(x)) {
    return(sum(vapply(as.list(x), n_uncaptioned_kable, integer(1))))
  }
  if (!is.call(x)) {
    return(0L)
  }
  fn <- x[[1]]
  is_kable <- identical(fn, as.name("kable")) ||
    (is.call(fn) &&
      identical(fn[[1]], as.name("::")) &&
      identical(fn[[3]], as.name("kable")))
  n <- as.integer(is_kable && !"caption" %in% names(as.list(x)))
  # Skip empty arguments (`x[, 1]`): binding one to a variable makes it
  # a missing argument that cannot be passed on.
  for (j in seq_along(x)[-1]) {
    if (!identical(x[[j]], quote(expr = ))) {
      n <- n + n_uncaptioned_kable(x[[j]])
    }
  }
  n
}

#' Check every dated blog post
#'
#' Runs [check_post_style()] over `vignettes/YYYY-MM-DD-*.qmd`.
#'
#' @param dir The vignettes directory.
#' @return The bound violations tibble across posts.
#' @keywords internal
check_posts_style <- function(dir = "vignettes") {
  posts <- list.files(
    dir,
    "^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*[.]qmd$",
    full.names = TRUE
  )
  dplyr::bind_rows(lapply(posts, check_post_style))
}
