# Goal -> feature -> task traceability (decision 0048). Tasks are GitHub
# issues that name their feature with a `Feature: Fnn` line; this file
# regenerates each feature card's task checklist in product/features.md and
# flags issues whose goal labels disagree with their feature's Goals line.

# Issue labels for each goal and constraint in product/goals.md.
goal_label_map <- c(
  G1 = "goal:G1",
  G2 = "goal:G2",
  G3 = "goal:G3",
  G4 = "goal:G4",
  C1 = "constraint:trust",
  C2 = "constraint:budget"
)

#' Feature ids named on `Feature:` lines
#'
#' A line counts when it starts with `Feature:` or `Features:` (any case),
#' so a passing mention ("see Feature F13") does not link an issue.
#'
#' @param text Character vector (issue bodies, comments); `NA` is ignored.
#' @return Sorted unique feature ids, e.g. `c("F04", "F21")`.
#' @keywords internal
feature_ids_in <- function(text) {
  lines <- unlist(strsplit(text[!is.na(text)], "\r?\n"))
  hits <- lines[grepl("^\\s*features?:", lines, ignore.case = TRUE)]
  ids <- unlist(regmatches(hits, gregexpr("\\bF[0-9]{2,}\\b", hits)))
  sort(unique(as.character(ids)))
}

#' Issue labels for a feature's Goals line
#'
#' @param goals A Goals value such as `"G1, C2"`.
#' @return The labels (`"goal:G1"`, `"constraint:budget"`, ...).
#' @keywords internal
goal_labels <- function(goals) {
  ids <- trimws(strsplit(goals, ",")[[1]])
  unknown <- setdiff(ids, names(goal_label_map))
  if (length(unknown) > 0L) {
    cli::cli_abort("Unknown goal or constraint: {.val {unknown}}.")
  }
  unname(goal_label_map[ids])
}

#' Each feature card's Goals line
#'
#' @param lines Lines of `product/features.md`.
#' @return A tibble with `feature` and `goals`, in card order.
#' @keywords internal
feature_goals <- function(lines) {
  heads <- grep("^### F[0-9]{2,} ", lines)
  feature <- regmatches(lines[heads], regexpr("F[0-9]{2,}", lines[heads]))
  goals <- vapply(
    seq_along(heads),
    function(i) {
      end <- if (i < length(heads)) heads[i + 1L] - 1L else length(lines)
      card <- lines[heads[i]:end]
      hit <- regmatches(
        card,
        regexec("\\*\\*Goals:\\*\\*\\s*([^\u00b7]+)", card)
      )
      hit <- Filter(length, hit)
      if (length(hit) == 0L) NA_character_ else trimws(hit[[1]][2])
    },
    character(1)
  )
  tibble::tibble(feature = feature, goals = goals)
}

#' One task checklist item
#'
#' @param number,title,url The issue's number, title and HTML URL.
#' @param closed Whether the issue is closed (ticks the box).
#' @param is_pr Whether it is a pull request rather than an issue.
#' @return Markdown checklist lines (vectorised over the arguments).
#' @keywords internal
task_line <- function(number, title, url, closed, is_pr) {
  sprintf(
    "- [%s] [%s#%s](%s) %s",
    ifelse(closed, "x", " "),
    ifelse(is_pr, "PR ", ""),
    number,
    url,
    title
  )
}

#' Replace every feature card's task block
#'
#' Blocks run from `<!-- tasks Fnn -->` to the next `<!-- /tasks -->`. A
#' feature with no tasks gets an empty block; text outside the markers is
#' left as is.
#'
#' @param lines Lines of `product/features.md`.
#' @param tasks Named list: feature id -> checklist lines.
#' @return The new lines.
#' @keywords internal
splice_tasks <- function(lines, tasks) {
  opens <- grep("^<!-- tasks F[0-9]{2,} -->$", lines)
  ids <- sub("^<!-- tasks (F[0-9]{2,}) -->$", "\\1", lines[opens])
  orphan <- setdiff(names(tasks), ids)
  if (length(orphan) > 0L) {
    cli::cli_abort("No task block in features.md for {.val {orphan}}.")
  }
  closes <- grep("^<!-- /tasks -->$", lines)
  out <- character()
  from <- 1L
  for (i in seq_along(opens)) {
    close <- closes[closes > opens[i]][1]
    out <- c(out, lines[from:opens[i]], tasks[[ids[i]]], lines[close])
    from <- close + 1L
  }
  if (from <= length(lines)) {
    out <- c(out, lines[from:length(lines)])
  }
  out
}

#' Regenerate feature task checklists from GitHub issues
#'
#' Reads every issue and pull request in `repo` (and their comments), links
#' each to the features named on its `Feature:` lines, rewrites the task
#' blocks in `path`, and warns about issues missing the goal labels of their
#' feature or naming a feature with no card. Uses the authenticated `gh` R
#' package (AGENTS.md "Git").
#'
#' @param path Path to `product/features.md`.
#' @param repo `owner/name` of the GitHub repository.
#' @param write Write the file (`FALSE` previews the result).
#' @return Invisibly, a tibble with one row per issue-feature link:
#'   `number`, `title`, `feature`, `closed`, `missing_labels`.
#' @keywords internal
sync_feature_tasks <- function(
  path = "product/features.md",
  repo = "ngiangre/cfb2nfl",
  write = TRUE
) {
  rlang::check_installed("gh")
  issues <- gh::gh(
    "GET /repos/{repo}/issues",
    repo = repo,
    state = "all",
    per_page = 100,
    .limit = Inf
  )
  comments <- gh::gh(
    "GET /repos/{repo}/issues/comments",
    repo = repo,
    per_page = 100,
    .limit = Inf
  )
  comment_issue <- as.integer(sub(
    ".*/",
    "",
    vapply(comments, \(x) x$issue_url, "")
  ))
  comment_body <- vapply(comments, \(x) x$body %||% "", "")

  links <- purrr::map(issues, function(x) {
    text <- c(x$body %||% "", comment_body[comment_issue == x$number])
    ids <- feature_ids_in(text)
    if (length(ids) == 0L) {
      return(NULL)
    }
    tibble::tibble(
      number = x$number,
      title = x$title,
      url = x$html_url,
      closed = identical(x$state, "closed"),
      is_pr = !is.null(x$pull_request),
      labels = list(vapply(x$labels, \(l) l$name, "")),
      feature = ids
    )
  })
  links <- dplyr::bind_rows(links)
  if (nrow(links) == 0L) {
    cli::cli_alert_warning("No issue carries a {.code Feature:} line.")
    return(invisible(links))
  }
  links <- dplyr::arrange(links, .data$feature, .data$number)

  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  goals <- feature_goals(lines)
  unknown <- setdiff(links$feature, goals$feature)
  if (length(unknown) > 0L) {
    cli::cli_alert_warning(
      "Issues name features with no card: {.val {unknown}} (skipped)."
    )
    links <- links[!links$feature %in% unknown, ]
  }

  want <- goals$goals[match(links$feature, goals$feature)]
  links$missing_labels <- purrr::map2_chr(
    want,
    links$labels,
    function(g, have) {
      paste(setdiff(goal_labels(g), have), collapse = ", ")
    }
  )
  for (i in which(nzchar(links$missing_labels))) {
    cli::cli_alert_warning(
      "#{links$number[i]} ({links$feature[i]}) lacks {links$missing_labels[i]}."
    )
  }

  tasks <- split(
    task_line(
      links$number,
      links$title,
      links$url,
      links$closed,
      links$is_pr
    ),
    links$feature
  )
  new <- splice_tasks(lines, tasks)
  if (write) {
    writeLines(new, path, useBytes = TRUE)
    cli::cli_alert_success(
      "Synced {nrow(links)} task link{?s} across {length(tasks)} feature{?s}."
    )
  }
  invisible(links[c("number", "title", "feature", "closed", "missing_labels")])
}
