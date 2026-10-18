# Interactive ERD plumbing for the Shiny data browser: the join graph is
# parsed from inst/data-model.md so the diagram, querychat context, and
# dictionaries stay in sync from one source.

# Table -> visual group. Display only; mirrors the narrative grouping in
# inst/data-model.md (college stats / games / context / draft & NFL / audit).
erd_groups <- c(
  player_stats = "College stats",
  player_season_stats = "College stats",
  stat_taxonomy = "College stats",
  ps_change = "College stats",
  career_summary = "College stats",
  roster_flags = "College stats",
  game_player_stats = "College stats",
  games = "Games",
  game_team_stats = "Games",
  roster = "Context",
  coaches = "Context",
  recruiting = "Context",
  teams = "Context",
  conference_tiers = "Context",
  picks = "Draft & NFL",
  nfl_pick_link = "Draft & NFL",
  nfl_draft_picks = "Draft & NFL",
  nfl_rosters = "Draft & NFL",
  nfl_player_stats = "Draft & NFL",
  audit_log = "Audit"
)

erd_group_colors <- c(
  "College stats" = "#4C78A8",
  "Games" = "#72B7B2",
  "Context" = "#F58518",
  "Draft & NFL" = "#54A24B",
  "Audit" = "#999999",
  "Other" = "#B0B0B0"
)

#' Parse the mermaid erDiagram block from the data-model doc
#'
#' Extracts the entity-relationship graph as tidy nodes/edges data frames so
#' the app renders the same ERD the documentation describes.
#'
#' @param lines Character vector of the document's lines.
#' @return List with `nodes` (id, group) and `edges` (from, to, card, label,
#'   dashes) data frames.
#' Load a file bundled under `inst/`
#'
#' Delegates to `app_sys()`, which falls back to the project checkout when
#' `system.file()` comes back empty on a deployed bundle.
#' @noRd
erd_asset <- function(rel) {
  p <- app_sys(rel)
  if (!file.exists(p)) {
    stop(sprintf("packaged asset not found: %s", rel), call. = FALSE)
  }
  p
}

#' Parse the mermaid erDiagram block from the data-model doc
#'
#' Extracts the entity-relationship graph as tidy nodes/edges data frames so
#' the app renders the same ERD the documentation describes.
#'
#' @param lines Character vector of the document's lines.
#' @return List with `nodes` (id, group) and `edges` (from, to, card, label,
#'   dashes) data frames.
#' @noRd
parse_erd_mermaid <- function(lines) {
  rel <- grep('^\\s*\\w+\\s+\\S+\\s+\\w+\\s*:\\s*"', lines, value = TRUE)
  m <- regexec('^\\s*(\\w+)\\s+(\\S+)\\s+(\\w+)\\s*:\\s*"(.*)"\\s*$', rel)
  parts <- regmatches(rel, m)
  edges <- data.frame(
    from = vapply(parts, `[[`, character(1), 2),
    card = vapply(parts, `[[`, character(1), 3),
    to = vapply(parts, `[[`, character(1), 4),
    label = vapply(parts, `[[`, character(1), 5),
    # Mermaid's dotted cardinalities (|o..o|) mark name-guarded joins.
    dashes = vapply(parts, function(p) grepl("\\.\\.", p[[3]]), logical(1)),
    stringsAsFactors = FALSE
  )
  ids <- unique(c(edges$from, edges$to))
  nodes <- data.frame(
    id = ids,
    group = unname(erd_groups[ids]),
    stringsAsFactors = FALSE
  )
  nodes$group[is.na(nodes$group)] <- "Other"
  list(nodes = nodes, edges = edges)
}

#' Load every data dictionary
#'
#' Reads `inst/dict/*.yml` into a named list keyed by table name; each entry
#' carries `grain`, `key`, `description`, and per-column metadata used for
#' table-header tooltips.
#' @noRd
app_dict <- function(dict_dir = app_sys("dict")) {
  files <- list.files(dict_dir, "\\.yml$", full.names = TRUE)
  out <- lapply(files, yaml::read_yaml)
  names(out) <- tools::file_path_sans_ext(basename(files))
  out
}

# Edge color by join namespace, so the five documented key families are
# visually distinct (mirrors the "Join keys & namespaces" section of
# inst/data-model.md).
erd_edge_palette <- c(
  athlete_id = "#4C78A8",
  game_id = "#72B7B2",
  draft_slot = "#54A24B",
  gsis_id = "#2CA02C",
  team_season = "#F58518",
  conference_season = "#E45756",
  derived = "#B0B0B0",
  name_guarded = "#9467BD"
)

#' Classify an edge's join key into its namespace
#'
#' @param label The mermaid edge label (e.g. "playerId, season").
#' @param dashes TRUE when the link is name-guarded.
#' @return Named palette entry, or `derived` for intra-pipeline transforms.
#' @noRd
erd_key_namespace <- function(label, dashes) {
  if (dashes) {
    return("name_guarded")
  }
  l <- tolower(label)
  if (grepl("pivoted|collapsed", l)) {
    return("derived")
  }
  if (grepl("gsis_id", l)) {
    return("gsis_id")
  }
  if (grepl("slot", l)) {
    return("draft_slot")
  }
  if (grepl("gameid", l)) {
    return("game_id")
  }
  if (grepl("conference", l)) {
    return("conference_season")
  }
  if (grepl("team|school", l)) {
    return("team_season")
  }
  if (grepl("playerid", l)) {
    return("athlete_id")
  }
  "derived"
}

#' Build the visNetwork ERD widget
#'
#' Nodes are tables (tooltips show grain, key, and row count); edges are the
#' join relationships, dashed when name-guarded. Only tables present in the
#' database are rendered — the doc's graph can lead the bundle (e.g. the
#' games family before its first publish). The click JS reports the selected
#' node id to a (namespaced) Shiny input.
#' @noRd
erd_network <- function(
  dict,
  tables,
  click_input = "erd_click",
  n_rows = NULL
) {
  md <- readLines(erd_asset("data-model.md"))
  g <- parse_erd_mermaid(md)

  keep <- g$nodes$id %in% tables
  g$nodes <- g$nodes[keep, , drop = FALSE]
  g$edges <- g$edges[
    g$edges$from %in% g$nodes$id & g$edges$to %in% g$nodes$id,
    ,
    drop = FALSE
  ]

  if (nrow(g$nodes) == 0) {
    return(
      visNetwork::visNetwork(
        data.frame(id = character(0), label = character(0)),
        data.frame(from = character(0), to = character(0)),
        height = "700px",
        width = "100%"
      )
    )
  }

  title <- vapply(
    g$nodes$id,
    function(id) {
      d <- dict[[id]]
      grain <- if (!is.null(d$grain)) htmltools::htmlEscape(d$grain) else ""
      n <- if (!is.null(n_rows[[id]])) {
        sprintf("<br/>Rows: %s", format(n_rows[[id]], big.mark = ","))
      } else {
        ""
      }
      sprintf("<b>%s</b><br/><small>%s%s</small>", id, grain, n)
    },
    character(1)
  )

  nodes <- g$nodes
  nodes$label <- nodes$id
  nodes$title <- unname(title)
  nodes$color <- unname(erd_group_colors[nodes$group])
  nodes$font <- list(list(size = 16, face = "sans"))

  edges <- g$edges
  if (nrow(edges) > 0) {
    ns <- mapply(erd_key_namespace, edges$label, edges$dashes)
    edges$arrows <- "to"
    edges$smooth <- FALSE
    edges$color <- unname(erd_edge_palette[ns])
    edges$title <- sprintf(
      "<b>%s → %s</b><br/>Join key: %s%s",
      edges$from,
      edges$to,
      htmltools::htmlEscape(edges$label),
      ifelse(
        ns == "name_guarded",
        "<br/><i>Name-guarded, not a plain key join</i>",
        ""
      )
    )
    edges$font <- list(list(size = 13, color = "#333333", face = "sans"))
  }

  visNetwork::visNetwork(nodes, edges, height = "700px", width = "100%") |>
    visNetwork::visEdges(
      arrows = "to",
      smooth = FALSE
    ) |>
    visNetwork::visOptions(
      highlightNearest = list(enabled = TRUE, degree = 1, hover = TRUE),
      nodesIdSelection = FALSE
    ) |>
    visNetwork::visHierarchicalLayout(
      direction = "LR",
      levelSeparation = 300,
      nodeSpacing = 120,
      sortMethod = "hubsize"
    ) |>
    visNetwork::visEvents(
      click = htmlwidgets::JS(sprintf(
        'function(nodes) { var sel = nodes.nodes.filter(function(x) {
           return typeof x === "string"; });
           if (sel.length) Shiny.setInputValue("%s", sel[0], {priority: "event"});
         }',
        click_input
      ))
    )
}
