# Mechanical checks of figure cards (feature F25), the card scaffold and the
# footer every card page shows. The checks run without loading the package
# (the post-style CI job sources the files), so they read the registries and
# R/ straight from the checkout.

card_status_values <- c("sketch", "investigation", "graduated")

# Shared helpers a card must call, never redefine (criterion 12).
card_shared_helpers <- c(
  "fmt",
  "pct",
  "wilson",
  "and_join",
  "team_color_values",
  "scale_fill_team",
  "scale_color_team",
  "theme_cfb2nfl",
  "theme_card",
  "card_caption"
)

# Zero violations, with the columns every check returns.
no_violations <- function() {
  tibble::tibble(
    file = character(),
    line = integer(),
    rule = character(),
    severity = character(),
    message = character()
  )
}

# Front matter of a .qmd as a list, and where its body starts.
qmd_front_matter <- function(lines) {
  fences <- which(lines == "---")
  if (length(fences) < 2L || fences[1] != 1L) {
    return(NULL)
  }
  list(
    meta = yaml::yaml.load(paste(lines[2:(fences[2] - 1L)], collapse = "\n")),
    body_start = fences[2] + 1L
  )
}

# Approved tags: "Facet: value" from inst/cards/tags.yml, plus
# "Question: <tag>" for every entry of inst/cards/questions.yml; and the
# glossary of terms cards define (inst/cards/terms.yml).
card_vocabulary <- function(root) {
  facets <- yaml::read_yaml(file.path(root, "inst", "cards", "tags.yml"))
  questions <- yaml::read_yaml(file.path(
    root,
    "inst",
    "cards",
    "questions.yml"
  ))
  terms_path <- file.path(root, "inst", "cards", "terms.yml")
  list(
    tags = unlist(lapply(names(facets), \(f) paste0(f, ": ", facets[[f]]))),
    questions = questions,
    question_tags = paste0("Question: ", vapply(questions, \(q) q$tag, "")),
    terms = if (file.exists(terms_path)) yaml::read_yaml(terms_path) else list()
  )
}

feature_ids <- function(root) {
  lines <- readLines(file.path(root, "product", "features.md"), warn = FALSE)
  sub("^### (F[0-9]+) .*", "\\1", grep("^### F[0-9]+ ", lines, value = TRUE))
}

# TRUE for each line that is a chunk fence or inside an R chunk.
chunk_lines <- function(lines) {
  open <- grepl("^\\s*```+\\s*\\{r", lines)
  close <- grepl("^\\s*```+\\s*$", lines)
  inside <- FALSE
  out <- logical(length(lines))
  for (i in seq_along(lines)) {
    if (!inside && open[i]) {
      inside <- TRUE
      out[i] <- TRUE
    } else if (inside) {
      out[i] <- TRUE
      if (close[i]) inside <- FALSE
    }
  }
  out
}

# Count kable()/knitr::kable() calls missing `arg`.
n_kable_without <- function(x, arg) {
  if (is.expression(x)) {
    return(sum(vapply(as.list(x), n_kable_without, integer(1), arg = arg)))
  }
  if (!is.call(x)) {
    return(0L)
  }
  fn <- x[[1]]
  is_kable <- identical(fn, as.name("kable")) ||
    (is.call(fn) &&
      identical(fn[[1]], as.name("::")) &&
      identical(fn[[3]], as.name("kable")))
  n <- as.integer(is_kable && !arg %in% names(as.list(x)))
  for (j in seq_along(x)[-1]) {
    if (!identical(x[[j]], quote(expr = ))) {
      n <- n + n_kable_without(x[[j]], arg)
    }
  }
  n
}

# String constants anywhere inside an expression (so paste("Top 10", y)
# yields "Top 10").
string_constants <- function(x) {
  if (is.character(x)) {
    return(x)
  }
  if (!is.call(x)) {
    return(character())
  }
  unlist(lapply(as.list(x)[-1], function(a) {
    if (identical(a, quote(expr = ))) character() else string_constants(a)
  }))
}

# The function a call names, without its `pkg::` prefix.
call_name <- function(x) {
  fn <- x[[1]]
  if (is.call(fn) && identical(fn[[1]], as.name("::"))) {
    fn <- fn[[3]]
  }
  if (is.name(fn)) as.character(fn) else ""
}

# The text a card's figures and tables show: titles and subtitles (from
# labs() and ggtitle()), every labs() label, and kable() col.names.
figure_text <- function(
  x,
  out = list(titles = character(), labels = character(), headers = character())
) {
  if (is.expression(x)) {
    for (e in as.list(x)) {
      out <- figure_text(e, out)
    }
    return(out)
  }
  if (!is.call(x)) {
    return(out)
  }
  args <- as.list(x)[-1]
  nms <- names(args) %||% rep("", length(args))
  fn <- call_name(x)
  if (fn == "labs") {
    label_args <- c(
      "x",
      "y",
      "title",
      "subtitle",
      "fill",
      "colour",
      "color",
      "caption",
      "size",
      "shape",
      "linetype",
      "alpha"
    )
    for (j in which(nms %in% label_args)) {
      txt <- string_constants(args[[j]])
      out$labels <- c(out$labels, txt)
      if (nms[j] %in% c("title", "subtitle")) {
        out$titles <- c(out$titles, txt)
      }
    }
  } else if (fn == "ggtitle") {
    first <- seq_along(args) == 1L & nms == ""
    for (j in which(nms %in% c("label", "subtitle") | first)) {
      txt <- string_constants(args[[j]])
      out$titles <- c(out$titles, txt)
      out$labels <- c(out$labels, txt)
    }
  } else if (fn == "kable" && "col.names" %in% nms) {
    out$headers <- c(
      out$headers,
      string_constants(args[[which(nms == "col.names")[1]]])
    )
  }
  for (a in args) {
    if (!identical(a, quote(expr = ))) {
      out <- figure_text(a, out)
    }
  }
  out
}

#' Check one figure card against the mechanical card rules
#'
#' Reads a `vignettes/card-<id>.qmd` and reports every rule it breaks: the
#' front matter (a question as the title, the thumbnail path for its id,
#' searchable alt text, a status, `graduated_to` once graduated), approved
#' and registered tags, glossary terms, follow-ups linked to a question or a feature, a
#' thumbnail that is present and fresh, an interactive figure, the release
#' date drawn in, data read from `cfb2nfl.duckdb`, figure text with no typed
#' numbers or column names, captioned tables with reader-facing headers, no
#' narrative prose, no redefined shared helper, and no em dashes or pie
#' charts. A newer data release than the thumbnail's is a `note`; everything
#' else is an `error`.
#'
#' @param path Path to a card `.qmd` file.
#' @param root The checkout root (registries, `R/`, thumbnails).
#' @param release The current data release date, or `NULL` to skip that check.
#' @param vocab,features,index Registries and parsed `R/` functions, built
#'   from `root` if not given (reused across cards by [check_cards_style()]).
#' @return A tibble with one row per violation: `file`, `line` (`NA` for
#'   whole-file rules), `rule`, `severity` and `message`.
#' @keywords internal
check_card_style <- function(
  path,
  root = card_root(),
  release = NULL,
  vocab = card_vocabulary(root),
  features = feature_ids(root),
  index = r_function_index(root)
) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  out <- list()
  flag <- function(rule, message, line = NA_integer_, severity = "error") {
    out[[length(out) + 1L]] <<- tibble::tibble(
      file = basename(path),
      line = as.integer(line),
      rule = rule,
      severity = severity,
      message = message
    )
  }
  id <- sub("^card-(.+)[.]qmd$", "\\1", basename(path))

  # ---- Front matter ----
  fm <- qmd_front_matter(lines)
  if (is.null(fm)) {
    flag("front_matter", "No YAML front matter at the top of the file.")
    return(dplyr::bind_rows(no_violations(), out))
  }
  meta <- fm$meta
  title <- meta$title %||% ""
  if (!grepl("[?]$", title)) {
    flag("title", "`title:` must be the card's question, ending in `?`.")
  }
  if (!identical(meta$image, paste0("card-thumbs/", id, ".png"))) {
    flag(
      "image",
      paste0(
        "`image:` must be `card-thumbs/",
        id,
        ".png` (the id is the file name)."
      )
    )
  }
  alt <- meta[["image-alt"]] %||% ""
  if (length(strsplit(trimws(alt), "\\s+")[[1]]) < 8L) {
    flag(
      "image_alt",
      "`image-alt:` must describe the figure in words (8 or more); search reads it."
    )
  }
  if (!isTRUE(meta$status %in% card_status_values)) {
    flag("status", "`status:` must be sketch, investigation or graduated.")
  }
  if (
    identical(meta$status, "graduated") && !nzchar(meta$graduated_to %||% "")
  ) {
    flag(
      "graduated_to",
      "A graduated card names where it went in `graduated_to:`."
    )
  }

  # ---- Tags and follow-ups ----
  tags <- unlist(meta$categories)
  q_tags <- grep("^Question: ", tags, value = TRUE)
  for (t in setdiff(q_tags, vocab$question_tags)) {
    flag(
      "question_tag",
      paste0("`", t, "` has no entry in inst/cards/questions.yml.")
    )
  }
  for (t in setdiff(setdiff(tags, q_tags), vocab$tags)) {
    flag(
      "tags",
      paste0("`", t, "` is not an approved tag (inst/cards/tags.yml).")
    )
  }
  for (t in setdiff(unlist(meta$terms), names(vocab$terms))) {
    flag(
      "terms",
      paste0("Term `", t, "` is not in the glossary (inst/cards/terms.yml).")
    )
  }
  for (f in meta$followups) {
    link <- f$link %||% ""
    ok <- link %in% vocab$question_tags || link %in% features
    if (!ok) {
      flag(
        "followup_link",
        paste0(
          "Follow-up \"",
          f$text %||% f,
          "\" must link to a registered `Question: <tag>` or a feature id."
        )
      )
    }
  }

  # ---- Code ----
  body <- seq_along(lines) >= fm$body_start
  in_chunk <- body & chunk_lines(lines)
  code_rows <- which(in_chunk & !grepl("^\\s*```", lines))
  code <- lines[code_rows]
  code_text <- paste(code, collapse = "\n")
  has_thumb <- grepl("card_thumbnail(", code_text, fixed = TRUE)
  if (!has_thumb) {
    flag(
      "no_figure",
      "A card saves its figure with `card_thumbnail()`; no card is only a table."
    )
  }
  if (!grepl("card_interactive(", code_text, fixed = TRUE)) {
    flag(
      "no_interactive",
      "Show the interactive figure with `card_interactive()`."
    )
  }
  if (!grepl("card_caption(", code_text, fixed = TRUE)) {
    flag(
      "release_date",
      "Draw the source and data release into the figure with `card_caption()`."
    )
  }
  if (!grepl("cfb2nfl.duckdb", code_text, fixed = TRUE)) {
    flag(
      "duckdb",
      "Read the data from `cfb2nfl.duckdb` in the visible setup code."
    )
  }
  if (has_thumb) {
    fresh <- card_freshness(
      path,
      id,
      dir = file.path(root, "vignettes", "card-thumbs"),
      release = release,
      index = index
    )
    msg <- switch(
      fresh$status,
      missing = "No thumbnail; render the card to save it.",
      stale_code = "The card's code changed since its thumbnail was saved; re-render it.",
      stale_r = paste0(
        "R functions changed since the thumbnail was saved (",
        and_join(fresh$changed),
        "); re-render it."
      ),
      stale_data = "A newer data release is out; re-render the card to update its thumbnail.",
      NULL
    )
    if (!is.null(msg)) {
      flag(
        "thumbnail",
        msg,
        severity = if (fresh$status == "stale_data") "note" else "error"
      )
    }
  }
  for (k in seq_along(code)) {
    i <- code_rows[k]
    helper_def <- paste0(
      "^\\s*(",
      paste(card_shared_helpers, collapse = "|"),
      ")\\s*(<-|=)\\s*function"
    )
    if (grepl(helper_def, code[k])) {
      flag(
        "helper_redefined",
        "This redefines a shared helper in R/; call it instead.",
        i
      )
    }
    if (grepl("coord_polar|\\bpie\\(", code[k])) {
      flag("pie_chart", "No pie charts; use ordered horizontal bars.", i)
    }
  }
  exprs <- tryCatch(parse(text = code, keep.source = FALSE), error = \(e) NULL)
  if (!is.null(exprs)) {
    if (n_kable_without(exprs, "caption") > 0L) {
      flag("kable_caption", "Every `kable()` needs a `caption`.")
    }
    if (n_kable_without(exprs, "col.names") > 0L) {
      flag(
        "column_name",
        "Give every `kable()` reader-facing headers with `col.names`."
      )
    }
    # Walk the parsed calls, so text built with paste() or ggtitle() and
    # kable() headers are read too.
    text <- figure_text(exprs)
    if (any(grepl("[0-9]", text$titles))) {
      flag(
        "numeric_title",
        "A number in a figure title or subtitle is typed in; compute it from the data."
      )
    }
    if (
      any(grepl(
        "\\b[a-z][a-z0-9]*_[a-z0-9_]+\\b",
        c(text$labels, text$headers)
      ))
    ) {
      flag(
        "column_name",
        "Figure or table text shows a column name; use a reader-facing label."
      )
    }
  }

  # ---- Text ----
  allowed <- grepl("^\\s*$|^#{1,6}\\s|^\\s*[-*+]\\s|^:::|^<!--", lines)
  for (i in which(body & !in_chunk & !allowed)) {
    flag(
      "prose",
      "Cards carry no narrative prose; move it into the figure, its caption or a table.",
      i
    )
  }
  for (i in grep("\u2014", lines, fixed = TRUE)) {
    flag("em_dash", "No em dashes.", i)
  }
  dplyr::bind_rows(no_violations(), out)
}

#' Check every figure card
#'
#' Runs [check_card_style()] over `vignettes/card-*.qmd`, and checks that no
#' card recorded in the migration ledger (`inst/cards/migration.yml`) was
#' renamed or deleted without an `aliases:` entry pointing its old page at a
#' card.
#'
#' @param root The checkout root.
#' @param release The current data release date, or `NULL`.
#' @return The bound violations tibble.
#' @keywords internal
check_cards_style <- function(root = card_root(), release = NULL) {
  cards <- list.files(
    file.path(root, "vignettes"),
    "^card-.*[.]qmd$",
    full.names = TRUE
  )
  vocab <- card_vocabulary(root)
  features <- feature_ids(root)
  index <- r_function_index(root)
  out <- lapply(
    cards,
    check_card_style,
    root = root,
    release = release,
    vocab = vocab,
    features = features,
    index = index
  )
  ledger_path <- file.path(root, "inst", "cards", "migration.yml")
  if (file.exists(ledger_path)) {
    published <- unique(unlist(lapply(yaml::read_yaml(ledger_path), \(e) {
      e$card
    })))
    ids <- sub("^card-(.+)[.]qmd$", "\\1", basename(cards))
    aliases <- unlist(lapply(cards, \(f) {
      qmd_front_matter(readLines(f, warn = FALSE))$meta$aliases
    }))
    for (p in setdiff(published, ids)) {
      if (!paste0("card-", p, ".html") %in% aliases) {
        out[[length(out) + 1L]] <- tibble::tibble(
          file = "migration.yml",
          line = NA_integer_,
          rule = "published_card",
          severity = "error",
          message = paste0(
            "Published card `",
            p,
            "` is gone; add `aliases: [card-",
            p,
            ".html]` to the card that replaced it."
          )
        )
      }
    }
  }
  dplyr::bind_rows(no_violations(), out)
}

#' Start a new figure card
#'
#' Copies `vignettes/_card-template.qmd` to `vignettes/card-<id>.qmd` with the
#' id filled in and `status: sketch`.
#'
#' @param id The card id: lowercase words joined by hyphens. It becomes the
#'   card's permanent URL, so choose it once.
#' @param question The card's question (its title).
#' @param root The checkout root.
#' @return The new card's path, invisibly.
#' @export
new_card <- function(
  id,
  question = "What does this figure ask?",
  root = card_root()
) {
  if (!grepl("^[a-z0-9]+(-[a-z0-9]+)*$", id)) {
    cli::cli_abort(
      "A card id is lowercase words joined by hyphens, not {.val {id}}."
    )
  }
  path <- file.path(root, "vignettes", paste0("card-", id, ".qmd"))
  if (file.exists(path)) {
    cli::cli_abort("{.path {path}} already exists.")
  }
  template <- readLines(
    file.path(root, "vignettes", "_card-template.qmd"),
    warn = FALSE
  )
  template <- gsub("{{id}}", id, template, fixed = TRUE)
  template <- gsub("{{question}}", question, template, fixed = TRUE)
  writeLines(template, path)
  cli::cli_alert_success("Created {.path {path}}.")
  invisible(path)
}

#' The footer of a card page
#'
#' Markdown for the bottom of a card: the data release it was rendered from,
#' the definitions of the terms it uses (`terms:`, from the glossary), the
#' status of each question it serves (with the reason when a question is
#' not answerable), its follow-ups linked to the question's cards on the
#' Investigations wall or to the feature that tracks them, and where the card
#' graduated to. Print it from an `output: asis` chunk with `cat()`.
#'
#' @param card Path to the card (defaults to the card being rendered).
#' @param root The checkout root.
#' @return One markdown string.
#' @export
card_footer <- function(card = card_source(root = root), root = card_root()) {
  meta <- qmd_front_matter(readLines(card, warn = FALSE))$meta
  vocab <- card_vocabulary(root)
  wall_link <- function(tag) {
    paste0(
      "investigations.html#category=",
      utils::URLencode(tag, reserved = TRUE)
    )
  }
  out <- paste0(
    "Data release ",
    format(data_release_date(file.path(root, "data")), "%Y-%m-%d"),
    "."
  )
  q_tags <- grep("^Question: ", unlist(meta$categories), value = TRUE)
  for (t in q_tags) {
    q <- vocab$questions[[match(t, vocab$question_tags)]]
    line <- paste0("- [", q$question, "](", wall_link(t), "): ", q$status)
    if (identical(q$status, "not answerable") && nzchar(q$reason %||% "")) {
      line <- paste0(line, ". ", q$reason)
    }
    out <- c(out, "", "**Question**", "", line)
  }
  terms <- vocab$terms[intersect(unlist(meta$terms), names(vocab$terms))]
  if (length(terms) > 0L) {
    defs <- vapply(
      terms,
      \(t) paste0("- **", t$label, ":** ", t$definition),
      ""
    )
    out <- c(out, "", "**Terms**", "", defs)
  }
  if (length(meta$followups) > 0L) {
    links <- vapply(
      meta$followups,
      function(f) {
        target <- if (startsWith(f$link, "Question: ")) {
          wall_link(f$link)
        } else {
          "https://github.com/ngiangre/cfb2nfl/blob/main/product/features.md"
        }
        paste0("- [", f$text, "](", target, ")")
      },
      ""
    )
    out <- c(out, "", "**Follow-ups**", "", links)
  }
  if (nzchar(meta$graduated_to %||% "")) {
    out <- c(
      out,
      "",
      paste0("Graduated to [", meta$graduated_to, "](", meta$graduated_to, ").")
    )
  }
  paste(out, collapse = "\n")
}
